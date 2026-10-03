import Foundation

/// Add Noise, Motion Blur, Emboss and Vignette (FR-9.5). Each returns the processed region and where it starts.
extension Effects {
    static func noisy(_ buffer: PixelBuffer, region: IntRect, amount: Double, monochrome: Bool) -> (PixelBuffer, IntPoint) {
        let result = PixelBuffer(width: region.width, height: region.height)
        let spread = min(max(amount, 0), 100) / 100 * 128
        ParallelRows.forEach(region.minY..<region.maxY) { rows in
            for y in rows {
                let source = buffer.row(y), target = result.row(y - region.minY)
                for x in region.minX..<region.maxX {
                    let pixel = source[x]
                    func grain(_ channel: UInt64) -> Double { Noise.triangular(x: x, y: y, channel: channel) * spread }
                    let shared = monochrome ? grain(0) : 0
                    func shifted(_ value: UInt8, _ channel: UInt64) -> UInt8 {
                        UInt8(min(255, max(0, (Double(value) + (monochrome ? shared : grain(channel))).rounded())))
                    }
                    target[x - region.minX] = Pixel(r: shifted(pixel.r, 1), g: shifted(pixel.g, 2), b: shifted(pixel.b, 3), a: pixel.a)
                }
            }
        }
        return (result, IntPoint(x: region.minX, y: region.minY))
    }

    /// Averages evenly spaced samples along a line through each pixel, in premultiplied color so transparent
    /// pixels don't darken the streaks. Unselected pixels are left out of the average.
    static func motionBlurred(_ buffer: PixelBuffer, region: IntRect, angle: Double, distance: Double, selection: SelectionMask?) -> (PixelBuffer, IntPoint) {
        let result = PixelBuffer(width: region.width, height: region.height)
        let radians = angle * .pi / 180
        let dx = cos(radians), dy = -sin(radians)
        let count = max(1, Int(min(max(distance, 1), 200).rounded()))
        // About a pixel apart, centered on the pixel, so the streak has no gaps.
        let spacing = count > 1 ? (min(max(distance, 1), 200) - 1) / Double(count - 1) : 0
        let offsets: [(Int, Int)] = (0..<count).map { index in
            let t = (Double(index) - Double(count - 1) / 2) * spacing
            return (Int((t * dx).rounded()), Int((t * dy).rounded()))
        }
        let bounds = buffer.bounds
        ParallelRows.forEach(region.minY..<region.maxY) { rows in
            for y in rows {
                let target = result.row(y - region.minY)
                for x in region.minX..<region.maxX {
                    var sum = SIMD4<Float>.zero
                    var samples: Float = 0
                    for (ox, oy) in offsets {
                        let sx = min(max(x + ox, bounds.minX), bounds.maxX - 1), sy = min(max(y + oy, bounds.minY), bounds.maxY - 1)
                        guard isSelected(selection, sx, sy) else { continue }
                        sum += Compositing.premultiplied(buffer.row(sy)[sx])
                        samples += 1
                    }
                    target[x - region.minX] = samples > 0 ? Compositing.pixel(sum / samples) : buffer.row(y)[x]
                }
            }
        }
        return (result, IntPoint(x: region.minX, y: region.minY))
    }

