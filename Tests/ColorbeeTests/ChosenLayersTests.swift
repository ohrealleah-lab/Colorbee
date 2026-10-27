import ColorbeeCore
import Testing
@testable import Colorbee

/// Choosing several layers in the Layers panel (FR-8.6), driven as the panel does.
@MainActor
struct ChosenLayersTests {
    /// A background and three layers, "Layer 1" to "Layer 3", with Layer 1 active.
    private func editor() -> Editor {
        let editor = makeEditor(width: 8, height: 8)
        for _ in 0..<3 { editor.addLayer() }
        editor.selectLayer(at: 1)
        return editor
    }

    private func chosenNames(_ editor: Editor) -> Set<String> {
        Set(editor.canvas.layers.filter { editor.chosenLayerIDs.contains($0.id) }.map(\.name))
    }

    @Test func shiftClickChoosesARangeAndTheClickedLayerIsActive() {
        let editor = editor()
        editor.chooseLayer(at: 3, extending: true, toggling: false)
        #expect(chosenNames(editor) == ["Layer 1", "Layer 2", "Layer 3"])
        #expect(editor.canvas.activeLayer.name == "Layer 3")
        // A second Shift-click still starts from Layer 1.
        editor.chooseLayer(at: 2, extending: true, toggling: false)
        #expect(chosenNames(editor) == ["Layer 1", "Layer 2"])
    }

    @Test func commandClickAddsAndTakesAway() {
        let editor = editor()
        editor.chooseLayer(at: 3, extending: false, toggling: true)
        #expect(chosenNames(editor) == ["Layer 1", "Layer 3"])
        editor.chooseLayer(at: 3, extending: false, toggling: true)
        #expect(chosenNames(editor) == ["Layer 1"])
        #expect(editor.canvas.activeLayer.name == "Layer 1")
        // The last chosen layer stays chosen.
        editor.chooseLayer(at: 1, extending: false, toggling: true)
        #expect(chosenNames(editor) == ["Layer 1"])
    }

    @Test func aPlainClickChoosesOneAgain() {
        let editor = editor()
        editor.chooseLayer(at: 3, extending: true, toggling: false)
        editor.chooseLayer(at: 3, extending: false, toggling: false)
        #expect(chosenNames(editor) == ["Layer 3"])
    }

    @Test func mergeDownBecomesMergeLayers() {
        let editor = editor()
        #expect(editor.mergeCommandTitle == "Merge Down")
        editor.chooseLayer(at: 3, extending: false, toggling: true)
        #expect(editor.mergeCommandTitle == "Merge Layers" && editor.canMerge)
        editor.mergeDown()
        #expect(editor.canvas.layers.map(\.name) == ["Background", "Layer 2", "Layer 3"])
        #expect(chosenNames(editor) == ["Layer 3"])
        editor.undo()
        #expect(editor.canvas.layers.count == 4 && !editor.hasSeveralChosenLayers)
    }

    @Test func deleteAndDuplicateWorkOnEveryChosenLayer() {
        let editor = editor()
        editor.chooseLayer(at: 3, extending: false, toggling: true)
        editor.duplicateLayer()
        #expect(editor.canvas.layers.map(\.name) == ["Background", "Layer 1", "Layer 1 copy", "Layer 2", "Layer 3", "Layer 3 copy"])
        #expect(chosenNames(editor) == ["Layer 1 copy", "Layer 3 copy"])
        editor.deleteLayer()
        #expect(editor.canvas.layers.map(\.name) == ["Background", "Layer 1", "Layer 2", "Layer 3"])
    }

    @Test func draggingAChosenLayerBringsTheOthers() {
        let editor = editor()
        editor.chooseLayer(at: 3, extending: false, toggling: true)
        editor.moveLayer(from: 3, to: 0)
        #expect(editor.canvas.layers.map(\.name) == ["Layer 1", "Layer 3", "Background", "Layer 2"])
        #expect(chosenNames(editor) == ["Layer 1", "Layer 3"])
    }

    @Test func opacityBlendModeHideAndLockChangeEveryChosenLayer() {
        let editor = editor()
        editor.chooseLayer(at: 3, extending: false, toggling: true)
        editor.previewOpacity(0.4)
        editor.finishLayerSettings()
        editor.setBlendMode(.screen)
        editor.toggleChosenLayersVisible()
        editor.toggleChosenLayersLocked()
        for layer in editor.canvas.layers {
            let chosen = ["Layer 1", "Layer 3"].contains(layer.name)
            #expect((layer.opacity == 0.4) == chosen && (layer.blendMode == .screen) == chosen)
            #expect(layer.isVisible != chosen && layer.isLocked == chosen)
        }
    }

    @Test func aLockedChosenLayerKeepsItsOpacityAndBlocksMerge() {
        let editor = editor()
        editor.canvas.layers[3].isLocked = true
        editor.chooseLayer(at: 3, extending: false, toggling: true)
        editor.chooseLayer(at: 1, extending: false, toggling: true)
        editor.chooseLayer(at: 1, extending: false, toggling: true)
        #expect(editor.canvas.activeLayer.name == "Layer 1")
        editor.previewOpacity(0.5)
        editor.finishLayerSettings()
        #expect(editor.canvas.layers[1].opacity == 0.5 && editor.canvas.layers[3].opacity == 1)
        #expect(!editor.canMerge && !editor.canDeleteLayers)
    }

    @Test func rightClickingALayerThatIsntChosenChoosesItAlone() {
        let editor = editor()
        editor.chooseLayer(at: 2, extending: false, toggling: true)
        editor.chooseForMenu(layerAt: 2)
        #expect(chosenNames(editor) == ["Layer 1", "Layer 2"])
        editor.chooseForMenu(layerAt: 3)
        #expect(chosenNames(editor) == ["Layer 3"])
    }

    @Test func addingALayerChoosesJustIt() {
        let editor = editor()
        editor.chooseLayer(at: 3, extending: false, toggling: true)
        editor.addLayer()
        #expect(chosenNames(editor) == ["Layer 4"])
    }
}
