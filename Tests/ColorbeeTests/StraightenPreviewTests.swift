import ColorbeeCore
import Testing
@testable import Colorbee

/// Straighten's preview is turned in the background and swapped in when ready (Leah, 2026-10-11).
@MainActor
struct StraightenPreviewTests {
    private func photo() -> Editor {
        let editor = makeEditor(width: 80, height: 50)
        editor.canvas.activeLayer.buffer.fill(.black, in: IntRect(x: 0, y: 22, width: 80, height: 4))
        editor.beginEffect(.straighten)
        return editor
    }

    /// Moves the slider, as `EffectBar` does.
    private func slide(_ editor: Editor, to angle: Double) {
        editor.effectValues[0] = angle
        editor.previewEffect()
    }

    /// Waits for the preview of `angle` to be shown.
    private func settle(_ editor: Editor, at angle: Double) async throws {
        for _ in 0..<400 {
            if !editor.straightenRunning, editor.straightenShown?.angle == angle { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("The preview of \(angle)° never showed")
    }

    /// What Straighten gives when worked out directly, for comparing.
    private func expected(_ angle: Double) -> (hash: Int, size: IntSize) {
        let editor = makeEditor(width: 80, height: 50)
        editor.canvas.activeLayer.buffer.fill(.black, in: IntRect(x: 0, y: 22, width: 80, height: 4))
        #expect(ImageActions.straighten(angle: angle, cropToFit: true, canvas: editor.canvas, history: editor.history, context: editor.selectionContext))
        return (editor.imageHash, editor.canvas.size)
    }

    @Test func thePreviewShowsTheTurnAndApplyKeepsItAsOneStep() async throws {
        let editor = photo()
        let original = (editor.imageHash, editor.canvas.size)
        slide(editor, to: 10)
        try await settle(editor, at: 10)
        #expect((editor.imageHash, editor.canvas.size) == expected(10))
        editor.applyEffect()
        #expect(editor.stepNames == ["Straighten"])
        editor.undo()
        #expect((editor.imageHash, editor.canvas.size) == original)
    }

    @Test func applyWhileStillTurningKeepsTheNewestAngle() async throws {
        let editor = photo()
        slide(editor, to: 10)
        try await settle(editor, at: 10)
        slide(editor, to: 20)
        editor.applyEffect()
        #expect((editor.imageHash, editor.canvas.size) == expected(20))
        #expect(editor.stepNames == ["Straighten"])
        // A turn still running when Apply came must not change anything later.
        try await Task.sleep(for: .milliseconds(200))
        #expect((editor.imageHash, editor.canvas.size) == expected(20))
        #expect(editor.stepNames == ["Straighten"])
    }

    @Test func cancelWhileTurningLeavesTheImageAsItWas() async throws {
        let editor = photo()
        let original = (editor.imageHash, editor.canvas.size)
        slide(editor, to: 15)
        try await Task.sleep(for: .milliseconds(1))
        editor.cancelEffect()
        try await Task.sleep(for: .milliseconds(200))
        #expect((editor.imageHash, editor.canvas.size) == original)
        #expect(editor.stepNames.isEmpty)
    }

    @Test func quickSliderMovesEndOnTheLastOne() async throws {
        let editor = photo()
        for angle in [3.0, 6.0, 9.0, 12.0] { slide(editor, to: angle) }
        try await settle(editor, at: 12)
        #expect((editor.imageHash, editor.canvas.size) == expected(12))
        editor.applyEffect()
        #expect(editor.stepNames == ["Straighten"])
    }

    /// Cancel waits for a turn still reading the layers, so Rotate right after can't change them under it
    /// (review O, finding 2), and nothing lands afterwards.
    @Test func rotatingRightAfterCancelIsSafeAndExact() async throws {
        let editor = photo()
        let expected = makeEditor(width: 80, height: 50)
        expected.canvas.activeLayer.buffer.fill(.black, in: IntRect(x: 0, y: 22, width: 80, height: 4))
        expected.apply(.rotate90Clockwise)
        slide(editor, to: 15)
        editor.cancelEffect()
        #expect(!editor.straightenRunning)
        editor.apply(.rotate90Clockwise)
        try await Task.sleep(for: .milliseconds(100))
        #expect((editor.imageHash, editor.canvas.size) == (expected.imageHash, expected.canvas.size))
        #expect(editor.stepNames.count == 1)
    }
}
