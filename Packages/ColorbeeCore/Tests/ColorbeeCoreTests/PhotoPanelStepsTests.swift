import Testing
@testable import ColorbeeCore

struct PhotoPanelStepsTests {
    private func state(_ values: [PhotoAdjustments.Slider: Double], auto: Set<PhotoAdjustments.Slider> = []) -> PhotoPanelSteps.State {
        PhotoPanelSteps.State(edit: PhotoEdit(adjustments: PhotoAdjustments(values)), autoMoved: auto)
    }

    @Test func undoAndRedoStepThroughFinishedChanges() {
        var steps = PhotoPanelSteps()
        #expect(steps.undoName == nil && !steps.hasChanges)
        steps.settle(state([.exposure: 20]))
        steps.settle(state([.exposure: 20, .contrast: 30]))
        #expect(steps.undoName == "Contrast")

        #expect(steps.undo(from: steps.settled) == state([.exposure: 20]))
        #expect(steps.undoName == "Exposure" && steps.redoName == "Contrast")
        #expect(steps.undo(from: steps.settled) == state([:]))
        #expect(steps.undo(from: steps.settled) == nil)
        #expect(!steps.hasChanges)

        #expect(steps.redo() == state([.exposure: 20]))
        #expect(steps.redo() == state([.exposure: 20, .contrast: 30]))
        #expect(steps.redo() == nil)
    }

    @Test func aNewChangeDropsWhatCouldBeRedone() {
        var steps = PhotoPanelSteps()
        steps.settle(state([.exposure: 20]))
        _ = steps.undo(from: steps.settled)
        steps.settle(state([.warmth: -10]))
        #expect(steps.redoName == nil && steps.undoName == "Warmth")
    }

    @Test func anUnfinishedChangeIsWhatUndoTakesBack() {
        var steps = PhotoPanelSteps()
        steps.settle(state([.exposure: 20]))
        // Changed but never finished (no slider let go): undo takes it back, not the step before.
        #expect(steps.undo(from: state([.exposure: 20, .shadows: 15])) == state([.exposure: 20]))
        #expect(steps.redo() == state([.exposure: 20, .shadows: 15]))
    }

    @Test func sameSettingsAndViewsAreNoStep() {
        var steps = PhotoPanelSteps()
        let same = steps.settle(state([:]))
        var shown = PhotoEdit()
        shown.showsSharpeningMask = true
        let view = steps.settle(PhotoPanelSteps.State(edit: shown))
        #expect(!same && !view && !steps.hasChanges)
    }

    @Test func autoMarksComeBackWithTheirStep() {
        var steps = PhotoPanelSteps()
        let auto = state([.exposure: 12, .vibrance: 8], auto: [.exposure, .vibrance])
        steps.settle(auto, named: "Auto")
        steps.settle(state([.exposure: 40, .vibrance: 8], auto: [.vibrance]))
        #expect(steps.undo(from: steps.settled) == auto)
        #expect(steps.undoName == "Auto")
    }

    @Test func namesSayWhatChanged() {
        let none = PhotoEdit()
        // Built whole: a section at its start is stored as nil, so setting one field on it would do nothing.
        var toneCurve = ToneCurve()
        toneCurve[.highlights] = 20
        #expect(PhotoPanelSteps.name(from: none, to: PhotoEdit(toneCurve: toneCurve)) == "Tone Curve")
        var effects = PhotoEffects()
        effects.grainSize = 60
        #expect(PhotoPanelSteps.name(from: none, to: PhotoEdit(effects: effects)) == "Grain")
        var detail = PhotoDetail()
        detail.masking = 40
        #expect(PhotoPanelSteps.name(from: none, to: PhotoEdit(detail: detail)) == "Sharpness")
        let several = PhotoEdit(adjustments: PhotoAdjustments([.exposure: 5, .contrast: 5]))
        #expect(PhotoPanelSteps.name(from: none, to: several) == "Changes")
        #expect(PhotoPanelSteps.name(from: several, to: none) == "Reset")
    }
}
