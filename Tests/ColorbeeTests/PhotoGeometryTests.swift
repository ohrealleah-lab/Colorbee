import ColorbeeCore
import Foundation
import Testing
@testable import Colorbee

/// Perspective Correction's corners found by Vision, and Crop…'s guides (FR-9.7 item 7).
@MainActor
struct PhotoGeometryTests {
    /// A light slanted board on a darker ground.
    private func board() -> Editor {
        let editor = makeEditor(width: 300, height: 200, background: Pixel(r: 70, g: 70, b: 70))
        let mask = SelectionMask.polygon([pt(60, 40), pt(240, 50), pt(230, 165), pt(70, 155)], clippedTo: editor.canvas.bounds)
        let buffer = editor.canvas.activeLayer.buffer
        for y in 0..<200 { for x in 0..<300 where (mask?[x, y] ?? 0) > 127 { buffer.row(y)[x] = Pixel(r: 240, g: 240, b: 235) } }
        return editor
    }

    private func waitForCorners(_ editor: Editor) async {
        for _ in 0..<200 where editor.isFindingCorners { try? await Task.sleep(for: .milliseconds(20)) }
    }

    @Test func perspectiveCornersStartOnTheBoard() async {
        let editor = board()
        editor.beginEffect(.perspective)
        #expect(editor.isFindingCorners)
        await waitForCorners(editor)
        let expected = [pt(60, 40), pt(240, 50), pt(230, 165), pt(70, 155)]
        #expect(zip(editor.perspectiveCorners, expected).allSatisfy { abs($0.x - $1.x) <= 3 && abs($0.y - $1.y) <= 3 }, "\(editor.perspectiveCorners)")
        // Reset puts a moved corner back there.
        let found = editor.perspectiveCorners
        editor.beginCanvasToolDrag(at: found[0], viewPoint: editor.viewport.viewPoint(fromImage: found[0]))
        editor.continueCanvasToolDrag(to: pt(20, 20), constrain: false)
        editor.endCanvasToolDrag()
        #expect(editor.perspectiveCorners != found)
        editor.resetPerspectiveCorners()
        #expect(editor.perspectiveCorners == found)
        editor.cancelEffect()
    }

    @Test func withNoRectangleTheCornersStayInset() async {
        let editor = makeEditor(width: 300, height: 200)
        editor.beginEffect(.perspective)
        let inset = editor.perspectiveCorners
        await waitForCorners(editor)
        #expect(editor.perspectiveCorners == inset && editor.perspectiveCorners[0] == pt(18, 12))
        editor.cancelEffect()
    }

    @Test func oSwitchesCropGuides() {
        let editor = makeEditor()
        let before = editor.cropOverlay
        editor.nextCropOverlay()
        #expect(editor.cropOverlay == before)
        editor.beginEffect(.crop)
        editor.nextCropOverlay()
        #expect(editor.cropOverlay == before.next)
        // Shown for a moment after O, though the box isn't being dragged.
        #expect(editor.canvasToolLines.count > 4)
        editor.cropOverlay = before
        editor.cancelEffect()
    }
}
