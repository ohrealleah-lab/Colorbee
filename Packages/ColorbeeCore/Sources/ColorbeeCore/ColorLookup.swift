/// A 3D color lookup table sampled from a per-pixel adjustment, so the display can show any color
/// adjustment layer with one shader (FR-8.4). Exports use the exact adjustment, not the table.
public struct ColorLookup: Sendable {
    /// Points along each axis.
    public let size: Int
    /// Straight RGBA in 0...1, red varying fastest, then green, then blue (Metal's 3D texture order).
    public let values: [Float]

    /// The size for adjustments with narrow color changes (the Color Mixer): measured, a 33-point table was off from
    /// the exact result by up to 17 levels near some colors' edges, a 65-point one by up to 8, about what the color
    /// sliders already show at 33 (stage 4). It's 4.4 MB rather than 0.6.
    public static let fineSize = 65

    /// Worked out on all cores, one blue slice per band, so a 65-point table keeps up with a dragged slider.
    public init(size: Int = 33, _ transform: (Pixel) -> Pixel) {
        self.size = size
        var values = [Float](repeating: 1, count: size * size * size * 4)
        let step = 255 / Double(size - 1)
        values.withUnsafeMutableBufferPointer { buffer in
            ParallelRows.forEach(0..<size, minimumRows: 1) { slices in
                for b in slices {
                    for g in 0..<size {
                        for r in 0..<size {
                            let input = Pixel(r: UInt8((Double(r) * step).rounded()), g: UInt8((Double(g) * step).rounded()),
                                              b: UInt8((Double(b) * step).rounded()))
                            let output = transform(input)
                            let index = ((b * size + g) * size + r) * 4
                            buffer[index] = Float(output.r) / 255
                            buffer[index + 1] = Float(output.g) / 255
                            buffer[index + 2] = Float(output.b) / 255
                        }
                    }
                }
            }
        }
        self.values = values
    }

    /// The table for a color adjustment layer, or nil when the display handles it another way.
    public init?(_ effect: Effect) {
        guard effect.usesColorLookup, let transform = effect.colorTransform else { return nil }
        if case .photo(let edit) = effect, edit.needsFineColorTable {
            self.init(size: Self.fineSize, transform)
        } else {
            self.init(transform)
        }
    }
}
