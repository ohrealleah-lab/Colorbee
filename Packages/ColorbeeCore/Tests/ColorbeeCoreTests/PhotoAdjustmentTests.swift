import Foundation
import Testing
@testable import ColorbeeCore

struct LevelsTests {
    @Test func identityChangesNothing() {
        #expect(Levels.identity.table == (0..<256).map { UInt8($0) })
    }

    @Test func blackAndWhitePointsStretchTheRange() {
        let table = Levels(black: 50, white: 200, gamma: 1).table
        #expect(table[0] == 0 && table[50] == 0)
        #expect(table[200] == 255 && table[255] == 255)
        #expect(table[125] == 128)
    }

    @Test func gammaAboveOneLightensTheMidtones() {
        let table = Levels(black: 0, white: 255, gamma: 2).table
        #expect(table[64] == 128)
        #expect(table[0] == 0 && table[255] == 255)
        #expect(Levels(gamma: 0.5).table[128] == 64)
    }

    @Test func autoMakesTheDarkestPixelBlackAndTheLightestWhite() {
        let buffer = PixelBuffer(width: 4, height: 1)
        buffer[0, 0] = Pixel(r: 40, g: 60, b: 80)
        buffer[1, 0] = Pixel(r: 120, g: 130, b: 140)
        buffer[2, 0] = Pixel(r: 190, g: 200, b: 210)
        buffer[3, 0] = Pixel(r: 0, g: 0, b: 0, a: 0)
        let levels = Levels.auto(from: Histogram(buffer))
        #expect(levels == Levels(black: 40, white: 210, gamma: 1))
        let table = levels.table
        #expect(table[40] == 0 && table[210] == 255)
    }

    @Test func autoContrastIsOneUndoStep() {
        let canvas = Canvas(size: IntSize(width: 3, height: 1), colorSpace: Canvas.defaultColorSpace, background: Pixel(r: 100, g: 100, b: 100))
        canvas.activeLayer.buffer[0, 0] = Pixel(r: 50, g: 50, b: 50)
        canvas.activeLayer.buffer[2, 0] = Pixel(r: 150, g: 150, b: 150)
        let history = History(byteBudget: .max)
        let original = canvas.activeLayer.buffer.contentHash()
        let edit = history.beginEdit("Auto Contrast", on: canvas)
        Effects.apply(.levels(Levels.auto(from: Histogram(canvas.activeLayer.buffer))), to: canvas.activeLayer, selection: nil, edit: edit)
        history.commit(edit)
        #expect(canvas.activeLayer.buffer[0, 0] == .black && canvas.activeLayer.buffer[2, 0] == .white)
        history.undo(on: canvas)
        #expect(canvas.activeLayer.buffer.contentHash() == original)
    }

    @Test func histogramCountsOnlyTheSelection() {
        let buffer = PixelBuffer(width: 2, height: 1, fill: .white)
        buffer[0, 0] = .black
        let selection = SelectionMask.rectangle(IntRect(x: 1, y: 0, width: 1, height: 1), clippedTo: buffer.bounds)
        let histogram = Histogram(buffer, selection: selection)
        #expect(histogram.luminance[255] == 1 && histogram.luminance[0] == 0)
        #expect(histogram.lowestValue == 255)
    }
}

struct CurvesTests {
    @Test func aStraightCurveChangesNothing() {
        let tables = Curves.identity.tables
        #expect(tables.red == (0..<256).map { UInt8($0) })
        #expect(tables.blue == tables.red && tables.green == tables.red)
    }

