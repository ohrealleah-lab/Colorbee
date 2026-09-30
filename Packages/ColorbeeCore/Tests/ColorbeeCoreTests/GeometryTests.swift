import Testing
@testable import ColorbeeCore

struct GeometryTests {
    @Test func intersectsOverlappingRects() {
        let a = IntRect(x: 0, y: 0, width: 10, height: 10)
        let b = IntRect(x: 5, y: 5, width: 10, height: 10)
        #expect(a.intersection(b) == IntRect(x: 5, y: 5, width: 5, height: 5))
    }

    @Test func disjointRectsHaveEmptyIntersection() {
        let a = IntRect(x: 0, y: 0, width: 4, height: 4)
        let b = IntRect(x: 4, y: 0, width: 4, height: 4)
        #expect(a.intersection(b).isEmpty)
    }

    @Test func unionIgnoresEmptyRects() {
        let a = IntRect(x: 2, y: 3, width: 4, height: 5)
        #expect(IntRect.zero.union(a) == a)
        #expect(a.union(.zero) == a)
        #expect(a.union(IntRect(x: 10, y: 0, width: 1, height: 1)) == IntRect(x: 2, y: 0, width: 9, height: 8))
    }

    @Test func enclosingRectRoundsOutward() {
        let rect = IntRect(enclosingMinX: 1.5, minY: -0.5, maxX: 3.2, maxY: 2.0)
        #expect(rect == IntRect(x: 1, y: -1, width: 3, height: 3))
    }
}
