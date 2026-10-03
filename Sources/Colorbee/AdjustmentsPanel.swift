import ColorbeeCore
import SwiftUI

/// The kinds of adjustment layer (FR-8.4, FR-9.5), with their names, icons and starting settings.
enum AdjustmentChoice: CaseIterable {
    case hueSaturation
    case levels
    case autoContrast
    case curves
    case desaturate
    case sepia
    case posterize
    case invert
    case gaussianBlur
    case sharpen
    case adjustPhoto

    var title: String {
        switch self {
        case .hueSaturation: "Hue/Saturation"
        case .levels: "Levels"
        case .autoContrast: "Auto Contrast"
        case .curves: "Curves"
        case .desaturate: "Desaturate"
        case .sepia: "Sepia"
        case .posterize: "Posterize"
        case .invert: "Invert"
        case .gaussianBlur: "Gaussian Blur"
        case .sharpen: "Sharpen"
        case .adjustPhoto: "Adjust Photo"
        }
    }

    var symbol: String {
        switch self {
        case .hueSaturation: "swatchpalette"
        case .levels: "chart.bar"
        case .autoContrast: "wand.and.rays"
        case .curves: "scribble.variable"
        case .desaturate: "circle.dotted.and.circle"
        case .sepia: "camera.filters"
        case .posterize: "square.grid.3x3.square"
        case .invert: "circle.lefthalf.filled"
        case .gaussianBlur: "drop"
        case .sharpen: "triangle"
        case .adjustPhoto: "camera.aperture"
        }
    }

    /// The settings a new adjustment layer starts with. Blur, Sharpen, Sepia and Posterize start with a
    /// visible amount, so adding one shows what it does. Auto Contrast is set from the image (Editor).
    var startingAdjustment: Effect {
        switch self {
        case .hueSaturation: .hueSaturation(hue: 0, saturation: 0, lightness: 0)
        case .levels, .autoContrast: .levels(.identity)
        case .curves: .curves(.identity)
        case .desaturate: .desaturate
        case .sepia: .sepia(amount: 100)
        case .posterize: .posterize(levels: 4)
        case .invert: .invert
        case .gaussianBlur: .gaussianBlur(radius: 8)
        case .sharpen: .sharpen(amount: 60)
        case .adjustPhoto: .photo(PhotoEdit())
        }
    }

    /// The sliders, shared with the Adjustments and Effects menus' live dialogs. Nil means no settings.
    var kind: EffectKind? {
        switch self {
        case .hueSaturation: .hueSaturation
        case .levels, .autoContrast: .levels
        case .curves: .curves
        case .sepia: .sepia
        case .posterize: .posterize
        case .gaussianBlur: .gaussianBlur
        case .sharpen: .sharpen
        case .desaturate, .invert, .adjustPhoto: nil
        }
    }

    /// The choice that edits `effect`. An Auto Contrast layer is a Levels layer.
    init?(_ effect: Effect) {
        switch effect {
        case .hueSaturation: self = .hueSaturation
        case .levels: self = .levels
        case .curves: self = .curves
        case .desaturate: self = .desaturate
        case .sepia: self = .sepia
        case .posterize: self = .posterize
        case .invert: self = .invert
        case .gaussianBlur: self = .gaussianBlur
        case .sharpen: self = .sharpen
        case .photo: self = .adjustPhoto
        // Brightness/Contrast was replaced by Adjust Photo's sliders (Leah); old layers of it have no settings here.
        case .brightnessContrast, .pixelate, .solidFill, .addNoise, .motionBlur, .emboss, .vignette: return nil
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
        case .levels(let levels): [levels.black, levels.gamma, levels.white]
        case .sepia(let amount): [amount]
        case .posterize(let levels): [Double(levels)]
        case .addNoise(let amount, let monochrome): [amount, monochrome ? 1 : 0]
        case .motionBlur(let angle, let distance): [angle, distance]
        case .emboss(let angle, let depth): [angle, depth]
        case .vignette(let amount, let size): [amount, size]
        case .invert, .desaturate, .solidFill, .curves, .photo: []
        }
    }
}

