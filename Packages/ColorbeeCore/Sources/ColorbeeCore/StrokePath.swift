/// Where a brush stroke goes as the pointer moves: Shift's straight line (`AxisLock`), and Smoothing (FR-4, stage 31)
/// as a pulled string. The line stays put until the pointer is `reach` away, then follows it on a string of that
/// length, so small wobbles never reach the picture. On release the line catches up to the pointer (Q31.3).
public struct StrokePath: Sendable {
    private var lock: AxisLock
    /// How far the pointer pulls ahead before the line follows, in image pixels; 0 is off.
    public let reach: Double
    /// Where the line has got to.
    public private(set) var pen: Point2D
    private var pointer: Point2D

    public init(start: Point2D, reach: Double = 0) {
        lock = AxisLock(start: start)
        self.reach = max(0, reach)
        pen = start
        pointer = start
    }

    /// Where the stroke goes for this pointer position. With `constrain` (Shift) the line is straight, and smoothing
    /// picks up from there.
    public mutating func next(_ point: Point2D, constrain: Bool) -> Point2D {
        if constrain {
            pen = lock.constrain(point)
            pointer = pen
            return pen
        }
        pointer = point
        let dx = point.x - pen.x, dy = point.y - pen.y
        let distance = (dx * dx + dy * dy).squareRoot()
        if distance > reach {
            let pull = (distance - reach) / distance
            pen = Point2D(x: pen.x + dx * pull, y: pen.y + dy * pull)
        }
        return pen
    }

    /// Where the line goes on release to end at the pointer; nil when it's already there.
    public var catchUp: Point2D? { pen == pointer ? nil : pointer }
}
