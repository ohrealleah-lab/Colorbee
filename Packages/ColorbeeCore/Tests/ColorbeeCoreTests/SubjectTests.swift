import Testing
@testable import ColorbeeCore

struct SubjectTests {
    private let context = SelectionContext(color2: .white)

    /// Two subjects on a 10 × 4 image: a hard-edged one on the left and a soft one on the right.
    private func scan() -> SubjectScan {
        var left = [UInt8](repeating: 0, count: 40), right = [UInt8](repeating: 0, count: 40)
        for y in 0..<4 {
            for x in 0..<3 { left[y * 10 + x] = 255 }
            right[y * 10 + 6] = 120
            for x in 7..<10 { right[y * 10 + x] = 255 }
        }
        return SubjectScan(size: IntSize(width: 10, height: 4), masks: [left, right])
    }

    @Test func clickingPicksTheSubjectUnderThePointer() {
        let scan = scan()
        #expect(scan.subject(at: IntPoint(x: 1, y: 1)) == 0)
        #expect(scan.subject(at: IntPoint(x: 8, y: 2)) == 1)
        #expect(scan.subject(at: IntPoint(x: 4, y: 2)) == nil)
        // The soft edge is under half, so it doesn't count as a click on the subject.
        #expect(scan.subject(at: IntPoint(x: 6, y: 0)) == nil)
        #expect(scan.mask(for: [0])[8] == 0 && scan.mask()[8] == 255)
    }

    @Test func removingTheBackgroundKeepsSoftEdgesAndUndoes() {
        let canvas = Canvas(size: IntSize(width: 10, height: 4), colorSpace: Canvas.defaultColorSpace, background: Pixel(r: 50, g: 60, b: 70))
        let history = History(byteBudget: .max)
        let original = canvas.activeLayer.buffer.contentHash()
        #expect(SubjectActions.removeBackground(scan().mask(), canvas: canvas, history: history, context: context))
        let buffer = canvas.activeLayer.buffer
        #expect(buffer[1, 1].a == 255 && buffer[4, 1].a == 0 && buffer[6, 1].a == 120)
        #expect(buffer[6, 1].r == 50)
        history.undo(on: canvas)
        #expect(canvas.activeLayer.buffer.contentHash() == original)
    }

    @Test func liftingPutsTheSubjectOnANewLayerAndLeavesTheOriginal() {
        let canvas = Canvas(size: IntSize(width: 10, height: 4), colorSpace: Canvas.defaultColorSpace, background: .black)
        let history = History(byteBudget: .max)
        let original = canvas.layers[0].buffer.contentHash()
        #expect(SubjectActions.liftToNewLayer(scan().mask(for: [1]), canvas: canvas, history: history, context: context))
        #expect(canvas.layers.count == 2 && canvas.activeLayerIndex == 1 && canvas.activeLayer.name == "Subject")
        #expect(canvas.layers[0].buffer.contentHash() == original)
        #expect(canvas.activeLayer.buffer[8, 0].a == 255 && canvas.activeLayer.buffer[1, 0].a == 0)
        history.undo(on: canvas)
        #expect(canvas.layers.count == 1)
    }

    @Test func selectingCutsTheSoftEdgeAtHalf() {
        let canvas = Canvas(size: IntSize(width: 10, height: 4), colorSpace: Canvas.defaultColorSpace, background: .white)
        SubjectActions.select(scan().mask(for: [1]), canvas: canvas, history: History(byteBudget: .max), context: context)
        #expect(canvas.selection.bounds == IntRect(x: 7, y: 0, width: 3, height: 4))
    }

    @Test func aLockedLayerRefuses() {
        let canvas = Canvas(size: IntSize(width: 10, height: 4), colorSpace: Canvas.defaultColorSpace, background: .white)
        canvas.activeLayer.isLocked = true
        #expect(!SubjectActions.removeBackground(scan().mask(), canvas: canvas, history: History(byteBudget: .max), context: context))
    }
}
