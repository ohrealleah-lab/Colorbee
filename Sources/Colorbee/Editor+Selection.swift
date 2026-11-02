import ColorbeeCore
import CoreGraphics
import Foundation
import Observation

extension Editor {
    // MARK: Selection dragging

    /// Whether a drag starting at `point` would move the selection rather than start a new one.
    func selectionContains(_ point: Point2D) -> Bool {
        canvas.selection.contains(IntPoint(containing: point))
    }

    /// The handle under a view point, if the selection's handles are showing there.
    func selectionHandle(atView point: Point2D) -> SelectionHandle? {
        guard tool.isSelectionTool, marqueePreview == nil, let rect = canvas.selection.bounds else { return nil }
        // On a selection small on screen, the handles would cover it all; inside it, a press moves it (review I, finding 15).
        if min(Double(rect.width), Double(rect.height)) * viewport.zoom < 24, selectionContains(viewport.imagePoint(fromView: point)) { return nil }
        return nearestHandle(SelectionHandle.allCases.map { ($0, $0.point(on: rect)) }, to: point)
    }

    /// The handle closest to a view point, if one is within reach. On a tiny box the handles overlap,
    /// and taking the first one in range would always pick a left or top one.
    func nearestHandle(_ handles: [(handle: SelectionHandle, point: Point2D)], to point: Point2D) -> SelectionHandle? {
        handles
            .map { handle, center -> (SelectionHandle, Double) in
                let view = viewport.viewPoint(fromImage: center)
                return (handle, max(abs(view.x - point.x), abs(view.y - point.y)))
            }
            .filter { $0.1 <= 6 }
            .min { $0.1 < $1.1 }?
            .0
    }

    func beginResize(_ handle: SelectionHandle, at point: Point2D) {
        guard !refusedBecauseLocked() else { return }
        finishInteractions()
        guard let rect = canvas.selection.bounds else { return }
        selectionDrag = .resize(edit: nil, handle: handle, original: rect, grab: point)
    }

    func beginSelectionDrag(at point: Point2D, modifiers: DragModifiers) {
        guard tool.isSelectionTool else { return }
        finishInteractions()
        // The wand always selects when a modifier is held, so it can add to or subtract from a selection.
        let wandCombining = tool == .magicWand && (modifiers.shift || modifiers.option)
        if !wandCombining, selectionContains(point), let origin = canvas.selection.bounds.map({ IntPoint(x: $0.minX, y: $0.minY) }) {
            // Moving selected pixels changes the layer; drawing a new outline doesn't.
            guard !refusedBecauseLocked() else { return }
            selectionDrag = .move(edit: nil, grab: point, origin: origin, smear: modifiers.shift, duplicate: modifiers.option)
            return
        }
        let mode: SelectionCombineMode = switch (modifiers.shift, modifiers.option) {
        case (true, true): .intersect
        case (true, false): .add
        case (false, true): .subtract
        case (false, false): .replace
        }
        switch tool {
        case .magicWand:
            // A floating paste is placed first, so the wand sees it rather than what's under it (review I, finding 2).
            placeFloatingKeepingOutline()
            let seed = IntPoint(containing: point)
            if wandMode == .object { return selectObject(at: seed, mode: mode) }
            let sampled = wandSamplesAllLayers ? canvas.flattened() : canvas.paintLayer.buffer
            let mask = SelectionMask.magicWand(in: sampled, at: seed, tolerance: wandTolerance, contiguous: wandContiguous)
            recordingChanges {
                SelectionActions.select(mask, mode: mode, canvas: canvas, history: history, context: selectionContext)
            }
            selectionDidChange()
            return
        case .lassoSelect:
            selectionDrag = .lasso(points: [point], mode: mode)
        case .ellipseSelect:
            selectionDrag = .marquee(shape: .ellipse, start: point, mode: mode, shiftHeldAtStart: modifiers.shift, shiftReleased: false)
        default:
            selectionDrag = .marquee(shape: .rectangle, start: point, mode: mode, shiftHeldAtStart: modifiers.shift, shiftReleased: false)
        }
        updateSelectionPreview(to: point, shiftDown: modifiers.shift)
    }

