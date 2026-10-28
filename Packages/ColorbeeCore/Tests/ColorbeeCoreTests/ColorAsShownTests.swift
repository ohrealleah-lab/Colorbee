import Testing
@testable import ColorbeeCore

/// The color readout and the Eyedropper read what's shown (FR-9.7 item 9): a small patch around the pointer must
/// match the whole picture, even under adjustments that look at neighbors or at where a pixel is.
struct ColorAsShownTests {
    private let context = SelectionContext(color2: .white)

    /// A picture with detail everywhere, so blurs and sharpening change it.
    private func picture() -> (Canvas, History) {
        let canvas = Canvas(size: IntSize(width: 90, height: 70), colorSpace: Canvas.defaultColorSpace, background: .white)
        var random = SplitMix64(seed: 9)
        for y in 0..<70 { for x in 0..<90 { canvas.activeLayer.buffer.row(y)[x] = Pixel(r: UInt8(x * 2), g: random.byte(), b: UInt8(y * 3)) } }
        return (canvas, History(byteBudget: .max))
    }

    private func expectMatchesTheExport(_ canvas: Canvas) {
        let flat = canvas.flattened()
        for point in [IntPoint(x: 0, y: 0), IntPoint(x: 3, y: 66), IntPoint(x: 45, y: 35), IntPoint(x: 89, y: 69), IntPoint(x: 70, y: 12)] {
            let shown = canvas.pixelAsShown(at: point)
            #expect(shown == flat[point.x, point.y], "at \(point)")
        }
    }

    @Test func underAVignetteAndGrainItMatchesTheExport() {
        let (canvas, history) = picture()
        var effects = PhotoEffects()
        effects.roundness = 40
        LayerActions.addAdjustment(.photo(PhotoEdit(adjustments: PhotoAdjustments([.vignette: -60, .grain: 70]), effects: effects)),
                                   named: "Look", canvas: canvas, history: history, context: context)
        expectMatchesTheExport(canvas)
    }

    @Test func underDetailSlidersAndABlurLayerItMatchesTheExport() {
        let (canvas, history) = picture()
        var detail = PhotoDetail()
        detail.radius = 2.5
        detail.color = 30
        LayerActions.addAdjustment(.photo(PhotoEdit(adjustments: PhotoAdjustments([.sharpness: 50, .definition: 40, .noiseReduction: 30, .texture: 20]), detail: detail)),
                                   named: "Detail", canvas: canvas, history: history, context: context)
        expectMatchesTheExport(canvas)
        LayerActions.addAdjustment(.gaussianBlur(radius: 6), named: "Blur", canvas: canvas, history: history, context: context)
        expectMatchesTheExport(canvas)
    }

    @Test func aSampleAveragesItsAreaOpacityIncluded() {
        let buffer = PixelBuffer(width: 3, height: 3, fill: .clear)
        buffer.row(1)[1] = Pixel(r: 90, g: 30, b: 0)
        buffer.row(0)[0] = Pixel(r: 30, g: 30, b: 0, a: 255)
        // Colors weighted by opacity, opacity averaged.
        #expect(buffer.averagedPixel(in: buffer.bounds) == Pixel(r: 60, g: 30, b: 0, a: 57))
        #expect(PixelBuffer(width: 2, height: 2).averagedPixel(in: IntRect(x: 0, y: 0, width: 2, height: 2)) == .clear)
        let canvas = Canvas(size: IntSize(width: 4, height: 4), colorSpace: Canvas.defaultColorSpace, background: .black)
        canvas.activeLayer.buffer.row(1)[1] = .white
        // A 3 × 3 sample around (1, 1): one white pixel in nine.
        #expect(canvas.colorAsShown(in: IntRect(x: 0, y: 0, width: 3, height: 3)) == Pixel(r: 28, g: 28, b: 28))
        #expect(canvas.colorAsShown(in: IntRect(x: 9, y: 9, width: 3, height: 3)) == nil)
    }
}
