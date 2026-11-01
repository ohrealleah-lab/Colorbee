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
        Self.settled(Colorbee.Editor(canvas: Canvas(size: IntSize(width: width, height: height), colorSpace: Canvas.defaultColorSpace, background: background)))
    }

    /// Settings that are saved for real are set here directly, never through the controls that save them.
    private static func settled(_ editor: Editor) -> Editor {
        editor.textIsEditable = false
        editor.smoothing = 0
        return editor
    }

    /// The project saved and opened again, as `ImageDocument` reads one: the page shown is unparked, the rest wait.
    private static func reopened(_ editor: Editor) throws(MonkeyFailure) -> Editor {
        do {
            let (stored, current) = try ProjectFile.storedPages(try editor.encodedProject())
            let pages = try stored.map { try Page(stored: $0, history: Editor.makeHistory()) }
            try pages[current].unpark()
            return settled(Editor(pages: PageStack(pages: pages, currentIndex: current)))
        } catch {
            throw MonkeyFailure(rule: "Saving or reopening a project failed", detail: "\(error)")
        }
    }

    /// Chooses `count` random steps as it goes, from what the document has, checking the rules after each. On a broken
    /// rule, `steps` holds the steps up to it.
    mutating func explore(count: Int) async throws(MonkeyFailureAt) {
        var random = MonkeyRandom(seed: seed &* 31 &+ 7)
        var chosen: [MonkeyStep] = []
        defer { steps = chosen }
        try await Self.drive(makeEditor(), finishing: true) { editor in
            guard chosen.count < count else { return nil }
            let step = MonkeyGenerator.step(&random, editor: editor)
            chosen.append(step)
            return step
        }
    }

    /// Does the steps again, as they were, checking the rules after each.
    func run() async throws(MonkeyFailureAt) {
        var next = steps.makeIterator()
        try await Self.drive(makeEditor(), finishing: true) { _ in next.next() }
    }

    private static func drive(_ start: Editor, finishing: Bool, next: (Editor) -> MonkeyStep?) async throws(MonkeyFailureAt) {
        var editor = start
        var tracker = UndoTracker(editor: editor)
        var done = 0
        while let step = next(editor) {
            let before = (revision: editor.history.revision, undoCount: editor.history.undoCount)
            let canvas = editor.canvas
            await step.perform(on: editor)
            done += 1
            do {
                if case .saveAndReopen = step {
                    // Carry on in the reopened copy, which must hold what was saved (the save places what's open).
                    editor.placePendingObjects()
                    let copy = try reopened(editor)
                    try MonkeyRules.checkSame(editor.canvas, copy.canvas, pages: (editor.pages.pages.count, copy.pages.pages.count))
                    editor = copy
                    tracker.restart(on: editor, pagesTouched: true)
                    continue
                }
                try MonkeyRules.checkDocument(editor)
                if step.redacts, editor.canvas === canvas, editor.history.revision != before.revision {
                    try MonkeyRules.checkRedacted(editor)
                }
                if editor.canvas !== canvas {
                    // Another page is shown: its own history, so the line starts again there.
                    tracker.restart(on: editor, pagesTouched: true)
                } else {
                    try tracker.note(step, before: before)
                }
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

/// What the document held at each place in history, so undo and redo can be checked against it.
@MainActor
struct UndoTracker {
    private(set) var editor: Editor
    /// Pages were added, switched or reopened: undo can then cross pages, so the end only checks that it works.
    private var pagesTouched = false
    /// The document at each undo count along the current line of history; nil where it can't be known.
    private var line: [[String]?]

    init(editor: Editor) {
        self.editor = editor
        line = [editor.documentState]
    }

    /// After a step: undo and redo must give back exactly what was there; a step that changed the document must be in
    /// history; anything else starts a new line from here.
    mutating func note(_ step: MonkeyStep, before: (revision: Int, undoCount: Int)) throws(MonkeyFailure) {
        let history = editor.history, count = history.undoCount, now = editor.documentState
        switch step {
        case .undo, .redo:
            guard count != before.undoCount else { break }
            guard line.indices.contains(count) else {
                throw MonkeyFailure(rule: "\(step) went somewhere history never was", detail: "Undo count \(count), but only \(line.count - 1) steps were recorded.")
            }
            if let want = line[count], want != now {
                throw MonkeyFailure(rule: "\(step) didn't give back the exact picture", detail: Self.difference(want, now))
            }
            return
        default:
            break
        }
        // Placing a floating piece is folded into the step that made it (`commit(_:mergingIntoPrevious:)`), so that
        // step's picture changed too, when this step also added one of its own.
        if history.revision - before.revision > max(1, count - before.undoCount), line.indices.contains(before.undoCount), before.undoCount > 0 {
            line[before.undoCount] = nil
        }
        if history.revision == before.revision {
            // Nothing recorded, so nothing in the document may have changed.
            if line.indices.contains(count), let want = line[count], want != now {
                throw MonkeyFailure(rule: "The picture changed without an undo step",
                                    detail: "\(step) changed it, but History recorded nothing, so Undo can't take it back. " + Self.difference(want, now))
            }
            return
        }
        if case .undoOnActiveLayer = step {
            // It took one older step out of history, leaving its change in the steps before: none of them can be checked.
            line = Array(repeating: nil, count: count) + [now]
        } else if count > before.undoCount + 1 {
            // One action, several steps (a paste can place what floated first): the ones in between weren't seen.
            line = Array(line.prefix(before.undoCount + 1)) + Array(repeating: nil, count: count - before.undoCount - 1) + [now]
        } else {
            line = Array(line.prefix(count)) + Array(repeating: nil, count: max(0, count - line.count)) + [now]
        }
    }

    /// Starts again on `editor`'s shown page, as nothing on it can be checked against what came before.
    mutating func restart(on editor: Editor, pagesTouched: Bool) {
        self.editor = editor
        self.pagesTouched = self.pagesTouched || pagesTouched
        line = Array(repeating: nil, count: editor.history.undoCount) + [editor.documentState]
    }

    /// At the end: undo all the way back, checking each picture, then redo all the way, likewise. Across pages, only
    /// that every undo and redo does something.
    func undoAndRedoEverything() throws(MonkeyFailure) {
        if pagesTouched { return try undoAndRedoAcrossPages() }
        let history = editor.history
        let end = history.undoCount
        var guardSteps = 0
        while history.undoCount > 0, guardSteps < 10_000 {
            let count = history.undoCount, name = history.undoActionName ?? "a step"
            editor.undo()
            guardSteps += 1
            guard history.undoCount < count else {
                throw MonkeyFailure(rule: "Undo stopped working", detail: "Undo did nothing with \(count) steps still in History.")
            }
            let now = history.undoCount
            if line.indices.contains(now), let want = line[now], want != editor.documentState {
                throw MonkeyFailure(rule: "Undoing everything didn't give back each picture",
                                    detail: "Undoing \(name), back to step \(now): " + Self.difference(want, editor.documentState))
            }
        }
        while history.undoCount < end, guardSteps < 20_000 {
            let count = history.undoCount, name = history.redoActionName ?? "a step"
            editor.redo()
            guardSteps += 1
            guard history.undoCount > count else {
                throw MonkeyFailure(rule: "Redo stopped working", detail: "Redo did nothing at step \(count) of \(end).")
            }
            let now = history.undoCount
            if line.indices.contains(now), let want = line[now], want != editor.documentState {
                throw MonkeyFailure(rule: "Redoing everything didn't give back each picture",
                                    detail: "Redoing \(name), to step \(now): " + Self.difference(want, editor.documentState))
            }
        }
    }

    private func undoAndRedoAcrossPages() throws(MonkeyFailure) {
        for redoing in [false, true] {
            for _ in 0..<10_000 {
                guard let name = redoing ? editor.redoActionName : editor.undoActionName else { break }
                let canvas = editor.canvas, count = editor.history.undoCount
                if redoing { editor.redo() } else { editor.undo() }
                guard editor.canvas !== canvas || editor.history.undoCount != count
                        || (redoing ? editor.redoActionName : editor.undoActionName) != name else {
                    throw MonkeyFailure(rule: "\(redoing ? "Redo" : "Undo") stopped working", detail: "\(name) did nothing, across pages.")
                }
                try MonkeyRules.checkDocument(editor)
            }
        }
    }

    /// What differs, in words: the size, the layers, or the first layer that changed and how.
    static func difference(_ want: [String], _ got: [String]) -> String {
        guard want.first == got.first else { return "the picture's size is \(got.first ?? "?"), not \(want.first ?? "?")." }
        guard want.count == got.count else { return "\(got.count - 1) layers instead of \(want.count - 1)." }
        guard let index = want.indices.first(where: { want[$0] != got[$0] }) else { return "nothing differs." }
        let fields = ["name", "shown", "opacity", "blend mode", "lock", "transparency lock", "Only the layer below", "Pass Through",
                      "group", "adjustment", "text", "mask on", "pixels", "mask pixels", "id"]
        let a = want[index].components(separatedBy: "|"), b = got[index].components(separatedBy: "|")
        let changed = zip(fields, zip(a, b)).filter { $0.1.0 != $0.1.1 }.map(\.0)
        return "layer \(index) (\"\(b.first ?? "")\") differs in its \(changed.joined(separator: ", "))."
    }
}

extension Editor {
    /// Everything undo and saving must keep, hidden or not (review Z, finding 2): the picture's size, then each layer's
    /// settings, pixels and mask.
    var documentState: [String] {
        ["\(canvas.size.width) × \(canvas.size.height)"] + canvas.layers.map { MonkeyRules.state(of: $0, pixels: true) + "|\($0.id.rawValue)" }
    }
}
