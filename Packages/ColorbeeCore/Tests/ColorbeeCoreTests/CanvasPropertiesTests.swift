import Testing
@testable import ColorbeeCore

struct CanvasPropertiesTests {
    private let red = Pixel(r: 255, g: 0, b: 0)
    private let blue = Pixel(r: 0, g: 0, b: 255)

    @Test func enlargingKeepsTheImageTopLeftAndFillsWithColor2() {
        let canvas = Canvas(size: IntSize(width: 4, height: 4), colorSpace: Canvas.defaultColorSpace, background: red)
        let history = History(byteBudget: .max)
        let context = SelectionContext(color2: blue)
        LayerActions.add(canvas: canvas, history: history, context: context)
        #expect(ImageActions.resizeCanvas(to: IntSize(width: 6, height: 5), canvas: canvas, history: history, context: context))
        #expect(canvas.size == IntSize(width: 6, height: 5))
        #expect(canvas.layers[0].buffer[1, 1] == red)
        #expect(canvas.layers[0].buffer[5, 4] == blue)
        // Layers above the background get transparent new area.
        #expect(canvas.layers[1].buffer[5, 4] == .clear)
        history.undo(on: canvas)
        #expect(canvas.size == IntSize(width: 4, height: 4))
    }

    @Test func shrinkingCropsFromTheBottomRight() {
        let canvas = Canvas(size: IntSize(width: 4, height: 4), colorSpace: Canvas.defaultColorSpace, background: .white)
        canvas.layers[0].buffer[0, 0] = red
        let history = History(byteBudget: .max)
        ImageActions.resizeCanvas(to: IntSize(width: 2, height: 3), canvas: canvas, history: history, context: SelectionContext(color2: blue))
        #expect(canvas.size == IntSize(width: 2, height: 3))
        #expect(canvas.layers[0].buffer[0, 0] == red)
    }

    @Test func aTransparentBackgroundLeavesTransparencyAndUndoes() {
        let canvas = Canvas(size: IntSize(width: 4, height: 4), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: .max)
        #expect(ImageActions.setTransparentBackground(true, canvas: canvas, history: history))
        #expect(canvas.vacatedFill(for: canvas.layers[0], color2: blue) == .clear)
        ImageActions.resizeCanvas(to: IntSize(width: 5, height: 4), canvas: canvas, history: history, context: SelectionContext(color2: blue))
        #expect(canvas.layers[0].buffer[4, 0] == .clear)
        history.undo(on: canvas)
        history.undo(on: canvas)
        #expect(!canvas.hasTransparentBackground)
        #expect(!ImageActions.setTransparentBackground(false, canvas: canvas, history: history))
    }

    @Test func historyListsStepsWithThumbnails() {
        let canvas = Canvas(size: IntSize(width: 40, height: 20), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: .max)
        history.makeThumbnail = { $0.thumbnail(maxSide: 10) }
        for name in ["One", "Two", "Three"] {
            let edit = history.beginEdit(name, on: canvas)
            edit.willModify(IntRect(x: 0, y: 0, width: 40, height: 20), in: canvas.layers[0])
            canvas.layers[0].buffer.fill(name == "Two" ? red : blue, in: canvas.bounds)
            history.commit(edit)
        }
        history.undo(on: canvas)
        let steps = history.steps
        #expect(steps.map(\.name) == ["One", "Two", "Three"])
        #expect(steps.map(\.isUndone) == [false, false, true])
        #expect(steps[1].thumbnail?.width == 10 && steps[1].thumbnail?.height == 5)
        #expect(steps[1].thumbnail?.pixels.first == red)
    }

    @Test func thumbnailsBlendLayersAndPointAdjustments() {
        let canvas = Canvas(size: IntSize(width: 8, height: 8), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: .max)
        LayerActions.addAdjustment(.invert, named: "Invert", canvas: canvas, history: history, context: SelectionContext(color2: .white))
        #expect(canvas.thumbnail(maxSide: 4).pixels.allSatisfy { $0 == .black })
    }
}
