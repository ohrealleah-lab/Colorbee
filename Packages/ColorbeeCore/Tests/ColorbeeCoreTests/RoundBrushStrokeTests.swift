import Testing
@testable import ColorbeeCore

struct RoundBrushStrokeTests {
    private func makeCanvas(width: Int = 32, height: Int = 32) -> (Canvas, History) {
        let canvas = Canvas(size: IntSize(width: width, height: height), colorSpace: Canvas.defaultColorSpace, background: .white)
        return (canvas, History(byteBudget: .max))
    }

    @Test func dabPaintsTheCenterAndLeavesDistantPixels() {
        let (canvas, history) = makeCanvas()
        let edit = history.beginEdit("Brush", on: canvas)
        let stroke = RoundBrushStroke(diameter: 9, color: .black, layer: canvas.activeLayer, edit: edit)

        stroke.move(to: Point2D(x: 16, y: 16))

        #expect(canvas.activeLayer.buffer[16, 16] == .black)
        #expect(canvas.activeLayer.buffer[0, 0] == .white)
        #expect(stroke.dirtyRect.contains(IntPoint(x: 16, y: 16)))
    }

    @Test func edgePixelsAreAntiAliased() {
        let (canvas, history) = makeCanvas()
        let edit = history.beginEdit("Brush", on: canvas)
        RoundBrushStroke(diameter: 10, color: .black, layer: canvas.activeLayer, edit: edit)
            .move(to: Point2D(x: 16, y: 16))

        let edge = canvas.activeLayer.buffer[20, 17]
        #expect(edge.r > 0 && edge.r < 255)
    }

    @Test func overlappingDabsDoNotDarkenATranslucentStroke() {
        let (canvas, history) = makeCanvas()
        let translucent = Pixel(r: 0, g: 0, b: 0, a: 128)
        let edit = history.beginEdit("Brush", on: canvas)
        let stroke = RoundBrushStroke(diameter: 9, color: translucent, layer: canvas.activeLayer, edit: edit)

        stroke.move(to: Point2D(x: 10, y: 16))
        stroke.move(to: Point2D(x: 22, y: 16))
        stroke.move(to: Point2D(x: 10, y: 16))

        #expect(canvas.activeLayer.buffer[16, 16] == Compositing.over(.white, translucent))
    }

    @Test func strokeUndoesAsOneStep() {
        let (canvas, history) = makeCanvas(width: 600, height: 300)
        let original = canvas.activeLayer.buffer.contentHash()
        let edit = history.beginEdit("Brush", on: canvas)
        let stroke = RoundBrushStroke(diameter: 20, color: .black, layer: canvas.activeLayer, edit: edit)
        stroke.move(to: Point2D(x: 10, y: 10))
        stroke.move(to: Point2D(x: 590, y: 290))

        #expect(history.commit(edit))
        #expect(history.undoCount == 1)
        history.undo(on: canvas)
        #expect(canvas.activeLayer.buffer.contentHash() == original)
    }

    @Test func fullyTransparentColorRecordsNothing() {
        let (canvas, history) = makeCanvas()
        let edit = history.beginEdit("Brush", on: canvas)
        RoundBrushStroke(diameter: 9, color: .clear, layer: canvas.activeLayer, edit: edit)
            .move(to: Point2D(x: 16, y: 16))
        #expect(!history.commit(edit))
    }
}
