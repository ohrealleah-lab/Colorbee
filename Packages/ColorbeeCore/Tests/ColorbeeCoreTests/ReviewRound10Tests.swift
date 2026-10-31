import Foundation
import Testing
@testable import ColorbeeCore

/// Code review round 10 (stage 33) and the monkey test's first find: merges, masks, undo, Align and dropping layers.
struct ReviewRound10Tests {
    private let context = SelectionContext(color2: .white)
    private let red = Pixel(r: 220, g: 30, b: 30), blue = Pixel(r: 20, g: 40, b: 220)

    /// White paper and a red square on a layer above it.
    private func picture() -> (Canvas, History) {
        let canvas = Canvas(size: IntSize(width: 24, height: 16), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: .max)
        LayerActions.add(canvas: canvas, history: history, context: context)
        canvas.activeLayer.buffer.fill(red, in: IntRect(x: 4, y: 4, width: 8, height: 8))
        return (canvas, history)
    }

    /// A new layer above the active one, painted with `color` over `rect`, shown only on the layer below.
    private func clippedLayer(_ canvas: Canvas, _ history: History, color: Pixel, rect: IntRect? = nil) {
        LayerActions.add(canvas: canvas, history: history, context: context)
        canvas.activeLayer.buffer.fill(color, in: rect ?? canvas.bounds)
        canvas.activeLayer.clipsToLayerBelow = true
    }

    @Test func mergingAGroupThatHoldsEveryLayerDoesntCrash() {
        let (canvas, history) = picture()
        let look = canvas.flattened().contentHash()
        LayerActions.group(Set(canvas.layers.map(\.id)), canvas: canvas, history: history, context: context)
        #expect(canvas.activeLayer.isGroup)
        #expect(LayerActions.mergeDown(canvas: canvas, history: history, context: context))
        #expect(canvas.layers.count == 1 && canvas.flattened().contentHash() == look)
        history.undo(on: canvas)
        #expect(canvas.layers.count == 3)
    }

    @Test func mergeAdjustmentTakesClippedPixelLayersAndMasksAlong() throws {
        let (canvas, history) = picture()
        clippedLayer(canvas, history, color: blue, rect: IntRect(x: 0, y: 0, width: 8, height: 16))
        LayerActions.addAdjustment(.invert, named: "Invert", canvas: canvas, history: history, context: context)
        canvas.activeLayer.clipsToLayerBelow = true
        LayerActions.addMask(.revealAll, canvas: canvas, history: history, context: context)
        let mask = try #require(canvas.activeLayer.mask)
        mask.buffer.fill(.black, in: IntRect(x: 0, y: 0, width: 6, height: 16))
        canvas.editsMask = false
        let look = canvas.flattened().contentHash()
        #expect(LayerActions.applyAdjustment(canvas: canvas, history: history, context: context))
        #expect(canvas.flattened().contentHash() == look && canvas.layers.count == 2)
    }

    @Test func undoOnActiveLayerBringsADeletedOrAppliedMaskBack() throws {
        for applying in [false, true] {
            let (canvas, history) = picture()
            LayerActions.addMask(.revealAll, canvas: canvas, history: history, context: context)
            let edit = history.beginEdit("Brush", on: canvas)
            edit.willModify(IntRect(x: 0, y: 0, width: 8, height: 16), in: canvas.paintLayer)
            canvas.paintLayer.buffer.fill(.black, in: IntRect(x: 0, y: 0, width: 8, height: 16))
            history.commit(edit)
            let look = canvas.flattened().contentHash(), pixels = try #require(canvas.activeLayer.mask).buffer.contentHash()
            if applying {
                LayerActions.applyMask(canvas: canvas, history: history, context: context)
            } else {
                LayerActions.deleteMask(canvas: canvas, history: history, context: context)
            }
            #expect(history.undoOnLayer(canvas.activeLayer.id, canvas: canvas), "applying \(applying)")
            #expect(canvas.activeLayer.mask?.buffer.contentHash() == pixels && canvas.flattened().contentHash() == look, "applying \(applying)")
        }
    }

