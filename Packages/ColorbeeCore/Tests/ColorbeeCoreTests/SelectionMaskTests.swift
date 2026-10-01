import Testing
@testable import ColorbeeCore

struct SelectionMaskTests {
    private let canvas = IntRect(x: 0, y: 0, width: 100, height: 100)

    private func selectedCount(_ mask: SelectionMask?) -> Int {
        mask?.values.filter { $0 > 0 }.count ?? 0
    }

    @Test func rectangleIsClippedToTheCanvas() throws {
        let mask = try #require(SelectionMask.rectangle(IntRect(x: -10, y: 90, width: 30, height: 30), clippedTo: canvas))
        #expect(mask.bounds == IntRect(x: 0, y: 90, width: 20, height: 10))
        #expect(mask.contains(IntPoint(x: 0, y: 99)))
        #expect(!mask.contains(IntPoint(x: 20, y: 95)))
    }

    @Test func rectangleOutsideTheCanvasSelectsNothing() {
        #expect(SelectionMask.rectangle(IntRect(x: 200, y: 0, width: 5, height: 5), clippedTo: canvas) == nil)
    }

    @Test func ellipseSelectsTheCenterButNotTheCorners() throws {
        let mask = try #require(SelectionMask.ellipse(in: IntRect(x: 10, y: 10, width: 20, height: 20), clippedTo: canvas))
        #expect(mask.contains(IntPoint(x: 20, y: 20)))
        #expect(!mask.contains(IntPoint(x: 10, y: 10)))
        #expect(!mask.contains(IntPoint(x: 29, y: 29)))
        #expect(mask.bounds == IntRect(x: 10, y: 10, width: 20, height: 20))
    }

    @Test func squarePolygonMatchesTheRectangle() throws {
        let points = [Point2D(x: 10, y: 10), Point2D(x: 20, y: 10), Point2D(x: 20, y: 20), Point2D(x: 10, y: 20)]
        let polygon = try #require(SelectionMask.polygon(points, clippedTo: canvas))
        #expect(polygon.bounds == IntRect(x: 10, y: 10, width: 10, height: 10))
        #expect(selectedCount(polygon) == 100)
    }

    @Test func trianglePolygonSelectsItsInsideOnly() throws {
        let points = [Point2D(x: 0, y: 0), Point2D(x: 40, y: 0), Point2D(x: 0, y: 40)]
        let triangle = try #require(SelectionMask.polygon(points, clippedTo: canvas))
        #expect(triangle.contains(IntPoint(x: 5, y: 5)))
        #expect(!triangle.contains(IntPoint(x: 30, y: 30)))
    }

    @Test func combineModes() {
        let left = SelectionMask.rectangle(IntRect(x: 0, y: 0, width: 10, height: 10), clippedTo: canvas)
        let right = SelectionMask.rectangle(IntRect(x: 5, y: 0, width: 10, height: 10), clippedTo: canvas)

        #expect(selectedCount(SelectionMask.combine(left, with: right, mode: .replace)) == 100)
        #expect(selectedCount(SelectionMask.combine(left, with: right, mode: .add)) == 150)
        #expect(selectedCount(SelectionMask.combine(left, with: right, mode: .subtract)) == 50)
        #expect(SelectionMask.combine(left, with: right, mode: .subtract)?.bounds == IntRect(x: 0, y: 0, width: 5, height: 10))
        #expect(selectedCount(SelectionMask.combine(left, with: right, mode: .intersect)) == 50)
        #expect(SelectionMask.combine(left, with: left, mode: .subtract) == nil)
        #expect(SelectionMask.combine(nil, with: right, mode: .add)?.bounds == right?.bounds)
    }

    @Test func invertSelectsEverythingElse() {
        let mask = SelectionMask.rectangle(IntRect(x: 0, y: 0, width: 10, height: 10), clippedTo: canvas)
        let inverted = mask?.inverted(in: canvas)
        #expect(selectedCount(inverted) == 100 * 100 - 100)
        #expect(inverted?.contains(IntPoint(x: 5, y: 5)) == false)
    }

    @Test func stretchingScalesTheShape() throws {
        let mask = try #require(SelectionMask.rectangle(IntRect(x: 0, y: 0, width: 4, height: 4), clippedTo: canvas))
        let stretched = try #require(mask.stretched(to: IntRect(x: 10, y: 10, width: 8, height: 2)))
        #expect(stretched.bounds == IntRect(x: 10, y: 10, width: 8, height: 2))
        #expect(selectedCount(stretched) == 16)
    }

    @Test func everyMaskHasItsOwnRevision() {
        let a = SelectionMask.rectangle(IntRect(x: 0, y: 0, width: 4, height: 4), clippedTo: canvas)
        let b = SelectionMask.rectangle(IntRect(x: 0, y: 0, width: 4, height: 4), clippedTo: canvas)
        #expect(a?.revision != b?.revision)
    }
}

struct SelectionRegionTests {
    @Test func separateAreasBecomeSeparateRegions() {
        let canvas = IntRect(x: 0, y: 0, width: 50, height: 50)
        let a = SelectionMask.rectangle(IntRect(x: 0, y: 0, width: 5, height: 5), clippedTo: canvas)
        let b = SelectionMask.rectangle(IntRect(x: 10, y: 10, width: 3, height: 3), clippedTo: canvas)
        let touching = SelectionMask.rectangle(IntRect(x: 13, y: 13, width: 2, height: 2), clippedTo: canvas)
        let combined = SelectionMask.combine(SelectionMask.combine(a, with: b, mode: .add), with: touching, mode: .add)
        let regions = combined?.connectedRegions() ?? []
        #expect(regions.count == 2)
        #expect(Set(regions.map(\.bounds)) == [IntRect(x: 0, y: 0, width: 5, height: 5), IntRect(x: 10, y: 10, width: 5, height: 5)])
    }
}
