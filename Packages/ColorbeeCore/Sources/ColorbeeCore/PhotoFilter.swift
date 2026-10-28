import Foundation

/// A named recipe of color and tone changes, the vignette and grain (FR-9.5, FR-9.7). Built-in filters and "Save as
/// Filter…" hold one Adjust Photo step; "Save Filter from Layers" holds one step per adjustment layer. Filters never
/// crop or straighten.
public struct PhotoFilter: Sendable, Hashable, Codable {
    public var name: String
    public var steps: [Effect]
    public var isBuiltIn: Bool

    public init(name: String, steps: [Effect], isBuiltIn: Bool = false) {
        self.name = name
        self.steps = steps.compactMap(\.forFilters)
        self.isBuiltIn = isBuiltIn
    }

    public init(name: String, adjustments: PhotoAdjustments, isBuiltIn: Bool = false) {
        self.init(name: name, steps: [.photo(PhotoEdit(adjustments: adjustments))], isBuiltIn: isBuiltIn)
    }

    /// The steps at `intensity` (0...1): each value scaled toward no change. Steps with no amount to scale
    /// (Invert, Posterize) apply in full at any intensity above zero.
    public func steps(atIntensity intensity: Double) -> [Effect] {
        guard intensity > 0 else { return [] }
        return steps.map { $0.scaled(by: intensity) }
    }

    /// The visible adjustment layers of `layers`, bottom to top, as one filter, each with only what a filter may
    /// hold. An Adjust Photo layer with Sharpness keeps its other sliders (stage 1a); a Blur layer is skipped.
    public static func fromLayers(_ layers: [Layer], name: String) -> PhotoFilter? {
        let filter = PhotoFilter(name: name, steps: layers.filter(\.isVisible).compactMap(\.adjustment))
        return filter.steps.isEmpty ? nil : filter
    }

    // MARK: Built in

    public static let builtIn: [PhotoFilter] = {
        let vivid: [PhotoAdjustments.Slider: Double] = [.saturation: 25, .vibrance: 20, .contrast: 15, .highlights: -10, .shadows: 10]
        let dramatic: [PhotoAdjustments.Slider: Double] = [.contrast: 35, .highlights: -30, .shadows: -20, .saturation: -10, .blackPoint: 15]
        func filter(_ name: String, _ values: [PhotoAdjustments.Slider: Double]) -> PhotoFilter {
            PhotoFilter(name: name, adjustments: PhotoAdjustments(values), isBuiltIn: true)
        }
        return [
            filter("Vivid", vivid),
            filter("Vivid Warm", vivid.merging([.warmth: 25]) { $1 }),
            filter("Vivid Cool", vivid.merging([.warmth: -25]) { $1 }),
            filter("Dramatic", dramatic),
            filter("Dramatic Warm", dramatic.merging([.warmth: 25]) { $1 }),
            filter("Dramatic Cool", dramatic.merging([.warmth: -25]) { $1 }),
            filter("Mono", [.saturation: -100, .contrast: 5]),
            filter("Silvertone", [.saturation: -100, .contrast: 20, .brightness: 10, .highlights: 10, .blackPoint: 5, .warmth: -8]),
            filter("Noir", [.saturation: -100, .contrast: 55, .blackPoint: 30, .highlights: -20, .shadows: -25]),
        ]
    }()

    // MARK: Files (.colorbeefilter)

    private struct Stored: Codable {
        var version = 1
        var name: String
        var steps: [LenientStep]
    }

    /// A step that reads back as none if it's of a kind this version doesn't know, so the filter keeps the rest.
    struct LenientStep: Codable {
        var effect: Effect?

        init(_ effect: Effect) { self.effect = effect }
        init(from decoder: Decoder) throws { effect = try? Effect(from: decoder) }
        func encode(to encoder: Encoder) throws { try effect?.encode(to: encoder) }
    }

    public func exported() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Stored(name: name, steps: steps.map(LenientStep.init)))
    }

    public static func imported(from data: Data) throws -> PhotoFilter {
        let stored = try JSONDecoder().decode(Stored.self, from: data)
        let filter = PhotoFilter(name: stored.name, steps: stored.steps.compactMap(\.effect))
        guard !filter.steps.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        return filter
    }
}

extension Effect {
    /// The part of this adjustment a filter may hold (FR-9.7): color and tone, and Adjust Photo's Vignette. An Adjust
    /// Photo step loses just the sliders filters leave out, rather than being dropped whole. Nil when nothing's left.
    public var forFilters: Effect? {
        switch self {
        case .invert, .desaturate, .brightnessContrast, .hueSaturation, .levels, .curves, .sepia, .posterize, .look:
            return self
        case .photo(var edit):
            edit.adjustments = edit.adjustments.forFilters
            // Sharpness's and Noise Reduction's finer settings go with them; the Vignette's shape and Grain stay.
            edit.detail = nil
            edit.showsSharpeningMask = false
            return edit.isNeutral ? nil : .photo(edit)
        default:
            return nil
        }
    }

    /// Toward no change by `factor` (0...1), for a filter's intensity.
    public func scaled(by factor: Double) -> Effect {
        let f = min(max(factor, 0), 1)
        switch self {
        case .brightnessContrast(let b, let c): return .brightnessContrast(brightness: b * f, contrast: c * f)
        case .hueSaturation(let h, let s, let l): return .hueSaturation(hue: h * f, saturation: s * f, lightness: l * f)
        case .levels(let levels):
            return .levels(Levels(black: levels.black * f, white: 255 - (255 - levels.white) * f, gamma: pow(levels.gamma, f)))
        case .curves(var curves):
            for channel in Curves.Channel.allCases {
                curves[channel] = curves[channel].map { Curves.Point(x: $0.x, y: $0.x + ($0.y - $0.x) * f) }
            }
            return .curves(curves)
        case .sepia(let amount): return .sepia(amount: amount * f)
        case .look(var look):
            look.amount *= f
            return .look(look)
        case .desaturate: return .photo(PhotoEdit(adjustments: PhotoAdjustments([.saturation: -100 * f])))
        case .photo(var edit):
            edit.adjustments = edit.adjustments.scaled(by: f)
            edit.filterIntensity *= f
            edit.mixer = edit.mixer?.scaled(by: f)
            edit.grading = edit.grading?.scaled(by: f)
            edit.pointColors = edit.pointColors?.scaled(by: f)
            return .photo(edit)
        default: return self
        }
    }
}

extension PhotoFilter {
    private enum CodingKeys: String, CodingKey {
        case name, steps, isBuiltIn
    }

    /// Through `init`, so a filter read from a project holds only what filters may, like an imported one. A step of a
    /// kind this version doesn't know is skipped.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(name: try container.decode(String.self, forKey: .name),
                  steps: try container.decode([LenientStep].self, forKey: .steps).compactMap(\.effect),
                  isBuiltIn: try container.decode(Bool.self, forKey: .isBuiltIn))
    }
}
