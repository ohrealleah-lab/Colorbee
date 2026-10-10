import simd
import Testing
@testable import ColorbeeCore

struct BlendModeTests {
    private let gray = SIMD3<Float>(repeating: 0.5)

    private func close(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Bool {
        simd_reduce_max(abs(a - b)) < 1e-5
    }

    @Test func separableModesMatchTheSpec() {
        let b = SIMD3<Float>(0.2, 0.5, 0.8), s = SIMD3<Float>(0.6, 0.5, 0.1)
        #expect(BlendMode.normal.blend(b, s) == s)
        #expect(BlendMode.multiply.blend(b, s) == b * s)
        #expect(BlendMode.screen.blend(b, s) == b + s - b * s)
        #expect(BlendMode.darken.blend(b, s) == SIMD3<Float>(0.2, 0.5, 0.1))
        #expect(BlendMode.lighten.blend(b, s) == SIMD3<Float>(0.6, 0.5, 0.8))
        #expect(BlendMode.difference.blend(b, s) == abs(b - s))
        #expect(close(BlendMode.additive.blend(b, s), SIMD3<Float>(0.8, 1, 0.9)))
        // Overlay is Hard Light with the layers swapped.
        #expect(BlendMode.overlay.blend(b, s) == BlendMode.hardLight.blend(s, b))
    }

    @Test func dodgeAndBurnHandleTheirEdgeCases() {
        #expect(BlendMode.colorDodge.blend(.zero, gray) == .zero)
        #expect(BlendMode.colorDodge.blend(gray, SIMD3(repeating: 1)) == SIMD3<Float>(repeating: 1))
        #expect(BlendMode.colorBurn.blend(SIMD3<Float>(repeating: 1), gray) == SIMD3<Float>(repeating: 1))
        #expect(BlendMode.colorBurn.blend(gray, .zero) == .zero)
    }

    @Test func softLightWithMiddleGrayChangesNothing() {
        let b = SIMD3<Float>(0.1, 0.4, 0.9)
        #expect(close(BlendMode.softLight.blend(b, gray), b))
    }

    @Test func luminosityKeepsTheBackdropHueAndTakesTheSourceLightness() {
        let red = SIMD3<Float>(1, 0, 0), white = SIMD3<Float>(1, 1, 1), black = SIMD3<Float>(0, 0, 0)
        #expect(close(BlendMode.luminosity.blend(red, white), white))
        #expect(close(BlendMode.luminosity.blend(red, black), black))
        // Color takes the source's hue and saturation over a gray backdrop's lightness.
        let colored = BlendMode.color.blend(gray, red)
        #expect(colored.x > colored.y && abs(colored.y - colored.z) < 1e-5)
        // Saturation from a gray source removes all color.
        let desaturated = BlendMode.saturation.blend(SIMD3<Float>(0.8, 0.2, 0.2), gray)
        #expect(simd_reduce_max(desaturated) - simd_reduce_min(desaturated) < 1e-5)
    }

    @Test func blendingOntoTransparencyIsPlainOver() {
        for mode in BlendMode.allCases {
            var backdrop = SIMD4<Float>.zero
            Compositing.blend(&backdrop, Pixel(r: 200, g: 40, b: 10), opacity: 1, mode: mode)
            #expect(Compositing.pixel(backdrop) == Pixel(r: 200, g: 40, b: 10))
        }
    }

    @Test func normalBlendMatchesOver() {
        let base = Pixel(r: 10, g: 200, b: 90, a: 180), top = Pixel(r: 250, g: 20, b: 60, a: 120)
        var backdrop = Compositing.premultiplied(base)
        Compositing.blend(&backdrop, top, opacity: 0.5, mode: .normal)
        let expected = Compositing.over(base, top, coverage: 0.5)
        let actual = Compositing.pixel(backdrop)
        for (a, e) in [(actual.r, expected.r), (actual.g, expected.g), (actual.b, expected.b), (actual.a, expected.a)] {
            #expect(abs(Int(a) - Int(e)) <= 1)
        }
    }
}

struct LayerActionTests {
    private let red = Pixel(r: 255, g: 0, b: 0)
    private let gray = Pixel(r: 128, g: 128, b: 128)
    private let context = SelectionContext(color2: .white)