    func continueSelectionDrag(to point: Point2D, shiftDown: Bool) {
        switch selectionDrag {
        case .marquee, .lasso:
            updateSelectionPreview(to: point, shiftDown: shiftDown)
        case .move(var edit, let grab, let origin, let smear, let duplicate):
            if edit == nil {
                edit = SelectionActions.beginMove(duplicate: duplicate, canvas: canvas, history: history, context: selectionContext)
                guard edit != nil else {
                    selectionDrag = nil
                    return
                }
            }
            let target = IntPoint(
                x: origin.x + Int((point.x - grab.x).rounded()),
                y: origin.y + Int((point.y - grab.y).rounded())
            )
            if let edit, let destination = canvas.selection.floating?.destination,
               destination.minX != target.x || destination.minY != target.y {
                SelectionActions.move(to: target, smear: smear, edit: edit, canvas: canvas, context: selectionContext)
                selectionDidChange()
            }
            selectionDrag = .move(edit: edit, grab: grab, origin: origin, smear: smear, duplicate: duplicate)
        case .resize(var edit, let handle, let original, let grab):
            if edit == nil {
                // Resizing a marquee lifts its pixels first.
                edit = SelectionActions.beginMove(duplicate: false, named: "Resize Selection", canvas: canvas, history: history, context: selectionContext)
                guard edit != nil else {
                    selectionDrag = nil
                    return
                }
            }
            let delta = Point2D(x: point.x - grab.x, y: point.y - grab.y)
            SelectionActions.resize(to: handle.resize(original, by: delta, keepProportions: shiftDown), canvas: canvas)
            selectionDrag = .resize(edit: edit, handle: handle, original: original, grab: grab)
            selectionDidChange()
        case nil:
            break
        }
    }

    /// Finishes the drag. Pass nil to finish without a final pointer position.
    func endSelectionDrag(at point: Point2D?) {
        guard let drag = selectionDrag else { return }
        selectionDrag = nil
        switch drag {
        case .marquee(_, let start, let mode, _, _):
            // A click is a press that moves under 2 points on screen, at any zoom (review I, finding 14).
            let reach = 2 / viewport.zoom
            let clicked = point.map { abs($0.x - start.x) < reach && abs($0.y - start.y) < reach } ?? false
            commitSelectionPreview(deselecting: clicked && mode == .replace)
        case .lasso(let points, let mode):
            commitSelectionPreview(deselecting: points.count < 3 && mode == .replace)
        case .move(let edit, _, _, _, _), .resize(let edit, _, _, _):
            if let edit { recordingChanges { history.commit(edit) } }
        }
        selectionDidChange()
    }

    /// Interrupted mid-drag (say, by a tool key): a marquee or lasso still being drawn is dropped and the
    /// earlier selection stays, while a move or resize keeps what's already been done.
    func cancelOrEndSelectionDrag() {
        switch selectionDrag {
        case .marquee, .lasso:
            selectionDrag = nil
            marqueePreview = nil
            selectionDidChange()
        case .move, .resize:
            endSelectionDrag(at: nil)
        case nil:
            break
        }
    }

    private func commitSelectionPreview(deselecting: Bool) {
        var preview = marqueePreview
        if selectionFeather >= 0.5, let drawn = drawnSelection, let shape = drawn.shape {
            preview = SelectionMask.combine(canvas.selection.outline, with: shape.feathered(radius: selectionFeather, clippedTo: canvas.bounds),
                                            mode: drawn.mode)
        }
        drawnSelection = nil
        marqueePreview = nil
        recordingChanges {
            if deselecting {
                SelectionActions.deselect(canvas: canvas, history: history, context: selectionContext)
            } else {
                SelectionActions.select(preview, mode: .replace, canvas: canvas, history: history, context: selectionContext)
            }
        }
    }

