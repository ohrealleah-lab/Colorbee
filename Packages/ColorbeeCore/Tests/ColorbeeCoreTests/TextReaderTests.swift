import CoreGraphics
import Foundation
import Testing
@testable import ColorbeeCore

/// Copy Text (FR-10.4), read back from text drawn with Colorbee's own renderer.
struct TextReaderTests {
    private func image(_ lines: [(String, x: Int, y: Int)], size: IntSize, transparent: Bool = false) throws -> CGImage {
        let canvas = Canvas(size: size, colorSpace: Canvas.defaultColorSpace, background: transparent ? .clear : .white)
        let edit = History(byteBudget: .max).beginEdit("Text", on: canvas)
        for line in lines {
            let spec = TextSpec(text: line.0, origin: Point2D(x: Double(line.x), y: Double(line.y)), fontFamily: "Helvetica", fontSize: 30, color: .black)
            if let rendered = TextRenderer.render(spec, colorSpace: canvas.colorSpace, clippedTo: canvas.bounds) {
                Compositing.draw(rendered.pixels, at: rendered.origin, onto: canvas.activeLayer, edit: edit)
            }
        }
        return try ImageCodec.makeCGImage(canvas.flattened(), colorSpace: canvas.colorSpace)
    }

    @Test func readsLinesTopToBottom() async throws {
        let text = try await TextReader.read(try image([("Bees make honey", 40, 40), ("Wasps do not", 40, 200)],
                                                       size: IntSize(width: 900, height: 320)))
        let first = try #require(text.range(of: "Bees make honey"))
        let second = try #require(text.range(of: "Wasps do not"))
        #expect(first.lowerBound < second.lowerBound)
        #expect(TextReader.wordCount(text) == 6)
    }

    /// Side-by-side columns of running text are read left column first. (Short separate lines side by side read
    /// as a table, row by row.)
    @Test func readsTheLeftColumnFirst() async throws {
        let left = ["Bees visit flowers to", "collect nectar and pollen.", "They carry pollen home", "on their back legs."]
        let right = ["Honey is made from", "nectar that bees store", "and dry in wax cells", "until it thickens."]
        let lines = [("A Two Column Page", x: 40, y: 30)]
            + left.enumerated().map { ($0.element, x: 40, y: 120 + $0.offset * 36) }
            + right.enumerated().map { ($0.element, x: 680, y: 120 + $0.offset * 36) }
        let text = try await TextReader.read(try image(lines, size: IntSize(width: 1300, height: 700)))
        let leftEnd = try #require(text.range(of: "back legs"))
        let rightStart = try #require(text.range(of: "Honey"))
        #expect(leftEnd.lowerBound < rightStart.lowerBound)
        // A paragraph's wrapped lines are joined.
        #expect(text.contains("Bees visit flowers to collect nectar and pollen."))
    }

    @Test func darkTextOnTransparencyIsRead() async throws {
        let text = try await TextReader.read(try image([("Clear background", 40, 40)], size: IntSize(width: 700, height: 140), transparent: true))
        #expect(text.contains("Clear background"))
    }

    @Test func anImageWithoutTextReadsAsNothing() async throws {
        let canvas = Canvas(size: IntSize(width: 400, height: 300), colorSpace: Canvas.defaultColorSpace, background: .white)
        canvas.activeLayer.buffer.fill(Pixel(r: 40, g: 120, b: 200), in: IntRect(x: 100, y: 80, width: 150, height: 120))
        let text = try await TextReader.read(try ImageCodec.makeCGImage(canvas.flattened(), colorSpace: canvas.colorSpace))
        #expect(text.isEmpty)
        #expect(TextReader.wordCount(text) == 0)
    }
}