    /// Gray relief: each pixel is mid-gray plus the change in brightness across it, seen from `angle`.
    static func embossed(_ buffer: PixelBuffer, region: IntRect, angle: Double, depth: Double) -> (PixelBuffer, IntPoint) {
        let result = PixelBuffer(width: region.width, height: region.height)
        let radians = angle * .pi / 180
        let dx = cos(radians), dy = -sin(radians)
        let scale = min(max(depth, 1), 10) / 2
        func luminance(_ x: Double, _ y: Double) -> Double {
            let bounds = buffer.bounds
            let fx = min(max(x, 0), Double(bounds.width - 1)), fy = min(max(y, 0), Double(bounds.height - 1))
            let x0 = Int(fx), y0 = Int(fy), x1 = min(x0 + 1, bounds.width - 1), y1 = min(y0 + 1, bounds.height - 1)
            let tx = fx - Double(x0), ty = fy - Double(y0)
            func l(_ px: Int, _ py: Int) -> Double { Double(buffer.row(py)[px].luminance) }
            let top = l(x0, y0) + (l(x1, y0) - l(x0, y0)) * tx
            let bottom = l(x0, y1) + (l(x1, y1) - l(x0, y1)) * tx
            return top + (bottom - top) * ty
        }
        ParallelRows.forEach(region.minY..<region.maxY) { rows in
            for y in rows {
                let target = result.row(y - region.minY), source = buffer.row(y)
                for x in region.minX..<region.maxX {
                    let relief = luminance(Double(x) - dx, Double(y) - dy) - luminance(Double(x) + dx, Double(y) + dy)
                    let gray = UInt8(min(255, max(0, (128 + relief * scale).rounded())))
                    target[x - region.minX] = Pixel(r: gray, g: gray, b: gray, a: source[x].a)
                }
            }
        }
        return (result, IntPoint(x: region.minX, y: region.minY))
    }

    static func vignetted(_ buffer: PixelBuffer, region: IntRect, amount: Double, size: Double) -> (PixelBuffer, IntPoint) {
        let result = PixelBuffer(width: region.width, height: region.height)
        ParallelRows.forEach(region.minY..<region.maxY) { rows in
            for y in rows {
                let source = buffer.row(y), target = result.row(y - region.minY)
                for x in region.minX..<region.maxX {
                    let strength = Vignette.strength(x: x, y: y, in: region, size: size) * amount / 100
                    target[x - region.minX] = Vignette.apply(strength, to: source[x])
                }
            }
        }
        return (result, IntPoint(x: region.minX, y: region.minY))
    }
}

/// Position-based grain that's the same every time for the same pixel.
enum Noise {
    static func hash(x: Int, y: Int, channel: UInt64) -> UInt64 {
        var z = UInt64(bitPattern: Int64(x)) &* 0x9E37_79B9_7F4A_7C15 ^ UInt64(bitPattern: Int64(y)) &* 0xC2B2_AE3D_27D4_EB4F ^ channel &* 0x1656_67B1_9E37_79F9
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// -1...1, more often near 0 (the sum of two even draws), which looks like film grain.
    static func triangular(x: Int, y: Int, channel: UInt64) -> Double {
        let value = hash(x: x, y: y, channel: channel)
        let a = Double(value & 0xFFFF_FFFF) / Double(UInt32.max), b = Double(value >> 32) / Double(UInt32.max)
        return a + b - 1
    }
}

/// The vignette's falloff, shared by Effects ▸ Vignette and Adjust Photo's Vignette slider.
public enum Vignette {
    /// 0 in the middle, rising to 1 at the corners of `region`. `size` 0...100 is how far out it starts.
    public static func strength(x: Int, y: Int, in region: IntRect, size: Double) -> Double {
        let cx = Double(region.minX) + Double(region.width) / 2, cy = Double(region.minY) + Double(region.height) / 2
        let nx = (Double(x) + 0.5 - cx) / (Double(region.width) / 2), ny = (Double(y) + 0.5 - cy) / (Double(region.height) / 2)
        let distance = (nx * nx + ny * ny).squareRoot() / 2.squareRoot()
        let start = min(max(size, 0), 100) / 100 * 0.95
        let t = min(max((distance - start) / (1 - start), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Positive strength darkens, negative lightens.
    public static func apply(_ strength: Double, to pixel: Pixel) -> Pixel {
        func channel(_ value: UInt8) -> UInt8 {
            let v = Double(value)
            let out = strength >= 0 ? v * (1 - strength) : v + (255 - v) * -strength
            return UInt8(min(255, max(0, out.rounded())))
        }
        return Pixel(r: channel(pixel.r), g: channel(pixel.g), b: channel(pixel.b), a: pixel.a)
    }
}
