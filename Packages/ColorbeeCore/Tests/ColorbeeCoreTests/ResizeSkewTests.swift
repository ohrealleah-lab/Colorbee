import Testing
@testable import ColorbeeCore

struct ResizeSkewTests {
    private let red = Pixel(r: 255, g: 0, b: 0)
    private let blue = Pixel(r: 0, g: 0, b: 255)

    private func makeCanvas(width: Int = 10, height: Int = 6, background: Pixel = .white) -> (Canvas, History) {
        (Canvas(size: IntSize(width: width, height: height), colorSpace: Canvas.defaultColorSpace, background: background),
         History(byteBudget: .max))
    }

    @Test func skewingWidensByTheSlantAcrossTheHeight() {
        let settings = ResizeSkew(size: IntSize(width: 100, height: 50), horizontalSkew: 45, resampling: .nearestNeighbor)
        #expect(settings.resultSize == IntSize(width: 149, height: 50))
        let both = ResizeSkew(size: IntSize(width: 10, height: 10), horizontalSkew: 45, verticalSkew: -45, resampling: .smooth)
        #expect(both.resultSize == IntSize(width: 19, height: 28))
    }

    @Test func positiveHorizontalSkewLeansTheTopRight() {
        let buffer = PixelBuffer(width: 3, height: 3, fill: red)
        let result = buffer.resizedAndSkewed(ResizeSkew(size: buffer.size, horizontalSkew: 45, resampling: .nearestNeighbor))
        #expect(result.size == IntSize(width: 5, height: 3))
        // Top row slides right by 2, the middle by 1, the bottom stays put.
        #expect((0..<5).map { result[$0, 0].a } == [0, 0, 255, 255, 255])
        #expect((0..<5).map { result[$0, 1].a } == [0, 255, 255, 255, 0])
        #expect((0..<5).map { result[$0, 2].a } == [255, 255, 255, 0, 0])
    }

    @Test func positiveVerticalSkewRaisesTheRightSide() {
        let buffer = PixelBuffer(width: 3, height: 3, fill: red)
        let result = buffer.resizedAndSkewed(ResizeSkew(size: buffer.size, verticalSkew: 45, resampling: .nearestNeighbor))
        #expect(result.size == IntSize(width: 3, height: 5))
        #expect((0..<5).map { result[2, $0].a } == [255, 255, 255, 0, 0])
        #expect((0..<5).map { result[0, $0].a } == [0, 0, 255, 255, 255])
    }

    @Test func smoothSkewSoftensTheSlantedEdges() {
        let buffer = PixelBuffer(width: 4, height: 4, fill: red)
        let result = buffer.resizedAndSkewed(ResizeSkew(size: buffer.size, horizontalSkew: 20, resampling: .smooth))
        let alphas = (0..<result.width).map { result[$0, 1].a }
        #expect(alphas.contains { $0 > 0 && $0 < 255 })
        // Partly covered edge pixels keep the full color rather than fading toward black.
        #expect((0..<result.width).allSatisfy { result[$0, 1].a == 0 || result[$0, 1].r == 255 })
    }

    @Test func refusesEnormousResults() {
        #expect(!ResizeSkew(size: IntSize(width: 1000, height: 1000), horizontalSkew: 89, resampling: .smooth).fits)
        #expect(ResizeSkew(size: IntSize(width: 1000, height: 1000), horizontalSkew: 30, resampling: .smooth).fits)
    }

    @Test func undoStepIsNamedForWhatChanged() {
        let size = IntSize(width: 10, height: 10)
        #expect(ResizeSkew(size: IntSize(width: 20, height: 20), resampling: .smooth).actionName(from: size) == "Resize")
        #expect(ResizeSkew(size: size, horizontalSkew: 10, resampling: .smooth).actionName(from: size) == "Skew")
        #expect(ResizeSkew(size: IntSize(width: 5, height: 5), verticalSkew: 10, resampling: .smooth).actionName(from: size) == "Resize and Skew")
    }

