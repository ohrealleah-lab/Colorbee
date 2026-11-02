import ColorbeeCore
import CoreGraphics
import Foundation
import Observation

extension Editor {
    // MARK: Picking from the picture (FR-9.7): the white-balance eyedropper and Point Color

    /// What the next click on the picture is for, while what it was turned on for is still being edited.
    var picturePickPurpose: PicturePickPurpose? {
        _ = layersRevision
        guard let picturePick else { return nil }
        switch picturePick.target {
        case .panel: return activeEffect == .adjustPhoto ? picturePick.purpose : nil
        case .layer(let id):
            guard activeEffect == nil, canvas.activeLayer.id == id, case .photo = canvas.activeLayer.adjustment else { return nil }
            return picturePick.purpose
        }
    }

    var isPickingFromPicture: Bool { picturePickPurpose != nil }

    func isPicking(_ purpose: PicturePickPurpose) -> Bool { picturePickPurpose == purpose }

    /// An eyedropper button: on for one click, or off again.
    func togglePicturePick(_ purpose: PicturePickPurpose) {
        if isPicking(purpose) { return cancelPicturePick() }
        if activeEffect == .adjustPhoto {
            picturePick = PicturePick(purpose: purpose, target: .panel)
        } else if activeEffect == nil, case .photo = canvas.activeLayer.adjustment {
            picturePick = PicturePick(purpose: purpose, target: .layer(canvas.activeLayer.id))
        }
    }

    func cancelPicturePick() {
        picturePick = nil
        // A drag on an Adjust Photo layer has already changed it: Esc keeps that as its step (review V, finding 6).
        if case .layer = pictureDrag?.target { finishLayerSettings() }
        pictureDrag = nil
    }

    /// The Color Mixer's hand follows its tab: switching to Saturation, say, makes drags change saturation.
    func followMixerTab(_ setting: ColorMixer.Setting) {
        guard case .colorMixer(let old) = picturePick?.purpose, old != setting else { return }
        picturePick?.purpose = .colorMixer(setting)
    }

    /// The 5 × 5 pixels around `center`, averaged: in the panel, the active layer as it was before Adjust Photo; for an
    /// Adjust Photo layer, the layers below it as shown, or with "Only the layer below", that layer as the adjustment
    /// sees it (review V, finding 9). Nil where there's nothing to read.
    private func pictureSample(at center: IntPoint, for target: PicturePick.Target) -> Pixel? {
        let area = IntRect(x: center.x - 2, y: center.y - 2, width: 5, height: 5).intersection(canvas.bounds)
        guard canvas.bounds.contains(center), !area.isEmpty else { return nil }
        switch target {
        case .panel:
            return effectSource?.averageColor(in: area)
        case .layer:
            let index = canvas.activeLayerIndex
            return (canvas.clipBasePatch(area, under: index) ?? canvas.patchAsShown(area, through: index - 1))
                .averageColor(in: IntRect(x: 0, y: 0, width: area.width, height: area.height))
        }
    }

    // MARK: Dragging on the picture to adjust (FR-9.7 item 6)

    /// Starts a hand drag at `point` (image) and `viewY`. It reads the picture as it was before Adjust Photo, so the
    /// target doesn't move while dragging. A press where there's nothing to read, or on a gray in the Color Mixer,
    /// beeps. False if the hand isn't on, so the press does what it usually does.
    func beginPictureDrag(at point: Point2D, viewY: Double) -> Bool {
        guard let purpose = picturePickPurpose, purpose.drags, let pick = picturePick, let edit = currentPhotoEdit(for: pick.target) else {
            return false
        }
        let center = IntPoint(containing: point)
        guard let sample = pictureSample(at: center, for: pick.target) else {
            onRefused()
            return true
        }
        switch purpose {
        case .toneCurve:
            let curve = edit.toneCurve ?? ToneCurve()
            let region = curve.region(for: sample)
            pictureDrag = PictureDrag(target: pick.target, region: region, mixer: nil, startY: viewY, startValue: curve[region])
        case .colorMixer(let tab):
            let mixer = edit.mixer ?? ColorMixer()
            let setting = mixer.blackAndWhite > 0 ? ColorMixer.Setting.gray : tab
            guard let range = ColorMixer.range(for: sample) else {
                onRefused()
                return true
            }
            pictureDrag = PictureDrag(target: pick.target, region: nil, mixer: (setting, range), startY: viewY, startValue: mixer[setting, range])
        case .whiteBalance, .pointColor:
            return false
        }
        return true
    }

