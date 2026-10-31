import ColorbeeCore
import Testing
@testable import Colorbee

/// Which colors a shape is drawn in (FR-5.1; Leah, 2026-10-31): a shape with one part draws it in Color 1.
@MainActor
struct ShapeColorTests {
    private let pink = Pixel(r: 240, g: 50, b: 130), blue = Pixel(r: 30, g: 60, b: 220)

    /// A placed rectangle from (10, 10) to (40, 40): its edge pixel and its middle pixel.
    private func rectangle(outline: PaintStyle?, fill: PaintStyle?, secondary: Bool = false) -> (edge: Pixel, middle: Pixel) {
        let editor = makeEditor()
        editor.color1 = pink
        editor.color2 = blue
        editor.selectTool(.shape)
        editor.shapeKind = .rectangle
        editor.shapeLineWidth = 3
        editor.shapeOutline = outline
        editor.shapeFill = fill
        editor.beginShapeDrag(at: pt(10, 10), viewPoint: editor.viewport.viewPoint(fromImage: pt(10, 10)), secondary: secondary, clickCount: 1)
        editor.continueShapeDrag(to: pt(40, 40), shiftDown: false)
        editor.endShapeDrag()
        editor.commitPendingShape()
        let image = editor.canvas.flattened()
        return (image[11, 25], image[25, 25])
    }

    @Test func aFillOnItsOwnUsesColor1() {
        #expect(rectangle(outline: nil, fill: .solid).middle == pink)
        // Right-drag swaps: Color 2.
        #expect(rectangle(outline: nil, fill: .solid, secondary: true).middle == blue)
    }

    @Test func underAnOutlineTheFillIsColor2AsInPaint() {
        let shape = rectangle(outline: .solid, fill: .solid)
        #expect(shape.edge == pink && shape.middle == blue)
        let swapped = rectangle(outline: .solid, fill: .solid, secondary: true)
        #expect(swapped.edge == blue && swapped.middle == pink)
    }

    @Test func anOutlineOnItsOwnIsColor1() {
        let shape = rectangle(outline: .solid, fill: nil)
        #expect(shape.edge == pink && shape.middle == paper)
    }
}
