import ColorbeeCore
import CoreGraphics
import Foundation

/// An effect with a dialog, and the sliders it shows.
enum EffectKind: CaseIterable {
    case gaussianBlur
    case pixelate
    case sharpen
    case hueSaturation
    case levels
    case curves
    case sepia
    case posterize
    case addNoise
    case motionBlur
    case emboss
    case vignette
    case adjustPhoto
    case dropShadow
    case border
    case spotlight
    case straighten
    case perspective
    case crop
    /// Waiting for a click on one of several subjects (Remove Background, Select Subject).
    case pickSubject
    /// Edit ▸ Color Range… and Luminance Range… (FR-9.7 item 3): a selection chosen in the bar, previewed with a tint.
    case colorRange
    case luminanceRange
    /// Edit ▸ Graduated Selection (FR-9.7 item 3): a dragged line, fully selected at its start and fading to its end.
    case graduatedSelection

    /// Drop Shadow, Border and Straighten change the canvas's size, so their preview is a real step, redone as
    /// settings change.
    var previewsAsStep: Bool { self == .dropShadow || self == .border || self == .straighten }

    /// Straighten, Perspective Correction and Crop: dragging on the canvas sets them, rather than panning.
    var isCanvasTool: Bool {
        self == .straighten || self == .perspective || self == .crop || self == .pickSubject || choosesSelection
    }

    /// Color Range and Luminance Range: they make a selection rather than change pixels.
    var choosesSelection: Bool { self == .colorRange || self == .luminanceRange || self == .graduatedSelection }

    /// Changes every layer, not just the active one.
    var appliesToWholeImage: Bool { self == .straighten || self == .perspective || self == .crop }

    struct Parameter {
        let label: String
        let range: ClosedRange<Double>
        let defaultValue: Double
        let unit: String
        /// The slider moves in steps of this size.
        var step: Double = 1
        /// A picker instead of a slider: the value is the chosen option's index.
        var options: [String]? = nil
    }

    var title: String {
        switch self {
        case .gaussianBlur: "Gaussian Blur"
        case .pixelate: "Pixelate"
        case .sharpen: "Sharpen"
        case .hueSaturation: "Hue/Saturation"
        case .levels: "Levels"
        case .curves: "Curves"
        case .sepia: "Sepia"
        case .posterize: "Posterize"
        case .addNoise: "Add Noise"
        case .motionBlur: "Motion Blur"
        case .emboss: "Emboss"
        case .vignette: "Vignette"
        case .adjustPhoto: "Adjust Photo"
        case .dropShadow: "Drop Shadow"
        case .border: "Border"
        case .spotlight: "Spotlight"
        case .straighten: "Straighten"
        case .perspective: "Perspective Correction"
        case .crop: "Crop"
        case .pickSubject: "Pick a Subject"
        case .colorRange: "Color Range"
        case .luminanceRange: "Luminance Range"
        case .graduatedSelection: "Graduated Selection"
        }
    }

    /// How a range's selection combines with the one there already (Leah, 2026-10-28).
    static let combineOptions = ["Replace", "Add", "Subtract", "Intersect"]

