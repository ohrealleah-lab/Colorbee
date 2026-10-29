import Testing
@testable import ColorbeeCore

/// Stamp Visible and showing or hiding several layers in one step (FR-8.6, stage 22).
struct StampVisibleTests {
    private let context = SelectionContext(color2: .white)

    @Test func stampVisibleHoldsWhatsShownAboveTheActiveLayer() {
        let canvas = Canvas(size: IntSize(width: 8, height: 8), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: .max)
        LayerActions.add(canvas: canvas, history: history, context: context)
        canvas.activeLayer.buffer.fill(Pixel(r: 255, g: 0, b: 0), in: IntRect(x: 0, y: 0, width: 4, height: 4))
        canvas.activeLayer.opacity = 0.5
        LayerActions.addAdjustment(.invert, named: "Invert", canvas: canvas, history: history, context: context)
        canvas.layers[2].isVisible = false
        canvas.activeLayerIndex = 0
        let shown = canvas.flattened()
        #expect(LayerActions.stampVisible(canvas: canvas, history: history, context: context))
        #expect(canvas.layers.map(\.name) == ["Background", "Stamp", "Layer 1", "Invert"] && canvas.activeLayerIndex == 1)
        #expect(canvas.layers[1].buffer.contentHash() == shown.contentHash())
        history.undo(on: canvas)
        #expect(canvas.layers.count == 3)
    }

    @Test func severalLayersShowOrHideInOneStep() {
        let canvas = Canvas(size: IntSize(width: 4, height: 4), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: .max)
        LayerActions.add(canvas: canvas, history: history, context: context)
        let ids = canvas.layers.map(\.id)
        #expect(LayerActions.setVisibility([ids[0]: false, ids[1]: true], named: "Show Only", canvas: canvas, history: history))
        #expect(canvas.layers.map(\.isVisible) == [false, true] && history.undoActionName == "Show Only")
        // No change, no step.
        #expect(!LayerActions.setVisibility([ids[0]: false], named: "Again", canvas: canvas, history: history))
        history.undo(on: canvas)
        #expect(canvas.layers.map(\.isVisible) == [true, true])
    }
}
