import Foundation

extension PhotoAdjustments {
    /// Adjust Photo's Auto button (FR-9.5): looks at the photo and sets Exposure, Brilliance, Highlights,
    /// Shadows, Contrast, White Balance (Warmth and Tint) and Vibrance. Sliders it leaves at zero aren't moved.
    public static func auto(for buffer: PixelBuffer, selection: SelectionMask? = nil) -> PhotoAdjustments {
        let stats = PhotoStatistics(buffer, selection: selection)
        guard stats.count > 0 else { return PhotoAdjustments() }
        var result = PhotoAdjustments()

        // Exposure: bring the median brightness toward a little under middle gray, in linear light.
        let median = max(stats.percentile(0.5), 0.02)
        let stops = log2(pow(0.42, 2.2) / pow(median, 2.2))
        result[.exposure] = round(min(max(stops, -1), 1) * 50 * 0.8)

        // Highlights and Shadows: recover clipped brights, open up crushed darks.
        if stats.shareAbove(0.96) > 0.02 { result[.highlights] = -round(min(stats.shareAbove(0.96) * 400, 50)) }
        if stats.shareBelow(0.08) > 0.10 { result[.shadows] = round(min(stats.shareBelow(0.08) * 120, 40)) }

        // Contrast: a flat photo (narrow middle 90 percent) gets more.
        let spread = stats.percentile(0.95) - stats.percentile(0.05)
        if spread < 0.7 { result[.contrast] = round(min((0.7 - spread) * 60, 30)) }

        // Brilliance: a gentle lift for photos without much tonal range.
        if spread < 0.85 { result[.brilliance] = round(min((0.85 - spread) * 50, 20)) }

        // White balance: pull the average color most of the way to gray.
        let mean = stats.meanColor
        if mean.x > 0.02, mean.z > 0.02 {
            // Solves r(1 + w) = b(1 - w) for the Warmth multiplier w (0.15 per 100).
            let w = (mean.z - mean.x) / (mean.z + mean.x)
            result[.warmth] = round(min(max(w / 0.15 * 100 * 0.7, -50), 50))
            let magenta = ((mean.x + mean.z) / 2 - mean.y) / max(mean.y, 0.02)
            result[.tint] = round(min(max(-magenta / 0.12 * 100 * 0.7, -50), 50))
        }

        // Vibrance: muted photos get more.
        result[.vibrance] = stats.meanChroma < 0.2 ? 20 : 10
        return result
    }
}

/// Brightness and color summaries of a photo's visible pixels, for Auto.
struct PhotoStatistics {
    private(set) var count = 0
    private var luma = [Int](repeating: 0, count: 256)
    private var sum = SIMD3<Double>.zero
    private var chroma = 0.0

    init(_ buffer: PixelBuffer, selection: SelectionMask?) {
        let region = (selection?.bounds ?? buffer.bounds).intersection(buffer.bounds)
        // A sample of at most about a million pixels is plenty for these averages.
        let stride = max(1, Int((Double(region.area) / 1_000_000).squareRoot().rounded(.up)))
        for y in Swift.stride(from: region.minY, to: region.maxY, by: stride) {
            let row = buffer.row(y)
            for x in Swift.stride(from: region.minX, to: region.maxX, by: stride) {
                let pixel = row[x]
                guard pixel.a > 0, selection.map({ $0[x, y] > 0 }) ?? true else { continue }
                count += 1
                luma[Int(pixel.luminance)] += 1
                let c = SIMD3(Double(pixel.r), Double(pixel.g), Double(pixel.b)) / 255
                sum += c
                chroma += c.max() - c.min()
            }
        }
    }

    var meanColor: SIMD3<Double> { count > 0 ? sum / Double(count) : .zero }
    var meanChroma: Double { count > 0 ? chroma / Double(count) : 0 }

    /// The brightness (0...1) below which `fraction` of the pixels fall.
    func percentile(_ fraction: Double) -> Double {
        let target = Double(count) * fraction
        var running = 0
        for value in 0..<256 {
            running += luma[value]
            if Double(running) >= target { return Double(value) / 255 }
        }
        return 1
    }

    func shareAbove(_ level: Double) -> Double {
        Double(luma[Int(level * 255)...].reduce(0, +)) / Double(max(count, 1))
    }

    func shareBelow(_ level: Double) -> Double {
        Double(luma[..<Int(level * 255)].reduce(0, +)) / Double(max(count, 1))
    }
}