    /// Up is more (Q16.2).
    func continuePictureDrag(viewY: Double) {
        guard let drag = pictureDrag, var edit = currentPhotoEdit(for: drag.target) else { return }
        let value = min(max((drag.startValue + (drag.startY - viewY) * Self.pictureDragRate).rounded(), -100), 100)
        if let region = drag.region {
            var curve = edit.toneCurve ?? ToneCurve()
            guard curve[region] != value else { return }
            curve[region] = value
            edit.toneCurve = curve
        } else if let (setting, range) = drag.mixer {
            var mixer = edit.mixer ?? ColorMixer()
            guard mixer[setting, range] != value else { return }
            mixer[setting, range] = value
            edit.mixer = mixer
        }
        switch drag.target {
        case .panel: setPhotoEdit(edit)
        case .layer: previewAdjustment(.photo(edit))
        }
    }

    /// An Adjust Photo layer's drag is one step; in the panel, Apply makes the step.
    func endPictureDrag() {
        guard let drag = pictureDrag else { return }
        pictureDrag = nil
        if case .layer = drag.target { finishLayerSettings() }
    }

    private func currentPhotoEdit(for target: PicturePick.Target) -> PhotoEdit? {
        switch target {
        case .panel: activeEffect == .adjustPhoto ? photoEdit : nil
        case .layer: activePhotoLayerEdit
        }
    }

    /// A click on the picture while an eyedropper is on. It reads the 5 × 5 pixels around the click: in the panel, the
    /// active layer as it was before Adjust Photo; for an Adjust Photo layer, the layers below it as shown. A click
    /// where there's nothing to read beeps and leaves the eyedropper on (Leah, 2026-10-27). False if no eyedropper
    /// was on, so the click does what it usually does.
    func pickFromPicture(at point: Point2D) -> Bool {
        guard let purpose = picturePickPurpose, let pick = picturePick else {
            picturePick = nil
            return false
        }
        // The hand takes drags (`beginPictureDrag`), not clicks.
        guard !purpose.drags else { return false }
        let center = IntPoint(containing: point)
        guard let sample = pictureSample(at: center, for: pick.target), var changed = currentPhotoEdit(for: pick.target) else {
            onRefused()
            return true
        }
        switch purpose {
        case .whiteBalance:
            changed = changed.neutralizing(sample)
        case .pointColor:
            var colors = changed.pointColors ?? PointColors()
            guard !colors.isFull else {
                onRefused()
                return true
            }
            colors.add(sample)
            changed.pointColors = colors
        case .toneCurve, .colorMixer:
            return false
        }
        picturePick = nil
        switch pick.target {
        case .panel:
            setPhotoEdit(changed)
            if purpose == .whiteBalance { photoAutoMoved.subtract([.warmth, .tint]) }
        case .layer:
            setAdjustment(.photo(changed))
        }
        return true
    }

    /// Adjust Photo's "As Adjustment Layer": the settings become an adjustment layer instead of pixels.
    func photoAsAdjustmentLayer() {
        guard activeEffect == .adjustPhoto else { return }
        let settings = photoEdit.withoutViews
        cancelEffect()
        addAdjustmentLayer(.photo(settings), named: settings.filter?.name ?? "Adjust Photo")
        PhotoSettingsStore.shared.last = settings
    }

    // MARK: Using Adjust Photo settings again (FR-9.7 item 4)

