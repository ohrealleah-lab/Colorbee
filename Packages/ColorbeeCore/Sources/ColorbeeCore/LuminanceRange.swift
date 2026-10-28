/// Edit ▸ Luminance Range… (FR-9.7 item 3): selects by brightness, from a lower to an upper bound (0 is black, 100
/// white), fully between them and fading out beyond them over a width that Smoothness sets. The result is a soft
/// selection (FR-3.4). Transparent pixels aren't selected; partly transparent ones are, as much as they show.
public struct LuminanceRange: Sendable, Equatable {
    public var lower: Double
    public var upper: Double
    /// 0...100: how far beyond the bounds the selection fades out, up to 40 brightness points at 100.
    public var smoothness: Double

    public init(lower: Double, upper: Double, smoothness: Double = 50) {
        self.lower = lower
        self.upper = upper
        self.smoothness = smoothness
    }

    public static let shadows = LuminanceRange(lower: 0, upper: 30)
    public static let midtones = LuminanceRange(lower: 35, upper: 65)
    public static let highlights = LuminanceRange(lower: 70, upper: 100)

    /// How much a brightness (0...100) is selected, 0...1.
    func amount(luminance: Double) -> Double {
        let low = min(max(min(lower, upper), 0), 100), high = min(max(max(lower, upper), 0), 100)
        let fade = min(max(smoothness, 0), 100) / 100 * 40
        if luminance >= low && luminance <= high { return 1 }
        guard fade > 0 else { return 0 }
        let distance = luminance < low ? low - luminance : luminance - high
        return 1 - PhotoAdjustments.smoothstep(0, fade, distance)
    }

    /// The selection over `buffer`, the size of the canvas; nil when nothing matches.
    public func selection(in buffer: PixelBuffer) -> SelectionMask? {
        // Each of the 256 brightness levels' amount, worked out once.
        let amounts = (0...255).map { amount(luminance: Double($0) / 255 * 100) }
        return SelectionMask.measured(buffer) { pixel in
            let luminance = PhotoAdjustments.luma(SIMD3(Double(pixel.r), Double(pixel.g), Double(pixel.b)))
            return UInt8((amounts[Int(luminance.rounded())] * Double(pixel.a)).rounded())
        }
    }
}
