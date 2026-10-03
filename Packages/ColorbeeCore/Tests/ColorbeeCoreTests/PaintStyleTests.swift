import CoreGraphics
import Testing
@testable import ColorbeeCore

struct PaintStyleTests {
    private let space = Canvas.defaultColorSpace
    private let bounds = IntRect(x: 0, y: 0, width: 100, height: 100)
    private let red = Pixel(r: 255, g: 0, b: 0)
    private let blue = Pixel(r: 0, g: 0, b: 255)

    private func rectangle(outline: PaintStyle? = .solid, fill: PaintStyle? = nil, width: Double = 6) -> ShapeSpec {
        ShapeSpec(
            kind: .rectangle, start: Point2D(x: 10, y: 10), end: Point2D(x: 90, y: 90), lineWidth: width,
            outline: outline == nil ? nil : red, fill: fill == nil ? nil : blue,
            outlineStyle: outline ?? .solid, fillStyle: fill ?? .solid
        )
    }

    /// The rendered pixel at an image position, or clear if it's outside what was drawn.
    private func pixel(_ rendered: (pixels: PixelBuffer, origin: IntPoint)?, _ x: Int, _ y: Int) -> Pixel {
        guard let rendered else { return .clear }
        let local = IntPoint(x: x - rendered.origin.x, y: y - rendered.origin.y)
        guard rendered.pixels.bounds.contains(local) else { return .clear }
        return rendered.pixels[local.x, local.y]
    }

    @Test func flattenTurnsARectangleIntoOneClosedLoop() {
        let lines = ShapeRenderer.flatten(CGPath(rect: CGRect(x: 0, y: 0, width: 10, height: 5), transform: nil))
        #expect(lines.count == 1)
        #expect(lines[0].first == lines[0].last)
        #expect(lines[0].count == 5)
    }

    @Test func flattenSplitsCurvesIntoShortPieces() {
        let lines = ShapeRenderer.flatten(CGPath(ellipseIn: CGRect(x: 0, y: 0, width: 40, height: 40), transform: nil))
        #expect(lines.count == 1)
        #expect(lines[0].count > 20)
        for point in lines[0] {
            let distance = ((point.x - 20) * (point.x - 20) + (point.y - 20) * (point.y - 20)).squareRoot()
            #expect(abs(distance - 20) < 0.5)
        }
    }

    @Test func crayonOutlineHasGrainAndLeavesTheMiddleEmpty() {
        let rendered = ShapeRenderer.render(rectangle(outline: .crayon, width: 10), colorSpace: space, clippedTo: bounds)
        let edge = (20..<80).map { pixel(rendered, $0, 15).a }
        #expect(edge.contains(0))
        #expect(edge.filter { $0 > 0 }.count > edge.count / 3)
        #expect(pixel(rendered, 50, 50).a == 0)
    }

    @Test func markerFillIsHalfStrength() {
        let rendered = ShapeRenderer.render(rectangle(outline: nil, fill: .marker), colorSpace: space, clippedTo: bounds)
        #expect(pixel(rendered, 50, 50) == Pixel(r: 0, g: 0, b: 255, a: 128))
    }

    @Test func watercolorFillPoolsAtTheEdges() {
        let rendered = ShapeRenderer.render(rectangle(outline: nil, fill: .watercolor), colorSpace: space, clippedTo: bounds)
        #expect(pixel(rendered, 12, 50).a > pixel(rendered, 50, 50).a + 30)
        #expect(pixel(rendered, 50, 50).a > 0)
    }

    @Test func solidOutlineSitsOnTopOfATexturedFill() {
        let rendered = ShapeRenderer.render(rectangle(outline: .solid, fill: .oil), colorSpace: space, clippedTo: bounds)
        #expect(pixel(rendered, 50, 12) == red)
        let inside = pixel(rendered, 50, 50)
        #expect(inside.b == 255 && inside.a > 0 && inside.a < 255)
    }

    @Test func texturedArrowKeepsASolidHead() {
        let arrow = ShapeSpec(
            kind: .arrow, start: Point2D(x: 10, y: 50), end: Point2D(x: 90, y: 50), lineWidth: 4,
            outline: red, fill: nil, outlineStyle: .crayon
        )
        let rendered = ShapeRenderer.render(arrow, colorSpace: space, clippedTo: bounds)
        #expect(pixel(rendered, 82, 50) == red)
        let shaft = (15..<60).map { pixel(rendered, $0, 50).a }
        #expect(shaft.contains(0) && shaft.contains { $0 > 0 })
    }

    @Test(arguments: PaintStyle.allCases)
    func everyStyleDrawsTheSameEachTime(style: PaintStyle) {
        let shape = rectangle(outline: style, fill: style)
        let first = ShapeRenderer.render(shape, colorSpace: space, clippedTo: bounds)
        let second = ShapeRenderer.render(shape, colorSpace: space, clippedTo: bounds)
        #expect(first?.pixels.contentHash() == second?.pixels.contentHash())
        #expect(first?.pixels.contentHash() != nil)
    }
}