    private func updateSelectionPreview(to point: Point2D, shiftDown: Bool) {
        let shape: SelectionMask?
        let mode: SelectionCombineMode
        switch selectionDrag {
        case .marquee(let kind, let start, let combine, let shiftHeldAtStart, var shiftReleased):
            if !shiftDown { shiftReleased = true }
            // Shift held from the start picks "add"; it only constrains once released and pressed again.
            let constrain = shiftDown && (!shiftHeldAtStart || shiftReleased)
            selectionDrag = .marquee(shape: kind, start: start, mode: combine, shiftHeldAtStart: shiftHeldAtStart, shiftReleased: shiftReleased)
            shape = SelectionActions.marquee(kind, from: start, to: point, constrain: constrain, in: canvas.bounds)
            mode = combine
        case .lasso(var points, let combine):
            if let last = points.last, abs(last.x - point.x) + abs(last.y - point.y) >= 1 {
                points.append(point)
            }
            selectionDrag = .lasso(points: points, mode: combine)
            shape = SelectionMask.polygon(points, clippedTo: canvas.bounds)
            mode = combine
        default:
            return
        }
        drawnSelection = (shape, mode)
        marqueePreview = SelectionMask.combine(canvas.selection.outline, with: shape, mode: mode)
        selectionBounds = marqueePreview?.bounds
        onRender()
    }

    // MARK: Selection commands

    func performSelectionCommand(_ command: () -> Void) {
        finishInteractions()
        recordingChanges(command)
        selectionDidChange()
    }

    /// Runs `body` and tells the document it changed if a history step was recorded.
    func recordingChanges(_ body: () -> Void) {
        let revision = history.revision
        history.thumbnailKey = selectionContext.transparentKey
        body()
        if history.revision != revision { noteEdited() }
    }

    /// The bookkeeping every recorded step needs, wherever it was recorded. Not for page changes (`changePages`),
    /// which are undone on their own list.
    func noteEdited() {
        stopFillForChange()
        // A page edit: page changes made before it can't be undone any more, as edits work in an image.
        pages.noteEdit()
        undone = []
        onDocumentChange(.done)
        layersRevision += 1
    }

    func selectAll() {
        if !tool.isSelectionTool { tool = .rectangleSelect }
        performSelectionCommand { SelectionActions.selectAll(canvas: canvas, history: history, context: selectionContext) }
    }

    func deselect() {
        performSelectionCommand { SelectionActions.deselect(canvas: canvas, history: history, context: selectionContext) }
    }

    // MARK: Edit ▸ Feather… and Modify Selection (FR-3.4, FR-9.7 item 3)

    /// A Match Tone being worked out: `plan` is set before `done` is signalled.
    final class PendingTone: @unchecked Sendable {
        let revision: Int
        let layer: LayerID
        let page: UUID
        let done = DispatchSemaphore(value: 0)
        var plan: UnsafeTransfer<ToneMatch.Plan?>?

        init(revision: Int, layer: LayerID, page: UUID) {
            self.revision = revision
            self.layer = layer
            self.page = page
        }
    }

    func beginSelectionChange(_ change: SelectionModification) {
        finishInteractions()
        placeFloatingKeepingOutline()
        guard let mask = canvas.selection.marquee else { return onRefused() }
        selectionChangeOriginal = mask
        selectionChange = change
        setSelectionChangeRadius(Double(change.startingRadius))
    }

    /// The slider's radius shows at once; the changed selection is worked out in the background, with moves made
    /// meanwhile merged, so a big selection doesn't stall the slider (review O, finding 12; review P, finding 5).
    func setSelectionChangeRadius(_ radius: Double) {
        guard selectionChangeOriginal != nil else { return }
        selectionChangeRadius = min(100, max(1, radius.rounded()))
        isWorkingOnSelectionChange = selectionChangeRadius != selectionChangeShown
        refreshSelectionChangePreview()
    }

