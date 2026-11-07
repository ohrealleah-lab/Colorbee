import ColorbeeCore
import CoreGraphics
import Foundation
import Observation

extension Editor {
    // MARK: Image

    func cropToSelection() {
        performSelectionCommand { ImageActions.cropToSelection(canvas: canvas, history: history, context: selectionContext) }
    }

    /// Image ▸ Trim: the border found from everything shown, and every layer cropped to what's inside it, as one step.
    /// Nothing to trim beeps.
    func trim() {
        finishInteractions()
        placeFloatingKeepingOutline()
        guard let kept = Trim.keptBounds(of: canvas.flattened()) else { return onRefused() }
        performSelectionCommand { ImageActions.crop(to: kept, named: "Trim", canvas: canvas, history: history, context: selectionContext) }
    }

    /// Keeps the zoom and recenters on the new canvas.
    func canvasDidResize() {
        canvasSize = canvas.size
        let center = Point2D(x: Double(canvas.size.width) / 2, y: Double(canvas.size.height) / 2)
        updateViewport { $0.center = center }
    }

    // MARK: Effects

    /// Opens an effect's dialog and shows its preview. It applies to the selection, or the whole layer.
    /// Batch Redact ▸ Blur… and Pixelate…: chosen with the bar like the effects, applied to every layer.
    func beginBatchRedact(_ kind: EffectKind) {
        beginEffect(kind, coveringAllLayers: true)
    }

    func beginEffect(_ kind: EffectKind, coveringAllLayers: Bool = false) {
        // Whole-image tools apply to every layer, locked or not (§23), and picking a subject was already
        // checked by findSubject, since selecting one doesn't change pixels (review B, findings 4 and 5).
        guard coveringAllLayers || kind.appliesToWholeImage || kind == .pickSubject || kind.choosesSelection || !refusedBecauseLocked() else { return }
        effectCoversAllLayers = coveringAllLayers
        finishInteractions()
        placeFloatingKeepingOutline()
        // Spotlight changes what's around the selection, so it needs one.
        if kind == .spotlight, canvas.selection.marquee == nil { return onRefused() }
        effectValues = kind.parameters.map(\.defaultValue)
        effectCurves = .identity
        photoEdit = PhotoEdit()
        photoAutoMoved = []
        if kind == .adjustPhoto { isSidebarOpen = true }
        effectHistogram = kind == .levels ? Histogram(canvas.paintLayer.buffer, selection: canvas.selection.marquee) : nil
        decorationPreviewed = false
        if kind == .crop {
            cropShape = .free
            cropPixelSize = nil
            cropRect = canvas.selection.bounds?.intersection(canvas.bounds) ?? canvas.bounds
            if cropRect.isEmpty { cropRect = canvas.bounds }
        }
        if kind == .perspective {
            // Inset a little, so the corners are easy to find and grab, until Vision finds better ones.
            let w = Double(canvas.size.width), h = Double(canvas.size.height), inset = 0.06
            perspectiveCorners = [Point2D(x: w * inset, y: h * inset), Point2D(x: w * (1 - inset), y: h * inset),
                                  Point2D(x: w * (1 - inset), y: h * (1 - inset)), Point2D(x: w * inset, y: h * (1 - inset))]
            perspectiveStartCorners = perspectiveCorners
            findPerspectiveCorners()
        }
        if coveringAllLayers {
            let (layers, locked) = AutoRedact.layersWithPixels(in: canvas.selection.marquee, canvas: canvas)
            if let locked {
                effectCoversAllLayers = false
                onRefused()
                redactionMessage = "“\(locked.name)” is locked, so nothing can be redacted there. Unlock it and try again."
                return
            }
            effectLayers = layers
        }
        effectEdit = kind.previewsAsStep || kind.isCanvasTool ? nil : history.beginEdit(kind.title, on: canvas)
        // Batch Redact ▸ Blur… and Pixelate… rename a layer named after its words, as every redaction does (review Y).
        effectEdit?.isRedaction = coveringAllLayers
        if kind == .spotlight {
            effectRegions = canvas.selection.marquee?.inverted(in: canvas.bounds).map { [$0] } ?? []
        } else if coveringAllLayers {
            // Redaction is never softened: a partly selected pixel is hidden completely (FR-3.4; review N, finding 1).
            effectRegions = canvas.selection.marquee?.hardened().connectedRegions()
        } else {
            effectRegions = canvas.selection.marquee?.connectedRegions()
        }
        activeEffect = kind
        shownEffect = nil
        if kind.choosesSelection { beginRange() }
        // Batch Redact previews several layers, so it's worked out here rather than from a copy of one.
        effectSource = effectEdit == nil || coveringAllLayers ? nil : canvas.paintLayer.buffer.copy()
        if effectSource != nil { previewEffect() } else { renderEffectPreview() }
    }

