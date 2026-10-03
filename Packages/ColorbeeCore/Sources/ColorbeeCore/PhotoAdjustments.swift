import Foundation
import simd

/// The Adjust Photo panel's sliders (FR-9.5), modeled on the iPhone Photos editor. Each is -100...100 with 0
/// meaning no change, except Sharpness, Definition and Noise Reduction, which are 0...100.
public struct PhotoAdjustments: Sendable, Hashable, Codable {
    public enum Slider: String, CaseIterable, Sendable, Codable {
        case exposure, brilliance, highlights, shadows, contrast, brightness, blackPoint
        case saturation, vibrance, warmth, tint
        case sharpness, definition, noiseReduction, vignette

        public var title: String {
            switch self {
            case .exposure: "Exposure"
            case .brilliance: "Brilliance"
            case .highlights: "Highlights"
            case .shadows: "Shadows"
            case .contrast: "Contrast"
            case .brightness: "Brightness"
            case .blackPoint: "Black Point"
            case .saturation: "Saturation"
            case .vibrance: "Vibrance"
            case .warmth: "Warmth"
            case .tint: "Tint"
            case .sharpness: "Sharpness"
            case .definition: "Definition"
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

        /// Color and tone: what filters may hold. Sharpness, Definition, Noise Reduction and Vignette are not.
        public var isColorOrTone: Bool {
            switch self {
            case .sharpness, .definition, .noiseReduction, .vignette: false
            default: true
            }
        }
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

    /// Only the color and tone sliders.
    public var colorAndTone: PhotoAdjustments {
        PhotoAdjustments(values.filter { $0.key.isColorOrTone })
    }

    var hasDetail: Bool { self[.sharpness] != 0 || self[.definition] != 0 || self[.noiseReduction] != 0 }

    // MARK: The math (mirrored in Shaders.metal through ColorLookup, plus photo_fragment for the rest)

    /// The per-pixel color and tone part, in slider order: light, then color.
    public var colorTransform: (Pixel) -> Pixel {
        let exposure = pow(2, self[.exposure] / 50)
        let brilliance = self[.brilliance] / 100
        let highlights = self[.highlights] / 100, shadows = self[.shadows] / 100
        let contrast = 1 + self[.contrast] / 100
        let brightness = pow(2, -self[.brightness] / 100)
        let blackPoint = self[.blackPoint] / 100 * 0.25
        let saturation = 1 + self[.saturation] / 100
        let vibrance = self[.vibrance] / 100
        let warmth = self[.warmth] / 100 * 0.15, tint = self[.tint] / 100
        return { pixel in
            var c = SIMD3(Double(pixel.r), Double(pixel.g), Double(pixel.b)) / 255
            if exposure != 1 {
                c = Self.power(Self.power(c, 2.2) * exposure, 1 / 2.2)
            }
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
    public static let definitionRadius = 12.0

    /// Sharpness, Definition and Noise Reduction for one pixel, from its own color and two blurred copies
    /// (straight colors, 0...1). Returns the new color.
    static func detail(_ original: SIMD3<Double>, fine: SIMD3<Double>, wide: SIMD3<Double>,
                       sharpness: Double, definition: Double, noiseReduction: Double) -> SIMD3<Double> {
        var c = original
        if noiseReduction > 0 {
            // Smooth only where the pixel is close to its surroundings, so edges stay crisp.
            let difference = simd_abs(original - fine).max()
            let weight = noiseReduction * (1 - smoothstep(0.04, 0.2, difference))
            c += (fine - c) * weight
        }
        if sharpness > 0 { c += (original - fine) * sharpness * 1.5 }
        if definition > 0 { c += (original - wide) * definition * 0.6 }
        return clamped(c)
    }
}

/// What the Adjust Photo panel holds (FR-9.5): a filter at an intensity, then the sliders on top.
public struct PhotoEdit: Sendable, Hashable, Codable {
    public var adjustments: PhotoAdjustments
    public var filter: PhotoFilter?
    /// 0...100 percent.
    public var filterIntensity: Double

    public init(adjustments: PhotoAdjustments = PhotoAdjustments(), filter: PhotoFilter? = nil, filterIntensity: Double = 100) {
        self.adjustments = adjustments
        self.filter = filter
        self.filterIntensity = filterIntensity
    }

    public var isNeutral: Bool { adjustments.isNeutral && (filter == nil || filterIntensity == 0) }

    /// The color and tone part: the filter's steps at its intensity, then the sliders' color and tone.
    public var colorTransform: (Pixel) -> Pixel {
        let steps = (filter?.steps(atIntensity: filterIntensity / 100) ?? []).compactMap(\.colorTransform)
        let own = adjustments.colorTransform
        return { pixel in own(steps.reduce(pixel) { $1($0) }) }
    }
}
