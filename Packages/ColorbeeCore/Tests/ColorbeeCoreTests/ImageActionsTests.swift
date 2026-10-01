import Testing
@testable import ColorbeeCore

struct ImageActionsTests {
    private let red = Pixel(r: 255, g: 0, b: 0)
    private let context = SelectionContext(color2: .white)

    private func makeCanvas() -> (Canvas, History) {
        let canvas = Canvas(size: IntSize(width: 300, height: 200), colorSpace: Canvas.defaultColorSpace, background: .white)
        canvas.activeLayer.buffer.fill(red, in: IntRect(x: 100, y: 50, width: 20, height: 20))
        return (canvas, History(byteBudget: .max))
    }

    @Test func cropKeepsOnlyTheRect() {
        let (canvas, history) = makeCanvas()
        #expect(ImageActions.crop(to: IntRect(x: 90, y: 40, width: 50, height: 40), canvas: canvas, history: history, context: context))
        #expect(canvas.size == IntSize(width: 50, height: 40))
        #expect(canvas.activeLayer.buffer.size == canvas.size)
        #expect(canvas.activeLayer.buffer[10, 10] == red)
        #expect(canvas.activeLayer.buffer[0, 0] == .white)
        #expect(history.undoActionName == "Crop")
    }

    @Test func cropUndoesAndRedoes() {
        let (canvas, history) = makeCanvas()
        let original = canvas.activeLayer.buffer.contentHash()
        ImageActions.crop(to: IntRect(x: 90, y: 40, width: 50, height: 40), canvas: canvas, history: history, context: context)
        let cropped = canvas.activeLayer.buffer.contentHash()

        history.undo(on: canvas)
        #expect(canvas.size == IntSize(width: 300, height: 200))
        #expect(canvas.activeLayer.buffer.contentHash() == original)

        history.redo(on: canvas)
        #expect(canvas.size == IntSize(width: 50, height: 40))
        #expect(canvas.activeLayer.buffer.contentHash() == cropped)
    }

    @Test func cropToSelectionPlacesFloatingAndDeselects() {
        let (canvas, history) = makeCanvas()
        let mask = SelectionMask.rectangle(IntRect(x: 100, y: 50, width: 20, height: 20), clippedTo: canvas.bounds)
        SelectionActions.select(mask, mode: .replace, canvas: canvas, history: history, context: context)
        SelectionActions.nudge(dx: 5, dy: 0, canvas: canvas, history: history, context: context)

        #expect(ImageActions.cropToSelection(canvas: canvas, history: history, context: context))
        #expect(canvas.size == IntSize(width: 20, height: 20))
        #expect(canvas.selection.isEmpty)
        #expect(canvas.activeLayer.buffer[10, 10] == red)
    }

    @Test func cropWithNothingToRemoveDoesNothing() {
        let (canvas, history) = makeCanvas()
        #expect(!ImageActions.crop(to: IntRect(x: -10, y: -10, width: 400, height: 400), canvas: canvas, history: history, context: context))
        #expect(!history.canUndo)
    }

    @Test func spilledCropsStillUndo() {
        let canvas = Canvas(size: IntSize(width: 200, height: 200), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: 50 * 50 * 4)
        canvas.activeLayer.buffer.fill(red, in: IntRect(x: 0, y: 0, width: 10, height: 10))
        let original = canvas.activeLayer.buffer.contentHash()
        for size in [180, 160, 140, 120] {
            ImageActions.crop(to: IntRect(x: 0, y: 0, width: size, height: size), canvas: canvas, history: history, context: context)
        }
        #expect(history.spilledEntryCount > 0)

        while history.canUndo { history.undo(on: canvas) }
        #expect(canvas.size == IntSize(width: 200, height: 200))
        #expect(canvas.activeLayer.buffer.contentHash() == original)
    }

    @Test func paintEditsAroundACropUndoInOrder() {
        let (canvas, history) = makeCanvas()
        let original = canvas.activeLayer.buffer.contentHash()
        let before = history.beginEdit("Fill", on: canvas)
        before.willModify(IntRect(x: 0, y: 0, width: 300, height: 10), in: canvas.activeLayer)
        canvas.activeLayer.buffer.fill(.black, in: IntRect(x: 0, y: 0, width: 300, height: 10))
        history.commit(before)

        ImageActions.crop(to: IntRect(x: 0, y: 0, width: 150, height: 100), canvas: canvas, history: history, context: context)
        let after = history.beginEdit("Fill", on: canvas)
        after.willModify(canvas.bounds, in: canvas.activeLayer)
        canvas.activeLayer.buffer.fill(red)
        history.commit(after)

        while history.canUndo { history.undo(on: canvas) }
        #expect(canvas.activeLayer.buffer.contentHash() == original)
    }
}