    private func refreshSelectionChangePreview() {
        guard !selectionChangeRunning, let original = selectionChangeOriginal, let change = selectionChange,
              selectionChangeRadius != selectionChangeShown else { return }
        selectionChangeRunning = true
        let session = selectionChangeSession, bounds = canvas.bounds, radius = selectionChangeRadius
        Task.detached(priority: .userInitiated) { [weak self] in
            let mask = UnsafeTransfer(change.applied(to: original, radius: Int(radius), clippedTo: bounds))
            await MainActor.run { [weak self] in self?.showSelectionChangePreview(mask.value, radius: radius, session: session) }
        }
    }

    private func showSelectionChangePreview(_ mask: SelectionMask?, radius: Double, session: Int) {
        guard session == selectionChangeSession else { return }
        selectionChangeRunning = false
        // With nothing left, the selection as it was stays on show, and the sheet says why OK is off.
        marqueePreview = mask
        selectionChangeLeavesNothing = mask == nil
        selectionChangeShown = radius
        isWorkingOnSelectionChange = radius != selectionChangeRadius
        onRender()
        if !isWorkingOnSelectionChange, appliesSelectionChangeWhenShown { return applySelectionChange() }
        refreshSelectionChangePreview()
    }

    /// OK keeps exactly the radius in the box: if its selection is still being worked out, it's applied when ready,
    /// rather than worked out here and holding up the window.
    func applySelectionChange() {
        guard selectionChange != nil else { return }
        if selectionChangeRadius != selectionChangeShown {
            appliesSelectionChangeWhenShown = true
            return
        }
        guard !selectionChangeLeavesNothing else { return onRefused() }
        let changed = marqueePreview
        endSelectionChange()
        recordingChanges { SelectionActions.select(changed, mode: .replace, canvas: canvas, history: history, context: selectionContext) }
        selectionDidChange()
    }

    func cancelSelectionChange() {
        endSelectionChange()
        onRender()
    }

    private func endSelectionChange() {
        selectionChangeOriginal = nil
        selectionChange = nil
        marqueePreview = nil
        selectionChangeShown = nil
        selectionChangeRunning = false
        selectionChangeLeavesNothing = false
        isWorkingOnSelectionChange = false
        appliesSelectionChangeWhenShown = false
        selectionChangeSession += 1
    }

    // MARK: Edit ▸ Color Range… and Luminance Range… (FR-9.7 item 3)

    private var rangeSettings: RangeSettings? {
        func value(_ index: Int) -> Double { effectValues[safe: index] ?? 0 }
        switch activeEffect {
        case .colorRange: return .color(ColorRange(colors: rangeColors, fuzziness: value(0)))
        case .luminanceRange: return .luminance(LuminanceRange(lower: value(0), upper: value(1), smoothness: value(2)))
        case .graduatedSelection: return graduatedLine.map { .graduated($0) }
        default: return nil
        }
    }

    private var rangeCombineMode: SelectionCombineMode {
        let position = activeEffect?.parameters.firstIndex { $0.options == EffectKind.combineOptions } ?? 0
        let index = Int((effectValues[safe: position] ?? 0).rounded())
        return [.replace, .add, .subtract, .intersect][min(max(index, 0), 3)]
    }

    /// Whether the range reads everything shown. An adjustment layer has no pixels of its own to read, so on one it
    /// always does (my choice, §23).
    var rangeSamplesAllLayers: Bool {
        get { wandSamplesAllLayers || !canvas.activeLayer.isPixelLayer }
        set {
            wandSamplesAllLayers = newValue
            guard activeEffect?.choosesSelection == true else { return }
            rangeSource = nil
            rangeShown = nil
            refreshRangePreview()
        }
    }

    func beginRange() {
        rangeColors = []
        graduatedLine = nil
        graduatedMoving = nil
        rangeShown = nil
        rangeMask = nil
        rangeSource = nil
    }

    func endRange() {
        if activeEffect?.choosesSelection == true { marqueePreview = nil }
        rangeColors = []
        graduatedLine = nil
        graduatedMoving = nil
        rangeShown = nil
        rangeRunning = false
        rangeMask = nil
        rangeSource = nil
        rangeSession += 1
    }