    // MARK: Straighten, Perspective Correction and Crop (FR-9.5)

    /// Looks for a rectangle in the picture as shown, on this Mac (FR-9.7 item 7, Q17.1), and moves the corners onto
    /// it, unless they've been moved meanwhile. With none found, they stay where they are.
    private func findPerspectiveCorners() {
        cornerSearch += 1
        let search = cornerSearch
        isFindingCorners = true
        // Flattened from a copy in the background, as Auto-Redact does: a big picture took a moment (review W, finding 7).
        let copy = UnsafeTransfer(canvas.copy())
        Task { @MainActor [weak self] in
            let image = await Task.detached(priority: .userInitiated) {
                (try? ImageCodec.makeCGImage(copy.value.flattened(), colorSpace: copy.value.colorSpace)).map(UnsafeTransfer.init)
            }.value
            let found = if let image { try? await RectangleFinder.find(in: image.value) } else { [Point2D]?.none }
            guard let self, search == self.cornerSearch else { return }
            self.isFindingCorners = false
            guard self.activeEffect == .perspective, self.perspectiveCorners == self.perspectiveStartCorners, let found else { return }
            let width = Double(self.canvas.size.width), height = Double(self.canvas.size.height)
            self.perspectiveCorners = found.map { Point2D(x: min(max($0.x, 0), width), y: min(max($0.y, 0), height)) }
            self.perspectiveStartCorners = self.perspectiveCorners
            self.onRender()
        }
    }

    /// Perspective Correction's Reset: the corners go back to where they started.
    func resetPerspectiveCorners() {
        guard activeEffect == .perspective else { return }
        perspectiveCorners = perspectiveStartCorners
        onRender()
    }

    /// Crop…'s O key (Q17.2): the next guides, named at the bottom of the canvas.
    func nextCropOverlay() {
        guard activeEffect == .crop else { return }
        cropOverlay = cropOverlay.next
        showNotice(cropOverlay.title)
        let until = ContinuousClock.now + .seconds(2)
        cropOverlayShownUntil = until
        Task { @MainActor [weak self] in
            try? await Task.sleep(until: until)
            self?.renderSoon()
        }
    }

    private var showsCropOverlay: Bool {
        isDraggingCrop || cropOverlayShownUntil.map { ContinuousClock.now < $0 } ?? false
    }

    /// Width ÷ height the crop box keeps, or nil for any shape.
    var cropAspect: Double? {
        if let size = cropPixelSize { return Double(size.width) / Double(size.height) }
        return cropShape.aspect(original: canvas.size)
    }

    /// Changing the shape or size preset fits the largest box of that shape in the image.
    func setCrop(shape: CropShape, pixelSize: IntSize?) {
        cropShape = shape
        cropPixelSize = pixelSize
        if let aspect = cropAspect {
            cropRect = CropBox.fitted(aspect: aspect, in: canvas.bounds)
        }
        renderSoon()
    }

    /// The handles to draw for the open canvas tool, in image coordinates.
    var canvasToolHandles: [Point2D] {
        switch activeEffect {
        case .crop: SelectionHandle.allCases.map { $0.point(on: cropRect) }
        case .perspective: perspectiveCorners
        case .graduatedSelection: graduatedLine.map { [$0.start, $0.end] } ?? []
        default: []
        }
    }

