import Foundation
import Testing
@testable import ColorbeeCore

/// Curved text (FR-6.4, stage 35): one smooth arc, every line nested around the same centre.
struct CurvedTextTests {
    private let ink = Pixel(r: 20, g: 20, b: 200)

    private func spec(_ text: String = "MMMMMMMMMMMM", curve: Double, background: Pixel? = nil) -> TextSpec {
        var spec = TextSpec(text: text, origin: Point2D(x: 20, y: 30), fontFamily: "Helvetica Neue", fontSize: 24, color: ink, background: background)
        spec.curve = curve
        return spec
    }

    private func render(_ spec: TextSpec) throws -> (pixels: PixelBuffer, origin: IntPoint) {
        try #require(TextRenderer.render(spec, colorSpace: Canvas.defaultColorSpace, clippedTo: IntRect(x: 0, y: 0, width: 600, height: 600)))
    }

    /// The topmost row with ink in columns `range` of the rendered pixels.
    private func topInk(_ pixels: PixelBuffer, columns range: Range<Int>) -> Int? {
        (0..<pixels.height).first { y in range.contains { pixels.row(y)[$0].a > 128 } }
    }

    @Test func straightTextIsUnchanged() throws {
        let straight = spec(curve: 0)
        #expect(TextRenderer.box(for: straight) == TextRenderer.layoutBox(for: straight))
        var almost = straight
        almost.curve = 0.2
        #expect(try render(almost).pixels.contentHash() == render(straight).pixels.contentHash())
    }

    @Test func aSmileRaisesTheEndsAndAFrownLowersThem() throws {
        for curve in [100.0, 40, -40, -100] {
            let (pixels, _) = try render(spec(curve: curve))
            let quarter = pixels.width / 6
            let left = try #require(topInk(pixels, columns: 0..<quarter))
            let middle = try #require(topInk(pixels, columns: pixels.width / 2 - quarter / 2..<pixels.width / 2 + quarter / 2))
            let right = try #require(topInk(pixels, columns: pixels.width - quarter..<pixels.width))
            if curve > 0 {
                #expect(left < middle && right < middle, "curve \(curve)")
            } else {
                #expect(left > middle && right > middle, "curve \(curve)")
            }
            // Balanced around the middle, to within a couple of pixels of anti-aliasing.
            #expect(abs(left - right) <= 3, "curve \(curve)")
        }
    }

    @Test func aStrongerCurveBendsFurther() throws {
        let gentle = TextRenderer.box(for: spec(curve: -30)), strong = TextRenderer.box(for: spec(curve: -100))
        let straight = TextRenderer.box(for: spec(curve: 0))
        #expect(straight.height < gentle.height && gentle.height < strong.height)
        // The words keep their spacing along the arc, so a half circle is narrower than the straight line.
        #expect(strong.width < straight.width)
    }

    @Test func everyLineCurvesAroundTheSameCentre() throws {
        let (pixels, _) = try render(spec("MMMMMMMMMM\nMMMMMMMMMM", curve: -100))
        // The middle columns have ink in two bands, one for each line (a few columns, as the middle may fall
        // between letters).
        let columns = pixels.width / 2 - 6..<pixels.width / 2 + 6
        var bands = 0, inInk = false
        for y in 0..<pixels.height {
            let dark = columns.contains { pixels.row(y)[$0].a > 128 }
            if dark && !inInk { bands += 1 }
            inInk = dark
        }
        #expect(bands == 2)
    }

    @Test func anOpaqueBackgroundIsACurvedBand() throws {
        let (pixels, _) = try render(spec(curve: -100, background: .white))
        // A frown's band leaves the top corners of its bounds empty, unlike a rectangle.
        #expect(pixels.row(1)[1].a == 0 && pixels.row(1)[pixels.width - 2].a == 0)
        // The top of the arc is covered.
        #expect(pixels.row(3)[pixels.width / 2].a == 255)
    }

    @Test func underlineAndStrikethroughFollowTheCurve() throws {
        let plain = spec(curve: -60)
        var lined = plain
        lined.underline = true
        lined.strikethrough = true
        let a = try render(plain).pixels, b = try render(lined).pixels
        #expect(a.contentHash() != b.contentHash())
        #expect(TextRenderer.box(for: lined).contains(TextRenderer.box(for: plain)))
    }

    @Test func theCurveStaysInRange() {
        var bent = spec(curve: 0)
        bent.curve = 400
        #expect(bent.curve == 100)
        bent.curve = -.infinity
        #expect(bent.curve == 0)
    }

    @Test func aCurvedTextLayerKeepsItsCurveInAProject() throws {
        let canvas = Canvas(size: IntSize(width: 300, height: 200), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: .max)
        LayerActions.addText(spec(curve: -75), canvas: canvas, history: history, context: SelectionContext(color2: .white))
        let reopened = try ProjectFile.decode(try ProjectFile.encode(canvas))
        #expect(reopened.layers[1].text?.spec.curve == -75)
        // Its pixels are the curved text drawn.
        let layer = reopened.layers[1]
        let text = try #require(layer.text)
        #expect(layer.buffer.contentHash() == text.drawn(size: canvas.size, colorSpace: canvas.colorSpace).contentHash())
    }

    @Test func resizingTheImageKeepsTheCurve() {
        let text = TextLayer(spec: spec(curve: 50)).fitted(scale: 2, dx: 0, dy: 0)
        #expect(text.spec.curve == 50 && text.spec.fontSize == 48)
    }
}
