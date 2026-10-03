/// A 3D color lookup table sampled from a per-pixel adjustment, so the display can show any color
/// adjustment layer with one shader (FR-8.4). Exports use the exact adjustment, not the table.
public struct ColorLookup: Sendable {
    /// Points along each axis.
    public let size: Int
    /// Straight RGBA in 0...1, red varying fastest, then green, then blue (Metal's 3D texture order).
    public let values: [Float]

    public init(size: Int = 33, _ transform: (Pixel) -> Pixel) {
        self.size = size
        var values = [Float](repeating: 1, count: size * size * size * 4)
        let step = 255 / Double(size - 1)
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    let input = Pixel(r: UInt8((Double(r) * step).rounded()), g: UInt8((Double(g) * step).rounded()),
                                      b: UInt8((Double(b) * step).rounded()))
                    let output = transform(input)
                    let index = ((b * size + g) * size + r) * 4
                    values[index] = Float(output.r) / 255
                    values[index + 1] = Float(output.g) / 255
                    values[index + 2] = Float(output.b) / 255
                }
            }
        }
        self.values = values
    }

    /// The table for a color adjustment layer, or nil when the display handles it another way.
    public init?(_ effect: Effect) {
        guard effect.usesColorLookup, let transform = effect.colorTransform else { return nil }
        self.init(transform)
    }
}
