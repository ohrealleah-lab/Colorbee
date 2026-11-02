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

    /// Every other episode's history gets a tiny budget, so it spills to disk and frees layers as a long session's
    /// would (monkey gaps, R6).
    var tinyHistory: Bool { seed % 2 == 0 }

    var start: String {
        "A new \(width) × \(height) picture, background \(String(format: "#%02X%02X%02X", background.r, background.g, background.b))"
            + (tinyHistory ? ", with a tiny history budget." : ".")
    }

    func makeEditor() -> Editor {
        let canvas = Canvas(size: IntSize(width: width, height: height), colorSpace: Canvas.defaultColorSpace, background: background)
        return Self.settled(Editor(pages: PageStack(pages: [Page(canvas: canvas, history: Editor.makeHistory())])))
    }

    /// Settings that are saved for real are set here directly, never through the controls that save them.
    private static func settled(_ editor: Editor) -> Editor {
        editor.textIsEditable = false
        editor.smoothing = 0
        return editor
    }

    /// The project saved and opened again, as `ImageDocument` reads one: the page shown is unparked, the rest wait.
    private static func reopened(_ data: Data) throws(MonkeyFailure) -> Editor {
        do {
            let (stored, current) = try ProjectFile.storedPages(data)
            let pages = try stored.map { try Page(stored: $0, history: Editor.makeHistory()) }
            try pages[current].unpark()
            return settled(Editor(pages: PageStack(pages: pages, currentIndex: current)))
        } catch {
            throw MonkeyFailure(rule: "Saving or reopening a project failed", detail: "\(error)")
        }
    }

    /// One page of a saved project, opened on its own for checking.
    private static func page(_ index: Int, of data: Data) throws(MonkeyFailure) -> Canvas {
        do {
            let (stored, _) = try ProjectFile.storedPages(data)
            let page = try Page(stored: stored[index], history: History(byteBudget: .max))
            try page.unpark()
            return page.canvas
        } catch {
            throw MonkeyFailure(rule: "Saving or reopening a project failed", detail: "\(error)")
        }
    }

    private static func project(_ editor: Editor) throws(MonkeyFailure) -> Data {
        do {
            return try editor.encodedProject()
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
        try await withBudget {
            try await Self.drive(makeEditor(), finishing: true) { editor in
                guard chosen.count < count else { return nil }
                let step = MonkeyGenerator.step(&random, editor: editor)
                chosen.append(step)
                return step
            }
        }
    }

    /// Does the steps again, as they were, checking the rules after each.
    func run() async throws(MonkeyFailureAt) {
        var next = steps.makeIterator()
        try await withBudget {
            try await Self.drive(makeEditor(), finishing: true) { _ in next.next() }
        }
    }

    private func withBudget(_ body: () async throws -> Void) async throws(MonkeyFailureAt) {
        do {
            try await HistoryBudget.$forTests.withValue(tinyHistory ? 256 << 10 : nil) { try await body() }
        } catch let failure as MonkeyFailureAt {
            throw failure
        } catch {
            throw MonkeyFailureAt(failure: MonkeyFailure(rule: "The monkey itself failed", detail: "\(error)"), steps: 0)
        }
    }

    /// A save taken in the background while editing goes on (monkey gaps, R5): what it must hold, and when to check.
    private struct BackgroundSave {
        let snapshot: SaveSnapshot
        let look: Int
        let layers: [String]
        let floatingOn: LayerID?
        let pages: Int
        let due: Int
    }

    private static func drive(_ start: Editor, finishing: Bool, next: (Editor) -> MonkeyStep?) async throws(MonkeyFailureAt) {
        var editor = start
        var tracker = UndoTracker(editor: editor)
        var done = 0
        // Pages left while nothing floated, as they were, to compare when they're shown again (monkey gaps, R2).
        var leftPages: [(page: Page, layers: [String])] = []
        // Each text layer's words, so a redaction can be checked for leaving them anywhere (monkey gaps, R1).
        var words: [LayerID: String] = [:]
        var pendingSave: BackgroundSave?

        func checkPendingSave(force: Bool) async throws(MonkeyFailure) {
            guard let save = pendingSave, force || done >= save.due else { return }
            pendingSave = nil
            let snapshot = save.snapshot
            let data: Data
            do {
                data = try await Task.detached { try snapshot.encodedProject() }.value
            } catch {
                throw MonkeyFailure(rule: "Saving in the background failed", detail: "\(error)")
            }
            let (stored, current) = (try? ProjectFile.storedPages(data)) ?? ([], 0)
            guard stored.count == save.pages else {
                throw MonkeyFailure(rule: "A background save kept the wrong pages", detail: "\(stored.count) pages, not \(save.pages).")
            }
            let canvas = try page(current, of: data)
            let floatingOn = save.layers.isEmpty ? nil : save.floatingOn
            let layers = MonkeyRules.layerStates(of: canvas, floatingOn: floatingOn)
            guard layers == save.layers else {
                throw MonkeyFailure(rule: "A background save didn't keep the picture as it was",
                                    detail: "Editing went on while it saved, and in the saved page " + UndoTracker.difference(save.layers, layers))
            }
            guard MonkeyRules.shownHash(canvas.flattened()) == save.look else {
                throw MonkeyFailure(rule: "A background save didn't keep the picture as it was",
                                    detail: "Editing went on while it saved, and the saved page looks different.")
            }
        }

        while let step = next(editor) {
            let before = (revision: editor.history.revision, undoCount: editor.history.undoCount,
                          selection: MonkeyRules.selectionState(of: editor.canvas))
            let canvas = editor.canvas, shownPage = editor.page
            let leaving = canvas.selection.floating == nil ? MonkeyRules.layerStates(of: canvas, floatingOn: nil) : nil
            let hashes = step.redacts ? Dictionary(uniqueKeysWithValues: canvas.layers.map { ($0.id, $0.buffer.contentHash()) }) : [:]
            // Whether this step really redacted: a redaction that finds nothing, or places a floating piece first, isn't one.
            let redactedBefore = editor.redactedSinceSave
            if step.redacts { editor.redactedSinceSave = false }
            await step.perform(on: editor)
            let redacted = step.redacts && editor.redactedSinceSave
            if step.redacts { editor.redactedSinceSave = editor.redactedSinceSave || redactedBefore }
            done += 1
            do {
                switch step {
                case .saveAndReopen:
                    // Carry on in the reopened copy, which must hold what was saved (the save places what's open), every
                    // page of it.
                    editor.placePendingObjects()
                    let data = try project(editor)
                    let copy = try reopened(data)
                    try MonkeyRules.checkSame(editor.canvas, copy.canvas, pages: (editor.pages.pages.count, copy.pages.pages.count))
                    for (index, page) in editor.pages.pages.enumerated() where page !== editor.page {
                        guard let left = leftPages.first(where: { $0.page === page }) else { continue }
                        let saved = try Self.page(index, of: data)
                        guard MonkeyRules.layerStates(of: saved, floatingOn: nil) == left.layers else {
                            throw MonkeyFailure(rule: "A saved project reopens with a page changed", detail: "Page \(index + 1) came back different.")
                        }
                    }
                    leftPages = []
                    editor = copy
                    tracker.restart(on: editor, pagesTouched: true)
                    try await checkPendingSave(force: false)
                    continue
                case .saveInBackground:
                    let snapshot = editor.saveSnapshot()
                    pendingSave = BackgroundSave(snapshot: snapshot, look: MonkeyRules.shownHash(editor.canvas.flattened()),
                                                 layers: MonkeyRules.layerStates(of: editor.canvas, floatingOn: editor.canvas.selection.floating?.layerID),
                                                 floatingOn: editor.canvas.selection.floating?.layerID, pages: editor.pages.pages.count, due: done + 3)
                case .forgetHistory:
                    try MonkeyRules.checkForgotten(editor, before: leaving)
                    tracker.restart(on: editor, pagesTouched: false)
                    try MonkeyRules.checkDocument(editor)
                    try await checkPendingSave(force: false)
                    continue
                case .autoRedact:
                    // It changes every page.
                    leftPages = []
                default:
                    break
                }
                try MonkeyRules.checkDocument(editor)
                if redacted, editor.canvas === canvas {
                    try MonkeyRules.checkRedacted(editor)
                    // Placing a floating piece first changes its layer too, so which layers the redaction itself touched
                    // can't be told then.
                    let changed = leaving == nil ? [] : editor.canvas.layers.filter { layer in hashes[layer.id].map { $0 != layer.buffer.contentHash() } ?? false }
                    try MonkeyRules.checkNothingLeft(editor, redacted: changed, words: words)
                }
                if editor.page !== shownPage {
                    // Another page is shown: the one left must be as it was when it's shown again, and this one as it was
                    // left.
                    if let leaving {
                        leftPages.removeAll { $0.page === shownPage }
                        leftPages.append((shownPage, leaving))
                    }
                    if let index = leftPages.firstIndex(where: { $0.page === editor.page }) {
                        let left = leftPages.remove(at: index)
                        let now = MonkeyRules.layerStates(of: editor.canvas, floatingOn: nil)
                        guard left.layers == now else {
                            throw MonkeyFailure(rule: "A page changed while it wasn't shown", detail: UndoTracker.difference(left.layers, now))
                        }
                    }
                    tracker.restart(on: editor, pagesTouched: true)
                } else {
                    try tracker.note(step, before: before)
                }
                for layer in editor.canvas.layers { if let text = layer.text { words[layer.id] = text.spec.text } }
                try await checkPendingSave(force: false)
            } catch {
                throw MonkeyFailureAt(failure: error as? MonkeyFailure ?? MonkeyFailure(rule: "The monkey itself failed", detail: "\(error)"), steps: done)
            }
        }
        guard finishing else { return }
        do {
            try await checkPendingSave(force: true)
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
    /// One place in history: the layers (with the size first), the selection right after its step, and right before the
    /// next one (drawing a marquee isn't a step, so it can change in between; monkey gaps, R3).
    struct Mark: Equatable {
        var layers: [String]
        var after: String
        var before: String
    }

    private(set) var editor: Editor
    /// Pages were added, switched or reopened: undo can then cross pages, so the end only checks that it works.
    private var pagesTouched = false
    /// Each undo count along the current line of history; nil where it can't be known.
    private var line: [Mark?]
    /// Whether the line covers all redo can reach. After a restart (another page, a reopen) it doesn't know the steps
    /// redo still holds, until a new step clears them.
    private var knowsRedo = true

    init(editor: Editor) {
        self.editor = editor
        line = [Self.mark(editor)]
    }

    private static func mark(_ editor: Editor) -> Mark {
        let selection = MonkeyRules.selectionState(of: editor.canvas)
        return Mark(layers: editor.documentState, after: selection, before: selection)
    }

    /// After a step: undo and redo must give back exactly what was there, selection and floating piece included; a step
    /// that changed the layers must be in history; anything else starts a new line from here.
    mutating func note(_ step: MonkeyStep, before: (revision: Int, undoCount: Int, selection: String)) throws(MonkeyFailure) {
        let history = editor.history, count = history.undoCount, now = Self.mark(editor)
        switch step {
        case .undo, .redo:
            guard count != before.undoCount else { break }
            guard line.indices.contains(count) else {
                guard knowsRedo else {
                    line += Array(repeating: nil, count: count - line.count) + [nil]
                    return
                }
                throw MonkeyFailure(rule: "\(step) went somewhere history never was", detail: "Undo count \(count), but only \(line.count - 1) steps were recorded.")
            }
            if let want = line[count] {
                if want.layers != now.layers {
                    throw MonkeyFailure(rule: "\(step) didn't give back the exact picture", detail: Self.difference(want.layers, now.layers))
                }
                // A floating piece's pixels live only in the selection, so it must come back exactly. A marquee outline
                // kept after placing isn't recorded (drawing one isn't a step), so outlines aren't compared.
                let selection = { if case .undo = step { want.before } else { want.after } }()
                let floats = selection.hasPrefix("a floating") || now.after.hasPrefix("a floating")
                if floats, selection != now.after {
                    throw MonkeyFailure(rule: "\(step) didn't give back the selection", detail: "It should be \(selection), but it's \(now.after).")
                }
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
            // Nothing recorded, so the layers must be as they were. The selection may change (drawing a marquee isn't a
            // step).
            if line.indices.contains(count), let want = line[count] {
                if want.layers != now.layers {
                    throw MonkeyFailure(rule: "The picture changed without an undo step",
                                        detail: "\(step) changed it, but History recorded nothing, so Undo can't take it back. " + Self.difference(want.layers, now.layers))
                }
            }
            return
        }
        // A new step began from the selection there was just before it: that's what undoing it gives back.
        if count > before.undoCount, line.indices.contains(before.undoCount) {
            line[before.undoCount]?.before = before.selection
        }
        knowsRedo = true
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
        line = Array(repeating: nil, count: editor.history.undoCount) + [Self.mark(editor)]
        knowsRedo = false
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
            if line.indices.contains(now), let want = line[now], want.layers != editor.documentState {
                throw MonkeyFailure(rule: "Undoing everything didn't give back each picture",
                                    detail: "Undoing \(name), back to step \(now): " + Self.difference(want.layers, editor.documentState))
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
            if line.indices.contains(now), let want = line[now], want.layers != editor.documentState {
                throw MonkeyFailure(rule: "Redoing everything didn't give back each picture",
                                    detail: "Redoing \(name), to step \(now): " + Self.difference(want.layers, editor.documentState))
            }
        }
    }

    private func undoAndRedoAcrossPages() throws(MonkeyFailure) {
        for redoing in [false, true] {
            for _ in 0..<10_000 {
                guard let name = redoing ? editor.redoActionName : editor.undoActionName else { break }
                let canvas = editor.canvas, count = editor.history.undoCount, order = editor.pages.pages.map(ObjectIdentifier.init)
                if redoing { editor.redo() } else { editor.undo() }
                // Two page changes in a row can share a name, and undoing one may leave the page shown as it was.
                guard editor.canvas !== canvas || editor.history.undoCount != count || editor.pages.pages.map(ObjectIdentifier.init) != order
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
    var documentState: [String] { MonkeyRules.layerStates(of: canvas, floatingOn: nil) }
}
