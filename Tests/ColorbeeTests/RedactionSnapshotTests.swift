import ColorbeeCore
import Testing
@testable import Colorbee

/// A redaction deletes the History Snapshots of the pages it changes, after asking, and undo doesn't bring them back
/// (Leah, 2026-11-01).
@MainActor
struct RedactionSnapshotTests {
    let red = Pixel(r: 220, g: 20, b: 30, a: 255)

    private func editorWithSnapshot() throws -> Editor {
        let editor = makeEditor()
        editor.selectTool(.redactBrush)
        editor.redactBrushSize = 8
        editor.redactTreatment = .solidFill
        editor.color1 = red
        try editor.takeSnapshot(named: "Before")
        return editor
    }

    private func redactStroke(_ editor: Editor) {
        editor.beginRedactStroke(at: wobblyPath[0], secondary: false)
        for point in wobblyPath.dropFirst() { editor.continueRedactStroke(to: point, constrain: false) }
        editor.endRedactStroke()
    }

    @Test func theRedactBrushAsksThenDeletesTheSnapshots() throws {
        let editor = try editorWithSnapshot()
        let before = editor.imageHash
        redactStroke(editor)
        #expect(editor.snapshotQuestion?.count == 1)
        #expect(editor.imageHash == before && editor.stepNames.isEmpty)
        editor.deleteSnapshotsAndRedact()
        #expect(editor.snapshotQuestion == nil)
        #expect(editor.stepNames == ["Redact Brush"] && editor.imageHash != before)
        #expect(editor.historySnapshots.isEmpty)
        editor.undo()
        #expect(editor.imageHash == before && editor.historySnapshots.isEmpty)
    }

    @Test func cancelRedactsNothingAndKeepsTheSnapshots() throws {
        let editor = try editorWithSnapshot()
        let before = editor.imageHash
        redactStroke(editor)
        editor.snapshotQuestion = nil
        #expect(editor.imageHash == before && editor.stepNames.isEmpty)
        #expect(editor.historySnapshots.count == 1)
        #expect(editor.areaStrokePicture() == nil)
    }

    @Test func withoutSnapshotsNothingIsAsked() {
        let editor = makeEditor()
        editor.selectTool(.redactBrush)
        redactStroke(editor)
        #expect(editor.snapshotQuestion == nil && editor.stepNames == ["Redact Brush"])
    }

    @Test func aLockedLayerRefusesWithoutAsking() throws {
        let editor = try editorWithSnapshot()
        editor.setLayerLocked(true, at: 0)
        redactStroke(editor)
        #expect(editor.snapshotQuestion == nil && editor.redactionMessage != nil)
        #expect(editor.historySnapshots.count == 1)
    }

    @Test func anotherPagesSnapshotsAreLeftAlone() throws {
        let editor = try editorWithSnapshot()
        editor.newPage()
        redactStroke(editor)
        #expect(editor.snapshotQuestion == nil && editor.stepNames == ["Redact Brush"])
        #expect(editor.pages.pages[0].history.snapshots.count == 1)
    }

    @Test func solidFillAsksThenDeletesTheSnapshots() throws {
        let editor = try editorWithSnapshot()
        editor.selectTool(.rectangleSelect)
        editor.selectionDrag(from: Point2D(x: 10, y: 10), to: Point2D(x: 30, y: 30))
        editor.applySolidFill()
        #expect(editor.snapshotQuestion?.count == 1 && editor.stepNames.isEmpty)
        editor.deleteSnapshotsAndRedact()
        #expect(editor.canvas.activeLayer.buffer[20, 20] == red)
        #expect(editor.historySnapshots.isEmpty)
    }

    /// Batch Redact's Cancel leaves the bar open, with nothing applied; Apply then asks again.
    @Test func batchRedactAsksAtApply() throws {
        let editor = try editorWithSnapshot()
        editor.selectTool(.pencil)
        editor.stroke(wobblyPath)
        let drawn = editor.stepNames
        editor.selectTool(.rectangleSelect)
        editor.selectionDrag(from: Point2D(x: 10, y: 10), to: Point2D(x: 50, y: 50))
        editor.beginBatchRedact(.pixelate)
        editor.applyEffect()
        #expect(editor.snapshotQuestion?.count == 1 && editor.activeEffect == .pixelate)
        editor.snapshotQuestion = nil
        #expect(editor.activeEffect == .pixelate && editor.stepNames == drawn && editor.historySnapshots.count == 1)
        editor.applyEffect()
        editor.deleteSnapshotsAndRedact()
        #expect(editor.activeEffect == nil && editor.stepNames == drawn + ["Pixelate"])
        #expect(editor.historySnapshots.isEmpty)
    }

    /// Review AH, finding 1: redo, or a click forward in the History panel, brings a redaction back, so a snapshot taken
    /// after the undo has to go too (Leah, 2026-11-02).
    @Test func redoingARedactionAsksThenDeletesTheSnapshotsTakenSince() throws {
        let editor = makeEditor()
        editor.selectTool(.redactBrush)
        editor.redactTreatment = .solidFill
        editor.color1 = red
        redactStroke(editor)
        let redacted = editor.imageHash
        editor.undo()
        editor.redactedSinceSave = false
        try editor.takeSnapshot(named: "After undo")
        editor.redo()
        #expect(editor.snapshotQuestion?.count == 1 && editor.imageHash != redacted)
        editor.deleteSnapshotsAndRedact()
        #expect(editor.imageHash == redacted && editor.historySnapshots.isEmpty && editor.redactedSinceSave)
    }

    @Test func cancelingARedoKeepsTheSnapshotAndTheRedoStep() throws {
        let editor = makeEditor()
        editor.selectTool(.redactBrush)
        editor.redactTreatment = .solidFill
        redactStroke(editor)
        editor.undo()
        try editor.takeSnapshot(named: "After undo")
        let uncovered = editor.imageHash
        editor.redo()
        editor.snapshotQuestion = nil
        #expect(editor.imageHash == uncovered && editor.historySnapshots.count == 1)
        editor.jump(toStep: 1)
        #expect(editor.snapshotQuestion?.count == 1 && editor.imageHash == uncovered)
    }

    @Test func redoingARedactionWithoutSnapshotsAsksNothingButNotesIt() {
        let editor = makeEditor()
        editor.selectTool(.redactBrush)
        redactStroke(editor)
        editor.undo()
        editor.redactedSinceSave = false
        editor.redo()
        #expect(editor.snapshotQuestion == nil && editor.stepNames == ["Redact Brush"] && editor.redactedSinceSave)
    }
}
