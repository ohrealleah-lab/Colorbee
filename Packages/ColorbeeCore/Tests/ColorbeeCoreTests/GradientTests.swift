import Testing
@testable import ColorbeeCore

struct GradientTests {
    private let red = Pixel(r: 255, g: 0, b: 0)
    private let blue = Pixel(r: 0, g: 0, b: 255)

    private func draw(_ mode: GradientMode, from: Point2D, to: Point2D, end: Pixel? = nil, selection: SelectionMask? = nil, background: Pixel = .white) -> PixelBuffer {
        let canvas = Canvas(size: IntSize(width: 100, height: 100), colorSpace: Canvas.defaultColorSpace, background: background)
        let edit = History(byteBudget: .max).beginEdit("Gradient", on: canvas)
        Gradients.draw(mode, from: from, to: to, startColor: red, endColor: end ?? blue, onto: canvas.activeLayer, selection: selection, edit: edit)
        return canvas.activeLayer.buffer
    }

    @Test func linearRunsFromStartColorToEndColor() {
        let buffer = draw(.linear, from: Point2D(x: 10, y: 50), to: Point2D(x: 90, y: 50))
        #expect(buffer[2, 50] == red)
        #expect(buffer[95, 50] == blue)
        let middle = buffer[50, 50]
        #expect(middle.r > 100 && middle.r < 160 && middle.b > 100 && middle.b < 160)
        #expect(buffer[50, 0] == buffer[50, 99])
    }

    @Test func radialIsStartColorAtTheCenter() {
        let buffer = draw(.radial, from: Point2D(x: 50, y: 50), to: Point2D(x: 90, y: 50))
        #expect(buffer[50, 50].r > 240)
        #expect(buffer[50, 5] == blue)
        #expect(buffer[30, 50] == buffer[69, 50])
    }

    @Test func reflectedMirrorsAroundTheStart() {
        let buffer = draw(.reflected, from: Point2D(x: 50, y: 50), to: Point2D(x: 80, y: 50))
        #expect(buffer[40, 50] == buffer[59, 50])
        #expect(buffer[5, 50] == blue)
    }

    @Test func diamondAndConicalCoverTheCanvas() {
        let diamond = draw(.diamond, from: Point2D(x: 50, y: 50), to: Point2D(x: 80, y: 50))
        #expect(diamond[50, 50].r > 240 && diamond[0, 0] == blue)
        let conical = draw(.conical, from: Point2D(x: 50, y: 50), to: Point2D(x: 80, y: 50))
        #expect(conical[90, 50] != conical[10, 50])
    }

    @Test func fadingToTransparentKeepsTheColor() {
        let buffer = draw(.linear, from: Point2D(x: 0, y: 0), to: Point2D(x: 100, y: 0), end: Pixel(r: 0, g: 0, b: 255, a: 0), background: .clear)
        let pixel = buffer[50, 10]
        #expect(pixel.r == 255 && pixel.b == 0)
        #expect(pixel.a > 100 && pixel.a < 155)
        #expect(buffer[99, 10].a < 10)
    }

    @Test func staysInsideTheSelection() {
        let selection = SelectionMask.rectangle(IntRect(x: 0, y: 0, width: 50, height: 100), clippedTo: IntRect(x: 0, y: 0, width: 100, height: 100))
        let buffer = draw(.linear, from: Point2D(x: 0, y: 0), to: Point2D(x: 100, y: 0), selection: selection)
        #expect(buffer[60, 50] == .white)
        #expect(buffer[10, 50] != .white)
    }
}
