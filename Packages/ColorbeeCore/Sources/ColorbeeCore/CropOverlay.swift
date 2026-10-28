import Foundation

/// The guides Crop… shows over its box while it's dragged (FR-9.7 item 7, Q17.2). O switches to the next.
public enum CropOverlay: Int, CaseIterable, Sendable {
    case thirds, grid, diagonal, triangle, goldenRatio, goldenSpiral

    public var title: String {
        switch self {
        case .thirds: "Thirds"
        case .grid: "Grid"
        case .diagonal: "Diagonal"
        case .triangle: "Triangle"
        case .goldenRatio: "Golden Ratio"
        case .goldenSpiral: "Golden Spiral"
        }
    }

    public var next: CropOverlay { CropOverlay(rawValue: (rawValue + 1) % Self.allCases.count)! }

    /// The guide lines over `rect`, as segments in image coordinates. Curves are drawn as short straight pieces.
    public func lines(in rect: IntRect) -> [(Point2D, Point2D)] {
        let x0 = Double(rect.minX), y0 = Double(rect.minY), w = Double(rect.width), h = Double(rect.height)
        func point(_ u: Double, _ v: Double) -> Point2D { Point2D(x: x0 + u * w, y: y0 + v * h) }
        func across(_ fractions: [Double]) -> [(Point2D, Point2D)] {
            fractions.flatMap { f in [(point(f, 0), point(f, 1)), (point(0, f), point(1, f))] }
        }
        switch self {
        case .thirds:
            return across([1.0 / 3, 2.0 / 3])
        case .grid:
            return across((1..<8).map { Double($0) / 8 })
        case .goldenRatio:
            return across([0.382, 0.618])
        case .diagonal:
            // From each corner at 45°, as far as the box goes.
            let side = min(w, h)
            let corners = [(x0, y0, 1.0, 1.0), (x0 + w, y0, -1.0, 1.0), (x0, y0 + h, 1.0, -1.0), (x0 + w, y0 + h, -1.0, -1.0)]
            return corners.map { x, y, dx, dy in (Point2D(x: x, y: y), Point2D(x: x + dx * side, y: y + dy * side)) }
        case .triangle:
            // One diagonal, and a line from each of the other corners meeting it square.
            let a = point(0, 0), b = point(1, 1)
            func foot(_ p: Point2D) -> Point2D {
                let dx = b.x - a.x, dy = b.y - a.y
                let t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / (dx * dx + dy * dy)
                return Point2D(x: a.x + dx * t, y: a.y + dy * t)
            }
            let topRight = point(1, 0), bottomLeft = point(0, 1)
            return [(a, b), (topRight, foot(topRight)), (bottomLeft, foot(bottomLeft))]
        case .goldenSpiral:
            return Self.spiral(x0: x0, y0: y0, width: w, height: h)
        }
    }

    /// A golden spiral and the squares it turns through, made in a golden rectangle and stretched to the box, as
    /// photo editors do. On an upright box it's turned a quarter.
    private static func spiral(x0: Double, y0: Double, width: Double, height: Double) -> [(Point2D, Point2D)] {
        let phi = (1 + 5.0.squareRoot()) / 2
        let upright = height > width
        func placed(_ u: Double, _ v: Double) -> Point2D {
            upright ? Point2D(x: x0 + v * width, y: y0 + u / phi * height) : Point2D(x: x0 + u / phi * width, y: y0 + v * height)
        }
        var lines: [(Point2D, Point2D)] = []
        // The rectangle left to divide, in golden-rectangle units (phi across, 1 down).
        var (x, y, w, h) = (0.0, 0.0, phi, 1.0)
        for step in 0..<8 {
            let side = min(w, h)
            // Squares come off the left, top, right and bottom in turn; each holds a quarter turn of the spiral.
            let center: (x: Double, y: Double), start: Double
            switch step % 4 {
            case 0:
                lines.append((placed(x + side, y), placed(x + side, y + h)))
                center = (x + side, y + side); start = .pi
                (x, w) = (x + side, w - side)
            case 1:
                lines.append((placed(x, y + side), placed(x + w, y + side)))
                center = (x, y + side); start = 1.5 * .pi
                (y, h) = (y + side, h - side)
            case 2:
                lines.append((placed(x + w - side, y), placed(x + w - side, y + h)))
                center = (x + w - side, y); start = 0
                w -= side
            default:
                lines.append((placed(x, y + h - side), placed(x + w, y + h - side)))
                center = (x + side, y + h - side); start = 0.5 * .pi
                h -= side
            }
            let pieces = 12
            for piece in 0..<pieces {
                let a = start + Double(piece) / Double(pieces) * .pi / 2, b = start + Double(piece + 1) / Double(pieces) * .pi / 2
                lines.append((placed(center.x + side * cos(a), center.y + side * sin(a)), placed(center.x + side * cos(b), center.y + side * sin(b))))
            }
        }
        return lines
    }
}
