import Foundation

/// The Vignette's shape and the Grain's look in Adjust Photo's Effects section (FR-9.7 item 5). The Vignette and Grain
/// sliders are the amounts; these start at the vignette Colorbee always had (Q14.1) and Lightroom's grain (Q14.2).
/// Filters keep them, and a filter's Intensity scales only the amounts (Q0.7).
public struct PhotoEffects: Sendable, Hashable {
    /// How far out the vignette starts: higher leaves more of the middle untouched.
    public var midpoint = 50.0
    /// -100 is nearly a rectangle, 0 follows the picture's shape, 100 is a circle.
    public var roundness = 0.0
    /// How gradually the vignette fades in: 0 is a hard edge.
    public var feather = 50.0
    /// How big each grain is.
    public var grainSize = 25.0
    /// How uneven the grain is.
    public var grainRoughness = 50.0

    public static let range = 0.0...100.0
    public static let roundnessRange = -100.0...100.0

    public init() {}

    public var isDefault: Bool { self == PhotoEffects() }

    func clamped() -> PhotoEffects {
        func clamp(_ value: Double, _ range: ClosedRange<Double>, _ start: Double) -> Double {
            value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : start
        }
        let start = PhotoEffects()
        var result = PhotoEffects()
        result.midpoint = clamp(midpoint, Self.range, start.midpoint)
        result.roundness = clamp(roundness, Self.roundnessRange, start.roundness)
        result.feather = clamp(feather, Self.range, start.feather)
        result.grainSize = clamp(grainSize, Self.range, start.grainSize)
        result.grainRoughness = clamp(grainRoughness, Self.range, start.grainRoughness)
        return result
    }
}

/// A setting a file leaves out keeps its start, so a newer file still opens.
extension PhotoEffects: Codable {
    private enum CodingKeys: String, CodingKey {
        case midpoint, roundness, feather, grainSize, grainRoughness
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var effects = PhotoEffects()
        func read(_ key: CodingKeys, into value: inout Double) {
            if let stored = try? container.decodeIfPresent(Double.self, forKey: key) { value = stored }
        }
        read(.midpoint, into: &effects.midpoint)
        read(.roundness, into: &effects.roundness)
        read(.feather, into: &effects.feather)
        read(.grainSize, into: &effects.grainSize)
        read(.grainRoughness, into: &effects.grainRoughness)
        self = effects.clamped()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(midpoint, forKey: .midpoint)
        try container.encode(roundness, forKey: .roundness)
        try container.encode(feather, forKey: .feather)
        try container.encode(grainSize, forKey: .grainSize)
        try container.encode(grainRoughness, forKey: .grainRoughness)
    }
}

extension Vignette {
    /// One of Adjust Photo's vignettes: its amount (-100...100, positive darkens) and shape.
    public struct Shape: Sendable, Equatable {
        public var amount: Double
        public var midpoint = 50.0
        public var roundness = 0.0
        public var feather = 50.0
    }

    /// 0 inside the vignette, rising to 1 toward the edges of `region`. At midpoint 50, roundness 0 and feather 50
    /// this is exactly `strength(x:y:in:size:)` at size 50, the vignette Colorbee always had. Shaders.metal's
    /// `vignette_strength` does the same on screen.
    public static func strength(x: Int, y: Int, in region: IntRect, shape: Shape) -> Double {
        let halfWidth = Double(region.width) / 2, halfHeight = Double(region.height) / 2
        let dx = Double(x) + 0.5 - (Double(region.minX) + halfWidth), dy = Double(y) + 0.5 - (Double(region.minY) + halfHeight)
        let distance: Double
        if shape.roundness > 0 {
            // Toward a circle: both directions measured against the shorter side.
            let k = min(shape.roundness, 100) / 100, short = min(halfWidth, halfHeight)
            let nx = dx / (halfWidth + (short - halfWidth) * k), ny = dy / (halfHeight + (short - halfHeight) * k)
            distance = (nx * nx + ny * ny).squareRoot() / 2.squareRoot()
        } else if shape.roundness < 0 {
            // Toward a rectangle: a rounder-cornered square the further it goes.
            let p = 2 + min(-shape.roundness, 100) / 100 * 6
            let nx = abs(dx / halfWidth), ny = abs(dy / halfHeight)
            distance = pow(pow(nx, p) + pow(ny, p), 1 / p) / pow(2, 1 / p)
        } else {
            let nx = dx / halfWidth, ny = dy / halfHeight
            distance = (nx * nx + ny * ny).squareRoot() / 2.squareRoot()
        }
        let start = min(max(shape.midpoint, 0), 100) / 100 * 0.95
        let feather = min(max(shape.feather, 0), 100)
        let width = feather == 50 ? 1 - start : (1 - start) * feather / 50
        guard width > 0 else { return distance > start ? 1 : 0 }
        let t = min(max((distance - start) / width, 0), 1)
        return t * t * (3 - 2 * t)
    }
}

