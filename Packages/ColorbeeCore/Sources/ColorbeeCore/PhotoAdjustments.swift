import Foundation
import simd

/// The Adjust Photo panel's sliders (FR-9.5, FR-9.7), modeled on the iPhone Photos editor. Each is -100...100 with 0
/// meaning no change, except Sharpness, Definition and Noise Reduction, which are 0...100.
public struct PhotoAdjustments: Sendable, Hashable, Codable {
    public enum Slider: String, CaseIterable, Sendable, Codable {
        case exposure, brilliance, dehaze, highlights, shadows, contrast, brightness, whites, blackPoint
        case saturation, vibrance, warmth, tint
        case sharpness, definition, texture, noiseReduction, vignette

        public var title: String {
            switch self {
            case .exposure: "Exposure"
            case .brilliance: "Brilliance"
            case .dehaze: "Dehaze"
            case .highlights: "Highlights"
            case .shadows: "Shadows"
            case .contrast: "Contrast"
            case .brightness: "Brightness"
            case .whites: "Whites"
            case .blackPoint: "Black Point"
            case .saturation: "Saturation"
            case .vibrance: "Vibrance"
            case .warmth: "Warmth"
            case .tint: "Tint"
            case .sharpness: "Sharpness"
            case .definition: "Definition"
            case .texture: "Texture"
            case .noiseReduction: "Noise Reduction"
            case .vignette: "Vignette"
            }
        }

        public var range: ClosedRange<Double> {
            switch self {
            case .sharpness, .definition, .noiseReduction: 0...100
            default: -100...100
            }
        }

        /// What filters may hold (FR-9.7): color and tone, Dehaze and Vignette (Leah, 2026-10-27). Sharpness,
        /// Definition, Texture and Noise Reduction depend on each photo's own detail, so they stay out.
        public var inFilters: Bool {
            switch self {
            case .sharpness, .definition, .texture, .noiseReduction: false
            default: true
            }
        }

        /// The sliders beta 7 knows, saved in `values`. Sliders added since are saved under `added`, which older
        /// versions skip, so they still open the rest of the adjustment (stage 1a). Beta 7 can't read a name it
        /// doesn't know in `values`, and would lose the whole adjustment.
        static let original: Set<Slider> = [
            .exposure, .brilliance, .highlights, .shadows, .contrast, .brightness, .blackPoint,
            .saturation, .vibrance, .warmth, .tint, .sharpness, .definition, .noiseReduction, .vignette,
        ]
    }

    public var values: [Slider: Double] = [:]

    public init(_ values: [Slider: Double] = [:]) {
        self.values = values.filter { $0.value != 0 }
    }

    public subscript(slider: Slider) -> Double {
        get { values[slider] ?? 0 }
        set {
            let clamped = min(max(newValue, slider.range.lowerBound), slider.range.upperBound)
            values[slider] = clamped == 0 ? nil : clamped
        }
    }

    public var isNeutral: Bool { values.isEmpty }

    /// Every value times `factor` (a filter's intensity: 0.5 is half of each).
    public func scaled(by factor: Double) -> PhotoAdjustments {
        PhotoAdjustments(values.mapValues { $0 * factor })
    }

    /// Only the sliders a filter may hold.
    public var forFilters: PhotoAdjustments {
        PhotoAdjustments(values.filter { $0.key.inFilters })
    }

    var hasDetail: Bool { self[.sharpness] != 0 || self[.definition] != 0 || self[.texture] != 0 || self[.noiseReduction] != 0 }

    // MARK: The math (mirrored in Shaders.metal through ColorLookup, plus photo_fragment for the rest)

