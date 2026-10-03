import Foundation
import Testing
@testable import ColorbeeCore

struct AdjustPhotoTests {
    private typealias S = PhotoAdjustments.Slider
    private func adjusted(_ values: [S: Double], _ pixel: Pixel) -> Pixel {
        PhotoAdjustments(values).colorTransform(pixel)
    }

    @Test func neutralChangesNothing() {
        let transform = PhotoAdjustments().colorTransform
        for value in stride(from: 0, through: 255, by: 17) {
            let pixel = Pixel(r: UInt8(value), g: UInt8(255 - value), b: UInt8(value / 2), a: 99)
            #expect(transform(pixel) == pixel)
        }
    }

    @Test func eachLightSliderMovesTheRightWay() {
        let mid = Pixel(r: 120, g: 120, b: 120)
        #expect(adjusted([.exposure: 50], mid).r > 120)
        #expect(adjusted([.exposure: -50], mid).r < 120)
        #expect(adjusted([.brightness: 50], mid).r > 120)
        #expect(adjusted([.brightness: 50], .black) == .black && adjusted([.brightness: 50], .white) == .white)
        #expect(adjusted([.contrast: 50], Pixel(r: 200, g: 200, b: 200)).r > 200)
        #expect(adjusted([.contrast: 50], Pixel(r: 60, g: 60, b: 60)).r < 60)
        #expect(adjusted([.blackPoint: 100], Pixel(r: 50, g: 50, b: 50)).r == 0)
        #expect(adjusted([.blackPoint: -100], .black).r > 50)
    }

    @Test func highlightsAndShadowsWorkOnTheirOwnTones() {
        let bright = Pixel(r: 230, g: 230, b: 230), dark = Pixel(r: 25, g: 25, b: 25)
        #expect(adjusted([.highlights: -80], bright).r < 220)
        #expect(adjusted([.highlights: -80], dark) == dark)
        #expect(adjusted([.shadows: 80], dark).r > 40)
        #expect(adjusted([.shadows: 80], bright) == bright)
    }

    @Test func colorSliders() {
        let gray = Pixel(r: 128, g: 128, b: 128)
        let warm = adjusted([.warmth: 100], gray)
        #expect(warm.r > 128 && warm.b < 128)
        let magenta = adjusted([.tint: 100], gray)
        #expect(magenta.g < 128 && magenta.r > magenta.g)
        let mono = adjusted([.saturation: -100], Pixel(r: 200, g: 40, b: 90))
        #expect(mono.r == mono.g && mono.g == mono.b)
        // Vibrance gives a muted color a bigger push than a vivid one.
        let muted = Pixel(r: 140, g: 120, b: 110), vivid = Pixel(r: 250, g: 30, b: 20)
        let mutedGain = Double(adjusted([.vibrance: 100], muted).r) - Double(muted.r)
        let mutedChange = mutedGain / (140 - 124)
        let vividChange = (Double(adjusted([.vibrance: 100], vivid).r) - 250 + 1e-9) / (250 - 103)
        #expect(mutedChange > vividChange)
    }

    @Test func detailSlidersLeaveAFlatImageAlone() {
        let canvas = Canvas(size: IntSize(width: 30, height: 30), colorSpace: Canvas.defaultColorSpace, background: Pixel(r: 90, g: 140, b: 60))
        let before = canvas.activeLayer.buffer.contentHash()
        let edit = Edit(name: "Photo", canvas: canvas)
        Effects.apply(.photo(PhotoEdit(adjustments: PhotoAdjustments([.sharpness: 100, .definition: 100, .noiseReduction: 100]))),
                      to: canvas.activeLayer, selection: nil, edit: edit)
        #expect(canvas.activeLayer.buffer.contentHash() == before)
    }

    @Test func sharpnessCrispensAnEdgeAndNoiseReductionSmoothsSpeckles() {
        let canvas = Canvas(size: IntSize(width: 20, height: 20), colorSpace: Canvas.defaultColorSpace, background: Pixel(r: 100, g: 100, b: 100))
        for y in 0..<20 { for x in 10..<20 { canvas.activeLayer.buffer[x, y] = Pixel(r: 150, g: 150, b: 150) } }
        canvas.activeLayer.buffer[4, 4] = Pixel(r: 110, g: 110, b: 110)
        let edit = Edit(name: "Photo", canvas: canvas)
        Effects.apply(.photo(PhotoEdit(adjustments: PhotoAdjustments([.sharpness: 100]))), to: canvas.activeLayer, selection: nil, edit: edit)
        #expect(canvas.activeLayer.buffer[9, 10].r < 100 && canvas.activeLayer.buffer[10, 10].r > 150)

        let speckled = Canvas(size: IntSize(width: 20, height: 20), colorSpace: Canvas.defaultColorSpace, background: Pixel(r: 100, g: 100, b: 100))
        speckled.activeLayer.buffer[5, 5] = Pixel(r: 108, g: 108, b: 108)
        let smoothing = Edit(name: "Photo", canvas: speckled)
        Effects.apply(.photo(PhotoEdit(adjustments: PhotoAdjustments([.noiseReduction: 100]))), to: speckled.activeLayer, selection: nil, edit: smoothing)
        #expect(speckled.activeLayer.buffer[5, 5].r < 106)
    }

