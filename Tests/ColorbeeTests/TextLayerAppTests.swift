import ColorbeeCore
import Testing
@testable import Colorbee

/// Text layers in the app (stages 29 and 30), driven as the canvas, the Text options and the Layers panel do.
/// `textIsEditable` is set directly: only the Text options' switch saves it.
@MainActor
struct TextLayerAppTests {
    /// Types `words` in a new box at (4, 4) with the Text tool, and places it.
    private func type(_ words: String, in editor: Editor) {
        editor.selectTool(.text)
        editor.beginText(at: pt(4, 4), wrapWidth: nil)
        editor.updatePendingText(words)
        editor.commitPendingText()
    }

    private func editable() -> Editor {
        let editor = makeEditor(width: 96, height: 48)
        editor.textIsEditable = true
        editor.color1 = .black
        type("Hello", in: editor)
        return editor
    }

    @Test func withEditableOffTextIsPixelsAsBefore() {
        let editor = makeEditor(width: 96, height: 48)
        editor.textIsEditable = false
        type("Hello", in: editor)
        #expect(editor.canvas.layers.count == 1 && !editor.isLayered && editor.stepNames.last == "Text")
    }

    @Test func withEditableOnTextIsALayerAndMakesAProject() {
        let editor = editable()
        #expect(editor.canvas.layers.count == 2 && editor.canvas.activeLayer.text?.spec.text == "Hello")
        #expect(editor.canvas.activeLayer.name == "Hello" && editor.isLayered)
        // The next text goes on a layer of its own, not into this one.
        type("Second", in: editor)
        #expect(editor.canvas.layers.count == 3)
    }

    @Test func doubleClickingOpensTheTextWithItsSettingsAndPlacingRedrawsIt() throws {
        let editor = editable()
        let look = editor.imageHash
        editor.textStyle.fontSize = 40
        editor.color1 = Pixel(r: 0, g: 0, b: 255)
        editor.selectLayer(at: 0)
        #expect(editor.editText(at: pt(8, 12)))
        let pending = try #require(editor.pendingText)
        #expect(pending.string == "Hello" && pending.layerID == editor.canvas.layers[1].id && editor.activeLayerIndex == 1)
        // The box shows the layer's own settings, not the ones last used.
        #expect(editor.textStyle.fontSize == 24 && editor.color1 == .black && editor.editedTextLayerID == pending.layerID)
        editor.updatePendingText("Hello there")
        editor.textStyle.bold = true
        editor.commitPendingText()
        let text = try #require(editor.canvas.layers[1].text)
        #expect(text.spec.text == "Hello there" && text.spec.bold && editor.canvas.layers.count == 2)
        #expect(editor.stepNames.last == "Edit Text" && editor.canvas.layers[1].name == "Hello there")
        editor.undo()
        #expect(editor.imageHash == look && editor.canvas.layers[1].text?.spec.text == "Hello")
        // A double-click away from any text opens nothing.
        #expect(!editor.editText(at: pt(90, 44)))
    }

    @Test func placingWithoutChangesMakesNoStep() {
        let editor = editable()
        let steps = editor.stepNames
        editor.editText(layerAt: 1)
        editor.commitPendingText()
        #expect(editor.stepNames == steps)
    }

    @Test func paintingOnATextLayerAsksToRasterizeFirst() {
        let editor = editable()
        let pixels = editor.canvas.activeLayer.buffer.contentHash()
        editor.selectTool(.brush)
        editor.stroke([pt(2.5, 10.5), pt(60.5, 10.5)])
        #expect(editor.canvas.activeLayer.buffer.contentHash() == pixels && editor.canvas.activeLayer.text != nil)
        #expect(editor.notice?.text.contains("Rasterize Text") == true && !editor.activeLayerTakesEdits)
        editor.rasterizeText()
        #expect(editor.canvas.activeLayer.text == nil && editor.activeLayerTakesEdits && editor.stepNames.last == "Rasterize Text")
        editor.stroke([pt(2.5, 10.5), pt(60.5, 10.5)])
        #expect(editor.canvas.activeLayer.buffer.contentHash() != pixels)
    }

    @Test func theRedactBrushTurnsTheTextIntoPixels() {
        let editor = editable()
        editor.selectTool(.redactBrush)
        editor.beginRedactStroke(at: pt(4, 14), secondary: false)
        editor.continueRedactStroke(to: pt(60, 14), constrain: false)
        editor.endRedactStroke()
        #expect(editor.canvas.layers[1].text == nil && editor.canvas.layers[1].name == "Text")
        editor.undo()
        #expect(editor.canvas.layers[1].text?.spec.text == "Hello")
    }

    @Test func turnedTextSaysWhyItCantBeEdited() {
        let editor = editable()
        editor.apply(Orientation.rotate90Clockwise)
        #expect(editor.editText(layerAt: 1) && editor.pendingText == nil)
        #expect(editor.notice?.text.contains("Turned text") == true)
    }

    @Test func deletingEveryWordRemovesTheLayer() {
        let editor = editable()
        editor.editText(layerAt: 1)
        editor.updatePendingText("")
        editor.commitPendingText()
        #expect(editor.canvas.layers.count == 1 && editor.stepNames.last == "Delete Text")
    }
}
