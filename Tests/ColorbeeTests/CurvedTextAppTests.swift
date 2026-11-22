import ColorbeeCore
import Foundation
import Testing
@testable import Colorbee

/// Curved text in the app (FR-6.4, stage 35), driven as the canvas and the Text options do. `textIsEditable` is set
/// directly: only the Text options' switch saves it.
@MainActor
struct CurvedTextAppTests {
    private func type(_ words: String, curve: Double, editable: Bool, in editor: Editor) {
        editor.textIsEditable = editable
        editor.selectTool(.text)
        editor.textStyle.curve = curve
        editor.beginText(at: pt(10, 30), wrapWidth: nil)
        editor.updatePendingText(words)
    }

    @Test func curvedTextIsTypedInAStraightBoxAndPlacedBent() throws {
        let editor = makeEditor(width: 240, height: 120)
        type("Hello there", curve: -80, editable: false, in: editor)
        let spec = try #require(editor.pendingText.map(editor.textSpec(for:)))
        #expect(spec.curve == -80)
        // The box with its handles stays the straight one the words are typed in.
        #expect(editor.pendingTextFrame == TextRenderer.layoutBox(for: spec))
        #expect(TextRenderer.box(for: spec) != TextRenderer.layoutBox(for: spec))
        let before = editor.imageHash
        editor.commitPendingText()
        #expect(editor.imageHash != before && editor.canvas.layers.count == 1)
    }

    @Test func aCurvedTextLayerReopensWithItsCurveAndCanChangeIt() throws {
        let editor = makeEditor(width: 240, height: 120)
        type("Hello there", curve: 60, editable: true, in: editor)
        editor.commitPendingText()
        let index = try #require(editor.canvas.layers.firstIndex { $0.text != nil })
        editor.textStyle.curve = 0
        #expect(editor.editText(layerAt: index))
        #expect(editor.textStyle.curve == 60)
        editor.textStyle.curve = -30
        editor.commitPendingText()
        let layer = editor.canvas.layers[index]
        #expect(layer.text?.spec.curve == -30)
        #expect(layer.buffer.contentHash() == layer.text?.drawn(size: editor.canvas.size, colorSpace: editor.canvas.colorSpace).contentHash())
        editor.undo()
        #expect(editor.canvas.layers[index].text?.spec.curve == 60)
    }

    /// A text style saved before Curve existed still opens, with its other settings (stage 35).
    @Test func aTextStyleSavedBeforeCurveKeepsItsSettings() throws {
        var style = TextStyle()
        style.fontFamily = "Georgia"
        style.fontSize = 40
        style.bold = true
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(style)) as? [String: Any])
        json.removeValue(forKey: "curve")
        let old = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(TextStyle.self, from: old)
        #expect(decoded.fontFamily == "Georgia" && decoded.fontSize == 40 && decoded.bold && decoded.curve == 0)
        style.curve = -45
        #expect(try JSONDecoder().decode(TextStyle.self, from: JSONEncoder().encode(style)) == style)
    }
}
