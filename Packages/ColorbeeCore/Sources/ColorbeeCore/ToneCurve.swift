import Foundation

/// Adjust Photo's parametric Tone Curve (FR-9.7 item 6): four regions, Shadows, Darks, Lights and Highlights, each
/// -100...100, between three split points, as in Lightroom. Applied to red, green and blue alike, after the Light and
/// Color sliders. Point curves are Adjustments ▸ Curves… (Q15.4).
public struct ToneCurve: Sendable, Hashable {
    public enum Region: Int, CaseIterable, Sendable {
        case shadows, darks, lights, highlights

        public var title: String {
            switch self {
            case .shadows: "Shadows"
            case .darks: "Darks"
            case .lights: "Lights"
            case .highlights: "Highlights"
            }
        }
    }

    /// Each region's amount, -100...100, in `Region` order.
    public var amounts: [Double] = [0, 0, 0, 0]
    /// Where Shadows meets Darks, Darks meets Lights and Lights meets Highlights, 0...100, in order.
    public var splits: [Double] = Self.defaultSplits

    public static let defaultSplits = [25.0, 50, 75]
    /// The closest two splits may be, and how far from the ends.
    public static let splitGap = 5.0
    public static let amountRange = -100.0...100.0

    public init() {}

    public subscript(region: Region) -> Double {
        get { amounts[region.rawValue] }
        set { amounts[region.rawValue] = min(max(newValue, Self.amountRange.lowerBound), Self.amountRange.upperBound) }
    }

    public var isNeutral: Bool { amounts.allSatisfy { $0 == 0 } }
    /// Neutral with the splits where they start: nothing worth keeping.
    public var isDefault: Bool { isNeutral && splits == Self.defaultSplits }

    /// The region a pixel's brightness falls in, between the splits, for dragging on the picture (FR-9.7 item 6).
    public func region(for pixel: Pixel) -> Region {
        let brightness = PhotoAdjustments.luma(SIMD3(Double(pixel.r), Double(pixel.g), Double(pixel.b))) / 255 * 100
        let index = splits.firstIndex { brightness < $0 } ?? 3
        return Region(rawValue: index)!
    }

    /// Moves split `index`, keeping the three in order and `splitGap` apart.
    public mutating func setSplit(_ index: Int, to value: Double) {
        let low = index == 0 ? Self.splitGap : splits[index - 1] + Self.splitGap
        let high = index == 2 ? 100 - Self.splitGap : splits[index + 1] - Self.splitGap
        splits[index] = min(max(value, low), high)
    }

    /// The amounts times `factor`, for a filter's intensity; the splits stay (Q0.7).
    public func scaled(by factor: Double) -> ToneCurve {
        var curve = self
        curve.amounts = amounts.map { $0 * factor }
        return curve
    }

    /// The curve's points, 0...255 on both axes: the ends stay put, and each region moves the middle of its stretch
    /// up or down. A region moves at most 45% of the way to its neighbors' points, so the curve always rises.
    public var points: [Curves.Point] {
        let s = splits.map { $0 / 100 }
        let centers = [s[0] / 2, (s[0] + s[1]) / 2, (s[1] + s[2]) / 2, (s[2] + 1) / 2]
        let xs = [0] + centers + [1]
        var points = [Curves.Point(x: 0, y: 0)]
        for (index, center) in centers.enumerated() {
            let room = min(center - xs[index], xs[index + 2] - center) * 0.45
            let y = center + amounts[index] / 100 * room
            points.append(Curves.Point(x: center * 255, y: y * 255))
        }
        points.append(Curves.Point(x: 255, y: 255))
        return points
    }

    /// The curve as a table of 256 values.
    public var table: [UInt8] { Curves.table(points) }

    public var transform: (Pixel) -> Pixel {
        let table = table
        return { Pixel(r: table[Int($0.r)], g: table[Int($0.g)], b: table[Int($0.b)], a: $0.a) }
    }
}

/// A file that leaves something out, or holds a value out of range, still opens.
extension ToneCurve: Codable {
    private enum CodingKeys: String, CodingKey {
        case amounts, splits
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        if let amounts = try? container.decodeIfPresent([Double].self, forKey: .amounts), amounts.count == 4 {
            for region in Region.allCases where amounts[region.rawValue].isFinite { self[region] = amounts[region.rawValue] }
        }
        if let splits = try? container.decodeIfPresent([Double].self, forKey: .splits), splits.count == 3,
           splits.allSatisfy(\.isFinite), splits[0] >= Self.splitGap, splits[1] - splits[0] >= Self.splitGap,
           splits[2] - splits[1] >= Self.splitGap, splits[2] <= 100 - Self.splitGap {
            self.splits = splits
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(amounts, forKey: .amounts)
        try container.encode(splits, forKey: .splits)
    }
}
