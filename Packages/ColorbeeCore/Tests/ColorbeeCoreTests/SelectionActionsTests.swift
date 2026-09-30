import Testing
@testable import ColorbeeCore

struct SelectionActionsTests {
    private let red = Pixel(r: 255, g: 0, b: 0)
    private let blue = Pixel(r: 0, g: 0, b: 255)
    private let context = SelectionContext(color2: .white)

    /// A 40×40 white canvas with a red 10×10 square at (10, 10).
    private func makeCanvas() -> (Canvas, History) {
        let canvas = Canvas(size: IntSize(width: 40, height: 40), colorSpace: Canvas.defaultColorSpace, background: .white)
        canvas.activeLayer.buffer.fill(red, in: IntRect(x: 10, y: 10, width: 10, height: 10))
        return (canvas, History(byteBudget: .max))
    }

    private func selectRedSquare(_ canvas: Canvas, _ history: History) {
        let mask = SelectionMask.rectangle(IntRect(x: 10, y: 10, width: 10, height: 10), clippedTo: canvas.bounds)
        SelectionActions.select(mask, mode: .replace, canvas: canvas, history: history, context: context)
    }

    private func move(_ canvas: Canvas, _ history: History, to origin: IntPoint, duplicate: Bool = false, smearThrough: [IntPoint] = []) {
        let edit = SelectionActions.beginMove(duplicate: duplicate, canvas: canvas, history: history, context: context)!
        for point in smearThrough {
            SelectionActions.move(to: point, smear: true, edit: edit, canvas: canvas, context: context)
        }
        SelectionActions.move(to: origin, smear: !smearThrough.isEmpty, edit: edit, canvas: canvas, context: context)
        history.commit(edit)
    }

    @Test func marqueeCoversBothEndPixelsInEitherDirection() {
        let bounds = IntRect(x: 0, y: 0, width: 100, height: 100)
        let forward = SelectionActions.marquee(.rectangle, from: Point2D(x: 2.5, y: 3.5), to: Point2D(x: 5.2, y: 7.9), constrain: false, in: bounds)
        let backward = SelectionActions.marquee(.rectangle, from: Point2D(x: 5.2, y: 7.9), to: Point2D(x: 2.5, y: 3.5), constrain: false, in: bounds)
        #expect(forward?.bounds == IntRect(x: 2, y: 3, width: 4, height: 5))
        #expect(backward?.bounds == forward?.bounds)
    }

    @Test func constrainedMarqueeIsSquare() {
        let bounds = IntRect(x: 0, y: 0, width: 100, height: 100)
        let square = SelectionActions.marquee(.rectangle, from: Point2D(x: 50, y: 50), to: Point2D(x: 40, y: 58), constrain: true, in: bounds)
        #expect(square?.bounds.width == square?.bounds.height)
        #expect(square?.bounds == IntRect(x: 40, y: 50, width: 11, height: 11))
    }

    @Test func movingLiftsPixelsAndFillsTheHoleWithColor2() {
        let (canvas, history) = makeCanvas()
        selectRedSquare(canvas, history)
        move(canvas, history, to: IntPoint(x: 25, y: 25))

        #expect(canvas.activeLayer.buffer[12, 12] == .white)
        #expect(canvas.selection.floating?.destination == IntRect(x: 25, y: 25, width: 10, height: 10))
        #expect(canvas.flattened()[27, 27] == red)
        #expect(history.undoActionName == "Move Selection")
    }

    @Test func holeIsTransparentOnATransparentCanvas() {
        let canvas = Canvas(size: IntSize(width: 20, height: 20), colorSpace: Canvas.defaultColorSpace, background: .clear)
        canvas.activeLayer.buffer.fill(red)
        let history = History(byteBudget: .max)
        SelectionActions.selectAll(canvas: canvas, history: history, context: context)
        move(canvas, history, to: IntPoint(x: 5, y: 5))
        #expect(canvas.activeLayer.buffer[1, 1] == .clear)
    }