    @Test func theCurvePassesThroughItsPointsWithoutOvershooting() {
        let points = [Curves.Point(x: 0, y: 0), Curves.Point(x: 64, y: 128), Curves.Point(x: 192, y: 200), Curves.Point(x: 255, y: 255)]
        let table = Curves.table(points)
        #expect(table[64] == 128 && table[192] == 200 && table[255] == 255)
        for index in 1..<256 { #expect(table[index] >= table[index - 1]) }
    }

    @Test func flatBeyondTheEndPoints() {
        let table = Curves.table([Curves.Point(x: 30, y: 20), Curves.Point(x: 220, y: 240)])
        #expect(table[0] == 20 && table[30] == 20)
        #expect(table[255] == 240)
    }

    @Test func aChannelCurveThenTheRGBCurve() {
        var curves = Curves.identity
        curves[.red] = [Curves.Point(x: 0, y: 255), Curves.Point(x: 255, y: 0)]
        curves[.rgb] = [Curves.Point(x: 0, y: 0), Curves.Point(x: 255, y: 128)]
        let pixel = Effect.curves(curves).pointwise!(Pixel(r: 0, g: 255, b: 255))
        #expect(pixel.r == 128 && pixel.g == 128 && pixel.b == 128)
    }
}

struct ToneEffectTests {
    @Test func sepiaAtFullTonesAndAtZeroChangesNothing() {
        let gray = Pixel(r: 100, g: 100, b: 100, a: 77)
        #expect(Effect.sepia(amount: 0).pointwise!(gray) == gray)
        let toned = Effect.sepia(amount: 100).pointwise!(gray)
        #expect(toned == Pixel(r: 135, g: 120, b: 94, a: 77))
    }

    @Test func posterizeKeepsOnlyEvenlySpacedValues() {
        let two = Effect.posterize(levels: 2).pointwise!
        #expect(two(Pixel(r: 100, g: 128, b: 200)) == Pixel(r: 0, g: 255, b: 255))
        let four = Effect.posterize(levels: 4).pointwise!
        let values = Set((0..<256).map { four(Pixel(r: UInt8($0), g: 0, b: 0)).r })
        #expect(values == [0, 85, 170, 255])
    }

    @Test func aColorLookupMatchesTheAdjustmentAtItsGridPoints() {
        let effect = Effect.levels(Levels(black: 32, white: 224, gamma: 1.4))
        let lookup = ColorLookup(effect)!
        let transform = effect.pointwise!
        #expect(lookup.size == 33)
        let step = 255.0 / 32
        for (r, g, b) in [(0, 0, 0), (32, 32, 32), (10, 20, 30), (16, 4, 31)] {
            let input = Pixel(r: UInt8((Double(r) * step).rounded()), g: UInt8((Double(g) * step).rounded()), b: UInt8((Double(b) * step).rounded()))
            let index = ((b * 33 + g) * 33 + r) * 4
            #expect(Float(transform(input).r) / 255 == lookup.values[index])
            #expect(Float(transform(input).b) / 255 == lookup.values[index + 2])
        }
        #expect(ColorLookup(.gaussianBlur(radius: 3)) == nil)
    }
}

struct TextureEffectTests {
    private func layer(_ width: Int, _ height: Int, fill: Pixel) -> (Canvas, Layer) {
        let canvas = Canvas(size: IntSize(width: width, height: height), colorSpace: Canvas.defaultColorSpace, background: fill)
        return (canvas, canvas.activeLayer)
    }

    private func apply(_ effect: Effect, to canvas: Canvas, selection: SelectionMask? = nil) {
        let edit = Edit(name: effect.name, canvas: canvas)
        Effects.apply(effect, to: canvas.activeLayer, selection: selection, edit: edit)
    }

    @Test func noiseIsTheSameEveryTimeAndKeepsAlpha() {
        let (a, _) = layer(20, 10, fill: Pixel(r: 128, g: 128, b: 128, a: 200))
        let (b, _) = layer(20, 10, fill: Pixel(r: 128, g: 128, b: 128, a: 200))
        apply(.addNoise(amount: 50, monochrome: false), to: a)
        apply(.addNoise(amount: 50, monochrome: false), to: b)
        #expect(a.activeLayer.buffer.contentHash() == b.activeLayer.buffer.contentHash())
        #expect(a.activeLayer.buffer[3, 3].a == 200)
        let changed = (0..<20).contains { a.activeLayer.buffer[$0, 2] != Pixel(r: 128, g: 128, b: 128, a: 200) }
        #expect(changed)
    }