    @Test func skewingTheImageFillsExposedCornersWithColor2AndUndoes() {
        let (canvas, history) = makeCanvas(background: red)
        let original = canvas.activeLayer.buffer.contentHash()
        let settings = ResizeSkew(size: canvas.size, horizontalSkew: 30, resampling: .nearestNeighbor)
        #expect(ImageActions.resizeAndSkew(settings, canvas: canvas, history: history, context: SelectionContext(color2: blue)))
        #expect(canvas.size == settings.resultSize)
        #expect(canvas.activeLayer.buffer[0, 0] == blue)
        #expect(canvas.activeLayer.buffer[canvas.size.width - 1, canvas.size.height - 1] == blue)
        #expect(canvas.activeLayer.buffer[canvas.size.width / 2, 3] == red)
        history.undo(on: canvas)
        #expect(canvas.size == IntSize(width: 10, height: 6))
        #expect(canvas.activeLayer.buffer.contentHash() == original)
    }

    @Test func exposedCornersStayTransparentOnATransparentImage() {
        let (canvas, history) = makeCanvas(background: .clear)
        canvas.activeLayer.buffer.fill(red, in: canvas.bounds)
        let settings = ResizeSkew(size: canvas.size, verticalSkew: 20, resampling: .nearestNeighbor)
        ImageActions.resizeAndSkew(settings, canvas: canvas, history: history, context: SelectionContext(color2: blue))
        #expect(canvas.activeLayer.buffer[0, 0].a == 0)
    }

    @Test func resizingTheImageHasNoExposedArea() {
        let (canvas, history) = makeCanvas(background: red)
        ImageActions.resizeAndSkew(ResizeSkew(size: IntSize(width: 20, height: 3), resampling: .smooth), canvas: canvas, history: history, context: SelectionContext(color2: blue))
        #expect(canvas.size == IntSize(width: 20, height: 3))
        #expect(canvas.activeLayer.buffer[0, 0] == red && canvas.activeLayer.buffer[19, 2] == red)
    }

    @Test func noChangeIsNotAStep() {
        let (canvas, history) = makeCanvas()
        #expect(!ImageActions.resizeAndSkew(ResizeSkew(size: canvas.size, resampling: .smooth), canvas: canvas, history: history, context: SelectionContext(color2: blue)))
        #expect(history.undoCount == 0)
    }

    @Test func resizingASelectionGrowsItAroundItsCenterInOneStep() {
        let (canvas, history) = makeCanvas(width: 40, height: 40)
        let context = SelectionContext(color2: .white)
        canvas.activeLayer.buffer.fill(red, in: IntRect(x: 10, y: 10, width: 10, height: 10))
        let mask = SelectionMask.rectangle(IntRect(x: 10, y: 10, width: 10, height: 10), clippedTo: canvas.bounds)
        SelectionActions.select(mask, mode: .replace, canvas: canvas, history: history, context: context)
        let settings = ResizeSkew(size: IntSize(width: 20, height: 20), resampling: .nearestNeighbor)
        #expect(SelectionActions.resizeAndSkewSelection(settings, canvas: canvas, history: history, context: context))
        #expect(canvas.selection.floating?.destination == IntRect(x: 5, y: 5, width: 20, height: 20))
        SelectionActions.placeFloating(canvas: canvas, history: history, context: context)
        #expect(canvas.activeLayer.buffer[6, 6] == red)
        #expect(canvas.activeLayer.buffer[24, 24] == red)
        // Drawing the marquee isn't a step, and placing merges into the resize.
        #expect(history.undoCount == 1)
    }

    @Test func skewingASelectionSlantsItsOutline() {
        let (canvas, history) = makeCanvas(width: 40, height: 40)
        let context = SelectionContext(color2: .white)
        let mask = SelectionMask.rectangle(IntRect(x: 10, y: 10, width: 6, height: 6), clippedTo: canvas.bounds)
        SelectionActions.select(mask, mode: .replace, canvas: canvas, history: history, context: context)
        let settings = ResizeSkew(size: IntSize(width: 6, height: 6), horizontalSkew: 45, resampling: .nearestNeighbor)
        SelectionActions.resizeAndSkewSelection(settings, canvas: canvas, history: history, context: context)
        guard let floating = canvas.selection.floating else {
            Issue.record("Expected a floating selection")
            return
        }
        #expect(floating.destination.size == IntSize(width: 11, height: 6))
        #expect(floating.mask[0, 0] == 0)
        #expect(floating.mask[10, 0] == 255)
        #expect(floating.mask[0, 5] == 255)
    }
}
