import Testing
@testable import ColorbeeCore

/// Commands on several chosen layers (FR-8.6).
struct SeveralLayerActionTests {
    private let red = Pixel(r: 255, g: 0, b: 0)
    private let green = Pixel(r: 0, g: 255, b: 0)
    private let gray = Pixel(r: 128, g: 128, b: 128)
    private let context = SelectionContext(color2: .white)

    /// A white background and `count` empty layers above it, "Layer 1" upward.
    private func makeCanvas(layers count: Int) -> (Canvas, History) {
        let canvas = Canvas(size: IntSize(width: 8, height: 8), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: .max)
        for _ in 0..<count { LayerActions.add(canvas: canvas, history: history, context: context) }
        return (canvas, history)
    }

    private func ids(_ canvas: Canvas, _ indices: Int...) -> Set<LayerID> { Set(indices.map { canvas.layers[$0].id }) }
    private func names(_ canvas: Canvas) -> [String] { canvas.layers.map(\.name) }

    // MARK: Merge Layers

    @Test func mergingKeepsTheLookAndTakesTheTopLayersName() {
        let (canvas, history) = makeCanvas(layers: 2)
        canvas.layers[0].buffer.fill(red, in: IntRect(x: 0, y: 0, width: 4, height: 8))
        canvas.layers[1].buffer.fill(gray, in: canvas.bounds)
        canvas.layers[1].blendMode = .multiply
        canvas.layers[2].buffer.fill(green, in: IntRect(x: 6, y: 6, width: 2, height: 2))
        canvas.layers[2].opacity = 0.5
        let before = canvas.flattened().contentHash()
        #expect(LayerActions.mergeLayers(ids(canvas, 0, 1, 2), canvas: canvas, history: history, context: context))
        #expect(names(canvas) == ["Layer 2"])
        #expect(canvas.flattened().contentHash() == before)
        #expect(canvas.layers[0].opacity == 1 && canvas.layers[0].blendMode == .normal)
        history.undo(on: canvas)
        #expect(names(canvas) == ["Background", "Layer 1", "Layer 2"])
        #expect(canvas.layers[1].blendMode == .multiply && canvas.layers[2].opacity == 0.5)
    }

    @Test func theMergedLayerSitsWhereTheTopChosenLayerWas() {
        let (canvas, history) = makeCanvas(layers: 3)
        // Layer 1 and Layer 3 chosen; Layer 2 between them stays where it is.
        #expect(LayerActions.mergeLayers(ids(canvas, 1, 3), canvas: canvas, history: history, context: context))
        #expect(names(canvas) == ["Background", "Layer 2", "Layer 3"])
        #expect(canvas.activeLayerIndex == 2)
    }

    @Test func aMergeFromTheBottomStaysTheBackground() {
        let (canvas, history) = makeCanvas(layers: 2)
        let background = canvas.layers[0].id
        #expect(LayerActions.mergeLayers(ids(canvas, 0, 1), canvas: canvas, history: history, context: context))
        #expect(names(canvas) == ["Layer 1", "Layer 2"])
        #expect(canvas.layers[0].id == background && canvas.backgroundLayerID == background)
    }

    @Test func hiddenChosenLayersStayAsTheyAre() {
        let (canvas, history) = makeCanvas(layers: 3)
        canvas.layers[2].isVisible = false
        #expect(LayerActions.mergeLayers(ids(canvas, 1, 2, 3), canvas: canvas, history: history, context: context))
        #expect(names(canvas) == ["Background", "Layer 2", "Layer 3"])
        #expect(!canvas.layers[1].isVisible && canvas.layers[2].isVisible)
    }

    @Test func mergingNeedsTwoVisibleLayersWithPixelsAndNothingLocked() {
        let (canvas, history) = makeCanvas(layers: 2)
        let revision = history.revision
        #expect(!LayerActions.canMergeLayers(ids(canvas, 1), in: canvas))
        canvas.layers[2].isVisible = false
        #expect(!LayerActions.canMergeLayers(ids(canvas, 1, 2), in: canvas))
        canvas.layers[2].isVisible = true
        canvas.layers[2].isLocked = true
        #expect(!LayerActions.mergeLayers(ids(canvas, 1, 2), canvas: canvas, history: history, context: context))
        // A locked chosen layer blocks the merge even when hidden.
        canvas.layers[2].isVisible = false
        #expect(!LayerActions.canMergeLayers(ids(canvas, 0, 1, 2), in: canvas))
        #expect(canvas.layers.count == 3 && history.revision == revision)
    }

    @Test func twoAdjustmentLayersAloneDontMerge() {
        let (canvas, history) = makeCanvas(layers: 0)
        LayerActions.addAdjustment(.invert, named: "Invert", canvas: canvas, history: history, context: context)
        LayerActions.addAdjustment(.desaturate, named: "Desaturate", canvas: canvas, history: history, context: context)
        #expect(!LayerActions.canMergeLayers(ids(canvas, 1, 2), in: canvas))
    }