    private func makeCanvas() -> (Canvas, History) {
        (Canvas(size: IntSize(width: 8, height: 8), colorSpace: Canvas.defaultColorSpace, background: .white), History(byteBudget: .max))
    }

    @Test func addingALayerPutsATransparentOneAboveAndSelectsIt() {
        let (canvas, history) = makeCanvas()
        #expect(LayerActions.add(canvas: canvas, history: history, context: context))
        #expect(canvas.layers.count == 2)
        #expect(canvas.activeLayerIndex == 1)
        #expect(canvas.activeLayer.name == "Layer 1")
        #expect(canvas.activeLayer.buffer[3, 3] == .clear)
        LayerActions.add(canvas: canvas, history: history, context: context)
        #expect(canvas.activeLayer.name == "Layer 2")
        history.undo(on: canvas)
        history.undo(on: canvas)
        #expect(canvas.layers.count == 1)
        history.redo(on: canvas)
        #expect(canvas.layers.count == 2 && canvas.activeLayer.name == "Layer 1")
    }

    @Test func deleteRefusesTheLastLayerAndLockedLayers() {
        let (canvas, history) = makeCanvas()
        #expect(!LayerActions.delete(canvas: canvas, history: history, context: context))
        LayerActions.add(canvas: canvas, history: history, context: context)
        canvas.activeLayer.isLocked = true
        #expect(!LayerActions.delete(canvas: canvas, history: history, context: context))
        canvas.activeLayer.isLocked = false
        #expect(LayerActions.delete(canvas: canvas, history: history, context: context))
        #expect(canvas.layers.count == 1 && canvas.activeLayerIndex == 0)
    }

    @Test func undoingADeleteBringsBackTheSameLayerAndPixels() {
        let (canvas, history) = makeCanvas()
        LayerActions.add(canvas: canvas, history: history, context: context)
        let layer = canvas.activeLayer
        layer.buffer.fill(red, in: IntRect(x: 0, y: 0, width: 4, height: 4))
        LayerActions.delete(canvas: canvas, history: history, context: context)
        history.undo(on: canvas)
        #expect(canvas.layers[1] === layer)
        #expect(canvas.layers[1].buffer[1, 1] == red)
        #expect(canvas.activeLayerIndex == 1)
    }

    @Test func mergeDownKeepsTheLookAndUndoes() {
        let (canvas, history) = makeCanvas()
        let base = canvas.layers[0].buffer
        LayerActions.add(canvas: canvas, history: history, context: context)
        canvas.activeLayer.buffer.fill(gray, in: canvas.bounds)
        canvas.activeLayer.blendMode = .multiply
        canvas.layers[0].buffer.fill(red, in: IntRect(x: 0, y: 0, width: 4, height: 8))
        let before = canvas.flattened().contentHash()
        #expect(LayerActions.mergeDown(canvas: canvas, history: history, context: context))
        #expect(canvas.layers.count == 1)
        #expect(canvas.flattened().contentHash() == before)
        #expect(canvas.layers[0].buffer[1, 1] == Pixel(r: 128, g: 0, b: 0))
        history.undo(on: canvas)
        #expect(canvas.layers.count == 2)
        #expect(canvas.layers[0].buffer === base)
        #expect(canvas.layers[1].blendMode == .multiply)
    }

    @Test func mergeDownRefusesLockedLayersAndTheBottomLayer() {
        let (canvas, history) = makeCanvas()
        #expect(!LayerActions.mergeDown(canvas: canvas, history: history, context: context))
        LayerActions.add(canvas: canvas, history: history, context: context)
        canvas.layers[0].isLocked = true
        #expect(!LayerActions.mergeDown(canvas: canvas, history: history, context: context))
    }

    @Test func mergeVisibleKeepsHiddenLayers() {
        let (canvas, history) = makeCanvas()
        LayerActions.add(canvas: canvas, history: history, context: context)
        canvas.activeLayer.buffer.fill(red, in: IntRect(x: 0, y: 0, width: 2, height: 2))
        LayerActions.add(canvas: canvas, history: history, context: context)
        canvas.activeLayer.isVisible = false
        let before = canvas.flattened().contentHash()
        #expect(LayerActions.mergeVisible(canvas: canvas, history: history, context: context))
        #expect(canvas.layers.count == 2)
        #expect(!canvas.layers[1].isVisible)
        #expect(canvas.flattened().contentHash() == before)
    }

