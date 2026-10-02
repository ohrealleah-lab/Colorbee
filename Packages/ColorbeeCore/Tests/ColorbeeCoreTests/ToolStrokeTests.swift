import Testing
@testable import ColorbeeCore

struct ToolStrokeTests {
    private let red = Pixel(r: 255, g: 0, b: 0)
    private let blue = Pixel(r: 0, g: 0, b: 255)

    private func makeCanvas(width: Int = 40, height: Int = 40) -> (Canvas, History) {
        (Canvas(size: IntSize(width: width, height: height), colorSpace: Canvas.defaultColorSpace, background: .white),
         History(byteBudget: .max))
    }

    @Test func linePixelsIncludeBothEnds() {
        let pixels = Line.pixels(from: IntPoint(x: 0, y: 0), to: IntPoint(x: 5, y: 2))
        #expect(pixels.first == IntPoint(x: 0, y: 0))
        #expect(pixels.last == IntPoint(x: 5, y: 2))
        #expect(pixels.count == 6)
        #expect(Line.pixels(from: IntPoint(x: 3, y: 3), to: IntPoint(x: 3, y: 3)) == [IntPoint(x: 3, y: 3)])
    }

    @Test func pencilDrawsOneHardPixelWideLine() {
        let (canvas, history) = makeCanvas()
        let edit = history.beginEdit("Pencil", on: canvas)
        let stroke = PencilStroke(color: .black, layer: canvas.activeLayer, edit: edit)
        stroke.move(to: Point2D(x: 2.7, y: 10.2))
        stroke.move(to: Point2D(x: 20.1, y: 10.9))

        let buffer = canvas.activeLayer.buffer
        for x in 2...20 {
            #expect(buffer[x, 10] == .black, "x = \(x)")
        }
        #expect(buffer[10, 9] == .white)
        #expect(buffer[10, 11] == .white)
        #expect(buffer[21, 10] == .white)
    }

    @Test func translucentPencilDoesNotDarkenWhereItCrossesItself() {
        let (canvas, history) = makeCanvas()
        let translucent = Pixel(r: 0, g: 0, b: 0, a: 100)
        let edit = history.beginEdit("Pencil", on: canvas)
        let stroke = PencilStroke(color: translucent, layer: canvas.activeLayer, edit: edit)
        stroke.move(to: Point2D(x: 5, y: 5))
        stroke.move(to: Point2D(x: 15, y: 5))
        stroke.move(to: Point2D(x: 5, y: 5))
        #expect(canvas.activeLayer.buffer[10, 5] == Compositing.over(.white, translucent))
    }

    @Test func eraserReplacesASquareWithTheFill() {
        let (canvas, history) = makeCanvas()
        canvas.activeLayer.buffer.fill(red)
        let edit = history.beginEdit("Erase", on: canvas)
        EraserStroke(size: 4, effect: .replace(.white), layer: canvas.activeLayer, edit: edit)
            .move(to: Point2D(x: 20.5, y: 20.5))

        let buffer = canvas.activeLayer.buffer
        #expect(buffer[18, 18] == .white)
        #expect(buffer[21, 21] == .white)
        #expect(buffer[17, 20] == red)
        #expect(buffer[22, 20] == red)
    }

    @Test func colorEraserOnlyReplacesColor1() {
        let (canvas, history) = makeCanvas()
        canvas.activeLayer.buffer.fill(red, in: IntRect(x: 0, y: 0, width: 20, height: 40))
        canvas.activeLayer.buffer.fill(blue, in: IntRect(x: 20, y: 0, width: 20, height: 40))
        let edit = history.beginEdit("Color Erase", on: canvas)
        let stroke = EraserStroke(size: 10, effect: .replaceMatching(target: red, tolerance: 0, with: .white), layer: canvas.activeLayer, edit: edit)
        stroke.move(to: Point2D(x: 10, y: 20))
        stroke.move(to: Point2D(x: 30, y: 20))

        let buffer = canvas.activeLayer.buffer
        #expect(buffer[15, 20] == .white)
        #expect(buffer[25, 20] == blue)
        #expect(buffer[15, 5] == red)
    }

