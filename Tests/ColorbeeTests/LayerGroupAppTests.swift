import ColorbeeCore
import Testing
@testable import Colorbee

/// Layer groups in the app (stages 25 and 26), driven as the Layers panel and the Layer menu do.
@MainActor
struct LayerGroupAppTests {
    /// Paper and three layers: Red, Green and Blue.
    private func layered() -> Editor {
        let editor = makeEditor(width: 16, height: 16)
        for (offset, (name, color)) in [("Red", Pixel(r: 255, g: 0, b: 0)), ("Green", Pixel(r: 0, g: 255, b: 0)), ("Blue", Pixel(r: 0, g: 0, b: 255))].enumerated() {
            editor.addLayer()
            editor.renameLayer(at: editor.activeLayerIndex, to: name)
            editor.canvas.activeLayer.buffer.fill(color, in: IntRect(x: offset * 4, y: 0, width: 8, height: 8))
        }
        return editor
    }

    private func names(_ editor: Editor) -> [String] { editor.canvas.layers.map(\.name) }

    /// Red and Green chosen, then Layer ▸ Group.
    private func grouped() -> Editor {
        let editor = layered()
        editor.chooseLayer(at: 1, extending: false, toggling: false)
        editor.chooseLayer(at: 2, extending: false, toggling: true)
        #expect(editor.canGroupLayers)
        editor.groupLayers()
        return editor
    }

    @Test func groupAndUngroupAreOneStepEach() {
        let editor = grouped()
        #expect(names(editor) == ["Background", "Red", "Green", "Group 1", "Blue"])
        #expect(editor.stepNames.last == "Group Layers" && editor.canvas.activeLayer.isGroup)
        #expect(editor.mergeCommandTitle == "Merge Group" && editor.canUngroupLayers)
        editor.ungroupLayers()
        #expect(names(editor) == ["Background", "Red", "Green", "Blue"] && editor.stepNames.last == "Ungroup")
        editor.undo()
        #expect(names(editor) == ["Background", "Red", "Green", "Group 1", "Blue"])
    }

    @Test func aGroupCantBePaintedOn() {
        let editor = grouped()
        #expect(editor.activeLayerIsLocked && !editor.activeLayerTakesEdits)
        let before = editor.imageHash
        editor.selectTool(.pencil)
        editor.stroke([pt(1.5, 12.5), pt(14.5, 12.5)])
        #expect(editor.imageHash == before)
    }

    @Test func aBlendModeTurnsOffPassThroughAndBack() {
        let editor = grouped()
        let group = editor.canvas.activeLayer
        editor.setBlendMode(.multiply)
        #expect(!group.passesThrough && group.blendMode == .multiply)
        editor.setPassesThrough()
        #expect(group.passesThrough)
        editor.undo()
        #expect(!group.passesThrough)
    }

    @Test func draggingMovesIntoAndOutOfAGroup() {
        let editor = grouped()
        let blue = editor.canvas.layers[4], group = editor.canvas.layers[3]
        editor.moveLayer(blue.id, to: .into(group.id))
        #expect(names(editor) == ["Background", "Red", "Green", "Blue", "Group 1"] && blue.groupID == group.id)
        editor.moveLayer(blue.id, to: .above(group.id))
        #expect(names(editor) == ["Background", "Red", "Green", "Group 1", "Blue"] && blue.groupID == nil)
    }

    @Test func isolatingALayerInAGroupKeepsTheGroupShowing() {
        let editor = grouped()
        editor.toggleIsolation(at: 1)
        #expect(editor.canvas.layers.map(\.isVisible) == [false, true, false, true, false])
        #expect(editor.canvas.isShown(editor.canvas.layers[1]))
    }

    @Test func hidingAGroupHidesItsLayersInThePicture() {
        let editor = grouped()
        let shown = editor.imageHash
        editor.setLayerVisible(false, at: 3)
        #expect(editor.imageHash != shown)
        #expect(!editor.canvas.isShown(editor.canvas.layers[1]) && editor.canvas.layers[1].isVisible)
    }

    @Test func foldingIsOnlyAView() {
        let editor = grouped()
        let steps = editor.stepNames.count
        editor.toggleFold(editor.canvas.activeLayer.id)
        #expect(editor.foldedGroups.contains(editor.canvas.activeLayer.id) && editor.stepNames.count == steps)
    }
}
