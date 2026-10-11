import ColorbeeCore
import Testing
@testable import Colorbee

/// Selection drags combine with the selection by the modifiers held when the drag starts (FR-3.2): none replaces,
/// Shift adds, Option subtracts, Shift+Option intersects. Shift pressed after the start makes a square.
/// A drag that starts inside the selection moves it instead (Shift smears, Option duplicates; FR-3.1, AC-7).
@MainActor
struct SelectionDragTests {
    /// A rectangle selected from (10, 10) to (30, 30): both end pixels are in it, so it's 21 pixels wide.
    func editorWithSelection(_ tool: Tool = .rectangleSelect) -> Editor {
        let editor = makeEditor()
        editor.selectTool(tool)
        editor.selectionDrag(from: pt(10, 10), to: pt(30, 30))
        return editor
    }

    @Test func aDragSelectsARectangle() {
        let editor = editorWithSelection()
        #expect(editor.canvas.selection.bounds == IntRect(x: 10, y: 10, width: 21, height: 21))
        #expect(editor.marqueePreview == nil)
    }

    @Test func aPlainDragReplacesTheSelection() {
        let editor = editorWithSelection()
        editor.selectionDrag(from: pt(40, 40), to: pt(50, 50))
        #expect(!editor.isSelected(15, 15))
        #expect(editor.isSelected(45, 45))
    }

    @Test func shiftAdds() {
        let editor = editorWithSelection()
        editor.selectionDrag(from: pt(40, 40), to: pt(50, 50), shift: true)
        #expect(editor.isSelected(15, 15))
        #expect(editor.isSelected(45, 45))
        #expect(!editor.isSelected(35, 35))
    }

    @Test func optionSubtracts() {
        let editor = editorWithSelection()
        editor.selectionDrag(from: pt(35, 35), to: pt(20, 20), option: true)
        #expect(editor.isSelected(15, 15))
        #expect(!editor.isSelected(25, 25))
        #expect(!editor.isSelected(32, 32))
    }

    @Test func shiftOptionIntersects() {
        let editor = editorWithSelection()
        editor.selectionDrag(from: pt(35, 35), to: pt(20, 20), shift: true, option: true)
        #expect(!editor.isSelected(15, 15))
        #expect(editor.isSelected(25, 25))
        #expect(!editor.isSelected(32, 32))
        #expect(editor.canvas.selection.bounds == IntRect(x: 20, y: 20, width: 11, height: 11))
    }

    /// Shift held from the start only picks Add; the rectangle keeps the shape dragged.
    @Test func shiftHeldFromTheStartDoesNotMakeASquare() {
        let editor = editorWithSelection()
        editor.selectionDrag(from: pt(40, 40), to: pt(60, 50), shift: true)
        #expect(editor.isSelected(15, 15))
        #expect(editor.isSelected(55, 45))
        #expect(!editor.isSelected(55, 55))
    }

    @Test func shiftPressedAfterTheStartMakesASquare() {
        let editor = makeEditor()
        editor.selectTool(.rectangleSelect)
        editor.selectionDrag(from: pt(10, 10), to: pt(40, 20), shiftDown: true)
        let bounds = editor.canvas.selection.bounds
        #expect(bounds != nil)
        #expect(bounds?.width == bounds?.height)
    }

    @Test func shiftReleasedAndPressedAgainAddsAndMakesASquare() {
        let editor = editorWithSelection()
        editor.beginSelectionDrag(at: pt(40, 40), modifiers: DragModifiers(shift: true))
        editor.continueSelectionDrag(to: pt(50, 45), shiftDown: false)
        editor.continueSelectionDrag(to: pt(60, 50), shiftDown: true)
        editor.endSelectionDrag(at: pt(60, 50))
        #expect(editor.isSelected(15, 15))
        // A 20 × 20 square from (40, 40), not the 20 × 10 rectangle dragged.
        #expect(editor.isSelected(45, 55))
    }

    @Test func anEllipseCombinesTheSameWay() {
        let editor = editorWithSelection()
        editor.selectTool(.ellipseSelect)
        editor.selectionDrag(from: pt(34, 34), to: pt(54, 54), shift: true)
        #expect(editor.isSelected(15, 15))
        #expect(editor.isSelected(44, 44))
        #expect(!editor.isSelected(35, 35))
    }

    @Test func aLassoCombinesTheSameWay() {
        let editor = editorWithSelection()
        editor.selectTool(.lassoSelect)
        // Starts outside the selection, so Option subtracts a band through it.
        editor.beginSelectionDrag(at: pt(36, 16), modifiers: DragModifiers(option: true))
        for point in [pt(20, 16), pt(20, 24), pt(36, 24)] { editor.continueSelectionDrag(to: point, shiftDown: false) }
        editor.endSelectionDrag(at: pt(36, 24))
        #expect(editor.isSelected(15, 20))
        #expect(!editor.isSelected(25, 20))
        #expect(editor.isSelected(25, 27))
        #expect(editor.canvas.selection.floating == nil)
    }

