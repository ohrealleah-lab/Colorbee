import ColorbeeCore
import Testing
@testable import Colorbee

/// Shapes and text stay editable until placed; placing them is one step, and it happens before any other command
/// (`finishInteractions()`), so that command's step comes after it.
@MainActor
struct PendingObjectTests {
    /// Commands that must place a pending object first, with the name of the step each adds (nil: none).
    nonisolated static let commands: [(name: String, step: String?, run: @MainActor @Sendable (Editor) -> Void)] = [
        ("Pick another tool", nil, { $0.selectTool(.pencil) }),
        // Selecting is not an undo step on its own.
        ("Select All", nil, { $0.selectAll() }),
        ("New Layer", "New Layer", { $0.addLayer() }),
        ("Flip Horizontal", Orientation.flipHorizontal.name, { $0.apply(.flipHorizontal) }),
        ("Fill", "Fill", { $0.fill(at: pt(60, 60), secondary: false) }),
        ("Save", nil, { _ = $0.saveSnapshot() }),
    ]

    func editorWithPendingShape() -> Editor {
        let editor = makeEditor()
        editor.selectTool(.shape)
        editor.shapeKind = .rectangle
        editor.shapeDrag(from: pt(10, 10), to: pt(30, 25))
        return editor
    }

    func editorWithPendingText() -> Editor {
        let editor = makeEditor()
        editor.selectTool(.text)
        editor.textStyle.fontSize = 14
        editor.beginText(at: pt(4, 4), wrapWidth: nil)
        editor.updatePendingText("Hi")
        return editor
    }

    @Test func aShapeIsNotAStepUntilPlaced() {
        let editor = editorWithPendingShape()
        #expect(editor.pendingShape != nil)
        #expect(editor.history.undoCount == 0)
        #expect(editor.imageHash == makeEditor().imageHash)
    }

    @Test(arguments: commands.indices)
    func aPendingShapeIsPlacedBeforeTheCommand(index: Int) {
        let command = Self.commands[index]
        let editor = editorWithPendingShape()
        command.run(editor)
        #expect(editor.pendingShape == nil, "\(command.name)")
        let shapeStep = ShapeKind.rectangle.name
        #expect(editor.stepNames == [shapeStep] + [command.step].compactMap(\.self), "\(command.name)")
    }

    @Test(arguments: commands.indices)
    func pendingTextIsPlacedBeforeTheCommand(index: Int) {
        let command = Self.commands[index]
        let editor = editorWithPendingText()
        command.run(editor)
        #expect(editor.pendingText == nil, "\(command.name)")
        #expect(editor.stepNames == ["Text"] + [command.step].compactMap(\.self), "\(command.name)")
    }

    @Test(arguments: commands.indices)
    func aPendingBadgeIsPlacedBeforeTheCommand(index: Int) {
        let command = Self.commands[index]
        let editor = makeEditor()
        editor.selectTool(.stepBadge)
        editor.badgeDiameter = 16
        editor.badgeClick(at: pt(20, 20))
        command.run(editor)
        #expect(editor.pendingBadge == nil, "\(command.name)")
        #expect(editor.stepNames == ["Step Badge"] + [command.step].compactMap(\.self), "\(command.name)")
    }

    /// What's saved is what's shown: the badge still being placed is in the file (found by these tests, 2026-10-11).
    @Test func aSaveHoldsTheBadgeStillBeingPlaced() {
        let editor = makeEditor()
        editor.selectTool(.stepBadge)
        editor.badgeDiameter = 16
        editor.badgeClick(at: pt(20, 20))
        editor.badgeClick(at: pt(44, 20))
        let snapshot = editor.saveSnapshot()
        #expect(snapshot.canvas.flattened().contentHash() == editor.imageHash)
        #expect(editor.stepNames == ["Step Badge", "Step Badge"])
    }

    /// An autosave doesn't fix in place what's still being placed.
    @Test func anAutosaveLeavesPendingObjectsEditable() {
        let editor = makeEditor()
        editor.selectTool(.stepBadge)
        editor.badgeClick(at: pt(20, 20))
        _ = editor.saveSnapshot(placingPending: false)
        #expect(editor.pendingBadge != nil)
        #expect(editor.history.undoCount == 0)
    }

    @Test func aStrokePlacesAPendingShapeFirst() {
        let editor = editorWithPendingShape()
        editor.selectTool(.pencil)
        editor.stroke(wobblyPath)
        #expect(editor.stepNames == [ShapeKind.rectangle.name, "Pencil"])
    }

    @Test func undoingAfterPlacingTakesOffOnlyTheCommandsStep() {
        let editor = editorWithPendingShape()
        editor.commitPendingShape()
        let withShape = editor.imageHash
        editor.selectTool(.pencil)
        editor.stroke(wobblyPath)
        editor.undo()
        #expect(editor.imageHash == withShape)
    }

    /// ⌘Z discards a shape not yet placed rather than undoing the step before it.
    @Test func undoDiscardsAPendingShape() {
        let editor = makeEditor()
        editor.selectTool(.pencil)
        editor.stroke(wobblyPath)
        let painted = editor.imageHash
        editor.selectTool(.shape)
        editor.shapeDrag(from: pt(10, 10), to: pt(30, 25))

        editor.undo()
        #expect(editor.pendingShape == nil)
        #expect(editor.stepNames == ["Pencil"])
        #expect(editor.imageHash == painted)
    }

    @Test func undoPlacesPendingTextThenUndoesIt() {
        let editor = editorWithPendingText()
        let before = editor.imageHash
        editor.undo()
        #expect(editor.pendingText == nil)
        #expect(editor.imageHash == before)
        editor.redo()
        #expect(editor.imageHash != before)
    }

    @Test func aShapeStaysEditableUntilPlaced() {
        let editor = editorWithPendingShape()
        // Drag from inside the shape: moves it.
        editor.beginShapeDrag(at: pt(20, 18), viewPoint: editor.viewport.viewPoint(fromImage: pt(20, 18)), secondary: false, clickCount: 1)
        editor.continueShapeDrag(to: pt(30, 28), shiftDown: false)
        editor.endShapeDrag()
        #expect(editor.pendingShape?.start == pt(20, 20))
        #expect(editor.history.undoCount == 0)
    }

    @Test func aClickWithoutADragMakesNoShape() {
        let editor = makeEditor()
        editor.selectTool(.shape)
        editor.shapeDrag(from: pt(10, 10), to: pt(10.4, 10.2))
        #expect(editor.pendingShape == nil)
    }

    @Test func savingCanLeaveAPendingShapeInPlace() {
        let editor = editorWithPendingShape()
        _ = editor.saveSnapshot(placingPending: false)
        #expect(editor.pendingShape != nil)
        #expect(editor.history.undoCount == 0)
    }

    @Test func emptyTextAddsNoStep() {
        let editor = makeEditor()
        editor.selectTool(.text)
        editor.beginText(at: pt(4, 4), wrapWidth: nil)
        editor.selectTool(.pencil)
        #expect(editor.pendingText == nil)
        #expect(editor.history.undoCount == 0)
    }
}