    /// Adjustments ▸ Adjust Photo: Same as Last: the last settings applied, on the selection or active layer, as one
    /// step. Worked out in the background from a copy, so a big photo doesn't stall the window (review V, finding 4); if
    /// the image changes meanwhile, nothing is applied.
    func applySameAsLastPhoto() {
        guard let last = PhotoSettingsStore.shared.last else { return onRefused() }
        guard !refusedBecauseLocked() else { return }
        finishInteractions()
        placeFloatingKeepingOutline()
        let effect = Effect.photo(last), selection = canvas.selection.marquee
        let source = UnsafeTransfer(canvas.paintLayer.buffer.copy())
        let revision = history.revision, layerID = canvas.paintLayer.id, pageID = page.id
        sameAsLastRunning = true
        Task { @MainActor [weak self] in
            let preview = await Task.detached(priority: .userInitiated) {
                EffectPreview.render(effect, from: source.value, regions: nil, selection: selection, copying: false)
            }.value
            guard let self else { return }
            self.sameAsLastRunning = false
            guard self.history.revision == revision, self.page.id == pageID, self.canvas.paintLayer.id == layerID else {
                return self.showNotice("The image changed while Same as Last was working. Try again.")
            }
            guard let preview else { return }
            let edit = self.history.beginEdit(effect.name, on: self.canvas)
            preview.write(into: self.canvas.paintLayer, edit: edit)
            self.recordingChanges { self.history.commit(edit) }
            self.onRender()
        }
    }

    /// The settings of the active Adjust Photo layer, if it is one.
    var activePhotoLayerEdit: PhotoEdit? {
        guard case .photo(let edit) = activeAdjustment else { return nil }
        return edit
    }

    // MARK: Adjust Photo's histogram and clipping warnings (FR-9.7 item 6)

    /// Adjust Photo's controls are showing: its panel, or the Adjustments panel on an Adjust Photo layer.
    var showsPhotoControls: Bool {
        activeEffect == .adjustPhoto || (isSidebarOpen && showsAdjustmentsPanel && activePhotoLayerEdit != nil)
    }

    /// Works out the histogram again once the current change has been drawn, at most every `photoHistogramInterval`.
    /// Changes meanwhile wait for that one, so the last change is always shown.
    func refreshPhotoHistogram() {
        guard !photoHistogramScheduled else { return }
        photoHistogramScheduled = true
        let wait = lastPhotoHistogram.map { max(.zero, Self.photoHistogramInterval - (ContinuousClock.now - $0)) } ?? .zero
        Task { @MainActor [weak self] in
            if wait > .zero { try? await Task.sleep(for: wait) }
            guard let self else { return }
            photoHistogramScheduled = false
            lastPhotoHistogram = .now
            guard showsPhotoControls else { return }
            photoHistogram = Histogram(canvas.thumbnail(maxSide: Self.photoHistogramSide))
        }
    }

    /// Copy Photo Settings: from the Adjust Photo panel while it's open, otherwise from the active Adjust Photo layer.
    func copyPhotoSettings() {
        if activeEffect == .adjustPhoto {
            PhotoSettingsStore.shared.copied = photoEdit.withoutViews
        } else if let edit = activePhotoLayerEdit {
            PhotoSettingsStore.shared.copied = edit.withoutViews
        } else {
            onRefused()
        }
    }

    /// Paste Photo Settings: into the Adjust Photo panel, opening it if needed, so they're seen before Return (Leah,
    /// 2026-10-27). On an Adjust Photo layer, they become that layer's settings, as one step.
    func pastePhotoSettings() {
        guard let copied = PhotoSettingsStore.shared.copied else { return onRefused() }
        if activeEffect == nil, activePhotoLayerEdit != nil { return setAdjustment(.photo(copied)) }
        if activeEffect == nil { beginEffect(.adjustPhoto) }
        guard activeEffect == .adjustPhoto else { return }
        photoAutoMoved = []
        setPhotoEdit(copied)
    }

    /// Paste Photo Settings as Adjustment Layer: a new Adjust Photo layer above the active one.
    func pastePhotoSettingsAsLayer() {
        guard let copied = PhotoSettingsStore.shared.copied else { return onRefused() }
        addAdjustmentLayer(.photo(copied), named: copied.filter?.name ?? "Adjust Photo")
        PhotoSettingsStore.shared.last = copied
    }

