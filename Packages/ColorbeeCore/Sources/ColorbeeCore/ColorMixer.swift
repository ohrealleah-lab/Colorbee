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

        public var centerHue: Double { ColorMixer.centers[rawValue] }
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

    /// The range that owns most of `pixel`'s hue, for dragging on the picture (FR-9.7 item 6); nil for a color too
    /// close to gray to have one.
    public static func range(for pixel: Pixel) -> Range? {
        let high = max(pixel.r, pixel.g, pixel.b), low = min(pixel.r, pixel.g, pixel.b)
        guard Int(high) - Int(low) >= 8 else { return nil }
        let weights = weights(hue: HSL(pixel).hue)
        return Range(rawValue: weights.indices.max { weights[$0] < weights[$1] }!)
    }

    /// How much each range owns `hue` (degrees): two neighbors share it, with a soft (cosine) handover.
    static func weights(hue: Double) -> [Double] {
        let weights = weightVector(hue: hue)
        return Range.allCases.map { weights[$0.rawValue] }
    }

    private static let centers = SIMD8<Double>(0, 30, 60, 120, 180, 225, 270, 315)

    /// `weights(hue:)` without making a list, for the per-pixel function.
    static func weightVector(hue: Double) -> SIMD8<Double> {
        var weights = SIMD8<Double>(repeating: 0)
        let h = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        for i in 0..<8 {
            let start = centers[i], end = i + 1 < 8 ? centers[i + 1] : 360
            guard h >= start, h < end else { continue }
            let t = (h - start) / (end - start)
            let handover = (1 - cos(Double.pi * t)) / 2
            weights[i] += 1 - handover
            weights[(i + 1) % 8] += handover
        }
        return weights
    }

    /// One setting's values for `weights`, added up in range order.
    private static func blended(_ row: SIMD8<Double>, _ weights: SIMD8<Double>) -> Double {
        var sum = 0.0
        for i in 0..<8 { sum += row[i] * weights[i] }
        return sum
    }

    /// The per-pixel function, or nil when it changes nothing. The values are copied out of their lists first: reading
    /// a list for each pixel counts a reference up and down, and with every core doing that the mixer ran about 40
    /// times slower (2026-10-28).
    public var transform: ((Pixel) -> Pixel)? {
        guard !isNeutral else { return nil }
        func row(_ setting: Setting) -> SIMD8<Double> {
            guard let values = values[setting] else { return SIMD8(repeating: 0) }
            return SIMD8(values)
        }
        let rows = Rows(hue: row(.hue), saturation: row(.saturation), luminance: row(.luminance), gray: row(.gray),
                        shifts: values[.hue] != nil || values[.saturation] != nil || values[.luminance] != nil,
                        blackAndWhite: blackAndWhite)
        return { pixel in Self.apply(pixel, rows) }
    }

    private struct Rows {
        let hue, saturation, luminance, gray: SIMD8<Double>
        let shifts: Bool
        let blackAndWhite: Double
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

    private static func apply(_ pixel: Pixel, _ rows: Rows) -> Pixel {
        let c = SIMD3(Double(pixel.r), Double(pixel.g), Double(pixel.b)) / 255
        let chroma = c.max() - c.min()
        let hsl = HSL(pixel)
        let weights = weightVector(hue: hsl.hue)
        // Gray (and nearly gray) pixels have no hue to speak of, so they're left as they are.
        let colorful = PhotoAdjustments.smoothstep(0, 0.12, chroma)
        var result = pixel
        if rows.blackAndWhite < 1, colorful > 0, rows.shifts {
            result = shifted(pixel, hue: blended(rows.hue, weights) * colorful, saturation: blended(rows.saturation, weights) * colorful,
                             luminance: blended(rows.luminance, weights) * colorful)
        }
        guard rows.blackAndWhite > 0 else { return result }
        // Black & White: the brightness of each color, made lighter or darker by its range's mix, most in the
        // middle tones.
        let base = PhotoAdjustments.luma(c)
        let mix = blended(rows.gray, weights) / 100 * PhotoAdjustments.smoothstep(0, 0.3, chroma)
        let gray = min(max(base + mix * 1.2 * base * (1 - base), 0), 1)
        let color = SIMD3(Double(result.r), Double(result.g), Double(result.b))
        let out = color + (SIMD3(repeating: gray * 255) - color) * rows.blackAndWhite
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