    @Test func flattenDropsHiddenLayersAndUndoes() {
        let (canvas, history) = makeCanvas()
        LayerActions.add(canvas: canvas, history: history, context: context)
        canvas.activeLayer.buffer.fill(red, in: IntRect(x: 0, y: 0, width: 2, height: 2))
        canvas.activeLayer.opacity = 0.5
        LayerActions.add(canvas: canvas, history: history, context: context)
        canvas.activeLayer.isVisible = false
        let before = canvas.flattened().contentHash()
        #expect(LayerActions.flatten(canvas: canvas, history: history, context: context))
        #expect(canvas.layers.count == 1)
        #expect(canvas.flattened().contentHash() == before)
        history.undo(on: canvas)
        #expect(canvas.layers.count == 3)
        #expect(canvas.layers[1].opacity == 0.5)
    }

    @Test func movingALayerKeepsTheActiveLayerActive() {
        let (canvas, history) = makeCanvas()
        LayerActions.add(canvas: canvas, history: history, context: context)
        LayerActions.add(canvas: canvas, history: history, context: context)
        let active = canvas.activeLayer
        #expect(LayerActions.move(from: 2, to: 0, canvas: canvas, history: history, context: context))
        #expect(canvas.layers[0] === active)
        #expect(canvas.activeLayer === active)
        history.undo(on: canvas)
        #expect(canvas.layers[2] === active)
    }

    @Test func settingsChangesAreStepsButUnchangedOnesAreNot() {
        let (canvas, history) = makeCanvas()
        #expect(LayerActions.update("Rename", layerAt: 0, canvas: canvas, history: history) { $0.name = "Paper" })
        #expect(!LayerActions.update("Rename", layerAt: 0, canvas: canvas, history: history) { $0.name = "Paper" })
        LayerActions.update("Hide", layerAt: 0, canvas: canvas, history: history) { $0.isVisible = false }
        history.undo(on: canvas)
        #expect(canvas.layers[0].isVisible)
        history.undo(on: canvas)
        #expect(canvas.layers[0].name == "Background")
    }

    @Test func erasingOnlyLeavesColor2OnTheBackgroundAtTheBottom() {
        let (canvas, history) = makeCanvas()
        LayerActions.add(canvas: canvas, history: history, context: context)
        #expect(canvas.vacatedFill(for: canvas.layers[0], color2: red) == red)
        #expect(canvas.vacatedFill(for: canvas.layers[1], color2: red) == .clear)
        LayerActions.move(from: 0, to: 1, canvas: canvas, history: history, context: context)
        #expect(canvas.vacatedFill(for: canvas.layers[1], color2: red) == .clear)
        #expect(canvas.vacatedFill(for: canvas.layers[0], color2: red) == .clear)
    }

