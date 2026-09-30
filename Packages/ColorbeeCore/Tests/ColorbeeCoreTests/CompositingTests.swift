import CoreGraphics
import Testing
@testable import ColorbeeCore

struct CompositingTests {
    private let red = Pixel(r: 255, g: 0, b: 0)

    @Test func opaqueSourceReplacesDestination() {
        #expect(Compositing.over(.white, red) == red)
    }

    @Test func transparentSourceLeavesDestination() {
        #expect(Compositing.over(.white, Pixel(r: 255, g: 0, b: 0, a: 0)) == .white)
    }

    @Test func overTransparentDestinationKeepsStraightColor() {
        let translucent = Pixel(r: 200, g: 100, b: 50, a: 128)
        #expect(Compositing.over(.clear, translucent) == translucent)
    }

    @Test func halfAlphaBlendsOverOpaque() {
        let result = Compositing.over(.white, Pixel(r: 0, g: 0, b: 0, a: 128))
        #expect(result == Pixel(r: 127, g: 127, b: 127))
    }

    @Test func coverageScalesSourceAlpha() {
        #expect(Compositing.over(.white, .black, coverage: 0.5) == Pixel(r: 128, g: 128, b: 128))
    }

    @Test func drawCompositesAtOffsetAndClipsToLayer() {
        let canvas = Canvas(size: IntSize(width: 4, height: 4), colorSpace: Canvas.defaultColorSpace, background: .white)
        let image = PixelBuffer(width: 4, height: 4, fill: red)
        let history = History(byteBudget: .max)
        let edit = history.beginEdit("Paste", on: canvas)

        let changed = Compositing.draw(image, at: IntPoint(x: -2, y: -2), onto: canvas.activeLayer, edit: edit)

        #expect(changed == IntRect(x: 0, y: 0, width: 2, height: 2))
        #expect(canvas.activeLayer.buffer[0, 0] == red)
        #expect(canvas.activeLayer.buffer[1, 1] == red)
        #expect(canvas.activeLayer.buffer[2, 2] == .white)
    }

    @Test func flattenAppliesOpacityAndSkipsHiddenLayers() {
        let canvas = Canvas(size: IntSize(width: 2, height: 1), colorSpace: Canvas.defaultColorSpace, background: .white)
        let top = Layer(name: "Top", buffer: PixelBuffer(width: 2, height: 1, fill: .black))
        top.opacity = 0.5
        canvas.insertLayer(top, at: 1)

        #expect(canvas.flattened()[0, 0] == Pixel(r: 128, g: 128, b: 128))

        top.isVisible = false
        #expect(canvas.flattened()[0, 0] == .white)
    }
}
