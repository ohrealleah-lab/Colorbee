import ColorbeeCore
import Foundation
import Testing
@testable import Colorbee

/// Editor commands the earlier tests left out: tool sizes, whole-image commands, the layer-only undo and revert,
/// adjustments, and every effect's bar applied and undone.
@MainActor
@Suite(.serialized)
struct EditorCommandTests {
    /// A gradient with a dark block, so every effect and adjustment changes something.
    private func pictureEditor(width: Int = 48, height: Int = 36) -> Editor {
        let editor = makeEditor(width: width, height: height)
        let buffer = editor.canvas.activeLayer.buffer
        for y in 0..<height {
            for x in 0..<width { buffer[x, y] = Pixel(r: UInt8(60 + x * 2), g: UInt8(80 + y * 2), b: UInt8(100 + (x + y) % 40)) }
        }
        buffer.fill(Pixel(r: 20, g: 30, b: 40), in: IntRect(x: 4, y: 4, width: 12, height: 10))
        return editor
    }

    @Test(arguments: [Tool.brush, .shape, .eraser, .stepBadge, .redactBrush, .retouch])
    func toolSizesStayInTheirRange(tool: Tool) {
        let editor = makeEditor()
        editor.selectTool(tool)
        let range = editor.toolSizeRange
        #expect(editor.toolSizePresets.count == 5)
        #expect(editor.toolSizePresets.allSatisfy(range.contains))
        editor.toolSize = 0
        #expect(editor.toolSize == range.lowerBound)
        editor.toolSize = 100_000
        #expect(editor.toolSize == range.upperBound)
        editor.adjustToolSize(larger: true)
        #expect(editor.toolSize == range.upperBound)
        editor.toolSize = range.lowerBound
        editor.adjustToolSize(larger: false)
        #expect(editor.toolSize == range.lowerBound)
        editor.adjustToolSize(larger: true)
        #expect(editor.toolSize! > range.lowerBound)
    }

    @Test func toolsWithoutASizeHaveNone() {
        let editor = makeEditor()
        editor.selectTool(.pencil)
        #expect(editor.toolSize == nil)
        editor.toolSize = 20
        #expect(editor.toolSize == nil)
    }

    @Test func canvasPropertiesChangeTheSizeAndTransparencyAsOneUndo() {
        let editor = pictureEditor()
        let before = editor.imageHash
        editor.applyCanvasProperties(size: IntSize(width: 60, height: 20), transparentBackground: true)
        #expect(editor.canvas.size == IntSize(width: 60, height: 20))
        #expect(editor.canvas.hasTransparentBackground)
        #expect(editor.canvas.activeLayer.buffer[55, 10].a == 0)
        while editor.stepNames.count > 0 { editor.undo() }
        #expect(editor.canvas.size == IntSize(width: 48, height: 36))
        #expect(editor.imageHash == before)
    }

    @Test func resizeAndSkewTheWholeImage() {
        let editor = pictureEditor()
        editor.apply(ResizeSkew(size: IntSize(width: 24, height: 18), horizontalSkew: 0, verticalSkew: 0, resampling: .smooth))
        #expect(editor.canvas.size == IntSize(width: 24, height: 18))
        editor.apply(ResizeSkew(size: IntSize(width: 24, height: 18), horizontalSkew: 20, verticalSkew: 0, resampling: .nearestNeighbor))
        #expect(editor.canvas.size.width > 24)
        editor.undo()
        editor.undo()
        #expect(editor.canvas.size == IntSize(width: 48, height: 36))
    }

    @Test func revertLayerBringsBackTheOpenedPixels() {
        // Revert Layer goes back to the image as opened, so nothing is drawn in before the editor opens it.
        let editor = makeEditor(width: 48, height: 36)
        let opened = editor.imageHash
        editor.selectTool(.pencil)
        editor.stroke([pt(2.5, 30.5), pt(45.5, 30.5)])
        #expect(editor.canRevertLayer)
        editor.revertLayer()
        #expect(editor.imageHash == opened)
        #expect(editor.stepNames.last == "Revert Layer")
        editor.undo()
        #expect(editor.imageHash != opened)
    }

