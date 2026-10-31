import Foundation
import Testing
@testable import ColorbeeCore

/// Layer masks (FR-8.8, stages 27 to 28b) and "Only the layer below" for pixel layers (Q28.4).
struct LayerMaskTests {
    private let context = SelectionContext(color2: .white)
    private let red = Pixel(r: 220, g: 30, b: 30)

    /// White paper and a red layer over the left half.
    private func picture() -> (Canvas, History) {
        let canvas = Canvas(size: IntSize(width: 20, height: 10), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: .max)
        LayerActions.add(canvas: canvas, history: history, context: context)
        canvas.activeLayer.name = "Red"
        canvas.activeLayer.buffer.fill(red, in: IntRect(x: 0, y: 0, width: 10, height: 10))
        return (canvas, history)
    }

    /// Black ink on the mask's top half, as a brush would leave it.
    private func paintTopHalf(_ canvas: Canvas, _ history: History, ink: Pixel = .black) {
        let mask = canvas.paintLayer
        let edit = history.beginEdit("Brush", on: canvas)
        edit.willModify(IntRect(x: 0, y: 0, width: 20, height: 5), in: mask)
        mask.buffer.fill(ink, in: IntRect(x: 0, y: 0, width: 20, height: 5))
        history.commit(edit)
    }

    @Test func aMaskHidesWhereItsBlackAndUndoesExactly() throws {
        let (canvas, history) = picture()
        #expect(LayerActions.addMask(.revealAll, canvas: canvas, history: history, context: context))
        let mask = try #require(canvas.activeLayer.mask)
        #expect(canvas.editsMask && canvas.paintLayer === mask && mask.buffer.isUntouched)
        #expect(canvas.flattened()[2, 2] == red)
        paintTopHalf(canvas, history)
        #expect(canvas.flattened()[2, 2] == .white && canvas.flattened()[2, 8] == red)
        // Gray ink half hides.
        paintTopHalf(canvas, history, ink: Pixel(r: 128, g: 128, b: 128))
        let half = canvas.flattened()[2, 2]
        #expect(abs(Int(half.g) - 143) <= 2)
        #expect(canvas.thumbnail(maxSide: 20).pixels == canvas.flattened().pixels(in: canvas.bounds))
        history.undo(on: canvas)
        history.undo(on: canvas)
        #expect(canvas.flattened()[2, 2] == red)
        history.undo(on: canvas)
        #expect(canvas.activeLayer.mask == nil)
    }

