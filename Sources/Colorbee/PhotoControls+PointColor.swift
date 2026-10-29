import ColorbeeCore
import SwiftUI

/// Adjust Photo's Point Color section (FR-9.7 item 2): pick up to eight colors from the picture, then shift each one's
/// hue, saturation and luminance, with a Range for how wide "that color" is. Holding the Range slider grays out what
/// the color doesn't touch (Leah, 2026-10-27).
extension PhotoControls {
    var pointColorSection: some View {
        let title = "Point Color"
        let colors = edit.pointColors ?? PointColors()
        let chosen = colors.swatches.indices.contains(chosenSwatch) ? chosenSwatch : colors.swatches.count - 1
        return Group {
            sectionHeading(title)
            if !isFolded(title) {
                HStack(spacing: 6) {
                    pointColorDropper(disabled: colors.isFull)
                    ForEach(Array(colors.swatches.enumerated()), id: \.offset) { index, swatch in
                        Button { chosenSwatch = index } label: {
                            Circle()
                                .fill(Color(red: Double(swatch.color.r) / 255, green: Double(swatch.color.g) / 255, blue: Double(swatch.color.b) / 255))
                                .frame(width: 16, height: 16)
                                .overlay(Circle().strokeBorder(index == chosen ? Color.accentColor : Theme.secondaryInk.opacity(0.4),
                                                               lineWidth: index == chosen ? 2 : 1))
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Color \(index + 1)")
                        .accessibilityLabel("Picked color \(index + 1)")
                        .accessibilityAddTraits(index == chosen ? .isSelected : [])
                    }
                    Spacer()
                    if chosen >= 0 {
                        Button {
                            var changed = colors
                            changed.remove(at: chosen)
                            change(changed)
                            onFinish()
                        } label: {
                            Image(systemName: "minus.circle").font(.system(size: 12)).frame(width: 18, height: 18).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.secondaryInk)
                        .help("Remove this color")
                        .accessibilityLabel("Remove picked color \(chosen + 1)")
                    }
                }
                .onChange(of: colors.swatches.count) { old, new in
                    // A newly picked color is the one to adjust.
                    if new > old { chosenSwatch = new - 1 }
                }
                if chosen >= 0 {
                    let swatch = colors[chosen]
                    swatchRow("Hue", swatch.hue, colors, chosen) { $0.hue = $1 }
                    swatchRow("Saturation", swatch.saturation, colors, chosen) { $0.saturation = $1 }
                    swatchRow("Luminance", swatch.luminance, colors, chosen) { $0.luminance = $1 }
                    row("Range", value: swatch.range, range: 0...100, unit: "", resetValue: 50, end: {
                        var changed = edit.pointColors ?? colors
                        changed.showsRangeOf = nil
                        change(changed)
                        onFinish()
                    }, reset: {
                        change(colors.resettingRange(of: chosen))
                        onFinish()
                    }) { value in
                        var changed = colors
                        changed[chosen].range = value
                        changed.showsRangeOf = chosen
                        change(changed)
                    }
                } else {
                    Text("Click the eyedropper, then a color in the picture.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryInk)
                }
            }
        }
    }

    private func swatchRow(_ title: String, _ value: Double, _ colors: PointColors, _ index: Int,
                           _ apply: @escaping (inout PointColors.Swatch, Double) -> Void) -> some View {
        row(title, value: value, range: -100...100, unit: "") { newValue in
            var changed = colors
            apply(&changed[index], newValue)
            change(changed)
        }
    }

    private func pointColorDropper(disabled: Bool) -> some View {
        let isOn = editor.isPicking(.pointColor)
        return Button { editor.togglePicturePick(.pointColor) } label: {
            Image(systemName: "eyedropper")
                .font(.system(size: 11))
                .frame(width: 18, height: 18)
                .background(isOn ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(isOn ? Color.accentColor : Theme.secondaryInk)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(disabled ? "Eight colors is the most; remove one to pick another" : "Pick a color: click it in the picture. Esc cancels.")
        .accessibilityLabel("Pick a color from the picture")
        .accessibilityValue(isOn ? "On" : "Off")
    }

    private func change(_ colors: PointColors) {
        var changed = edit
        changed.pointColors = colors
        onChange(changed)
    }
}
