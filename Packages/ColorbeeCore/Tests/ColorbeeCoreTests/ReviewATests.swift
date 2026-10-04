import Testing
@testable import ColorbeeCore

/// Regression tests for the stage 8–9 review, session A (Docs/Review/findings-A.md).
struct ReviewATests {
    private let context = SelectionContext(color2: .white)

    private func painted(_ width: Int, _ height: Int, layers: Int = 1) -> Canvas {
        let canvas = Canvas(size: IntSize(width: width, height: height), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: .max)
        for _ in 1..<layers { LayerActions.add(canvas: canvas, history: history, context: context) }
        for (index, layer) in canvas.layers.enumerated() {
            for y in 0..<height { for x in 0..<width { layer.buffer[x, y] = Pixel(r: UInt8((x * 7 + index * 40) & 255), g: UInt8((y * 5) & 255), b: UInt8(index * 60)) } }
        }
        return canvas
    }

    /// Finding 1: placing a paste after a layer-settings step must still undo its pixels.
    @Test func aPastePlacedAfterALayerSettingUndoesCompletely() {
        let canvas = painted(20, 20)
        let history = History(byteBudget: .max)
        let original = canvas.activeLayer.buffer.contentHash()
        SelectionActions.paste(PixelBuffer(width: 6, height: 6, fill: .black), at: IntPoint(x: 3, y: 3), canvas: canvas, history: history, context: context)
        LayerActions.update("Hide Layer", layerAt: 0, canvas: canvas, history: history) { $0.isVisible = false }
        SelectionActions.placeFloating(canvas: canvas, history: history, context: context)
        #expect(canvas.activeLayer.buffer[5, 5] == .black)
        while history.canUndo { history.undo(on: canvas) }
        #expect(canvas.activeLayer.buffer.contentHash() == original)
        #expect(canvas.layers[0].isVisible)
    }

    /// Finding 2: undoing a geometry step and then dropping it leaves the byte count exact.
    @Test(arguments: [(64, 16), (16, 64)])
    func undoingAndDroppingAGeometryStepKeepsTheByteCount(sizes: (Int, Int)) {
        let canvas = painted(sizes.0, sizes.0)
        let history = History(byteBudget: .max)
        if sizes.1 < sizes.0 {
            ImageActions.crop(to: IntRect(x: 0, y: 0, width: sizes.1, height: sizes.1), canvas: canvas, history: history, context: context)
        } else {
            ImageActions.resizeCanvas(to: IntSize(width: sizes.1, height: sizes.1), canvas: canvas, history: history, context: context)
        }
        history.undo(on: canvas)
        let edit = history.beginEdit("Paint", on: canvas)
        edit.willModify(IntRect(x: 0, y: 0, width: 2, height: 2), in: canvas.activeLayer)
        canvas.activeLayer.buffer[0, 0] = Pixel(r: 1, g: 2, b: 3)
        #expect(history.commit(edit))
        // Only the paint step is left: one tile, which on a canvas this small is the whole canvas.
        #expect(history.byteCount == sizes.0 * sizes.0 * 4)
    }

    /// Finding 3: a layer moved out of memory again with the same pixels doesn't grow the spill file.
    @Test func reEvictingAnUnchangedLayerReusesItsCopyOnDisk() {
        let canvas = painted(256, 256, layers: 2)
        let history = History(byteBudget: 1)
        LayerActions.delete(canvas: canvas, history: history, context: context)
        LayerActions.update("Rename", layerAt: 0, canvas: canvas, history: history) { $0.name = "Renamed" }
        let afterFirst = history.spillFileSize
        #expect(afterFirst > 0)
        for _ in 0..<5 {
            history.undo(on: canvas)
            history.undo(on: canvas)
            history.redo(on: canvas)
            history.redo(on: canvas)
        }
        #expect(history.spillFileSize == afterFirst)
        while history.canUndo { history.undo(on: canvas) }
        #expect(canvas.layers.count == 2)
    }

    /// Finding 4: undoing a spilled crop leaves empty and adjustment layers empty.
    @Test func aSpilledCropKeepsEmptyLayersEmpty() {
        let canvas = painted(64, 64)
        let history = History(byteBudget: 1)
        LayerActions.addAdjustment(.invert, named: "Invert", canvas: canvas, history: history, context: context)
        LayerActions.add(canvas: canvas, history: history, context: context)
        ImageActions.crop(to: IntRect(x: 0, y: 0, width: 32, height: 32), canvas: canvas, history: history, context: context)
        LayerActions.update("Rename", layerAt: 0, canvas: canvas, history: history) { $0.name = "After" }
        history.undo(on: canvas)
        history.undo(on: canvas)
        #expect(canvas.size == IntSize(width: 64, height: 64))
        #expect(canvas.layers[1].buffer.isUntouched)
        #expect(canvas.layers[2].buffer.isUntouched)
        #expect(!canvas.layers[0].buffer.isUntouched)
    }

    /// Finding 6: Straighten refuses a result past the size limit, before allocating anything.
    @Test func straightenRefusesAnOversizedResult() {
        let canvas = Canvas(size: IntSize(width: 16000, height: 16000), colorSpace: Canvas.defaultColorSpace, background: .clear)
        let history = History(byteBudget: .max)
        #expect(!ImageActions.straighten(angle: 45, cropToFit: false, canvas: canvas, history: history, context: context))
        #expect(!history.canUndo && canvas.size == IntSize(width: 16000, height: 16000))
    }

    /// Finding 7: a buffer held by both a geometry step and a layer step is counted once.
    @Test func aSharedBufferIsCountedOnce() {
        let canvas = painted(40, 40, layers: 2)
        let history = History(byteBudget: .max)
        ImageActions.crop(to: IntRect(x: 0, y: 0, width: 20, height: 20), canvas: canvas, history: history, context: context)
        LayerActions.delete(canvas: canvas, history: history, context: context)
        history.undo(on: canvas)
        history.undo(on: canvas)
        // History alone holds the two cropped 20 × 20 buffers.
        #expect(history.byteCount == 2 * 20 * 20 * 4)
    }

    /// Finding 8: Straighten without Crop to Fit fills the corners of an empty solid background with Color 2.
    @Test func straightenFillsTheCornersOfAnEmptySolidBackground() {
        let canvas = Canvas(size: IntSize(width: 60, height: 40), colorSpace: Canvas.defaultColorSpace, background: .clear)
        let history = History(byteBudget: .max)
        let red = SelectionContext(color2: Pixel(r: 255, g: 0, b: 0))
        ImageActions.setTransparentBackground(false, canvas: canvas, history: history)
        #expect(ImageActions.straighten(angle: 10, cropToFit: false, canvas: canvas, history: history, context: red))
        #expect(canvas.layers[0].buffer[0, 0] == Pixel(r: 255, g: 0, b: 0))
    }
}