    /// Save as Filter…: the filter at its intensity, then the sliders a filter may hold, as one filter.
    /// Returns the settings that now look the same: the new filter at 100%, with the sliders it absorbed
    /// back at zero (only Sharpness, Definition, Texture and Noise Reduction stay). Nil if there was nothing to save.
    func saveFilter(from edit: PhotoEdit, named name: String) -> PhotoEdit? {
        var steps = edit.filter?.steps(atIntensity: edit.filterIntensity / 100) ?? []
        let own = edit.filterPart
        if !own.isNeutral { steps.append(.photo(own)) }
        guard !steps.isEmpty else {
            onRefused()
            return nil
        }
        let savedName = FilterStore.shared.add(PhotoFilter(name: name, steps: steps))
        var after = edit.partFiltersLeaveOut
        after.filter = FilterStore.shared.filter(named: savedName)
        return after
    }

    /// Save Filter from Layers: the visible adjustment layers, bottom to top, each with what a filter may hold.
    /// False when there are none to save.
    func saveFilterFromLayers(named name: String) -> Bool {
        guard let filter = PhotoFilter.fromLayers(canvas.shownLayers, name: name) else { return false }
        FilterStore.shared.add(filter)
        return true
    }

    /// Adjustments ▸ Auto Contrast: one step, no settings (FR-9.5, AC-31).
    func autoContrast() {
        guard !refusedBecauseLocked() else { return }
        finishInteractions()
        placeFloatingKeepingOutline()
        let selection = canvas.selection.marquee
        let levels = Levels.auto(from: Histogram(canvas.paintLayer.buffer, selection: selection))
        guard levels != .identity else { return }
        pixelStep("Auto Contrast") { layer, edit in Effects.apply(.levels(levels), to: layer, selection: selection, edit: edit) }
    }

    /// An Auto Contrast adjustment layer: a Levels layer with its points set from what's beneath it now.
    func addAutoContrastLayer() {
        let below = canvas.composited(through: canvas.activeLayerIndex)
        addAdjustmentLayer(.levels(Levels.auto(from: Histogram(below))), named: "Auto Contrast")
    }

    /// An adjustment with no settings (Invert, Desaturate), applied to the selection or the whole layer.
    func applyAdjustment(_ effect: Effect) {
        guard !refusedBecauseLocked() else { return }
        finishInteractions()
        placeFloatingKeepingOutline()
        let selection = canvas.selection.marquee
        pixelStep(effect.name) { layer, edit in Effects.apply(effect, to: layer, selection: selection, edit: edit) }
    }

    /// What Resize and Skew starts from: the selection as it appears now, or the whole image.
    var resizeSkewBaseSize: IntSize {
        canvas.selection.bounds?.size ?? canvas.size
    }

    func showResizeSkew() {
        finishInteractions()
        isResizeSkewOpen = true
    }

    /// Resizes and skews the selection, or the whole image when nothing is selected (FR-7.2).
    func apply(_ settings: ResizeSkew) {
        isResizeSkewOpen = false
        if !canvas.selection.isEmpty, refusedBecauseLocked() { return }
        finishInteractions()
        recordingChanges {
            if canvas.selection.isEmpty {
                ImageActions.resizeAndSkew(settings, canvas: canvas, history: history, context: selectionContext)
            } else {
                SelectionActions.resizeAndSkewSelection(settings, canvas: canvas, history: history, context: selectionContext)
            }
        }
        selectionDidChange()
    }

    /// Rotates or flips the selection, or the whole image when nothing is selected.
    func apply(_ orientation: Orientation) {
        // The whole image turns every layer, locked or not; a selection is pixels on the active layer.
        if !canvas.selection.isEmpty, refusedBecauseLocked() { return }
        finishInteractions()
        recordingChanges {
            if canvas.selection.isEmpty {
                ImageActions.transform(orientation, canvas: canvas, history: history, context: selectionContext)
            } else {
                SelectionActions.transformSelection(orientation, canvas: canvas, history: history, context: selectionContext)
            }
        }
        selectionDidChange()
    }

    /// The D key: Color 1 black, Color 2 white.
    /// D: black and white, or on a mask white and black, as in Photoshop (Q28.3).
    func resetColors() {
        color1 = canvas.editsMask ? .white : .black
        color2 = canvas.editsMask ? .black : .white
    }

