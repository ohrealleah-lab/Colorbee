import Foundation
import simd

/// Sharpness's and Noise Reduction's finer settings (FR-9.7 item 5), under their disclosure arrows in Adjust Photo.
/// Each starts where Colorbee always had it, so photos edited before keep their look exactly (Q13.1). The Sharpness
/// slider is the amount, and the Noise Reduction slider is luminance noise reduction.
public struct PhotoDetail: Sendable, Hashable {
    /// Sharpness's radius in pixels: the size of detail it brings out.
    public var radius = PhotoAdjustments.fineRadius
    /// Below 50, strong edges are held back so halos fade; above 50, the finest detail is brought out more.
    public var sharpnessDetail = 50.0
    /// Sharpens only edges: the higher, the more flat areas such as sky are left alone.
    public var masking = 0.0
    /// Luminance noise reduction's detail: higher keeps more fine detail, lower smooths more.
    public var luminanceDetail = 50.0
    /// Color noise reduction: smooths colored speckles, keeping each pixel's brightness.
    public var color = 0.0
    /// Higher keeps more small color detail.
    public var colorDetail = 50.0

    public static let radiusRange = 0.5...3.0
    public static let range = 0.0...100.0

    public init() {}

    public var isDefault: Bool { self == PhotoDetail() }

    /// Every setting within its range; values that aren't numbers are put back to their start.
    func clamped() -> PhotoDetail {
        func clamp(_ value: Double, _ range: ClosedRange<Double>, _ start: Double) -> Double {
            value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : start
        }
        let start = PhotoDetail()
        var result = PhotoDetail()
        result.radius = clamp(radius, Self.radiusRange, start.radius)
        result.sharpnessDetail = clamp(sharpnessDetail, Self.range, start.sharpnessDetail)
        result.masking = clamp(masking, Self.range, start.masking)
        result.luminanceDetail = clamp(luminanceDetail, Self.range, start.luminanceDetail)
        result.color = clamp(color, Self.range, start.color)
        result.colorDetail = clamp(colorDetail, Self.range, start.colorDetail)
        return result
    }
}

/// A setting a file leaves out keeps its start, so a newer file still opens.
extension PhotoDetail: Codable {
    private enum CodingKeys: String, CodingKey {
        case radius, sharpnessDetail, masking, luminanceDetail, color, colorDetail
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var detail = PhotoDetail()
        func read(_ key: CodingKeys, into value: inout Double) {
            if let stored = try? container.decodeIfPresent(Double.self, forKey: key) { value = stored }
        }
        read(.radius, into: &detail.radius)
        read(.sharpnessDetail, into: &detail.sharpnessDetail)
        read(.masking, into: &detail.masking)
        read(.luminanceDetail, into: &detail.luminanceDetail)
        read(.color, into: &detail.color)
        read(.colorDetail, into: &detail.colorDetail)
        self = detail.clamped()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(radius, forKey: .radius)
        try container.encode(sharpnessDetail, forKey: .sharpnessDetail)
        try container.encode(masking, forKey: .masking)
        try container.encode(luminanceDetail, forKey: .luminanceDetail)
        try container.encode(color, forKey: .color)
        try container.encode(colorDetail, forKey: .colorDetail)
    }
}

/// Everything the detail step needs for one pixel, worked out once per render (CPU) or passed to the shader (GPU,
/// `adjust_photo_fragment`), so both do the same arithmetic.
public struct DetailAmounts: Sendable, Equatable {
    /// The sliders, 0...1 (Texture -1...1).
    public var sharpness = 0.0, definition = 0.0, texture = 0.0, noiseReduction = 0.0, color = 0.0
    /// Scales luminance noise reduction's edge thresholds: 1 at Detail 50, smaller keeps more detail.
    public var luminanceScale = 1.0
    /// The same for color noise reduction.
    public var colorScale = 1.0
    /// How strongly big differences (halos) are held back, from Sharpness Detail below 50.
    public var haloDamping = 0.0
    /// How much the finest detail is boosted, from Sharpness Detail above 50.
    public var fineBoost = 0.0
    /// Masking's edge threshold; 0 sharpens everywhere.
    public var maskThreshold = 0.0
    /// Draw the Masking edge mask instead of the photo (Option-drag on Masking, Q13.2).
    public var showsMask = false

