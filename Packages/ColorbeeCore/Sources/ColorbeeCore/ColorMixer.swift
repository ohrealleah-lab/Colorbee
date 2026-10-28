import Foundation

/// Adjust Photo's Color Mixer (FR-9.7 items 1 and 6): hue, saturation and luminance for each of eight color ranges,
/// and Black & White with its own mix of the same ranges. Blended between neighboring ranges, so there are no hard
/// edges between colors, and gray stays gray. Each value is −100...100.
public struct ColorMixer: Sendable, Hashable {
    /// The ranges and the hue at the middle of each (Leah, 2026-10-27; Lightroom's).
    public enum Range: Int, CaseIterable, Sendable {
        case red, orange, yellow, green, aqua, blue, purple, magenta

        public var title: String {
            switch self {
            case .red: "Red"
            case .orange: "Orange"
            case .yellow: "Yellow"
            case .green: "Green"
            case .aqua: "Aqua"
            case .blue: "Blue"
            case .purple: "Purple"
            case .magenta: "Magenta"
            }
        }

        public var centerHue: Double {
            [0, 30, 60, 120, 180, 225, 270, 315][rawValue]
        }
    }

    public enum Setting: String, CaseIterable, Sendable {
        case hue, saturation, luminance, gray
    }

    private var values: [Setting: [Double]] = [:]
    /// Black & White: 0 is color, 1 black and white. The switch sets 0 or 1; a filter's Intensity scales it.
    public var blackAndWhite: Double = 0 {
        didSet { blackAndWhite = min(max(blackAndWhite.isFinite ? blackAndWhite : 0, 0), 1) }
    }

    public init() {}

    public subscript(setting: Setting, range: Range) -> Double {
        get { values[setting]?[range.rawValue] ?? 0 }
        set {
            var row = values[setting] ?? Array(repeating: 0, count: Range.allCases.count)
            row[range.rawValue] = newValue.isFinite ? min(max(newValue, -100), 100) : 0
            values[setting] = row.allSatisfy { $0 == 0 } ? nil : row
        }
    }

    public var isNeutral: Bool { values.isEmpty && blackAndWhite == 0 }

    /// Toward no change by `factor` (0...1), for a filter's intensity. Hue shifts shrink too.
    public func scaled(by factor: Double) -> ColorMixer {
        var scaled = self
        scaled.values = values.mapValues { $0.map { $0 * factor } }
        scaled.blackAndWhite = blackAndWhite * factor
        return scaled
    }

    /// How much each range owns `hue` (degrees): two neighbors share it, with a soft (cosine) handover.
    static func weights(hue: Double) -> [Double] {
        let centers = Range.allCases.map(\.centerHue)
        var weights = Array(repeating: 0.0, count: centers.count)
        let h = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        for i in centers.indices {
            let start = centers[i], end = i + 1 < centers.count ? centers[i + 1] : 360
            guard h >= start, h < end else { continue }
            let t = (h - start) / (end - start)
            let handover = (1 - cos(Double.pi * t)) / 2
            weights[i] += 1 - handover
            weights[(i + 1) % centers.count] += handover
        }
        return weights
    }

    private func blended(_ setting: Setting, _ weights: [Double]) -> Double {
        guard let row = values[setting] else { return 0 }
        return zip(row, weights).reduce(0) { $0 + $1.0 * $1.1 }
    }

    /// The per-pixel function, or nil when it changes nothing.
    public var transform: ((Pixel) -> Pixel)? {
        guard !isNeutral else { return nil }
        let mixer = self
        return { pixel in mixer.apply(pixel) }
    }

    /// One color's hue, saturation and luminance changed, each −100...100; shared with Point Color.
    static func shifted(_ pixel: Pixel, hue: Double, saturation: Double, luminance: Double) -> Pixel {
        // ±100 moves a hue about ±30°, so red can lean orange or magenta but never become green (Leah, 2026-10-27).
        var adjusted = HSL(pixel).adjusted(hue: hue / 100 * 30, saturation: 0, lightness: 0)
        // Luminance moves the middle tones most and leaves near-black and near-white alone, so a dark orange
        // doesn't jump out of the shadows.
        let lightness = adjusted.lightness
        adjusted.lightness = min(max(lightness + luminance / 100 * 1.2 * lightness * (1 - lightness), 0), 1)
        var result = adjusted.pixel(alpha: pixel.a)
        // Saturation scales how far the color is from gray, like Adjust Photo's Saturation: +100 doubles it,
        // −100 makes it gray, and a nearly gray pixel stays nearly gray.
        if saturation != 0 {
            let rgb = SIMD3(Double(result.r), Double(result.g), Double(result.b)) / 255
            let gray = PhotoAdjustments.luma(rgb)
            let saturated = PhotoAdjustments.clamped(gray + (rgb - gray) * (1 + saturation / 100)) * 255
            result = Pixel(r: UInt8(saturated.x.rounded()), g: UInt8(saturated.y.rounded()), b: UInt8(saturated.z.rounded()), a: pixel.a)
        }
        return result
    }

    func apply(_ pixel: Pixel) -> Pixel {
        let c = SIMD3(Double(pixel.r), Double(pixel.g), Double(pixel.b)) / 255
        let chroma = c.max() - c.min()
        let hsl = HSL(pixel)
        let weights = Self.weights(hue: hsl.hue)
        // Gray (and nearly gray) pixels have no hue to speak of, so they're left as they are.
        let colorful = PhotoAdjustments.smoothstep(0, 0.12, chroma)
        var result = pixel
        if blackAndWhite < 1, colorful > 0, values[.hue] != nil || values[.saturation] != nil || values[.luminance] != nil {
            result = Self.shifted(pixel, hue: blended(.hue, weights) * colorful, saturation: blended(.saturation, weights) * colorful,
                                  luminance: blended(.luminance, weights) * colorful)
        }
        guard blackAndWhite > 0 else { return result }
        // Black & White: the brightness of each color, made lighter or darker by its range's mix, most in the
        // middle tones.
        let base = PhotoAdjustments.luma(c)
        let mix = blended(.gray, weights) / 100 * PhotoAdjustments.smoothstep(0, 0.3, chroma)
        let gray = min(max(base + mix * 1.2 * base * (1 - base), 0), 1)
        let color = SIMD3(Double(result.r), Double(result.g), Double(result.b))
        let out = color + (SIMD3(repeating: gray * 255) - color) * blackAndWhite
        return Pixel(r: UInt8(min(255, max(0, out.x.rounded()))), g: UInt8(min(255, max(0, out.y.rounded()))),
                     b: UInt8(min(255, max(0, out.z.rounded()))), a: pixel.a)
    }
}

extension ColorMixer: Codable {
    private enum CodingKeys: String, CodingKey {
        case hue, saturation, luminance, gray, blackAndWhite
    }

    /// Values from a file are kept within range; a list of the wrong length is read as far as it goes.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        for setting in Setting.allCases {
            guard let key = CodingKeys(stringValue: setting.rawValue),
                  let row = try? container.decodeIfPresent([Double].self, forKey: key) else { continue }
            for (range, value) in zip(Range.allCases, row) { self[setting, range] = value }
        }
        blackAndWhite = (try? container.decodeIfPresent(Double.self, forKey: .blackAndWhite)) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        for (setting, row) in values {
            try container.encode(row, forKey: CodingKeys(stringValue: setting.rawValue)!)
        }
        if blackAndWhite != 0 { try container.encode(blackAndWhite, forKey: .blackAndWhite) }
    }
}
