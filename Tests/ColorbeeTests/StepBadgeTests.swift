import ColorbeeCore
import Testing
@testable import Colorbee

/// Step Badges (FR-5.3): numbers and letters count separately, and undo steps the count back.
@MainActor
struct StepBadgeTests {
    func badgeEditor() -> Editor {
        let editor = makeEditor()
        editor.selectTool(.stepBadge)
        editor.badgeDiameter = 16
        return editor
    }

    @Test func eachClickPlacesTheBadgeBeforeAsOneStep() {
        let editor = badgeEditor()
        editor.badgeClick(at: pt(12, 12))
        #expect(editor.pendingBadge?.value == 1)
        #expect(editor.history.undoCount == 0)

        editor.badgeClick(at: pt(40, 12))
        #expect(editor.pendingBadge?.value == 2)
        #expect(editor.stepNames == ["Step Badge"])

        editor.commitPendingBadge()
        #expect(editor.pendingBadge == nil)
        #expect(editor.stepNames == ["Step Badge", "Step Badge"])
        #expect(editor.nextBadge == 3)
    }

    @Test func numbersAndLettersCountSeparately() {
        let editor = badgeEditor()
        editor.badgeClick(at: pt(12, 12))
        editor.badgeClick(at: pt(40, 12))
        editor.commitPendingBadge()
        #expect(editor.nextBadge == 3)

        editor.badgeStyle = .letters
        #expect(editor.nextBadge == 1)
        editor.badgeClick(at: pt(12, 40))
        #expect(editor.pendingBadgeSpec?.label == "A")
        editor.commitPendingBadge()
        #expect(editor.nextBadge == 2)

        editor.badgeStyle = .numbers
        #expect(editor.nextBadge == 3)
        editor.badgeClick(at: pt(40, 40))
        #expect(editor.pendingBadgeSpec?.label == "3")
    }

    @Test func undoStepsTheCountBackAndRedoForward() {
        let editor = badgeEditor()
        editor.badgeClick(at: pt(12, 12))
        editor.badgeClick(at: pt(40, 12))
        editor.commitPendingBadge()
        #expect(editor.nextBadge == 3)

        editor.undo()
        #expect(editor.nextBadge == 2)
        editor.undo()
        #expect(editor.nextBadge == 1)
        editor.redo()
        #expect(editor.nextBadge == 2)
        editor.redo()
        #expect(editor.nextBadge == 3)
    }

    @Test func undoingALetterStepsBackOnlyTheLetters() {
        let editor = badgeEditor()
        editor.badgeClick(at: pt(12, 12))
        editor.badgeClick(at: pt(40, 12))
        editor.commitPendingBadge()
        editor.badgeStyle = .letters
        editor.badgeClick(at: pt(12, 40))
        editor.commitPendingBadge()

        editor.undo()
        #expect(editor.nextBadge == 1)
        editor.badgeStyle = .numbers
        #expect(editor.nextBadge == 3)
    }

    /// ⌘Z with a badge still being placed removes just that badge, and its number is used again.
    @Test func undoWhilePlacingRemovesThatBadgeAndReusesItsNumber() {
        let editor = badgeEditor()
        editor.badgeClick(at: pt(12, 12))
        editor.badgeClick(at: pt(40, 12))
        let placed = editor.imageHash
        #expect(editor.history.undoCount == 1)

        editor.undo()
        #expect(editor.pendingBadge == nil)
        #expect(editor.history.undoCount == 1)
        #expect(editor.imageHash == placed)
        #expect(editor.nextBadge == 2)
    }

    @Test func pressingOnThePendingBadgeMovesItWithoutPlacingIt() {
        let editor = badgeEditor()
        editor.badgeClick(at: pt(20, 20))
        editor.beginBadge(at: pt(21, 20), secondary: false)
        editor.continueBadge(to: pt(31, 30))
        editor.endBadge()
        #expect(editor.pendingBadge?.center == pt(30, 30))
        #expect(editor.pendingBadge?.value == 1)
        #expect(editor.history.undoCount == 0)
    }

    @Test func undoingAPlacedBadgeRestoresThePixels() {
        let editor = badgeEditor()
        let before = editor.imageHash
        editor.badgeClick(at: pt(20, 20))
        editor.commitPendingBadge()
        #expect(editor.imageHash != before)
        editor.undo()
        #expect(editor.imageHash == before)
    }

    @Test func aLockedLayerRefusesANewBadge() {
        let editor = badgeEditor()
        editor.setLayerLocked(true, at: 0)
        var refusals = 0
        editor.onRefused = { refusals += 1 }
        editor.badgeClick(at: pt(20, 20))
        #expect(refusals == 1)
        #expect(editor.pendingBadge == nil)
        #expect(editor.nextBadge == 1)
    }
}
