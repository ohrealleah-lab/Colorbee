import ColorbeeCore
import CoreGraphics
import Foundation
import Observation

extension Editor {
    // MARK: Redact Brush (FR-9.6)

    /// Starts a stroke. Nothing changes until it ends; meanwhile the area shows see-through. It paints where you
    /// paint, whatever is selected.
    func beginRedactStroke(at point: Point2D, secondary: Bool) {
        finishInteractions()
        placeFloatingSelection()
        let area = RedactBrushArea(diameter: redactBrushSize, canvasBounds: canvas.bounds, overlayColor: Pixel(r: 230, g: 40, b: 60, a: 120))
        area.move(to: point)
        redactStroke = (area, StrokePath(start: point, reach: smoothingReach), secondary)
        onRender()
    }

    /// Shift keeps the stroke on one horizontal or vertical line, for a line of text.
    func continueRedactStroke(to point: Point2D, constrain: Bool) {
        guard var stroke = redactStroke else { return }
        stroke.area.move(to: stroke.path.next(point, constrain: constrain))
        redactStroke = stroke
        onRender()
    }

    /// Redacts the area on every layer with pixels under it, as one step, like Batch Redact. Blur and Pixelate are
    /// as strong as the brush is wide, as Auto-Redact's follow the text's height; Solid Fill uses Color 1, or Color 2
    /// with the right button.
    func endRedactStroke() {
        guard let stroke = redactStroke else { return }
        redactStroke = nil
        if let point = stroke.path.catchUp { stroke.area.move(to: point) }
        guard let mask = stroke.area.mask else { return onRender() }
        let strength = max(6, stroke.area.diameter / 3)
        let effect: Effect = switch redactTreatment {
        case .blur: .gaussianBlur(radius: strength)
        case .pixelate: .pixelate(cellSize: Int(strength.rounded()))
        case .solidFill: .solidFill(stroke.secondary ? color2 : color1)
        }
        redactEveryLayer(with: effect, in: mask, named: "Redact Brush")
    }

    /// The see-through area of a Redact Brush or Remove stroke, or of a fill under way, for the screen.
    func areaStrokePicture() -> (pixels: PixelBuffer, origin: IntPoint)? {
        redactStroke?.area.picture ?? retouchStroke?.area.picture ?? fillingArea?.picture
    }

    /// The size of the round brush outline under the pointer, for the tools that paint an area.
    var areaBrushSize: Double? {
        switch tool {
        case .redactBrush: redactBrushSize
        case .retouch: retouchSize
        default: nil
        }
    }

    // MARK: Retouching: brushes (FR-4.6)

    /// Option-click with the Clone Stamp: where to copy from. The next stroke sets the offset.
    func setCloneSource(_ point: Point2D) {
        cloneSource = point
        cloneOffset = nil
        cloneCrosshair = point
        onRender()
    }

    /// The local brushes, Smudge and the Clone Stamp change pixels as you paint; the stroke is one step.
    func beginRetouchBrush(at point: Point2D, pressure: Double) {
        guard !refusedBecauseLocked() else { return }
        let kind = retouchKind
        var offset: IntPoint?
        if kind == .cloneStamp {
            guard let source = cloneSource else {
                showNotice("Option-click where to copy from first")
                return onRefused()
            }
            // Aligned keeps the offset from the first stroke; otherwise each stroke starts again from the source.
            offset = cloneAligned ? cloneOffset : nil
            if offset == nil {
                offset = IntPoint(x: Int((source.x - point.x).rounded()), y: Int((source.y - point.y).rounded()))
                if cloneAligned { cloneOffset = offset }
            }
        }
        finishInteractions()
        placeFloatingSelection()
        let layer = canvas.paintLayer
        let edit = history.beginEdit(kind.name, on: canvas)
        let stroke: Stroke
        if kind == .smudge {
            stroke = SmudgeStroke(diameter: retouchSize, hardness: retouchHardness, strength: retouchStrength, layer: layer, edit: edit)
        } else if let offset {
            // The active layer and those below, as shown: adjustments above apply to the result anyway (Leah, 2026-10-13).
            let source = retouchSamplesAllLayers ? canvas.composited(through: canvas.activeLayerIndex) : nil
            stroke = RetouchStroke(diameter: retouchSize, hardness: retouchHardness, strength: 1, kind: .clone(offset: offset, source: source),
                                   layer: layer, edit: edit)
        } else if let adjustment = kind.adjustment(range: toneRange) {
            stroke = RetouchStroke(diameter: retouchSize, hardness: retouchHardness, strength: retouchStrength, kind: .adjust(adjustment),
                                   layer: layer, edit: edit)
        } else {
            return
        }
        retouchBrush = (stroke, edit, kind, StrokePath(start: point, reach: smoothingReach), offset, pressure)
        moveRetouchBrush(to: point, pressure: pressure)
    }

