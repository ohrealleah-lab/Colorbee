/// Levels, Curves and Posterize change each channel on its own, so the display shows them through a table of
/// all 256 values per channel, read without interpolation: exactly what export gives. A `ColorLookup`'s
/// interpolation would smooth over their hard steps (review C, finding 2).
public struct ChannelTable: Sendable, Equatable {
    /// The new red, green and blue for each value 0...255, as RGBA8 (alpha unused): a 256 × 1 texture.
    public let values: [UInt8]

    public init?(_ effect: Effect) {
        guard effect.usesChannelTable, let transform = effect.colorTransform else { return nil }
        var values = [UInt8](repeating: 255, count: 256 * 4)
        for index in 0..<256 {
            let value = UInt8(index)
            values[index * 4] = transform(Pixel(r: value, g: 0, b: 0)).r
            values[index * 4 + 1] = transform(Pixel(r: 0, g: value, b: 0)).g
            values[index * 4 + 2] = transform(Pixel(r: 0, g: 0, b: value)).b
        }
        self.values = values
    }

    func apply(_ pixel: Pixel) -> Pixel {
        Pixel(r: values[Int(pixel.r) * 4], g: values[Int(pixel.g) * 4 + 1], b: values[Int(pixel.b) * 4 + 2], a: pixel.a)
    }
}
