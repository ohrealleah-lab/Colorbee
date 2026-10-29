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

    /// Review W, finding 3: blurs one above another reach as far as their reaches added up.
    @Test func underTwoBlursItMatchesTheExport() {
        let (canvas, history) = picture()
        LayerActions.addAdjustment(.gaussianBlur(radius: 8), named: "Blur", canvas: canvas, history: history, context: context)
        LayerActions.addAdjustment(.gaussianBlur(radius: 8), named: "Blur 2", canvas: canvas, history: history, context: context)
        expectMatchesTheExport(canvas)
    }

    /// Review W, finding 1: a paste not yet placed is read as it shows.
    @Test func aFloatingPasteIsReadAsShown() {
        let (canvas, history) = picture()
        SelectionActions.paste(PixelBuffer(width: 20, height: 20, fill: Pixel(r: 217, g: 43, b: 43)), at: IntPoint(x: 35, y: 25),
                               canvas: canvas, history: history, context: context)
        #expect(canvas.pixelAsShown(at: IntPoint(x: 45, y: 35)) == Pixel(r: 217, g: 43, b: 43))
        LayerActions.addAdjustment(.gaussianBlur(radius: 3), named: "Blur", canvas: canvas, history: history, context: context)
        expectMatchesTheExport(canvas)
    }

    /// Review V, finding 9: an adjustment set to "Only the layer below" sees that layer itself, not the picture.
    @Test func aClippedAdjustmentSeesItsOwnLayer() throws {
        let (canvas, history) = picture()
        LayerActions.add(canvas: canvas, history: history, context: context)
        canvas.activeLayer.buffer.fill(Pixel(r: 255, g: 0, b: 0), in: IntRect(x: 10, y: 10, width: 30, height: 30))
        canvas.activeLayer.opacity = 0.5
        canvas.activeLayer.blendMode = .multiply
        LayerActions.addAdjustment(.invert, named: "Invert", canvas: canvas, history: history, context: context)
        #expect(canvas.clipBasePatch(IntRect(x: 20, y: 20, width: 3, height: 3), under: canvas.activeLayerIndex) == nil)
        canvas.activeLayer.clipsToLayerBelow = true
        let patch = try #require(canvas.clipBasePatch(IntRect(x: 20, y: 20, width: 3, height: 3), under: canvas.activeLayerIndex))
        #expect(patch.averageColor(in: patch.bounds) == Pixel(r: 255, g: 0, b: 0))
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