    /// Guide lines for the open canvas tool: the crop frame and its guides while dragging, the perspective
    /// outline, Straighten's grid and the line being drawn.
    var canvasToolLines: [(from: Point2D, to: Point2D, color: SIMD4<Float>)] {
        var lines: [(from: Point2D, to: Point2D, color: SIMD4<Float>)] = []
        let white = SIMD4<Float>(1, 1, 1, 0.95), faint = SIMD4<Float>(1, 1, 1, 0.55), accent = SIMD4<Float>(1, 0.35, 0.2, 1)
        switch activeEffect {
        case .crop:
            let r = cropRect
            let corners = [Point2D(x: Double(r.minX), y: Double(r.minY)), Point2D(x: Double(r.maxX), y: Double(r.minY)),
                           Point2D(x: Double(r.maxX), y: Double(r.maxY)), Point2D(x: Double(r.minX), y: Double(r.maxY))]
            for index in 0..<4 { lines.append((corners[index], corners[(index + 1) % 4], white)) }
            if showsCropOverlay {
                lines += cropOverlay.lines(in: r).map { ($0.0, $0.1, faint) }
            }
        case .graduatedSelection:
            // The line, and guides across the canvas where the fade starts and ends, as in Lightroom.
            guard let line = graduatedLine else { break }
            lines.append((line.start, line.end, accent))
            for point in [line.start, line.end] {
                if let guide = guideAcross(line, through: point) { lines.append((guide.0, guide.1, white)) }
            }
        case .perspective where perspectiveCorners.count == 4:
            for index in 0..<4 { lines.append((perspectiveCorners[index], perspectiveCorners[(index + 1) % 4], accent)) }
        case .straighten:
            let width = Double(canvas.size.width), height = Double(canvas.size.height)
            for step in 1..<8 {
                let x = width * Double(step) / 8, y = height * Double(step) / 8
                lines.append((Point2D(x: x, y: 0), Point2D(x: x, y: height), faint))
                lines.append((Point2D(x: 0, y: y), Point2D(x: width, y: y), faint))
            }
            if let line = straightenLine { lines.append((line.start, line.end, accent)) }
        default:
            break
        }
        return lines
    }

    /// A drag on the canvas while Straighten, Perspective Correction or Crop is open.
    func beginCanvasToolDrag(at point: Point2D, viewPoint: Point2D, adding: Bool = false) {
        switch activeEffect {
        case .pickSubject:
            pickSubject(at: point, marking: adding)
            return
        case .colorRange:
            pickRangeColor(at: point, adding: adding)
            return
        case .graduatedSelection:
            beginGraduatedDrag(at: point, viewPoint: viewPoint)
        case .straighten:
            straightenLine = (point, point)
        case .perspective:
            let nearest = perspectiveCorners.indices.min { a, b in
                distance(viewport.viewPoint(fromImage: perspectiveCorners[a]), viewPoint) < distance(viewport.viewPoint(fromImage: perspectiveCorners[b]), viewPoint)
            }
            guard let nearest, distance(viewport.viewPoint(fromImage: perspectiveCorners[nearest]), viewPoint) <= 16 else { return }
            toolDrag = (point, nil, .zero, nearest)
        case .crop:
            let handle = nearestHandle(SelectionHandle.allCases.map { ($0, $0.point(on: cropRect)) }, to: viewPoint)
            let inside = point.x >= Double(cropRect.minX) && point.x < Double(cropRect.maxX) && point.y >= Double(cropRect.minY) && point.y < Double(cropRect.maxY)
            if handle == nil && !inside {
                // Outside the box: draw a new one from here.
                let start = IntPoint(x: Int(point.x.rounded()), y: Int(point.y.rounded()))
                cropRect = CropBox.clamped(IntRect(x: start.x, y: start.y, width: 1, height: 1), to: canvas.bounds, aspect: nil)
                toolDrag = (point, .bottomRight, cropRect, nil)
            } else {
                toolDrag = (point, handle, cropRect, nil)
            }
            isDraggingCrop = true
        default:
            break
        }
        renderSoon()
    }