    private func rangeSampled() -> PixelBuffer {
        if let rangeSource { return rangeSource }
        // A graduated selection reads no pixels, only the canvas's size.
        if activeEffect == .graduatedSelection { return canvas.paintLayer.buffer }
        let source = rangeSamplesAllLayers ? canvas.flattened() : canvas.paintLayer.buffer
        rangeSource = source
        return source
    }

    /// A click picks the color there, a 5 × 5 average like the other eyedroppers; Shift-click adds it to those
    /// picked. A click where there's nothing to read beeps.
    func pickRangeColor(at point: Point2D, adding: Bool) {
        let pixel = IntPoint(containing: point)
        guard canvas.bounds.contains(pixel),
              let color = rangeSampled().averageColor(in: IntRect(x: pixel.x - 2, y: pixel.y - 2, width: 5, height: 5)) else { return onRefused() }
        rangeColors = adding ? rangeColors + [color] : [color]
        refreshRangePreview()
    }

    /// The range's selection is worked out in the background, with changes made meanwhile merged, then combined with
    /// the selection there already for the tint.
    func refreshRangePreview() {
        guard !rangeRunning, let settings = rangeSettings else { return showRangePreview() }
        guard settings != rangeShown else { return showRangePreview() }
        rangeRunning = true
        let session = rangeSession, source = UnsafeTransfer(rangeSampled())
        Task.detached(priority: .userInitiated) { [weak self] in
            let mask = settings.selection(in: source.value)
            let result = UnsafeTransfer(mask)
            await MainActor.run { [weak self] in
                guard let self, session == self.rangeSession else { return }
                self.rangeRunning = false
                self.rangeMask = result.value
                self.rangeShown = settings
                self.refreshRangePreview()
            }
        }
    }

    private func showRangePreview() {
        // Nothing clicked or drawn yet: the selection as it is, untinted.
        if rangeSettings == nil || activeEffect == .colorRange && rangeColors.isEmpty {
            marqueePreview = nil
        } else {
            marqueePreview = SelectionMask.combine(canvas.selection.marquee, with: rangeMask, mode: rangeCombineMode)
        }
        onRender()
    }

    /// Return makes the range the selection, combined as the bar says; with no color clicked yet there's nothing to
    /// take. It's no more an undo step than any other selection.
    func applyRange() {
        guard let settings = rangeSettings else { return onRefused() }
        if activeEffect == .colorRange, rangeColors.isEmpty { return onRefused() }
        let mask: SelectionMask?
        if settings == rangeShown {
            mask = rangeMask
        } else {
            // The newest settings aren't worked out yet: OK keeps exactly what's in the bar.
            mask = settings.selection(in: rangeSampled())
        }
        let mode = rangeCombineMode
        endEffectSession()
        activeEffect = nil
        recordingChanges { SelectionActions.select(mask, mode: mode, canvas: canvas, history: history, context: selectionContext) }
        if !tool.isSelectionTool { tool = .rectangleSelect }
        selectionDidChange()
    }

    /// Near an end of the line, a drag moves that end; anywhere else, it draws a new line from there.
    func beginGraduatedDrag(at point: Point2D, viewPoint: Point2D) {
        if let line = graduatedLine {
            let ends: [(GraduatedEnd, Point2D)] = [(.end, line.end), (.start, line.start)]
            if let near = ends.first(where: { distance(viewport.viewPoint(fromImage: $0.1), viewPoint) <= 12 }) {
                graduatedMoving = near.0
                return
            }
        }
        graduatedMoving = .end
        graduatedLine = GraduatedSelection(start: point, end: point)
        refreshRangePreview()
    }

