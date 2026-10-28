import ColorbeeCore
import Testing
@testable import Colorbee

/// Edit ▸ Feather… (FR-3.4) and Modify Selection ▸ Expand…, Contract… and Smooth… (FR-9.7 item 3), which share a sheet.
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
        editor.beginSelectionChange(.feather)
        #expect(editor.blocksDocumentCommands)
        editor.cancelSelectionChange()
        #expect(!editor.blocksDocumentCommands)
    }

    @Test func cancelLeavesTheSelectionAndAddsNoStep() {
        let editor = boxed()
        let before = editor.canvas.selection.marquee
        editor.beginSelectionChange(.feather)
        editor.setSelectionChangeRadius(20)
        editor.cancelSelectionChange()
        #expect(editor.canvas.selection.marquee?.revision == before?.revision)
        #expect(editor.stepNames.isEmpty)
    }

    /// OK waits for the selection to be worked out in the background rather than holding up the window.
    private func applied(_ editor: Editor) async throws {
        editor.applySelectionChange()
        try await waitUntil { editor.selectionChange == nil }
    }

    @Test func okSoftensTheEdge() async throws {
        let editor = boxed()
        editor.beginSelectionChange(.feather)
        editor.setSelectionChangeRadius(6)
        try await applied(editor)
        #expect(editor.canvas.selection.marquee?.isSoft == true)
    }

    /// Slider moves are worked out in the background and merged; OK keeps exactly the radius in the box, even when its
    /// preview isn't ready yet (review O, finding 12).
    @Test func okUsesTheNewestRadiusAfterQuickMoves() async throws {
        let editor = boxed()
        let original = try #require(editor.canvas.selection.marquee)
        let expected = try #require(original.feathered(radius: 14, clippedTo: editor.canvas.bounds))
        editor.beginSelectionChange(.feather)
        for radius in [4.0, 9.0, 14.0] { editor.setSelectionChangeRadius(radius) }
        try await applied(editor)
        let applied = try #require(editor.canvas.selection.marquee)
        #expect(applied.bounds == expected.bounds && applied.values == expected.values)
        // A preview still running when OK came changes nothing afterwards.
        try await Task.sleep(for: .milliseconds(100))
        #expect(editor.canvas.selection.marquee?.revision == applied.revision)
    }

    @Test func expandAndContractMoveTheEdgeAndAddNoStep() async throws {
        let editor = boxed()
        let box = try #require(editor.canvas.selection.marquee).bounds
        editor.beginSelectionChange(.expand)
        #expect(editor.selectionChangeRadius == 2)
        editor.setSelectionChangeRadius(5)
        try await applied(editor)
        #expect(editor.canvas.selection.marquee?.bounds == box.insetBy(-5))
        editor.beginSelectionChange(.contract)
        editor.setSelectionChangeRadius(8)
        try await applied(editor)
        #expect(editor.canvas.selection.marquee?.bounds == box.insetBy(3))
        #expect(editor.stepNames.isEmpty)
    }

    @Test func okIsRefusedWhenNothingWouldBeLeft() async throws {
        let editor = boxed()
        let before = try #require(editor.canvas.selection.marquee)
        editor.beginSelectionChange(.contract)
        editor.setSelectionChangeRadius(40)
        try await waitUntil { !editor.isWorkingOnSelectionChange }
        #expect(editor.selectionChangeLeavesNothing)
        editor.applySelectionChange()
        #expect(editor.selectionChange == .contract)
        editor.cancelSelectionChange()
        #expect(editor.canvas.selection.marquee?.revision == before.revision)
    }
}