    @Test func fillStopsAtBordersAndCanvasEdges() {
        let (canvas, history) = makeCanvas()
        let buffer = canvas.activeLayer.buffer
        buffer.fill(.black, in: IntRect(x: 10, y: 10, width: 20, height: 1))
        buffer.fill(.black, in: IntRect(x: 10, y: 29, width: 20, height: 1))
        buffer.fill(.black, in: IntRect(x: 10, y: 10, width: 1, height: 20))
        buffer.fill(.black, in: IntRect(x: 29, y: 10, width: 1, height: 20))

        let edit = history.beginEdit("Fill", on: canvas)
        let filled = FloodFill.fill(layer: canvas.activeLayer, at: IntPoint(x: 20, y: 20), with: red, tolerance: 0, selection: nil, edit: edit)

        #expect(filled == IntRect(x: 11, y: 11, width: 18, height: 18))
        #expect(buffer[11, 11] == red)
        #expect(buffer[28, 28] == red)
        #expect(buffer[10, 10] == .black)
        #expect(buffer[5, 5] == .white)
        #expect(history.commit(edit))
        history.undo(on: canvas)
        #expect(buffer[20, 20] == .white)
    }

    @Test func fillToleranceIncludesSimilarColors() {
        let (canvas, history) = makeCanvas()
        let buffer = canvas.activeLayer.buffer
        buffer.fill(Pixel(r: 250, g: 250, b: 250), in: IntRect(x: 0, y: 0, width: 20, height: 40))

        let exact = history.beginEdit("Fill", on: canvas)
        FloodFill.fill(layer: canvas.activeLayer, at: IntPoint(x: 30, y: 5), with: red, tolerance: 0, selection: nil, edit: exact)
        #expect(buffer[5, 5] != red)

        let loose = history.beginEdit("Fill", on: canvas)
        FloodFill.fill(layer: canvas.activeLayer, at: IntPoint(x: 5, y: 5), with: blue, tolerance: 0.05, selection: nil, edit: loose)
        #expect(buffer[5, 5] == blue)
    }

    @Test func fillStaysInsideTheSelection() {
        let (canvas, history) = makeCanvas()
        let selection = SelectionMask.rectangle(IntRect(x: 0, y: 0, width: 10, height: 10), clippedTo: canvas.bounds)
        let edit = history.beginEdit("Fill", on: canvas)
        FloodFill.fill(layer: canvas.activeLayer, at: IntPoint(x: 5, y: 5), with: red, tolerance: 0, selection: selection, edit: edit)
        #expect(canvas.activeLayer.buffer[9, 9] == red)
        #expect(canvas.activeLayer.buffer[10, 10] == .white)

        let outside = history.beginEdit("Fill", on: canvas)
        #expect(FloodFill.fill(layer: canvas.activeLayer, at: IntPoint(x: 20, y: 20), with: red, tolerance: 0, selection: selection, edit: outside).isEmpty)
    }

    @Test func fillCoversALargeCanvasWithoutRecursion() {
        let (canvas, history) = makeCanvas(width: 2000, height: 2000)
        let edit = history.beginEdit("Fill", on: canvas)
        let filled = FloodFill.fill(layer: canvas.activeLayer, at: IntPoint(x: 0, y: 0), with: red, tolerance: 0, selection: nil, edit: edit)
        #expect(filled == canvas.bounds)
        #expect(canvas.activeLayer.buffer[1999, 1999] == red)
    }
}

struct EraserFootprintTests {
    @Test func coversTheSquareTheEraserClears() {
        #expect(EraserStroke.footprint(at: Point2D(x: 10.7, y: 20.2), size: 8) == IntRect(x: 6, y: 16, width: 8, height: 8))
        #expect(EraserStroke.footprint(at: Point2D(x: 3, y: 3), size: 5) == IntRect(x: 1, y: 1, width: 5, height: 5))
    }

    @Test func matchesThePixelsAStrokeErases() {
        let canvas = Canvas(size: IntSize(width: 20, height: 20), colorSpace: Canvas.defaultColorSpace, background: .black)
        let history = History(byteBudget: .max)
        let edit = history.beginEdit("Erase", on: canvas)
        let stroke = EraserStroke(size: 5, effect: .replace(.white), layer: canvas.activeLayer, edit: edit)
        let point = Point2D(x: 9.6, y: 4.1)
        #expect(stroke.move(to: point) == EraserStroke.footprint(at: point, size: 5))
    }
}
