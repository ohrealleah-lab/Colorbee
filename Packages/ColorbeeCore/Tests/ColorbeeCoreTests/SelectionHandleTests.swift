import Testing
@testable import ColorbeeCore

struct SelectionHandleTests {
    private let rect = IntRect(x: 10, y: 10, width: 40, height: 20)

    @Test func cornerStretchesFreely() {
        let resized = SelectionHandle.bottomRight.resize(rect, by: Point2D(x: 10, y: 30), keepProportions: false)
        #expect(resized == IntRect(x: 10, y: 10, width: 50, height: 50))
    }

    @Test func topLeftMovesTheOrigin() {
        let resized = SelectionHandle.topLeft.resize(rect, by: Point2D(x: -5, y: 4), keepProportions: false)
        #expect(resized == IntRect(x: 5, y: 14, width: 45, height: 16))
    }

    @Test func edgeHandleOnlyChangesOneSide() {
        let resized = SelectionHandle.right.resize(rect, by: Point2D(x: 20, y: 99), keepProportions: false)
        #expect(resized == IntRect(x: 10, y: 10, width: 60, height: 20))
    }

    @Test func shiftKeepsTheAspectRatio() {
        let resized = SelectionHandle.bottomRight.resize(rect, by: Point2D(x: 40, y: 0), keepProportions: true)
        #expect(resized == IntRect(x: 10, y: 10, width: 80, height: 40))
        let fromTopLeft = SelectionHandle.topLeft.resize(rect, by: Point2D(x: 20, y: 0), keepProportions: true)
        #expect(fromTopLeft == IntRect(x: 30, y: 20, width: 20, height: 10))
    }

    @Test func proportionalEdgeGrowsAroundTheCenter() {
        let resized = SelectionHandle.right.resize(rect, by: Point2D(x: 40, y: 0), keepProportions: true)
        #expect(resized == IntRect(x: 10, y: 0, width: 80, height: 40))
    }

    @Test func neverFlipsOrVanishes() {
        let resized = SelectionHandle.right.resize(rect, by: Point2D(x: -500, y: 0), keepProportions: false)
        #expect(resized == IntRect(x: 10, y: 10, width: 1, height: 20))
        let squashed = SelectionHandle.top.resize(rect, by: Point2D(x: 0, y: 500), keepProportions: false)
        #expect(squashed.height == 1 && squashed.maxY == 30)
    }

    @Test func resizingAFloatingSelectionScalesFromTheOriginal() {
        let canvas = Canvas(size: IntSize(width: 100, height: 100), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: .max)
        let context = SelectionContext(color2: .white, resampling: .smooth)
        let checker = PixelBuffer(width: 8, height: 8)
        for y in 0..<8 { for x in 0..<8 { checker[x, y] = (x + y) % 2 == 0 ? .black : .white } }
        SelectionActions.paste(checker, at: IntPoint(x: 0, y: 0), canvas: canvas, history: history, context: context)

        let edit = SelectionActions.beginMove(duplicate: false, named: "Resize Selection", canvas: canvas, history: history, context: context)!
        SelectionActions.resize(to: IntRect(x: 0, y: 0, width: 2, height: 2), canvas: canvas)
        SelectionActions.resize(to: IntRect(x: 0, y: 0, width: 8, height: 8), canvas: canvas)
        history.commit(edit)
        SelectionActions.placeFloating(canvas: canvas, history: history, context: context)

        for y in 0..<8 {
            for x in 0..<8 {
                #expect(canvas.activeLayer.buffer[x, y] == checker[x, y])
            }
        }
    }

    @Test func marqueeOutlineGrowsWithoutTouchingPixels() {
        let canvas = Canvas(size: IntSize(width: 100, height: 100), colorSpace: Canvas.defaultColorSpace, background: .white)
        canvas.selection = .marquee(SelectionMask.rectangle(IntRect(x: 10, y: 10, width: 10, height: 10), clippedTo: canvas.bounds)!)
        let before = canvas.activeLayer.buffer.contentHash()
        SelectionActions.resizeMarquee(byWidth: 5, height: -3, canvas: canvas)
        #expect(canvas.selection.marquee?.bounds == IntRect(x: 10, y: 10, width: 15, height: 7))
        #expect(canvas.activeLayer.buffer.contentHash() == before)
    }
}
