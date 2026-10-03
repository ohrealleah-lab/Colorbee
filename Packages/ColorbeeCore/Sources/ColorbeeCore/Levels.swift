import Foundation

/// Levels (FR-9.5): input black and white points and a midtone gamma, applied to red, green and blue alike.
public struct Levels: Sendable, Hashable, Codable {
    /// 0...254; values at or below become black.
    public var black: Double
    /// 1...255; values at or above become white.
    public var white: Double
    /// 0.1...9.99; above 1 lightens the midtones, below 1 darkens them.
    public var gamma: Double

    public init(black: Double = 0, white: Double = 255, gamma: Double = 1) {
        self.black = black
        self.white = white
        self.gamma = gamma
    }

    public static let identity = Levels()

    /// Black and white points at the darkest and lightest channel values of the visible pixels, so the
    /// darkest pixel becomes black and the lightest white (Auto Contrast, AC-31). Gamma stays at 1.
    public static func auto(from histogram: Histogram) -> Levels {
        guard let low = histogram.lowestValue, let high = histogram.highestValue, high > low else { return .identity }
        return Levels(black: Double(low), white: Double(high), gamma: 1)
    }

    /// The output for each 8-bit input value.
    public var table: [UInt8] {
        let black = min(max(black, 0), 254), white = max(min(white, 255), black + 1)
        let exponent = 1 / min(max(gamma, 0.1), 9.99)
        return (0..<256).map { value in
            let t = min(max((Double(value) - black) / (white - black), 0), 1)
            return UInt8((pow(t, exponent) * 255).rounded())
        }
    }
}
