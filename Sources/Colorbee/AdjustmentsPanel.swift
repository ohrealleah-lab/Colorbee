import ColorbeeCore
import SwiftUI

/// The six kinds of adjustment layer (FR-8.4), with their names, icons and starting settings.
enum AdjustmentChoice: CaseIterable {
    case brightnessContrast
    case hueSaturation
    case desaturate
    case invert
    case gaussianBlur
    case sharpen

    var title: String {
        switch self {
        case .brightnessContrast: "Brightness/Contrast"
        case .hueSaturation: "Hue/Saturation"
        case .desaturate: "Desaturate"
        case .invert: "Invert"
        case .gaussianBlur: "Gaussian Blur"
        case .sharpen: "Sharpen"
        }
    }

    var symbol: String {
        switch self {
        case .brightnessContrast: "sun.max"
        case .hueSaturation: "swatchpalette"
        case .desaturate: "circle.dotted.and.circle"
        case .invert: "circle.lefthalf.filled"
        case .gaussianBlur: "drop"
        case .sharpen: "triangle"
        }
    }

    /// The settings a new adjustment layer starts with. Blur and Sharpen start with a visible amount,
    /// so adding one shows what it does.
    var startingAdjustment: Effect {
        switch self {
        case .brightnessContrast: .brightnessContrast(brightness: 0, contrast: 0)
        case .hueSaturation: .hueSaturation(hue: 0, saturation: 0, lightness: 0)
        case .desaturate: .desaturate
        case .invert: .invert
        case .gaussianBlur: .gaussianBlur(radius: 8)
        case .sharpen: .sharpen(amount: 60)
        }
    }

    /// The sliders, shared with the Adjustments and Effects menus' live dialogs. Nil means no settings.
    var kind: EffectKind? {
        switch self {
        case .brightnessContrast: .brightnessContrast
        case .hueSaturation: .hueSaturation
        case .gaussianBlur: .gaussianBlur
        case .sharpen: .sharpen
        case .desaturate, .invert: nil
        }
    }

    init?(_ effect: Effect) {
        switch effect {
        case .brightnessContrast: self = .brightnessContrast
        case .hueSaturation: self = .hueSaturation
        case .desaturate: self = .desaturate
        case .invert: self = .invert
        case .gaussianBlur: self = .gaussianBlur
        case .sharpen: self = .sharpen
        case .pixelate, .solidFill: return nil
        }
    }
}

extension Effect {
    /// The settings in slider order (matching `EffectKind.parameters`).
    var sliderValues: [Double] {
        switch self {
        case .brightnessContrast(let brightness, let contrast): [brightness, contrast]
        case .hueSaturation(let hue, let saturation, let lightness): [hue, saturation, lightness]
        case .gaussianBlur(let radius): [radius]
        case .sharpen(let amount): [amount]
        case .pixelate(let cellSize): [Double(cellSize)]
        case .invert, .desaturate, .solidFill: []
        }
    }
}

/// The menu of adjustment layers to add, used in the Layers panel's footer.
struct AddAdjustmentMenu: View {
    let editor: Editor

    var body: some View {
        Menu {
            ForEach(AdjustmentChoice.allCases, id: \.self) { choice in
                Button(choice.title, systemImage: choice.symbol) {
                    editor.addAdjustmentLayer(choice.startingAdjustment, named: choice.title)
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "slider.horizontal.3").font(.system(size: 12))
                Text("Adjustment").font(.system(size: 11.5))
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .foregroundStyle(Theme.secondaryInk)
        .fixedSize()
        .help("Add an adjustment layer: it changes how the layers below look, without changing their pixels")
    }
}

/// The Adjustments panel (FR-8.4): the active adjustment layer's settings, or a way to add one.
struct AdjustmentsPanel: View {
    @Bindable var editor: Editor

    var body: some View {
        let adjustment = editor.activeAdjustment
        let choice = adjustment.flatMap(AdjustmentChoice.init)
        VStack(alignment: .leading, spacing: 12) {
            if let adjustment, let choice {
                if let kind = choice.kind {
                    ForEach(Array(kind.parameters.enumerated()), id: \.offset) { index, parameter in
                        slider(parameter, value: adjustment.sliderValues[safe: index] ?? parameter.defaultValue) { newValue in
                            var values = adjustment.sliderValues
                            values[index] = newValue
                            editor.previewAdjustment(kind.effect(values))
                        }
                    }
                } else {
                    Text("\(choice.title) has no settings.").font(.system(size: 12)).foregroundStyle(Theme.secondaryInk)
                }
                HStack(spacing: 8) {
                    Toggle("Preview", isOn: Binding(
                        get: { editor.layers[editor.activeLayerIndex].isVisible },
                        set: { editor.setLayerVisible($0, at: editor.activeLayerIndex) }
                    ))
                    .font(.system(size: 12))
                    .help("Show or hide this adjustment")
                    Spacer()
                    if choice.kind != nil {
                        Button("Reset") { editor.setAdjustment(choice.startingAdjustment) }
                            .help("Back to the starting settings")
                    }
                    Button("Apply") { editor.applyAdjustmentLayer() }
                        .disabled(!LayerActions.canApplyAdjustment(editor.canvas))
                        .help("Apply Adjustment: turn it into pixels on the layer below")
                }
                .controlSize(.small)
            } else {
                Text("Select an adjustment layer to change its settings, or add one:")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                    ForEach(AdjustmentChoice.allCases, id: \.self) { choice in
                        Button { editor.addAdjustmentLayer(choice.startingAdjustment, named: choice.title) } label: {
                            Label(choice.title, systemImage: choice.symbol)
                                .font(.system(size: 11.5))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .frame(height: 24)
                                .background(Theme.field, in: RoundedRectangle(cornerRadius: 7))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    private func slider(_ parameter: EffectKind.Parameter, value: Double, set: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(parameter.label).font(.system(size: 12))
                Spacer()
                Text(formatted(value, parameter))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(Theme.field, in: RoundedRectangle(cornerRadius: 5))
            }
            Slider(value: Binding(get: { value }, set: { set($0.rounded()) }), in: parameter.range) { editing in
                if !editing { editor.finishLayerSettings() }
            }
            .controlSize(.small)
        }
    }

    private func formatted(_ value: Double, _ parameter: EffectKind.Parameter) -> String {
        let number = Int(value.rounded())
        let signed = parameter.range.lowerBound < 0 && number > 0 ? "+\(number)" : "\(number)"
        return signed + parameter.unit
    }
}
