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

    // MARK: Text layers and redaction safety

    private func textPicture(_ words: String = "Card 4111") -> (Canvas, History) {
        let canvas = Canvas(size: IntSize(width: 90, height: 40), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: .max)
        LayerActions.addText(TextSpec(text: words, origin: Point2D(x: 4, y: 4), fontFamily: "Helvetica Neue", fontSize: 14, color: .black),
                             canvas: canvas, history: history, context: context)
        return (canvas, history)
    }

    private func redactEverything(_ canvas: Canvas, _ history: History) {
        let all = SelectionMask.rectangle(canvas.bounds, clippedTo: canvas.bounds)!
        _ = AutoRedact.apply(.solidFill(.black), in: all, canvas: canvas, history: history)
    }

    @Test func noRedactedWordsSurviveInAName() throws {
        // A copy, a layer made pixels first, and a mask's name.
        for way in 0..<3 {
            let (canvas, history) = textPicture()
            switch way {
            case 0: LayerActions.duplicate(canvas: canvas, history: history, context: context)
            case 1: LayerActions.rasterizeText(canvas: canvas, history: history, context: context)
            default:
                LayerActions.addMask(.revealAll, canvas: canvas, history: history, context: context)
                canvas.editsMask = false
            }
            redactEverything(canvas, history)
            let names = canvas.layers.flatMap { [$0.name] + ($0.mask.map { [$0.name] } ?? []) }
            #expect(!names.contains { $0.contains("4111") }, "way \(way): \(names)")
            #expect(try ProjectFile.encode(canvas).range(of: Data("4111".utf8)) == nil, "way \(way)")
            history.undo(on: canvas)
            #expect(canvas.layers.last?.name.contains("4111") == true, "way \(way)")
        }
        // A name typed by hand is the person's own, and other pixel changes never rename.
        let (canvas, history) = textPicture()
        LayerActions.update("Rename", layerAt: 1, canvas: canvas, history: history) { $0.name = "Mine" }
        redactEverything(canvas, history)
        #expect(canvas.layers[1].name == "Mine")
        let (other, otherHistory) = textPicture()
        let edit = otherHistory.beginEdit("Brush", on: other)
        edit.willModify(IntRect(x: 0, y: 0, width: 4, height: 4), in: other.layers[1])
        otherHistory.commit(edit)
        #expect(other.layers[1].text == nil && other.layers[1].name == "Card 4111")
    }

    @Test func aCancelledRedactionPreviewPutsTheTextBack() {
        let (canvas, history) = textPicture()
        let layer = canvas.layers[1]
        let edit = history.beginEdit("Blur", on: canvas)
        edit.isRedaction = true
        edit.willModify(canvas.bounds, in: layer)
        #expect(layer.text == nil && layer.name == "Text")
        edit.restoreOriginals()
        #expect(layer.text?.spec.text == "Card 4111" && layer.name == "Card 4111" && layer.nameFromWords)
    }

    @Test func aCropThatCutsTextOffMakesItPixels() {
        let (canvas, history) = textPicture()
        #expect(ImageActions.crop(to: IntRect(x: 0, y: 0, width: 30, height: 40), canvas: canvas, history: history, context: context))
        #expect(canvas.layers[1].text == nil)
        #expect(ImageActions.resizeCanvas(to: IntSize(width: 120, height: 40), canvas: canvas, history: history, context: context))
        #expect(canvas.layers[1].text == nil)
        history.undo(on: canvas)
        history.undo(on: canvas)
        #expect(canvas.layers[1].text?.spec.text == "Card 4111")
    }

    @Test func redactionIgnoresLockTransparentPixels() {
        let (canvas, history) = textPicture()
        canvas.layers[1].locksTransparency = true
        redactEverything(canvas, history)
        // No letter's outline is left: the whole layer is solid.
        #expect(canvas.layers[1].buffer.pixels(in: canvas.bounds).allSatisfy { $0.a == 255 })
    }

    @Test func deletingEveryWordTakesTheTextsClippedLayersAlong() {
        let (canvas, history) = textPicture()
        LayerActions.addAdjustment(.invert, named: "Invert", canvas: canvas, history: history, context: context)
        canvas.activeLayer.clipsToLayerBelow = true
        let look = Canvas(size: canvas.size, colorSpace: canvas.colorSpace, background: .white).flattened().contentHash()
        var empty = canvas.layers[1].text!.spec
        empty.text = ""
        #expect(LayerActions.setText(empty, layerAt: 1, canvas: canvas, history: history, context: context))
        #expect(canvas.layers.count == 1 && canvas.flattened().contentHash() == look)
    }

    @Test func undoingACropPastAMaskBroughtBackOutOfOrderDoesntCrash() {
        let (canvas, history) = picture()
        let look = canvas.flattened().contentHash()
        #expect(ImageActions.crop(to: IntRect(x: 2, y: 2, width: 16, height: 10), canvas: canvas, history: history, context: context))
        LayerActions.addMask(.revealAll, canvas: canvas, history: history, context: context)
        #expect(history.undoOnLayer(canvas.activeLayer.id, canvas: canvas))
        history.undo(on: canvas)
        #expect(canvas.activeLayer.mask != nil)
        history.undo(on: canvas)
        #expect(canvas.size == IntSize(width: 24, height: 16) && canvas.activeLayer.mask?.buffer.size == canvas.size)
        #expect(canvas.flattened().contentHash() == look)
    }
}