    @Test func moveAndPlaceUndoAsOneStep() {
        let (canvas, history) = makeCanvas()
        let original = canvas.activeLayer.buffer.contentHash()
        selectRedSquare(canvas, history)
        move(canvas, history, to: IntPoint(x: 25, y: 25))
        SelectionActions.placeFloating(canvas: canvas, history: history, context: context)

        #expect(canvas.activeLayer.buffer[27, 27] == red)
        #expect(canvas.selection.isEmpty)
        #expect(history.undoCount == 1)

        history.undo(on: canvas)
        #expect(canvas.activeLayer.buffer.contentHash() == original)
        #expect(canvas.selection.marquee?.bounds == IntRect(x: 10, y: 10, width: 10, height: 10))

        history.redo(on: canvas)
        #expect(canvas.activeLayer.buffer[27, 27] == red)
        #expect(canvas.selection.isEmpty)
    }

    @Test func eachMoveOfAFloatingSelectionIsItsOwnStep() {
        let (canvas, history) = makeCanvas()
        selectRedSquare(canvas, history)
        move(canvas, history, to: IntPoint(x: 20, y: 20))
        move(canvas, history, to: IntPoint(x: 25, y: 25))
        #expect(history.undoCount == 2)

        history.undo(on: canvas)
        #expect(canvas.selection.floating?.destination.minX == 20)
    }

    @Test func duplicateLeavesTheOriginal() {
        let (canvas, history) = makeCanvas()
        selectRedSquare(canvas, history)
        move(canvas, history, to: IntPoint(x: 25, y: 25), duplicate: true)
        SelectionActions.placeFloating(canvas: canvas, history: history, context: context)
        #expect(canvas.activeLayer.buffer[12, 12] == red)
        #expect(canvas.activeLayer.buffer[27, 27] == red)
    }

    @Test func smearLeavesATrail() {
        let (canvas, history) = makeCanvas()
        selectRedSquare(canvas, history)
        move(canvas, history, to: IntPoint(x: 28, y: 10), smearThrough: [IntPoint(x: 13, y: 10), IntPoint(x: 18, y: 10), IntPoint(x: 23, y: 10)])
        SelectionActions.placeFloating(canvas: canvas, history: history, context: context)
        for x in [14, 20, 26, 32] {
            #expect(canvas.activeLayer.buffer[x, 15] == red, "x = \(x)")
        }
    }

    @Test func transparentSelectionSkipsColor2() {
        let (canvas, history) = makeCanvas()
        canvas.activeLayer.buffer.fill(blue, in: IntRect(x: 30, y: 0, width: 10, height: 40))
        let mask = SelectionMask.rectangle(IntRect(x: 5, y: 5, width: 20, height: 20), clippedTo: canvas.bounds)
        let transparent = SelectionContext(color2: .white, transparentSelection: true)
        SelectionActions.select(mask, mode: .replace, canvas: canvas, history: history, context: transparent)
        let edit = SelectionActions.beginMove(duplicate: true, canvas: canvas, history: history, context: transparent)!
        SelectionActions.move(to: IntPoint(x: 20, y: 5), smear: false, edit: edit, canvas: canvas, context: transparent)
        history.commit(edit)
        SelectionActions.placeFloating(canvas: canvas, history: history, context: transparent)

        #expect(canvas.activeLayer.buffer[32, 8] == blue)
        #expect(canvas.activeLayer.buffer[27, 17] == red)
    }

    @Test func deletingAMarqueeFillsItAndUndoRestores() {
        let (canvas, history) = makeCanvas()
        let original = canvas.activeLayer.buffer.contentHash()
        selectRedSquare(canvas, history)
        #expect(SelectionActions.deleteSelection(canvas: canvas, history: history, context: context))
        #expect(canvas.activeLayer.buffer[15, 15] == .white)
        #expect(canvas.selection.marquee != nil)

        history.undo(on: canvas)
        #expect(canvas.activeLayer.buffer.contentHash() == original)
    }

