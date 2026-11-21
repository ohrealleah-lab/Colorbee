import Testing
@testable import ColorbeeCore

/// Esc on floating pixels takes back everything since they were lifted or pasted (stage 34b; §23, 2026-11-20).
struct CancelFloatingTests {
    private let red = Pixel(r: 255, g: 0, b: 0)
    private let blue = Pixel(r: 0, g: 0, b: 255)
    private let context = SelectionContext(color2: .white)

    /// A 40×40 white canvas with a red 10×10 square at (10, 10).
    private func makeCanvas() -> (Canvas, History) {
        let canvas = Canvas(size: IntSize(width: 40, height: 40), colorSpace: Canvas.defaultColorSpace, background: .white)
        canvas.activeLayer.buffer.fill(red, in: IntRect(x: 10, y: 10, width: 10, height: 10))
        return (canvas, History(byteBudget: .max))
    }

    private func select(_ rect: IntRect, _ canvas: Canvas, _ history: History) {
        SelectionActions.select(.rectangle(rect, clippedTo: canvas.bounds), mode: .replace, canvas: canvas, history: history, context: context)
    }

    private func move(_ canvas: Canvas, _ history: History, by dx: Int, _ dy: Int, smear: Bool = false, duplicate: Bool = false) {
        let edit = SelectionActions.beginMove(duplicate: duplicate, canvas: canvas, history: history, context: context)!
        let at = canvas.selection.floating!.destination
        SelectionActions.move(to: IntPoint(x: at.minX + dx, y: at.minY + dy), smear: smear, edit: edit, canvas: canvas, context: context)
        history.commit(edit)
    }

    @Test func aMovedPasteDisappearsWithNothingToRedo() {
        let (canvas, history) = makeCanvas()
        let before = canvas.activeLayer.buffer.contentHash()
        let steps = history.undoCount
        let piece = PixelBuffer(width: 4, height: 4)
        piece.fill(blue, in: piece.bounds)
        SelectionActions.paste(piece, at: IntPoint(x: 2, y: 2), canvas: canvas, history: history, context: context)
        move(canvas, history, by: 5, 5)
        SelectionActions.nudge(dx: 1, dy: 0, canvas: canvas, history: history, context: context)

        #expect(SelectionActions.cancelFloating(canvas: canvas, history: history))
        #expect(canvas.selection.isEmpty && canvas.activeLayer.buffer.contentHash() == before)
        #expect(history.undoCount == steps && !history.canRedo)
    }

    @Test func liftedPixelsGoBackAfterAMoveANudgeAResizeAndASmear() {
        let (canvas, history) = makeCanvas()
        let before = canvas.activeLayer.buffer.contentHash()
        select(IntRect(x: 10, y: 10, width: 10, height: 10), canvas, history)
        let selected = canvas.selection
        let steps = history.undoCount
        move(canvas, history, by: 8, 3)
        SelectionActions.nudge(dx: 0, dy: 2, canvas: canvas, history: history, context: context)
        let edit = history.beginEdit("Resize Selection", on: canvas)
        edit.recordsSelectionChange = true
        SelectionActions.resize(to: IntRect(x: 20, y: 18, width: 15, height: 6), canvas: canvas)
        history.commit(edit)
        move(canvas, history, by: -3, 4, smear: true)
        #expect(canvas.activeLayer.buffer.contentHash() != before)

        #expect(SelectionActions.cancelFloating(canvas: canvas, history: history))
        #expect(canvas.activeLayer.buffer.contentHash() == before)
        // Back to the marquee that was there before the lift, not one step further.
        #expect(canvas.selection.isSame(as: selected) && history.undoCount == steps && !history.canRedo)
    }

    @Test func aPieceAlreadyPlacedStays() {
        let (canvas, history) = makeCanvas()
        let first = PixelBuffer(width: 3, height: 3)
        first.fill(blue, in: first.bounds)
        SelectionActions.paste(first, at: IntPoint(x: 30, y: 30), canvas: canvas, history: history, context: context)
        // A second paste places the first.
        SelectionActions.paste(first, at: IntPoint(x: 0, y: 0), canvas: canvas, history: history, context: context)
        #expect(SelectionActions.cancelFloating(canvas: canvas, history: history))
        #expect(canvas.activeLayer.buffer.row(31)[31] == blue && canvas.activeLayer.buffer.row(1)[1] == .white)
    }