    func continueRetouchBrush(to point: Point2D, constrain: Bool, pressure: Double) {
        guard var brush = retouchBrush else { return }
        let target = brush.path.next(point, constrain: constrain)
        brush.pressure = pressure
        retouchBrush = brush
        moveRetouchBrush(to: target, pressure: pressure)
    }

    private func moveRetouchBrush(to point: Point2D, pressure: Double) {
        guard let brush = retouchBrush else { return }
        if let offset = brush.offset { cloneCrosshair = Point2D(x: point.x + Double(offset.x), y: point.y + Double(offset.y)) }
        if !brush.stroke.move(to: point, pressure: pressure).isEmpty || brush.offset != nil { onRender() }
    }

    /// Ends the stroke as one step; the Clone Stamp's Match Tone evens out what it copied first, in the same step.
    func endRetouchBrush() {
        guard let brush = retouchBrush else { return }
        if let point = brush.path.catchUp { moveRetouchBrush(to: point, pressure: brush.pressure) }
        retouchBrush = nil
        brush.stroke.finish()
        let stroke = brush.stroke as? RetouchStroke
        var tone: (mask: SelectionMask, reference: ToneMatch.Reference?)?
        if brush.kind == .cloneStamp, cloneMatchesTone, let stroke, let mask = stroke.coverage {
            tone = (mask, stroke.toneReference(over: ToneMatch.readArea(for: mask, in: canvas.bounds), mask: mask))
        }
        // A dab or a short stroke is matched at once, as part of its step, so quick dabs never miss it; only a big
        // stroke goes to the background.
        if let match = tone, ToneMatch.readArea(for: match.mask, in: canvas.bounds).area < Self.backgroundToneArea {
            ToneMatch.apply(to: canvas.paintLayer, in: match.mask, reference: match.reference, edit: brush.edit)
            tone = nil
        }
        recordingChanges { history.commit(brush.edit) }
        onRender()
        if let tone { matchTone(in: tone.mask, reference: tone.reference) }
    }

    /// The Clone Stamp's Match Tone: worked out in the background from a copy of the pixels, so a long stroke doesn't
    /// pause the app, then folded into the stroke's step (review O, finding 13). Anything that starts a new edit
    /// first waits for it and lands it (`finishPendingTone`), so it never lands in the middle of another edit, where
    /// that edit's undo or Cancel would lose it (review R, finding 1).
    private func matchTone(in mask: SelectionMask, reference: ToneMatch.Reference?) {
        let layer = canvas.paintLayer
        let area = ToneMatch.readArea(for: mask, in: layer.buffer.bounds)
        guard !area.isEmpty else { return }
        // With a reference the plan needs only the edge's before and copied pixels, not a copy of the area.
        let pixels = reference == nil ? layer.buffer.pixels(in: area) : nil
        let pending = PendingTone(revision: history.revision, layer: layer.id, page: page.id)
        let work = UnsafeTransfer(mask)
        pendingTone = pending
        isMatchingTone = true
        DispatchQueue.global(qos: .userInitiated).async {
            pending.plan = UnsafeTransfer(ToneMatch.plan(pixels, area: area, mask: work.value, reference: reference))
            pending.done.signal()
            DispatchQueue.main.async { [weak self] in self?.land(pending) }
        }
    }

    /// Waits for a Match Tone still being worked out, and lands it, before anything else changes the image.
    func finishPendingTone() {
        guard let pending = pendingTone else { return }
        pending.done.wait()
        land(pending)
    }

    private func land(_ pending: PendingTone) {
        guard pendingTone === pending else { return }
        pendingTone = nil
        isMatchingTone = false
        guard let plan = pending.plan?.value else { return }
        // Every new edit lands the tone first, so these hold unless something changed the image without that; then
        // the stroke keeps its own tone rather than the tone landing in another edit.
        guard history.revision == pending.revision, page.id == pending.page, canvas.paintLayer.id == pending.layer,
              !isEditInProgress else {
            return showNotice("The image changed before Match Tone finished, so the stroke kept its own tone.")
        }
        let edit = history.beginEdit(RetouchKind.cloneStamp.name, on: canvas)
        ToneMatch.apply(plan, to: canvas.paintLayer, edit: edit)
        recordingChanges { history.commit(edit, mergingIntoPrevious: true) }
        onRender()
    }

