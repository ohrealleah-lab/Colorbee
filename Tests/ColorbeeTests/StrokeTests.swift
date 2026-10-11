import ColorbeeCore
import Testing
@testable import Colorbee

/// Pencil, Brush and Eraser strokes: Shift straightens them, each is one undo step, and some layers refuse them.
@MainActor
struct StrokeTests {
    nonisolated static let strokeTools: [Tool] = [.pencil, .brush, .eraser]

    func editor(with tool: Tool) -> Editor {
        let editor = makeEditor()
        editor.selectTool(tool)
        return editor
    }

    // MARK: Shift keeps a stroke on one line (Leah, 2026-10-10)

    @Test(arguments: strokeTools)
    func shiftKeepsAWobblyDragOnOneHorizontalLine(tool: Tool) {
        let wobbly = editor(with: tool)
        wobbly.stroke(wobblyPath, constrain: true)

        // The same drag along a ruler-straight line, without Shift.
        let straight = editor(with: tool)
        straight.stroke(wobblyPath.map { pt($0.x, wobblyPath[0].y) })

        #expect(wobbly.imageHash == straight.imageHash)
        #expect(wobbly.imageHash != makeEditor().imageHash)
    }

    @Test(arguments: strokeTools)
    func shiftKeepsAWobblyDragOnOneVerticalLine(tool: Tool) {
        let path = wobblyPath.map { pt($0.y, $0.x) }
        let wobbly = editor(with: tool)
        wobbly.stroke(path, constrain: true)

        let straight = editor(with: tool)
        straight.stroke(path.map { pt(path[0].x, $0.y) })

        #expect(wobbly.imageHash == straight.imageHash)
    }

    @Test func shiftedPencilStrokeTouchesOnlyItsStartingRow() {
        let editor = editor(with: .pencil)
        editor.stroke(wobblyPath, constrain: true)
        #expect(editor.canvas.activeLayer.buffer.rowsChanged(from: paper) == [20])
    }

    @Test func shiftedBrushStrokeStaysWithinItsWidthOfTheStartingRow() {
        let editor = editor(with: .brush)
        editor.brushDiameter = 5
        editor.stroke(wobblyPath, constrain: true)
        let rows = editor.canvas.activeLayer.buffer.rowsChanged(from: paper)
        #expect(!rows.isEmpty)
        #expect(rows.allSatisfy { abs(Double($0) + 0.5 - wobblyPath[0].y) <= 3.5 })
    }

    @Test(arguments: strokeTools)
    func withoutShiftTheWobbleShows(tool: Tool) {
        let wobbly = editor(with: tool)
        wobbly.stroke(wobblyPath)
        let straight = editor(with: tool)
        straight.stroke(wobblyPath.map { pt($0.x, wobblyPath[0].y) })
        #expect(wobbly.imageHash != straight.imageHash)
    }

    /// The axis is picked by the first full pixel of movement, so a drag that starts sideways stays sideways.
    @Test func theFirstMovementPicksTheAxis() {
        let editor = editor(with: .pencil)
        editor.stroke([pt(30.5, 30.5), pt(32.5, 30.9), pt(33.5, 45.5), pt(34.5, 10.5)], constrain: true)
        #expect(editor.canvas.activeLayer.buffer.rowsChanged(from: paper) == [30])
    }

    @Test func symmetryMirrorsAShiftedStroke() {
        let editor = editor(with: .pencil)
        editor.symmetry = .horizontal
        editor.stroke(wobblyPath, constrain: true)
        #expect(editor.canvas.activeLayer.buffer.rowsChanged(from: paper) == [20, 43])
    }

    // MARK: One undo step each

    @Test(arguments: strokeTools)
    func eachStrokeIsOneUndoStep(tool: Tool) {
        let editor = editor(with: tool)
        let before = editor.imageHash
        editor.stroke(wobblyPath)
        let afterFirst = editor.imageHash
        editor.stroke(wobblyPath.map { pt($0.x, $0.y + 20) })

        #expect(editor.history.undoCount == 2)
        editor.undo()
        #expect(editor.imageHash == afterFirst)
        editor.undo()
        #expect(editor.imageHash == before)
        editor.redo()
        #expect(editor.imageHash == afterFirst)
    }

    @Test func strokesAreNamedForWhatTheyDid() {
        let editor = editor(with: .pencil)
        editor.stroke(wobblyPath)
        editor.selectTool(.brush)
        editor.stroke(wobblyPath)
        editor.brush = .marker
        editor.stroke(wobblyPath)
        editor.selectTool(.eraser)
        // Right-drag: the Color Eraser, which needs Color 1 under it to change anything.
        editor.stroke(wobblyPath, secondary: true)
        editor.stroke(wobblyPath)
        #expect(editor.stepNames == ["Pencil", "Brush Stroke", Brush.marker.name, "Color Erase", "Erase"])
    }

    @Test func aSymmetricStrokeIsStillOneStep() {
        let editor = editor(with: .brush)
        editor.symmetry = .both
        let before = editor.imageHash
        editor.stroke(wobblyPath)
        #expect(editor.history.undoCount == 1)
        editor.undo()
        #expect(editor.imageHash == before)
    }

    @Test func aStrokeMarksTheDocumentEditedOnce() {
        let editor = editor(with: .pencil)
        var changes: [DocumentChange] = []
        editor.onDocumentChange = { changes.append($0) }
        editor.stroke(wobblyPath)
        #expect(changes.count == 1)
    }

    // MARK: Layers that refuse strokes (FR-8.2, FR-8.4)

    @Test(arguments: strokeTools)
    func aLockedLayerRefusesStrokes(tool: Tool) {
        let editor = editor(with: tool)
        editor.setLayerLocked(true, at: 0)
        let steps = editor.history.undoCount
        let before = editor.imageHash
        var refusals = 0
        editor.onRefused = { refusals += 1 }

        editor.stroke(wobblyPath)

        #expect(refusals == 1)
        #expect(editor.imageHash == before)
        #expect(editor.history.undoCount == steps)
    }

    @Test(arguments: strokeTools)
    func anAdjustmentLayerRefusesStrokes(tool: Tool) {
        let editor = editor(with: tool)
        editor.addAdjustmentLayer(.invert, named: "Invert")
        #expect(editor.canvas.activeLayer.adjustment != nil)
        let steps = editor.history.undoCount
        let pixels = editor.canvas.layers[0].buffer.contentHash()
        var refusals = 0
        editor.onRefused = { refusals += 1 }

        editor.stroke(wobblyPath)

        #expect(refusals == 1)
        #expect(editor.canvas.layers[0].buffer.contentHash() == pixels)
        #expect(editor.history.undoCount == steps)
    }

    @Test func aStrokePaintsOnlyTheActiveLayer() {
        let editor = editor(with: .pencil)
        editor.addLayer()
        let bottom = editor.canvas.layers[0].buffer.contentHash()
        editor.stroke(wobblyPath)
        #expect(editor.canvas.layers[0].buffer.contentHash() == bottom)
        #expect(!editor.canvas.layers[1].buffer.rowsChanged(from: .clear).isEmpty)
    }
}
