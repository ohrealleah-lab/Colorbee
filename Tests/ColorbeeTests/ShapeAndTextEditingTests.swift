import ColorbeeCore
import Foundation
import Testing
@testable import Colorbee

/// Editing a shape or text box before it's placed (FR-5.2, FR-6): its handles, rotating, moving, and building a
/// polygon or curve point by point, driven the way `CanvasView` drives them.
@MainActor
@Suite(.serialized)
struct ShapeAndTextEditingTests {
    private func drag(_ editor: Editor, from a: Point2D, to b: Point2D, shift: Bool = false, clickCount: Int = 1) {
        editor.beginShapeDrag(at: a, viewPoint: editor.viewport.viewPoint(fromImage: a), secondary: false, clickCount: clickCount)
        editor.continueShapeDrag(to: b, shiftDown: shift)
        editor.endShapeDrag()
    }

    private func click(_ editor: Editor, at point: Point2D, count: Int = 1) {
        editor.beginShapeDrag(at: point, viewPoint: editor.viewport.viewPoint(fromImage: point), secondary: false, clickCount: count)
        editor.endShapeDrag()
    }

    private func rectangleEditor() -> Editor {
        let editor = makeEditor(width: 120, height: 100)
        editor.selectTool(.shape)
        editor.shapeKind = .rectangle
        drag(editor, from: pt(20, 20), to: pt(60, 50))
        return editor
    }

    @Test func aCornerHandleResizesAndShiftKeepsTheShape() throws {
        let editor = rectangleEditor()
        let corner = try #require(editor.pendingShapeHandlePoints.max { $0.x + $0.y < $1.x + $1.y })
        drag(editor, from: corner, to: pt(corner.x + 20, corner.y + 10))
        let shape = try #require(editor.pendingShape)
        #expect(abs(max(shape.start.x, shape.end.x) - 80) <= 1 && abs(max(shape.start.y, shape.end.y) - 60) <= 1)
        #expect(abs(min(shape.start.x, shape.end.x) - 20) <= 1)
        // With Shift, the 2:1.5 box stays that shape.
        let grown = try #require(editor.pendingShapeHandlePoints.max { $0.x + $0.y < $1.x + $1.y })
        drag(editor, from: grown, to: pt(grown.x + 30, grown.y), shift: true)
        let kept = try #require(editor.pendingShape)
        let width = abs(kept.end.x - kept.start.x), height = abs(kept.end.y - kept.start.y)
        #expect(abs(width / height - 60.0 / 40.0) < 0.1, "\(width) × \(height)")
    }

    @Test func dragInsideMovesAndTheRotateHandleTurnsInFifteenDegreeSteps() throws {
        let editor = rectangleEditor()
        drag(editor, from: pt(40, 35), to: pt(50, 45))
        let moved = try #require(editor.pendingShape)
        #expect(min(moved.start.x, moved.end.x) == 30 && min(moved.start.y, moved.end.y) == 30)
        let handle = try #require(editor.pendingShapeRotateHandle)
        let center = pt((moved.start.x + moved.end.x) / 2, (moved.start.y + moved.end.y) / 2)
        // A quarter turn, a little off: Shift snaps it to exactly 90°.
        drag(editor, from: handle, to: pt(center.x + 40, center.y + 2), shift: true)
        let turned = try #require(editor.pendingShape)
        #expect(abs(turned.rotation - Double.pi / 2) < 1e-9)
        editor.selectTool(.pencil)
        #expect(editor.pendingShape == nil)
        #expect(editor.stepNames.count == 1)
    }

    @Test func aPolygonIsBuiltClickByClickAndClosedWithADoubleClick() throws {
        let editor = makeEditor(width: 120, height: 100)
        editor.selectTool(.shape)
        editor.shapeKind = .polygon
        drag(editor, from: pt(20, 20), to: pt(90, 20))
        click(editor, at: pt(90, 80))
        click(editor, at: pt(20, 80))
        click(editor, at: pt(20, 80), count: 2)
        let polygon = try #require(editor.pendingShape)
        #expect(!polygon.isBuilding)
        #expect(polygon.points.count == 4)
        editor.selectTool(.pencil)
        #expect(editor.canvas.activeLayer.buffer.rowsChanged(from: paper).contains(50))
    }

    @Test func clickingTheFirstCornerClosesAPolygon() throws {
        let editor = makeEditor(width: 120, height: 100)
        editor.selectTool(.shape)
        editor.shapeKind = .polygon
        drag(editor, from: pt(20, 20), to: pt(90, 20))
        click(editor, at: pt(60, 80))
        click(editor, at: pt(20, 20))
        #expect(editor.pendingShape?.isBuilding == false)
        #expect(editor.pendingShape?.points.count == 3)
    }

    @Test func aCurveIsBentByTwoMoreDrags() throws {
        let editor = makeEditor(width: 120, height: 100)
        editor.selectTool(.shape)
        editor.shapeKind = .curve
        drag(editor, from: pt(10, 50), to: pt(110, 50))
        let line = try #require(editor.pendingShape)
        #expect(line.points.count == 4)
        #expect(line.points[1].y == 50)
        drag(editor, from: pt(40, 50), to: pt(40, 10))
        drag(editor, from: pt(80, 50), to: pt(80, 90))
        let curve = try #require(editor.pendingShape)
        #expect(curve.points[1].y < 50 || curve.points[2].y > 50)
    }

    @Test func shiftKeepsALineStraight() throws {
        let editor = makeEditor(width: 120, height: 100)
        editor.selectTool(.shape)
        editor.shapeKind = .line
        drag(editor, from: pt(10, 50), to: pt(100, 54), shift: true)
        let line = try #require(editor.pendingShape)
        #expect(line.end.y == 50)
    }

    @Test func aTextBoxIsMovedByItsBorderAndWrappedByASideHandle() throws {
        let editor = makeEditor(width: 200, height: 120)
        editor.selectTool(.text)
        editor.beginText(at: pt(20, 20), wrapWidth: 100)
        #expect(editor.pendingTextHandles.count == 8)
        let border = try #require(editor.pendingTextBorder)
        let edge = editor.viewport.viewPoint(fromImage: pt((border.minX + border.maxX) / 2 + 20, border.minY))
        let grab = try #require(editor.textBoxGrab(atView: edge))
        editor.beginTextBoxDrag(grab, at: pt(0, 0))
        editor.continueTextBoxDrag(to: pt(10, 5))
        editor.endTextBoxDrag()
        #expect(editor.pendingText?.origin == pt(30, 25))
        let right = try #require(editor.pendingTextHandles.first { $0.handle == .right })
        let handle = try #require(editor.textBoxGrab(atView: editor.viewport.viewPoint(fromImage: right.point)))
        editor.beginTextBoxDrag(handle, at: right.point)
        editor.continueTextBoxDrag(to: pt(right.point.x + 40, right.point.y))
        editor.endTextBoxDrag()
        #expect(editor.pendingText?.wrapWidth == 140)
        // Well inside the box, clicks go to the text, not the frame.
        let inside = editor.viewport.viewPoint(fromImage: pt((border.minX + border.maxX) / 2 + 10, (border.minY + border.maxY) / 2 + 5))
        #expect(editor.textBoxGrab(atView: inside) == nil || (border.maxY - border.minY) < 20)
    }
}