    @Test func aChosenAdjustmentIsBakedIntoTheChosenLayersBelowIt() {
        let (canvas, history) = makeCanvas(layers: 1)
        canvas.layers[1].buffer.fill(red, in: IntRect(x: 0, y: 0, width: 2, height: 2))
        LayerActions.addAdjustment(.invert, named: "Invert", canvas: canvas, history: history, context: context)
        #expect(LayerActions.mergeLayers(ids(canvas, 1, 2), canvas: canvas, history: history, context: context))
        #expect(names(canvas) == ["Background", "Invert"])
        #expect(canvas.layers[1].adjustment == nil)
        // The red is inverted; the background, not chosen, no longer is.
        #expect(canvas.flattened()[0, 0] == Pixel(r: 0, g: 255, b: 255))
        #expect(canvas.flattened()[5, 5] == .white)
    }

    @Test func aChosenLayersClippedAdjustmentsGoWithIt() {
        let (canvas, history) = makeCanvas(layers: 2)
        canvas.layers[1].buffer.fill(red, in: IntRect(x: 0, y: 0, width: 2, height: 2))
        canvas.activeLayerIndex = 1
        LayerActions.addAdjustment(.invert, named: "Invert", canvas: canvas, history: history, context: context)
        canvas.layers[2].clipsToLayerBelow = true
        let before = canvas.flattened().contentHash()
        #expect(LayerActions.mergeLayers(ids(canvas, 1, 3), canvas: canvas, history: history, context: context))
        #expect(names(canvas) == ["Background", "Layer 2"])
        #expect(canvas.flattened().contentHash() == before)
    }

    // MARK: Delete, Duplicate, Move

    @Test func deletingRemovesEveryChosenLayerInOneStep() {
        let (canvas, history) = makeCanvas(layers: 3)
        #expect(LayerActions.deleteLayers(ids(canvas, 1, 3), canvas: canvas, history: history, context: context))
        #expect(names(canvas) == ["Background", "Layer 2"])
        #expect(canvas.activeLayerIndex == 0)
        history.undo(on: canvas)
        #expect(names(canvas) == ["Background", "Layer 1", "Layer 2", "Layer 3"])
    }

    @Test func deletingKeepsALayerAndRefusesLockedOnes() {
        let (canvas, history) = makeCanvas(layers: 1)
        #expect(!LayerActions.canDeleteLayers(ids(canvas, 0, 1), in: canvas))
        canvas.layers[1].isLocked = true
        #expect(!LayerActions.deleteLayers(ids(canvas, 1), canvas: canvas, history: history, context: context))
        #expect(canvas.layers.count == 2)
    }

    @Test func duplicatingCopiesEachChosenLayerAboveItself() throws {
        let (canvas, history) = makeCanvas(layers: 2)
        canvas.activeLayerIndex = 1
        let copies = try #require(LayerActions.duplicateLayers(ids(canvas, 1, 2), canvas: canvas, history: history, context: context))
        #expect(names(canvas) == ["Background", "Layer 1", "Layer 1 copy", "Layer 2", "Layer 2 copy"])
        #expect(Set(copies) == ids(canvas, 2, 4))
        #expect(canvas.activeLayer.name == "Layer 1 copy")
        history.undo(on: canvas)
        #expect(canvas.layers.count == 3)
    }

    @Test func movingKeepsTheChosenLayersTogetherInOrder() {
        let (canvas, history) = makeCanvas(layers: 4)
        canvas.activeLayerIndex = 3
        let chosen = ids(canvas, 1, 3)
        // Dragging Layer 3 to the top: Layer 1 comes along, just below it.
        #expect(LayerActions.moveLayers(chosen, dragging: 3, to: 4, canvas: canvas, history: history, context: context))
        #expect(names(canvas) == ["Background", "Layer 2", "Layer 4", "Layer 1", "Layer 3"])
        #expect(canvas.activeLayer.name == "Layer 3")
        // Dragging Layer 1 to the bottom.
        #expect(LayerActions.moveLayers(chosen, dragging: 3, to: 0, canvas: canvas, history: history, context: context))
        #expect(names(canvas) == ["Layer 1", "Layer 3", "Background", "Layer 2", "Layer 4"])
        history.undo(on: canvas)
        history.undo(on: canvas)
        #expect(names(canvas) == ["Background", "Layer 1", "Layer 2", "Layer 3", "Layer 4"])
    }

    @Test func aMoveThatChangesNothingIsNoStep() {
        let (canvas, history) = makeCanvas(layers: 2)
        let revision = history.revision
        #expect(!LayerActions.moveLayers(ids(canvas, 1, 2), dragging: 2, to: 2, canvas: canvas, history: history, context: context))
        #expect(history.revision == revision)
    }

    // MARK: Settings

    @Test func settingsChangeOnEveryChosenLayerInOneStep() {
        let (canvas, history) = makeCanvas(layers: 3)
        #expect(LayerActions.update("Layer Opacity", layersWithIDs: ids(canvas, 1, 3), canvas: canvas, history: history) { $0.opacity = 0.25 })
        #expect(canvas.layers.map(\.opacity) == [1, 0.25, 1, 0.25])
        history.undo(on: canvas)
        #expect(canvas.layers.allSatisfy { $0.opacity == 1 })
    }
}