    /// Batch redaction with a solid color: every selected region becomes Color 1 in one step (FR-9.4).
    func applySolidFill() {
        finishInteractions()
        placeFloatingKeepingOutline()
        guard canvas.selection.marquee != nil else { return }
        redactEveryLayer(with: .solidFill(color1))
    }

    /// `snapshotsAnswered`: for Batch Redact, the person agreed to delete the page's History Snapshots.
    func applyEffect(snapshotsAnswered: Bool = false) {
        if activeEffect?.choosesSelection == true { return applyRange() }
        // Batch Redact would leave snapshots showing what it covers, so it asks first (Leah, 2026-11-01). Cancel
        // leaves the bar open, with nothing applied.
        if effectCoversAllLayers, effectEdit != nil, !snapshotsAnswered, !history.snapshots.isEmpty {
            snapshotQuestion = SnapshotQuestion(count: history.snapshots.count) { [weak self] in
                guard let self, self.effectCoversAllLayers else { return }
                self.applyEffect(snapshotsAnswered: true)
            }
            return
        }
        // Masking's edge mask and Point Color's Range are only ever views (Q13.2; review V, finding 1): what's applied is
        // the photo, re-rendered below if need be.
        photoEdit = photoEdit.withoutViews
        if effectPreviewScheduled { renderEffectPreview() }
        if activeEffect == .pickSubject {
            // With no subjects of its own there's nothing for Return to take; waiting on a closer look, it waits.
            guard pickHasSubjects, !isFindingSubject else { return onRefused() }
            activeEffect = nil
            // The Shift-clicked subjects, or with none, all of them (Leah, 2026-11-01).
            if let pick = subjectPick { perform(pick.action, mask: pick.scan.mask(for: pickMarked.isEmpty ? nil : pickMarked.sorted())) }
            endPick()
            return
        }
        if activeEffect == .crop || activeEffect == .perspective {
            // Crossed or folded corners can't be straightened; the tool stays open to fix them (review C, finding 1).
            if activeEffect == .perspective, !Warp.isConvex(perspectiveCorners) { return onRefused() }
            let kind = activeEffect
            activeEffect = nil
            recordingChanges {
                if kind == .crop {
                    ImageActions.crop(to: cropRect, resizingTo: cropPixelSize, canvas: canvas, history: history, context: selectionContext)
                } else {
                    ImageActions.correctPerspective(corners: perspectiveCorners, canvas: canvas, history: history, context: selectionContext)
                }
            }
            if canvas.size != canvasSize { canvasDidResize() }
            // The new image can be a very different size; show all of it.
            zoomToFit()
            selectionDidChange()
            onRender()
            return
        }
        if activeEffect?.previewsAsStep == true {
            if activeEffect == .straighten {
                // Apply keeps exactly the settings on screen: if they're still being turned, finish it here.
                let settings = straightenSettings
                if straightenRunning || straightenShown.map({ $0 != settings }) ?? true {
                    stopStraightenPreview()
                    renderDecorationPreview(.straighten, now: true)
                }
                straightenShown = nil
                zoomToFit()
            }
            activeEffect = nil
            // The preview already is the step; it counts as a change only now.
            if decorationPreviewed {
                noteEdited()
            } else {
                onRefused()
            }
            decorationPreviewed = false
            return
        }
        // Apply commits exactly the settings on screen: if the newest ones are still being worked out, do it now.
        if let kind = activeEffect, effectEdit != nil, kind.effect(effectValues, curves: effectCurves, photo: photoEdit) != shownEffect {
            renderEffectPreview()
        }
        guard let edit = effectEdit else { return }
        // Batch Redact's preview already covers every layer under the selection; Apply keeps what's shown.
        let redacting = effectCoversAllLayers
        let appliedPhoto = activeEffect == .adjustPhoto ? photoEdit : nil
        endEffectSession()
        activeEffect = nil
        var committed = false
        recordingChanges { committed = history.commit(edit) }
        if redacting, committed {
            deleteSnapshotsAfterRedacting(page)
            noteRedaction()
        }
        if committed, let appliedPhoto { PhotoSettingsStore.shared.last = appliedPhoto }
    }
}
