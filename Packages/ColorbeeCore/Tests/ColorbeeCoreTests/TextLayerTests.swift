import Foundation
import Testing
@testable import ColorbeeCore

/// Text layers (FR-6.3, stages 29 and 30): placed text that stays editable, and when it becomes pixels.
struct TextLayerTests {
    private let context = SelectionContext(color2: .white)

    private func spec(_ text: String = "Hello", at origin: Point2D = Point2D(x: 4, y: 6), font: String = "Helvetica Neue") -> TextSpec {
        TextSpec(text: text, origin: origin, fontFamily: font, fontSize: 18, color: Pixel(r: 200, g: 20, b: 20))
    }

    /// White paper with a text layer on it.
    private func picture(_ text: TextSpec? = nil) -> (Canvas, History) {
        let canvas = Canvas(size: IntSize(width: 80, height: 40), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: .max)
        LayerActions.addText(text ?? spec(), canvas: canvas, history: history, context: context)
        return (canvas, history)
    }

    /// The layer's pixels are exactly its text drawn.
    private func matchesItsText(_ layer: Layer, _ canvas: Canvas) -> Bool {
        guard let text = layer.text else { return false }
        return layer.buffer.contentHash() == text.drawn(size: canvas.size, colorSpace: canvas.colorSpace).contentHash()
    }

    @Test func placedTextIsALayerOfItsOwnThatUndoes() throws {
        let (canvas, history) = picture()
        #expect(canvas.layers.count == 2 && canvas.activeLayerIndex == 1)
        let layer = canvas.activeLayer
        #expect(layer.name == "Hello" && matchesItsText(layer, canvas) && !layer.buffer.isUntouched)
        history.undo(on: canvas)
        #expect(canvas.layers.count == 1)
        history.redo(on: canvas)
        #expect(canvas.activeLayer.text?.spec.text == "Hello")
        // Nothing to place, nothing made.
        #expect(!LayerActions.addText(spec(""), canvas: canvas, history: history, context: context))
    }

    @Test func editingDrawsTheTextAgainAndUndoesExactly() throws {
        let (canvas, history) = picture()
        let before = canvas.flattened().contentHash()
        var changed = spec("Goodbye")
        changed.bold = true
        #expect(LayerActions.setText(changed, layerAt: 1, canvas: canvas, history: history, context: context))
        let layer = canvas.layers[1]
        #expect(layer.name == "Goodbye" && layer.text?.spec.bold == true && matchesItsText(layer, canvas))
        #expect(history.undoActionName == "Edit Text")
        // A name you gave it stays.
        LayerActions.update("Rename", layerAt: 1, canvas: canvas, history: history) { $0.name = "Title" }
        #expect(LayerActions.setText(spec("Again"), layerAt: 1, canvas: canvas, history: history, context: context))
        #expect(layer.name == "Title")
        history.undo(on: canvas)
        history.undo(on: canvas)
        history.undo(on: canvas)
        #expect(canvas.flattened().contentHash() == before && layer.text?.spec == spec() && layer.name == "Hello")
        // Deleting every word removes the layer.
        #expect(LayerActions.setText(spec(""), layerAt: 1, canvas: canvas, history: history, context: context))
        #expect(canvas.layers.count == 1)
    }

    @Test func anyPixelChangeMakesItPlainPixelsAndUndoBringsTheTextBack() throws {
        let (canvas, history) = picture()
        let layer = canvas.layers[1]
        let edit = history.beginEdit("Brush", on: canvas)
        edit.willModify(IntRect(x: 0, y: 0, width: 10, height: 10), in: layer)
        layer.buffer.fill(.black, in: IntRect(x: 0, y: 0, width: 10, height: 10))
        history.commit(edit)
        #expect(layer.text == nil)
        history.undo(on: canvas)
        #expect(layer.text?.spec == spec() && matchesItsText(layer, canvas))
        history.redo(on: canvas)
        #expect(layer.text == nil)
    }