    @Test func vignetteSliderDarkensTheCorners() {
        let canvas = Canvas(size: IntSize(width: 31, height: 31), colorSpace: Canvas.defaultColorSpace, background: .white)
        let edit = Edit(name: "Photo", canvas: canvas)
        Effects.apply(.photo(PhotoEdit(adjustments: PhotoAdjustments([.vignette: 100]))), to: canvas.activeLayer, selection: nil, edit: edit)
        #expect(canvas.activeLayer.buffer[15, 15] == .white && canvas.activeLayer.buffer[0, 0].r < 100)
    }

    @Test func autoBrightensADarkPhotoAndNeutralizesABlueCast() {
        let buffer = PixelBuffer(width: 64, height: 64)
        for y in 0..<64 {
            let row = buffer.row(y)
            for x in 0..<64 { row[x] = Pixel(r: UInt8(20 + x / 2), g: UInt8(25 + x / 2), b: UInt8(60 + x / 2)) }
        }
        let auto = PhotoAdjustments.auto(for: buffer)
        #expect(auto[.exposure] > 0)
        #expect(auto[.warmth] > 0)
        #expect(auto[.vibrance] > 0)
        let allowed: Set<S> = [.exposure, .brilliance, .highlights, .shadows, .contrast, .warmth, .tint, .vibrance]
        #expect(Set(auto.values.keys).isSubset(of: allowed))
        #expect(PhotoAdjustments.auto(for: PixelBuffer(width: 4, height: 4)).isNeutral)
    }

    @Test func aPhotoAdjustmentIsALayerAndShowsThroughALookupTable() {
        let effect = Effect.photo(PhotoEdit(adjustments: PhotoAdjustments([.exposure: 30, .warmth: 40, .sharpness: 50])))
        #expect(Layer.isAdjustable(effect))
        let lookup = ColorLookup(effect)!
        let transform = effect.colorTransform!
        let step = 255.0 / 32
        let input = Pixel(r: UInt8((8 * step).rounded()), g: UInt8((16 * step).rounded()), b: UInt8((24 * step).rounded()))
        #expect(lookup.values[((24 * 33 + 16) * 33 + 8) * 4] == Float(transform(input).r) / 255)
    }
}

struct PhotoFilterTests {
    @Test func thereAreNineBuiltInFiltersOfColorAndToneOnly() {
        #expect(PhotoFilter.builtIn.map(\.name) == ["Vivid", "Vivid Warm", "Vivid Cool", "Dramatic", "Dramatic Warm", "Dramatic Cool", "Mono", "Silvertone", "Noir"])
        #expect(PhotoFilter.builtIn.allSatisfy { $0.isBuiltIn && $0.steps.allSatisfy(\.isColorOrTone) })
        let mono = PhotoFilter.builtIn[6].steps(atIntensity: 1)
        let pixel = mono.compactMap(\.colorTransform).reduce(Pixel(r: 200, g: 50, b: 80)) { $1($0) }
        #expect(pixel.r == pixel.g && pixel.g == pixel.b)
    }

    @Test func halfIntensityIsHalfOfEachValue() {
        let filter = PhotoFilter(name: "Mine", adjustments: PhotoAdjustments([.contrast: 40, .warmth: -20, .sharpness: 80]))
        guard case .photo(let edit) = filter.steps(atIntensity: 0.5)[0] else { Issue.record("Not a photo step"); return }
        #expect(edit.adjustments == PhotoAdjustments([.contrast: 20, .warmth: -10]))
        #expect(filter.steps(atIntensity: 0).isEmpty)
    }

