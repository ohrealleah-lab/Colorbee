import Testing
@testable import ColorbeeCore

struct DecorationTests {
    private let context = SelectionContext(color2: .white)

    private func screenshot(_ width: Int, _ height: Int) -> (Canvas, History) {
        let canvas = Canvas(size: IntSize(width: width, height: height), colorSpace: Canvas.defaultColorSpace, background: Pixel(r: 40, g: 120, b: 200))
        return (canvas, History(byteBudget: .max))
    }

    @Test func aShadowGrowsTheCanvasAndUndoesExactly() {
        let (canvas, history) = screenshot(20, 10)
        let original = canvas.activeLayer.buffer.contentHash()
        let shadow = DropShadow(offsetX: 4, offsetY: 6, blur: 0, color: .black, opacity: 100)
        #expect(Decorations.dropShadow(shadow, canvas: canvas, history: history, context: context))
        // It only grows where the shadow sticks out: right and below, by the offset.
        #expect(canvas.size == IntSize(width: 24, height: 16))
        let layer = canvas.activeLayer
        #expect(layer.buffer[10, 5] == Pixel(r: 40, g: 120, b: 200))
        #expect(layer.buffer[22, 14] == .black)
        #expect(layer.buffer[21, 2] == .white)
        history.undo(on: canvas)
        #expect(canvas.size == IntSize(width: 20, height: 10))
        #expect(canvas.activeLayer.buffer.contentHash() == original)
        history.redo(on: canvas)
        #expect(canvas.size == IntSize(width: 24, height: 16))
    }

    @Test func aBlurredShadowFadesOut() {
        let (canvas, history) = screenshot(30, 30)
        Decorations.dropShadow(DropShadow(offsetX: 0, offsetY: 10, blur: 4, color: .black, opacity: 100), canvas: canvas, history: history, context: context)
        let layer = canvas.activeLayer
        let near = layer.buffer[15, 31].r, far = layer.buffer[15, 50].r
        #expect(near < far)
        #expect(far > 240)
    }

    @Test func aCutoutCastsAShadowOfItsOwnShapeAndSoftEdgesCastLess() {
        let canvas = Canvas(size: IntSize(width: 40, height: 40), colorSpace: Canvas.defaultColorSpace, background: .clear)
        let history = History(byteBudget: .max)
        let layer = canvas.activeLayer
        layer.buffer.fill(.black, in: IntRect(x: 10, y: 10, width: 5, height: 5))
        layer.buffer.fill(Pixel(r: 0, g: 0, b: 0, a: 128), in: IntRect(x: 25, y: 10, width: 5, height: 5))
        let shadow = DropShadow(offsetX: 0, offsetY: 8, blur: 0, color: Pixel(r: 200, g: 0, b: 0), opacity: 100)
        #expect(Decorations.dropShadow(shadow, canvas: canvas, history: history, context: context))
        #expect(canvas.size == IntSize(width: 40, height: 40))
        // Under the solid square, a full shadow; under the half-transparent one, about half.
        #expect(layer.buffer[12, 20].a == 255 && layer.buffer[12, 20].r == 200)
        #expect(abs(Int(layer.buffer[27, 20].a) - 128) <= 1)
        // Between the squares there's no shadow.
        #expect(layer.buffer[20, 20].a == 0)
    }

    @Test func aBorderFollowsACircleNotItsBox() {
        let canvas = Canvas(size: IntSize(width: 60, height: 60), colorSpace: Canvas.defaultColorSpace, background: .clear)
        let history = History(byteBudget: .max)
        let circle = SelectionMask.ellipse(in: IntRect(x: 20, y: 20, width: 20, height: 20), clippedTo: canvas.bounds)!
        Effects.apply(.solidFill(Pixel(r: 0, g: 200, b: 0)), to: canvas.activeLayer, selection: circle, edit: Edit(name: "Fill", canvas: canvas))
        #expect(Decorations.border(Border(width: 3, color: .black), canvas: canvas, history: history, context: context))
        let layer = canvas.activeLayer
        #expect(layer.buffer[30, 18] == .black)
        #expect(layer.buffer[30, 30] == Pixel(r: 0, g: 200, b: 0))
        // The box's corner is far from the circle, so it gets no border.
        #expect(layer.buffer[19, 19].a == 0)
        #expect(layer.buffer[30, 14].a == 0)
    }

    @Test func aBorderAroundAScreenshotIsARectangleOutside() {
        let (canvas, history) = screenshot(10, 10)
        #expect(Decorations.border(Border(width: 5, color: .black), canvas: canvas, history: history, context: context))
        #expect(canvas.size == IntSize(width: 20, height: 20))
        let layer = canvas.activeLayer
        #expect(layer.buffer[0, 0] == .black && layer.buffer[19, 10] == .black && layer.buffer[4, 4] == .black)
        #expect(layer.buffer[5, 5] == Pixel(r: 40, g: 120, b: 200) && layer.buffer[10, 10] == Pixel(r: 40, g: 120, b: 200))
    }

    @Test func onlyTheSelectedObjectCastsAShadowAndOtherLayersMoveAlong() {
        let canvas = Canvas(size: IntSize(width: 30, height: 30), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: .max)
        LayerActions.add(canvas: canvas, history: history, context: context)
        let top = canvas.activeLayer
        top.buffer.fill(.black, in: IntRect(x: 2, y: 2, width: 4, height: 4))
        top.buffer.fill(.black, in: IntRect(x: 20, y: 20, width: 4, height: 4))
        canvas.selection = .marquee(SelectionMask.rectangle(IntRect(x: 0, y: 0, width: 10, height: 10), clippedTo: canvas.bounds)!)
        let shadow = DropShadow(offsetX: -6, offsetY: 0, blur: 0, color: Pixel(r: 0, g: 0, b: 255), opacity: 100)
        #expect(Decorations.dropShadow(shadow, canvas: canvas, history: history, context: context))
        // It reaches 4 pixels past the left edge (offset 6, starting at x 2), so the canvas grows by 4.
        #expect(canvas.size == IntSize(width: 34, height: 30))
        #expect(canvas.layers[0].buffer[0, 15] == .white)
        #expect(top.buffer[4 + 20 - 6, 21].a == 0)
        #expect(top.buffer[4 + 2 - 6, 3] == Pixel(r: 0, g: 0, b: 255))
        #expect(canvas.selection.bounds == IntRect(x: 4, y: 0, width: 10, height: 10))
    }

    @Test func nothingToDecorateIsRefused() {
        let canvas = Canvas(size: IntSize(width: 10, height: 10), colorSpace: Canvas.defaultColorSpace, background: .clear)
        #expect(!Decorations.border(Border(), canvas: canvas, history: History(byteBudget: .max), context: context))
    }
}