/// The menu of adjustment layers to add, used in the Layers panel's footer.
struct AddAdjustmentMenu: View {
    let editor: Editor

    var body: some View {
        Menu {
            ForEach(AdjustmentChoice.allCases, id: \.self) { choice in
                Button(choice.title, systemImage: choice.symbol) { editor.addAdjustmentLayer(choice) }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "slider.horizontal.3").font(.system(size: 12)).accessibilityHidden(true)
                Text("Adjustment").font(.system(size: 11.5))
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).accessibilityHidden(true)
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
    @State private var curvesChannel = Curves.Channel.rgb
    @State private var histogramBelow: Histogram?

    var body: some View {
        let adjustment = editor.activeAdjustment
        let choice = adjustment.flatMap(AdjustmentChoice.init)
        VStack(alignment: .leading, spacing: 12) {
            if let adjustment, let choice {
                if case .photo(let photo) = adjustment {
                    // Fifteen sliders and the filters don't fit under the Layers panel, so they scroll.
                    ScrollView {
                    PhotoControls(edit: photo, editor: editor) { editor.previewAdjustment(.photo($0)) } onFinish: {
                        editor.finishLayerSettings()
                    } onAuto: {
                        let below = editor.canvas.composited(through: max(0, editor.activeLayerIndex - 1))
                        var changed = photo
                        let auto = PhotoAdjustments.auto(for: below)
                        for slider in [PhotoAdjustments.Slider.exposure, .brilliance, .highlights, .shadows, .contrast, .warmth, .tint, .vibrance] {
                            changed.adjustments[slider] = auto[slider]
                        }
                        editor.setAdjustment(.photo(changed))
                    }
                    }
                    .frame(maxHeight: 340)
                }
                if case .curves(let curves) = adjustment {
                    CurvesEditor(curves: curves, channel: $curvesChannel) { editor.previewAdjustment(.curves($0)) } onFinish: {
                        editor.finishLayerSettings()
                    }
                }
                if choice.kind == .levels {
                    HistogramView(histogram: histogramBelow, black: adjustment.sliderValues[0], white: adjustment.sliderValues[2])
                        .frame(height: 44)
                        .task(id: editor.canvas.activeLayer.id) { histogramBelow = editor.histogramBelowActiveLayer() }
                        .help("The layers below this one, by brightness")
                }
                if let kind = choice.kind {
                    ForEach(Array(kind.parameters.enumerated()), id: \.offset) { index, parameter in
                        slider(parameter, value: adjustment.sliderValues[safe: index] ?? parameter.defaultValue) { newValue in
                            var values = adjustment.sliderValues
                            values[index] = newValue
                            editor.previewAdjustment(kind.effect(values))
                        }
                    }
                } else if choice != .adjustPhoto {
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
                    if choice.kind == .levels {
                        Button("Auto") {
                            if let histogramBelow { editor.setAdjustment(.levels(Levels.auto(from: histogramBelow))) }
                        }
                        .help("Set the black and white points to the darkest and lightest pixels below")
                    }
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
                // One way in from the sidebar: the Layers panel's Adjustment ▾ menu (Leah, FRD §23).
                Text("Select an adjustment layer to change its settings. To add one, use Adjustment ▾ in the Layers panel, or Layer ▸ New Adjustment Layer.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
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
            Slider(value: Binding(get: { value }, set: { set(($0 / parameter.step).rounded() * parameter.step) }), in: parameter.range) { editing in
                if !editing { editor.finishLayerSettings() }
            }
            .controlSize(.small)
        }
    }

    private func formatted(_ value: Double, _ parameter: EffectKind.Parameter) -> String {
        guard parameter.step >= 1 else { return String(format: "%.2f", value) + parameter.unit }
        let number = Int(value.rounded())
        let signed = parameter.range.lowerBound < 0 && number > 0 ? "+\(number)" : "\(number)"
        return signed + parameter.unit
    }
}
