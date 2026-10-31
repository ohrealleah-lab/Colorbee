import Testing
@testable import ColorbeeCore

/// Shift's straight line and Smoothing's pulled string (stage 31).
struct StrokePathTests {
    @Test func withoutSmoothingTheLineGoesWhereThePointerIs() {
        var path = StrokePath(start: Point2D(x: 5, y: 5))
        #expect(path.next(Point2D(x: 9, y: 7), constrain: false) == Point2D(x: 9, y: 7))
        #expect(path.catchUp == nil)
    }

    @Test func smallWobblesWithinTheReachNeverMoveTheLine() {
        var path = StrokePath(start: Point2D(x: 10, y: 10), reach: 8)
        for wobble in [Point2D(x: 13, y: 12), Point2D(x: 7, y: 14), Point2D(x: 16, y: 9)] {
            #expect(path.next(wobble, constrain: false) == Point2D(x: 10, y: 10))
        }
    }

    @Test func pastTheReachTheLineFollowsOnTheString() {
        var path = StrokePath(start: Point2D(x: 0, y: 0), reach: 8)
        // 20 to the right: the line goes 12, staying 8 behind.
        #expect(path.next(Point2D(x: 20, y: 0), constrain: false) == Point2D(x: 12, y: 0))
        // Straight down from there: it follows along the string's direction.
        let pen = path.next(Point2D(x: 20, y: 30), constrain: false)
        let left = ((20 - pen.x) * (20 - pen.x) + (30 - pen.y) * (30 - pen.y)).squareRoot()
        #expect(abs(left - 8) < 1e-9)
        // On release it catches up to the pointer.
        #expect(path.catchUp == Point2D(x: 20, y: 30))
    }

    @Test func shiftKeepsTheLineStraightEvenWithSmoothing() {
        var path = StrokePath(start: Point2D(x: 10, y: 10), reach: 8)
        #expect(path.next(Point2D(x: 30, y: 12), constrain: true) == Point2D(x: 30, y: 10))
        #expect(path.next(Point2D(x: 50, y: 7), constrain: true) == Point2D(x: 50, y: 10))
        #expect(path.catchUp == nil)
    }

    @Test func aSmoothedPathIsSteadierThanAShakyOne() {
        // A hand moving right while shaking up and down by 3 pixels.
        let shaky = (0..<200).map { Point2D(x: Double($0), y: 50 + ($0 % 2 == 0 ? 3 : -3)) }
        var path = StrokePath(start: shaky[0], reach: 10)
        let smoothed = shaky.map { path.next($0, constrain: false) }
        let spread = smoothed.dropFirst(20).map(\.y)
        #expect(spread.max()! - spread.min()! < 1)
    }
}
