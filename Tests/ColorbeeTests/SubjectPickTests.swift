import ColorbeeCore
import Foundation
import Testing
@testable import Colorbee

/// Select Subject on an image with no subject: the bar asks for a click, and a click looks closer (Leah, 2026-10-27).
/// These run Apple's subject finder, on this Mac.
@MainActor
struct SubjectPickTests {
    private func waitForTheLook(_ editor: Editor) async throws {
        for _ in 0..<400 where editor.isFindingSubject { try await Task.sleep(for: .milliseconds(50)) }
        #expect(!editor.isFindingSubject)
    }

    @Test func withNoSubjectTheBarAsksForAClick() async throws {
        let editor = makeEditor()
        var refusals = 0
        editor.onRefused = { refusals += 1 }
        let revision = editor.history.revision
        editor.findSubject(.select)
        try await waitForTheLook(editor)
        #expect(editor.activeEffect == .pickSubject && !editor.pickHasSubjects)
        // Return has nothing to take, so it beeps and the bar stays.
        editor.applyEffect()
        #expect(refusals == 1 && editor.activeEffect == .pickSubject)
        editor.cancelEffect()
        #expect(editor.activeEffect == nil && editor.history.revision == revision && !editor.hasSelection)
    }

    @Test func aClickOnNothingLooksCloserThenBeeps() async throws {
        let editor = makeEditor()
        var refusals = 0
        editor.onRefused = { refusals += 1 }
        editor.findSubject(.liftToNewLayer)
        try await waitForTheLook(editor)
        editor.beginCanvasToolDrag(at: pt(30, 30), viewPoint: pt(30, 30))
        #expect(editor.isFindingSubject)
        // A second click while it looks waits its turn rather than starting another look.
        editor.beginCanvasToolDrag(at: pt(10, 10), viewPoint: pt(10, 10))
        try await waitForTheLook(editor)
        #expect(refusals == 1)
        #expect(editor.activeEffect == .pickSubject && editor.canvas.layers.count == 1)
        editor.cancelEffect()
    }

    /// Review T, finding 5: Esc mid-look ends it at once, and a new search isn't upset when the old look finishes.
    @Test func cancellingDuringACloserLookClearsItAtOnce() async throws {
        let editor = makeEditor()
        editor.findSubject(.select)
        try await waitForTheLook(editor)
        editor.beginCanvasToolDrag(at: pt(30, 30), viewPoint: pt(30, 30))
        #expect(editor.isFindingSubject)
        editor.cancelEffect()
        #expect(!editor.isFindingSubject && editor.activeEffect == nil)
        editor.findSubject(.select)
        #expect(editor.isFindingSubject)
        try await waitForTheLook(editor)
        #expect(editor.activeEffect == .pickSubject)
        editor.cancelEffect()
    }

    @Test func aClickOffTheImageBeepsWithoutLooking() async throws {
        let editor = makeEditor()
        var refusals = 0
        editor.onRefused = { refusals += 1 }
        editor.findSubject(.select)
        try await waitForTheLook(editor)
        editor.beginCanvasToolDrag(at: pt(-5, 10), viewPoint: pt(-5, 10))
        #expect(refusals == 1 && !editor.isFindingSubject)
        editor.cancelEffect()
    }

    // Shift-click and Return (Leah, 2026-11-01), with two made-up subjects, the left and right halves, so no Vision.
    // The left half is black, so Refine Edge keeps the edge between them where it is.

    private func pickingTwoHalves(_ action: Editor.SubjectAction = .select) throws -> Editor {
        let editor = makeEditor()
        let layer = editor.canvas.paintLayer
        layer.buffer.fill(.black, in: IntRect(x: 0, y: 0, width: 32, height: 64))
        let left = (0..<(64 * 64)).map { $0 % 64 < 32 ? UInt8(255) : 0 }
        let scan = SubjectScan(size: editor.canvas.size, masks: [left, left.map { 255 - $0 }])
        let image = try ImageCodec.makeCGImage(layer.buffer, colorSpace: editor.canvas.colorSpace)
        editor.subjectPick = (scan, image, action, layer.id)
        editor.pickSubjectCount = 2
        editor.pickLabels = SubjectLabelMap(size: scan.size, values: scan.labels())
        editor.beginEffect(.pickSubject)
        return editor
    }

