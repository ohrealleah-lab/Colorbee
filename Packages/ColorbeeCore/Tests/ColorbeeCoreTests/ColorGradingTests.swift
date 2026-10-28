import Foundation
import Testing
@testable import ColorbeeCore

/// Color Grading (FR-9.7 item 2, stage 5), on a gray ramp like the one in `Color Chart.png`.
struct ColorGradingTests {
    private let ramp = (0...16).map { i -> Pixel in let v = UInt8(min(255, i * 16)); return Pixel(r: v, g: v, b: v) }

    private func tealAndOrange(balance: Double = 0) -> ColorGrading {
        var grading = ColorGrading()
        grading[.shadows] = .init(hue: 180, strength: 60)
        grading[.highlights] = .init(hue: 30, strength: 60)
        grading.balance = balance
        return grading
    }

    @Test func shadowsGoTealAndHighlightsOrange() {
        let apply = tealAndOrange().transform!
        let dark = apply(ramp[2]), light = apply(ramp[14])
        #expect(dark.b > dark.r && dark.g > dark.r)
        #expect(light.r > light.b)
        // Tinting doesn't change brightness much.
        #expect(abs(Int(light.luminance) - Int(ramp[14].luminance)) <= 6)
    }

    @Test func balanceRightGivesTheHighlightsMoreOfTheRamp() {
        func orangeCount(_ grading: ColorGrading) -> Int { ramp.map(grading.transform!).filter { $0.r > $0.b }.count }
        #expect(orangeCount(tealAndOrange(balance: 80)) > orangeCount(tealAndOrange()))
    }

    @Test func globalAndLuminanceReachEveryTone() {
        var grading = ColorGrading()
        grading[.global] = .init(hue: 240, strength: 40)
        grading[.midtones] = .init(luminance: 50)
        let apply = grading.transform!
        for pixel in ramp.dropFirst().dropLast() { #expect(apply(pixel).b > apply(pixel).r) }
        #expect(apply(ramp[8]).luminance > ramp[8].luminance + 10)
    }

    @Test func aFilterAtHalfIntensityHalvesTheStrengthAndKeepsTheHue() {
        var grading = tealAndOrange(balance: 40)
        grading.blending = 70
        let half = grading.scaled(by: 0.5)
        #expect(half[.shadows] == .init(hue: 180, strength: 30) && half[.highlights].hue == 30)
        #expect(half.blending == 70 && half.balance == 40)
        let filter = PhotoFilter(name: "Teal", steps: [.photo(PhotoEdit(grading: grading))])
        guard case .photo(let step) = filter.steps(atIntensity: 0.5)[0] else { Issue.record("Not a photo step"); return }
        #expect(step.grading == half)
    }

    @Test func blendingAloneIsKeptButChangesNothing() {
        var grading = ColorGrading()
        grading.blending = 80
        let edit = PhotoEdit(grading: grading)
        #expect(edit.grading?.blending == 80)
        #expect(edit.isNeutral)
        #expect(PhotoEdit(grading: ColorGrading()).grading == nil)
    }

    @Test func itsSavedAndReadBackSafely() throws {
        let edit = PhotoEdit(grading: tealAndOrange(balance: -20))
        #expect(try JSONDecoder().decode(PhotoEdit.self, from: JSONEncoder().encode(edit)) == edit)
        let odd = #"{"adjustments": {"values": []}, "filterIntensity": 100, "grading": {"wheels": {"shadows": {"hue": 500, "strength": 900, "luminance": -3}, "sideways": {"hue": 1, "strength": 1, "luminance": 1}}, "blending": 1e9}}"#
        let read = try JSONDecoder().decode(PhotoEdit.self, from: Data(odd.utf8)).grading
        #expect(read?[.shadows] == .init(hue: 140, strength: 100, luminance: -3))
        #expect(read?.blending == 100 && read?.wheels.count == 1)
    }
}