    var parameters: [Parameter] {
        switch self {
        case .gaussianBlur: [Parameter(label: "Radius", range: 1...100, defaultValue: 8, unit: "px")]
        case .pixelate: [Parameter(label: "Cell size", range: 2...100, defaultValue: 12, unit: "px")]
        case .sharpen: [Parameter(label: "Amount", range: 0...200, defaultValue: 60, unit: "%")]
        case .hueSaturation: [
            Parameter(label: "Hue", range: -180...180, defaultValue: 0, unit: "°"),
            Parameter(label: "Saturation", range: -100...100, defaultValue: 0, unit: ""),
            Parameter(label: "Lightness", range: -100...100, defaultValue: 0, unit: ""),
        ]
        case .levels: [
            Parameter(label: "Black", range: 0...254, defaultValue: 0, unit: ""),
            Parameter(label: "Midtones", range: 0.1...9.99, defaultValue: 1, unit: "", step: 0.01),
            Parameter(label: "White", range: 1...255, defaultValue: 255, unit: ""),
        ]
        case .curves, .adjustPhoto, .perspective, .crop, .pickSubject: []
        case .colorRange: [
            Parameter(label: "Fuzziness", range: 0...100, defaultValue: 25, unit: "%"),
            Parameter(label: "Selection", range: 0...3, defaultValue: 0, unit: "", options: Self.combineOptions),
        ]
        // From and To are shown as one two-handle slider, with the Shadows, Midtones and Highlights choices.
        case .luminanceRange: [
            Parameter(label: "From", range: 0...100, defaultValue: LuminanceRange.shadows.lower, unit: ""),
            Parameter(label: "To", range: 0...100, defaultValue: LuminanceRange.shadows.upper, unit: ""),
            Parameter(label: "Smoothness", range: 0...100, defaultValue: 50, unit: ""),
            Parameter(label: "Selection", range: 0...3, defaultValue: 0, unit: "", options: Self.combineOptions),
        ]
        case .graduatedSelection: [
            Parameter(label: "Selection", range: 0...3, defaultValue: 0, unit: "", options: Self.combineOptions),
        ]
        case .straighten: [
            Parameter(label: "Angle", range: -45...45, defaultValue: 0, unit: "°", step: 0.1),
            Parameter(label: "Corners", range: 0...1, defaultValue: 0, unit: "", options: ["Crop to Fit", "Grow Canvas"]),
        ]
        case .dropShadow: [
            Parameter(label: "Across", range: -200...200, defaultValue: 12, unit: "px"),
            Parameter(label: "Down", range: -200...200, defaultValue: 12, unit: "px"),
            Parameter(label: "Blur", range: 0...100, defaultValue: 10, unit: "px"),
            Parameter(label: "Opacity", range: 0...100, defaultValue: 50, unit: "%"),
            Parameter(label: "Color", range: 0...1, defaultValue: 0, unit: "", options: ["Black", "Color 1"]),
        ]
        case .border: [
            Parameter(label: "Width", range: 1...200, defaultValue: 8, unit: "px"),
            Parameter(label: "Color", range: 0...3, defaultValue: 0, unit: "", options: ["Color 1", "Color 2", "Black", "White"]),
        ]
        case .spotlight: [
            Parameter(label: "Outside", range: 0...2, defaultValue: 0, unit: "", options: ["Dim", "Blur", "Desaturate"]),
            Parameter(label: "Amount", range: 0...100, defaultValue: 60, unit: "%"),
        ]
        case .sepia: [Parameter(label: "Amount", range: 0...100, defaultValue: 100, unit: "%")]
        case .posterize: [Parameter(label: "Levels", range: 2...32, defaultValue: 4, unit: "")]
        case .addNoise: [
            Parameter(label: "Amount", range: 0...100, defaultValue: 20, unit: "%"),
            Parameter(label: "Noise", range: 0...1, defaultValue: 0, unit: "", options: ["Color", "Monochrome"]),
        ]
        case .motionBlur: [
            Parameter(label: "Angle", range: -180...180, defaultValue: 0, unit: "°"),
            Parameter(label: "Distance", range: 1...200, defaultValue: 20, unit: "px"),
        ]
        case .emboss: [
            Parameter(label: "Angle", range: -180...180, defaultValue: 135, unit: "°"),
            Parameter(label: "Depth", range: 1...10, defaultValue: 3, unit: ""),
        ]
        case .vignette: [
            Parameter(label: "Amount", range: -100...100, defaultValue: 50, unit: ""),
            Parameter(label: "Size", range: 0...100, defaultValue: 50, unit: ""),
        ]
        }
    }

    func effect(_ values: [Double], curves: Curves = .identity, photo: PhotoEdit = PhotoEdit()) -> Effect {
        func value(_ index: Int) -> Double { values.indices.contains(index) ? values[index] : parameters[index].defaultValue }
        return switch self {
        case .gaussianBlur: .gaussianBlur(radius: value(0))
        case .pixelate: .pixelate(cellSize: Int(value(0).rounded()))
        case .sharpen: .sharpen(amount: value(0))
        case .hueSaturation: .hueSaturation(hue: value(0), saturation: value(1), lightness: value(2))
        case .levels: .levels(Levels(black: value(0), white: max(value(2), value(0) + 1), gamma: value(1)))
        case .curves: .curves(curves)
        case .sepia: .sepia(amount: value(0))
        case .posterize: .posterize(levels: Int(value(0).rounded()))
        case .addNoise: .addNoise(amount: value(0), monochrome: value(1) >= 0.5)
        case .motionBlur: .motionBlur(angle: value(0), distance: value(1))
        case .emboss: .emboss(angle: value(0), depth: value(1))
        case .vignette: .vignette(amount: value(0), size: value(1))
        case .adjustPhoto: .photo(photo)
        case .spotlight:
            switch Int(value(0).rounded()) {
            case 1: .gaussianBlur(radius: max(1, value(1) / 2))
            case 2: .hueSaturation(hue: 0, saturation: -value(1), lightness: 0)
            default: .brightnessContrast(brightness: -value(1) * 0.8, contrast: 0)
            }
        // Done by Decorations and ImageActions, not as an effect (see Editor.renderEffectPreview).
        case .dropShadow, .border, .straighten, .perspective, .crop, .pickSubject, .colorRange, .luminanceRange, .graduatedSelection: .invert
        }
    }
}

extension RedactionTreatment {
    var title: String {
        switch self {
        case .blur: "Blur"
        case .pixelate: "Pixelate"
        case .solidFill: "Solid Fill"
        }
    }
}
