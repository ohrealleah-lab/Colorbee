import Foundation

/// Edit ▸ Graduated Selection (FR-9.7 item 3), like Lightroom's linear gradient: everything on the start's side of a
/// dragged line is fully selected, fading smoothly to nothing at the end, and beyond the end nothing is. The fade
/// runs across the line, so the selection's edges are straight and at right angles to it.
public struct GraduatedSelection: Sendable, Equatable {
    public var start: Point2D
    public var end: Point2D

    public init(start: Point2D, end: Point2D) {
        self.start = start
        self.end = end
    }

    /// How much a point is selected, 0...1: by how far along the line it lies.
    func amount(at point: Point2D) -> Double {
        let dx = end.x - start.x, dy = end.y - start.y
        let length = dx * dx + dy * dy
        guard length > 0 else { return 0 }
        let along = ((point.x - start.x) * dx + (point.y - start.y) * dy) / length
        return 1 - PhotoAdjustments.smoothstep(0, 1, along)
    }

    /// The selection over a canvas of `bounds`, sampled at pixel centers; nil when nothing is selected.
    public func selection(in bounds: IntRect) -> SelectionMask? {
        guard !bounds.isEmpty else { return nil }
        let width = bounds.width, height = bounds.height
        var values = [UInt8](repeating: 0, count: width * height)
        values.withUnsafeMutableBufferPointer { target in
            ParallelRows.forEach(0..<height) { rows in
                for y in rows {
                    for x in 0..<width {
                        let point = Point2D(x: Double(bounds.minX + x) + 0.5, y: Double(bounds.minY + y) + 0.5)
                        target[y * width + x] = UInt8((amount(at: point) * 255).rounded())
                    }
                }
            }
        }
        return SelectionMask(bounds: bounds, values: values).trimmed()
    }

    /// `point` moved so the line from `anchor` runs across, down or at 45° (Shift while dragging).
    public static func constrained(_ point: Point2D, from anchor: Point2D) -> Point2D {
        let dx = point.x - anchor.x, dy = point.y - anchor.y
        let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
        // Along the snapped direction, as far as the pointer reaches in it.
        let reach = dx * cos(angle) + dy * sin(angle)
        return Point2D(x: anchor.x + reach * cos(angle), y: anchor.y + reach * sin(angle))
    }
}