    @Test func aMagicWandCombinesTheSameWay() {
        let editor = makeEditor()
        // Two separate black squares on the gray.
        editor.selectTool(.rectangleSelect)
        editor.selectionDrag(from: pt(4, 4), to: pt(14, 14))
        editor.fill(at: pt(8, 8), secondary: false)
        editor.selectionDrag(from: pt(40, 40), to: pt(50, 50))
        editor.fill(at: pt(45, 45), secondary: false)
        editor.deselect()

        editor.selectTool(.magicWand)
        editor.selectionDrag(from: pt(8, 8), to: pt(8, 8))
        editor.selectionDrag(from: pt(45, 45), to: pt(45, 45), shift: true)
        #expect(editor.isSelected(8, 8))
        #expect(editor.isSelected(45, 45))
        #expect(!editor.isSelected(30, 30))

        // With a modifier the wand always selects, even inside the selection (2026-10-01).
        editor.selectionDrag(from: pt(8, 8), to: pt(8, 8), option: true)
        #expect(!editor.isSelected(8, 8))
        #expect(editor.isSelected(45, 45))
    }

    // MARK: Not undo steps

    @Test func drawingAndCombiningOutlinesAreNotUndoSteps() {
        let editor = editorWithSelection()
        editor.selectionDrag(from: pt(40, 40), to: pt(50, 50), shift: true)
        editor.selectionDrag(from: pt(35, 35), to: pt(20, 20), option: true)
        #expect(editor.history.undoCount == 0)
    }

    @Test func aClickDeselects() {
        let editor = editorWithSelection()
        editor.selectionDrag(from: pt(45, 45), to: pt(45.5, 45.5))
        #expect(editor.canvas.selection.isEmpty)
    }

    @Test func aShiftClickKeepsTheSelection() {
        let editor = editorWithSelection()
        editor.selectionDrag(from: pt(45, 45), to: pt(45.5, 45.5), shift: true)
        #expect(editor.isSelected(15, 15))
    }

    // MARK: Drags that start inside the selection

    func editorWithPaintedSelection() -> Editor {
        let editor = makeEditor()
        editor.selectTool(.rectangleSelect)
        editor.selectionDrag(from: pt(10, 10), to: pt(20, 20))
        editor.fill(at: pt(15, 15), secondary: false)
        return editor
    }

    @Test func aDragInsideMovesTheSelectionAsOneStep() {
        let editor = editorWithPaintedSelection()
        let steps = editor.history.undoCount
        let before = editor.imageHash
        editor.selectionDrag(from: pt(15, 15), to: pt(45, 15))
        #expect(editor.history.undoCount == steps + 1)
        #expect(editor.history.undoActionName == "Move Selection")
        #expect(editor.canvas.selection.bounds == IntRect(x: 40, y: 10, width: 11, height: 11))
        editor.undo()
        #expect(editor.imageHash == before)
    }

    @Test func optionDragInsideDuplicates() {
        let editor = editorWithPaintedSelection()
        editor.selectionDrag(from: pt(15, 15), to: pt(45, 15), option: true)
        editor.placePendingObjects()
        editor.deselect()
        #expect(editor.history.undoActionName != nil)
        let layer = editor.canvas.activeLayer.buffer
        #expect(layer[15, 15] == .black)
        #expect(layer[45, 15] == .black)
    }

    @Test func shiftDragInsideSmears() {
        let editor = editorWithPaintedSelection()
        editor.beginSelectionDrag(at: pt(15, 15), modifiers: DragModifiers(shift: true))
        for x in stride(from: 16.0, through: 45, by: 1) { editor.continueSelectionDrag(to: pt(x, 15), shiftDown: true) }
        editor.endSelectionDrag(at: pt(45, 15))
        editor.selectTool(.pencil)
        // The trail of copies fills the whole way from the start to the end.
        let layer = editor.canvas.activeLayer.buffer
        #expect((10..<50).allSatisfy { layer[$0, 15] == .black })
    }

    @Test func aLockedLayerRefusesAMoveButNotANewOutline() {
        let editor = editorWithPaintedSelection()
        editor.setLayerLocked(true, at: 0)
        var refusals = 0
        editor.onRefused = { refusals += 1 }
        let before = editor.imageHash
        editor.selectionDrag(from: pt(15, 15), to: pt(45, 15))
        #expect(refusals == 1)
        #expect(editor.imageHash == before)

        editor.selectionDrag(from: pt(40, 40), to: pt(50, 50))
        #expect(refusals == 1)
        #expect(editor.isSelected(45, 45))
    }
}