/// The monkey test's thumbnail and export finds (2026-10-31).
struct MonkeyThumbnailTests {
    private let context = SelectionContext(color2: .white)

    @Test func thumbnailsBlendAdjustmentsAsTheExportDoes() {
        for mode in [BlendMode.luminosity, .softLight, .difference, .darken, .colorBurn] {
            let canvas = Canvas(size: IntSize(width: 12, height: 8), colorSpace: Canvas.defaultColorSpace, background: Pixel(r: 30, g: 40, b: 60))
            let history = History(byteBudget: .max)
            canvas.layers[0].buffer.fill(Pixel(r: 200, g: 120, b: 40), in: IntRect(x: 0, y: 0, width: 6, height: 8))
            LayerActions.addAdjustment(.invert, named: "Invert", canvas: canvas, history: history, context: context)
            canvas.activeLayer.blendMode = mode
            let flat = canvas.flattened().pixels(in: canvas.bounds), thumbnail = canvas.thumbnail(maxSide: 12).pixels
            let apart = zip(flat, thumbnail).map { a, b in max(abs(Int(a.r) - Int(b.r)), abs(Int(a.g) - Int(b.g)), abs(Int(a.b) - Int(b.b))) }.max()!
            #expect(apart <= 2, "\(mode)")
        }
    }

    @Test func aLayerShownOnlyOnAHiddenLayerShowsNowhere() {
        let canvas = Canvas(size: IntSize(width: 8, height: 8), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: .max)
        LayerActions.add(canvas: canvas, history: history, context: context)
        canvas.activeLayer.buffer.fill(.black, in: canvas.bounds)
        canvas.activeLayer.clipsToLayerBelow = true
        canvas.layers[0].isVisible = false
        #expect(canvas.flattened().pixels(in: canvas.bounds).allSatisfy { $0.a == 0 })
    }

    @Test func mergeAdjustmentOverAnAdjustmentAtTheBottomDoesntCrash() {
        let canvas = Canvas(size: IntSize(width: 8, height: 8), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: .max)
        LayerActions.addAdjustment(.invert, named: "Invert", canvas: canvas, history: history, context: context)
        LayerActions.add(canvas: canvas, history: history, context: context)
        canvas.activeLayer.buffer.fill(Pixel(r: 200, g: 30, b: 30), in: IntRect(x: 0, y: 0, width: 4, height: 8))
        LayerActions.addAdjustment(.desaturate, named: "Desaturate", canvas: canvas, history: history, context: context)
        canvas.layers[0].isVisible = false
        let look = canvas.flattened().contentHash()
        #expect(LayerActions.applyAdjustment(canvas: canvas, history: history, context: context))
        #expect(canvas.flattened().contentHash() == look)
    }
}
