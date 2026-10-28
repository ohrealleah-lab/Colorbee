import ColorbeeCore
import SwiftUI

/// Adjust Photo's Color Grading section (FR-9.7 item 2): one large wheel with tabs for Shadows, Midtones, Highlights
/// and Global, its Luminance, then Blending and Balance (Leah, 2026-10-27).
extension PhotoControls {
    var colorGradingSection: some View {
        let title = "Color Grading"
        let grading = edit.grading ?? ColorGrading()
        let region = gradingRegion
        return Group {
            sectionHeading(title)
            if !isFolded(title) {
                Picker("Color Grading", selection: $gradingRegion) {
                    ForEach(ColorGrading.Region.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                // Four tabs fit the sidebar only at this size.
                .controlSize(.mini)
                ColorWheel(title: region.title, wheel: grading[region],
                           others: ColorGrading.Region.allCases.filter { $0 != region }.map { grading[$0] }.filter { $0.strength > 0 }) { wheel in
                    var changed = grading
                    changed[region] = wheel
                    change(changed)
                } onFinish: { onFinish() }
                .frame(width: 140, height: 140)
                .frame(maxWidth: .infinity)
                Text("Hue \(Int(grading[region].hue))° · Strength \(Int(grading[region].strength))")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondaryInk)
                    .frame(maxWidth: .infinity)
                row("Luminance", value: grading[region].luminance, range: -100...100, unit: "") { value in
                    var changed = grading
                    var wheel = grading[region]
                    wheel.luminance = value
                    changed[region] = wheel
                    change(changed)
                }
                row("Blending", value: grading.blending, range: 0...100, unit: "", resetValue: 50) { value in
                    var changed = grading
                    changed.blending = value
                    change(changed)
                }
                row("Balance", value: grading.balance, range: -100...100, unit: "") { value in
                    var changed = grading
                    changed.balance = value
                    change(changed)
                }
            }
        }
    }

    private func change(_ grading: ColorGrading) {
        var changed = edit
        changed.grading = grading
        onChange(changed)
    }
}