    public init(_ edit: PhotoEdit) {
        let a = edit.adjustments, detail = edit.detail ?? PhotoDetail()
        sharpness = a[.sharpness] / 100
        definition = a[.definition] / 100
        texture = a[.texture] / 100
        noiseReduction = a[.noiseReduction] / 100
        color = detail.color / 100
        luminanceScale = Self.scale(forDetail: detail.luminanceDetail)
        colorScale = Self.scale(forDetail: detail.colorDetail)
        haloDamping = max(0, 50 - detail.sharpnessDetail) / 50 * 40
        fineBoost = max(0, detail.sharpnessDetail - 50) / 50
        maskThreshold = detail.masking / 100 * 0.12
        showsMask = edit.showsSharpeningMask
        sharpensOwnRadius = detail.radius != PhotoAdjustments.fineRadius
        radius = detail.radius
    }

    /// 1 at 50, a quarter at 100 and four times at 0.
    static func scale(forDetail detail: Double) -> Double {
        detail == 50 ? 1 : pow(2, (50 - detail) / 25)
    }

    /// Which blurred copies the step reads: the 1.2 px one for noise reduction (and sharpening at that radius), one
    /// at Sharpness's own radius otherwise, Texture's 3 px one (also for color noise and Masking), and Definition's.
    public var needsFine: Bool { noiseReduction > 0 || (sharpness > 0 && !sharpensOwnRadius) }
    public var needsMedium: Bool { texture != 0 || color > 0 || (sharpness > 0 && maskThreshold > 0) || showsMask && maskThreshold > 0 }
    public var needsWide: Bool { definition > 0 }
    public var needsSharpenBlur: Bool { sharpness > 0 && sharpensOwnRadius }
    public var isNeeded: Bool { needsFine || needsMedium || needsWide || needsSharpenBlur || showsMask }
    /// Sharpness's radius differs from the noise reduction blur's, so it needs a blur of its own.
    public var sharpensOwnRadius = false
    /// Sharpness's blur radius.
    public var radius = PhotoAdjustments.fineRadius
}

extension PhotoAdjustments {
    /// How much sharpening a pixel gets under Masking, 0...1, from how far it is from its 3 px surroundings: 1 at
    /// edges, 0 in flat areas. White in the Option-drag view.
    static func sharpeningMask(_ original: SIMD3<Double>, medium: SIMD3<Double>, threshold: Double) -> Double {
        guard threshold > 0 else { return 1 }
        return smoothstep(threshold * 0.5, threshold * 1.5, simd_abs(original - medium).max())
    }

    /// Sharpness, Definition, Texture and noise reduction for one pixel, from its own color and blurred copies
    /// (straight colors, 0...1). Returns the new color. Texture works on detail up to a few pixels across, against
    /// a blur a quarter of Definition's, so it brings out (or, negative, smooths) texture without wide halos.
    /// `sharp` is the blur at Sharpness's radius (the fine one unless the radius was changed).
    static func detail(_ original: SIMD3<Double>, fine: SIMD3<Double>, sharp: SIMD3<Double>, medium: SIMD3<Double>,
                       wide: SIMD3<Double>, _ amounts: DetailAmounts) -> SIMD3<Double> {
        if amounts.showsMask {
            return SIMD3(repeating: sharpeningMask(original, medium: medium, threshold: amounts.maskThreshold))
        }
        var c = original
        if amounts.noiseReduction > 0 {
            // Smooth only where the pixel is close to its surroundings, so edges stay crisp.
            let difference = simd_abs(original - fine).max()
            let s = amounts.luminanceScale
            let weight = amounts.noiseReduction * (1 - smoothstep(0.04 * s, 0.2 * s, difference))
            c += (fine - c) * weight
        }
        if amounts.color > 0 {
            // The pixel's color moves toward its surroundings' while its brightness stays, unless the color differs a
            // lot (a real color edge).
            let chroma = c - luma(c), around = medium - luma(medium)
            let s = amounts.colorScale
            let weight = amounts.color * (1 - smoothstep(0.08 * s, 0.3 * s, simd_abs(chroma - around).max()))
            c += (around - chroma) * weight
        }
        if amounts.sharpness > 0 {
            let difference = original - sharp
            var gain = 1.0
            let size = simd_abs(difference).max()
            if amounts.haloDamping > 0 { gain = 1 / (1 + size * amounts.haloDamping) }
            if amounts.fineBoost > 0 { gain = 1 + amounts.fineBoost * (1 - smoothstep(0, 0.1, size)) }
            if amounts.maskThreshold > 0 { gain *= sharpeningMask(original, medium: medium, threshold: amounts.maskThreshold) }
            c += gain == 1 ? difference * amounts.sharpness * 1.5 : difference * amounts.sharpness * 1.5 * gain
        }
        if amounts.definition > 0 { c += (original - wide) * amounts.definition * 0.6 }
        if amounts.texture != 0 { c += (original - medium) * amounts.texture * 0.8 }
        return clamped(c)
    }
}
