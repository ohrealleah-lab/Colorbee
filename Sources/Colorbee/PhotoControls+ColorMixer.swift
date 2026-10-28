import ColorbeeCore
import SwiftUI

/// Adjust Photo's Color Mixer section (FR-9.7 items 1 and 6): Black & White at the top, then Hue, Saturation and
/// Luminance tabs of eight sliders, one per color range (Leah, 2026-10-27). With Black & White on, the eight sliders
/// set how light each color becomes in gray.
extension PhotoControls {
    var colorMixerSection: some View {
        let title = "Color Mixer"
        let mixer = edit.mixer ?? ColorMixer()
        let isBlackAndWhite = mixer.blackAndWhite > 0
        return Group {
            sectionHeading(title)
            if !isFolded(title) {
                Toggle("Black & White", isOn: Binding(get: { isBlackAndWhite }, set: { on in
                    var changed = mixer
                    changed.blackAndWhite = on ? 1 : 0
                    change(changed)
                    onFinish()
                }))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: 12))
                .help("Make the picture black and white; the sliders then set how light each color becomes")
                if !isBlackAndWhite {
                    Picker("Color Mixer", selection: $mixerSetting) {
                        Text("Hue").tag(ColorMixer.Setting.hue)
                        Text("Saturation").tag(ColorMixer.Setting.saturation)
                        Text("Luminance").tag(ColorMixer.Setting.luminance)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                }
                let setting = isBlackAndWhite ? ColorMixer.Setting.gray : mixerSetting
                ForEach(ColorMixer.Range.allCases, id: \.self) { range in
                    row(range.title, value: mixer[setting, range], range: -100...100, unit: "", swatch: Self.swatch(range)) { value in
                        var changed = mixer
                        changed[setting, range] = value
                        change(changed)
                    }
                }
            }
        }
    }

    private func change(_ mixer: ColorMixer) {
        var changed = edit
        changed.mixer = mixer
        onChange(changed)
    }

    private static func swatch(_ range: ColorMixer.Range) -> Color {
        Color(hue: range.centerHue / 360, saturation: 0.75, brightness: 0.9)
    }
}
