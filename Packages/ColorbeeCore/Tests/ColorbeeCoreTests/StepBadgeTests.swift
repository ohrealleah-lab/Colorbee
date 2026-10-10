import CoreGraphics
import Testing
@testable import ColorbeeCore

/// Step badges (FR-5.3).
struct StepBadgeTests {
    private let red = Pixel(r: 220, g: 30, b: 30)
    private let space = Canvas.defaultColorSpace
    private let canvas = IntRect(x: 0, y: 0, width: 400, height: 400)

    @Test func labelsCountInNumbersOrLetters() {
        #expect((1...3).map { StepBadge.label(for: $0, style: .numbers) } == ["1", "2", "3"])
        #expect([1, 2, 26, 27, 28, 52, 53, 702, 703].map { StepBadge.label(for: $0, style: .letters) }
            == ["A", "B", "Z", "AA", "AB", "AZ", "BA", "ZZ", "AAA"])
    }

    @Test func aLabelReadsBackAsItsValue() {
        for value in [1, 9, 26, 27, 99, 703] {
            #expect(StepBadge.value(of: StepBadge.label(for: value, style: .letters), style: .letters) == value)
            #expect(StepBadge.value(of: StepBadge.label(for: value, style: .numbers), style: .numbers) == value)
        }
        #expect(StepBadge.value(of: " c ", style: .letters) == 3)
        #expect(StepBadge.value(of: "4", style: .letters) == 4)
        #expect(StepBadge.value(of: "0", style: .numbers) == nil)
        #expect(StepBadge.value(of: "B", style: .numbers) == nil)
        #expect(StepBadge.value(of: "", style: .letters) == nil)
    }

    private func pixel(_ rendered: (pixels: PixelBuffer, origin: IntPoint), _ x: Int, _ y: Int) -> Pixel {
        rendered.pixels[x - rendered.origin.x, y - rendered.origin.y]
    }

    @Test func theCircleIsFilledAndOutlinedWithTheNumberInTheOtherColor() throws {
        let spec = StepBadgeSpec(label: "1", center: Point2D(x: 100, y: 100), diameter: 64, fill: red, ink: .white)
        let rendered = try #require(StepBadge.render(spec, colorSpace: space, clippedTo: canvas))
        // Inside the circle, below the number: the fill.
        #expect(pixel(rendered, 100, 126) == red)
        // On the outline, at the right edge: the ink.
        #expect(pixel(rendered, 130, 100) == .white)
        // Outside the circle: nothing.
        #expect(pixel(rendered, 72, 72).a == 0)
        // The number is drawn in the ink: some white near the middle.
        let middle = (90...110).flatMap { x in (88...112).map { pixel(rendered, x, $0) } }
        #expect(middle.contains(.white))
        #expect(spec.contains(Point2D(x: 120, y: 100)) && !spec.contains(Point2D(x: 140, y: 140)))
    }

    @Test func aDraggedBadgePointsAnArrowInItsFillColor() throws {
        var spec = StepBadgeSpec(label: "2", center: Point2D(x: 100, y: 100), diameter: 40, fill: red, ink: .white,
                                 arrowTip: Point2D(x: 300, y: 100))
        let rendered = try #require(StepBadge.render(spec, colorSpace: space, clippedTo: canvas))
        #expect(pixel(rendered, 200, 100) == red)
        #expect(pixel(rendered, 296, 100).a > 0)
        #expect(pixel(rendered, 200, 120).a == 0)
        // A tip still inside the circle draws no arrow.
        spec.arrowTip = Point2D(x: 110, y: 100)
        let plain = try #require(StepBadge.render(spec, colorSpace: space, clippedTo: canvas))
        #expect(pixel(plain, 128, 100).a == 0)
    }

    @Test func aBadgeOffTheCanvasDrawsNothing() {
        let spec = StepBadgeSpec(label: "1", center: Point2D(x: -200, y: -200), diameter: 32, fill: red, ink: .white)
        #expect(StepBadge.render(spec, colorSpace: space, clippedTo: canvas) == nil)
    }
}
