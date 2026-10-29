import Testing
@testable import ColorbeeCore

/// Layer ▸ Align and Distribute (stage 24): exact boxes and moves.
struct LayerAlignTests {
    private let context = SelectionContext(color2: .white)

    /// White paper with one layer per box, each filled red.
    private func layers(_ boxes: [IntRect]) -> (Canvas, History, [Layer]) {
        let canvas = Canvas(size: IntSize(width: 100, height: 60), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: .max)
        var made: [Layer] = []
        for box in boxes {
            LayerActions.add(canvas: canvas, history: history, context: context)
            canvas.activeLayer.buffer.fill(Pixel(r: 255, g: 0, b: 0), in: box)
            made.append(canvas.activeLayer)
        }
        return (canvas, history, made)
    }

    @Test func visibleBoundsIgnoreClearPixels() {
        let buffer = PixelBuffer(width: 10, height: 10)
        #expect(buffer.visibleBounds == nil)
        buffer.row(2)[3] = Pixel(r: 0, g: 0, b: 0, a: 1)
        buffer.row(7)[8] = .black
        #expect(buffer.visibleBounds == IntRect(x: 3, y: 2, width: 6, height: 6))
    }

    @Test func alignMovesEachBoxToTheReference() {
        let (_, _, made) = layers([IntRect(x: 10, y: 5, width: 10, height: 10), IntRect(x: 40, y: 20, width: 20, height: 6)])
        let reference = IntRect(x: 10, y: 5, width: 50, height: 21)
        #expect(LayerAlign.offsets(aligning: made, to: .left, reference: reference) == [made[0].id: IntPoint(x: 0, y: 0), made[1].id: IntPoint(x: -30, y: 0)])
        #expect(LayerAlign.offsets(aligning: made, to: .right, reference: reference)[made[0].id] == IntPoint(x: 40, y: 0))
        #expect(LayerAlign.offsets(aligning: made, to: .centers, reference: reference)[made[1].id] == IntPoint(x: -15, y: 0))
        #expect(LayerAlign.offsets(aligning: made, to: .bottom, reference: reference)[made[0].id] == IntPoint(x: 0, y: 11))
        #expect(LayerAlign.offsets(aligning: made, to: .middle, reference: reference)[made[1].id] == IntPoint(x: 0, y: -7))
    }

    @Test func distributeMakesEqualGapsKeepingTheEnds() {
        let (_, _, made) = layers([IntRect(x: 0, y: 0, width: 10, height: 5), IntRect(x: 15, y: 0, width: 20, height: 5),
                                   IntRect(x: 80, y: 0, width: 20, height: 5)])
        // 100 across, 50 of boxes: two gaps of 25.
        let offsets = LayerAlign.offsets(distributing: made, .horizontally)
        #expect(offsets[made[0].id] == IntPoint(x: 0, y: 0) && offsets[made[1].id] == IntPoint(x: 20, y: 0) && offsets[made[2].id] == IntPoint(x: 0, y: 0))
        #expect(LayerAlign.offsets(distributing: Array(made.prefix(2)), .horizontally).isEmpty)
    }

    @Test func movingIsOneStepThatUndoesExactly() {
        let (canvas, history, made) = layers([IntRect(x: 10, y: 5, width: 10, height: 10), IntRect(x: 40, y: 20, width: 20, height: 6)])
        let before = canvas.flattened().contentHash()
        let steps = history.undoCount
        let result = LayerAlign.move(LayerAlign.offsets(aligning: made, to: .left, reference: IntRect(x: 10, y: 5, width: 50, height: 21)),
                                     named: "Align Left", canvas: canvas, history: history, context: context)
        #expect(result == nil && history.undoCount == steps + 1 && history.undoActionName == "Align Left")
        #expect(made[1].buffer.visibleBounds == IntRect(x: 10, y: 20, width: 20, height: 6))
        history.undo(on: canvas)
        #expect(canvas.flattened().contentHash() == before)
    }

    @Test func pixelsThatWouldLeaveTheCanvasStopIt() {
        let (canvas, history, made) = layers([IntRect(x: 0, y: 0, width: 80, height: 10)])
        let offsets = LayerAlign.offsets(aligning: made, to: .left, reference: IntRect(x: 50, y: 0, width: 10, height: 10))
        #expect(LayerAlign.move(offsets, named: "Align Left", canvas: canvas, history: history, context: context) == .offCanvas("Layer 1"))
        #expect(made[0].buffer.visibleBounds == IntRect(x: 0, y: 0, width: 80, height: 10))
    }
}
