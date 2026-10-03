import Dispatch

enum ParallelRows {
    /// Runs `body` over `range` split into bands of rows, on all cores. Each band is handed to one call,
    /// so per-band scratch memory is allocated once. Small ranges run on the calling thread.
    /// `body` must only write rows inside the band it's given; that's what makes sharing it across threads safe.
    static func forEach(_ range: Range<Int>, minimumRows: Int = 32, _ body: (Range<Int>) -> Void) {
        let bands = min(range.count / minimumRows, 64)
        guard bands > 1 else {
            if !range.isEmpty { body(range) }
            return
        }
        withoutActuallyEscaping(body) { body in
            let work = UnsafeSendable(body)
            DispatchQueue.concurrentPerform(iterations: bands) { band in
                let start = range.lowerBound + range.count * band / bands
                let end = range.lowerBound + range.count * (band + 1) / bands
                work.value(start..<end)
            }
        }
    }
}

extension ParallelRows {
    /// `transform` applied to 0..<count on all cores, in order. `transform` must not share mutable state.
    static func map<T>(_ count: Int, _ transform: (Int) -> T) -> [T] {
        guard count > 1 else { return (0..<count).map(transform) }
        let results = UnsafeMutableBufferPointer<T?>.allocate(capacity: count)
        results.initialize(repeating: nil)
        defer { results.deinitialize().deallocate() }
        withoutActuallyEscaping(transform) { transform in
            let work = UnsafeSendable(transform), output = UnsafeSendable(results)
            DispatchQueue.concurrentPerform(iterations: count) { index in
                output.value[index] = work.value(index)
            }
        }
        return results.map { $0! }
    }
}

private struct UnsafeSendable<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
