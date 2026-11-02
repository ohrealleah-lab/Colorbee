import CoreGraphics
import Foundation

/// Refine Edge (Leah, 2026-11-02): moves a subject mask's soft, rounded edge onto the picture's own edges, so a lamp's
/// stem keeps its waist and hair ends where the hair does. It's a color guided filter (He, Sun and Tang, 2010): near
/// the edge, each small window fits the mask as a blend of the picture's red, green and blue, which follows the
/// picture's edges. Only pixels near the mask's edge change, so a subject's inside stays whole and the background stays
/// clear.
public enum RefineEdge {
    /// 8 px looked best on both a 1,100 px portrait and a 2,144 px game screenshot (Leah's before-and-after,
    /// 2026-11-02); 16 px brought back smears of the background beside hair, and haloed the lamp. Smaller pictures get
    /// less, down to 4 px, and Vision's outline is coarser on much larger ones, so they get more, up to 16 px.
    static func radius(for size: IntSize) -> Int {
        let shorter = Double(min(size.width, size.height))
        let radius = shorter < 1120 ? shorter / 140 : max(8, shorter / 280)
        return min(16, max(4, Int(radius.rounded())))
    }

    static let epsilon: Float = 1e-3
    static let tileSize = 256

    /// `mask` refined against the picture `image`, of the same size. Off the main thread.
    public static func refined(_ mask: [UInt8], in image: CGImage) async -> [UInt8] {
        await Task.detached(priority: .userInitiated) {
            let size = IntSize(width: image.width, height: image.height)
            guard mask.count == size.width * size.height, let guide = rgba(of: image) else { return mask }
            return refined(mask, guide: guide, size: size, radius: radius(for: size))
        }.value
    }

    /// The picture's pixels as RGBA bytes, in its own color space, so nothing is converted.
    static func rgba(of image: CGImage) -> [UInt8]? {
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                          bytesPerRow: image.width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        return drawn ? bytes : nil
    }

    /// The work, in tiles on all cores. Each tile reads a margin of twice the radius around it, which is everything its
    /// own pixels depend on, so the tiles join with no seams. A tile whose mask is all one value is left as it is.
    static func refined(_ mask: [UInt8], guide: [UInt8], size: IntSize, radius: Int, tile: Int = tileSize) -> [UInt8] {
        var result = mask
        let columns = (size.width + tile - 1) / tile, rows = (size.height + tile - 1) / tile
        result.withUnsafeMutableBufferPointer { buffer in
            // Each tile writes only its own pixels.
            let output = UnsafeSendable(buffer)
            DispatchQueue.concurrentPerform(iterations: columns * rows) { index in
                let core = IntRect(x: index % columns * tile, y: index / columns * tile, width: tile, height: tile)
                    .intersection(IntRect(size: size))
                refineTile(core, mask: mask, guide: guide, size: size, radius: radius, into: output.value)
            }
        }
        return result
    }