    @Test func redactionAlwaysTurnsTheTextIntoPixels() throws {
        let (canvas, history) = picture()
        let layer = canvas.layers[1]
        let box = try #require(SelectionMask.rectangle(IntRect(x: 0, y: 0, width: 80, height: 40), clippedTo: canvas.bounds))
        let outcome = AutoRedact.apply(.solidFill(.black), in: box, canvas: canvas, history: history)
        #expect(outcome == .redacted && layer.text == nil && layer.name == "Text")
        // The saved project has no words left in it.
        let reopened = try ProjectFile.decode(try ProjectFile.encode(canvas))
        #expect(reopened.layers.allSatisfy { $0.text == nil })
        let data = try ProjectFile.encode(canvas)
        #expect(data.range(of: Data("Hello".utf8)) == nil)
        history.undo(on: canvas)
        #expect(layer.text != nil && layer.name == "Hello")
    }

    @Test func rotatingAndFlippingTurnThePixelsAndOnlyUprightTextEdits() throws {
        for seed in UInt64(1)...8 {
            let (canvas, history) = picture()
            let layer = canvas.layers[1]
            var random = SplitMix64(seed: seed)
            for _ in 0..<5 {
                let orientation = Orientation.allCases[random.int(0..<Orientation.allCases.count)]
                ImageActions.transform(orientation, canvas: canvas, history: history, context: context)
            }
            // The text's record of the turns matches the pixels: drawn upright, mirrored, then turned.
            let text = try #require(layer.text)
            var expected = text.drawn(size: text.quarterTurns % 2 == 1 ? IntSize(width: canvas.size.height, height: canvas.size.width) : canvas.size,
                                      colorSpace: canvas.colorSpace)
            if text.mirrored { expected = expected.transformed(.flipHorizontal) }
            for _ in 0..<text.quarterTurns { expected = expected.transformed(.rotate90Clockwise) }
            #expect(expected.contentHash() == layer.buffer.contentHash(), "seed \(seed)")
            #expect(LayerActions.canEditText(of: layer, in: canvas) == text.isUpright, "seed \(seed)")
            if !text.isUpright {
                #expect(!LayerActions.setText(spec("No"), layerAt: 1, canvas: canvas, history: history, context: context))
            }
        }
        // Turning back makes it editable again.
        let (canvas, history) = picture()
        ImageActions.transform(.rotate90Clockwise, canvas: canvas, history: history, context: context)
        ImageActions.transform(.flipHorizontal, canvas: canvas, history: history, context: context)
        ImageActions.transform(.rotate90Clockwise, canvas: canvas, history: history, context: context)
        #expect(canvas.layers[1].text?.isUpright == false)
        ImageActions.transform(.flipHorizontal, canvas: canvas, history: history, context: context)
        #expect(canvas.layers[1].text?.isUpright == true && matchesItsText(canvas.layers[1], canvas))
    }

    @Test func cropCanvasSizeAndResizeKeepTheTextCrispAndEditable() throws {
        let (canvas, history) = picture()
        let layer = canvas.layers[1]
        #expect(ImageActions.crop(to: IntRect(x: 2, y: 3, width: 70, height: 30), canvas: canvas, history: history, context: context))
        #expect(layer.text?.spec.origin == Point2D(x: 2, y: 3) && matchesItsText(layer, canvas))
        #expect(ImageActions.resizeCanvas(to: IntSize(width: 90, height: 50), anchor: .center, canvas: canvas, history: history, context: context))
        #expect(layer.text?.spec.origin == Point2D(x: 12, y: 13) && matchesItsText(layer, canvas))
        #expect(ImageActions.resizeAndSkew(ResizeSkew(size: IntSize(width: 180, height: 100), resampling: .smooth), canvas: canvas, history: history, context: context))
        #expect(layer.text?.spec.fontSize == 36 && layer.text?.spec.origin == Point2D(x: 24, y: 26) && matchesItsText(layer, canvas))
        history.undo(on: canvas)
        history.undo(on: canvas)
        history.undo(on: canvas)
        #expect(layer.text?.spec == spec() && matchesItsText(layer, canvas))
    }

