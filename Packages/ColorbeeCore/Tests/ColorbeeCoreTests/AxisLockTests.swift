import Testing
@testable import ColorbeeCore

struct AxisLockTests {
    @Test func staysAtStartUntilThePointerMovesAPixel() {
        var lock = AxisLock(start: Point2D(x: 10, y: 10))
        #expect(lock.constrain(Point2D(x: 10.5, y: 10.4)) == Point2D(x: 10, y: 10))
        #expect(lock.axis == nil)
    }

    @Test func firstClearMovementChoosesTheAxis() {
        var horizontal = AxisLock(start: Point2D(x: 10, y: 10))
        #expect(horizontal.constrain(Point2D(x: 14, y: 12)) == Point2D(x: 14, y: 10))
        #expect(horizontal.axis == .horizontal)

        var vertical = AxisLock(start: Point2D(x: 10, y: 10))
        #expect(vertical.constrain(Point2D(x: 9, y: 4)) == Point2D(x: 10, y: 4))
        #expect(vertical.axis == .vertical)
    }

    /// Moving back and forth across the diagonal must not flip to the other axis mid-drag.
    @Test func axisHoldsForTheRestOfTheDrag() {
        var lock = AxisLock(start: Point2D(x: 0, y: 0))
        _ = lock.constrain(Point2D(x: 5, y: 1))
        let path = [Point2D(x: 2, y: 30), Point2D(x: -8, y: -40), Point2D(x: 20, y: 3)]
        #expect(path.map { lock.constrain($0) } == [Point2D(x: 2, y: 0), Point2D(x: -8, y: 0), Point2D(x: 20, y: 0)])
        #expect(lock.axis == .horizontal)
    }
}
