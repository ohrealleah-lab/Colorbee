import Foundation

/// Curves (FR-9.5): a tone curve for red, green and blue together, then one for each channel.
public struct Curves: Sendable, Hashable, Codable {
    public struct Point: Sendable, Hashable, Codable {
        public var x: Double
        public var y: Double
        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    public enum Channel: Int, Sendable, CaseIterable, Codable {
        case rgb, red, green, blue
    }

    /// Points from 0 to 255 on both axes, kept in order of `x`. A curve needs at least two points.
    public var rgb: [Point]
    public var red: [Point]
    public var green: [Point]
    public var blue: [Point]

    public static let straight = [Point(x: 0, y: 0), Point(x: 255, y: 255)]
    public static let identity = Curves(rgb: straight, red: straight, green: straight, blue: straight)

    public init(rgb: [Point], red: [Point], green: [Point], blue: [Point]) {
        self.rgb = rgb
        self.red = red
        self.green = green
        self.blue = blue
    }

    public subscript(channel: Channel) -> [Point] {
        get {
            switch channel {
            case .rgb: rgb
            case .red: red
            case .green: green
            case .blue: blue
            }
        }
        set {
            let sorted = newValue.sorted { $0.x < $1.x }
            switch channel {
            case .rgb: rgb = sorted
            case .red: red = sorted
            case .green: green = sorted
            case .blue: blue = sorted
            }
        }
    }

    /// The output for each 8-bit input value of each channel: its own curve, then the RGB curve.
    public var tables: (red: [UInt8], green: [UInt8], blue: [UInt8]) {
        let master = Self.table(rgb)
        func combined(_ points: [Point]) -> [UInt8] { Self.table(points).map { master[Int($0)] } }
        return (combined(red), combined(green), combined(blue))
    }

    /// A smooth curve through `points` that never overshoots between them (monotone cubic, Fritsch–Carlson),
    /// so a rising set of points gives a rising curve. Flat beyond the first and last points.
    public static func table(_ points: [Point]) -> [UInt8] {
        let points = points.sorted { $0.x < $1.x }
        guard points.count >= 2 else {
            let value = UInt8(min(max(points.first?.y ?? 0, 0), 255).rounded())
            return points.isEmpty ? (0..<256).map { UInt8($0) } : [UInt8](repeating: value, count: 256)
        }
        let count = points.count
        var slopes = [Double](repeating: 0, count: count - 1)
        for i in 0..<(count - 1) {
            let dx = points[i + 1].x - points[i].x
            slopes[i] = dx > 0 ? (points[i + 1].y - points[i].y) / dx : 0
        }
        var tangents = [Double](repeating: 0, count: count)
        tangents[0] = slopes[0]
        tangents[count - 1] = slopes[count - 2]
        for i in 1..<(count - 1) {
            tangents[i] = slopes[i - 1] * slopes[i] <= 0 ? 0 : (slopes[i - 1] + slopes[i]) / 2
        }
        for i in 0..<(count - 1) where slopes[i] != 0 {
            let a = tangents[i] / slopes[i], b = tangents[i + 1] / slopes[i]
            let length = (a * a + b * b).squareRoot()
            if length > 3 {
                tangents[i] = 3 * a / length * slopes[i]
                tangents[i + 1] = 3 * b / length * slopes[i]
            }
        }
        return (0..<256).map { value in
            let x = Double(value)
            let y: Double
            if x <= points[0].x {
                y = points[0].y
            } else if x >= points[count - 1].x {
                y = points[count - 1].y
            } else {
                var i = 0
                while points[i + 1].x < x { i += 1 }
                let h = points[i + 1].x - points[i].x
                let t = (x - points[i].x) / h
                let t2 = t * t, t3 = t2 * t
                y = (2 * t3 - 3 * t2 + 1) * points[i].y + (t3 - 2 * t2 + t) * h * tangents[i]
                    + (-2 * t3 + 3 * t2) * points[i + 1].y + (t3 - t2) * h * tangents[i + 1]
            }
            return UInt8(min(max(y, 0), 255).rounded())
        }
    }
}