    @Test func skewOrAStretchMakesItPixels() throws {
        let (canvas, history) = picture()
        let layer = canvas.layers[1]
        #expect(ImageActions.resizeAndSkew(ResizeSkew(size: IntSize(width: 160, height: 40), resampling: .smooth), canvas: canvas, history: history, context: context))
        #expect(layer.text == nil)
        history.undo(on: canvas)
        #expect(ImageActions.resizeAndSkew(ResizeSkew(size: canvas.size, horizontalSkew: 10, resampling: .smooth), canvas: canvas, history: history, context: context))
        #expect(layer.text == nil)
        history.undo(on: canvas)
        #expect(layer.text?.spec == spec() && matchesItsText(layer, canvas))
    }

    @Test func aMissingFontKeepsItsPixelsUntilItMustBeScaled() throws {
        let missing = spec(font: "No Such Font Colorbee")
        let (canvas, history) = picture(missing)
        let layer = canvas.layers[1]
        #expect(layer.text?.hasFont == false)
        let pixels = layer.buffer.pixels(in: IntRect(x: 2, y: 3, width: 70, height: 30))
        #expect(ImageActions.crop(to: IntRect(x: 2, y: 3, width: 70, height: 30), canvas: canvas, history: history, context: context))
        #expect(layer.text != nil && layer.buffer.pixels(in: canvas.bounds) == pixels)
        #expect(ImageActions.resizeAndSkew(ResizeSkew(size: IntSize(width: 140, height: 60), resampling: .smooth), canvas: canvas, history: history, context: context))
        #expect(layer.text == nil)
    }

    @Test func mergesFlattenAndRasterizeLeavePlainPixels() {
        for merge in 0..<3 {
            let (canvas, history) = picture()
            let look = canvas.flattened().contentHash()
            switch merge {
            case 0: LayerActions.mergeDown(canvas: canvas, history: history, context: context)
            case 1: LayerActions.flatten(canvas: canvas, history: history, context: context)
            default: LayerActions.rasterizeText(canvas: canvas, history: history, context: context)
            }
            #expect(canvas.layers.allSatisfy { $0.text == nil } && canvas.flattened().contentHash() == look, "merge \(merge)")
            history.undo(on: canvas)
            #expect(canvas.layers[1].text != nil, "merge \(merge)")
        }
        // A merge onto a text layer below makes it pixels too.
        let (canvas, history) = picture()
        LayerActions.add(canvas: canvas, history: history, context: context)
        LayerActions.mergeDown(canvas: canvas, history: history, context: context)
        #expect(canvas.activeLayer.text == nil)
    }

    @Test func projectsSnapshotsAndDuplicatesKeepTheText() throws {
        let (canvas, history) = picture()
        ImageActions.transform(.rotate90Clockwise, canvas: canvas, history: history, context: context)
        LayerActions.duplicate(canvas: canvas, history: history, context: context)
        #expect(canvas.layers[2].text == canvas.layers[1].text)
        let data = try ProjectFile.encode(canvas)
        let reopened = try ProjectFile.decode(data)
        #expect(reopened.layers[1].text == canvas.layers[1].text && reopened.layers[1].text?.quarterTurns == 1)
        #expect(reopened.flattened().contentHash() == canvas.flattened().contentHash())
        let snapshot = try history.takeSnapshot(named: "Turned", of: canvas)
        LayerActions.rasterizeText(canvas: canvas, history: history, context: context)
        try history.goToSnapshot(snapshot.id, on: canvas)
        #expect(canvas.activeLayer.text?.quarterTurns == 1)
    }

