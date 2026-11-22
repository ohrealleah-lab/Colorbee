import ColorbeeCore
import Testing
@testable import Colorbee

/// The Adjust Photo panel's own undo, and Esc asking before it discards changes (stage 34a; §23, 2026-11-20).
@MainActor
@Suite(.serialized)
struct PhotoPanelUndoTests {
    private func picture() -> Editor {
        let editor = makeEditor(width: 24, height: 16)
        let buffer = editor.canvas.activeLayer.buffer
        for y in 0..<16 { for x in 0..<24 { buffer.row(y)[x] = Pixel(r: UInt8(40 + x * 6), g: UInt8(90 + y * 4), b: 120) } }
        return editor
    }

    /// A slider dragged and let go, as the panel does it.
    private func drag(_ editor: Editor, _ slider: PhotoAdjustments.Slider, to value: Double) {
        var edit = editor.photoEdit
        edit.adjustments[slider] = value
        editor.setPhotoEdit(edit)
        editor.settlePhotoStep()
    }

    @Test func undoAndRedoStepThroughThePanelThenApplyIsOneStep() {
        let editor = picture()
        let before = editor.imageHash
        let documentUndo = editor.undoActionName
        editor.beginEffect(.adjustPhoto)
        drag(editor, .exposure, to: 30)
        drag(editor, .contrast, to: 20)
        #expect(editor.photoUndoName == "Contrast")

        editor.undoPhotoStep()
        #expect(editor.photoEdit.adjustments[.contrast] == 0 && editor.photoEdit.adjustments[.exposure] == 30)
        #expect(editor.photoUndoName == "Exposure" && editor.photoRedoName == "Contrast")
        editor.redoPhotoStep()
        #expect(editor.photoEdit.adjustments[.contrast] == 20)
        // The document's own history isn't touched while the panel is open.
        #expect(editor.undoActionName == documentUndo)

        editor.applyEffect()
        #expect(editor.activeEffect == nil && editor.imageHash != before)
        editor.undo()
        #expect(editor.imageHash == before)
    }

    @Test func undoingEverythingLeavesNothingToAskAbout() {
        let editor = picture()
        editor.beginEffect(.adjustPhoto)
        drag(editor, .shadows, to: 25)
        #expect(editor.photoPanelHasChanges)
        editor.undoPhotoStep()
        #expect(editor.photoUndoName == nil && !editor.photoPanelHasChanges)
        editor.escapeEffect()
        #expect(!editor.asksToDiscardPhoto && editor.activeEffect == nil)
    }

    @Test func escAsksOnlyWhenSomethingChanged() {
        let editor = picture()
        let before = editor.imageHash
        editor.beginEffect(.adjustPhoto)
        editor.escapeEffect()
        #expect(editor.activeEffect == nil && !editor.asksToDiscardPhoto)

        editor.beginEffect(.adjustPhoto)
        drag(editor, .warmth, to: 40)
        editor.escapeEffect()
        #expect(editor.asksToDiscardPhoto && editor.activeEffect == .adjustPhoto)
        #expect(editor.photoEdit.adjustments[.warmth] == 40)

        // Discard.
        editor.cancelEffect()
        #expect(editor.activeEffect == nil && !editor.asksToDiscardPhoto && editor.imageHash == before)
    }

    @Test func otherEffectBarsStillCancelOnEsc() {
        let editor = picture()
        editor.beginEffect(.gaussianBlur)
        editor.effectValues = [12]
        editor.escapeEffect()
        #expect(editor.activeEffect == nil && !editor.asksToDiscardPhoto)
    }

    @Test func autoIsOneStepAndItsMarksComeBack() {
        let editor = picture()
        editor.beginEffect(.adjustPhoto)
        editor.autoPhoto()
        editor.settlePhotoStep(named: "Auto")
        let marked = editor.photoAutoMoved
        #expect(!marked.isEmpty && editor.photoUndoName == "Auto")
        let first = marked.sorted { $0.rawValue < $1.rawValue }[0]
        drag(editor, first, to: 0)
        #expect(!editor.photoAutoMoved.contains(first))
        editor.undoPhotoStep()
        #expect(editor.photoAutoMoved == marked)
        editor.undoPhotoStep()
        #expect(editor.photoAutoMoved.isEmpty && editor.photoEdit == PhotoEdit())
    }

    @Test func aChangeNotYetFinishedIsWhatUndoTakesBack() {
        let editor = picture()
        editor.beginEffect(.adjustPhoto)
        drag(editor, .exposure, to: 10)
        var edit = editor.photoEdit
        edit.adjustments[.vibrance] = 50
        editor.setPhotoEdit(edit)
        #expect(editor.photoUndoName == "Vibrance" && editor.photoRedoName == nil)
        editor.undoPhotoStep()
        #expect(editor.photoEdit.adjustments[.vibrance] == 0 && editor.photoEdit.adjustments[.exposure] == 10)
    }

    @Test func stepsGoWhenThePanelCloses() {
        let editor = picture()
        editor.beginEffect(.adjustPhoto)
        drag(editor, .exposure, to: 10)
        editor.cancelEffect()
        editor.beginEffect(.adjustPhoto)
        #expect(editor.photoUndoName == nil && editor.photoRedoName == nil)
    }

    // MARK: Review round 13 (AK)

    /// Esc while still dragging with the hand keeps the drag as its own step (review AK, finding 1).
    @Test func escDuringAHandDragKeepsItAsItsOwnStep() {
        let editor = picture()
        editor.beginEffect(.adjustPhoto)
        editor.togglePicturePick(.toneCurve)
        #expect(editor.beginPictureDrag(at: pt(4, 4), viewY: 300))
        editor.continuePictureDrag(viewY: 260)
        editor.cancelPicturePick()
        editor.endPictureDrag()
        #expect(editor.photoUndoName == "Tone Curve" && editor.photoSteps.settled == editor.photoPanelState)
        drag(editor, .exposure, to: 20)
        #expect(editor.photoUndoName == "Exposure")
        editor.cancelEffect()
    }

    /// ⌘Z in the middle of a hand drag ends it, so what it takes back stays taken back (review AK, finding 3).
    @Test func undoInTheMiddleOfAHandDragStaysUndone() {
        let editor = picture()
        editor.beginEffect(.adjustPhoto)
        editor.togglePicturePick(.toneCurve)
        #expect(editor.beginPictureDrag(at: pt(4, 4), viewY: 300))
        editor.continuePictureDrag(viewY: 260)
        editor.undoPhotoStep()
        editor.continuePictureDrag(viewY: 200)
        editor.endPictureDrag()
        #expect(editor.photoEdit.withoutViews == PhotoEdit() && editor.photoRedoName == "Tone Curve")
        editor.cancelEffect()
    }
}
