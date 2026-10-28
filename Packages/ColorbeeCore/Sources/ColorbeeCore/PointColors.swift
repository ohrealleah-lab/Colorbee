import Foundation

/// Adjust Photo's Point Color (FR-9.7 item 2): colors picked from the picture, each with its own hue, saturation and
/// luminance shift and a Range for how wide "that color" is. Up to eight (Leah, 2026-10-27).
public struct PointColors: Sendable, Hashable {
    public struct Swatch: Sendable, Hashable {
        /// The color as it was picked, before any change.
        public var color: Pixel
        /// −100...100 each; ±100 hue is about ±30°.
        public var hue: Double = 0
        public var saturation: Double = 0
        public var luminance: Double = 0
        /// 0...100, 50 by default: how far from the picked color still counts as it.
        public var range: Double = 50

        public init(color: Pixel, hue: Double = 0, saturation: Double = 0, luminance: Double = 0, range: Double = 50) {
            self.color = Pixel(r: color.r, g: color.g, b: color.b)
            self.hue = hue
            self.saturation = saturation
            self.luminance = luminance
            self.range = range
        }

        public var isNeutral: Bool { hue == 0 && saturation == 0 && luminance == 0 }

        func cleaned() -> Swatch {
            func number(_ v: Double, _ low: Double, _ high: Double, _ fallback: Double = 0) -> Double {
                v.isFinite ? min(max(v, low), high) : fallback
            }
            return Swatch(color: color, hue: number(hue, -100, 100), saturation: number(saturation, -100, 100),
                          luminance: number(luminance, -100, 100), range: number(range, 0, 100, 50))
        }
    }

    public static let maximum = 8

    public private(set) var swatches: [Swatch] = []
    /// While the Range slider is held, the picture shows only what that swatch touches; the rest turns gray
    /// (Leah, 2026-10-27). For the preview only: it's never saved.
    public var showsRangeOf: Int?

    public init(_ swatches: [Swatch] = []) {
        self.swatches = Array(swatches.prefix(Self.maximum).map { $0.cleaned() })
    }

    /// No swatch changes anything (picked colors with no shifts yet), and no Range preview.
    public var isNeutral: Bool { swatches.allSatisfy(\.isNeutral) && showsRangeOf == nil }

    public var isFull: Bool { swatches.count >= Self.maximum }
    public var isEmpty: Bool { swatches.isEmpty }

    public mutating func add(_ color: Pixel) {
        guard !isFull else { return }
        swatches.append(Swatch(color: color))
    }

    public mutating func remove(at index: Int) {
        guard swatches.indices.contains(index) else { return }
        swatches.remove(at: index)
        showsRangeOf = nil
    }

    public subscript(index: Int) -> Swatch {
        get { swatches[index] }
        set { swatches[index] = newValue.cleaned() }
    }

    /// Toward no change by `factor` (0...1), for a filter's intensity: the shifts shrink; the picked colors and their
    /// Range stay, since they say which colors, not how much.
    public func scaled(by factor: Double) -> PointColors {
        PointColors(swatches.map { Swatch(color: $0.color, hue: $0.hue * factor, saturation: $0.saturation * factor,
                                          luminance: $0.luminance * factor, range: $0.range) })
    }

    /// How much a pixel counts as `swatch`'s color: near its hue, its colorfulness and its lightness, each within a
    /// tolerance that widens with Range, fading softly to nothing.
    static func weight(of pixel: HSLColor, for swatch: HSLColor, range: Double) -> Double {
        guard pixel.chroma > 0, swatch.chroma > 0 else { return 0 }
        let hueTolerance = 6 + range * 0.44, chromaTolerance = 0.1 + range * 0.004, lightnessTolerance = 0.12 + range * 0.004
        var hueDistance = abs(pixel.hue - swatch.hue).truncatingRemainder(dividingBy: 360)
        if hueDistance > 180 { hueDistance = 360 - hueDistance }
        func near(_ distance: Double, _ tolerance: Double) -> Double {
            1 - PhotoAdjustments.smoothstep(tolerance * 0.5, tolerance, distance)
        }
        return near(hueDistance, hueTolerance) * near(abs(pixel.chroma - swatch.chroma), chromaTolerance)
            * near(abs(pixel.lightness - swatch.lightness), lightnessTolerance)
            * PhotoAdjustments.smoothstep(0, 0.08, pixel.chroma)
    }

