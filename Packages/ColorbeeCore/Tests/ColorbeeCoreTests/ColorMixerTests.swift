import Foundation
import Testing
@testable import ColorbeeCore

/// The Color Mixer and Black & White (FR-9.7 items 1 and 6, stage 4), on the patches of `Color Chart.png`.
struct ColorMixerTests {
    private let red = Pixel(r: 217, g: 43, b: 43), orange = Pixel(r: 217, g: 130, b: 43), green = Pixel(r: 43, g: 217, b: 43)
    private let aqua = Pixel(r: 43, g: 217, b: 217), blue = Pixel(r: 43, g: 87, b: 217), purple = Pixel(r: 130, g: 43, b: 217)
    private let skin = Pixel(r: 198, g: 134, b: 99), gray = Pixel(r: 128, g: 128, b: 128)
    private var chart: [Pixel] { [red, orange, green, aqua, blue, purple, skin, gray] }

    private func mixer(_ setting: ColorMixer.Setting, _ range: ColorMixer.Range, _ value: Double, blackAndWhite: Double = 0) -> ColorMixer {
        var mixer = ColorMixer()
        mixer[setting, range] = value
        mixer.blackAndWhite = blackAndWhite
        return mixer
    }

    @Test func eachHueBelongsToTwoNeighborsAtMost() {
        for hue in stride(from: 0.0, to: 360, by: 7.5) {
            let weights = ColorMixer.weights(hue: hue)
            #expect(abs(weights.reduce(0, +) - 1) < 1e-9)
            #expect(weights.filter { $0 > 1e-9 }.count <= 2)
        }
        for range in ColorMixer.Range.allCases { #expect(ColorMixer.weights(hue: range.centerHue)[range.rawValue] == 1) }
    }

    @Test func blueSaturationOnlyTurnsTheBluePatchGray() {
        let apply = mixer(.saturation, .blue, -100).transform!
        #expect(apply(blue) == Pixel(r: 87, g: 87, b: 87))
        for pixel in chart where pixel != blue { #expect(apply(pixel) == pixel, "\(pixel) changed") }
    }

    @Test func greenHueLeansTowardAquaAndNothingElseMoves() {
        let apply = mixer(.hue, .green, 100).transform!
        let shifted = HSL(apply(green)).hue
        #expect(abs(shifted - 150) < 2)
        for pixel in chart where pixel != green { #expect(apply(pixel) == pixel, "\(pixel) changed") }
    }

    @Test func luminanceLightensTheMiddleAndLeavesNearBlackAlone() {
        let apply = mixer(.luminance, .orange, 60).transform!
        #expect(apply(orange).luminance > orange.luminance + 10)
        // A nearly black orange moves a few levels at most (it jumped about 70 before stage 4's fix).
        let darkOrange = Pixel(r: 18, g: 9, b: 0)
        #expect(abs(Int(apply(darkOrange).luminance) - Int(darkOrange.luminance)) <= 6)
        #expect(apply(gray) == gray && apply(blue) == blue)
    }

    @Test func blackAndWhiteStartsLikeMonoAndTheMixLightensOneColor() {
        let plain = mixer(.gray, .red, 0, blackAndWhite: 1).transform!
        let mono = PhotoAdjustments([.saturation: -100]).colorTransform
        for pixel in chart {
            #expect(plain(pixel).r == plain(pixel).g && plain(pixel).g == plain(pixel).b)
            #expect(abs(Int(plain(pixel).r) - Int(mono(pixel).r)) <= 1)
        }
        let redLighter = mixer(.gray, .red, 60, blackAndWhite: 1).transform!
        #expect(redLighter(red).r > plain(red).r + 15)
        for pixel in chart where pixel != red && pixel != orange && pixel != purple && pixel != skin {
            #expect(redLighter(pixel) == plain(pixel), "\(pixel) changed")
        }
    }

    @Test func aFilterAtHalfIntensityHalvesTheMixer() {
        let full = mixer(.hue, .green, 80, blackAndWhite: 1)
        let half = full.scaled(by: 0.5)
        #expect(half[.hue, .green] == 40 && half.blackAndWhite == 0.5)
        let filter = PhotoFilter(name: "Mix", steps: [.photo(PhotoEdit(mixer: full))])
        guard case .photo(let step) = filter.steps(atIntensity: 0.5)[0] else { Issue.record("Not a photo step"); return }
        #expect(step.mixer == half)
    }

    @Test func itsSavedBesideWhatBeta7ReadsAndRoundTrips() throws {
        let edit = PhotoEdit(adjustments: PhotoAdjustments([.exposure: 10]), mixer: mixer(.saturation, .blue, -100))
        let data = try JSONEncoder().encode(edit)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["mixer"] != nil && json["adjustments"] != nil)
        #expect(try JSONDecoder().decode(PhotoEdit.self, from: data) == edit)
        // A damaged mixer is left out, and the rest of the adjustment kept.
        let damaged = #"{"adjustments": {"values": ["exposure", 10]}, "filterIntensity": 100, "mixer": "nonsense"}"#
        #expect(try JSONDecoder().decode(PhotoEdit.self, from: Data(damaged.utf8)) == PhotoEdit(adjustments: PhotoAdjustments([.exposure: 10])))
        #expect(PhotoEdit(mixer: ColorMixer()).mixer == nil)
    }

    @Test func saveAsFilterKeepsTheMixerAndTheDisplayUsesTheFinerTable() {
        let edit = PhotoEdit(adjustments: PhotoAdjustments([.sharpness: 30, .contrast: 10]), mixer: mixer(.hue, .red, 50))
        #expect(edit.filterPart == PhotoEdit(adjustments: PhotoAdjustments([.contrast: 10]), mixer: mixer(.hue, .red, 50)))
        #expect(edit.partFiltersLeaveOut == PhotoEdit(adjustments: PhotoAdjustments([.sharpness: 30])))
        #expect(edit.needsFineColorTable && !PhotoEdit(adjustments: PhotoAdjustments([.contrast: 10])).needsFineColorTable)
        #expect(ColorLookup(.photo(edit))?.size == ColorLookup.fineSize)
        let viaFilter = PhotoEdit(filter: PhotoFilter(name: "Mix", steps: [.photo(edit.filterPart)]))
        #expect(viaFilter.needsFineColorTable)
        for pixel in chart { #expect(viaFilter.colorTransform(pixel) == edit.colorTransform(pixel)) }
    }
}