    /// The per-pixel color and tone part, in slider order: light, then color.
    public var colorTransform: (Pixel) -> Pixel {
        let exposure = pow(2, self[.exposure] / 50)
        let dehaze = self[.dehaze] / 100
        let brilliance = self[.brilliance] / 100
        let highlights = self[.highlights] / 100, shadows = self[.shadows] / 100
        let contrast = 1 + self[.contrast] / 100
        let brightness = pow(2, -self[.brightness] / 100)
        // Whites moves the white point, like Black Point mirrored: +100 stretches 0.75 up to white.
        let whitePoint = 1 - self[.whites] / 100 * 0.25
        let blackPoint = self[.blackPoint] / 100 * 0.25
        let saturation = 1 + self[.saturation] / 100
        let vibrance = self[.vibrance] / 100
        let warmth = self[.warmth] / 100 * 0.15, tint = self[.tint] / 100
        return { pixel in
            var c = SIMD3(Double(pixel.r), Double(pixel.g), Double(pixel.b)) / 255
            if exposure != 1 {
                c = Self.power(Self.power(c, 2.2) * exposure, 1 / 2.2)
            }
            if dehaze != 0 { c = Self.dehazed(Self.clamped(c), dehaze) }
            // Brilliance lifts shadows and holds back highlights, then adds a little midtone contrast.
            let shadowLift = shadows + brilliance * 0.5, highlightPull = highlights - brilliance * 0.5
            if shadowLift != 0 || highlightPull != 0 || brilliance != 0 {
                let l = Self.luma(c)
                let shadowWeight = 1 - Self.smoothstep(0, 0.5, l), highlightWeight = Self.smoothstep(0.5, 1, l)
                for i in 0..<3 {
                    let v = c[i]
                    var out = v
                    if shadowLift != 0 { out += 0.35 * shadowLift * shadowWeight * (shadowLift > 0 ? 1 - v : v) }
                    if highlightPull != 0 { out += 0.35 * highlightPull * highlightWeight * (highlightPull > 0 ? 1 - v : v) }
                    c[i] = out
                }
                if brilliance != 0 { c = 0.5 + (c - 0.5) * (1 + 0.2 * abs(brilliance)) }
            }
            if contrast != 1 { c = 0.5 + (c - 0.5) * contrast }
            c = Self.clamped(c)
            if brightness != 1 { c = Self.power(c, brightness) }
            if whitePoint != 1 {
                // Weighted by brightness, so only the brightest parts move much (FR-9.7).
                let weight = Self.smoothstep(0.3, 1, Self.luma(c))
                c = Self.clamped(c + (c / whitePoint - c) * weight)
            }
            if blackPoint > 0 {
                c = (c - blackPoint) / (1 - blackPoint)
            } else if blackPoint < 0 {
                c = -blackPoint + c * (1 + blackPoint)
            }
            c = Self.clamped(c)
            if saturation != 1 || vibrance != 0 {
                let l = Self.luma(c)
                // Vibrance boosts muted colors more than vivid ones, so skin tones don't go orange.
                let chroma = (c.max() - c.min())
                let boost = saturation * (1 + vibrance * (vibrance > 0 ? 1 - chroma : 1))
                c = l + (c - l) * boost
            }
            if warmth != 0 {
                c.x *= 1 + warmth
                c.z *= 1 - warmth
            }
            if tint != 0 {
                // Positive is magenta, negative green.
                c.y *= 1 - tint * 0.12
                c.x *= 1 + tint * 0.04
                c.z *= 1 + tint * 0.04
            }
            c = Self.clamped(c) * 255
            return Pixel(r: UInt8(c.x.rounded()), g: UInt8(c.y.rounded()), b: UInt8(c.z.rounded()), a: pixel.a)
        }
    }

    /// Dehaze (FR-9.7) on one pixel, so it goes through the color table like the color sliders. Haze is an even veil
    /// of light gray over the picture: a pixel is its true color mixed with `hazeGray`. +100 takes a 60% veil off
    /// (bringing back contrast and color, darks most), and −100 lays one on; −n exactly undoes +n. White stays white.
    static func dehazed(_ c: SIMD3<Double>, _ amount: Double) -> SIMD3<Double> {
        let veil = 0.6 * abs(amount)
        let gray = SIMD3(repeating: hazeGray)
        if amount > 0 { return clamped((c - gray * veil) / (1 - veil)) }
        return c * (1 - veil) + gray * veil
    }

    static let hazeGray = 0.88

    static func luma(_ c: SIMD3<Double>) -> Double { 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z }

    static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    static func power(_ c: SIMD3<Double>, _ exponent: Double) -> SIMD3<Double> {
        SIMD3(pow(c.x, exponent), pow(c.y, exponent), pow(c.z, exponent))
    }

    static func clamped(_ c: SIMD3<Double>) -> SIMD3<Double> {
        simd_clamp(c, SIMD3(repeating: 0), SIMD3(repeating: 1))
    }

    /// Blur radii for the detail sliders, in image pixels. The display scales them with the zoom.
    public static let fineRadius = 1.2
    public static let textureRadius = 3.0
    public static let definitionRadius = 12.0

    /// Sharpness, Definition, Texture and Noise Reduction for one pixel, from its own color and three blurred copies
    /// (straight colors, 0...1). Returns the new color. Texture works on detail up to a few pixels across, against
    /// a blur a quarter of Definition's, so it brings out (or, negative, smooths) texture without wide halos.
    static func detail(_ original: SIMD3<Double>, fine: SIMD3<Double>, medium: SIMD3<Double>, wide: SIMD3<Double>,
                       sharpness: Double, definition: Double, texture: Double, noiseReduction: Double) -> SIMD3<Double> {
        var c = original
        if noiseReduction > 0 {
            // Smooth only where the pixel is close to its surroundings, so edges stay crisp.
            let difference = simd_abs(original - fine).max()
            let weight = noiseReduction * (1 - smoothstep(0.04, 0.2, difference))
            c += (fine - c) * weight
        }
        if sharpness > 0 { c += (original - fine) * sharpness * 1.5 }
        if definition > 0 { c += (original - wide) * definition * 0.6 }
        if texture != 0 { c += (original - medium) * texture * 0.8 }
        return clamped(c)
    }
}