    @Test func undoOnActiveLayerLeavesOtherLayersAlone() {
        let editor = pictureEditor()
        editor.selectTool(.pencil)
        editor.stroke([pt(2.5, 30.5), pt(45.5, 30.5)])
        let backgroundDrawn = editor.canvas.layers[0].buffer.contentHash()
        editor.addLayer()
        editor.stroke([pt(2.5, 20.5), pt(45.5, 20.5)])
        let topDrawn = editor.canvas.layers[1].buffer.contentHash()
        editor.selectLayer(at: 0)
        #expect(editor.undoOnActiveLayerName != nil)
        editor.undoOnActiveLayer()
        #expect(editor.canvas.layers[0].buffer.contentHash() != backgroundDrawn)
        #expect(editor.canvas.layers[1].buffer.contentHash() == topDrawn)
    }

    @Test func autoContrastAndAdjustmentsAreOneStepEach() {
        let editor = pictureEditor()
        let before = editor.imageHash
        editor.autoContrast()
        #expect(editor.stepNames == ["Auto Contrast"])
        editor.applyAdjustment(.invert)
        #expect(editor.stepNames.count == 2)
        editor.undo()
        editor.undo()
        #expect(editor.imageHash == before)
        // A flat image has nothing to stretch.
        let flat = makeEditor()
        flat.autoContrast()
        #expect(flat.stepNames.isEmpty)
    }

    @Test func autoInAdjustPhotoMovesSlidersAndApplies() {
        let editor = pictureEditor()
        let before = editor.imageHash
        editor.beginEffect(.adjustPhoto)
        editor.autoPhoto()
        #expect(!editor.photoAutoMoved.isEmpty)
        editor.applyEffect()
        #expect(editor.imageHash != before)
        editor.undo()
        #expect(editor.imageHash == before)
    }

    @Test func pickingAColorSetsTheWell() {
        let editor = pictureEditor()
        editor.pickColor(at: pt(8, 8), secondary: false, allLayers: false)
        #expect(editor.color1 == Pixel(r: 20, g: 30, b: 40))
        editor.pickColor(at: pt(8, 8), secondary: true, allLayers: false)
        #expect(editor.color2 == Pixel(r: 20, g: 30, b: 40))
    }

    @Test func pastingFloatsAnImageThatPlacesAsOneStep() {
        let editor = pictureEditor()
        let patch = PixelBuffer(width: 6, height: 4, fill: Pixel(r: 250, g: 0, b: 0))
        editor.paste(patch, at: IntPoint(x: 30, y: 20))
        #expect(editor.canvas.selection.floating != nil)
        editor.selectTool(.pencil)
        #expect(editor.canvas.selection.floating == nil)
        #expect(editor.canvas.activeLayer.buffer[32, 21] == Pixel(r: 250, g: 0, b: 0))
    }

    @Test func beforeAfterTurnsOnAndOff() {
        let editor = pictureEditor()
        editor.selectTool(.pencil)
        editor.stroke([pt(2.5, 30.5), pt(45.5, 30.5)])
        editor.toggleComparison()
        #expect(editor.comparison != nil)
        editor.toggleComparison()
        #expect(editor.comparison == nil)
    }

    /// Every effect with a bar: opened, applied at its starting settings, and undone exactly. Color Range waits for a
    /// click, like picking a subject; `SelectionRangeBarTests` covers it.
    @Test(arguments: EffectKind.allCases.filter { ![.pickSubject, .crop, .perspective, .colorRange].contains($0) })
    func everyEffectAppliesAndUndoes(kind: EffectKind) async throws {
        let editor = pictureEditor()
        if kind == .spotlight { editor.selectionDrag(from: pt(10, 10), to: pt(30, 25)) }
        let before = editor.imageHash
        let size = editor.canvas.size
        editor.beginEffect(kind)
        #expect(editor.activeEffect == kind)
        #expect(editor.effectValues.count == kind.parameters.count)
        editor.applyEffect()
        try await waitUntil { editor.activeEffect == nil }
        if editor.stepNames.isEmpty { return }
        while !editor.stepNames.isEmpty { editor.undo() }
        #expect(editor.canvas.size == size)
        #expect(editor.imageHash == before)
    }
}
