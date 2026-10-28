import Foundation
import Testing
@testable import ColorbeeCore

/// Adjust Photo's Vignette shape and Grain (FR-9.7 item 5).
struct PhotoEffectsTests {
    private func shape(_ change: (inout Vignette.Shape) -> Void = { _ in }) -> Vignette.Shape {
        var shape = Vignette.Shape(amount: 50)
        change(&shape)
        return shape
    }

    @Test func atItsStartTheShapeIsTheOldVignetteExactly() {
        for region in [IntRect(x: 0, y: 0, width: 40, height: 24), IntRect(x: 5, y: 3, width: 17, height: 31)] {
            for y in region.minY..<region.maxY {
                for x in region.minX..<region.maxX {
                    #expect(Vignette.strength(x: x, y: y, in: region, shape: shape()) == Vignette.strength(x: x, y: y, in: region, size: 50))
                }
            }
        }
    }

    @Test func roundnessMakesACircleOrARectangle() {
        let wide = IntRect(x: 0, y: 0, width: 200, height: 100)
        let circle = shape { $0.roundness = 100 }
        // On a circle, points the same distance from the middle match, across or down.
        #expect(abs(Vignette.strength(x: 100 + 45, y: 50, in: wide, shape: circle) - Vignette.strength(x: 100, y: 50 + 45, in: wide, shape: circle)) < 0.02)
        // Toward a rectangle, the middle of an edge darkens more than with the picture's own shape.
        let square = shape { $0.roundness = -100 }
        #expect(Vignette.strength(x: 100, y: 3, in: wide, shape: square) > Vignette.strength(x: 100, y: 3, in: wide, shape: shape()))
    }

    @Test func featherAndMidpointMoveTheEdge() {
        let region = IntRect(x: 0, y: 0, width: 60, height: 60)
        let hard = shape { $0.feather = 0 }
        let values = Set((0..<60).map { Vignette.strength(x: $0, y: 30, in: region, shape: hard) })
        #expect(values == [0, 1])
        let further = shape { $0.midpoint = 80 }
        #expect(Vignette.strength(x: 5, y: 5, in: region, shape: further) < Vignette.strength(x: 5, y: 5, in: region, shape: shape()))
    }

    @Test func grainIsFixedToThePixelsAndAveragesOut() {
        let grain = Grain(amount: 60)
        #expect(grain.offset(x: 17, y: 42) == grain.offset(x: 17, y: 42))
        let offsets = (0..<64).flatMap { y in (0..<64).map { x in grain.offset(x: x, y: y) } }
        let mean = offsets.reduce(0, +) / Double(offsets.count)
        #expect(abs(mean) < 0.01 && offsets.contains { $0 > 0.03 } && offsets.contains { $0 < -0.03 })
        #expect(offsets.allSatisfy { abs($0) <= 0.12 })
        #expect(Grain(amount: 0).offset(x: 3, y: 4) == 0)
    }

    @Test func biggerGrainIsSmootherFromPixelToPixel() {
        func roughness(_ grain: Grain) -> Double {
            let pairs = (0..<2000).map { abs(grain.offset(x: $0 % 50, y: $0 / 50) - grain.offset(x: $0 % 50 + 1, y: $0 / 50)) }
            return pairs.reduce(0, +) / Double(pairs.count)
        }
        #expect(roughness(Grain(amount: 60, size: 100, roughness: 0)) < roughness(Grain(amount: 60, size: 0, roughness: 0)) / 2)
        #expect(roughness(Grain(amount: 60, size: 100, roughness: 100)) > roughness(Grain(amount: 60, size: 100, roughness: 0)))
    }

    @Test func aFilterKeepsTheShapeAndGrainAndIntensityScalesOnlyTheAmounts() {
        var effects = PhotoEffects()
        effects.roundness = 60
        effects.grainSize = 70
        let panel = PhotoEdit(adjustments: PhotoAdjustments([.vignette: -40, .grain: 50, .sharpness: 30]), effects: effects)
        let filter = PhotoFilter(name: "Film", steps: [.photo(panel.filterPart)])
        let atHalf = PhotoEdit(filter: filter, filterIntensity: 50)
        #expect(atHalf.vignettes == [Vignette.Shape(amount: -20, midpoint: 50, roundness: 60, feather: 50)])
        #expect(atHalf.grains == [Grain(amount: 25, size: 70, roughness: 50)])
        #expect(panel.partFiltersLeaveOut.effects == nil && panel.partFiltersLeaveOut.adjustments == PhotoAdjustments([.sharpness: 30]))
        // A filter saved before stage 14 has neither.
        #expect(PhotoEdit(filter: PhotoFilter(name: "Old", adjustments: PhotoAdjustments([.saturation: 20]))).grains.isEmpty)
    }

    @Test func grainOnAPictureMatchesWhereverItsApplied() {
        let canvas = Canvas(size: IntSize(width: 32, height: 32), colorSpace: Canvas.defaultColorSpace, background: Pixel(r: 128, g: 128, b: 128))
        let edit = PhotoEdit(adjustments: PhotoAdjustments([.grain: 80]))
        let whole = canvas.copy(), part = canvas.copy()
        Effects.apply(.photo(edit), to: whole.activeLayer, selection: nil, edit: Edit(name: "Grain", canvas: whole, recordsPixels: false))
        let mask = SelectionMask.rectangle(IntRect(x: 10, y: 10, width: 8, height: 8), clippedTo: whole.bounds)
        Effects.apply(.photo(edit), to: part.activeLayer, selection: mask, edit: Edit(name: "Grain", canvas: part, recordsPixels: false))
        // The same grain at the same pixel, so a selection's grain lines up with the rest.
        #expect(whole.activeLayer.buffer.row(12)[13] == part.activeLayer.buffer.row(12)[13])
        #expect(whole.activeLayer.buffer.row(12)[13] != Pixel(r: 128, g: 128, b: 128) || whole.activeLayer.buffer.row(12)[14] != Pixel(r: 128, g: 128, b: 128))
    }

    @Test func settingsAreSavedAndKeptInRange() throws {
        var effects = PhotoEffects()
        effects.feather = 10
        effects.grainRoughness = 80
        let edit = PhotoEdit(adjustments: PhotoAdjustments([.grain: 30]), effects: effects)
        #expect(try JSONDecoder().decode(PhotoEdit.self, from: JSONEncoder().encode(edit)) == edit)
        let read = try JSONDecoder().decode(PhotoEffects.self, from: Data(#"{"roundness": -400, "grainSize": 12}"#.utf8))
        #expect(read.roundness == -100 && read.grainSize == 12 && read.midpoint == 50)
        #expect(PhotoEdit(effects: PhotoEffects()).effects == nil)
    }
}
