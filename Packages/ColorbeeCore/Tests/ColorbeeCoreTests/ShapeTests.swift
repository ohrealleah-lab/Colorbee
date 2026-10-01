import Testing
@testable import ColorbeeCore

struct ShapeTests {
    private let red = Pixel(r: 255, g: 0, b: 0)
    private let blue = Pixel(r: 0, g: 0, b: 255)
    private let canvasBounds = IntRect(x: 0, y: 0, width: 200, height: 200)

    private func draw(_ shape: ShapeSpec) -> Canvas {
        let canvas = Canvas(size: IntSize(width: 200, height: 200), colorSpace: Canvas.defaultColorSpace, background: .white)
        let edit = History(byteBudget: .max).beginEdit("Shape", on: canvas)
        if let rendered = ShapeRenderer.render(shape, colorSpace: canvas.colorSpace, clippedTo: canvas.bounds) {
            Compositing.draw(rendered.pixels, at: rendered.origin, onto: canvas.activeLayer, edit: edit)
        }
        return canvas
    }

    @Test func rectangleHasOutlineAndFill() {
        let shape = ShapeSpec(kind: .rectangle, start: Point2D(x: 20, y: 20), end: Point2D(x: 80, y: 60), lineWidth: 4, outline: red, fill: blue)
        let buffer = draw(shape).activeLayer.buffer
        #expect(buffer[21, 40] == red)
        #expect(buffer[50, 21] == red)
        #expect(buffer[50, 40] == blue)
        #expect(buffer[18, 40] == .white)
        #expect(buffer[82, 40] == .white)
    }

    @Test func noFillLeavesTheInsideAlone() {
        let shape = ShapeSpec(kind: .rectangle, start: Point2D(x: 20, y: 20), end: Point2D(x: 80, y: 60), lineWidth: 2, outline: red, fill: nil)
        #expect(draw(shape).activeLayer.buffer[50, 40] == .white)
    }

    @Test func ellipseLeavesTheCornersEmpty() {
        let shape = ShapeSpec(kind: .ellipse, start: Point2D(x: 20, y: 20), end: Point2D(x: 120, y: 120), lineWidth: 2, outline: nil, fill: blue)
        let buffer = draw(shape).activeLayer.buffer
        #expect(buffer[70, 70] == blue)
        #expect(buffer[23, 23] == .white)
    }

    @Test func lineCoversItsPath() {
        let shape = ShapeSpec(kind: .line, start: Point2D(x: 10, y: 100), end: Point2D(x: 190, y: 100), lineWidth: 5, outline: red, fill: blue)
        let buffer = draw(shape).activeLayer.buffer
        #expect(buffer[100, 100] == red)
        #expect(buffer[100, 90] == .white)
    }

    @Test func arrowHasAHeadAtTheEnd() {
        let shape = ShapeSpec(kind: .arrow, start: Point2D(x: 10, y: 100), end: Point2D(x: 150, y: 100), lineWidth: 3, outline: red, fill: nil)
        let buffer = draw(shape).activeLayer.buffer
        #expect(buffer[142, 102] == red)
        #expect(buffer[60, 102] == .white)
        #expect(buffer[60, 104] == .white)
        #expect(buffer[155, 100] == .white)
    }

    @Test func translucentColorsStayStraightAlpha() {
        let translucent = Pixel(r: 255, g: 0, b: 0, a: 128)
        let shape = ShapeSpec(kind: .rectangle, start: Point2D(x: 0, y: 0), end: Point2D(x: 50, y: 50), lineWidth: 1, outline: nil, fill: translucent)
        let rendered = ShapeRenderer.render(shape, colorSpace: Canvas.defaultColorSpace, clippedTo: canvasBounds)
        let pixel = rendered?.pixels[20, 20]
        #expect(pixel?.r == 255 && pixel?.a == 128)
    }

    @Test func constrainingMakesSquaresAndFortyFiveDegreeLines() {
        let box = ShapeSpec(kind: .rectangle, start: Point2D(x: 10, y: 10), end: Point2D(x: 50, y: 30), lineWidth: 1, outline: red, fill: nil).constrained()
        #expect(box.box.width == box.box.height)
        let line = ShapeSpec(kind: .line, start: Point2D(x: 0, y: 0), end: Point2D(x: 100, y: 10), lineWidth: 1, outline: red, fill: nil).constrained()
        #expect(abs(line.end.y) < 1e-9)
    }

    @Test func invisibleShapesRenderNothing() {
        let shape = ShapeSpec(kind: .line, start: Point2D(x: 0, y: 0), end: Point2D(x: 10, y: 10), lineWidth: 1, outline: nil, fill: blue)
        #expect(ShapeRenderer.render(shape, colorSpace: Canvas.defaultColorSpace, clippedTo: canvasBounds) == nil)
    }
}
