import ColorbeeCore
import Foundation
import Testing
@testable import Colorbee

/// The overnight monkey test (stage 32; Leah, 2026-10-29): thousands of random, legal edits to small documents, with
/// the rules checked after each. `make monkey` runs it for 8 hours (`MINUTES=30 make monkey` for less) and writes a
/// report of every different rule broken, each shrunk to the fewest steps that still break it. It keeps going after a
/// failure, up to 20 different ones (Q32.2), and checks no speeds (Q32.3).
@MainActor
struct MonkeyTests {
    nonisolated private static let environment = ProcessInfo.processInfo.environment
    /// Set only by `make monkey`, so `make test` skips the long run.
    nonisolated private static let minutes = environment["COLORBEE_MONKEY_MINUTES"].flatMap(Double.init)
    static let stepsPerEpisode = 60
    static let maxFailures = 20

    /// A few short episodes on every `make test`, so the monkey itself keeps working and today's code breaks no rule.
    @Test func aShortRunBreaksNoRules() async {
        for seed in UInt64(1)...4 {
            var episode = MonkeyEpisode.random(seed: seed)
            do {
                try await episode.explore(count: 40)
            } catch {
                let (shrunk, failure) = await Self.shrink(episode, failure: error)
                Issue.record(Comment(rawValue: Self.describe(shrunk, failure: failure)))
            }
        }
    }

    @Test(.enabled(if: minutes != nil, "Run with make monkey")) func overnight() async {
        let started = Date()
        let deadline = started.addingTimeInterval((Self.minutes ?? 0) * 60)
        let baseSeed = Self.environment["COLORBEE_MONKEY_SEED"].flatMap(UInt64.init) ?? UInt64(started.timeIntervalSince1970)
        let episodeLimit = Self.environment["COLORBEE_MONKEY_EPISODES"].flatMap(Int.init) ?? .max
        let folder = URL(fileURLWithPath: Self.environment["COLORBEE_MONKEY_REPORT"] ?? FileManager.default.temporaryDirectory.path)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let inProgress = folder.appendingPathComponent("Monkey In Progress.txt")
        var found: [(key: String, count: Int, text: String)] = []
        var episodes = 0, steps = 0

        while Date() < deadline, episodes < episodeLimit, found.count < Self.maxFailures {
            let seed = baseSeed &+ UInt64(episodes)
            // If Colorbee itself crashes, this says which episode to replay.
            try? "Episode seed \(seed) was running. Replay it with: make monkey SEED=\(seed) EPISODES=1\n".write(to: inProgress, atomically: true, encoding: .utf8)
            var episode = MonkeyEpisode.random(seed: seed)
            do {
                try await episode.explore(count: Self.stepsPerEpisode)
            } catch {
                let key = error.failure.rule + " · " + (episode.steps.prefix(error.steps).last?.kind ?? "")
                if let index = found.firstIndex(where: { $0.key == key }) {
                    found[index].count += 1
                } else {
                    let (shrunk, failure) = await Self.shrink(episode, failure: error)
                    found.append((key, 1, Self.describe(shrunk, failure: failure)))
                    Self.writeReport(found: found, episodes: episodes + 1, steps: steps + episode.steps.count, started: started, finished: nil, to: folder)
                }
            }
            episodes += 1
            steps += episode.steps.count
            // Lets the app's own queued work run between episodes.
            try? await Task.sleep(for: .milliseconds(2))
        }
        try? FileManager.default.removeItem(at: inProgress)
        let report = Self.writeReport(found: found, episodes: episodes, steps: steps, started: started, finished: Date(), to: folder)
        print("Monkey report: \(report.path)")
    }

    /// The fewest steps that still break the same rule: everything after the failure goes, then each step that isn't
    /// needed, one at a time from the end.
    static func shrink(_ episode: MonkeyEpisode, failure: MonkeyFailureAt, tries: Int = 150) async -> (MonkeyEpisode, MonkeyFailureAt) {
        var best = episode
        best.steps = Array(episode.steps.prefix(failure.steps))
        var bestFailure = failure
        var index = best.steps.count - 1
        var attempts = 0
        while index >= 0, attempts < tries {
            var candidate = best
            candidate.steps.remove(at: index)
            attempts += 1
            do {
                try await candidate.run()
            } catch where error.failure.rule == failure.failure.rule {
                best = candidate
                best.steps = Array(candidate.steps.prefix(error.steps))
                bestFailure = error
            } catch {}
            index = min(index - 1, best.steps.count - 1)
        }
        return (best, bestFailure)
    }

    static func describe(_ episode: MonkeyEpisode, failure: MonkeyFailureAt) -> String {
        var text = "**\(failure.failure.rule).** \(failure.failure.detail)\n\n"
        text += "Seed \(episode.seed). \(episode.start)\n\n"
        for (index, step) in episode.steps.enumerated() {
            text += "\(index + 1). \(step)\n"
        }
        if failure.atEnd {
            text += "\(episode.steps.count + 1). (At the end: save and reopen, then undo and redo everything.)\n"
        }
        return text
    }

    @discardableResult
    static func writeReport(found: [(key: String, count: Int, text: String)], episodes: Int, steps: Int, started: Date, finished: Date?,
                            to folder: URL) -> URL {
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd HHmm"
        let file = folder.appendingPathComponent("Monkey Report \(stamp.string(from: started)).md")
        let time = DateFormatter()
        time.dateStyle = .medium
        time.timeStyle = .short
        var text = "# Colorbee monkey test\n\n"
        text += "Started \(time.string(from: started))"
        if let finished {
            let minutes = Int(finished.timeIntervalSince(started) / 60)
            text += ", finished \(time.string(from: finished)) (\(minutes / 60) h \(minutes % 60) min)"
        } else {
            text += ", still running"
        }
        text += ". \(episodes) small pictures, \(steps) steps.\n\n"
        if found.isEmpty {
            text += "No rule was broken.\n"
        } else {
            text += "\(found.count) different rule\(found.count == 1 ? "" : "s") broken. Each is shrunk to the fewest steps that still break it.\n"
            for (number, failure) in found.enumerated() {
                text += "\n## \(number + 1). Seen \(failure.count) time\(failure.count == 1 ? "" : "s")\n\n\(failure.text)"
            }
        }
        try? text.write(to: file, atomically: true, encoding: .utf8)
        return file
    }
}
