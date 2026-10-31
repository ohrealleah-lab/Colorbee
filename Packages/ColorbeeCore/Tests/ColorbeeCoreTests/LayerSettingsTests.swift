import Foundation
import Testing
@testable import ColorbeeCore

/// Every layer setting survives every path that carries a layer's settings: a layer step and its undo, Undo on
/// Active Layer, a History Snapshot, saving and reopening a project, and copying a layer (review round 11, AE 1).
struct LayerSettingsTests {
    private let context = SelectionContext(color2: .white)

    /// Everything about a layer that a path could drop, spelled out field by field.
    private struct Look: Equatable {
        let id: LayerID, name: String, nameFromWords: Bool, isVisible: Bool, opacity: Double, blendMode: BlendMode
        let isLocked: Bool, locksTransparency: Bool, adjustment: Effect?, clipsToLayerBelow: Bool, isGroup: Bool
        let groupID: LayerID?, passesThrough: Bool, maskEnabled: Bool, text: TextLayer?, pixels: Int, mask: String?

        init(_ layer: Layer) {
            id = layer.id
            name = layer.name
            nameFromWords = layer.nameFromWords
            isVisible = layer.isVisible
            opacity = layer.opacity
            blendMode = layer.blendMode
            isLocked = layer.isLocked
            locksTransparency = layer.locksTransparency
            adjustment = layer.adjustment
            clipsToLayerBelow = layer.clipsToLayerBelow
            isGroup = layer.isGroup
            groupID = layer.groupID
            passesThrough = layer.passesThrough
            maskEnabled = layer.maskEnabled
            text = layer.text
            pixels = layer.buffer.contentHash()
            mask = layer.mask.map { "\($0.name) \($0.buffer.contentHash())" }
        }
    }

    private func look(_ canvas: Canvas) -> [Look] { canvas.layers.map(Look.init) }

    /// A group (not Pass Through) holding a text layer with a mask that's turned off, and an Adjust Photo layer on
    /// "Only the layer below": every setting away from where it starts, on some layer.
    private func everySetting() -> (Canvas, History, text: Layer) {
        let canvas = Canvas(size: IntSize(width: 60, height: 30), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: .max)
        LayerActions.addText(TextSpec(text: "Words", origin: Point2D(x: 4, y: 4), fontFamily: "Helvetica Neue", fontSize: 16, color: .black),
                             canvas: canvas, history: history, context: context)
        let text = canvas.activeLayer
        LayerActions.addAdjustment(.photo(PhotoEdit(adjustments: PhotoAdjustments([.exposure: 20]))), named: "Brighter",
                                   canvas: canvas, history: history, context: context)
        let adjustment = canvas.activeLayer
        LayerActions.group([text.id, adjustment.id], canvas: canvas, history: history, context: context)
        let group = canvas.layers.first { $0.isGroup }!
        group.name = "Folder"
        group.passesThrough = false
        group.opacity = 0.8
        group.blendMode = .screen
        text.opacity = 0.6
        text.blendMode = .multiply
        text.isVisible = false
        text.isLocked = true
        text.locksTransparency = true
        text.mask = Layer(name: "Text Mask", buffer: PixelBuffer(width: 60, height: 30, fill: Pixel(r: 0, g: 0, b: 0, a: 255)))
        text.maskEnabled = false
        adjustment.clipsToLayerBelow = true
        adjustment.opacity = 0.5
        #expect(text.nameFromWords && text.text != nil && adjustment.groupID == group.id)
        return (canvas, history, text)
    }

    /// Every setting on `layer` moved somewhere else.
    private func changeEverything(_ layer: Layer) {
        layer.name = "Renamed"
        layer.isVisible.toggle()
        layer.opacity = 0.3
        layer.blendMode = .difference
        layer.isLocked.toggle()
        layer.locksTransparency.toggle()
        layer.clipsToLayerBelow.toggle()
        layer.passesThrough.toggle()
        layer.maskEnabled.toggle()
        layer.mask = nil
        layer.text = nil
        if layer.adjustment != nil { layer.adjustment = .invert }
    }

    private func layerStep(_ history: History, _ canvas: Canvas, _ change: () -> Void) {
        let edit = history.beginEdit("Change", on: canvas)
        edit.willChangeLayers()
        change()
        history.commit(edit)
    }

    @Test func aLayerStepUndoesEverySetting() {
        let (canvas, history, _) = everySetting()
        let before = look(canvas)
        layerStep(history, canvas) {
            for layer in canvas.layers {
                changeEverything(layer)
                layer.groupID = nil
            }
        }
        #expect(look(canvas) != before)
        history.undo(on: canvas)
        #expect(look(canvas) == before)
    }

    @Test func undoOnActiveLayerPutsBackEverySetting() {
        let (canvas, history, text) = everySetting()
        let before = look(canvas)
        layerStep(history, canvas) { changeEverything(text) }
        #expect(look(canvas) != before)
        #expect(history.undoOnLayer(text.id, canvas: canvas))
        #expect(look(canvas) == before)
    }

    @Test func goingToASnapshotPutsBackEverySetting() throws {
        let (canvas, history, _) = everySetting()
        let before = look(canvas)
        let snapshot = try history.takeSnapshot(named: "Start", of: canvas)
        layerStep(history, canvas) { canvas.layers.forEach(changeEverything) }
        #expect(look(canvas) != before)
        try history.goToSnapshot(snapshot.id, on: canvas)
        #expect(look(canvas) == before)
    }

    @Test func aProjectKeepsEverySetting() throws {
        let (canvas, _, _) = everySetting()
        let reopened = try ProjectFile.decode(ProjectFile.encode(canvas))
        #expect(look(reopened) == look(canvas))
    }

    @Test func aCopyHasEverySetting() {
        let (canvas, _, _) = everySetting()
        for layer in canvas.layers { #expect(Look(layer.copy(buffer: layer.buffer)) == Look(layer)) }
    }
}