    /// Shift keeps the line across, down or at 45°, measured from the end that isn't moving.
    func continueGraduatedDrag(to point: Point2D, constrain: Bool) {
        guard var line = graduatedLine, let moving = graduatedMoving else { return }
        switch moving {
        case .end: line.end = constrain ? GraduatedSelection.constrained(point, from: line.start) : point
        case .start: line.start = constrain ? GraduatedSelection.constrained(point, from: line.end) : point
        }
        graduatedLine = line
        refreshRangePreview()
    }

    /// A guide at right angles to `line` through `point`, reaching across the canvas and stopping at its edges.
    func guideAcross(_ line: GraduatedSelection, through point: Point2D) -> (Point2D, Point2D)? {
        let dx = line.end.x - line.start.x, dy = line.end.y - line.start.y
        let length = hypot(dx, dy)
        guard length > 0 else { return nil }
        let across = Point2D(x: -dy / length, y: dx / length)
        // Along the guide, the part inside the canvas (Liang–Barsky clipping).
        var low = -Double.infinity, high = Double.infinity
        for (origin, direction, size) in [(point.x, across.x, Double(canvas.size.width)), (point.y, across.y, Double(canvas.size.height))] {
            if direction == 0 {
                guard origin >= 0 && origin <= size else { return nil }
            } else {
                let a = (0 - origin) / direction, b = (size - origin) / direction
                low = max(low, min(a, b))
                high = min(high, max(a, b))
            }
        }
        guard low < high else { return nil }
        return (Point2D(x: point.x + across.x * low, y: point.y + across.y * low),
                Point2D(x: point.x + across.x * high, y: point.y + across.y * high))
    }

    /// The preset whose From and To the bar's values match, shown chosen; nil once the handles leave every preset.
    var luminancePresetIndex: Int? {
        guard activeEffect == .luminanceRange, effectValues.count > 1 else { return nil }
        return Self.luminancePresets.firstIndex { $0.range.lower == effectValues[0] && $0.range.upper == effectValues[1] }
    }

    /// Luminance Range's Shadows, Midtones and Highlights choices.
    func setLuminanceRange(_ range: LuminanceRange) {
        guard activeEffect == .luminanceRange, effectValues.count > 1 else { return }
        effectValues[0] = range.lower
        effectValues[1] = range.upper
    }

    func invertSelection() {
        if !tool.isSelectionTool { tool = .rectangleSelect }
        performSelectionCommand { SelectionActions.invert(canvas: canvas, history: history, context: selectionContext) }
    }

    func deleteSelection(named name: String = "Delete") {
        guard !refusedBecauseLocked() else { return }
        performSelectionCommand {
            SelectionActions.deleteSelection(named: name, canvas: canvas, history: history, context: selectionContext)
        }
    }

    /// ⌘-arrows: grow or shrink the marquee's outline without touching the pixels.
    func resizeMarquee(byWidth dx: Int, height dy: Int) {
        finishInteractions()
        SelectionActions.resizeMarquee(byWidth: dx, height: dy, canvas: canvas)
        selectionDidChange()
    }

    func nudgeSelection(dx: Int, dy: Int) {
        guard !refusedBecauseLocked() else { return }
        performSelectionCommand {
            SelectionActions.nudge(dx: dx, dy: dy, canvas: canvas, history: history, context: selectionContext)
        }
    }

    /// Copy Merged: the selection as all visible layers show it together.
    func selectedMergedPixels() -> PixelBuffer? {
        finishInteractions()
        return SelectionActions.selectedPixels(canvas: canvas, context: selectionContext, merged: true)
    }

    func selectedPixels() -> PixelBuffer? {
        finishInteractions()
        return SelectionActions.selectedPixels(canvas: canvas, context: selectionContext)
    }

    /// Where Copy's pixels come from on the canvas, recorded with them for Paste in Place (FR-10.1).
    func copiedPlace(merged: Bool) -> IntPoint {
        SelectionActions.selectedPixelsOrigin(canvas: canvas, merged: merged)
    }

