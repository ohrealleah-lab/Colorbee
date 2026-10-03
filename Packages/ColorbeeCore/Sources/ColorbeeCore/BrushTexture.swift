/// Grain for the textured brushes. It's fixed to image pixels rather than to the stroke, so overlapping
/// strokes share one grain, like crayon or graphite on the same sheet of paper.
enum BrushTexture {
    /// A repeatable pseudo-random value in 0..<1 for a pixel.
    static func hash(_ x: Int, _ y: Int, seed: UInt32 = 0) -> Double {
        var h = UInt32(truncatingIfNeeded: x) &* 0x8DA6_B343
        h ^= UInt32(truncatingIfNeeded: y) &* 0xD816_3841
        h ^= seed &* 0xCB1A_B31F
        h ^= h >> 13
        h &*= 0x5BD1_E995
        h ^= h >> 15
        return Double(h) / 4_294_967_296
    }

    /// Smooth noise in 0..<1: `hash` on a unit lattice, blended between lattice points.
    static func smooth(_ x: Double, _ y: Double, seed: UInt32 = 0) -> Double {
        let x0 = Int(x.rounded(.down)), y0 = Int(y.rounded(.down))
        let fx = x - Double(x0), fy = y - Double(y0)
        let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
        let top = hash(x0, y0, seed: seed) + (hash(x0 + 1, y0, seed: seed) - hash(x0, y0, seed: seed)) * sx
        let bottom = hash(x0, y0 + 1, seed: seed) + (hash(x0 + 1, y0 + 1, seed: seed) - hash(x0, y0 + 1, seed: seed)) * sx
        return top + (bottom - top) * sy
    }
}

/// A small, fast, seedable generator, so sprayed and bristled strokes can be reproduced in tests.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