    @Test func savedFromLayersInOrderSkippingOthers() {
        let canvas = Canvas(size: IntSize(width: 4, height: 4), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: .max), context = SelectionContext(color2: .white)
        LayerActions.addAdjustment(.levels(Levels(black: 10, white: 250, gamma: 1.1)), named: "Levels", canvas: canvas, history: history, context: context)
        LayerActions.addAdjustment(.gaussianBlur(radius: 4), named: "Blur", canvas: canvas, history: history, context: context)
        LayerActions.addAdjustment(.sepia(amount: 50), named: "Sepia", canvas: canvas, history: history, context: context)
        let filter = PhotoFilter.fromLayers(canvas.layers, name: "Stack")
        #expect(filter?.steps == [.levels(Levels(black: 10, white: 250, gamma: 1.1)), .sepia(amount: 50)])
        #expect(PhotoFilter.fromLayers([canvas.layers[0]], name: "None") == nil)
    }

    @Test func aFilterSavedFromThePanelLooksTheSameAtFullIntensity() {
        // What Save as Filter keeps: the chosen filter at its intensity, then the color and tone sliders.
        let before = PhotoEdit(adjustments: PhotoAdjustments([.exposure: 18, .warmth: 22, .vibrance: 10, .sharpness: 40]),
                               filter: PhotoFilter.builtIn[0], filterIntensity: 60)
        let steps = before.filter!.steps(atIntensity: 0.6) + [.photo(PhotoEdit(adjustments: before.adjustments.colorAndTone))]
        let saved = PhotoFilter(name: "Mine", steps: steps)
        let after = PhotoEdit(adjustments: PhotoAdjustments([.sharpness: 40]), filter: saved, filterIntensity: 100)
        for pixel in [Pixel(r: 30, g: 60, b: 90), Pixel(r: 200, g: 180, b: 40), Pixel(r: 128, g: 128, b: 128, a: 77)] {
            #expect(after.colorTransform(pixel) == before.colorTransform(pixel))
        }
    }

    @Test func otherStepsScaleTowardNoChange() {
        #expect(Effect.levels(Levels(black: 40, white: 200, gamma: 4)).scaled(by: 0.5) == .levels(Levels(black: 20, white: 227.5, gamma: 2)))
        #expect(Effect.sepia(amount: 80).scaled(by: 0.25) == .sepia(amount: 20))
        var curves = Curves.identity
        curves[.rgb] = [Curves.Point(x: 0, y: 0), Curves.Point(x: 100, y: 200), Curves.Point(x: 255, y: 255)]
        guard case .curves(let half) = Effect.curves(curves).scaled(by: 0.5) else { Issue.record("Not curves"); return }
        #expect(half.rgb[1] == Curves.Point(x: 100, y: 150))
        #expect(Effect.invert.scaled(by: 0.3) == .invert)
    }

    @Test func aFilterFileRoundTrips() throws {
        let filter = PhotoFilter(name: "Sunset", steps: [.photo(PhotoEdit(adjustments: PhotoAdjustments([.warmth: 30]))), .posterize(levels: 6)])
        let back = try PhotoFilter.imported(from: filter.exported())
        #expect(back == filter)
        #expect(throws: (any Error).self) { try PhotoFilter.imported(from: Data("nope".utf8)) }
    }
}

struct EffectCodingTests {
    @Test func everyEffectRoundTripsThroughJSON() throws {
        var curves = Curves.identity
        curves[.blue] = [Curves.Point(x: 0, y: 30), Curves.Point(x: 255, y: 220)]
        let filter = PhotoFilter.builtIn[3]
        let effects: [Effect] = [
            .gaussianBlur(radius: 3), .pixelate(cellSize: 9), .solidFill(Pixel(r: 1, g: 2, b: 3, a: 4)), .invert, .desaturate,
            .brightnessContrast(brightness: 5, contrast: -6), .hueSaturation(hue: 7, saturation: 8, lightness: 9), .sharpen(amount: 10),
            .levels(Levels(black: 1, white: 200, gamma: 0.7)), .curves(curves), .sepia(amount: 11), .posterize(levels: 12),
            .addNoise(amount: 13, monochrome: true), .motionBlur(angle: 14, distance: 15), .emboss(angle: 16, depth: 2), .vignette(amount: -17, size: 18),
            .photo(PhotoEdit(adjustments: PhotoAdjustments([.exposure: 19, .definition: 20]), filter: filter, filterIntensity: 65)),
        ]
        for effect in effects {
            #expect(try JSONDecoder().decode(Effect.self, from: JSONEncoder().encode(effect)) == effect)
        }
    }

    @Test func projectsFromBeforeStageNineStillOpen() throws {
        let old = Data(#"{"kind":"brightnessContrast","values":[12,-3]}"#.utf8)
        #expect(try JSONDecoder().decode(Effect.self, from: old) == .brightnessContrast(brightness: 12, contrast: -3))
        #expect(throws: (any Error).self) { try JSONDecoder().decode(Effect.self, from: Data(#"{"kind":"future","values":[]}"#.utf8)) }
    }
}