    @Test func mergingALayerShownOnlyOnTheLayerBelowKeepsItsLook() {
        // Merge Down onto its base, and onto another layer clipped to the same base.
        for onClipped in [false, true] {
            let (canvas, history) = picture()
            if onClipped { clippedLayer(canvas, history, color: Pixel(r: 0, g: 200, b: 0, a: 120), rect: IntRect(x: 0, y: 0, width: 24, height: 6)) }
            clippedLayer(canvas, history, color: blue, rect: IntRect(x: 0, y: 0, width: 8, height: 16))
            let look = canvas.flattened().contentHash()
            #expect(LayerActions.mergeDown(canvas: canvas, history: history, context: context))
            #expect(canvas.flattened().contentHash() == look, "onto a clipped layer \(onClipped)")
        }
        // Merge Layers with the clipped layer chosen but not its base: it stays as it is.
        let (canvas, history) = picture()
        clippedLayer(canvas, history, color: blue, rect: IntRect(x: 0, y: 0, width: 8, height: 16))
        LayerActions.add(canvas: canvas, history: history, context: context)
        canvas.activeLayer.buffer.fill(Pixel(r: 0, g: 0, b: 0), in: IntRect(x: 20, y: 0, width: 4, height: 4))
        let look = canvas.flattened().contentHash()
        LayerActions.mergeLayers([canvas.layers[2].id, canvas.layers[3].id], canvas: canvas, history: history, context: context)
        #expect(canvas.flattened().contentHash() == look)
    }

    @Test func alignMovesALayersMaskAndWords() throws {
        let (canvas, history) = picture()
        LayerActions.addMask(.revealAll, canvas: canvas, history: history, context: context)
        canvas.activeLayer.mask!.buffer.fill(.black, in: IntRect(x: 4, y: 4, width: 4, height: 8))
        canvas.editsMask = false
        let before = canvas.flattened()
        LayerAlign.move([canvas.activeLayer.id: IntPoint(x: 10, y: 0)], named: "Align", canvas: canvas, history: history, context: context)
        let after = canvas.flattened()
        // The half the mask hid is still hidden, ten pixels to the right.
        #expect(after[15, 8] == .white && after[19, 8] == before[9, 8] && after[19, 8] != .white)
        // A text layer's words go with its pixels.
        var spec = TextSpec(text: "Hi", origin: Point2D(x: 1, y: 1), fontFamily: "Helvetica Neue", fontSize: 10, color: blue)
        spec.bold = true
        LayerActions.addText(spec, canvas: canvas, history: history, context: context)
        let text = canvas.activeLayer
        LayerAlign.move([text.id: IntPoint(x: 6, y: 2)], named: "Align", canvas: canvas, history: history, context: context)
        let moved = try #require(text.text)
        #expect(moved.spec.origin == Point2D(x: 7, y: 3))
        #expect(text.buffer.contentHash() == moved.drawn(size: canvas.size, colorSpace: canvas.colorSpace).contentHash())
    }

    @Test func droppingBesideALayerKeepsItsClippedLayersOnIt() {
        let (canvas, history) = picture()
        let base = canvas.activeLayer
        clippedLayer(canvas, history, color: blue)
        LayerActions.add(canvas: canvas, history: history, context: context)
        let loose = canvas.activeLayer
        LayerActions.moveLayers([loose.id], to: .below(canvas.layers[0].id), canvas: canvas, history: history, context: context)
        LayerActions.moveLayers([loose.id], to: .above(base.id), canvas: canvas, history: history, context: context)
        #expect(canvas.layers.last === loose)
        LayerActions.moveLayers([loose.id], to: .below(canvas.layers[2].id), canvas: canvas, history: history, context: context)
        #expect(canvas.layers[3].clipsToLayerBelow && canvas.layers[2] === base && canvas.layers[1] === loose)
    }

    @Test func aMaskOnlyHistoryHoldsIsCounted() {
        let (canvas, history) = picture()
        LayerActions.addMask(.hideAll, canvas: canvas, history: history, context: context)
        let before = history.byteCount
        LayerActions.deleteMask(canvas: canvas, history: history, context: context)
        #expect(history.byteCount >= before + canvas.size.width * canvas.size.height * MemoryLayout<Pixel>.stride)
    }
}