    @Test func returnTakesTheShiftClickedSubjects() async throws {
        let editor = try pickingTwoHalves()
        editor.pickMarked = [1]
        editor.applyEffect()
        // Refine Edge works in the background, and Esc can still stop it meanwhile.
        #expect(editor.isFindingSubject && editor.activeEffect == .pickSubject)
        try await waitUntil { editor.activeEffect == nil }
        #expect(editor.canvas.selection.bounds == IntRect(x: 32, y: 0, width: 32, height: 64))
        #expect(editor.pickMarked.isEmpty && editor.pickLabels == nil && !editor.isFindingSubject)
    }

    @Test func returnWithNoneMarkedTakesThemAll() async throws {
        let editor = try pickingTwoHalves()
        editor.applyEffect()
        try await waitUntil { editor.activeEffect == nil }
        #expect(editor.canvas.selection.bounds == editor.canvas.bounds)
    }

    @Test func escWhileRefiningTakesNothing() async throws {
        let editor = try pickingTwoHalves()
        editor.applyEffect()
        editor.cancelEffect()
        #expect(!editor.isFindingSubject && editor.activeEffect == nil)
        try await Task.sleep(for: .milliseconds(500))
        #expect(!editor.hasSelection)
    }

    @Test func shiftClickingAMarkedSubjectUnmarksItWithoutLooking() throws {
        let editor = try pickingTwoHalves()
        editor.pickMarked = [0, 1]
        editor.beginCanvasToolDrag(at: pt(10, 10), viewPoint: pt(10, 10), adding: true)
        #expect(editor.pickMarked == [1] && !editor.isFindingSubject)
        editor.cancelEffect()
        #expect(editor.pickMarked.isEmpty && editor.pickLabels == nil && editor.subjectPick == nil)
    }

    @Test func theSubjectUnderThePointerIsTinted() throws {
        let editor = try pickingTwoHalves()
        editor.pointer = IntPoint(x: 50, y: 5)
        #expect(editor.pickHoveredLabel == 2)
        editor.pickMarked = [0]
        #expect(editor.pickMarkedBits == 1)
        editor.cancelEffect()
        #expect(editor.pickHoveredLabel == 0)
    }

    // The Magic Wand's Object mode (Leah, 2026-10-27).

    @Test func objectModeOnNothingBeepsAndKeepsTheSelection() async throws {
        let editor = makeEditor()
        var refusals = 0
        editor.onRefused = { refusals += 1 }
        editor.wandMode = .object
        editor.selectTool(.rectangleSelect)
        editor.selectionDrag(from: pt(5, 5), to: pt(20, 20))
        let selection = editor.canvas.selection.bounds
        editor.selectTool(.magicWand)
        editor.beginSelectionDrag(at: pt(40, 40), modifiers: DragModifiers(shift: true))
        #expect(editor.isFindingObject)
        try await waitForTheLook(editor)
        #expect(refusals == 1 && editor.canvas.selection.bounds == selection)
        // The first look is kept for the next click, until the image changes.
        #expect(editor.wandSubjects?.key.revision == editor.history.revision)
    }

    @Test func escStopsObjectModeAndNothingIsSelected() async throws {
        let editor = makeEditor()
        var refusals = 0
        editor.onRefused = { refusals += 1 }
        editor.selectTool(.magicWand)
        editor.wandMode = .object
        editor.beginSelectionDrag(at: pt(40, 40), modifiers: DragModifiers())
        editor.cancelObjectSearch()
        #expect(!editor.isFindingObject && !editor.isFindingSubject)
        try await Task.sleep(for: .seconds(2))
        #expect(refusals == 0 && !editor.hasSelection)
    }
}

/// Tooltips show after half a second in Colorbee (Leah, 2026-10-27), set where nothing is saved.
@MainActor
struct TooltipDelayTests {
    @Test func theDelayIsRegisteredAtHalfASecond() {
        let registered = UserDefaults.standard.volatileDomain(forName: UserDefaults.registrationDomain)
        #expect(registered["NSInitialToolTipDelay"] as? Int == 500)
    }
}
