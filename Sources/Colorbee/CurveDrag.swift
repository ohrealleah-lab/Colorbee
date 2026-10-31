import ColorbeeCore
import CoreGraphics
import Foundation

/// The Curves graph's points as the mouse edits them (FR-9.5), apart from the view so it can be tested: where a
/// point sits in a graph of `size`, which point a press grabs, and what one drag does to the points.
struct CurveDrag {
    /// The plot area is inset on every side, so the end points' handles aren't cut off at the corners.
    static let inset: CGFloat = 5

    let size: CGSize
    /// The point being dragged; -1 once it's been dragged off and removed.
    private(set) var dragging: Int?
    /// Where the dragged point was when it was grabbed; it moves by the drag, so a click doesn't shift it.
    private var grabbed: Curves.Point?

    init(size: CGSize) {
        self.size = size
    }

    func location(of point: Curves.Point) -> CGPoint {
        let width = size.width - 2 * Self.inset, height = size.height - 2 * Self.inset
        return CGPoint(x: Self.inset + point.x / 255 * width, y: Self.inset + (1 - point.y / 255) * height)
    }

    func value(at location: CGPoint) -> Curves.Point {
        let width = Double(size.width - 2 * Self.inset), height = Double(size.height - 2 * Self.inset)
        let x: Double = min(max(Double(location.x - Self.inset) / width, 0), 1) * 255
        let y: Double = min(max(1 - Double(location.y - Self.inset) / height, 0), 1) * 255
        return Curves.Point(x: x.rounded(), y: y.rounded())
    }

    func nearest(to location: CGPoint, in points: [Curves.Point]) -> Int? {
        let distances = points.indices.map { index -> (Int, Double) in
            let center = self.location(of: points[index])
            return (index, hypot(center.x - location.x, center.y - location.y))
        }
        return distances.filter { $0.1 <= 10 }.min { $0.1 < $1.1 }?.0
    }

    /// The points after the drag that began at `start` has moved by `translation` to `location`, or nil when it
    /// changes nothing more (its point was dragged off).
    mutating func moved(_ points: [Curves.Point], start: CGPoint, location: CGPoint, translation: CGSize) -> [Curves.Point]? {
        var points = points
        if dragging == nil {
            let startValue = value(at: start)
            // A click at an existing point's x (an end point's, say) grabs that point rather than adding a
            // second one there (review D, finding 3).
            if let index = nearest(to: start, in: points) ?? points.firstIndex(where: { $0.x == startValue.x }) {
                dragging = index
            } else {
                points.append(startValue)
                points.sort { $0.x < $1.x }
                dragging = points.firstIndex(of: startValue)
            }
            grabbed = dragging.flatMap { points.indices.contains($0) ? points[$0] : nil }
        }
        guard let index = dragging, points.indices.contains(index) else { return nil }
        // Dragging a middle point well outside the graph removes it.
        let outside = location.x < -20 || location.x > size.width + 20 || location.y < -20 || location.y > size.height + 20
        if outside, index != 0, index != points.count - 1 {
            points.remove(at: index)
            dragging = -1
        } else {
            let origin = grabbed.map { self.location(of: $0) } ?? start
            var point = value(at: CGPoint(x: origin.x + translation.width, y: origin.y + translation.height))
            // A point stays between its neighbors, so the curve stays a function of x.
            let low = index > 0 ? points[index - 1].x + 1 : 0
            let high = index < points.count - 1 ? points[index + 1].x - 1 : 255
            point.x = min(max(point.x, low), high)
            points[index] = point
        }
        return points
    }

    /// The points without the one double-clicked at `location`, or nil when there's none there or it's an end point.
    func removing(near location: CGPoint, from points: [Curves.Point]) -> [Curves.Point]? {
        guard let index = nearest(to: location, in: points), index != 0, index != points.count - 1 else { return nil }
        var points = points
        points.remove(at: index)
        return points
    }
}
