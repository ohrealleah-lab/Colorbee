import Testing
@testable import ColorbeeCore

/// Soft edges next to see-through pixels keep their color: pixels are stored with straight alpha, so a transparent
/// pixel's hidden black mustn't be mixed in (review O, findings 3, 9 and 11).
struct SeeThroughEdgeTests {
    private let yellow = Pixel(r: 250, g: 210, b: 20)

    /// An empty (transparent) layer on a canvas, ready to paint on.
    private func emptyLayer() -> (Canvas, History) {
        let canvas = Canvas(size: IntSize(width: 60, height: 40), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: .max)
        LayerActions.add(canvas: canvas, history: history, context: SelectionContext(color2: .white))
        return (canvas, history)
    }

    /// Every pixel that shows at all still has `color`'s red, green and blue, give or take rounding.
    private func keepsColor(_ buffer: PixelBuffer, _ color: Pixel, tolerance: Int = 2) -> Bool {
        for y in 0..<buffer.height {
            for x in 0..<buffer.width where buffer[x, y].a > 8 {
                let p = buffer[x, y]
                if abs(Int(p.r) - Int(color.r)) > tolerance || abs(Int(p.g) - Int(color.g)) > tolerance
                    || abs(Int(p.b) - Int(color.b)) > tolerance { return false }
            }
        }
        return true
    }

    @Test func mixingWithTransparencyKeepsTheColor() {
        #expect(Compositing.lerp(.clear, .white, 0.5) == Pixel(r: 255, g: 255, b: 255, a: 128))
        // Equally opaque pixels mix exactly as before.
        #expect(Compositing.lerp(Pixel(r: 0, g: 100, b: 200), Pixel(r: 100, g: 200, b: 0), 0.5) == Pixel(r: 50, g: 150, b: 100))
    }

    @Test func aFeatheredFillOnAnEmptyLayerHasNoDarkEdge() throws {
        let (canvas, history) = emptyLayer()
        let box = try #require(SelectionMask.rectangle(IntRect(x: 15, y: 10, width: 30, height: 20), clippedTo: canvas.bounds))
        let soft = try #require(box.feathered(radius: 6, clippedTo: canvas.bounds))
        let edit = history.beginEdit("Fill", on: canvas)
        FloodFill.fill(layer: canvas.activeLayer, at: IntPoint(x: 30, y: 20), with: yellow, tolerance: 0, selection: soft, edit: edit)
        #expect(keepsColor(canvas.activeLayer.buffer, yellow))
    }

    @Test func aSoftCloneOntoAnEmptyLayerHasNoDarkRing() {
        let (canvas, history) = emptyLayer()
        let source = PixelBuffer(width: 60, height: 40)
        source.fill(yellow, in: source.bounds)
        let edit = history.beginEdit("Clone", on: canvas)
        let stroke = RetouchStroke(diameter: 16, hardness: 0, strength: 1, kind: .clone(offset: IntPoint(x: 0, y: 0), source: source),
                                   layer: canvas.activeLayer, edit: edit)
        stroke.move(to: Point2D(x: 20, y: 20))
        stroke.move(to: Point2D(x: 40, y: 20))
        history.commit(edit)
        #expect(canvas.activeLayer.buffer[30, 20].a > 200)
        #expect(keepsColor(canvas.activeLayer.buffer, yellow))
    }

    @Test func theBlurBrushSoftensAnEdgeWithoutDarkeningIt() {
        let (canvas, history) = emptyLayer()
        canvas.activeLayer.buffer.fill(yellow, in: IntRect(x: 0, y: 15, width: 60, height: 10))
        let edit = history.beginEdit("Blur", on: canvas)
        let stroke = RetouchStroke(diameter: 20, hardness: 1, strength: 1, kind: .adjust(.blur), layer: canvas.activeLayer, edit: edit)
        stroke.move(to: Point2D(x: 10, y: 15))
        stroke.move(to: Point2D(x: 50, y: 15))
        history.commit(edit)
        let edge = canvas.activeLayer.buffer[30, 15]
        #expect(edge.a > 0 && edge.a < 255, "the edge softens")
        #expect(keepsColor(canvas.activeLayer.buffer, yellow))
    }

    @Test func smudgingInFromTheEdgeKeepsAnOpaqueLayerOpaque() {
        let canvas = Canvas(size: IntSize(width: 60, height: 40), colorSpace: Canvas.defaultColorSpace, background: yellow)
        let history = History(byteBudget: .max)
        let edit = history.beginEdit("Smudge", on: canvas)
        let stroke = SmudgeStroke(diameter: 20, hardness: 0.5, strength: 1, layer: canvas.activeLayer, edit: edit)
        stroke.move(to: Point2D(x: 0, y: 20), pressure: 1)
        stroke.move(to: Point2D(x: 40, y: 20), pressure: 1)
        history.commit(edit)
        let buffer = canvas.activeLayer.buffer
        for y in 0..<buffer.height { for x in 0..<buffer.width { #expect(buffer[x, y].a == 255) } }
        #expect(keepsColor(buffer, yellow))
    }

    @Test func redEyeFollowsASoftSelection() {
        let red = Pixel(r: 200, g: 30, b: 30)
        let canvas = Canvas(size: IntSize(width: 4, height: 4), colorSpace: Canvas.defaultColorSpace, background: red)
        let history = History(byteBudget: .max)
        let full = SelectionMask(bounds: IntRect(x: 0, y: 0, width: 1, height: 1), values: [255])
        let half = SelectionMask(bounds: IntRect(x: 1, y: 0, width: 1, height: 1), values: [128])
        let edit = history.beginEdit("Remove Red-Eye", on: canvas)
        RedEye.fix(in: full, layer: canvas.activeLayer, edit: edit)
        RedEye.fix(in: half, layer: canvas.activeLayer, edit: edit)
        let fixed = Int(canvas.activeLayer.buffer[0, 0].r), partly = Int(canvas.activeLayer.buffer[1, 0].r)
        #expect(fixed < 60)
        #expect(abs(partly - (200 + fixed) / 2) <= 2)
    }
}
