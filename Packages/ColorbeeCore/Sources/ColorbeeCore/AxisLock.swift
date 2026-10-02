/// Shift-constrained drawing: keeps a stroke on one horizontal or vertical line through its start.
/// The axis is chosen by the first clear movement and then held for the rest of the drag, so moving
/// back and forth slides along the same line instead of flipping between axes (as in MS Paint).
public struct AxisLock: Sendable {
    public enum Axis: Sendable {
        case horizontal
        case vertical
    }

    public let start: Point2D
    public private(set) var axis: Axis?

    public init(start: Point2D) {
        self.start = start
    }

    /// Projects `point` onto the locked axis, choosing the axis if it isn't chosen yet.
    /// Until the pointer has moved a full pixel the axis stays open and the stroke stays at its start.
    public mutating func constrain(_ point: Point2D) -> Point2D {
        let dx = abs(point.x - start.x)
        let dy = abs(point.y - start.y)
        if axis == nil {
            guard max(dx, dy) >= 1 else { return start }
            axis = dx >= dy ? .horizontal : .vertical
        }
        return axis == .horizontal ? Point2D(x: point.x, y: start.y) : Point2D(x: start.x, y: point.y)
    }
}
