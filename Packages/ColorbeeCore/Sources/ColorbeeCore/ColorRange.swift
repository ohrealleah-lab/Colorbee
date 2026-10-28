/// Edit ▸ Color Range… (FR-9.7 item 3): selects the colors clicked in the picture, and colors near them. Fuzziness
/// sets how near: the closest colors are fully selected and the selection fades out to the edge of the range, so the
/// result is a soft selection (FR-3.4). Colors are compared as the Magic Wand compares them, by the largest
/// difference in any channel, alpha included.
public struct ColorRange: Sendable, Equatable {
    /// The colors clicked; Shift-click adds more.
    public var colors: [Pixel]
    /// 0...100. At 0, only the exact colors.
    public var fuzziness: Double

    public init(colors: [Pixel] = [], fuzziness: Double = 25) {
        self.colors = colors
        self.fuzziness = fuzziness
    }

    /// How much a pixel `difference` levels away from the nearest clicked color is selected (0...255): fully up to
    /// half the range, then fading smoothly to nothing at its edge.
    func amount(difference: Int) -> UInt8 {
        let range = min(max(fuzziness, 0), 100) / 100 * 255
        guard range > 0 else { return difference == 0 ? 255 : 0 }
        let fade = 1 - PhotoAdjustments.smoothstep(range * 0.5, range, Double(difference))
        return UInt8((fade * 255).rounded())
    }

    /// The selection over `buffer`, the size of the canvas; nil when nothing matches.
    public func selection(in buffer: PixelBuffer) -> SelectionMask? {
        guard !colors.isEmpty else { return nil }
        // Every difference's amount, worked out once.
        let amounts = (0...255).map { amount(difference: $0) }
        let colors = colors.map { SIMD4($0.r, $0.g, $0.b, $0.a) }
        return SelectionMask.measured(buffer) { pixel in
            let value = SIMD4(pixel.r, pixel.g, pixel.b, pixel.a)
            var nearest = UInt8.max
            for color in colors {
                // Fully transparent pixels are one color, whatever their hidden channels, as for the wand.
                let difference = value.w | color.w == 0 ? 0 : (pointwiseMax(value, color) &- pointwiseMin(value, color)).max()
                nearest = min(nearest, difference)
            }
            return amounts[Int(nearest)]
        }
    }
}

extension SelectionMask {
    /// A canvas-sized selection from how much each pixel of `buffer` is selected, worked out on all cores; nil when
    /// nothing is.
    static func measured(_ buffer: PixelBuffer, _ amount: (Pixel) -> UInt8) -> SelectionMask? {
        let width = buffer.width, height = buffer.height
        guard width > 0, height > 0 else { return nil }
        var values = [UInt8](repeating: 0, count: width * height)
        values.withUnsafeMutableBufferPointer { target in
            ParallelRows.forEach(0..<height) { rows in
                for y in rows {
                    let row = buffer.row(y)
                    for x in 0..<width { target[y * width + x] = amount(row[x]) }
                }
            }
        }
        return SelectionMask(bounds: IntRect(x: 0, y: 0, width: width, height: height), values: values).trimmed()
    }
}