    /// The per-pixel function, or nil when it changes nothing.
    public var transform: ((Pixel) -> Pixel)? {
        let active = swatches.enumerated().filter { !$0.element.isNeutral || $0.offset == showsRangeOf }
        guard !active.isEmpty else { return nil }
        let picked = active.map { (index: $0.offset, swatch: $0.element, color: HSLColor($0.element.color)) }
        let masked = showsRangeOf
        return { pixel in
            let original = HSLColor(pixel)
            var result = pixel
            var maskWeight = 1.0
            for entry in picked {
                let weight = Self.weight(of: original, for: entry.color, range: entry.swatch.range)
                if entry.index == masked { maskWeight = weight }
                guard weight > 0, !entry.swatch.isNeutral else { continue }
                result = ColorMixer.shifted(result, hue: entry.swatch.hue * weight, saturation: entry.swatch.saturation * weight,
                                            luminance: entry.swatch.luminance * weight)
            }
            guard masked != nil, maskWeight < 1 else { return result }
            // The Range preview: what this color doesn't touch fades to gray.
            let gray = UInt8((PhotoAdjustments.luma(SIMD3(Double(result.r), Double(result.g), Double(result.b)) / 255) * 255).rounded())
            func fade(_ v: UInt8) -> UInt8 { UInt8((Double(v) * maskWeight + Double(gray) * (1 - maskWeight)).rounded()) }
            return Pixel(r: fade(result.r), g: fade(result.g), b: fade(result.b), a: pixel.a)
        }
    }
}

/// A color's hue (degrees), chroma (0...1, how far from gray) and HSL lightness, for comparing colors.
struct HSLColor {
    let hue: Double
    let chroma: Double
    let lightness: Double

    init(_ pixel: Pixel) {
        let hsl = HSL(pixel)
        hue = hsl.hue
        lightness = hsl.lightness
        chroma = Double(max(pixel.r, pixel.g, pixel.b) - min(pixel.r, pixel.g, pixel.b)) / 255
    }
}

extension PointColors.Swatch: Codable {
    private enum CodingKeys: String, CodingKey {
        case color, hue, saturation, luminance, range
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rgb = try container.decode([UInt8].self, forKey: .color)
        guard rgb.count >= 3 else { throw DecodingError.dataCorruptedError(forKey: .color, in: container, debugDescription: "Needs RGB") }
        func value(_ key: CodingKeys, _ fallback: Double) -> Double { (try? container.decodeIfPresent(Double.self, forKey: key)) ?? fallback }
        self = PointColors.Swatch(color: Pixel(r: rgb[0], g: rgb[1], b: rgb[2]), hue: value(.hue, 0), saturation: value(.saturation, 0),
                                  luminance: value(.luminance, 0), range: value(.range, 50)).cleaned()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode([color.r, color.g, color.b], forKey: .color)
        try container.encode(hue, forKey: .hue)
        try container.encode(saturation, forKey: .saturation)
        try container.encode(luminance, forKey: .luminance)
        try container.encode(range, forKey: .range)
    }
}

extension PointColors: Codable {
    private enum CodingKeys: String, CodingKey {
        case swatches
    }

    /// A swatch this version can't read is skipped; values are kept within range.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var list = try container.nestedUnkeyedContainer(forKey: .swatches)
        var read: [Swatch] = []
        while !list.isAtEnd {
            if let swatch = try? list.decode(Swatch.self) {
                read.append(swatch)
            } else {
                _ = try? list.decode(Skipped.self)
            }
        }
        self.init(read)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(swatches, forKey: .swatches)
    }

    /// Anything, read and thrown away, so the list moves past an entry it can't use.
    private struct Skipped: Decodable {
        init(from decoder: Decoder) throws {}
    }
}