    /// A stroke, drag, effect, fill or object being placed.
    private var isEditInProgress: Bool {
        activeStroke != nil || retouchBrush != nil || retouchStroke != nil || redactStroke != nil || selectionDrag != nil
            || gradientDrag != nil || activeEffect != nil || fillProgress != nil || pendingShape != nil || pendingText != nil
            || pendingBadge != nil
    }

    /// Where the crosshair goes while hovering with the Clone Stamp: the source, or where an aligned offset reads from.
    func cloneCrosshair(hovering point: Point2D?) -> Point2D? {
        guard tool == .retouch, retouchKind == .cloneStamp, let source = cloneSource else { return nil }
        if retouchBrush != nil { return cloneCrosshair }
        if cloneAligned, let offset = cloneOffset, let point { return Point2D(x: point.x + Double(offset.x), y: point.y + Double(offset.y)) }
        return source
    }

    // MARK: Retouching: Remove and Spot Heal (FR-4.6)

    /// Starts painting over what to remove or heal. Nothing changes until the stroke ends.
    func beginRetouchStroke(at point: Point2D) {
        // One fill at a time.
        guard fillProgress == nil else { return onRefused() }
        guard !refusedBecauseLocked() else { return }
        finishInteractions()
        placeFloatingSelection()
        let area = RedactBrushArea(diameter: retouchSize, canvasBounds: canvas.bounds, overlayColor: Pixel(r: 230, g: 40, b: 60, a: 110))
        area.move(to: point)
        retouchStroke = (area, StrokePath(start: point, reach: smoothingReach), retouchKind)
        onRender()
    }

    func continueRetouchStroke(to point: Point2D, constrain: Bool) {
        guard var stroke = retouchStroke else { return }
        stroke.area.move(to: stroke.path.next(point, constrain: constrain))
        retouchStroke = stroke
        onRender()
    }

    /// Fills the painted area from its surroundings in the background, then places it as one step ("Remove" or
    /// "Spot Heal"). Spot Heal looks only just around the spot and evens out the tone. If the image changed
    /// meanwhile, the fill no longer fits it and is dropped.
    func endRetouchStroke() {
        guard let stroke = retouchStroke else { return }
        retouchStroke = nil
        if let point = stroke.path.catchUp { stroke.area.move(to: point) }
        let layer = canvas.paintLayer
        let healing = stroke.kind == .spotHeal
        let image = retouchSamplesAllLayers ? canvas.composited(through: canvas.activeLayerIndex) : layer.buffer
        guard let mask = stroke.area.mask,
              let job = MatchSurroundings.Job(image: image, area: mask, nearby: healing, matchingTone: healing) else { return onRender() }
        guard !job.isTooLarge else {
            showNotice("That area is too big to fill at once. Remove a smaller part at a time, or use the Clone Stamp.")
            return onRender()
        }
        let flag = CancelFlag()
        fillCancel = flag
        fillingArea = stroke.area
        fillProgress = 0
        let revision = history.revision, layerID = layer.id, pageID = page.id
        Task { @MainActor [weak self] in
            let outcome = await Task.detached(priority: .userInitiated) { [weak self] in
                // Also stops once the document is gone: closing its window cancels (review O, finding 8).
                Result { try job.run(progress: { value in
                    Task { @MainActor in if self?.fillCancel === flag { self?.fillProgress = value } }
                }, isCancelled: { flag.isSet || self == nil }) }
            }.value
            guard let self, self.fillCancel === flag else { return }
            self.fillCancel = nil
            self.fillProgress = nil
            self.fillingArea = nil
            if case .failure(let error) = outcome, error is MatchSurroundings.NothingToFillFrom {
                self.showNotice("There isn't enough picture around that area to fill it from.")
            }
            guard case .success(let fill) = outcome else { return self.onRender() }
            guard self.history.revision == revision, self.page.id == pageID, self.canvas.paintLayer.id == layerID,
                  self.activeLayerTakesEdits else {
                self.showNotice("The image changed while filling. Try again.")
                return self.onRender()
            }
            let edit = self.history.beginEdit(stroke.kind.name, on: self.canvas)
            fill.apply(to: self.canvas.paintLayer, edit: edit)
            self.recordingChanges { self.history.commit(edit) }
            self.onRender()
        }
    }

    /// The image changed or another page is shown while a fill runs: its result wouldn't fit, so it stops now rather
    /// than finishing for nothing (review O, finding 8).
    func stopFillForChange() {
        guard fillCancel != nil else { return }
        cancelFill()
        showNotice("The image changed while filling. Try again.")
    }

    /// Esc while a fill runs: stops it, and nothing changes.
    func cancelFill() {
        guard let flag = fillCancel else { return }
        flag.set()
        fillCancel = nil
        fillProgress = nil
        fillingArea = nil
        onRender()
    }
}
