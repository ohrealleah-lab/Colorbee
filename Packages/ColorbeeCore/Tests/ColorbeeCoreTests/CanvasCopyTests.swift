import Testing
@testable import ColorbeeCore

struct CanvasCopyTests {
    @Test func copyMatchesAndStaysIndependent() {
        let canvas = Canvas(size: IntSize(width: 6, height: 4), colorSpace: Canvas.defaultColorSpace, background: .white)
        let top = Layer(name: "Top", buffer: PixelBuffer(width: 6, height: 4))
        top.buffer.fill(Pixel(r: 200, g: 0, b: 0, a: 128), in: IntRect(x: 1, y: 1, width: 3, height: 2))
        top.blendMode = .multiply
        top.opacity = 0.5
        canvas.insertLayer(top, at: 1)
        canvas.selection = .marquee(SelectionMask(bounds: IntRect(x: 0, y: 0, width: 2, height: 2), values: [255, 255, 255, 255]))

        let copy = canvas.copy()
        #expect(copy.layers.map(\.id) == canvas.layers.map(\.id))
        #expect(copy.layers[1].blendMode == .multiply && copy.layers[1].opacity == 0.5)
        #expect(copy.selection.bounds == canvas.selection.bounds)
        #expect(copy.flattened().contentHash() == canvas.flattened().contentHash())

        let before = copy.flattened().contentHash()
        canvas.layers[1].buffer.fill(.black)
        #expect(copy.flattened().contentHash() == before)
    }
}
