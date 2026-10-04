import Foundation
import Testing
@testable import ColorbeeCore

/// Regression tests for the findings of cloud review G (Docs/Review/findings-G.md), which Leah confirmed by hand.
struct ReviewGTests {
    private let context = SelectionContext(color2: .white)

    private func paint(_ canvas: Canvas, _ history: History) {
        let edit = history.beginEdit("Pencil", on: canvas)
        edit.willModify(IntRect(x: 1, y: 1, width: 3, height: 3), in: canvas.activeLayer)
        canvas.activeLayer.buffer.fill(.black, in: IntRect(x: 1, y: 1, width: 3, height: 3))
        history.commit(edit)
    }

    /// Finding 1: while a paste floats, Undo on Active Layer can't say which step it would undo.
    @Test func undoOnActiveLayerWaitsForAFloatingPasteToBePlaced() {
        let canvas = Canvas(size: IntSize(width: 16, height: 16), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: 512 << 20)
        paint(canvas, history)
        #expect(history.undoOnLayerActionName(canvas.activeLayer.id, canvas: canvas) == "Pencil")
        SelectionActions.paste(PixelBuffer(width: 4, height: 4, fill: .black), at: IntPoint(x: 8, y: 8), canvas: canvas, history: history, context: context)
        #expect(history.undoOnLayerActionName(canvas.activeLayer.id, canvas: canvas) == nil)
    }

    /// Finding 3: the layers as saved include a floating selection, as the file does.
    @Test func theLayersAsSavedIncludeAFloatingPaste() throws {
        let canvas = Canvas(size: IntSize(width: 16, height: 16), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: 512 << 20)
        SelectionActions.paste(PixelBuffer(width: 4, height: 4, fill: Pixel(r: 200, g: 0, b: 0)), at: IntPoint(x: 8, y: 8),
                               canvas: canvas, history: history, context: context)
        let saved = canvas.layerBuffersAsSaved(transparentKey: nil, resampling: .smooth)
        let reopened = try ProjectFile.decode(ProjectFile.encode(canvas, resampling: .smooth))
        let layer = canvas.layers[0]
        #expect(saved[layer.id]?.contentHash() == reopened.layers[0].buffer.contentHash())
        #expect(saved[layer.id]?.row(9)[9] == Pixel(r: 200, g: 0, b: 0))
        #expect(layer.buffer.row(9)[9] == .white)
    }

    /// Finding 4: a flip or rotation since the save is visible to Revert Layer, and undoing it isn't.
    @Test func turningTheImageChangesItsGeometrySteps() {
        let canvas = Canvas(size: IntSize(width: 16, height: 16), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: 512 << 20)
        paint(canvas, history)
        let saved = history.geometrySteps
        ImageActions.transform(.flipHorizontal, canvas: canvas, history: history, context: context)
        #expect(history.geometrySteps != saved)
        paint(canvas, history)
        history.undo(on: canvas)
        history.undo(on: canvas)
        #expect(history.geometrySteps == saved)
    }

    /// Finding 5: copying a buffer that holds nothing keeps it free.
    @Test func copyingAnUntouchedBufferLeavesItUntouched() {
        let empty = PixelBuffer(width: 512, height: 512)
        #expect(empty.copy().isUntouched)
        let canvas = Canvas(size: IntSize(width: 512, height: 512), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: 512 << 20)
        LayerActions.addAdjustment(.invert, named: "Invert", canvas: canvas, history: history, context: context)
        LayerActions.duplicate(canvas: canvas, history: history, context: context)
        #expect(canvas.activeLayer.buffer.isUntouched)
    }
}
