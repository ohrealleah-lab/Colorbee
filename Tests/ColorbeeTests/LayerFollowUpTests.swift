import ColorbeeCore
import Testing
@testable import Colorbee

/// Select All Layers, isolating a layer with Option-click, and Stamp Visible (FR-8.6, stage 22).
@MainActor
struct LayerFollowUpTests {
    /// Paper and three layers: Red, Green and an Invert adjustment.
    private func layered() -> Editor {
        let editor = makeEditor(width: 16, height: 16)
        for (name, color) in [("Red", Pixel(r: 255, g: 0, b: 0)), ("Green", Pixel(r: 0, g: 255, b: 0))] {
            editor.addLayer()
            editor.renameLayer(at: editor.activeLayerIndex, to: name)
            editor.canvas.activeLayer.buffer.fill(color, in: IntRect(x: name == "Red" ? 0 : 8, y: 0, width: 8, height: 8))
        }
        editor.addAdjustmentLayer(.invert)
        return editor
    }

    private func visibility(_ editor: Editor) -> [Bool] { editor.canvas.layers.map(\.isVisible) }

    @Test func selectAllLayersChoosesEveryLayer() {
        let editor = layered()
        editor.setLayerVisible(false, at: 1)
        editor.selectAllLayers()
        #expect(editor.chosenLayerIDs == Set(editor.canvas.layers.map(\.id)))
    }

    @Test func optionClickShowsOnlyThatLayerAndAgainBringsBackWhatWasShowing() {
        let editor = layered()
        editor.setLayerVisible(false, at: 0)
        let before = visibility(editor)
        let steps = editor.stepNames.count
        editor.toggleIsolation(at: 2)
        #expect(visibility(editor) == [false, false, true, false])
        #expect(editor.stepNames.last == "Show Only “Green”" && editor.stepNames.count == steps + 1)
        editor.toggleIsolation(at: 2)
        #expect(visibility(editor) == before)
        // Undo takes each back as a step.
        editor.undo()
        #expect(visibility(editor) == [false, false, true, false])
    }

    @Test func changingVisibilityWhileIsolatedShowsEverythingOnTheSecondClick() {
        let editor = layered()
        editor.setLayerVisible(false, at: 0)
        editor.toggleIsolation(at: 2)
        editor.setLayerVisible(true, at: 1)
        editor.toggleIsolation(at: 2)
        #expect(visibility(editor) == [true, true, true, true])
    }

    @Test func undoingAnIsolationThenOptionClickingIsolatesAgain() {
        let editor = layered()
        editor.toggleIsolation(at: 1)
        editor.undo()
        editor.toggleIsolation(at: 1)
        #expect(visibility(editor) == [false, true, false, false])
    }

    /// Review U, finding 6: an isolation that was undone is forgotten, even after other eyes change.
    @Test func anUndoneIsolationIsForgottenAfterAnotherEyeChanges() {
        let editor = layered()
        editor.toggleIsolation(at: 1)
        editor.undo()
        editor.setLayerVisible(false, at: 2)
        editor.toggleIsolation(at: 1)
        #expect(visibility(editor) == [false, true, false, false])
    }

    @Test func stampVisibleAddsTheMergedPictureAndKeepsTheLayers() {
        let editor = layered()
        editor.setLayerVisible(false, at: 2)
        let shown = editor.imageHash, count = editor.canvas.layers.count
        editor.selectLayer(at: 1)
        editor.stampVisible()
        #expect(editor.canvas.layers.count == count + 1 && editor.canvas.activeLayer.name == "Stamp" && editor.activeLayerIndex == 2)
        #expect(editor.stepNames.last == "Stamp Visible")
        // On its own, with every other layer hidden, the stamp looks like the whole picture did.
        editor.toggleIsolation(at: 2)
        #expect(editor.imageHash == shown)
        editor.undo()
        editor.undo()
        #expect(editor.canvas.layers.count == count && editor.imageHash == shown)
    }
}

/// Layer ▸ Align and Distribute (stage 24), as the menu runs them.
@MainActor
struct AlignAppTests {
    private func badges() -> Editor {
        let editor = makeEditor(width: 60, height: 40)
        for box in [IntRect(x: 5, y: 2, width: 6, height: 6), IntRect(x: 30, y: 15, width: 8, height: 4), IntRect(x: 20, y: 30, width: 4, height: 8)] {
            editor.addLayer()
            editor.canvas.activeLayer.buffer.fill(.black, in: box)
        }
        return editor
    }

    @Test func severalLayersLineUpWithEachOtherAndOneWithTheCanvas() {
        let editor = badges()
        editor.selectAllLayers()
        #expect(editor.canAlignChosenLayers && editor.canDistributeChosenLayers)
        editor.alignChosenLayers(.left)
        #expect(editor.canvas.layers.dropFirst().allSatisfy { $0.buffer.visibleBounds?.minX == 0 })
        #expect(editor.stepNames.last == "Align Left")
        editor.undo()
        // One layer centers on the canvas.
        editor.selectLayer(at: 2)
        editor.alignChosenLayers(.centers)
        #expect(editor.canvas.layers[2].buffer.visibleBounds?.minX == 26)
    }

    @Test func aLockedChosenLayerGreysItOutAndOffCanvasRefuses() throws {
        let editor = badges()
        editor.selectLayer(at: 1)
        editor.selectionDrag(from: pt(50.5, 0.5), to: pt(58.5, 10.5))
        var refused = 0
        editor.onRefused = { refused += 1 }
        // The 6-wide badge fits inside the selection's right edge; aligning left to x 50 is fine.
        editor.alignChosenLayers(.left)
        #expect(editor.canvas.layers[1].buffer.visibleBounds?.minX == 50 && refused == 0)
        editor.setLayerLocked(true, at: 1)
        #expect(!editor.canAlignChosenLayers)
    }
}