/// Film-like grain fixed to the picture's pixels, so the preview, the screen and the export all match (FR-9.7 item 5).
/// Shaders.metal's `grain_offset` does the same on screen.
public struct Grain: Sendable, Equatable {
    /// 0...100.
    public var amount: Double
    /// 0...100: each grain is 1 to 4 pixels across.
    public var size = 25.0
    /// 0...100: mixes in finer, more uneven grain.
    public var roughness = 50.0

    /// The brightness change at image pixel (x, y), as a fraction of full brightness: up to ±0.2 at amount 100.
    public func offset(x: Int, y: Int) -> Double {
        let cell = 1 + min(max(size, 0), 100) / 100 * 3
        let k = min(max(roughness, 0), 100) / 100
        let px = Double(x) + 0.5, py = Double(y) + 0.5
        let smooth = Self.valueNoise(px, py, cell: cell, seed: 1)
        let rough = k > 0 ? Self.valueNoise(px, py, cell: max(1, cell / 2), seed: 2) : 0
        return (smooth * (1 - k) + rough * k) * min(max(amount, 0), 100) / 100 * 0.2
    }

    /// Smoothly varying noise, -1...1, on a grid `cell` pixels apart.
    static func valueNoise(_ px: Double, _ py: Double, cell: Double, seed: UInt32) -> Double {
        let gx = px / cell - 0.5, gy = py / cell - 0.5
        let ix = gx.rounded(.down), iy = gy.rounded(.down)
        let fx = gx - ix, fy = gy - iy
        let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
        func corner(_ a: Int32, _ b: Int32) -> Double {
            Double(hash(Int32(ix) &+ a, Int32(iy) &+ b, seed)) / Double(UInt32.max) * 2 - 1
        }
        let top = corner(0, 0) + (corner(1, 0) - corner(0, 0)) * sx
        let bottom = corner(0, 1) + (corner(1, 1) - corner(0, 1)) * sx
        return top + (bottom - top) * sy
    }

    /// 32 bits, so the GPU can work out the very same values.
    static func hash(_ x: Int32, _ y: Int32, _ seed: UInt32) -> UInt32 {
        var h = UInt32(bitPattern: x) &* 0x8DA6_B343 ^ UInt32(bitPattern: y) &* 0xD816_3841 ^ seed &* 0xCB1A_B31F
        h ^= h >> 16
        h &*= 0x7FEB_352D
        h ^= h >> 15
        h &*= 0x846C_A68B
        h ^= h >> 16
        return h
    }

    /// Adds the grain to a pixel, the same amount to each channel.
    public func apply(to pixel: Pixel, x: Int, y: Int) -> Pixel {
        let shift = offset(x: x, y: y) * 255
        func channel(_ value: UInt8) -> UInt8 { UInt8(min(255, max(0, (Double(value) + shift).rounded()))) }
        return Pixel(r: channel(pixel.r), g: channel(pixel.g), b: channel(pixel.b), a: pixel.a)
    }
}
