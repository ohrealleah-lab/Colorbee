import ColorbeeCore

/// The tools in the Retouch gallery (FR-4.6). Each keeps its own size.
enum RetouchKind: CaseIterable {
    case remove
    case spotHeal
    case cloneStamp
    case lighten
    case darken
    case saturate
    case desaturate
    case blur
    case sharpen
    case smudge

    var name: String {
        switch self {
        case .remove: "Remove"
        case .spotHeal: "Spot Heal"
        case .cloneStamp: "Clone Stamp"
        case .lighten: "Lighten"
        case .darken: "Darken"
        case .saturate: "Saturate"
        case .desaturate: "Desaturate"
        case .blur: "Blur"
        case .sharpen: "Sharpen"
        case .smudge: "Smudge"
        }
    }

    var symbol: String {
        switch self {
        case .remove: "wand.and.rays"
        case .spotHeal: "bandage"
        case .cloneStamp: "seal"
        case .lighten: "sun.max"
        case .darken: "moon"
        case .saturate: "drop.halffull"
        case .desaturate: "circle.lefthalf.filled"
        case .blur: "aqi.medium"
        case .sharpen: "triangle"
        case .smudge: "hand.point.up.left"
        }
    }

    /// What it's for, in the palette bar.
    var hint: String {
        switch self {
        case .remove: "For simple backgrounds: sky, walls, sand, screenshots · For busy spots, use the Clone Stamp"
        case .spotHeal: "Click a spot, or brush over a thin scratch · For anything bigger, use Remove"
        case .cloneStamp: "Option-click where to copy from"
        case .smudge: "Drag colors like a finger through wet paint"
        default: "Another stroke adds more"
        }
    }

    /// Remove and Spot Heal fill the painted area when the stroke ends; the others change pixels as you paint.
    var fillsArea: Bool { self == .remove || self == .spotHeal }

    /// Which tools have a Strength setting, and which a tone Range.
    var hasStrength: Bool { !fillsArea && self != .cloneStamp }
    var hasRange: Bool { self == .lighten || self == .darken }
    /// Remove, Spot Heal and the Clone Stamp read pixels, so they can read all visible layers.
    var canSampleAllLayers: Bool { fillsArea || self == .cloneStamp }

    func adjustment(range: ToneRange) -> LocalAdjustment? {
        switch self {
        case .lighten: .lighten(range)
        case .darken: .darken(range)
        case .saturate: .saturate
        case .desaturate: .desaturate
        case .blur: .blur
        case .sharpen: .sharpen
        default: nil
        }
    }

    var defaultSize: Double {
        switch self {
        case .remove: 40
        case .spotHeal: 16
        case .cloneStamp, .smudge: 30
        default: 40
        }
    }

    var sizePresets: [Int] {
        switch self {
        case .spotHeal: [6, 10, 16, 24, 40]
        case .cloneStamp, .smudge: [10, 20, 30, 50, 80]
        default: [10, 20, 40, 80, 160]
        }
    }
}
