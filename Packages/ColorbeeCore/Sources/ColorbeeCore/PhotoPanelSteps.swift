/// Undo and redo inside the Adjust Photo panel (§23, 2026-11-20). Each finished change (a slider let go, Auto, a filter,
/// Paste Settings, Reset, an eyedropper click, a hand drag) is one step. The steps belong to the open panel: Apply is
/// still one step in the document's history, and they go when the panel closes.
public struct PhotoPanelSteps: Sendable {
    /// The panel's settings, with the sliders Auto set (they're marked in the panel, so undo brings the marks back).
    public struct State: Sendable, Equatable {
        public var edit: PhotoEdit
        public var autoMoved: Set<PhotoAdjustments.Slider>

        public init(edit: PhotoEdit = PhotoEdit(), autoMoved: Set<PhotoAdjustments.Slider> = []) {
            // Views (Masking's edge mask, Point Color's Range) are never steps.
            self.edit = edit.withoutViews
            self.autoMoved = autoMoved
        }
    }

    private struct Step: Sendable {
        let state: State
        let name: String
    }

    /// The settings as of the last finished change.
    public private(set) var settled: State
    /// Each holds the settings from before its step.
    private var undoSteps: [Step] = []
    /// Each holds the settings from after its step.
    private var redoSteps: [Step] = []

    public init(start: State = State()) {
        settled = start
    }

    public var undoName: String? { undoSteps.last?.name }
    public var redoName: String? { redoSteps.last?.name }
    /// Whether the settings differ from where the panel started.
    public var hasChanges: Bool { !undoSteps.isEmpty }

    /// Records `now` as a step if it differs from the last finished change. `name` defaults to what changed.
    @discardableResult
    public mutating func settle(_ now: State, named name: String? = nil) -> Bool {
        guard now != settled else { return false }
        undoSteps.append(Step(state: settled, name: name ?? Self.name(from: settled.edit, to: now.edit)))
        redoSteps = []
        settled = now
        return true
    }

    /// The settings to show after undoing the newest step, or nil if there's none. A change not yet finished is
    /// finished first, so it's what goes.
    public mutating func undo(from current: State) -> State? {
        settle(current)
        guard let step = undoSteps.popLast() else { return nil }
        redoSteps.append(Step(state: settled, name: step.name))
        settled = step.state
        return step.state
    }

    public mutating func redo() -> State? {
        guard let step = redoSteps.popLast() else { return nil }
        undoSteps.append(Step(state: settled, name: step.name))
        settled = step.state
        return step.state
    }

    /// What a change did, for Edit ▸ Undo: the one slider or section that changed, or "Changes" when several did.
    public static func name(from old: PhotoEdit, to new: PhotoEdit) -> String {
        var names: [String] = PhotoAdjustments.Slider.allCases.filter { old.adjustments[$0] != new.adjustments[$0] }.map(\.title)
        if old.filter?.name != new.filter?.name { names.append("Filter") }
        if old.filterIntensity != new.filterIntensity, old.filter?.name == new.filter?.name { names.append("Intensity") }
        if old.toneCurve != new.toneCurve { names.append("Tone Curve") }
        if old.mixer != new.mixer { names.append("Color Mixer") }
        if old.pointColors != new.pointColors { names.append("Point Color") }
        if old.grading != new.grading { names.append("Color Grading") }
        if old.detail != new.detail {
            let was = old.detail ?? PhotoDetail(), now = new.detail ?? PhotoDetail()
            let sharpening = was.radius != now.radius || was.sharpnessDetail != now.sharpnessDetail || was.masking != now.masking
            names.append(sharpening ? "Sharpness" : "Noise Reduction")
        }
        if old.effects != new.effects {
            let was = old.effects ?? PhotoEffects(), now = new.effects ?? PhotoEffects()
            let grain = was.grainSize != now.grainSize || was.grainRoughness != now.grainRoughness
            names.append(grain ? "Grain" : "Vignette")
        }
        let unique = names.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        if unique.count == 1 { return unique[0] }
        return new.withoutViews == PhotoEdit() ? "Reset" : "Changes"
    }
}
