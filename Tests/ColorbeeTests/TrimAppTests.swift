import ColorbeeCore
import Testing
@testable import Colorbee

/// Image ▸ Trim (§23, 2026-10-28), as the menu runs it.
@MainActor
struct TrimAppTests {
    @Test func trimCropsEveryLayerToWhatsShownAsOneStep() {
        let editor = makeEditor(width: 40, height: 30, background: .clear)
        editor.canvas.activeLayer.buffer.fill(.black, in: IntRect(x: 5, y: 6, width: 4, height: 4))
        editor.addLayer()
        editor.canvas.activeLayer.buffer.fill(Pixel(r: 200, g: 0, b: 0), in: IntRect(x: 20, y: 15, width: 3, height: 2))
        editor.trim()
        // Decided by both layers together.
        #expect(editor.canvas.size == IntSize(width: 18, height: 11) && editor.canvasSize == editor.canvas.size)
        #expect(editor.stepNames.last == "Trim")
        editor.undo()
        #expect(editor.canvas.size == IntSize(width: 40, height: 30))
    }

    @Test func nothingToTrimBeeps() {
        let editor = makeEditor()
        var refused = 0
        editor.onRefused = { refused += 1 }
        editor.trim()
        #expect(refused == 1 && editor.stepNames.isEmpty)
    }
}
