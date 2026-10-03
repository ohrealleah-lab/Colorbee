import Testing
@testable import ColorbeeCore

struct AdjustmentTests {
    private let orange = Pixel(r: 245, g: 150, b: 30)

    private func apply(_ effect: Effect, to color: Pixel) -> Pixel {
        let canvas = Canvas(size: IntSize(width: 8, height: 8), colorSpace: Canvas.defaultColorSpace, background: color)
        let edit = History(byteBudget: .max).beginEdit("Adjust", on: canvas)
        Effects.apply(effect, to: canvas.activeLayer, selection: nil, edit: edit)
        return canvas.activeLayer.buffer[4, 4]
    }

    @Test func invertFlipsChannelsAndKeepsAlpha() {
        #expect(apply(.invert, to: Pixel(r: 10, g: 200, b: 255, a: 128)) == Pixel(r: 245, g: 55, b: 0, a: 128))
    }

    @Test func desaturateMakesGray() {
        let gray = apply(.desaturate, to: orange)
        #expect(gray.r == gray.g && gray.g == gray.b)
    }

    @Test func brightnessAndContrast() {
        #expect(apply(.brightnessContrast(brightness: 0, contrast: 0), to: orange) == orange)
        #expect(apply(.brightnessContrast(brightness: 50, contrast: 0), to: Pixel(r: 100, g: 100, b: 100)).r > 100)
        #expect(apply(.brightnessContrast(brightness: 0, contrast: 50), to: Pixel(r: 200, g: 60, b: 128)) == Pixel(r: 236, g: 26, b: 128))
    }

    @Test func hueSaturationRoundTripsAndShifts() {
        #expect(apply(.hueSaturation(hue: 0, saturation: 0, lightness: 0), to: orange) == orange)
        let shifted = apply(.hueSaturation(hue: 180, saturation: 0, lightness: 0), to: Pixel(r: 255, g: 0, b: 0))
        #expect(shifted == Pixel(r: 0, g: 255, b: 255))
        let gray = apply(.hueSaturation(hue: 0, saturation: -100, lightness: 0), to: orange)
        #expect(gray.r == gray.g && gray.g == gray.b)
    }

    @Test func sharpenIncreasesEdgeContrast() {
        let canvas = Canvas(size: IntSize(width: 20, height: 10), colorSpace: Canvas.defaultColorSpace, background: Pixel(r: 100, g: 100, b: 100))
        canvas.activeLayer.buffer.fill(Pixel(r: 150, g: 150, b: 150), in: IntRect(x: 10, y: 0, width: 10, height: 10))
        let edit = History(byteBudget: .max).beginEdit("Sharpen", on: canvas)
        Effects.apply(.sharpen(amount: 100), to: canvas.activeLayer, selection: nil, edit: edit)
        #expect(canvas.activeLayer.buffer[9, 5].r < 100)
        #expect(canvas.activeLayer.buffer[10, 5].r > 150)
        #expect(canvas.activeLayer.buffer[2, 5].r == 100)
    }
}

struct OrientationTests {
    private let red = Pixel(r: 255, g: 0, b: 0)

    private func makeCanvas() -> (Canvas, History) {
        let canvas = Canvas(size: IntSize(width: 30, height: 20), colorSpace: Canvas.defaultColorSpace, background: .white)
        canvas.activeLayer.buffer[0, 0] = red
        return (canvas, History(byteBudget: .max))
    }

    @Test func rotatingTheImageSwapsItsSidesAndUndoes() {
        let (canvas, history) = makeCanvas()
        let original = canvas.activeLayer.buffer.contentHash()
        ImageActions.transform(.rotate90Clockwise, canvas: canvas, history: history, context: SelectionContext(color2: .white))
        #expect(canvas.size == IntSize(width: 20, height: 30))
        #expect(canvas.activeLayer.buffer[19, 0] == red)
        history.undo(on: canvas)
        #expect(canvas.size == IntSize(width: 30, height: 20))
        #expect(canvas.activeLayer.buffer.contentHash() == original)
    }

    @Test(arguments: Orientation.allCases)
    func transformsKeepNoPixelsAndUndoAndRedoExactly(orientation: Orientation) {
        let (canvas, history) = makeCanvas()
        canvas.activeLayer.buffer[3, 7] = Pixel(r: 1, g: 2, b: 3, a: 4)
        let original = canvas.activeLayer.buffer.contentHash()
        ImageActions.transform(orientation, canvas: canvas, history: history, context: SelectionContext(color2: .white))
        let turned = canvas.activeLayer.buffer.contentHash()
        #expect(history.byteCount == 0)
        history.undo(on: canvas)
        #expect(canvas.size == IntSize(width: 30, height: 20))
        #expect(canvas.activeLayer.buffer.contentHash() == original)
        history.redo(on: canvas)
        #expect(canvas.activeLayer.buffer.contentHash() == turned)
    }

    @Test(arguments: Orientation.allCases)
    func everyTransformMapsCornersCorrectly(orientation: Orientation) {
        let buffer = PixelBuffer(width: 3, height: 2)
        buffer[0, 0] = red
        let result = buffer.transformed(orientation)
        let expected: (Int, Int) = switch orientation {
        case .rotate90Clockwise: (1, 0)
        case .rotate90CounterClockwise: (0, 2)
        case .rotate180: (2, 1)
        case .flipHorizontal: (2, 0)
        case .flipVertical: (0, 1)
        }
        #expect(result[expected.0, expected.1] == red)
    }

    /// Leah's hand test: flipping both ways is a half turn, but a single vertical flip is not.
    @Test func bothFlipsEqualAHalfTurn() {
        let buffer = PixelBuffer(width: 4, height: 3)
        for y in 0..<3 { for x in 0..<4 { buffer[x, y] = Pixel(r: UInt8(x * 60), g: UInt8(y * 80), b: 7) } }
        let bothFlips = buffer.transformed(.flipVertical).transformed(.flipHorizontal)
        #expect(bothFlips.contentHash() == buffer.transformed(.rotate180).contentHash())
        #expect(buffer.transformed(.flipVertical).contentHash() != buffer.transformed(.rotate180).contentHash())
    }

    @Test func flippingASelectionStaysInPlace() {
        let (canvas, history) = makeCanvas()
        let context = SelectionContext(color2: .white)
        canvas.activeLayer.buffer.fill(red, in: IntRect(x: 10, y: 5, width: 3, height: 4))
        let mask = SelectionMask.rectangle(IntRect(x: 10, y: 5, width: 6, height: 4), clippedTo: canvas.bounds)
        SelectionActions.select(mask, mode: .replace, canvas: canvas, history: history, context: context)
        SelectionActions.transformSelection(.flipHorizontal, canvas: canvas, history: history, context: context)
        SelectionActions.placeFloating(canvas: canvas, history: history, context: context)
        #expect(canvas.activeLayer.buffer[15, 6] == red)
        #expect(canvas.activeLayer.buffer[10, 6] == .white)
        #expect(history.undoCount == 1)
    }

    @Test func rotatingASelectionKeepsItsCenter() {
        let (canvas, history) = makeCanvas()
        let context = SelectionContext(color2: .white)
        let mask = SelectionMask.rectangle(IntRect(x: 10, y: 5, width: 8, height: 4), clippedTo: canvas.bounds)
        SelectionActions.select(mask, mode: .replace, canvas: canvas, history: history, context: context)
        SelectionActions.transformSelection(.rotate90Clockwise, canvas: canvas, history: history, context: context)
        #expect(canvas.selection.floating?.destination == IntRect(x: 12, y: 3, width: 4, height: 8))
    }
}
