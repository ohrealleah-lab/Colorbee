/// The tools in the Retouch gallery (FR-4.6). Each keeps its own size.
enum RetouchKind: CaseIterable {
    case remove
    case spotHeal

    var name: String {
        switch self {
        case .remove: "Remove"
        case .spotHeal: "Spot Heal"
        }
    }

    var symbol: String {
        switch self {
        case .remove: "wand.and.rays"
        case .spotHeal: "bandage"
        }
    }

    /// What it's for, in the palette bar.
    var hint: String {
        switch self {
        case .remove: "For simple backgrounds: sky, walls, sand, screenshots · For busy spots, use the Clone Stamp"
        case .spotHeal: "Click a spot, or brush over a thin scratch · For anything bigger, use Remove"
        }
    }

    var defaultSize: Double {
        switch self {
        case .remove: 40
        case .spotHeal: 16
        }
    }

    var sizePresets: [Int] {
        switch self {
        case .remove: [10, 20, 40, 80, 160]
        case .spotHeal: [6, 10, 16, 24, 40]
        }
    }
}