    @Test func deletingAFloatingSelectionCanBeUndone() {
        let (canvas, history) = makeCanvas()
        selectRedSquare(canvas, history)
        move(canvas, history, to: IntPoint(x: 25, y: 25))
        SelectionActions.deleteSelection(canvas: canvas, history: history, context: context)
        #expect(canvas.selection.isEmpty)
        #expect(canvas.flattened()[27, 27] == .white)

        history.undo(on: canvas)
        #expect(canvas.selection.floating?.destination.minX == 25)
    }

    @Test func pasteFloatsAndOneUndoRemovesItAfterPlacing() {
        let (canvas, history) = makeCanvas()
        let original = canvas.activeLayer.buffer.contentHash()
        let image = PixelBuffer(width: 5, height: 5, fill: blue)
        SelectionActions.paste(image, at: IntPoint(x: 2, y: 2), canvas: canvas, history: history, context: context)
        #expect(canvas.activeLayer.buffer[3, 3] == .white)
        #expect(canvas.flattened()[3, 3] == blue)

        SelectionActions.placeFloating(canvas: canvas, history: history, context: context)
        #expect(canvas.activeLayer.buffer[3, 3] == blue)
        #expect(history.undoCount == 1)

        history.undo(on: canvas)
        #expect(canvas.activeLayer.buffer.contentHash() == original)
        #expect(canvas.selection.isEmpty)
    }

    @Test func nudgeMovesByOneStep() {
        let (canvas, history) = makeCanvas()
        selectRedSquare(canvas, history)
        SelectionActions.nudge(dx: 1, dy: 0, canvas: canvas, history: history, context: context)
        SelectionActions.nudge(dx: 0, dy: 10, canvas: canvas, history: history, context: context)
        #expect(canvas.selection.floating?.destination == IntRect(x: 11, y: 20, width: 10, height: 10))
        #expect(history.undoCount == 2)
    }

    @Test func selectedPixelsAreCroppedToTheSelection() throws {
        let (canvas, history) = makeCanvas()
        let mask = SelectionMask.ellipse(in: IntRect(x: 10, y: 10, width: 10, height: 10), clippedTo: canvas.bounds)
        SelectionActions.select(mask, mode: .replace, canvas: canvas, history: history, context: context)
        let pixels = try #require(SelectionActions.selectedPixels(canvas: canvas, context: context))
        #expect(pixels.size == IntSize(width: 10, height: 10))
        #expect(pixels[5, 5] == red)
        #expect(pixels[0, 0] == .clear)
    }

    @Test func startingANewSelectionPlacesTheFloatingOne() {
        let (canvas, history) = makeCanvas()
        selectRedSquare(canvas, history)
        move(canvas, history, to: IntPoint(x: 25, y: 25))
        let other = SelectionMask.rectangle(IntRect(x: 0, y: 0, width: 5, height: 5), clippedTo: canvas.bounds)
        SelectionActions.select(other, mode: .replace, canvas: canvas, history: history, context: context)

        #expect(canvas.activeLayer.buffer[27, 27] == red)
        #expect(canvas.selection.marquee?.bounds == IntRect(x: 0, y: 0, width: 5, height: 5))
        #expect(history.undoCount == 1)
    }

    @Test func addingCombinesWithTheExistingSelection() {
        let (canvas, history) = makeCanvas()
        selectRedSquare(canvas, history)
        let other = SelectionMask.rectangle(IntRect(x: 30, y: 30, width: 5, height: 5), clippedTo: canvas.bounds)
        SelectionActions.select(other, mode: .add, canvas: canvas, history: history, context: context)
        #expect(canvas.selection.marquee?.bounds == IntRect(x: 10, y: 10, width: 25, height: 25))
        #expect(canvas.selection.contains(IntPoint(x: 31, y: 31)))
        #expect(!canvas.selection.contains(IntPoint(x: 25, y: 25)))
    }

    @Test func invertingNothingSelectsEverything() {
        let (canvas, history) = makeCanvas()
        SelectionActions.invert(canvas: canvas, history: history, context: context)
        #expect(canvas.selection.marquee?.bounds == canvas.bounds)
    }