    @Test func layerStepsOverTheBudgetSpillTheirLayersAndStillUndoExactly() {
        let side = 200
        let canvas = Canvas(size: IntSize(width: side, height: side), colorSpace: Canvas.defaultColorSpace, background: .white)
        // About three layers' worth, so older merged-away layers have to leave memory.
        let history = History(byteBudget: 3 * side * side * 4)
        var random = SplitMix64(seed: 7)
        func paint() {
            let edit = history.beginEdit("Paint", on: canvas)
            let rect = IntRect(x: random.int(0..<side / 2), y: random.int(0..<side / 2), width: random.int(1..<side / 2), height: random.int(1..<side / 2))
            edit.willModify(rect, in: canvas.activeLayer)
            canvas.activeLayer.buffer.fill(Pixel(r: random.byte(), g: random.byte(), b: random.byte(), a: random.byte()), in: rect)
            history.commit(edit)
        }
        let blank = canvas.flattened().contentHash()
        paint()
        // The image after each round, by how many steps it took to get there.
        var checkpoints: [Int: Int] = [:]
        for round in 0..<6 {
            LayerActions.add(canvas: canvas, history: history, context: context)
            paint()
            LayerActions.add(canvas: canvas, history: history, context: context)
            paint()
            if round % 2 == 0 {
                LayerActions.mergeDown(canvas: canvas, history: history, context: context)
            } else {
                LayerActions.flatten(canvas: canvas, history: history, context: context)
            }
            checkpoints[history.undoCount] = canvas.flattened().contentHash()
        }
        // Over budget only by the newest steps, which never spill.
        #expect(history.byteCount <= history.byteBudget + 4 * side * side * 4)
        let final = canvas.flattened().contentHash()

        while history.canUndo {
            history.undo(on: canvas)
            if let expected = checkpoints[history.undoCount] { #expect(canvas.flattened().contentHash() == expected) }
        }
        #expect(canvas.layers.count == 1)
        #expect(canvas.flattened().contentHash() == blank)
        while history.canRedo {
            history.redo(on: canvas)
            if let expected = checkpoints[history.undoCount] { #expect(canvas.flattened().contentHash() == expected) }
        }
        #expect(canvas.flattened().contentHash() == final)
    }

    /// Budgets from tiny (everything spills) to roomy (the crop stays in memory while the layer is written out).
    @Test(arguments: [1, 2, 3, 4, 5, 6])
    func aBufferSharedByALayerStepAndACropSurvivesSpilling(budgetInLayers: Int) {
        let side = 120
        let canvas = Canvas(size: IntSize(width: side, height: side), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: budgetInLayers * side * side * 4)
        var checkpoints: [Int: Int] = [:]
        func mark() { checkpoints[history.undoCount] = canvas.flattened().contentHash() }
        func paint(_ value: UInt8) {
            let edit = history.beginEdit("Paint", on: canvas)
            let rect = IntRect(x: Int(value) % 40, y: 10, width: 50, height: 60)
            edit.willModify(rect, in: canvas.activeLayer)
            canvas.activeLayer.buffer.fill(Pixel(r: value, g: 255 - value, b: 90), in: rect)
            history.commit(edit)
            mark()
        }
        mark()
        LayerActions.add(canvas: canvas, history: history, context: context); mark()
        paint(30)
        LayerActions.mergeDown(canvas: canvas, history: history, context: context); mark()
        // A layer step whose record holds the merged buffer, then a crop that keeps the same buffer.
        LayerActions.update("Blend Mode", layerAt: 0, canvas: canvas, history: history) { $0.blendMode = .multiply }; mark()
        ImageActions.crop(to: IntRect(x: 5, y: 5, width: 100, height: 90), canvas: canvas, history: history, context: context); mark()
        for value in stride(from: 40, to: 200, by: 20) { paint(UInt8(value)) }

        while history.canUndo {
            history.undo(on: canvas)
            #expect(canvas.flattened().contentHash() == checkpoints[history.undoCount])
        }
        while history.canRedo {
            history.redo(on: canvas)
            #expect(canvas.flattened().contentHash() == checkpoints[history.undoCount])
        }
    }

    @Test func randomLayerAndPixelEditsUndoBackToTheOriginal() {
        let (canvas, history) = makeCanvas()
        canvas.layers[0].buffer.fill(gray, in: IntRect(x: 2, y: 2, width: 3, height: 3))
        let original = canvas.flattened().contentHash()
        var random = SplitMix64(seed: 99)
        for step in 0..<60 {
            switch Int.random(in: 0..<8, using: &random) {
            case 0: LayerActions.add(canvas: canvas, history: history, context: context)
            case 1: LayerActions.duplicate(canvas: canvas, history: history, context: context)
            case 2: LayerActions.delete(canvas: canvas, history: history, context: context)
            case 3: LayerActions.mergeDown(canvas: canvas, history: history, context: context)
            case 4:
                let mode = BlendMode.allCases[step % BlendMode.allCases.count]
                LayerActions.update("Blend Mode", layerAt: canvas.activeLayerIndex, canvas: canvas, history: history) { $0.blendMode = mode }
            case 5:
                let count = canvas.layers.count
                LayerActions.move(from: step % count, to: (step * 7) % count, canvas: canvas, history: history, context: context)
            case 6: LayerActions.flatten(canvas: canvas, history: history, context: context)
            default:
                let edit = history.beginEdit("Paint", on: canvas)
                let area = IntRect(x: step % 6, y: (step * 3) % 6, width: 2, height: 2)
                edit.willModify(area, in: canvas.activeLayer)
                canvas.activeLayer.buffer.fill(Pixel(r: UInt8(step * 4), g: 90, b: 200), in: area)
                history.commit(edit)
            }
        }
        while history.canUndo { history.undo(on: canvas) }
        #expect(canvas.layers.count == 1)
        #expect(canvas.flattened().contentHash() == original)
    }
}

struct AdjustmentLayerTests {
    private let red = Pixel(r: 255, g: 0, b: 0)
    private let context = SelectionContext(color2: .white)

    private func makeCanvas() -> (Canvas, History) {
        (Canvas(size: IntSize(width: 8, height: 8), colorSpace: Canvas.defaultColorSpace, background: .white), History(byteBudget: .max))
    }

    @Test func anAdjustmentLayerChangesWhatsBelowWithoutTouchingIt() {
        let (canvas, history) = makeCanvas()
        #expect(LayerActions.addAdjustment(.invert, named: "Invert", canvas: canvas, history: history, context: context))
        #expect(canvas.flattened()[3, 3] == .black)
        #expect(canvas.layers[0].buffer[3, 3] == .white)
    }

    @Test func opacityFadesTheAdjustmentIn() {
        let (canvas, history) = makeCanvas()
        LayerActions.addAdjustment(.invert, named: "Invert", canvas: canvas, history: history, context: context)
        canvas.activeLayer.opacity = 0.5
        let pixel = canvas.flattened()[3, 3]
        #expect(abs(Int(pixel.r) - 128) <= 1 && pixel.r == pixel.g && pixel.a == 255)
    }

    @Test func layersAboveAnAdjustmentAreNotAdjusted() {
        let (canvas, history) = makeCanvas()
        LayerActions.addAdjustment(.invert, named: "Invert", canvas: canvas, history: history, context: context)
        LayerActions.add(canvas: canvas, history: history, context: context)
        canvas.activeLayer.buffer.fill(red, in: IntRect(x: 0, y: 0, width: 2, height: 2))
        let flat = canvas.flattened()
        #expect(flat[0, 0] == red)
        #expect(flat[5, 5] == .black)
    }

    @Test func hiddenAdjustmentsDoNothing() {
        let (canvas, history) = makeCanvas()
        LayerActions.addAdjustment(.invert, named: "Invert", canvas: canvas, history: history, context: context)
        canvas.activeLayer.isVisible = false
        #expect(canvas.flattened()[3, 3] == .white)
    }

    @Test func applyAdjustmentBakesItIntoTheLayerBelowAndUndoes() {
        let (canvas, history) = makeCanvas()
        LayerActions.addAdjustment(.brightnessContrast(brightness: -50, contrast: 0), named: "Darker", canvas: canvas, history: history, context: context)
        let looks = canvas.flattened().contentHash()
        #expect(LayerActions.applyAdjustment(canvas: canvas, history: history, context: context))
        #expect(canvas.layers.count == 1)
        #expect(canvas.flattened().contentHash() == looks)
        #expect(canvas.layers[0].buffer[1, 1].r < 255)
        history.undo(on: canvas)
        #expect(canvas.layers.count == 2)
        #expect(canvas.layers[0].buffer[1, 1] == .white)
    }

    // Leah's "Cant Copy" project: a cut-out subject over a background, with an adjustment on top. Baking it into
    // the subject alone left the background unadjusted.
    @Test func applyAdjustmentKeepsTheLookOverSeveralLayersAndUndoesInOneStep() {
        let (canvas, history) = makeCanvas()
        LayerActions.add(canvas: canvas, history: history, context: context)
        canvas.activeLayer.buffer.fill(red, in: IntRect(x: 0, y: 0, width: 4, height: 4))
        canvas.activeLayer.opacity = 0.5
        LayerActions.add(canvas: canvas, history: history, context: context)
        canvas.activeLayer.isVisible = false
        LayerActions.addAdjustment(.invert, named: "Invert", canvas: canvas, history: history, context: context)
        LayerActions.add(canvas: canvas, history: history, context: context)
        canvas.activeLayer.buffer.fill(red, in: IntRect(x: 6, y: 6, width: 2, height: 2))
        canvas.activeLayerIndex = 3
        let looks = canvas.flattened().contentHash()
        let before = canvas.layers.map(\.id)
        let undoCount = history.undoCount

        #expect(LayerActions.applyAdjustment(canvas: canvas, history: history, context: context))
        #expect(canvas.flattened().contentHash() == looks)
        // The merged layer at the bottom, the hidden layer kept, the layer above untouched.
        #expect(canvas.layers.map(\.id) == [before[0], before[2], before[4]])
        #expect(canvas.activeLayerIndex == 0)
        #expect(canvas.layers[0].adjustment == nil && canvas.layers[0].opacity == 1)
        #expect(canvas.layers[0].buffer[7, 7] == .black)
        #expect(canvas.layers[1].isVisible == false)
        #expect(history.undoCount == undoCount + 1)

        history.undo(on: canvas)
        #expect(canvas.layers.map(\.id) == before)
        #expect(canvas.layers[0].buffer[7, 7] == .white)
        #expect(canvas.flattened().contentHash() == looks)
    }

    @Test func applyAdjustmentNeedsAVisibleAdjustmentAndUnlockedLayersBelow() {
        let (canvas, history) = makeCanvas()
        LayerActions.addAdjustment(.invert, named: "Invert", canvas: canvas, history: history, context: context)
        #expect(LayerActions.canApplyAdjustment(canvas))
        canvas.activeLayer.isVisible = false
        #expect(!LayerActions.canApplyAdjustment(canvas))
        canvas.activeLayer.isVisible = true
        canvas.layers[0].isLocked = true
        #expect(!LayerActions.canApplyAdjustment(canvas))
        canvas.layers[0].isVisible = false
        #expect(!LayerActions.canApplyAdjustment(canvas))
    }

    @Test func mergeDownOnAnAdjustmentAppliesIt() {
        let (canvas, history) = makeCanvas()
        LayerActions.addAdjustment(.invert, named: "Invert", canvas: canvas, history: history, context: context)
        #expect(LayerActions.mergeDown(canvas: canvas, history: history, context: context))
        #expect(canvas.layers[0].buffer[1, 1] == .black)
    }

    @Test func pixelsCantMergeIntoAnAdjustmentLayer() {
        let (canvas, history) = makeCanvas()
        LayerActions.addAdjustment(.invert, named: "Invert", canvas: canvas, history: history, context: context)
        LayerActions.add(canvas: canvas, history: history, context: context)
        #expect(!LayerActions.canMergeDown(canvas))
    }

    @Test func changingTheSettingsIsAnUndoableStep() {
        let (canvas, history) = makeCanvas()
        LayerActions.addAdjustment(.brightnessContrast(brightness: 0, contrast: 0), named: "B/C", canvas: canvas, history: history, context: context)
        LayerActions.update("Adjustment", layerAt: 1, canvas: canvas, history: history) { $0.adjustment = .brightnessContrast(brightness: 40, contrast: 0) }
        #expect(canvas.layers[1].adjustment == .brightnessContrast(brightness: 40, contrast: 0))
        history.undo(on: canvas)
        #expect(canvas.layers[1].adjustment == .brightnessContrast(brightness: 0, contrast: 0))
    }

    @Test func aBlurAdjustmentSoftensAnEdge() {
        let (canvas, history) = makeCanvas()
        canvas.layers[0].buffer.fill(.black, in: IntRect(x: 0, y: 0, width: 4, height: 8))
        LayerActions.addAdjustment(.gaussianBlur(radius: 1), named: "Blur", canvas: canvas, history: history, context: context)
        let edge = canvas.flattened()[4, 4]
        #expect(edge.r > 0 && edge.r < 255)
        #expect(canvas.layers[0].buffer[4, 4] == .white)
    }

    @Test func flattenAppliesAdjustments() {
        let (canvas, history) = makeCanvas()
        LayerActions.addAdjustment(.invert, named: "Invert", canvas: canvas, history: history, context: context)
        LayerActions.flatten(canvas: canvas, history: history, context: context)
        #expect(canvas.layers.count == 1)
        #expect(canvas.layers[0].adjustment == nil)
        #expect(canvas.layers[0].buffer[2, 2] == .black)
    }
}

struct UndoOnLayerTests {
    private let red = Pixel(r: 255, g: 0, b: 0)
    private let blue = Pixel(r: 0, g: 0, b: 255)
    private let context = SelectionContext(color2: .white)

    private func makeCanvas() -> (Canvas, History) {
        let canvas = Canvas(size: IntSize(width: 8, height: 8), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: .max)
        LayerActions.add(canvas: canvas, history: history, context: context)
        return (canvas, history)
    }

    private func paint(_ color: Pixel, layer index: Int, canvas: Canvas, history: History, area: IntRect = IntRect(x: 0, y: 0, width: 4, height: 4)) {
        let layer = canvas.layers[index]
        let edit = history.beginEdit("Paint", on: canvas)
        edit.willModify(area, in: layer)
        layer.buffer.fill(color, in: area)
        history.commit(edit)
    }

    @Test func takesBackOnlyTheActiveLayersLastChange() {
        let (canvas, history) = makeCanvas()
        paint(red, layer: 0, canvas: canvas, history: history)
        paint(blue, layer: 1, canvas: canvas, history: history)
        canvas.activeLayerIndex = 0
        #expect(history.undoOnLayerActionName(canvas.layers[0].id, canvas: canvas) == "Paint")
        #expect(history.undoOnLayer(canvas.layers[0].id, canvas: canvas))
        #expect(canvas.layers[0].buffer[1, 1] == .white)
        #expect(canvas.layers[1].buffer[1, 1] == blue)
        // It's a step of its own: ⌘Z brings the change back.
        #expect(history.undoActionName == "Undo Paint")
        history.undo(on: canvas)
        #expect(canvas.layers[0].buffer[1, 1] == red)
        #expect(canvas.layers[1].buffer[1, 1] == blue)
    }

    @Test func isUnavailableWhenTheChangeAlsoTouchedAnotherLayer() {
        let (canvas, history) = makeCanvas()
        let edit = history.beginEdit("Both", on: canvas)
        for layer in canvas.layers {
            edit.willModify(IntRect(x: 0, y: 0, width: 2, height: 2), in: layer)
            layer.buffer.fill(red, in: IntRect(x: 0, y: 0, width: 2, height: 2))
        }
        history.commit(edit)
        #expect(history.undoOnLayerActionName(canvas.layers[0].id, canvas: canvas) == nil)
        #expect(!history.undoOnLayer(canvas.layers[0].id, canvas: canvas))
    }

    @Test func isUnavailableAcrossAWholeCanvasChange() {
        let (canvas, history) = makeCanvas()
        paint(red, layer: 0, canvas: canvas, history: history)
        ImageActions.crop(to: IntRect(x: 0, y: 0, width: 6, height: 6), canvas: canvas, history: history, context: context)
        #expect(history.undoOnLayerActionName(canvas.layers[0].id, canvas: canvas) == nil)
    }

    @Test func undoesASettingChangeOnTheLayerAlone() {
        let (canvas, history) = makeCanvas()
        LayerActions.update("Layer Opacity", layerAt: 0, canvas: canvas, history: history) { $0.opacity = 0.3 }
        paint(blue, layer: 1, canvas: canvas, history: history)
        #expect(history.undoOnLayer(canvas.layers[0].id, canvas: canvas))
        #expect(canvas.layers[0].opacity == 1)
        #expect(canvas.layers[1].buffer[1, 1] == blue)
        history.undo(on: canvas)
        #expect(canvas.layers[0].opacity == 0.3)
    }

    @Test func aMergeThatInvolvedTheLayerBlocksIt() {
        let (canvas, history) = makeCanvas()
        paint(red, layer: 1, canvas: canvas, history: history)
        LayerActions.mergeDown(canvas: canvas, history: history, context: context)
        #expect(history.undoOnLayerActionName(canvas.layers[0].id, canvas: canvas) == nil)
    }
}