/// What the Adjust Photo panel holds (FR-9.5): a filter at an intensity, then the sliders on top.
/// New controls that aren't a single slider get keys of their own here: older versions skip keys they don't know.
public struct PhotoEdit: Sendable, Hashable, Codable {
    public var adjustments: PhotoAdjustments
    public var filter: PhotoFilter?
    /// 0...100 percent.
    public var filterIntensity: Double
    /// The Color Mixer and Black & White (FR-9.7); nil when untouched.
    public var mixer: ColorMixer? {
        didSet { if mixer?.isNeutral == true { mixer = nil } }
    }

    public init(adjustments: PhotoAdjustments = PhotoAdjustments(), filter: PhotoFilter? = nil, filterIntensity: Double = 100,
                mixer: ColorMixer? = nil) {
        self.adjustments = adjustments
        self.filter = filter
        self.filterIntensity = filterIntensity
        self.mixer = mixer?.isNeutral == true ? nil : mixer
    }

    public var isNeutral: Bool { adjustments.isNeutral && (filter == nil || filterIntensity == 0) && mixer == nil }

    /// The color and tone part: the filter's steps at its intensity, then the sliders' color and tone, then the
    /// Color Mixer.
    public var colorTransform: (Pixel) -> Pixel {
        let steps = (filter?.steps(atIntensity: filterIntensity / 100) ?? []).compactMap(\.colorTransform)
        let own = adjustments.colorTransform
        let mixed = mixer?.transform
        return { pixel in
            let adjusted = own(steps.reduce(pixel) { $1($0) })
            return mixed?(adjusted) ?? adjusted
        }
    }

    /// Whether the display needs `ColorLookup.fineSize` to show this closely: a Color Mixer here or in the filter.
    public var needsFineColorTable: Bool {
        mixer != nil || (filter?.steps ?? []).contains { step in
            if case .photo(let edit) = step { return edit.needsFineColorTable }
            return false
        }
    }

    /// What Save as Filter keeps of the panel's own settings (its filter is kept separately): everything a filter may hold.
    public var filterPart: PhotoEdit {
        var part = self
        part.adjustments = adjustments.forFilters
        part.filter = nil
        part.filterIntensity = 100
        return part
    }

    /// What stays on the panel after Save as Filter: the settings filters leave out.
    public var partFiltersLeaveOut: PhotoEdit {
        PhotoEdit(adjustments: PhotoAdjustments(adjustments.values.filter { !$0.key.inFilters }))
    }

    /// The vignettes, in the order they apply after all the color: the filter's at its intensity, then the
    /// panel's own (Leah, 2026-10-27). Zero amounts are left out.
    public var vignetteAmounts: [Double] {
        let fromFilter = (filter?.steps(atIntensity: filterIntensity / 100) ?? []).flatMap { step -> [Double] in
            if case .photo(let edit) = step { return edit.vignetteAmounts }
            return []
        }
        return (fromFilter + [adjustments[.vignette]]).filter { $0 != 0 }
    }
}

extension PhotoAdjustments {
    private enum CodingKeys: String, CodingKey {
        case values, added
    }

    /// Values from a file are kept within each slider's range. A slider this version doesn't know is skipped, so a
    /// file from a newer Colorbee opens with only that slider missing.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        // Name and value, one after the other: how a dictionary keyed by `Slider` was always saved.
        var list = try container.nestedUnkeyedContainer(forKey: .values)
        while !list.isAtEnd {
            let name = try list.decode(String.self), value = try list.decode(Double.self)
            set(name, value)
        }
        for (name, value) in try container.decodeIfPresent([String: Double].self, forKey: .added) ?? [:] {
            set(name, value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var list = container.nestedUnkeyedContainer(forKey: .values)
        var added: [String: Double] = [:]
        for slider in Slider.allCases {
            guard let value = values[slider] else { continue }
            if Slider.original.contains(slider) {
                try list.encode(slider.rawValue)
                try list.encode(value)
            } else {
                added[slider.rawValue] = value
            }
        }
        if !added.isEmpty { try container.encode(added, forKey: .added) }
    }

    private mutating func set(_ name: String, _ value: Double) {
        guard let slider = Slider(rawValue: name), value.isFinite else { return }
        self[slider] = value
    }
}

extension PhotoEdit {
    private enum CodingKeys: String, CodingKey {
        case adjustments, filter, filterIntensity, mixer
    }

    /// A control this version can't read is left at neutral rather than losing the whole adjustment.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let intensity = try container.decode(Double.self, forKey: .filterIntensity)
        self.init(adjustments: try container.decode(PhotoAdjustments.self, forKey: .adjustments),
                  filter: try container.decodeIfPresent(PhotoFilter.self, forKey: .filter),
                  filterIntensity: intensity.isFinite ? min(max(intensity, 0), 100) : 100,
                  mixer: try? container.decodeIfPresent(ColorMixer.self, forKey: .mixer))
    }
}
