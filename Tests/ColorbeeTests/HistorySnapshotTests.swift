import ColorbeeCore
import Testing
@testable import Colorbee

/// History Snapshots (FR-9.7 item 4), driven the way the History panel and Edit ▸ New Snapshot… do.
@MainActor
struct HistorySnapshotAppTests {
    @Test func goingToASnapshotIsAStepThatUndoes() throws {
        let editor = makeEditor()
        let start = editor.imageHash
        try editor.takeSnapshot(named: editor.nextSnapshotName)
        #expect(editor.historySnapshots.map(\.name) == ["Snapshot 1"] && editor.nextSnapshotName == "Snapshot 2")
        #expect(editor.stepNames.isEmpty)
        editor.selectTool(.pencil)
        editor.stroke(wobblyPath)
        editor.applyAdjustment(.invert)
        let edited = editor.imageHash
        var changes: [DocumentChange] = []
        editor.onDocumentChange = { changes.append($0) }
        editor.goToSnapshot(try #require(editor.historySnapshots.first).id)
        #expect(editor.imageHash == start)
        #expect(editor.stepNames.last == "Go to Snapshot" && changes == [.done])
        editor.undo()
        #expect(editor.imageHash == edited)
    }

    @Test func aFloatingSelectionIsPlacedBeforeTheSnapshot() throws {
        let editor = makeEditor()
        editor.paste(PixelBuffer(width: 10, height: 10, fill: Pixel(r: 0, g: 0, b: 255)))
        #expect(editor.canvas.selection.floating != nil)
        try editor.takeSnapshot(named: "Pasted")
        #expect(editor.canvas.selection.floating == nil && editor.canvas.selection.marquee != nil)
        let pasted = editor.imageHash
        editor.deselect()
        editor.selectAll()
        editor.applyAdjustment(.invert)
        editor.goToSnapshot(try #require(editor.historySnapshots.first).id)
        #expect(editor.imageHash == pasted)
    }

    @Test func goingBackToADifferentSizeRecentersTheCanvas() throws {
        let editor = makeEditor(width: 64, height: 48)
        try editor.takeSnapshot(named: "Full size")
        editor.selectionDrag(from: pt(4.5, 4.5), to: pt(20.5, 30.5))
        editor.cropToSelection()
        #expect(editor.canvasSize != IntSize(width: 64, height: 48))
        editor.goToSnapshot(try #require(editor.historySnapshots.first).id)
        #expect(editor.canvas.size == IntSize(width: 64, height: 48) && editor.canvasSize == editor.canvas.size)
    }

    @Test func snapshotsCanBeRenamedAndDeleted() throws {
        let editor = makeEditor()
        try editor.takeSnapshot(named: "Start")
        let id = try #require(editor.historySnapshots.first).id
        editor.renameSnapshot(id, to: "Before dramatic")
        #expect(editor.historySnapshots.map(\.name) == ["Before dramatic"])
        editor.deleteSnapshot(id)
        #expect(editor.historySnapshots.isEmpty)
    }

    @Test func atTheCapANewSnapshotIsRefused() throws {
        let editor = makeEditor(width: 8, height: 8)
        for _ in 0..<History.snapshotLimit { try editor.takeSnapshot(named: editor.nextSnapshotName) }
        #expect(throws: HistorySnapshot.Failure.full) { try editor.takeSnapshot(named: "One more") }
        #expect(editor.historySnapshots.count == 10 && editor.historySnapshots.last?.name == "Snapshot 10")
    }

    @Test func eachPageHasItsOwn() throws {
        let editor = makeEditor()
        try editor.takeSnapshot(named: "Page 1")
        editor.newPage()
        #expect(editor.historySnapshots.isEmpty)
        editor.showPage(at: 0)
        #expect(editor.historySnapshots.map(\.name) == ["Page 1"])
    }
}
