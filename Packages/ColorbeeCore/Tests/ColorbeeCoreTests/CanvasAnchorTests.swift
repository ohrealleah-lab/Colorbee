import Testing
@testable import ColorbeeCore

/// Canvas Properties' anchor (FR-2.2, §23 2026-10-28): where the picture stays when the canvas changes size.
struct CanvasAnchorTests {
    private let paper = Pixel(r: 200, g: 200, b: 200), blue = Pixel(r: 0, g: 0, b: 255), mark = Pixel(r: 255, g: 0, b: 0)
    private let context = SelectionContext(color2: Pixel(r: 0, g: 0, b: 255))

    /// A 4 × 4 picture with a red mark at its top-left pixel.
    private func canvas() -> (Canvas, History) {
        let canvas = Canvas(size: IntSize(width: 4, height: 4), colorSpace: Canvas.defaultColorSpace, background: paper)
        canvas.activeLayer.buffer.row(0)[0] = mark
        return (canvas, History(byteBudget: .max))
    }

    /// Where the mark ended up.
    private func markPosition(_ canvas: Canvas) -> IntPoint? {
        let buffer = canvas.layers[0].buffer
        for y in 0..<buffer.height { for x in 0..<buffer.width where buffer[x, y] == mark { return IntPoint(x: x, y: y) } }
        return nil
    }

    @Test func growingPutsTheNewSpaceAwayFromTheAnchor() {
        // Growing from 4 × 4 to 8 × 6: 4 spare across, 2 down.
        let expected: [CanvasAnchor: IntPoint] = [
            .topLeft: IntPoint(x: 0, y: 0), .top: IntPoint(x: 2, y: 0), .topRight: IntPoint(x: 4, y: 0),
            .left: IntPoint(x: 0, y: 1), .center: IntPoint(x: 2, y: 1), .right: IntPoint(x: 4, y: 1),
            .bottomLeft: IntPoint(x: 0, y: 2), .bottom: IntPoint(x: 2, y: 2), .bottomRight: IntPoint(x: 4, y: 2),
        ]
        for anchor in CanvasAnchor.allCases {
            let (canvas, history) = canvas()
            #expect(ImageActions.resizeCanvas(to: IntSize(width: 8, height: 6), anchor: anchor, canvas: canvas, history: history, context: context))
            #expect(markPosition(canvas) == expected[anchor], "\(anchor.title)")
            // All the new space, 8 × 6 less the 4 × 4 picture, is Color 2 on the background.
            let buffer = canvas.layers[0].buffer
            #expect((0..<6).reduce(0) { count, y in count + (0..<8).filter { buffer[$0, y] == blue }.count } == 32)
        }
    }

    @Test func centerOnAnOddDifferencePutsTheExtraPixelRightAndBelow() {
        let (canvas, history) = canvas()
        ImageActions.resizeCanvas(to: IntSize(width: 7, height: 9), anchor: .center, canvas: canvas, history: history, context: context)
        // 3 spare across: 1 on the left, 2 on the right. 5 down: 2 above, 3 below.
        #expect(markPosition(canvas) == IntPoint(x: 1, y: 2))
        #expect(canvas.layers[0].buffer[0, 2] == blue && canvas.layers[0].buffer[5, 2] == blue && canvas.layers[0].buffer[1, 6] == blue)
    }

    @Test func shrinkingCutsTheSidesAwayFromTheAnchor() {
        let picture = Canvas(size: IntSize(width: 6, height: 6), colorSpace: Canvas.defaultColorSpace, background: paper)
        for y in 0..<6 { for x in 0..<6 { picture.activeLayer.buffer.row(y)[x] = Pixel(r: UInt8(x * 10), g: UInt8(y * 10), b: 0) } }
        let history = History(byteBudget: .max)
        // Center, 6 to 3: one cut on the left and two on the right (the extra one on the right); the same down.
        ImageActions.resizeCanvas(to: IntSize(width: 3, height: 3), anchor: .center, canvas: picture, history: history, context: context)
        #expect(picture.layers[0].buffer[0, 0] == Pixel(r: 10, g: 10, b: 0))
        #expect(picture.layers[0].buffer[2, 2] == Pixel(r: 30, g: 30, b: 0))
        history.undo(on: picture)
        ImageActions.resizeCanvas(to: IntSize(width: 4, height: 6), anchor: .bottomRight, canvas: picture, history: history, context: context)
        #expect(picture.layers[0].buffer[0, 0] == Pixel(r: 20, g: 0, b: 0))
        history.undo(on: picture)
        #expect(picture.size == IntSize(width: 6, height: 6) && picture.layers[0].buffer[0, 0] == Pixel(r: 0, g: 0, b: 0))
    }

    @Test func everyLayerAndTheSelectionMoveTogether() throws {
        let (canvas, history) = canvas()
        LayerActions.add(canvas: canvas, history: history, context: context)
        canvas.activeLayer.buffer.row(3)[3] = mark
        let mask = try #require(SelectionMask.rectangle(IntRect(x: 0, y: 0, width: 2, height: 2), clippedTo: canvas.bounds))
        canvas.selection = .marquee(mask)
        ImageActions.resizeCanvas(to: IntSize(width: 10, height: 10), anchor: .center, canvas: canvas, history: history, context: context)
        #expect(canvas.layers[1].buffer[6, 6] == mark && canvas.layers[1].buffer[9, 9] == .clear)
        #expect(canvas.selection.marquee?.bounds == IntRect(x: 3, y: 3, width: 2, height: 2))
        history.undo(on: canvas)
        #expect(canvas.selection.marquee?.bounds == IntRect(x: 0, y: 0, width: 2, height: 2))
        // A smaller canvas keeps only the part of the selection still on it, or none.
        ImageActions.resizeCanvas(to: IntSize(width: 2, height: 2), anchor: .bottomRight, canvas: canvas, history: history, context: context)
        #expect(canvas.selection.marquee == nil)
    }
}
