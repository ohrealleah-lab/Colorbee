import ColorbeeCore
import Foundation
@testable import Colorbee

/// A seeded random number generator, so every monkey episode can be replayed exactly.
struct MonkeyRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func int(_ range: Range<Int>) -> Int { Int.random(in: range, using: &self) }
    mutating func int(_ range: ClosedRange<Int>) -> Int { Int.random(in: range, using: &self) }
    mutating func chance(_ odds: Double) -> Bool { Double.random(in: 0..<1, using: &self) < odds }
    mutating func pick<T>(_ items: [T]) -> T { items[int(0..<items.count)] }
}

/// A rule the monkey found broken: which one, and what it saw.
struct MonkeyFailure: Error {
    let rule: String
    let detail: String
}

/// One small document and the steps done to it (stage 32). `run` does them and checks the rules after each step, and
/// at the end saves, reopens, and undoes and redoes everything.
@MainActor
struct MonkeyEpisode {
    let seed: UInt64
    let width: Int
    let height: Int
    let background: Pixel
    var steps: [MonkeyStep] = []

    /// A new episode: a small picture, with no steps yet.
    static func random(seed: UInt64) -> MonkeyEpisode {
        var random = MonkeyRandom(seed: seed)
        return MonkeyEpisode(seed: seed, width: random.int(24...140), height: random.int(24...100),
                             background: random.pick([.white, Pixel(r: 200, g: 200, b: 200), Pixel(r: 30, g: 40, b: 60)]))
    }

    var start: String { "A new \(width) × \(height) picture, background \(String(format: "#%02X%02X%02X", background.r, background.g, background.b))." }

    func makeEditor() -> Editor {
        let editor = Colorbee.Editor(canvas: Canvas(size: IntSize(width: width, height: height), colorSpace: Canvas.defaultColorSpace, background: background))
        // Settings that are saved for real are set here directly, never through the controls that save them.
        editor.textIsEditable = false
        editor.smoothing = 0
        return editor
    }

    /// Chooses `count` random steps as it goes, from what the document has, checking the rules after each. On a broken
    /// rule, `steps` holds the steps up to it.
    mutating func explore(count: Int) throws(MonkeyFailureAt) {
        var random = MonkeyRandom(seed: seed &* 31 &+ 7)
        var chosen: [MonkeyStep] = []
        defer { steps = chosen }
        try Self.drive(makeEditor(), finishing: true) { editor in
            guard chosen.count < count else { return nil }
            let step = MonkeyGenerator.step(&random, editor: editor)
            chosen.append(step)
            return step
        }
    }

    /// Does the steps again, as they were, checking the rules after each.
    func run() throws(MonkeyFailureAt) {
        var next = steps.makeIterator()
        try Self.drive(makeEditor(), finishing: true) { _ in next.next() }
    }

    private static func drive(_ editor: Editor, finishing: Bool, next: (Editor) -> MonkeyStep?) throws(MonkeyFailureAt) {
        var tracker = UndoTracker(editor: editor)
        var done = 0
        while let step = next(editor) {
            let before = (revision: editor.history.revision, undoCount: editor.history.undoCount)
            step.perform(on: editor)
            done += 1
            do {
                try MonkeyRules.checkDocument(editor)
                try tracker.note(step, before: before)
            } catch {
                throw MonkeyFailureAt(failure: error, steps: done)
            }
        }
        guard finishing else { return }
        do {
            try MonkeyRules.checkSaving(editor)
            try tracker.undoAndRedoEverything()
        } catch {
            throw MonkeyFailureAt(failure: error, steps: done, atEnd: true)
        }
    }
}

/// A broken rule, how many steps it took, and whether it showed in the checks at the end.
struct MonkeyFailureAt: Error {
    let failure: MonkeyFailure
    let steps: Int
    var atEnd = false
}

/// What the picture looked like at each place in history, so undo and redo can be checked against it.
@MainActor
struct UndoTracker {
    let editor: Editor
    /// The picture at each undo count along the current line of history.
    private var line: [Int]

    init(editor: Editor) {
        self.editor = editor
        line = [editor.imageHash]
    }

    /// After a step: undo and redo must give back exactly what was there; a step that changed the picture must be in
    /// history; anything else starts a new line from here.
    mutating func note(_ step: MonkeyStep, before: (revision: Int, undoCount: Int)) throws(MonkeyFailure) {
        let history = editor.history, count = history.undoCount, hash = editor.imageHash
        switch step {
        case .undo, .redo:
            guard count != before.undoCount else { break }
            guard line.indices.contains(count) else {
                throw MonkeyFailure(rule: "\(step) went somewhere history never was", detail: "Undo count \(count), but only \(line.count - 1) steps were recorded.")
            }
            guard line[count] == Int.min || line[count] == hash else {
                throw MonkeyFailure(rule: "\(step) didn't give back the exact picture", detail: "After \(step), the picture differs from how it was at that point in history.")
            }
            return
        default:
            break
        }
        if history.revision == before.revision {
            // Nothing recorded, so nothing in the picture may have changed.
            guard line.indices.contains(count), line[count] == Int.min || line[count] == hash else {
                throw MonkeyFailure(rule: "The picture changed without an undo step", detail: "\(step) changed the picture, but History recorded nothing, so Undo can't take it back.")
            }
            return
        }
        if case .undoOnActiveLayer = step {
            // It took one older step out of history: the pictures between it and now can't be checked any more, but
            // undoing everything still goes back to the start.
            line = [line[0]] + Array(repeating: Int.min, count: max(0, count - 1)) + [hash]
        } else {
            line = Array(line.prefix(count)) + Array(repeating: Int.min, count: max(0, count - line.count)) + [hash]
        }
    }

    /// At the end: undo all the way back, checking each picture, then redo all the way, likewise.
    func undoAndRedoEverything() throws(MonkeyFailure) {
        let history = editor.history
        let end = history.undoCount
        var guardSteps = 0
        while history.undoCount > 0, guardSteps < 10_000 {
            let count = history.undoCount
            editor.undo()
            guardSteps += 1
            guard history.undoCount < count else {
                throw MonkeyFailure(rule: "Undo stopped working", detail: "Undo did nothing with \(count) steps still in History.")
            }
            let now = history.undoCount
            if line.indices.contains(now), line[now] != Int.min, line[now] != editor.imageHash {
                throw MonkeyFailure(rule: "Undoing everything didn't give back each picture", detail: "Undoing back to step \(now) gave a different picture than step \(now) had.")
            }
        }
        while history.undoCount < end, guardSteps < 20_000 {
            let count = history.undoCount
            editor.redo()
            guardSteps += 1
            guard history.undoCount > count else {
                throw MonkeyFailure(rule: "Redo stopped working", detail: "Redo did nothing at step \(count) of \(end).")
            }
            let now = history.undoCount
            if line.indices.contains(now), line[now] != Int.min, line[now] != editor.imageHash {
                throw MonkeyFailure(rule: "Redoing everything didn't give back each picture", detail: "Redoing to step \(now) gave a different picture than step \(now) had.")
            }
        }
    }
}