    @Test func monochromeNoiseMovesEveryChannelTogether() {
        let (canvas, _) = layer(16, 16, fill: Pixel(r: 128, g: 128, b: 128))
        apply(.addNoise(amount: 40, monochrome: true), to: canvas)
        for y in 0..<16 {
            for x in 0..<16 {
                let pixel = canvas.activeLayer.buffer[x, y]
                #expect(pixel.r == pixel.g && pixel.g == pixel.b)
            }
        }
    }

    @Test func noNoiseAtZero() {
        let (canvas, _) = layer(8, 8, fill: Pixel(r: 10, g: 200, b: 90))
        let before = canvas.activeLayer.buffer.contentHash()
        apply(.addNoise(amount: 0, monochrome: false), to: canvas)
        #expect(canvas.activeLayer.buffer.contentHash() == before)
    }

    @Test func horizontalMotionBlurSpreadsADotSideways() {
        let (canvas, layer) = layer(21, 9, fill: .white)
        layer.buffer[10, 4] = .black
        apply(.motionBlur(angle: 0, distance: 5), to: canvas)
        #expect(layer.buffer[8, 4].r < 255 && layer.buffer[12, 4].r < 255)
        #expect(layer.buffer[10, 3] == .white && layer.buffer[10, 5] == .white)
        #expect(layer.buffer[5, 4] == .white)
    }

    @Test func verticalMotionBlurSpreadsADotUpAndDown() {
        let (canvas, layer) = layer(9, 21, fill: .white)
        layer.buffer[4, 10] = .black
        apply(.motionBlur(angle: 90, distance: 5), to: canvas)
        #expect(layer.buffer[4, 8].r < 255 && layer.buffer[4, 12].r < 255)
        #expect(layer.buffer[3, 10] == .white)
    }

    @Test func embossingAFlatImageGivesMidGray() {
        let (canvas, layer) = layer(10, 10, fill: Pixel(r: 30, g: 200, b: 90, a: 180))
        apply(.emboss(angle: 45, depth: 4), to: canvas)
        #expect(layer.buffer[5, 5] == Pixel(r: 128, g: 128, b: 128, a: 180))
    }

    @Test func embossingShowsAnEdgeLightOnOneSideDarkOnTheOther() {
        let (canvas, layer) = layer(10, 4, fill: .black)
        for y in 0..<4 { for x in 5..<10 { layer.buffer[x, y] = .white } }
        apply(.emboss(angle: 0, depth: 2), to: canvas)
        // Lit from the right: the step up to white faces away from the light, so it's dark.
        #expect(layer.buffer[5, 2].r < 128)
        #expect(layer.buffer[1, 2].r == 128 && layer.buffer[8, 2].r == 128)
    }

    @Test func vignetteLeavesTheMiddleAndDarkensTheCorners() {
        let (canvas, layer) = layer(41, 41, fill: .white)
        apply(.vignette(amount: 100, size: 30), to: canvas)
        #expect(layer.buffer[20, 20] == .white)
        #expect(layer.buffer[0, 0].r < 30)
        let (light, lightLayer) = self.layer(41, 41, fill: .black)
        apply(.vignette(amount: -100, size: 30), to: light)
        #expect(lightLayer.buffer[20, 20] == .black && lightLayer.buffer[0, 0].r > 220)
    }

    @Test func effectsStayInsideTheSelectionAndUndoExactly() {
        let (canvas, layer) = layer(30, 20, fill: Pixel(r: 90, g: 120, b: 150))
        for x in 0..<30 { layer.buffer[x, 10] = .black }
        let history = History(byteBudget: .max)
        let original = layer.buffer.contentHash()
        let selection = SelectionMask.rectangle(IntRect(x: 5, y: 5, width: 10, height: 10), clippedTo: canvas.bounds)
        for effect: Effect in [.addNoise(amount: 30, monochrome: false), .motionBlur(angle: 30, distance: 9),
                               .emboss(angle: 120, depth: 5), .vignette(amount: 60, size: 20), .sepia(amount: 80),
                               .posterize(levels: 3), .curves(.identity), .levels(Levels(black: 20, white: 230, gamma: 0.8))] {
            let edit = history.beginEdit(effect.name, on: canvas)
            Effects.apply(effect, to: layer, selection: selection, edit: edit)
            history.commit(edit)
            #expect(layer.buffer[0, 0] == Pixel(r: 90, g: 120, b: 150))
            #expect(layer.buffer[29, 10] == .black)
        }
        while history.canUndo { history.undo(on: canvas) }
        #expect(layer.buffer.contentHash() == original)
    }
}

struct ToneAdjustmentLayerTests {
    private let context = SelectionContext(color2: .white)

