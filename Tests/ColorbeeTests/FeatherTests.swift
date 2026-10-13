import ColorbeeCore
import Testing
@testable import Colorbee

/// Edit ▸ Feather… (FR-3.4).
@MainActor
struct FeatherTests {
    private func boxed() -> Editor {
        let editor = makeEditor()
        editor.selectionDrag(from: pt(10.5, 10.5), to: pt(40.5, 40.5))
        return editor
    }

    /// Document commands wait while the sheet is open: OK puts back the selection as it was when it opened
    /// (review P, finding 1).
    @Test func commandsAreBlockedWhileTheSheetIsOpen() {
        let editor = boxed()
        #expect(!editor.blocksDocumentCommands)
        editor.beginFeather()
        #expect(editor.blocksDocumentCommands)
        editor.cancelFeather()
        #expect(!editor.blocksDocumentCommands)
    }

    @Test func cancelLeavesTheSelectionAndAddsNoStep() {
        let editor = boxed()
        let before = editor.canvas.selection.marquee
        editor.beginFeather()
        editor.setFeatherRadius(20)
        editor.cancelFeather()
        #expect(editor.canvas.selection.marquee?.revision == before?.revision)
        #expect(editor.stepNames.isEmpty)
    }

    @Test func okSoftensTheEdge() {
        let editor = boxed()
        editor.beginFeather()
        editor.setFeatherRadius(6)
        editor.applyFeather()
        #expect(editor.canvas.selection.marquee?.isSoft == true)
    }

    /// Slider moves are worked out in the background and merged; OK keeps exactly the radius in the box, even when its
    /// preview isn't ready yet (review O, finding 12).
    @Test func okUsesTheNewestRadiusAfterQuickMoves() async throws {
        let editor = boxed()
        let original = try #require(editor.canvas.selection.marquee)
        let expected = try #require(original.feathered(radius: 14, clippedTo: editor.canvas.bounds))
        editor.beginFeather()
        for radius in [4.0, 9.0, 14.0] { editor.setFeatherRadius(radius) }
        editor.applyFeather()
        let applied = try #require(editor.canvas.selection.marquee)
        #expect(applied.bounds == expected.bounds && applied.values == expected.values)
        // A preview still running when OK came changes nothing afterwards.
        try await Task.sleep(for: .milliseconds(100))
        #expect(editor.canvas.selection.marquee?.revision == applied.revision)
    }
}
