import Foundation
import Testing
@testable import ColorbeeCore

/// Overnight monkey test, 2026-11-03: Undo on Active Layer on an Edit Text, then Undo of the Resize Canvas before it.
struct TextGeometryUndoTests {
    private let context = SelectionContext(color2: .white)
    @Test func undoingAResizeAfterUndoOnLayerKeepsTextMatchingItsWords() throws {
        let canvas = Canvas(size: IntSize(width: 114, height: 59), colorSpace: Canvas.defaultColorSpace, background: Pixel(r: 200, g: 200, b: 200))
        let history = History(byteBudget: .max)
        let s = TextSpec(text: "x", origin: Point2D(x: 6, y: 28), fontFamily: "Helvetica Neue", fontSize: 18, color: Pixel(r: 0x4B, g: 0x9C, b: 0x27))
        LayerActions.addText(s, canvas: canvas, history: history, context: context)
        ImageActions.resizeCanvas(to: IntSize(width: 134, height: 75), canvas: canvas, history: history, context: context)
        var s2 = s; s2.text = "API key"
        #expect(LayerActions.setText(s2, layerAt: 1, canvas: canvas, history: history, context: context))
        let layer = canvas.layers[1]
        func ok() -> Bool { layer.buffer.contentHash() == layer.text!.drawn(size: canvas.size, colorSpace: canvas.colorSpace).contentHash() }
        #expect(ok(), "after edit")
        #expect(history.undoOnLayer(layer.id, canvas: canvas))
        #expect(layer.text?.spec.text == "x", "text after undo: \(layer.text?.spec.text ?? "nil")")
        #expect(ok(), "after undoOnLayer")
        history.undo(on: canvas); #expect(ok(), "undo1")
        history.undo(on: canvas); #expect(ok(), "undo2")
        history.redo(on: canvas); history.redo(on: canvas); #expect(ok(), "redo")
    }
}