    func continueCanvasToolDrag(to point: Point2D, constrain: Bool = false) {
        switch activeEffect {
        case .graduatedSelection:
            continueGraduatedDrag(to: point, constrain: constrain)
        case .straighten:
            if let line = straightenLine { straightenLine = (line.start, point) }
        case .perspective:
            guard let drag = toolDrag, let corner = drag.corner else { return }
            perspectiveCorners[corner] = Point2D(x: min(max(point.x, 0), Double(canvas.size.width)), y: min(max(point.y, 0), Double(canvas.size.height)))
        case .crop:
            guard let drag = toolDrag else { return }
            let delta = Point2D(x: point.x - drag.start.x, y: point.y - drag.start.y)
            if let handle = drag.handle {
                var start = drag.rect
                // A new box drawn with a preset shape starts at that shape so it keeps it.
                if let aspect = cropAspect, start.width <= 1 || start.height <= 1 {
                    start = IntRect(x: start.minX, y: start.minY, width: max(1, Int(aspect.rounded())), height: max(1, Int((1 / aspect).rounded())))
                }
                let resized = handle.resize(start, by: delta, keepProportions: cropAspect != nil)
                cropRect = CropBox.clamped(resized, to: canvas.bounds, aspect: cropAspect)
            } else {
                cropRect = CropBox.moved(drag.rect, by: IntPoint(x: Int(delta.x.rounded()), y: Int(delta.y.rounded())), within: canvas.bounds)
            }
        default:
            break
        }
        renderSoon()
    }

    func endCanvasToolDrag() {
        if activeEffect == .straighten, let line = straightenLine {
            straightenLine = nil
            // The line was drawn on the turned preview, so its tilt adds to the turn already there.
            if distance(viewport.viewPoint(fromImage: line.start), viewport.viewPoint(fromImage: line.end)) > 8,
               effectValues.indices.contains(0) {
                let turned = effectValues[0] + Warp.straighteningAngle(from: line.start, to: line.end)
                effectValues[0] = (min(max(turned, -45), 45) * 10).rounded() / 10
            }
        }
        toolDrag = nil
        isDraggingCrop = false
        graduatedMoving = nil
        renderSoon()
    }

    func distance(_ a: Point2D, _ b: Point2D) -> Double { hypot(a.x - b.x, a.y - b.y) }

    // MARK: Messages and Copy Text (FR-10.4)