    private static func refineTile(_ core: IntRect, mask: [UInt8], guide: [UInt8], size: IntSize, radius: Int,
                                   into output: UnsafeMutableBufferPointer<UInt8>) {
        let margin = 2 * radius
        let region = IntRect(x: core.x - margin, y: core.y - margin, width: core.width + 2 * margin, height: core.height + 2 * margin)
            .intersection(IntRect(size: size))
        let w = region.width, h = region.height, n = w * h
        var p = [Float](repeating: 0, count: n)
        var low: UInt8 = 255, high: UInt8 = 0
        var I = [[Float]](repeating: [Float](repeating: 0, count: n), count: 3)
        for y in 0..<h {
            for x in 0..<w {
                let source = (region.y + y) * size.width + region.x + x, here = y * w + x
                let value = mask[source]
                low = min(low, value)
                high = max(high, value)
                p[here] = Float(value) / 255
                for channel in 0..<3 { I[channel][here] = Float(guide[source * 4 + channel]) / 255 }
            }
        }
        guard low < high else { return }

        let box = { (values: [Float]) in boxMean(values, width: w, height: h, radius: radius) }
        let meanI = I.map(box)
        let meanP = box(p)
        // The picture's color covariance in each window (rr, rg, rb, gg, gb, bb) and its covariance with the mask.
        let pairs = [(0, 0), (0, 1), (0, 2), (1, 1), (1, 2), (2, 2)]
        let sigma = pairs.map { pair in
            let product = box(zip(I[pair.0], I[pair.1]).map(*))
            return (0..<n).map { product[$0] - meanI[pair.0][$0] * meanI[pair.1][$0] }
        }
        let covariance = (0..<3).map { channel in
            let product = box(zip(I[channel], p).map(*))
            return (0..<n).map { product[$0] - meanI[channel][$0] * meanP[$0] }
        }
        var A = [[Float]](repeating: [Float](repeating: 0, count: n), count: 3)
        var B = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let a = sigma[0][i] + epsilon, b = sigma[1][i], c = sigma[2][i]
            let d = sigma[3][i] + epsilon, e = sigma[4][i], f = sigma[5][i] + epsilon
            // The inverse of the symmetric matrix [a b c; b d e; c e f], by cofactors.
            let m00 = d * f - e * e, m01 = c * e - b * f, m02 = b * e - c * d
            let m11 = a * f - c * c, m12 = b * c - a * e, m22 = a * d - b * b
            let determinant = a * m00 + b * m01 + c * m02
            let v0 = covariance[0][i], v1 = covariance[1][i], v2 = covariance[2][i]
            let x = (m00 * v0 + m01 * v1 + m02 * v2) / determinant
            let y = (m01 * v0 + m11 * v1 + m12 * v2) / determinant
            let z = (m02 * v0 + m12 * v1 + m22 * v2) / determinant
            A[0][i] = x
            A[1][i] = y
            A[2][i] = z
            B[i] = meanP[i] - x * meanI[0][i] - y * meanI[1][i] - z * meanI[2][i]
        }
        let meanA = A.map(box), meanB = box(B)

        for y in (core.y - region.y)..<(core.maxY - region.y) {
            for x in (core.x - region.x)..<(core.maxX - region.x) {
                let i = y * w + x
                // Away from the edge (the mask the same all around), the mask stays exactly as it was.
                guard meanP[i] > 0.002, meanP[i] < 0.998 else { continue }
                let q = meanA[0][i] * I[0][i] + meanA[1][i] * I[1][i] + meanA[2][i] * I[2][i] + meanB[i]
                let value = Int((min(max(q, 0), 1) * 255).rounded())
                output[(region.y + y) * size.width + region.x + x] = value < 4 ? 0 : value > 251 ? 255 : UInt8(value)
            }
        }
    }

    /// The mean over a square of side 2 × radius + 1 around each pixel, clipped at the edges.
    static func boxMean(_ values: [Float], width: Int, height: Int, radius: Int) -> [Float] {
        var rows = [Double](repeating: 0, count: values.count)
        for y in 0..<height {
            var sum = 0.0
            let start = y * width
            for x in 0..<min(radius, width) { sum += Double(values[start + x]) }
            for x in 0..<width {
                if x + radius < width { sum += Double(values[start + x + radius]) }
                if x - radius - 1 >= 0 { sum -= Double(values[start + x - radius - 1]) }
                rows[start + x] = sum / Double(min(width - 1, x + radius) - max(0, x - radius) + 1)
            }
        }
        var result = [Float](repeating: 0, count: values.count)
        var sums = [Double](repeating: 0, count: width)
        for y in 0..<min(radius, height) {
            for x in 0..<width { sums[x] += rows[y * width + x] }
        }
        for y in 0..<height {
            if y + radius < height { for x in 0..<width { sums[x] += rows[(y + radius) * width + x] } }
            if y - radius - 1 >= 0 { for x in 0..<width { sums[x] -= rows[(y - radius - 1) * width + x] } }
            let count = Double(min(height - 1, y + radius) - max(0, y - radius) + 1)
            for x in 0..<width { result[y * width + x] = Float(sums[x] / count) }
        }
        return result
    }
}
