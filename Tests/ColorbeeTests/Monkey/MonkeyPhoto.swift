import ColorbeeCore
import Foundation
@testable import Colorbee

/// Whole Adjust Photo settings for the monkey (Leah, 2026-11-10): several sliders at once, anywhere in their range, and
/// sometimes each of the other parts, so combinations nobody would think to try get made.
enum MonkeyPhoto {
    static func edit(_ random: inout MonkeyRandom) -> PhotoEdit {
        func value(_ range: ClosedRange<Int>) -> Double { Double(random.int(range)) }
        var edit = PhotoEdit()
        for _ in 0..<random.int(1...6) {
            let slider = random.pick(PhotoAdjustments.Slider.allCases)
            edit.adjustments[slider] = value(Int(slider.range.lowerBound)...Int(slider.range.upperBound))
        }
        if random.chance(0.3) {
            var mixer = ColorMixer()
            for _ in 0..<random.int(1...4) {
                mixer[random.pick(ColorMixer.Setting.allCases), random.pick(ColorMixer.Range.allCases)] = value(-100...100)
            }
            if random.chance(0.3) { mixer.blackAndWhite = value(1...100) / 100 }
            edit.mixer = mixer
        }
        if random.chance(0.3) {
            var grading = ColorGrading()
            for _ in 0..<random.int(1...3) {
                grading[random.pick(ColorGrading.Region.allCases)] = ColorGrading.Wheel(hue: value(0...359), strength: value(0...100), luminance: value(-100...100))
            }
            grading.blending = value(0...100)
            grading.balance = value(-100...100)
            edit.grading = grading
        }
        if random.chance(0.25) {
            edit.pointColors = PointColors((0..<random.int(1...3)).map { _ in
                PointColors.Swatch(color: Pixel(r: UInt8(random.int(0...255)), g: UInt8(random.int(0...255)), b: UInt8(random.int(0...255))),
                                   hue: value(-100...100), saturation: value(-100...100), luminance: value(-100...100), range: value(0...100))
            })
        }
        if random.chance(0.3) {
            var curve = ToneCurve()
            curve.amounts = (0..<4).map { _ in value(-100...100) }
            let first = random.int(10...40), second = random.int((first + 5)...(first + 40)), third = random.int((second + 5)...95)
            curve.splits = [Double(first), Double(second), Double(third)]
            edit.toneCurve = curve
        }
        if random.chance(0.25) {
            var detail = PhotoDetail()
            detail.radius = value(5...30) / 10
            (detail.sharpnessDetail, detail.masking, detail.luminanceDetail) = (value(0...100), value(0...100), value(0...100))
            (detail.color, detail.colorDetail) = (value(0...100), value(0...100))
            edit.detail = detail
        }
        if random.chance(0.25) {
            var effects = PhotoEffects()
            (effects.midpoint, effects.roundness, effects.feather) = (value(0...100), value(-100...100), value(0...100))
            (effects.grainSize, effects.grainRoughness) = (value(0...100), value(0...100))
            edit.effects = effects
        }
        if random.chance(0.2) {
            edit.filter = random.pick(PhotoFilter.builtIn + [PhotoFilter(name: "Warm Look", steps: [.look(ScreenMatchesExportTests.warmLook)])])
            edit.filterIntensity = value(0...100)
        }
        return edit
    }

    /// The settings in words, for the report.
    static func words(_ edit: PhotoEdit) -> String {
        var parts = edit.adjustments.values.sorted { $0.key.title < $1.key.title }.map { "\($0.key.title) \(Int($0.value))" }
        if let filter = edit.filter { parts.append("filter \(filter.name) at \(Int(edit.filterIntensity))%") }
        if let mixer = edit.mixer { parts.append("\(mixer)") }
        if let grading = edit.grading { parts.append("\(grading)") }
        if let points = edit.pointColors { parts.append("\(points)") }
        if let curve = edit.toneCurve { parts.append("\(curve)") }
        if let detail = edit.detail { parts.append("\(detail)") }
        if let effects = edit.effects { parts.append("\(effects)") }
        return parts.isEmpty ? "nothing changed" : parts.joined(separator: ", ")
    }
}
