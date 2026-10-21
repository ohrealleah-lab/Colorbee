import ColorbeeCore
import Foundation
import Testing
@testable import Colorbee

/// Crop…, Straighten… and Perspective Correction… driven by canvas drags, the way `CanvasView` drives them (FR-9.5).
@MainActor
@Suite(.serialized)
struct CanvasToolTests {
    private func drag(_ editor: Editor, from a: Point2D, to b: Point2D) {
        editor.beginCanvasToolDrag(at: a, viewPoint: editor.viewport.viewPoint(fromImage: a))
        editor.continueCanvasToolDrag(to: b)
        editor.endCanvasToolDrag()
    }

    /// A picture with a mark in one corner, so a crop or a turn shows.
    private func markedEditor() -> Editor {
        let editor = makeEditor(width: 80, height: 60)
        editor.canvas.activeLayer.buffer.fill(.black, in: IntRect(x: 0, y: 0, width: 10, height: 10))
        return editor
    }

    @Test func cropStartsOnTheWholeImageAndAHandleDragShrinksIt() {
        let editor = markedEditor()
        let before = editor.imageHash
        editor.beginEffect(.crop)
        #expect(editor.cropRect == editor.canvas.bounds)
        #expect(editor.canvasToolHandles.count == 8)
        #expect(editor.canvasToolLines.count == 4)
        drag(editor, from: pt(80, 60), to: pt(50, 40))
        #expect(editor.cropRect == IntRect(x: 0, y: 0, width: 50, height: 40))
        editor.applyEffect()
        #expect(editor.canvas.size == IntSize(width: 50, height: 40))
        #expect(editor.stepNames.last == "Crop")
        editor.undo()
        #expect(editor.canvas.size == IntSize(width: 80, height: 60))
        #expect(editor.imageHash == before)
    }

    @Test func dragsInsideMoveTheBoxAndOutsideDrawANewOne() {
        let editor = markedEditor()
        editor.beginEffect(.crop)
        drag(editor, from: pt(80, 60), to: pt(40, 30))
        drag(editor, from: pt(20, 15), to: pt(30, 25))
        #expect(editor.cropRect == IntRect(x: 10, y: 10, width: 40, height: 30))
        // Outside the box: a new box from where the drag starts.
        drag(editor, from: pt(70, 50), to: pt(78, 58))
        #expect(editor.cropRect.minX == 70 && editor.cropRect.minY == 50)
        editor.cancelEffect()
        #expect(editor.canvas.size == IntSize(width: 80, height: 60))
    }

    @Test func aCropShapeKeepsItsProportions() {
        let editor = markedEditor()
        editor.beginEffect(.crop)
        editor.setCrop(shape: .square, pixelSize: nil)
        #expect(editor.cropRect.width == editor.cropRect.height)
        drag(editor, from: pt(Double(editor.cropRect.maxX), Double(editor.cropRect.maxY)), to: pt(30, 30))
        #expect(editor.cropRect.width == editor.cropRect.height)
        editor.cancelEffect()
    }

    @Test func aLineDrawnWithStraightenSetsTheTurn() {
        let editor = markedEditor()
        editor.beginEffect(.straighten)
        #expect(editor.canvasToolLines.count == 14)
        // Drawn along a horizon that rises 5 px over 50: about 5.7°.
        drag(editor, from: pt(10, 40), to: pt(60, 35))
        #expect(abs(abs(editor.effectValues[0]) - 5.7) < 0.2, "\(editor.effectValues)")
        #expect(editor.straightenLine == nil)
        // A tiny line (a click) changes nothing.
        let turn = editor.effectValues[0]
        drag(editor, from: pt(10, 40), to: pt(11, 40))
        #expect(editor.effectValues[0] == turn)
        editor.cancelEffect()
    }

    @Test func perspectiveCornersAreDraggedAndApplied() {
        let editor = markedEditor()
        let before = editor.imageHash
        editor.beginEffect(.perspective)
        #expect(editor.canvasToolHandles.count == 4)
        #expect(editor.canvasToolLines.count == 4)
        let corner = editor.perspectiveCorners[0]
        drag(editor, from: corner, to: pt(-20, -20))
        // Kept on the image.
        #expect(editor.perspectiveCorners[0] == pt(0, 0))
        // A drag far from every corner moves none.
        let corners = editor.perspectiveCorners
        drag(editor, from: pt(40, 30), to: pt(45, 35))
        #expect(editor.perspectiveCorners == corners)
        editor.applyEffect()
        #expect(editor.stepNames.last == "Perspective Correction")
        editor.undo()
        #expect(editor.imageHash == before)
    }
}

/// Pages (FR-11.6) through the Editor: adding, copying, moving, deleting and undoing them.
@MainActor
@Suite(.serialized)
struct EditorPageTests {
    @Test func newDuplicateMoveAndDeleteUndoAndRedo() {
        let editor = makeEditor(width: 40, height: 30)
        editor.canvas.activeLayer.buffer.fill(.black, in: IntRect(x: 0, y: 0, width: 5, height: 5))
        let first = editor.imageHash
        editor.duplicatePage()
        #expect(editor.pageCount == 2)
        #expect(editor.currentPageIndex == 1)
        #expect(editor.imageHash == first)
        editor.newPage()
        #expect(editor.pageCount == 3)
        #expect(editor.currentPageIndex == 2)
        let blank = editor.imageHash
        #expect(blank != first)
        editor.movePage(from: 2, to: 0)
        #expect(editor.currentPageIndex == 0)
        #expect(editor.imageHash == blank)
        editor.deletePage()
        #expect(editor.pageCount == 2)
        editor.undo()
        #expect(editor.pageCount == 3)
        editor.undo()
        editor.undo()
        editor.undo()
        #expect(editor.pageCount == 1)
        #expect(editor.imageHash == first)
        editor.redo()
        #expect(editor.pageCount == 2)
    }

    @Test func eachPageKeepsItsOwnEdits() {
        let editor = makeEditor(width: 40, height: 30)
        editor.newPage()
        editor.selectTool(.pencil)
        editor.stroke([pt(2.5, 2.5), pt(30.5, 2.5)])
        let drawn = editor.imageHash
        editor.showPage(at: 0)
        #expect(editor.imageHash != drawn)
        editor.showPage(at: 1)
        #expect(editor.imageHash == drawn)
        editor.undo()
        #expect(editor.imageHash != drawn)
    }

    @Test func theLastPageCantBeDeleted() {
        let editor = makeEditor(width: 40, height: 30)
        editor.deletePage()
        #expect(editor.pageCount == 1)
    }
}