    /// Paste in Place: at `place` when any of the image lands on the canvas there; otherwise, or with no place (a
    /// picture copied in another app), where ⌘V puts it (Leah, 2026-10-28).
    func paste(_ image: PixelBuffer, inPlaceAt place: IntPoint?) {
        guard let place, !IntRect(x: place.x, y: place.y, width: image.width, height: image.height).intersection(canvas.bounds).isEmpty else {
            return paste(image)
        }
        paste(image, at: place)
    }

    /// Pastes as a floating selection at the top-left of the visible area (FR-10.1), or at `origin`.
    func paste(_ image: PixelBuffer, at origin: IntPoint? = nil) {
        guard !refusedBecauseLocked() else { return }
        let visibleTopLeft = viewport.imagePoint(fromView: .zero)
        let origin = origin ?? IntPoint(
            x: min(max(0, Int(visibleTopLeft.x.rounded(.down))), canvas.size.width - 1),
            y: min(max(0, Int(visibleTopLeft.y.rounded(.down))), canvas.size.height - 1)
        )
        if !tool.isSelectionTool { tool = .rectangleSelect }
        performSelectionCommand {
            SelectionActions.paste(image, at: origin, canvas: canvas, history: history, context: selectionContext)
        }
        onFocusCanvas()
    }

    func selectionDidChange() {
        selectionBounds = marqueePreview?.bounds ?? canvas.selection.bounds
        if let floating = canvas.selection.floating, floating.destination.size != floating.pixels.size {
            selectionScalePercent = Int((Double(floating.destination.width) / Double(floating.pixels.width) * 100).rounded())
        } else {
            selectionScalePercent = nil
        }
        if canvasSize != canvas.size { canvasDidResize() }
        onRender()
    }
}

// MARK: Object mode on the Magic Wand (Leah, 2026-10-27)

extension Editor {
    /// Selects the thing under the click, as Select Subject finds it: the subject Vision's first look found there,
    /// untangled from its neighbors, or else one a closer look finds, with Refine Edge. Nothing found beeps and leaves
    /// the selection.
    func selectObject(at pixel: IntPoint, mode: SelectionCombineMode) {
        guard !isFindingSubject, canvas.bounds.contains(pixel) else { return onRefused() }
        let layer = canvas.paintLayer
        let key = WandSubjectsKey(canvas: ObjectIdentifier(canvas), layer: wandSamplesAllLayers ? nil : layer.id, revision: history.revision)
        let cached = wandSubjects?.key == key ? wandSubjects : nil
        guard let image = cached?.image ?? (try? ImageCodec.makeCGImage(wandSamplesAllLayers ? canvas.flattened() : layer.buffer,
                                                                          colorSpace: canvas.colorSpace)) else { return onRefused() }
        isFindingSubject = true
        isFindingObject = true
        objectLook += 1
        let look = objectLook
        Task { @MainActor [weak self] in
            let scan = if let cached { cached.scan } else { (try? await SubjectScan.find(in: image)) ?? SubjectScan(size: IntSize(width: image.width, height: image.height), masks: []) }
            var mask = try? await scan.subjectMask(at: pixel, in: image)
            if let found = mask { mask = await RefineEdge.refined(found, in: image) }
            guard let self, self.objectLook == look else { return }
            self.isFindingSubject = false
            self.isFindingObject = false
            // Something changed the image meanwhile, so what was found may no longer fit it.
            guard self.history.revision == key.revision, ObjectIdentifier(self.canvas) == key.canvas, self.canvas.paintLayer.id == layer.id,
                  self.activeStroke == nil, self.activeEffect == nil else {
                return self.showNotice("The image changed while Colorbee was looking. Try again.")
            }
            self.wandSubjects = (key, scan, image)
            guard let mask else { return self.onRefused() }
            self.recordingChanges {
                SubjectActions.select(mask, mode: mode, canvas: self.canvas, history: self.history, context: self.selectionContext)
            }
            self.selectionDidChange()
        }
    }

    /// Esc while Object mode looks: stops it, and nothing changes.
    func cancelObjectSearch() {
        guard isFindingObject else { return }
        objectLook += 1
        isFindingObject = false
        isFindingSubject = false
    }
}
