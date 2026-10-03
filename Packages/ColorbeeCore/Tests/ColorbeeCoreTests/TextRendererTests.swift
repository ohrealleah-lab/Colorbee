import CoreGraphics
import Testing
@testable import ColorbeeCore

struct TextRendererTests {
    private let red = Pixel(r: 255, g: 0, b: 0)
    private let bounds = IntRect(x: 0, y: 0, width: 600, height: 400)

    private func spec(_ text: String, wrap: Double? = nil, background: Pixel? = nil) -> TextSpec {
        TextSpec(text: text, origin: Point2D(x: 20, y: 30), wrapWidth: wrap, fontFamily: "Helvetica", fontSize: 40, color: red, background: background)
    }

    private func coloredCount(_ buffer: PixelBuffer, matching: (Pixel) -> Bool) -> Int {
        var count = 0
        for y in 0..<buffer.height {
            for x in 0..<buffer.width where matching(buffer[x, y]) { count += 1 }
        }
        return count
    }

    @Test func drawsGlyphsInsideTheBox() throws {
        let rendered = try #require(TextRenderer.render(spec("Hello"), colorSpace: Canvas.defaultColorSpace, clippedTo: bounds))
        #expect(rendered.origin == IntPoint(x: 20, y: 30))
        #expect(coloredCount(rendered.pixels) { $0.a > 200 && $0.r == 255 } > 100)
        #expect(rendered.pixels[0, 0].a == 0)
    }

    @Test func opaqueBackgroundFillsTheWholeBox() throws {
        let rendered = try #require(TextRenderer.render(spec("Hi", background: .white), colorSpace: Canvas.defaultColorSpace, clippedTo: bounds))
        let pixels = rendered.pixels
        #expect(coloredCount(pixels) { $0.a < 255 } == 0)
        #expect(pixels[0, 0] == .white)
    }

    @Test func wrappingMakesTheBoxTaller() {
        let text = "The quick brown fox jumps over the lazy dog"
        let unwrapped = TextRenderer.box(for: spec(text))
        let wrapped = TextRenderer.box(for: spec(text, wrap: 150))
        #expect(wrapped.width <= 151)
        #expect(wrapped.height > unwrapped.height * 2)
    }

    @Test func emptyTextDrawsNothing() {
        #expect(TextRenderer.render(spec(""), colorSpace: Canvas.defaultColorSpace, clippedTo: bounds) == nil)
    }

    @Test func boldIsWiderThanRegular() {
        var bold = spec("Wide words")
        bold.bold = true
        #expect(TextRenderer.box(for: bold).width > TextRenderer.box(for: spec("Wide words")).width)
    }

    @Test func strikethroughAddsInk() throws {
        var struck = spec("Strike")
        struck.strikethrough = true
        let plain = try #require(TextRenderer.render(spec("Strike"), colorSpace: Canvas.defaultColorSpace, clippedTo: bounds))
        let lined = try #require(TextRenderer.render(struck, colorSpace: Canvas.defaultColorSpace, clippedTo: bounds))
        #expect(coloredCount(lined.pixels) { $0.a > 128 } > coloredCount(plain.pixels) { $0.a > 128 })
    }

    /// Italic letters lean past their advance; the last one must not be cut off (Leah's report).
    @Test(arguments: [nil, 200.0])
    func italicTextIsNotClipped(wrapWidth: Double?) {
        var spec = TextSpec(text: "ffff", origin: Point2D(x: 10, y: 10), wrapWidth: wrapWidth, fontFamily: "Helvetica Neue", fontSize: 72, color: .black)
        spec.italic = true
        guard let rendered = TextRenderer.render(spec, colorSpace: Canvas.defaultColorSpace, clippedTo: IntRect(x: 0, y: 0, width: 600, height: 300)) else {
            Issue.record("Nothing rendered")
            return
        }
        let lastColumn = rendered.pixels.width - 1
        #expect((0..<rendered.pixels.height).allSatisfy { rendered.pixels[lastColumn, $0].a == 0 })
        #expect(TextRenderer.box(for: spec).width == rendered.pixels.width)
    }
}
