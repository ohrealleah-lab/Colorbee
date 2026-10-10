import Testing
@testable import ColorbeeCore

/// Adjustment layers that change only the layer below (Leah, 2026-10-10).
struct ClippedAdjustmentTests {
    private let context = SelectionContext(color2: .white)
    private let gray = Pixel(r: 100, g: 100, b: 100)

    /// A white background, a "subject" layer with a gray square, and an Invert on top.
    private func stack() -> (Canvas, History) {
        let canvas = Canvas(size: IntSize(width: 20, height: 20), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: .max)
        LayerActions.add(canvas: canvas, history: history, context: context)
        canvas.activeLayer.buffer.fill(gray, in: IntRect(x: 5, y: 5, width: 10, height: 10))
        LayerActions.addAdjustment(.invert, named: "Invert", canvas: canvas, history: history, context: context)
        return (canvas, history)
    }

    @Test func aClippedAdjustmentChangesOnlyTheLayerBelow() {
        let (canvas, history) = stack()
        #expect(canvas.flattened()[1, 1] == .black)
        #expect(LayerActions.update("Only the Layer Below", layerAt: 2, canvas: canvas, history: history) { $0.clipsToLayerBelow = true })
        let flat = canvas.flattened()
        // The background shows through unchanged; the subject is inverted.
        #expect(flat[1, 1] == .white)
        #expect(flat[10, 10] == Pixel(r: 155, g: 155, b: 155))
        #expect(canvas.thumbnail(maxSide: 20).pixels[1 * 20 + 1] == .white)
        history.undo(on: canvas)
        #expect(!canvas.layers[2].clipsToLayerBelow && canvas.flattened()[1, 1] == .black)
    }

    @Test func clipsReachTheNearestPixelLayerThroughOtherClips() {
        let (canvas, history) = stack()
        canvas.layers[2].clipsToLayerBelow = true
        LayerActions.addAdjustment(.desaturate, named: "Gray", canvas: canvas, history: history, context: context)
        canvas.layers[3].clipsToLayerBelow = true
        #expect(canvas.clipBaseIndex(forLayerAt: 3) == 1)
        #expect(canvas.clippedAdjustments(onLayerAt: 1).map(\.name) == ["Invert", "Gray"])
        // Nothing to clip to: the bottom layer, or an adjustment that isn't clipped.
        #expect(!canvas.canClip(layerAt: 0))
        canvas.layers[2].clipsToLayerBelow = false
        #expect(canvas.clipBaseIndex(forLayerAt: 3) == nil && !canvas.canClip(layerAt: 3))
    }

    @Test func aHiddenSubjectHidesItsClippedAdjustments() {
        let (canvas, _) = stack()
        canvas.layers[2].clipsToLayerBelow = true
        canvas.layers[1].isVisible = false
        #expect(canvas.flattened()[10, 10] == .white)
    }

    @Test func mergingAClippedAdjustmentBakesItIntoItsLayerOnly() {
        let (canvas, history) = stack()
        canvas.layers[2].clipsToLayerBelow = true
        let look = canvas.flattened().contentHash()
        #expect(LayerActions.applyAdjustment(canvas: canvas, history: history, context: context))
        #expect(canvas.layers.count == 2)
        #expect(canvas.layers[0].buffer[1, 1] == .white)
        #expect(canvas.layers[1].buffer[10, 10] == Pixel(r: 155, g: 155, b: 155))
        #expect(canvas.flattened().contentHash() == look)
        history.undo(on: canvas)
        #expect(canvas.layers.count == 3 && canvas.layers[1].buffer[10, 10] == gray)
    }

    @Test func theSettingIsSavedInAProject() throws {
        let (canvas, _) = stack()
        canvas.layers[2].clipsToLayerBelow = true
        let reopened = try ProjectFile.decode(ProjectFile.encode(canvas))
        #expect(reopened.layers[2].clipsToLayerBelow)
        #expect(reopened.flattened().contentHash() == canvas.flattened().contentHash())
    }
}
