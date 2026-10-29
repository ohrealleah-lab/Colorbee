import Foundation

extension PhotoEdit {
    /// The white-balance eyedropper (FR-9.7): Warmth and Tint set so `sample`, a color from the picture before any
    /// of these settings, comes out gray, the filter included. The Tone Curve, Color Mixer and Point Color keep a gray
    /// gray; Color Grading's tint is kept on purpose (Leah, review V, finding 5). When the cast is stronger than Warmth
    /// and Tint can fix, or the sample isn't near gray, they go as far as they can (Leah, 2026-10-27).
    public func neutralizing(_ sample: Pixel) -> PhotoEdit {
        var neutral = self
        neutral.adjustments[.warmth] = 0
        neutral.adjustments[.tint] = 0
        // Warmth and Tint are the sliders' last steps, so the color just before them is the filter's and the other
        // sliders'; what comes after them is left out, since a curve steepens the very cast being measured.
        var upToWarmth = neutral
        upToWarmth.toneCurve = nil
        upToWarmth.mixer = nil
        upToWarmth.pointColors = nil
        upToWarmth.grading = nil
        let before = upToWarmth.colorTransform(sample)
        let r = Double(before.r), g = Double(before.g), b = Double(before.b)
        guard r + b > 0 else { return neutral }
        // Warmth multiplies red by 1 + w and blue by 1 − w (w = 0.15 per 100); Tint multiplies green by 1 − 0.12t and
        // red and blue by 1 + 0.04t (t = 1 per 100). See `PhotoAdjustments.colorTransform`.
        let w = min(max((b - r) / (b + r), -0.15), 0.15)
        let red = r * (1 + w)
        let t = red + g > 0 ? min(max((g - red) / (0.04 * red + 0.12 * g), -1), 1) : 0
        neutral.adjustments[.warmth] = (w / 0.15 * 100).rounded()
        neutral.adjustments[.tint] = (t * 100).rounded()
        return neutral
    }
}

extension PixelBuffer {
    /// The average color of `rect` (clipped to the buffer), weighted by opacity, at full opacity. Nil when every
    /// pixel there is clear.
    public func averageColor(in rect: IntRect) -> Pixel? {
        let area = rect.intersection(bounds)
        var sum = SIMD3<Double>.zero, weight = 0.0
        for y in area.minY..<area.maxY {
            let row = row(y)
            for x in area.minX..<area.maxX {
                let pixel = row[x], alpha = Double(pixel.a)
                sum += SIMD3(Double(pixel.r), Double(pixel.g), Double(pixel.b)) * alpha
                weight += alpha
            }
        }
        guard weight > 0 else { return nil }
        let mean = (sum / weight).rounded(.toNearestOrAwayFromZero)
        return Pixel(r: UInt8(mean.x), g: UInt8(mean.y), b: UInt8(mean.z))
    }
}

extension PixelBuffer {
    /// The average of `rect` (clipped to the buffer): its colors weighted by opacity, and its opacity averaged, as the
    /// Eyedropper's Sample Size picks (FR-9.7 item 9). Fully clear where every pixel is.
    public func averagedPixel(in rect: IntRect) -> Pixel {
        let area = rect.intersection(bounds)
        guard !area.isEmpty else { return .clear }
        let alpha = (0..<area.height).reduce(0) { sum, y in
            let row = row(area.minY + y)
            return sum + (area.minX..<area.maxX).reduce(0) { $0 + Int(row[$1].a) }
        }
        guard let color = averageColor(in: area) else { return .clear }
        let opacity = (Double(alpha) / Double(area.width * area.height)).rounded()
        return Pixel(r: color.r, g: color.g, b: color.b, a: UInt8(opacity))
    }
}
