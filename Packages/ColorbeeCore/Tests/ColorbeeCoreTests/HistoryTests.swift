import Testing
@testable import ColorbeeCore

struct HistoryTests {
    private let red = Pixel(r: 255, g: 0, b: 0)

    private func fill(_ rect: IntRect, with color: Pixel, on canvas: Canvas, history: History) {
        let edit = history.beginEdit("Fill", on: canvas)
        edit.willModify(rect, in: canvas.activeLayer)
        canvas.activeLayer.buffer.fill(color, in: rect)
        history.commit(edit)
    }

    @Test func undoRestoresAndRedoReapplies() {
        let canvas = Canvas(size: IntSize(width: 300, height: 300), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: .max)
        let before = canvas.activeLayer.buffer.contentHash()

        fill(IntRect(x: 200, y: 200, width: 90, height: 90), with: red, on: canvas, history: history)
        let after = canvas.activeLayer.buffer.contentHash()
        #expect(history.undoActionName == "Fill")

        history.undo(on: canvas)
        #expect(canvas.activeLayer.buffer.contentHash() == before)
        #expect(history.redoActionName == "Fill")

        history.redo(on: canvas)
        #expect(canvas.activeLayer.buffer.contentHash() == after)
    }

    @Test func newEditClearsRedo() {
        let canvas = Canvas(size: IntSize(width: 16, height: 16), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: .max)
        fill(IntRect(x: 0, y: 0, width: 4, height: 4), with: red, on: canvas, history: history)
        history.undo(on: canvas)
        #expect(history.canRedo)

        fill(IntRect(x: 8, y: 8, width: 4, height: 4), with: .black, on: canvas, history: history)
        #expect(!history.canRedo)
    }

    @Test func unchangedEditIsNotRecorded() {
        let canvas = Canvas(size: IntSize(width: 16, height: 16), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: .max)
        fill(IntRect(x: 0, y: 0, width: 4, height: 4), with: .white, on: canvas, history: history)
        #expect(!history.canUndo)
    }

    @Test func stepsOverTheMemoryBudgetSpillToDiskAndStillUndo() {
        let canvas = Canvas(size: IntSize(width: 64, height: 64), colorSpace: Canvas.defaultColorSpace, background: .white)
        let entryBytes = 64 * 64 * 4
        let history = History(byteBudget: entryBytes * 2)
        let original = canvas.activeLayer.buffer.contentHash()
        for index in 0..<6 {
            fill(canvas.bounds, with: Pixel(r: UInt8(index * 40), g: 0, b: 0), on: canvas, history: history)
        }
        let final = canvas.activeLayer.buffer.contentHash()

        #expect(history.undoCount == 6)
        #expect(history.spilledEntryCount > 0)
        #expect(history.byteCount <= history.byteBudget)

        while history.canUndo { history.undo(on: canvas) }
        #expect(canvas.activeLayer.buffer.contentHash() == original)
        #expect(history.byteCount <= history.byteBudget)

        while history.canRedo { history.redo(on: canvas) }
        #expect(canvas.activeLayer.buffer.contentHash() == final)
    }

    @Test func undoRestoresTheSelection() {
        let canvas = Canvas(size: IntSize(width: 32, height: 32), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: .max)
        let mask = SelectionMask.rectangle(IntRect(x: 0, y: 0, width: 8, height: 8), clippedTo: canvas.bounds)!
        canvas.selection = .marquee(mask)
        fill(IntRect(x: 20, y: 20, width: 4, height: 4), with: red, on: canvas, history: history)
        canvas.selection = .none

        history.undo(on: canvas)
        #expect(canvas.selection.marquee?.revision == mask.revision)
    }

    @Test func selectionOnlyChangesAreRecordedOnlyWhenAsked() {
        let canvas = Canvas(size: IntSize(width: 16, height: 16), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: .max)
        let quiet = history.beginEdit("Select", on: canvas)
        canvas.selection = .marquee(SelectionMask.rectangle(canvas.bounds, clippedTo: canvas.bounds)!)
        #expect(!history.commit(quiet))

        let recorded = history.beginEdit("Deselect", on: canvas)
        recorded.recordsSelectionChange = true
        canvas.selection = .none
        #expect(history.commit(recorded))
    }

    @Test func randomEditsUndoBackToTheOriginal() {
        var random = SplitMix64(seed: 0xC010_4BEE)
        let canvas = Canvas(size: IntSize(width: 600, height: 400), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: .max)
        let original = canvas.activeLayer.buffer.contentHash()

        for _ in 0..<40 {
            let color = Pixel(r: random.byte(), g: random.byte(), b: random.byte(), a: random.byte())
            if random.next() % 2 == 0 {
                let rect = IntRect(x: random.int(0..<600), y: random.int(0..<400), width: random.int(1..<300), height: random.int(1..<300))
                fill(rect, with: color, on: canvas, history: history)
            } else {
                let edit = history.beginEdit("Brush", on: canvas)
                let stroke = RoundBrushStroke(diameter: Double(random.int(1..<60)), color: color, layer: canvas.activeLayer, edit: edit)
                for _ in 0..<5 {
                    stroke.move(to: Point2D(x: Double(random.int(-50..<650)), y: Double(random.int(-50..<450))))
                }
                history.commit(edit)
            }
        }
        let final = canvas.activeLayer.buffer.contentHash()

        while history.canUndo { history.undo(on: canvas) }
        #expect(canvas.activeLayer.buffer.contentHash() == original)

        while history.canRedo { history.redo(on: canvas) }
        #expect(canvas.activeLayer.buffer.contentHash() == final)
    }
}

struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func byte() -> UInt8 { UInt8(truncatingIfNeeded: next()) }
    mutating func int(_ range: Range<Int>) -> Int { Int.random(in: range, using: &self) }
}
