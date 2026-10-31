import ColorbeeCore
import Testing
@testable import Colorbee

/// Layer masks in the app (stages 27 to 28b), driven as the Layers panel and the Layer menu do.
@MainActor
struct LayerMaskAppTests {
    private let red = Pixel(r: 255, g: 0, b: 0)

    /// Paper and a red layer over everything.
    private func picture() -> Editor {
        let editor = makeEditor(width: 32, height: 32)
        editor.addLayer()
        editor.canvas.activeLayer.buffer.fill(red, in: editor.canvas.bounds)
        return editor
    }

    @Test func paintingBlackOnTheMaskHidesTheLayer() {
        let editor = picture()
        editor.addMask()
        #expect(editor.editsMask && editor.stepNames.last == "Add Layer Mask")
        let layerPixels = editor.canvas.activeLayer.buffer.contentHash()
        editor.selectTool(.pencil)
        editor.color1 = .black
        editor.stroke([pt(2.5, 10.5), pt(29.5, 10.5)])
        // The stroke went on the mask: the layer's own pixels are as they were, and the picture shows paper there.
        #expect(editor.canvas.activeLayer.buffer.contentHash() == layerPixels)
        #expect(editor.canvas.flattened()[10, 10] == paper && editor.canvas.flattened()[10, 20] == red)
        // Back to the layer: the next stroke paints pixels.
        editor.paint(onMask: false, at: editor.activeLayerIndex)
        #expect(!editor.editsMask)
        editor.color1 = Pixel(r: 0, g: 0, b: 255)
        editor.stroke([pt(2.5, 20.5), pt(29.5, 20.5)])
        #expect(editor.canvas.activeLayer.buffer.contentHash() != layerPixels)
    }

    @Test func whileAMaskIsChosenColorsAreGraysAndDSwapsThem() {
        let editor = picture()
        editor.color1 = Pixel(r: 255, g: 0, b: 0)
        editor.addMask()
        #expect(editor.color1 == Pixel(r: 54, g: 54, b: 54))
        editor.resetColors()
        #expect(editor.color1 == .white && editor.color2 == .black)
        editor.selectLayer(at: 0)
        #expect(!editor.editsMask)
    }

    @Test func aMaskMakesThePictureAProject() {
        let editor = makeEditor(width: 16, height: 16)
        #expect(!editor.isLayered)
        editor.addMask()
        #expect(editor.isLayered)
    }

    @Test func shiftClickTurnsTheMaskOffAndOptionClickShowsItAlone() {
        let editor = picture()
        editor.addMask(hidingAll: true)
        #expect(editor.canvas.flattened()[5, 5] == paper)
        editor.toggleMaskEnabled()
        #expect(editor.canvas.flattened()[5, 5] == red && editor.stepNames.last == "Turn Off Layer Mask")
        editor.toggleMaskAlone(at: editor.activeLayerIndex)
        #expect(editor.showsMaskAlone)
        editor.selectLayer(at: 0)
        #expect(!editor.showsMaskAlone)
    }
}
