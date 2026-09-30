import Darwin
import Foundation
import os
import Synchronization

enum Diagnostics {
    static let logger = Logger(subsystem: "com.leah.Colorbee", category: "performance")
    static let signposter = OSSignposter(subsystem: "com.leah.Colorbee", category: .pointsOfInterest)

    @MainActor private static var hasReportedColdStart = false

    /// Logs a line to the unified log and to stderr, so benchmark runs can capture it.
    static func report(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    @MainActor
    static func reportColdStartIfNeeded() {
        guard !hasReportedColdStart, let start = processStartDate() else { return }
        hasReportedColdStart = true
        report(String(format: "Cold start: %.0f ms (process start to first frame on screen)", Date().timeIntervalSince(start) * 1000))
    }

    static func processStartDate() -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000)
    }

    /// The same "memory" figure Activity Monitor shows.
    static func physicalFootprint() -> UInt64? {
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? usage.ri_phys_footprint : nil
    }

    static func megabytes(_ bytes: UInt64?) -> String {
        guard let bytes else { return "unknown" }
        return String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }
}

/// Input-to-present latencies, recorded from Metal's presentation callbacks on any thread.
final class LatencyStats: Sendable {
    private let samples = Mutex<[Double]>([])

    func record(_ seconds: Double) {
        samples.withLock { $0.append(seconds) }
    }

    func drain() -> [Double] {
        samples.withLock { samples in
            defer { samples.removeAll() }
            return samples
        }
    }

    static func summary(_ samples: [Double]) -> String {
        guard !samples.isEmpty else { return "no frames" }
        let sorted = samples.sorted()
        func percentile(_ p: Double) -> Double {
            sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * p))] * 1000
        }
        let over16 = sorted.filter { $0 > 0.016 }.count
        return String(
            format: "%d frames · p50 %.1f ms · p95 %.1f ms · max %.1f ms · over 16 ms: %d",
            sorted.count, percentile(0.5), percentile(0.95), percentile(1), over16
        )
    }
}