    @Test func aRotatedLiftGoesBackToo() {
        let (canvas, history) = makeCanvas()
        canvas.activeLayer.buffer.fill(blue, in: IntRect(x: 10, y: 10, width: 10, height: 2))
        let before = canvas.activeLayer.buffer.contentHash()
        select(IntRect(x: 8, y: 8, width: 14, height: 14), canvas, history)
        SelectionActions.transformSelection(.rotate90Clockwise, canvas: canvas, history: history, context: context)
        #expect(canvas.selection.floating != nil)
        #expect(SelectionActions.cancelFloating(canvas: canvas, history: history))
        #expect(canvas.activeLayer.buffer.contentHash() == before && canvas.selection.marquee != nil)
    }

    @Test func nothingFloatingIsLeftAlone() {
        let (canvas, history) = makeCanvas()
        #expect(!SelectionActions.cancelFloating(canvas: canvas, history: history))
        select(IntRect(x: 0, y: 0, width: 5, height: 5), canvas, history)
        #expect(!SelectionActions.cancelFloating(canvas: canvas, history: history))
        #expect(canvas.selection.marquee != nil)
    }

    /// Undo property test for Esc: random edits, then pixels lifted or pasted and changed at random, then Esc. The
    /// picture and selection are exactly as they were just before the lift or paste, whatever came between.
    @Test func escStopsExactlyAtTheLiftOrPaste() {
        var random = SplitMix64(seed: 34)
        for _ in 0..<60 {
            let (canvas, history) = makeCanvas()
            func rect() -> IntRect {
                IntRect(x: Int.random(in: 0..<30, using: &random), y: Int.random(in: 0..<30, using: &random),
                        width: Int.random(in: 2...12, using: &random), height: Int.random(in: 2...12, using: &random))
            }
            // Some settled edits first, so there's history below the lift.
            for _ in 0..<Int.random(in: 0...3, using: &random) {
                select(rect(), canvas, history)
                move(canvas, history, by: Int.random(in: -6...6, using: &random), Int.random(in: -6...6, using: &random))
                SelectionActions.placeFloating(canvas: canvas, history: history, context: context)
            }
            let before = canvas.activeLayer.buffer.contentHash()
            if Bool.random(using: &random) {
                select(rect(), canvas, history)
                move(canvas, history, by: Int.random(in: -6...6, using: &random), Int.random(in: -6...6, using: &random))
            } else {
                let piece = PixelBuffer(width: 5, height: 4)
                piece.fill(blue, in: piece.bounds)
                SelectionActions.paste(piece, at: IntPoint(x: Int.random(in: -3..<38, using: &random), y: Int.random(in: -3..<38, using: &random)),
                                       canvas: canvas, history: history, context: context)
            }
            let steps = history.undoCount
            for _ in 0..<Int.random(in: 0...5, using: &random) {
                guard canvas.selection.floating != nil else { break }
                switch Int.random(in: 0..<5, using: &random) {
                case 0: move(canvas, history, by: Int.random(in: -6...6, using: &random), Int.random(in: -6...6, using: &random))
                case 1: move(canvas, history, by: Int.random(in: -6...6, using: &random), 2, smear: true)
                case 2: move(canvas, history, by: 4, Int.random(in: -6...6, using: &random), duplicate: true)
                case 3: SelectionActions.nudge(dx: Int.random(in: -2...2, using: &random), dy: 1, canvas: canvas, history: history, context: context)
                default: SelectionActions.transformSelection(.flipHorizontal, canvas: canvas, history: history, context: context)
                }
            }
            // An undo in between leaves steps to redo; Esc still goes all the way back.
            if Bool.random(using: &random), history.undoCount > steps { history.undo(on: canvas) }
            guard canvas.selection.floating != nil else { continue }
            #expect(SelectionActions.cancelFloating(canvas: canvas, history: history))
            #expect(canvas.activeLayer.buffer.contentHash() == before)
            #expect(history.undoCount == steps - 1 && !history.canRedo)
        }
    }
}
