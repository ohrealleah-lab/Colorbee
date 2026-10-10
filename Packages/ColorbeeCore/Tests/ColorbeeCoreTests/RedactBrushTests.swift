import Testing
@testable import ColorbeeCore

/// The Redact Brush (FR-9.6): the area a stroke covers, redacted through Batch Redact.
struct RedactBrushTests {
    private let red = Pixel(r: 255, g: 0, b: 0, a: 110)
    private let bounds = IntRect(x: 0, y: 0, width: 600, height: 400)
    private let context = SelectionContext(color2: .white)

    @Test func aClickCoversARoundDot() throws {
        let area = RedactBrushArea(diameter: 10, canvasBounds: bounds, overlayColor: red)
        area.move(to: Point2D(x: 50, y: 50))
        let mask = try #require(area.mask)
        #expect(mask[50, 50] == 255 && mask[45, 50] == 255 && mask[54, 50] == 255)
        // Outside the circle, though inside its box.
        #expect(mask[45, 45] == 0)
        #expect(mask.bounds == IntRect(x: 45, y: 45, width: 10, height: 10))
    }

    /// The whole band between points is covered, however far apart they are, with no gaps.
    @Test func aStrokeCoversEverythingAlongItsPath() throws {
        let area = RedactBrushArea(diameter: 8, canvasBounds: bounds, overlayColor: red)
        area.move(to: Point2D(x: 20, y: 30))
        area.move(to: Point2D(x: 520, y: 30))
        let mask = try #require(area.mask)
        #expect((20..<520).allSatisfy { mask[$0, 30] == 255 && mask[$0, 27] == 255 && mask[$0, 33] == 255 })
        #expect(mask[300, 36] == 0 && mask[300, 23] == 0)
    }

    /// The picture grows with the stroke and keeps what it already covered.
    @Test func growingKeepsWhatWasCovered() throws {
        let area = RedactBrushArea(diameter: 6, canvasBounds: bounds, overlayColor: red)
        area.move(to: Point2D(x: 10, y: 10))
        area.move(to: Point2D(x: 590, y: 390))
        let picture = try #require(area.picture)
        #expect(picture.pixels[10 - picture.origin.x, 10 - picture.origin.y] == red)
        #expect(picture.pixels[300 - picture.origin.x, 200 - picture.origin.y] == red)
        #expect(area.mask?[10, 10] == 255)
    }

    @Test func offTheCanvasCoversNothing() {
        let area = RedactBrushArea(diameter: 6, canvasBounds: bounds, overlayColor: red)
        area.move(to: Point2D(x: -50, y: -50))
        #expect(area.mask == nil)
    }

    /// Like Batch Redact: every layer with pixels under the stroke, as one step, and a locked one stops it.
    @Test func redactingTheAreaChangesEveryLayerUnderItOrNone() throws {
        let canvas = Canvas(size: IntSize(width: 600, height: 400), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: .max)
        LayerActions.add(canvas: canvas, history: history, context: context)
        canvas.activeLayer.buffer.fill(Pixel(r: 0, g: 0, b: 200), in: IntRect(x: 0, y: 0, width: 600, height: 60))
        let area = RedactBrushArea(diameter: 20, canvasBounds: canvas.bounds, overlayColor: red)
        area.move(to: Point2D(x: 100, y: 30))
        area.move(to: Point2D(x: 300, y: 30))
        let mask = try #require(area.mask)

        canvas.layers[1].isLocked = true
        #expect(AutoRedact.apply(.solidFill(.black), in: mask, named: "Redact Brush", canvas: canvas, history: history) == .locked(layerName: canvas.layers[1].name))
        #expect(canvas.layers[1].buffer[200, 30] == Pixel(r: 0, g: 0, b: 200))

        canvas.layers[1].isLocked = false
        let steps = history.undoCount
        #expect(AutoRedact.apply(.solidFill(.black), in: mask, named: "Redact Brush", canvas: canvas, history: history) == .redacted)
        #expect(history.undoCount == steps + 1 && history.undoActionName == "Redact Brush")
        #expect(canvas.layers[0].buffer[200, 30] == .black && canvas.layers[1].buffer[200, 30] == .black)
        #expect(canvas.layers[1].buffer[200, 50] == Pixel(r: 0, g: 0, b: 200))
    }
}
