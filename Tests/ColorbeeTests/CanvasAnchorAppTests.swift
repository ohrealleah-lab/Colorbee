import ColorbeeCore
import Testing
@testable import Colorbee

/// Canvas Properties' anchor (FR-2.2), as the sheet's OK applies it.
@MainActor
struct CanvasAnchorAppTests {
    @Test func centerGivesAnEvenBorderAsOneStep() {
        let editor = makeEditor(width: 20, height: 10)
        editor.canvas.activeLayer.buffer.row(0)[0] = .black
        editor.applyCanvasProperties(size: IntSize(width: 30, height: 20), anchor: .center, transparentBackground: false)
        #expect(editor.canvas.size == IntSize(width: 30, height: 20) && editor.canvasSize == editor.canvas.size)
        #expect(editor.canvas.activeLayer.buffer[5, 5] == .black)
        #expect(editor.stepNames == ["Resize Canvas"])
        editor.undo()
        #expect(editor.canvas.size == IntSize(width: 20, height: 10) && editor.canvas.activeLayer.buffer[0, 0] == .black)
    }

    @Test func theCanvasEdgeHandlesStillAddSpaceRightAndBelow() {
        let editor = makeEditor(width: 20, height: 10)
        editor.canvas.activeLayer.buffer.row(0)[0] = .black
        editor.resizeCanvas(to: IntSize(width: 30, height: 20))
        #expect(editor.canvas.activeLayer.buffer[0, 0] == .black)
    }
}
