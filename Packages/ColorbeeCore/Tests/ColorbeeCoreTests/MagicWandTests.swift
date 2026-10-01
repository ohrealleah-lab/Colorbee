import Testing
@testable import ColorbeeCore

struct MagicWandTests {
    private let red = Pixel(r: 255, g: 0, b: 0)

    /// White with two separate red squares.
    private func makeBuffer() -> PixelBuffer {
        let buffer = PixelBuffer(width: 60, height: 40, fill: .white)
        buffer.fill(red, in: IntRect(x: 5, y: 5, width: 10, height: 10))
        buffer.fill(red, in: IntRect(x: 40, y: 20, width: 10, height: 10))
        return buffer
    }

    @Test func contiguousSelectsOnlyTheConnectedArea() throws {
        let mask = try #require(SelectionMask.magicWand(in: makeBuffer(), at: IntPoint(x: 7, y: 7), tolerance: 0, contiguous: true))
        #expect(mask.bounds == IntRect(x: 5, y: 5, width: 10, height: 10))
        #expect(!mask.contains(IntPoint(x: 45, y: 25)))
    }

    @Test func nonContiguousSelectsEveryMatch() throws {
        let mask = try #require(SelectionMask.magicWand(in: makeBuffer(), at: IntPoint(x: 7, y: 7), tolerance: 0, contiguous: false))
        #expect(mask.contains(IntPoint(x: 7, y: 7)))
        #expect(mask.contains(IntPoint(x: 45, y: 25)))
        #expect(!mask.contains(IntPoint(x: 30, y: 30)))
        #expect(mask.connectedRegions().count == 2)
    }

    @Test func toleranceWidensTheMatch() throws {
        let buffer = makeBuffer()
        buffer.fill(Pixel(r: 240, g: 10, b: 10), in: IntRect(x: 15, y: 5, width: 5, height: 10))
        let exact = try #require(SelectionMask.magicWand(in: buffer, at: IntPoint(x: 7, y: 7), tolerance: 0, contiguous: true))
        let loose = try #require(SelectionMask.magicWand(in: buffer, at: IntPoint(x: 7, y: 7), tolerance: 0.1, contiguous: true))
        #expect(exact.bounds.width == 10)
        #expect(loose.bounds.width == 15)
    }

    @Test func solidFillRedactsEachSelectedPixel() {
        let canvas = Canvas(size: IntSize(width: 60, height: 40), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: .max)
        let selection = SelectionMask.ellipse(in: IntRect(x: 0, y: 0, width: 20, height: 20), clippedTo: canvas.bounds)
        let edit = history.beginEdit("Solid Fill", on: canvas)
        Effects.apply(.solidFill(.black), to: canvas.activeLayer, selection: selection, edit: edit)
        #expect(canvas.activeLayer.buffer[10, 10] == .black)
        #expect(canvas.activeLayer.buffer[0, 0] == .white)
        #expect(history.commit(edit))
    }
}
