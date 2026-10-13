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
}