    @Test func toneAdjustmentsWorkAsLayersAndReopenFromAProject() throws {
        let canvas = Canvas(size: IntSize(width: 6, height: 6), colorSpace: Canvas.defaultColorSpace, background: Pixel(r: 100, g: 150, b: 200))
        let history = History(byteBudget: .max)
        var curves = Curves.identity
        curves[.green] = [Curves.Point(x: 0, y: 0), Curves.Point(x: 128, y: 200), Curves.Point(x: 255, y: 255)]
        for effect: Effect in [.levels(Levels(black: 10, white: 240, gamma: 1.2)), .curves(curves), .sepia(amount: 40), .posterize(levels: 5)] {
            #expect(Layer.isAdjustable(effect))
            #expect(LayerActions.addAdjustment(effect, named: effect.name, canvas: canvas, history: history, context: context))
        }
        let expected = [Effect.levels(Levels(black: 10, white: 240, gamma: 1.2)), .curves(curves), .sepia(amount: 40), .posterize(levels: 5)]
            .reduce(Pixel(r: 100, g: 150, b: 200)) { $1.pointwise!($0) }
        #expect(canvas.flattened()[2, 2] == expected)
        let reopened = try ProjectFile.decode(ProjectFile.encode(canvas))
        #expect(reopened.layers.map(\.adjustment) == canvas.layers.map(\.adjustment))
        #expect(reopened.flattened().contentHash() == canvas.flattened().contentHash())
        for effect: Effect in [.addNoise(amount: 10, monochrome: true), .motionBlur(angle: 0, distance: 3), .emboss(angle: 0, depth: 1), .vignette(amount: 1, size: 1)] {
            #expect(!Layer.isAdjustable(effect))
        }
    }
}

struct EffectPreviewTests {
    @Test(arguments: [Effect.gaussianBlur(radius: 3), .motionBlur(angle: 30, distance: 9), .vignette(amount: 70, size: 20),
                      .photo(PhotoEdit(adjustments: PhotoAdjustments([.sharpness: 60, .exposure: 20, .vignette: 40]))), .pixelate(cellSize: 5)])
    func aBackgroundPreviewMatchesApplyingDirectly(effect: Effect) {
        func photo() -> Canvas {
            let canvas = Canvas(size: IntSize(width: 40, height: 30), colorSpace: Canvas.defaultColorSpace, background: .white)
            for y in 0..<30 { for x in 0..<40 { canvas.activeLayer.buffer[x, y] = Pixel(r: UInt8(x * 6), g: UInt8(y * 8), b: UInt8((x ^ y) * 4)) } }
            return canvas
        }
        let selection = SelectionMask.ellipse(in: IntRect(x: 5, y: 4, width: 26, height: 20), clippedTo: IntRect(x: 0, y: 0, width: 40, height: 30))!
        for regions in [nil, selection.connectedRegions()] as [[SelectionMask]?] {
            let direct = photo()
            let directEdit = Edit(name: "Direct", canvas: direct)
            if let regions { Effects.apply(effect, to: direct.activeLayer, regions: regions, edit: directEdit) } else { Effects.apply(effect, to: direct.activeLayer, selection: nil, edit: directEdit) }

            let previewed = photo()
            let source = previewed.activeLayer.buffer.copy()
            let edit = Edit(name: "Preview", canvas: previewed)
            EffectPreview.render(effect, from: source, regions: regions)?.write(into: previewed.activeLayer, edit: edit)
            #expect(previewed.activeLayer.buffer.contentHash() == direct.activeLayer.buffer.contentHash())
            edit.restoreOriginals()
            #expect(previewed.activeLayer.buffer.contentHash() == source.contentHash())
        }
    }
}
