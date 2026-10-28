import Foundation

/// Adjust Photo's Color Grading (FR-9.7 item 2): a color wheel each for the shadows, midtones and highlights, and one
/// for the whole picture. Each wheel tints toward a hue by a strength and can lighten or darken its tones. Blending
/// sets how much the three tone ranges overlap; Balance moves where shadows end and highlights begin.
public struct ColorGrading: Sendable, Hashable {
    public enum Region: String, CaseIterable, Sendable, Codable {
        case shadows, midtones, highlights, global

        public var title: String {
            switch self {
            case .shadows: "Shadows"
            case .midtones: "Midtones"
            case .highlights: "Highlights"
            case .global: "Global"
            }
        }
    }

    public struct Wheel: Sendable, Hashable, Codable {
        /// Degrees, 0...360 (0 is red).
        public var hue: Double
        /// 0...100: how strongly the tones lean toward `hue`.
        public var strength: Double
        /// −100...100.
        public var luminance: Double

        public init(hue: Double = 0, strength: Double = 0, luminance: Double = 0) {
            self.hue = hue
            self.strength = strength
            self.luminance = luminance
        }

        public var isNeutral: Bool { strength == 0 && luminance == 0 }

        /// Kept within range; anything that isn't a number reads as 0.
        func cleaned() -> Wheel {
            func number(_ v: Double) -> Double { v.isFinite ? v : 0 }
            let h = number(hue).truncatingRemainder(dividingBy: 360)
            return Wheel(hue: h < 0 ? h + 360 : h, strength: min(max(number(strength), 0), 100),
                         luminance: min(max(number(luminance), -100), 100))
        }
    }

    public var wheels: [Region: Wheel] = [:]
    /// 0...100, 50 by default (Leah, 2026-10-27).
    public var blending: Double = 50
    /// −100...100, 0 by default: right gives the highlights more of the picture.
    public var balance: Double = 0

    public init() {}

    public subscript(region: Region) -> Wheel {
        get { wheels[region] ?? Wheel() }
        set {
            let wheel = newValue.cleaned()
            wheels[region] = wheel.isNeutral && wheel.hue == 0 ? nil : wheel
        }
    }

    /// Nothing tints or lightens; Blending and Balance alone change nothing.
    public var isNeutral: Bool { wheels.values.allSatisfy(\.isNeutral) }

    /// Everything as it starts, so there's nothing to keep.
    public var isUntouched: Bool { wheels.isEmpty && blending == 50 && balance == 0 }

    /// Toward no change by `factor` (0...1), for a filter's intensity: strengths and luminances shrink, hues stay,
    /// and Blending and Balance are kept, since they're the shape rather than the amount (Leah, 2026-10-27).
    public func scaled(by factor: Double) -> ColorGrading {
        var scaled = self
        scaled.wheels = wheels.mapValues { Wheel(hue: $0.hue, strength: $0.strength * factor, luminance: $0.luminance * factor) }
        return scaled
    }

    /// How much each tone range owns a brightness (0...1): soft bumps at black, middle gray and white, wider as
    /// Blending rises, shared so they add up to 1. Balance first bends the brightness, so to the right more of the
    /// picture counts as highlights.
    func toneWeights(_ lightness: Double) -> (shadows: Double, midtones: Double, highlights: Double) {
        let bent = pow(max(lightness, 0), pow(2, -min(max(balance, -100), 100) / 100 * 1.5))
        let width = 0.08 + min(max(blending, 0), 100) / 100 * 0.3
        func bump(_ center: Double) -> Double { exp(-pow(bent - center, 2) / (2 * width * width)) }
        let s = bump(0), m = bump(0.5), h = bump(1), total = s + m + h
        return (s / total, m / total, h / total)
    }

    /// A hue's direction away from gray, with no brightness of its own, so tinting doesn't lighten or darken.
    static func tint(hue: Double) -> SIMD3<Double> {
        let h = hue / 60, x = 1 - abs(h.truncatingRemainder(dividingBy: 2) - 1)
        let rgb: SIMD3<Double> = switch Int(h) % 6 {
        case 0: SIMD3(1, x, 0)
        case 1: SIMD3(x, 1, 0)
        case 2: SIMD3(0, 1, x)
        case 3: SIMD3(0, x, 1)
        case 4: SIMD3(x, 0, 1)
        default: SIMD3(1, 0, x)
        }
        return rgb - PhotoAdjustments.luma(rgb)
    }

    /// The per-pixel function, or nil when it changes nothing.
    public var transform: ((Pixel) -> Pixel)? {
        guard !isNeutral else { return nil }
        let grading = self
        let parts = Region.allCases.map { region -> (Region, SIMD3<Double>, Double) in
            let wheel = grading[region]
            return (region, Self.tint(hue: wheel.hue) * wheel.strength / 100 * 0.3, wheel.luminance / 100 * 0.25)
        }
        return { pixel in
            var c = SIMD3(Double(pixel.r), Double(pixel.g), Double(pixel.b)) / 255
            let weights = grading.toneWeights(PhotoAdjustments.luma(c))
            for (region, tint, lift) in parts {
                let weight = switch region {
                case .shadows: weights.shadows
                case .midtones: weights.midtones
                case .highlights: weights.highlights
                case .global: 1.0
                }
                guard weight > 0 else { continue }
                c += tint * weight
                if lift != 0 { c += (lift > 0 ? 1 - c : c) * lift * weight }
            }
            c = PhotoAdjustments.clamped(c) * 255
            return Pixel(r: UInt8(c.x.rounded()), g: UInt8(c.y.rounded()), b: UInt8(c.z.rounded()), a: pixel.a)
        }
    }
}

extension ColorGrading: Codable {
    private enum CodingKeys: String, CodingKey {
        case wheels, blending, balance
    }

    /// Values from a file are kept within range; a wheel this version can't read is left at neutral.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        let saved = (try? container.decodeIfPresent([String: Wheel].self, forKey: .wheels)) ?? [:]
        for (name, wheel) in saved {
            if let region = Region(rawValue: name) { self[region] = wheel }
        }
        let blending = (try? container.decodeIfPresent(Double.self, forKey: .blending)) ?? 50
        self.blending = blending.isFinite ? min(max(blending, 0), 100) : 50
        let balance = (try? container.decodeIfPresent(Double.self, forKey: .balance)) ?? 0
        self.balance = balance.isFinite ? min(max(balance, -100), 100) : 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Dictionary(uniqueKeysWithValues: wheels.map { ($0.key.rawValue, $0.value) }), forKey: .wheels)
        try container.encode(blending, forKey: .blending)
        try container.encode(balance, forKey: .balance)
    }
}