    @Test func addMaskFromTheSelectionShowsOnlyTheSelection() throws {
        let (canvas, history) = picture()
        canvas.selection = .marquee(try #require(SelectionMask.rectangle(IntRect(x: 0, y: 5, width: 20, height: 5), clippedTo: canvas.bounds)))
        #expect(LayerActions.addMask(.selection, canvas: canvas, history: history, context: context))
        #expect(canvas.flattened()[2, 2] == .white && canvas.flattened()[2, 8] == red)
        LayerActions.invertMask(canvas: canvas, history: history, context: context)
        #expect(canvas.flattened()[2, 2] == red && canvas.flattened()[2, 8] == .white)
    }

    @Test func turningOffApplyingAndDeletingAMask() throws {
        let (canvas, history) = picture()
        LayerActions.addMask(.revealAll, canvas: canvas, history: history, context: context)
        paintTopHalf(canvas, history)
        LayerActions.setMaskEnabled(false, canvas: canvas, history: history)
        #expect(canvas.flattened()[2, 2] == red)
        history.undo(on: canvas)
        let shown = canvas.flattened().contentHash()
        #expect(LayerActions.applyMask(canvas: canvas, history: history, context: context))
        #expect(canvas.activeLayer.mask == nil && canvas.activeLayer.buffer[2, 2] == .clear)
        #expect(canvas.flattened().contentHash() == shown)
        history.undo(on: canvas)
        #expect(LayerActions.deleteMask(canvas: canvas, history: history, context: context))
        #expect(canvas.flattened()[2, 2] == red)
    }

    @Test func undoOnActiveLayerTakesBackMaskStrokes() throws {
        let (canvas, history) = picture()
        LayerActions.addMask(.revealAll, canvas: canvas, history: history, context: context)
        paintTopHalf(canvas, history)
        let layer = canvas.activeLayer.id
        #expect(history.undoOnLayerActionName(layer, canvas: canvas) == "Brush")
        #expect(history.undoOnLayer(layer, canvas: canvas))
        #expect(canvas.flattened()[2, 2] == red)
    }

    @Test func cropRotateAndSnapshotsKeepTheMask() throws {
        let (canvas, history) = picture()
        LayerActions.addMask(.revealAll, canvas: canvas, history: history, context: context)
        paintTopHalf(canvas, history)
        let snapshot = try history.takeSnapshot(named: "Masked", of: canvas)
        let shown = canvas.flattened().contentHash()
        ImageActions.transform(.rotate180, canvas: canvas, history: history, context: context)
        #expect(canvas.activeLayer.mask?.buffer.size == canvas.size && canvas.flattened()[17, 2] == red)
        #expect(ImageActions.crop(to: IntRect(x: 0, y: 0, width: 12, height: 10), canvas: canvas, history: history, context: context))
        #expect(canvas.activeLayer.mask?.buffer.size == canvas.size)
        try history.goToSnapshot(snapshot.id, on: canvas)
        #expect(canvas.flattened().contentHash() == shown)
        history.undo(on: canvas)
        history.undo(on: canvas)
        history.undo(on: canvas)
        #expect(canvas.flattened().contentHash() == shown)
    }

    @Test func projectsKeepMasksAndBeta7SeesTheLayerWhole() throws {
        let (canvas, history) = picture()
        LayerActions.addMask(.revealAll, canvas: canvas, history: history, context: context)
        paintTopHalf(canvas, history)
        canvas.layers[0].mask = Layer(name: "Untouched", buffer: PixelBuffer(size: canvas.size))
        canvas.layers[0].maskEnabled = false
        let data = try ProjectFile.encode(canvas)
        let reopened = try ProjectFile.decode(data)
        #expect(reopened.flattened().contentHash() == canvas.flattened().contentHash())
        #expect(reopened.layers[1].mask?.id == canvas.layers[1].mask?.id && reopened.layers[0].maskEnabled == false)
        #expect(reopened.layers[0].mask?.buffer.isUntouched == true)
        // Beta 7 reads `layers` only: no masks there.
        let parked = try ProjectFile.decodeParked(data)
        #expect(parked.pixelLayers.contains(canvas.layers[1].mask!.id))
    }

    @Test func duplicatesGetMasksOfTheirOwn() throws {
        let (canvas, history) = picture()
        LayerActions.addMask(.revealAll, canvas: canvas, history: history, context: context)
        paintTopHalf(canvas, history)
        LayerActions.duplicate(canvas: canvas, history: history, context: context)
        let original = try #require(canvas.layers[1].mask), copy = try #require(canvas.layers[2].mask)
        #expect(original !== copy && original.id != copy.id && original.buffer !== copy.buffer)
        #expect(copy.buffer[2, 2] == .black)
    }

    @Test func mergeDownKeepsALowerLayersMaskedLook() {
        let (canvas, history) = picture()
        LayerActions.addMask(.revealAll, canvas: canvas, history: history, context: context)
        paintTopHalf(canvas, history)
        LayerActions.add(canvas: canvas, history: history, context: context)
        canvas.activeLayer.buffer.fill(Pixel(r: 0, g: 0, b: 200, a: 120), in: IntRect(x: 5, y: 0, width: 10, height: 10))
        let shown = canvas.flattened().contentHash()
        #expect(LayerActions.mergeDown(canvas: canvas, history: history, context: context))
        #expect(canvas.activeLayer.mask == nil && canvas.flattened().contentHash() == shown)
    }

    @Test func aMaskedAdjustmentChangesOnlyWhereItShows() {
        let (canvas, history) = picture()
        LayerActions.addAdjustment(.invert, named: "Invert", canvas: canvas, history: history, context: context)
        LayerActions.addMask(.revealAll, canvas: canvas, history: history, context: context)
        paintTopHalf(canvas, history)
        let flat = canvas.flattened()
        #expect(flat[2, 2] == red && flat[2, 8] == Pixel(r: 35, g: 225, b: 225))
        #expect(canvas.thumbnail(maxSide: 20).pixels == flat.pixels(in: canvas.bounds))
    }

    @Test func aMaskedGroupHidesEverythingInIt() {
        let (canvas, history) = picture()
        LayerActions.group([canvas.layers[1].id], canvas: canvas, history: history, context: context)
        for passesThrough in [true, false] {
            canvas.layers[2].passesThrough = passesThrough
            canvas.activeLayerIndex = 2
            if canvas.activeLayer.mask == nil {
                LayerActions.addMask(.revealAll, canvas: canvas, history: history, context: context)
                paintTopHalf(canvas, history)
            }
            let flat = canvas.flattened()
            #expect(flat[2, 2] == .white && flat[2, 8] == red, "Pass Through \(passesThrough)")
        }
    }

    @Test func aClippedPixelLayerShowsOnlyOnTheLayerBelow() throws {
        let (canvas, history) = picture()
        LayerActions.add(canvas: canvas, history: history, context: context)
        canvas.activeLayer.buffer.fill(Pixel(r: 0, g: 0, b: 200), in: canvas.bounds)
        #expect(canvas.canClip(layerAt: 2))
        canvas.activeLayer.clipsToLayerBelow = true
        let flat = canvas.flattened()
        #expect(flat[2, 2] == Pixel(r: 0, g: 0, b: 200) && flat[15, 2] == .white)
        #expect(canvas.thumbnail(maxSide: 20).pixels == flat.pixels(in: canvas.bounds))
        // A project keeps it (it was lost on saving until 2026-10-31).
        let reopened = try ProjectFile.decode(try ProjectFile.encode(canvas))
        #expect(reopened.layers[2].clipsToLayerBelow && reopened.flattened().contentHash() == flat.contentHash())
        // It belongs to the layer: deleting the layer takes it too.
        canvas.activeLayerIndex = 1
        #expect(LayerActions.delete(canvas: canvas, history: history, context: context))
        #expect(canvas.layers.count == 1)
    }
}
