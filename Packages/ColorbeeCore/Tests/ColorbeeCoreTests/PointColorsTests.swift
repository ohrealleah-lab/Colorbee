import Foundation
import Testing
@testable import ColorbeeCore

/// Point Color (FR-9.7 item 2, stage 6), on the patches of `Color Chart.png`.
struct PointColorsTests {
    private let red = Pixel(r: 217, g: 43, b: 43), orange = Pixel(r: 217, g: 130, b: 43), yellow = Pixel(r: 217, g: 217, b: 43)
    private let blue = Pixel(r: 43, g: 87, b: 217), skinLight = Pixel(r: 241, g: 194, b: 167), skin = Pixel(r: 198, g: 134, b: 99)
    private let gray = Pixel(r: 128, g: 128, b: 128)

    private func picked(_ color: Pixel, hue: Double = 0, saturation: Double = 0, range: Double = 50) -> PointColors {
        PointColors([.init(color: color, hue: hue, saturation: saturation, range: range)])
    }

    /// Reset Range puts the Range back to the middle and turns the gray view off, in one change (Leah's test of
    /// review V, finding 1).
    @Test func resetRangeGoesBackToTheMiddleWithTheViewOff() {
        var colors = PointColors([PointColors.Swatch(color: Pixel(r: 220, g: 40, b: 40), hue: 50, range: 80)])
        colors.showsRangeOf = 0
        let reset = colors.resettingRange(of: 0)
        #expect(reset[0].range == 50 && reset[0].hue == 50)
        #expect(reset.showsRangeOf == nil)
    }

    @Test func aHueShiftMovesOnlyThePickedColor() {
        let apply = picked(orange, hue: 50).transform!
        #expect(apply(orange) != orange)
        #expect(abs(HSL(apply(orange)).hue - (30 + 15)) < 2)
        for pixel in [red, yellow, blue, skinLight, gray] { #expect(apply(pixel) == pixel, "\(pixel) changed") }
    }

    @Test func widerRangeTakesInNeighbors() {
        #expect(picked(orange, hue: 50, range: 50).transform!(yellow) == yellow)
        #expect(picked(orange, hue: 50, range: 100).transform!(yellow) != yellow)
    }

    @Test func severalColorsEachChangeTheirOwn() {
        let colors = PointColors([.init(color: orange, hue: 50), .init(color: skin, saturation: -80)])
        let apply = colors.transform!
        #expect(apply(orange) != orange)
        let calmer = apply(skin)
        #expect(Int(calmer.r) - Int(calmer.b) < Int(skin.r) - Int(skin.b) - 30)
        #expect(apply(blue) == blue)
    }

    @Test func theRangePreviewGraysOutTheRestAndIsNeverSaved() throws {
        var colors = picked(blue)
        colors.showsRangeOf = 0
        let apply = colors.transform!
        let elsewhere = apply(orange)
        #expect(elsewhere.r == elsewhere.g && elsewhere.g == elsewhere.b)
        #expect(apply(blue) == blue)
        let read = try JSONDecoder().decode(PointColors.self, from: JSONEncoder().encode(colors))
        #expect(read.showsRangeOf == nil && read.swatches == colors.swatches)
    }

    @Test func eightColorsAtMost() {
        var colors = PointColors()
        for i in 0..<10 { colors.add(Pixel(r: UInt8(i * 20), g: 90, b: 140)) }
        #expect(colors.swatches.count == 8 && colors.isFull)
        colors.remove(at: 3)
        #expect(colors.swatches.count == 7)
    }

    @Test func aFilterScalesTheShiftsAndKeepsTheColorsAndRange() {
        let colors = PointColors([.init(color: orange, hue: 60, saturation: -40, luminance: 20, range: 70)])
        let half = colors.scaled(by: 0.5)
        #expect(half.swatches == [.init(color: orange, hue: 30, saturation: -20, luminance: 10, range: 70)])
        let filter = PhotoFilter(name: "Point", steps: [.photo(PhotoEdit(pointColors: colors))])
        guard case .photo(let step) = filter.steps(atIntensity: 0.5)[0] else { Issue.record("Not a photo step"); return }
        #expect(step.pointColors == half)
    }

    @Test func savedAndReadBackSafely() throws {
        let edit = PhotoEdit(pointColors: PointColors([.init(color: orange, hue: 40, range: 30)]))
        #expect(try JSONDecoder().decode(PhotoEdit.self, from: JSONEncoder().encode(edit)) == edit)
        #expect(edit.needsFineColorTable)
        let odd = #"{"adjustments": {"values": []}, "filterIntensity": 100, "pointColors": {"swatches": [{"color": [217, 130, 43], "hue": 900, "range": -5}, {"color": "teal"}, {"color": [1, 2, 3]}]}}"#
        let read = try JSONDecoder().decode(PhotoEdit.self, from: Data(odd.utf8)).pointColors
        #expect(read?.swatches.count == 2)
        #expect(read?.swatches.first == .init(color: orange, hue: 100, range: 0))
        // Picked colors with no changes yet are kept but change nothing.
        #expect(PhotoEdit(pointColors: PointColors([.init(color: orange)])).isNeutral)
    }
}