    @Test func undoOnActiveLayerTakesBackATextEdit() {
        let (canvas, history) = picture()
        LayerActions.setText(spec("Changed"), layerAt: 1, canvas: canvas, history: history, context: context)
        // A stroke on the paper below, after it.
        let edit = history.beginEdit("Brush", on: canvas)
        edit.willModify(IntRect(x: 70, y: 30, width: 4, height: 4), in: canvas.layers[0])
        canvas.layers[0].buffer.fill(.black, in: IntRect(x: 70, y: 30, width: 4, height: 4))
        history.commit(edit)
        #expect(history.undoOnLayer(canvas.layers[1].id, canvas: canvas))
        #expect(canvas.layers[1].text?.spec.text == "Hello" && matchesItsText(canvas.layers[1], canvas))
        #expect(canvas.layers[0].buffer[71, 31] == .black)
    }

    @Test func randomTextCommandsUndoBackToTheOriginal() throws {
        for seed in UInt64(1)...6 {
            let (canvas, history) = picture()
            var random = SplitMix64(seed: seed)
            let look = canvas.flattened().contentHash()
            let texts = canvas.layers.map(\.text)
            let setUp = history.undoCount
            for step in 0..<30 {
                canvas.activeLayerIndex = random.int(0..<canvas.layers.count)
                switch random.int(0..<8) {
                case 0: LayerActions.addText(spec("Step \(step)", at: Point2D(x: Double(random.int(0..<40)), y: 2)), canvas: canvas, history: history, context: context)
                case 1: LayerActions.setText(spec("Edit \(step)"), layerAt: canvas.activeLayerIndex, canvas: canvas, history: history, context: context)
                case 2: ImageActions.transform(Orientation.allCases[random.int(0..<5)], canvas: canvas, history: history, context: context)
                case 3: ImageActions.crop(to: IntRect(x: 1, y: 1, width: canvas.size.width - 2, height: canvas.size.height - 2), canvas: canvas, history: history, context: context)
                case 4: LayerActions.mergeDown(canvas: canvas, history: history, context: context)
                case 5: LayerActions.rasterizeText(canvas: canvas, history: history, context: context)
                case 6:
                    let edit = history.beginEdit("Brush", on: canvas)
                    edit.willModify(IntRect(x: 0, y: 0, width: 6, height: 6), in: canvas.activeLayer)
                    canvas.activeLayer.buffer.fill(.black, in: IntRect(x: 0, y: 0, width: 6, height: 6))
                    history.commit(edit)
                default: LayerActions.duplicate(canvas: canvas, history: history, context: context)
                }
                // A text layer's pixels are always its words drawn, whenever it's upright.
                for layer in canvas.layers where layer.text?.isUpright == true {
                    #expect(matchesItsText(layer, canvas), "seed \(seed), step \(step)")
                }
            }
            while history.undoCount > setUp { history.undo(on: canvas) }
            #expect(canvas.flattened().contentHash() == look, "seed \(seed)")
            #expect(canvas.layers.map(\.text) == texts, "seed \(seed)")
        }
    }

    @Test func undoingRasterizeTextAfterUndoOnActiveLayerGivesBackJustTheText() throws {
        let (canvas, history) = picture()
        let layer = canvas.layers[1]
        LayerActions.rasterizeText(canvas: canvas, history: history, context: context)
        let edit = history.beginEdit("Brush", on: canvas)
        edit.willModify(IntRect(x: 0, y: 0, width: 10, height: 10), in: layer)
        layer.buffer.fill(.black, in: IntRect(x: 0, y: 0, width: 10, height: 10))
        history.commit(edit)
        #expect(history.undoOnLayer(layer.id, canvas: canvas))
        // Undo everything back: the reversal, then Rasterize Text.
        history.undo(on: canvas)
        history.undo(on: canvas)
        #expect(layer.text != nil && matchesItsText(layer, canvas))
    }
}
