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
}

/// Tooltips show after half a second in Colorbee (Leah, 2026-10-27), set where nothing is saved.
@MainActor
struct TooltipDelayTests {
    @Test func theDelayIsRegisteredAtHalfASecond() {
        let registered = UserDefaults.standard.volatileDomain(forName: UserDefaults.registrationDomain)
        #expect(registered["NSInitialToolTipDelay"] as? Int == 500)
    }
}
