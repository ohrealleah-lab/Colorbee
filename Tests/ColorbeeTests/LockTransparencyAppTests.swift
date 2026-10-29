import ColorbeeCore
import Testing
@testable import Colorbee

/// Lock Transparent Pixels through the tools, the way `CanvasView` drives them (FR-8.2, stage 23).
@MainActor
struct LockTransparencyAppTests {
    /// Paper below, and above it a layer with a white square in the middle, transparency locked.
    private func locked() -> Editor {
        let editor = makeEditor(width: 32, height: 32)
        editor.addLayer()
        editor.canvas.activeLayer.buffer.fill(.white, in: IntRect(x: 10, y: 10, width: 12, height: 12))
        editor.setLayerLocksTransparency(true, at: editor.activeLayerIndex)
        return editor
    }

    private func clearOutsideTheSquare(_ editor: Editor) -> Bool {
        let buffer = editor.canvas.activeLayer.buffer
        return (0..<32).allSatisfy { y in (0..<32).allSatisfy { x in (10..<22).contains(x) && (10..<22).contains(y) || buffer[x, y] == .clear } }
    }

    @Test func lockingIsAStepAndThePadlockMenuSaysWhich() {
        let editor = locked()
        #expect(editor.stepNames.last == "Lock Transparent Pixels" && editor.canvas.activeLayer.locksTransparency)
        // Not on an adjustment layer, which has no pixels.
        editor.addAdjustmentLayer(.invert)
        editor.setLayerLocksTransparency(true, at: editor.activeLayerIndex)
        #expect(!editor.canvas.activeLayer.locksTransparency)
    }

    @Test func brushFillAndEraserStayInsideTheShape() {
        let editor = locked()
        editor.color1 = Pixel(r: 255, g: 0, b: 0)
        editor.color2 = Pixel(r: 0, g: 0, b: 255)
        editor.selectTool(.brush)
        editor.brushDiameter = 12
        editor.beginStroke(at: pt(2, 16), secondary: false)
        editor.continueStroke(to: pt(16, 16), constrain: false)
        // Before the next frame shows it.
        editor.canvas.keepLockedTransparency()
        #expect(clearOutsideTheSquare(editor) && editor.canvas.activeLayer.buffer[16, 16] == Pixel(r: 255, g: 0, b: 0))
        editor.continueStroke(to: pt(30, 16), constrain: false)
        editor.endStroke()
        #expect(clearOutsideTheSquare(editor))
        editor.selectTool(.fill)
        editor.fill(at: pt(2, 2), secondary: false)
        #expect(clearOutsideTheSquare(editor))
        editor.selectTool(.eraser)
        editor.stroke([pt(12, 12), pt(20, 20)])
        #expect(clearOutsideTheSquare(editor) && editor.canvas.activeLayer.buffer[16, 16] == Pixel(r: 0, g: 0, b: 255))
    }
}
