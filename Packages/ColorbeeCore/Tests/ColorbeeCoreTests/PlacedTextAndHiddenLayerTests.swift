import Testing
@testable import ColorbeeCore

/// Placing text keeps the layer you were on, and which layers count as hidden (stage 34b; §23, 2026-11-20).
struct PlacedTextAndHiddenLayerTests {
    private let context = SelectionContext(color2: .white)

    private func spec(_ text: String = "Hi") -> TextSpec {
        TextSpec(text: text, origin: Point2D(x: 4, y: 4), fontFamily: "Helvetica Neue", fontSize: 14, color: .black)
    }

    @Test func placedTextGoesAboveAndTheLayerYouWereOnStaysActive() {
        let canvas = Canvas(size: IntSize(width: 60, height: 30), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: .max)
        LayerActions.add(canvas: canvas, history: history, context: context)
        canvas.activeLayerIndex = 0
        let picture = canvas.activeLayer
        #expect(LayerActions.addText(spec(), canvas: canvas, history: history, context: context))
        #expect(canvas.layers.count == 3 && canvas.activeLayer === picture)
        #expect(canvas.layers[1].text != nil)

        history.undo(on: canvas)
        #expect(canvas.layers.count == 2 && canvas.activeLayer === picture)
        history.redo(on: canvas)
        #expect(canvas.layers[1].text != nil && canvas.activeLayer === picture)
    }

    @Test func hiddenMeansItsEyeOrItsGroupsEyeIsOff() throws {
        let canvas = Canvas(size: IntSize(width: 10, height: 10), colorSpace: Canvas.defaultColorSpace, background: .white)
        let layer = canvas.activeLayer
        #expect(!canvas.isHidden(layer))
        layer.opacity = 0
        #expect(!canvas.isHidden(layer))
        layer.isVisible = false
        #expect(canvas.isHidden(layer))
        layer.isVisible = true

        let history = History(byteBudget: .max)
        LayerActions.group([layer.id], canvas: canvas, history: history, context: context)
        let group = try #require(canvas.layers.first { $0.isGroup })
        #expect(layer.groupID == group.id)
        group.isVisible = false
        #expect(canvas.isHidden(layer) && canvas.isHidden(group))
    }
}