    func showNotice(_ text: String) {
        let shown = Notice(text: text)
        notice = shown
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            if self?.notice == shown { self?.notice = nil }
        }
    }

    /// Copy Text: reads what you see in the selection (or the whole page) on this Mac and hands the text to `copy`.
    /// The image is never changed, and it isn't an undo step.
    /// `copy` puts the text on the clipboard and returns the clipboard's change count after, so a redaction can
    /// offer to remove it again (Leah, 2026-10-11; review N, finding 3).
    func copyText(_ copy: @escaping @MainActor (String) -> Int) {
        guard !isReadingText else { return }
        let pixels = selectedMergedPixels() ?? canvas.flattened()
        guard let image = try? ImageCodec.makeCGImage(pixels, colorSpace: canvas.colorSpace) else { return onRefused() }
        isReadingText = true
        let history = self.history, revision = history.revision
        Task { @MainActor [weak self] in
            let text = (try? await TextReader.read(image)) ?? ""
            guard let self else { return }
            self.isReadingText = false
            // A redaction (or any change) while reading would put the old text on the clipboard after it.
            guard self.history === history, history.revision == revision else {
                return self.showNotice("The image changed while reading, so nothing was copied")
            }
            // With no text the clipboard is left as it was.
            guard !text.isEmpty else { return self.showNotice("No text found") }
            self.copiedTextClipboardCount = copy(text)
            let words = TextReader.wordCount(text)
            self.showNotice(words == 1 ? "Copied 1 word" : "Copied \(words) words")
        }
    }

    // MARK: Remove Red-Eye (FR-9.5)

    /// Darkens red pupils, as one step. With a selection, the red inside it; otherwise in the eyes Vision finds.
    func removeRedEye() {
        guard !isFindingEyes, !refusedBecauseLocked() else { return }
        finishInteractions()
        placeFloatingKeepingOutline()
        if let mask = canvas.selection.marquee {
            if !pixelStep("Remove Red-Eye", { layer, edit in RedEye.fix(in: mask, layer: layer, edit: edit) }) { showNotice("No red-eye found") }
            return
        }
        let layer = canvas.paintLayer
        guard let image = try? ImageCodec.makeCGImage(layer.buffer, colorSpace: canvas.colorSpace) else { return onRefused() }
        let revision = history.revision
        isFindingEyes = true
        Task { @MainActor [weak self] in
            let eyes = (try? await RedEye.findEyes(in: image)) ?? []
            guard let self else { return }
            self.isFindingEyes = false
            // Something changed meanwhile, so the eyes may no longer be where they were found.
            guard self.history.revision == revision, self.canvas.paintLayer.id == layer.id, self.activeLayerTakesEdits else {
                return self.showNotice("The image changed while finding eyes. Try again.")
            }
            if !self.pixelStep("Remove Red-Eye", { layer, edit in RedEye.fix(eyes, in: layer, edit: edit) }) {
                self.showNotice(eyes.isEmpty ? "No eyes found. Select the red pupils and try again." : "No red-eye found")
            }
        }
    }

    // MARK: Subjects (FR-9.5)

    var pickHasSubjects: Bool { pickSubjectCount > 0 }

    /// Whether Lift Subject and Remove Background can start, as in the menu bar: one search at a time, on a picture
    /// layer that takes edits, with no effect's bar open.
    var canChangeLayerBySubject: Bool {
        !blocksDocumentCommands && !isFindingSubject && canvas.activeLayer.isPixelLayer && activeLayerTakesEdits
    }

    /// Finds the subject in the active layer with Vision, on this Mac, then waits for a click on the one to act on
    /// (Return takes all it found). A click away from them looks closer.
    func findSubject(_ action: SubjectAction) {
        guard !isFindingSubject, activeEffect == nil else { return }
        if action != .select, refusedBecauseLocked() { return }
        finishInteractions()
        placeFloatingKeepingOutline()
        let layer = canvas.paintLayer
        guard layer.isPixelLayer, let image = try? ImageCodec.makeCGImage(layer.buffer, colorSpace: canvas.colorSpace) else { return onRefused() }
        let revision = history.revision
        isFindingSubject = true
        Task { @MainActor [weak self] in
            let scan = try? await SubjectScan.find(in: image)
            let labels = await Task.detached { scan?.labels() }.value
            guard let self else { return }
            self.isFindingSubject = false
            // Something changed the image meanwhile (a step, an undo, or a stroke still being drawn), so the
            // masks may no longer fit it (review B, finding 2).
            guard self.history.revision == revision, self.activeStroke == nil, self.gradientDrag == nil,
                  self.canvas.paintLayer.id == layer.id, self.activeEffect == nil else {
                self.subjectMessage = "The image changed while Colorbee was looking for the subject. Try again."
                return
            }
            let found = scan ?? SubjectScan(size: layer.buffer.size, masks: [])
            // Even one subject waits for a click: Vision's first look can miss what's wanted, or merge it with its
            // neighbors, and a click elsewhere looks closer (Leah, 2026-10-27 and 2026-10-28).
            self.subjectPick = (found, image, action, layer.id)
            self.pickSubjectCount = found.masks.count
            self.pickMarked = []
            self.pickLabels = SubjectLabelMap(size: found.size, values: labels ?? found.labels())
            self.beginEffect(.pickSubject)
        }
    }

    /// The subject under the pointer while picking, as a label (0 for none), for its tint.
    var pickHoveredLabel: Int {
        guard activeEffect == .pickSubject, !isFindingSubject, let pointer, let pickLabels else { return 0 }
        return pickLabels.label(at: pointer)
    }

    /// The Shift-clicked subjects, one bit each, for the renderer. The shader reads them as a float, exact to 24 bits.
    var pickMarkedBits: UInt32 {
        pickMarked.reduce(0) { $1 < 24 ? $0 | 1 << UInt32($1) : $0 }
    }

    /// Ends picking, whether a subject was taken or not.
    func endPick() {
        subjectPick = nil
        pickMarked = []
        pickLabels = nil
    }

    func perform(_ action: SubjectAction, mask: [UInt8]) {
        recordingChanges {
            switch action {
            case .removeBackground: SubjectActions.removeBackground(mask, canvas: canvas, history: history, context: selectionContext)
            case .liftToNewLayer:
                // The picture's layer stays active and is the only one chosen (review T, finding 4; Leah, 2026-10-28).
                // The Layers panel opens, as after New Layer, so the new layer shows though it isn't active (Leah, 2026-10-28).
                if SubjectActions.liftToNewLayer(mask, canvas: canvas, history: history, context: selectionContext) {
                    otherChosenLayerIDs = []
                    showsLayersPanel = true
                    isSidebarOpen = true
                }
            case .select: SubjectActions.select(mask, canvas: canvas, history: history, context: selectionContext)
            }
        }
        selectionDidChange()
        onRender()
    }

    /// A click while picking: the subject there, untangled from its neighbors, or one found by looking closer around
    /// the click, or a beep. A plain click takes it, with any Shift-clicked ones; Shift-click marks it for Return, or
    /// unmarks it (Leah, 2026-11-01).
    private func pickSubject(at point: Point2D, marking: Bool) {
        guard let pick = subjectPick, !isFindingSubject else { return }
        let pixel = IntPoint(containing: point)
        guard canvas.bounds.contains(pixel) else { return onRefused() }
        let index = pixel.y * canvas.size.width + pixel.x
        if marking, let marked = pickMarked.first(where: { pick.scan.masks[$0][index] >= 128 }) {
            pickMarked.remove(marked)
            return
        }
        // Vision shrinks the whole image to about 512 px, so a small subject is missed there, and neighbors can run
        // together (Leah, 2026-10-27 and 2026-11-01).
        isFindingSubject = true
        closerLook += 1
        let look = closerLook
        Task { @MainActor [weak self] in
            let mask = try? await pick.scan.subjectMask(at: pixel, in: pick.image)
            guard let self, self.closerLook == look else { return }
            guard self.activeEffect == .pickSubject, let current = self.subjectPick, current.layer == pick.layer else {
                self.isFindingSubject = false
                return
            }
            guard let mask else {
                self.isFindingSubject = false
                return self.onRefused()
            }
            if marking {
                self.isFindingSubject = false
                return self.mark(mask)
            }
            self.take(SubjectScan(size: current.scan.size, masks: self.pickMarked.map { current.scan.masks[$0] } + [mask]).mask(), look: look)
        }
    }

    /// Takes the picked subjects, with Refine Edge moving their outline onto the picture's own edges first (Leah,
    /// 2026-11-02). It keeps looking while it refines, so Esc still cancels.
    func take(_ mask: [UInt8], look: Int) {
        guard let pick = subjectPick else { return }
        isFindingSubject = true
        Task { @MainActor [weak self] in
            let refined = await RefineEdge.refined(mask, in: pick.image)
            guard let self, self.closerLook == look else { return }
            self.isFindingSubject = false
            guard self.activeEffect == .pickSubject, self.subjectPick?.layer == pick.layer else { return }
            self.endPick()
            self.activeEffect = nil
            self.perform(pick.action, mask: refined)
        }
    }

    /// Marks a subject for Return: one already found, or a new one from a closer look, added so it's outlined too.
    private func mark(_ mask: [UInt8]) {
        guard var pick = subjectPick else { return }
        if let index = pick.scan.masks.firstIndex(of: mask) {
            pickMarked.insert(index)
            return
        }
        pick.scan = SubjectScan(size: pick.scan.size, masks: pick.scan.masks + [mask])
        subjectPick = pick
        pickSubjectCount = pick.scan.masks.count
        pickLabels = SubjectLabelMap(size: pick.scan.size, values: pick.scan.labels())
        pickMarked.insert(pick.scan.masks.count - 1)
    }

    /// Drop Shadow and Border: takes back the last preview step and draws the new one. Straighten does this in the
    /// background, unless `now` (Apply needs exactly the settings on screen).
    func renderDecorationPreview(_ kind: EffectKind, now: Bool = false) {
        if kind == .straighten, !now { return renderStraightenPreview() }
        if decorationPreviewed {
            history.undo(on: canvas)
            // The undone preview was never applied, so it mustn't be redoable, even if this tick draws nothing
            // (review A, finding 5).
            history.forgetRedo()
            decorationPreviewed = false
        }
        let colors = [color1, color2, .black, .white]
        let values = effectValues
        func value(_ index: Int) -> Double { values.indices.contains(index) ? values[index] : kind.parameters[index].defaultValue }
        let drawn = switch kind {
        case .straighten:
            ImageActions.straighten(angle: value(0), cropToFit: value(1) < 0.5, canvas: canvas, history: history, context: selectionContext)
        case .dropShadow:
            Decorations.dropShadow(DropShadow(offsetX: value(0), offsetY: value(1), blur: value(2),
                                              color: value(4) >= 0.5 ? color1 : .black, opacity: value(3)),
                                   canvas: canvas, history: history, context: selectionContext)
        default:
            Decorations.border(Border(width: value(0), color: colors[min(max(Int(value(1).rounded()), 0), 3)]),
                               canvas: canvas, history: history, context: selectionContext)
        }
        decorationPreviewed = drawn
        if kind == .straighten { straightenShown = (value(0), value(1) < 0.5) }
        if canvas.size != canvasSize { canvasDidResize() }
        selectionDidChange()
        onRender()
    }

    /// The Straighten slider's settings: the angle, and whether Crop to fit is on.
    var straightenSettings: (angle: Double, cropToFit: Bool) {
        let values = effectValues, parameters = EffectKind.straighten.parameters
        func value(_ index: Int) -> Double { values.indices.contains(index) ? values[index] : parameters[index].defaultValue }
        return (value(0), value(1) < 0.5)
    }

    /// Straighten turns every layer of a big photo in about 0.15 s each, so the preview is worked out in the
    /// background from the original layers and swapped in when it's ready, keeping the app responsive; settings
    /// changed meanwhile are merged into the next turn (Leah, 2026-10-11). The preview already on screen stays until then.
    private func renderStraightenPreview() {
        guard !straightenRunning else {
            straightenWanted = true
            return
        }
        let settings = straightenSettings
        if let shown = straightenShown, shown == settings { return }
        // The plan reads the original layers: take the shown preview back for a moment, as autosave does.
        if decorationPreviewed { history.undo(on: canvas) }
        let plan = StraightenPlan(angle: settings.angle, cropToFit: settings.cropToFit, canvas: canvas, context: selectionContext)
        if decorationPreviewed { history.redo(on: canvas) }
        guard let plan else {
            // Too small an angle to turn: show the original.
            return renderDecorationPreview(.straighten, now: true)
        }
        straightenRunning = true
        let token = straightenToken, work = UnsafeTransfer(plan)
        let stop = CancelFlag(), done = DispatchSemaphore(value: 0)
        straightenWork = (stop, done)
        Task.detached(priority: .userInitiated) { [weak self] in
            let buffers = UnsafeTransfer(work.value.render(isCancelled: { stop.isSet }))
            done.signal()
            guard let rendered = buffers.value else { return }
            let result = UnsafeTransfer(rendered)
            await MainActor.run { [weak self] in self?.showStraightenPreview(work.value, buffers: result.value, token: token) }
        }
    }

    private func showStraightenPreview(_ plan: StraightenPlan, buffers: [LayerID: PixelBuffer], token: Int) {
        guard token == straightenToken, activeEffect == .straighten else { return }
        straightenRunning = false
        straightenWork = nil
        if decorationPreviewed {
            history.undo(on: canvas)
            history.forgetRedo()
            decorationPreviewed = false
        }
        decorationPreviewed = ImageActions.straighten(plan, buffers: buffers, canvas: canvas, history: history, context: selectionContext)
        straightenShown = (plan.angle, plan.cropToFit)
        if canvas.size != canvasSize { canvasDidResize() }
        selectionDidChange()
        onRender()
        if straightenWanted {
            straightenWanted = false
            renderStraightenPreview()
        }
    }

    /// Drops a Straighten turn still being worked out; its result won't be shown. It reads the original layers, which
    /// any command after this may change in place (Rotate and Flip do), so this waits until it has stopped: at most
    /// the one layer it's turning (review O, finding 2).
    func stopStraightenPreview() {
        if let work = straightenWork {
            work.stop.set()
            work.done.wait()
            straightenWork = nil
        }
        straightenToken += 1
        straightenRunning = false
        straightenWanted = false
    }

    /// Called as the slider moves. Updates are merged, so only the latest value is ever computed
    /// and the slider never waits on a backlog.
    func previewEffect() {
        if effectSource != nil, effectEdit != nil {
            // One background render at a time; settings that change meanwhile are rendered next.
            if previewRunning { previewWanted = true } else { startBackgroundPreview() }
            return
        }
        guard !effectPreviewScheduled else { return }
        effectPreviewScheduled = true
        Task { @MainActor [weak self] in self?.renderEffectPreview() }
    }

    /// Works out the current settings from the original pixels off the main thread, then shows them.
    private func startBackgroundPreview() {
        guard let kind = activeEffect, let source = effectSource else { return }
        let effect = kind.effect(effectValues, curves: effectCurves, photo: photoEdit)
        guard effect != shownEffect else { return }
        let regions = effectRegions, generation = previewGeneration
        let original = UnsafeTransfer(source)
        previewRunning = true
        Task.detached(priority: .userInitiated) { [weak self] in
            let preview = EffectPreview.render(effect, from: original.value, regions: regions)
            await MainActor.run { [weak self] in self?.showBackgroundPreview(preview, of: effect, generation: generation) }
        }
    }

    private func showBackgroundPreview(_ preview: EffectPreview?, of effect: Effect, generation: Int) {
        // A render from a closed session mustn't clear the flag for the current one's (review B, finding 6).
        guard generation == previewGeneration else { return }
        previewRunning = false
        guard let edit = effectEdit else { return }
        edit.restoreOriginals()
        preview?.write(into: canvas.paintLayer, edit: edit)
        shownEffect = effect
        onRender()
        if activeEffect == .adjustPhoto { refreshPhotoHistogram() }
        if previewWanted {
            previewWanted = false
            startBackgroundPreview()
        }
    }

    func renderEffectPreview() {
        effectPreviewScheduled = false
        guard let kind = activeEffect else { return }
        if kind.previewsAsStep { return renderDecorationPreview(kind) }
        if kind.choosesSelection { return refreshRangePreview() }
        if kind.isCanvasTool { return onRender() }
        guard let edit = effectEdit else { return }
        edit.restoreOriginals()
        let effect = kind.effect(effectValues, curves: effectCurves, photo: photoEdit)
        for layer in effectCoversAllLayers ? effectLayers : [canvas.paintLayer] {
            if let regions = effectRegions {
                Effects.apply(effect, to: layer, regions: regions, edit: edit)
            } else {
                Effects.apply(effect, to: layer, selection: nil, edit: edit)
            }
        }
        shownEffect = effect
        onRender()
        if kind == .adjustPhoto { refreshPhotoHistogram() }
    }

    /// Levels' Auto button: black and white points at the darkest and lightest values (FR-9.5).
    func autoLevels() {
        guard activeEffect == .levels, let histogram = effectHistogram else { return }
        let levels = Levels.auto(from: histogram)
        effectValues = [levels.black, levels.gamma, levels.white]
        previewEffect()
    }

    func setPhotoEdit(_ edit: PhotoEdit) {
        guard activeEffect == .adjustPhoto else { return }
        photoEdit = edit
        photoAutoMoved = photoAutoMoved.filter { edit.adjustments[$0] != 0 }
        previewEffect()
    }

    /// Adjust Photo's Auto: sets the sliders it balances from the original pixels and marks them (FR-9.5).
    func autoPhoto() {
        guard activeEffect == .adjustPhoto, let source = effectSource else { return }
        // From the original pixels, not the preview on screen.
        let auto = PhotoAdjustments.auto(for: source, selection: canvas.selection.marquee)
        var changed = photoEdit
        for slider in PhotoAdjustments.autoSliders {
            changed.adjustments[slider] = auto[slider]
        }
        photoEdit = changed
        photoAutoMoved = Set(auto.values.keys)
        previewEffect()
    }
}