    @Test func movingABatchSelectionMovesEveryRegion() {
        let (canvas, history) = makeCanvas()
        canvas.activeLayer.buffer.fill(blue, in: IntRect(x: 30, y: 30, width: 5, height: 5))
        selectRedSquare(canvas, history)
        let other = SelectionMask.rectangle(IntRect(x: 30, y: 30, width: 5, height: 5), clippedTo: canvas.bounds)
        SelectionActions.select(other, mode: .add, canvas: canvas, history: history, context: context)
        move(canvas, history, to: IntPoint(x: 5, y: 5))
        SelectionActions.placeFloating(canvas: canvas, history: history, context: context)

        #expect(canvas.activeLayer.buffer[6, 6] == red)
        #expect(canvas.activeLayer.buffer[26, 26] == blue)
        #expect(canvas.activeLayer.buffer[20, 20] == .white)
    }

    @Test(arguments: [0x5E1E_C7ED, 1, 2, 3, 42, 777, 2026] as [UInt64])
    func randomSelectionWorkUndoesBackToTheOriginal(seed: UInt64) {
        var random = SplitMix64(seed: seed)
        let canvas = Canvas(size: IntSize(width: 300, height: 300), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: 1 << 20)
        let original = canvas.activeLayer.buffer.contentHash()

        func randomRect() -> IntRect {
            IntRect(x: random.int(-20..<300), y: random.int(-20..<300), width: random.int(1..<120), height: random.int(1..<120))
        }

        for _ in 0..<60 {
            let color = Pixel(r: random.byte(), g: random.byte(), b: random.byte())
            let context = SelectionContext(color2: color, transparentSelection: random.next() % 4 == 0)
            switch random.int(0..<7) {
            case 0:
                let edit = history.beginEdit("Fill", on: canvas)
                let rect = randomRect()
                edit.willModify(rect, in: canvas.activeLayer)
                canvas.activeLayer.buffer.fill(color, in: rect)
                history.commit(edit)
            case 1:
                let shape: SelectionShape = random.next() % 2 == 0 ? .rectangle : .ellipse
                let mode: SelectionCombineMode = [.replace, .add, .subtract, .intersect][random.int(0..<4)]
                let mask = SelectionActions.marquee(shape, from: Point2D(x: Double(random.int(0..<300)), y: Double(random.int(0..<300))),
                                                    to: Point2D(x: Double(random.int(0..<300)), y: Double(random.int(0..<300))),
                                                    constrain: false, in: canvas.bounds)
                SelectionActions.select(mask, mode: mode, canvas: canvas, history: history, context: context)
            case 2:
                guard let edit = SelectionActions.beginMove(duplicate: random.next() % 3 == 0, canvas: canvas, history: history, context: context) else { continue }
                for _ in 0..<random.int(1..<4) {
                    SelectionActions.move(to: IntPoint(x: random.int(-50..<300), y: random.int(-50..<300)),
                                          smear: random.next() % 3 == 0, edit: edit, canvas: canvas, context: context)
                }
                history.commit(edit)
            case 3:
                SelectionActions.placeFloating(canvas: canvas, history: history, context: context)
            case 4:
                let image = PixelBuffer(width: random.int(1..<80), height: random.int(1..<80), fill: color)
                SelectionActions.paste(image, at: IntPoint(x: random.int(0..<300), y: random.int(0..<300)), canvas: canvas, history: history, context: context)
            case 5:
                SelectionActions.deleteSelection(canvas: canvas, history: history, context: context)
            default:
                SelectionActions.nudge(dx: random.int(-3..<4), dy: random.int(-3..<4), canvas: canvas, history: history, context: context)
            }
        }
        let finalPixels = canvas.activeLayer.buffer.contentHash()
        let finalFlattened = canvas.flattened().contentHash()

        while history.canUndo { history.undo(on: canvas) }
        #expect(canvas.activeLayer.buffer.contentHash() == original)
        #expect(canvas.selection.floating == nil)

        while history.canRedo { history.redo(on: canvas) }
        #expect(canvas.activeLayer.buffer.contentHash() == finalPixels)
        #expect(canvas.flattened().contentHash() == finalFlattened)
    }
}
