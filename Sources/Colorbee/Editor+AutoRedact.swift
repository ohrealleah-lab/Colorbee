import ColorbeeCore
import CoreGraphics
import Foundation
import Observation

extension Editor {
    // MARK: After a redaction (review H, findings 1 and 2)

    /// The Clipboard History items the picture was pasted from, kept with its pages so they're saved and survive a
    /// relaunch (review AA, finding 4).
    private var clipboardSources: Set<ClipboardHistory.Item.ID> { Set(pages.pages.flatMap(\.canvas.pastedFrom)) }

    /// After a redacted file's earlier versions are removed: the undo history goes too, so the redaction can't
    /// be undone and then saved back, and Before/After's "As Opened" becomes the image as it is now (Leah, 2026-10-04).
    /// Every page's, along with page changes, so a deleted page can't come back either.
    func forgetHistory() {
        finishInteractions()
        pages.forgetHistory()
        undone = []
        redactionGroups = []
        let kept = Set(pages.pages.map(\.id))
        pageMemory = pageMemory.filter { kept.contains($0.key) }
        // Every page as opened is now as it is: nothing unredacted is kept (review K, finding 3).
        for other in pages.pages where other !== page {
            guard var memory = pageMemory[other.id], let project = try? other.projectData() else { continue }
            memory.opened = PageBaseline(data: project, describing: other.canvas)
            memory.savedGeometrySteps = other.history.geometrySteps
            pageMemory[other.id] = memory
        }
        opened = PageBaseline(canvas: canvas.copy())
        savedGeometrySteps = history.geometrySteps
        layersRevision += 1
        onRender()
    }

    func noteClipboardSource(_ id: ClipboardHistory.Item.ID?) {
        if let id { canvas.pastedFrom.insert(id) }
    }

    func noteRedaction() {
        redactedSinceSave = true
        let remaining = clipboardSources.filter(ClipboardHistory.shared.contains)
        let text = copiedTextClipboardCount.map(ClipboardHistory.clipboardUnchanged) ?? false
        if !text { copiedTextClipboardCount = nil }
        if !remaining.isEmpty || text { clipboardCleanup = ClipboardCleanup(images: Array(remaining), text: text) }
    }

    func removeClipboardSources() {
        guard let cleanup = clipboardCleanup else { return }
        cleanup.images.forEach { ClipboardHistory.shared.remove($0, clearingClipboard: true) }
        for page in pages.pages { page.canvas.pastedFrom.subtract(cleanup.images) }
        if cleanup.text, let count = copiedTextClipboardCount { ClipboardHistory.clearClipboard(ifUnchangedSince: count) }
        copiedTextClipboardCount = nil
        clipboardCleanup = nil
    }

    /// Batch Redact on every layer under the selection, or the whole image, as one step.
    /// `mask` is the area, the selection by default.
    func redactEveryLayer(with effect: Effect, in mask: SelectionMask? = nil, named name: String? = nil) {
        guard let area = mask ?? canvas.selection.marquee ?? SelectionMask.rectangle(canvas.bounds, clippedTo: canvas.bounds) else { return }
        // Only a redaction that will change something asks; a locked layer refuses at once, as without snapshots.
        if !history.snapshots.isEmpty {
            let (layers, locked) = AutoRedact.layersWithPixels(in: area.hardened(), canvas: canvas)
            if locked == nil, !layers.isEmpty {
                let revision = history.revision, pageID = page.id
                snapshotQuestion = SnapshotQuestion(count: history.snapshots.count) { [weak self] in
                    // If the picture changed while the question was up, the area asked about may not fit it.
                    guard let self else { return }
                    guard self.history.revision == revision, self.page.id == pageID else {
                        self.onRefused()
                        self.redactionMessage = "The picture changed while Colorbee was asking, so nothing was redacted. Try again."
                        return
                    }
                    self.redact(with: effect, in: area, named: name)
                }
                return onRender()
            }
        }
        redact(with: effect, in: area, named: name)
    }

    private func redact(with effect: Effect, in area: SelectionMask, named name: String?) {
        var outcome = AutoRedact.Outcome.nothingChanged
        recordingChanges { outcome = AutoRedact.apply(effect, in: area, named: name, canvas: canvas, history: history) }
        if case .locked(let name) = outcome {
            onRefused()
            redactionMessage = "“\(name)” is locked, so nothing was redacted. Unlock it and try again."
        } else if outcome == .redacted {
            lastRedaction = [RedactedArea(page: page.id, effect: effect, area: area.hardened())]
            deleteSnapshotsAfterRedacting(page)
            noteRedaction()
        }
        onRender()
    }

    /// Solid Fill only: Blur and Pixelate are as strong as each item's height, and need the picture before to check.
    private func noteRedacted(_ matches: [RedactionMatch], on page: Page, treatment: RedactionTreatment) {
        guard treatment == .solidFill else { return }
        lastRedaction += matches.compactMap { SelectionMask.rectangle($0.rect, clippedTo: page.canvas.bounds) }
            .map { RedactedArea(page: page.id, effect: .solidFill(color1), area: $0) }
    }

    /// A redacted page's History Snapshots still show what was redacted, so they go (Leah, 2026-11-01). Not a step:
    /// undoing the redaction doesn't bring them back.
    func deleteSnapshotsAfterRedacting(_ redacted: Page) {
        guard !redacted.history.snapshots.isEmpty else { return }
        redacted.history.deleteAllSnapshots()
        layersRevision += 1
    }

    /// The question's Delete Snapshots and Redact.
    func deleteSnapshotsAndRedact() {
        guard let question = snapshotQuestion else { return }
        snapshotQuestion = nil
        question.redact()
    }

    /// Drops the background preview state; a render still running finds a newer generation and is ignored.
    func endEffectSession() {
        picturePick = nil
        endRange()
        effectCoversAllLayers = false
        effectLayers = []
        effectEdit = nil
        effectSource = nil
        shownEffect = nil
        previewGeneration += 1
        previewRunning = false
        previewWanted = false
        stopStraightenPreview()
        straightenShown = nil
    }

    func cancelEffect() {
        stopStraightenPreview()
        straightenShown = nil
        if activeEffect?.previewsAsStep == true, decorationPreviewed {
            history.undo(on: canvas)
            history.forgetRedo()
            if canvas.size != canvasSize { canvasDidResize() }
            selectionDidChange()
        }
        decorationPreviewed = false
        if subjectPick != nil, isFindingSubject {
            // A closer look still running is dropped at once (review T, finding 5).
            closerLook += 1
            isFindingSubject = false
        }
        endPick()
        effectEdit?.restoreOriginals()
        endEffectSession()
        activeEffect = nil
        onRender()
    }

    // MARK: Auto-Redact

    /// Reads the text on every page, whole, on this Mac and opens the review. A selection is ignored: Batch
    /// Redact is for chosen areas (Leah, 2026-10-04).
    func beginAutoRedact() {
        // Every layer is redacted, so the active one being locked doesn't matter here; Apply checks the layers
        // under the boxes.
        finishInteractions()
        placeFloatingKeepingOutline()
        let read = pages.pages
        let session = AutoRedactSession(
            anyLayered: read.contains { $0.canvas.layers.count > 1 },
            pages: read.map { .init(pageID: $0.id, revision: $0.history.revision, canvasSize: $0.canvas.size) }
        )
        autoRedact = session
        onRender()
        // Each page is flattened from a copy (or its parked bytes) in the background, not on the main thread
        // (review E, finding 6), one page at a time so only one is held in full.
        let sources = read.map { page in
            page.parked.map(PageSource.parked) ?? .canvas(UnsafeTransfer(page.canvas.copy()))
        }
        Task { [weak self] in
            for (index, source) in sources.enumerated() {
                do {
                    let image = try await Task.detached(priority: .userInitiated) {
                        let canvas = try source.canvas()
                        return UnsafeTransfer(try ImageCodec.makeCGImage(canvas.flattened(), colorSpace: canvas.colorSpace))
                    }.value
                    let scan = try await TextScan.read(image.value)
                    let faces = try await FaceFinder.find(in: image.value)
                    // A scan from a run that was cancelled mustn't fill in a newer one (review E, finding 2).
                    guard let self, self.autoRedact?.id == session.id else { return }
                    self.autoRedact?.pages[index].scan = scan
                    self.autoRedact?.pages[index].faces = faces.map { (UUID(), $0) }
                    self.refreshAutoRedactMatches()
                } catch {
                    guard self?.autoRedact?.id == session.id else { return }
                    self?.autoRedact?.failedPage = session.pages[index].pageID
                    self?.autoRedact?.failure = error.localizedDescription
                    return
                }
            }
        }
    }

    func refreshAutoRedactMatches() {
        guard let session = autoRedact else { return }
        // Faces are numbered through the whole document, after each page's text.
        let findsFaces = redactionPatterns.contains { $0.isFaces && $0.isEnabled }
        var faceNumber = 1
        for (index, result) in session.pages.enumerated() {
            guard let scan = result.scan else { continue }
            let faces = findsFaces ? FaceFinder.matches(result.faces ?? [], numberedFrom: faceNumber) : []
            faceNumber += faces.count
            autoRedact?.pages[index].matches = scan.matches(for: redactionPatterns) + faces
        }
        let found = autoRedact?.matches.map(\.id) ?? []
        autoRedact?.keptVisible.formIntersection(found)
        onRender()
    }

    func setRedactionMatch(_ id: UUID, included: Bool) {
        if included { autoRedact?.keptVisible.remove(id) } else { autoRedact?.keptVisible.insert(id) }
        onRender()
    }

    func setRedactionTreatment(_ treatment: RedactionTreatment) {
        autoRedact?.treatment = treatment
    }

    /// The page number (from 1) of a page, for the review.
    func pageNumber(of id: UUID) -> Int? {
        pages.pages.firstIndex { $0.id == id }.map { $0 + 1 }
    }

    /// Clicking an item in the review: shows its page, and scrolls its box into view (Leah, 2026-10-04).
    func focusRedactionMatch(_ id: UUID) {
        guard let session = autoRedact, session.applying == nil,
              let result = session.pages.first(where: { $0.matches.contains { $0.id == id } }),
              let match = result.matches.first(where: { $0.id == id }),
              let number = pageNumber(of: result.pageID) else { return }
        autoRedact?.focused = id
        showPage(at: number - 1)
        let box = match.rect
        let corners = [viewport.viewPoint(fromImage: Point2D(x: Double(box.minX), y: Double(box.minY))),
                       viewport.viewPoint(fromImage: Point2D(x: Double(box.maxX), y: Double(box.maxY)))]
        let inView = corners.allSatisfy { $0.x >= 0 && $0.y >= 0 && $0.x <= viewport.viewSize.width && $0.y <= viewport.viewSize.height }
        if !inView {
            updateViewport { $0.center = Point2D(x: Double(box.minX + box.maxX) / 2, y: Double(box.minY + box.maxY) / 2) }
        }
        onRender()
    }

    /// Redacts every checked match, one step on each page, on every layer under it (review E, findings 1, 3 and
    /// 4). Nothing is redacted if any page changed since it was read or has a locked layer under a box.
    /// `snapshotsAnswered`: the person agreed to delete the snapshots of the pages being redacted.
    func applyAutoRedact(snapshotsAnswered: Bool = false) {
        guard let session = autoRedact, !session.isReading, session.failure == nil, session.applying == nil else { return }
        let targets = session.pages.compactMap { result -> (page: Page, result: AutoRedactSession.PageResult, matches: [RedactionMatch])? in
            let matches = session.selectedMatches(onPage: result.pageID)
            guard !matches.isEmpty, let page = pages.pages.first(where: { $0.id == result.pageID }) else { return nil }
            return (page, result, matches)
        }
        func onPage(_ page: Page) -> String {
            session.isMultiPage ? "On page \(pageNumber(of: page.id) ?? 0), " : ""
        }
        for target in targets where target.page.history.revision != target.result.revision || target.page.canvas.size != target.result.canvasSize {
            let what = session.isMultiPage ? "Page \(pageNumber(of: target.page.id) ?? 0)" : "The image"
            autoRedact?.problem = "\(what) changed after it was read. Cancel and run Auto-Redact again."
            return
        }
        for target in targets {
            let locked: Layer?
            do { locked = try lockedLayer(under: target.matches, on: target.page) } catch {
                autoRedact?.problem = "Couldn't check page \(pageNumber(of: target.page.id) ?? 0): \(error.localizedDescription)"
                return
            }
            if let locked {
                autoRedact?.problem = "\(onPage(target.page))“\(locked.name)” is locked. Cancel, unlock it and run Auto-Redact again; nothing was redacted."
                return
            }
        }
        let snapshots = targets.reduce(0) { $0 + $1.page.history.snapshots.count }
        if snapshots > 0, !snapshotsAnswered {
            // Asked again on the answer, so a page that changed meanwhile is still caught above.
            snapshotQuestion = SnapshotQuestion(count: snapshots) { [weak self] in self?.applyAutoRedact(snapshotsAnswered: true) }
            return
        }
        autoRedact?.applying = (0, targets.count)
        lastRedaction = []
        Task { [weak self] in
            guard let self else { return }
            var redacted = false, changedOtherPages = false
            var group: [(page: UUID, step: UUID)] = []
            var redactedPages: [Int] = []
            for (done, target) in targets.enumerated() {
                let apply = { AutoRedact.apply(target.matches, treatment: session.treatment, fill: self.color1,
                                               canvas: target.page.canvas, history: target.page.history) }
                let number = pageNumber(of: target.page.id) ?? 0
                if target.page === page {
                    recordingChanges {
                        if apply() == .redacted {
                            redacted = true
                            group += history.undoStepID.map { [(page.id, $0)] } ?? []
                            noteRedacted(target.matches, on: page, treatment: session.treatment)
                            deleteSnapshotsAfterRedacting(page)
                        }
                    }
                    redactedPages.append(number)
                } else {
                    // Another page is brought back just long enough to redact it, then compressed again. A page that
                    // was redacted but can't be parked again stays unparked; saving still includes it.
                    do {
                        try target.page.unpark()
                        if apply() == .redacted {
                            redacted = true
                            changedOtherPages = true
                            group += target.page.history.undoStepID.map { [(target.page.id, $0)] } ?? []
                            noteRedacted(target.matches, on: target.page, treatment: session.treatment)
                            deleteSnapshotsAfterRedacting(target.page)
                        }
                        redactedPages.append(number)
                        try target.page.park()
                    } catch {
                        // Says plainly what was and wasn't redacted (review K, finding 7).
                        let done = redactedPages.isEmpty ? "No page was redacted"
                            : "Page\(redactedPages.count == 1 ? "" : "s") \(redactedPages.map(String.init).joined(separator: ", ")) \(redactedPages.count == 1 ? "was" : "were") redacted"
                        autoRedact?.problem = "\(done), but page \(number) couldn't be: \(error.localizedDescription) Cancel, then check the pages."
                        break
                    }
                }
                autoRedact?.applying = (done + 1, targets.count)
                // Lets the review show its progress between pages.
                try? await Task.sleep(for: .milliseconds(1))
            }
            if group.count > 1 { redactionGroups.append(group) }
            if changedOtherPages { noteEdited() }
            if redacted { noteRedaction() }
            if autoRedact?.problem == nil { autoRedact = nil } else { autoRedact?.applying = nil }
            onRender()
        }
    }

    /// The first locked layer with pixels under `matches` on `page`. A parked page with no locked layer at all
    /// isn't brought back to look.
    private func lockedLayer(under matches: [RedactionMatch], on page: Page) throws -> Layer? {
        guard page.canvas.layers.contains(where: { page.canvas.isLocked($0) && $0.isPixelLayer }) else { return nil }
        guard page.isParked else { return AutoRedact.lockedLayer(under: matches, canvas: page.canvas) }
        try page.unpark()
        defer { try? page.park() }
        return AutoRedact.lockedLayer(under: matches, canvas: page.canvas)
    }

    func cancelAutoRedact() {
        guard autoRedact?.applying == nil else { return }
        autoRedact = nil
        onRender()
    }

    /// Saved patterns, with every built-in present (new built-ins are added, their expressions kept current).
    static func loadRedactionPatterns() -> [RedactionPattern] {
        let saved = StoredSettings.list(of: RedactionPattern.self, from: StoredSettings.data(forKey: patternsKey)) ?? []
        let builtIns = RedactionPattern.builtIns.map { builtIn in
            var pattern = builtIn
            pattern.isEnabled = saved.first { $0.id == builtIn.id }?.isEnabled ?? true
            return pattern
        }
        return builtIns + saved.filter { !$0.isBuiltIn }
    }

    static func saveRedactionPatterns(_ patterns: [RedactionPattern]) {
        StoredSettings.save(patterns, forKey: patternsKey)
    }

    // MARK: Before/After

    var comparisonBaseline: PixelBuffer? {
        switch comparison?.baseline {
        case .asOpened: asOpened
        case .lastSaved: lastSaved
        case nil: nil
        }
    }

    func toggleComparison() {
        if comparison == nil {
            finishInteractions()
            comparison = Comparison()
        } else {
            comparison = nil
        }
    }

    /// Fits the view to what's being compared: both images side by side, or just the canvas.
    func fitComparison() {
        if comparison?.layout == .sideBySide {
            // As opened has the page's size, which is known without decoding it.
            let width = opened.size.width + canvas.size.width + Self.comparisonGap
            let height = max(opened.size.height, canvas.size.height)
            updateViewport { $0.fit(IntSize(width: width, height: height), margin: 40) }
        } else {
            zoomToFit()
        }
    }

    /// Records the image as of an explicit save, for "Last Saved".
    /// `snapshot` is the copy that was written; nothing else changes it, so its buffers are kept as they are.
    func markSaved(_ snapshot: SaveSnapshot) {
        // Each other page's saved state is the bytes that were written for it (review L, finding 12).
        for other in snapshot.otherPages {
            guard var memory = pageMemory[other.id],
                  let described = (pages.pages + pages.restorablePages).first(where: { $0.id == other.id }) else { continue }
            memory.saved = PageBaseline(data: other.page.project, describing: described.canvas)
            memory.savedGeometrySteps = other.geometrySteps
            pageMemory[other.id] = memory
        }
        // With any floating selection drawn in, as the file has it (review G, finding 3).
        let savedPage = PageBaseline(layers: snapshot.canvas.layerBuffersAsSaved(transparentKey: snapshot.transparentKey,
                                                                                  resampling: snapshot.resampling),
                                     colorSpace: snapshot.canvas.colorSpace)
        guard snapshot.pageID == page.id else {
            // The save finished after another page was shown: it's that page's saved state.
            if let savedPage, var memory = pageMemory[snapshot.pageID] {
                savedPage.pack()
                memory.saved = savedPage
                memory.savedGeometrySteps = snapshot.geometrySteps
                pageMemory[snapshot.pageID] = memory
            }
            lastSavedSnapshot = snapshot
            lastSavedImage = nil
            return
        }
        lastSavedSnapshot = snapshot
        lastSavedImage = nil
        // Flattened ahead in the background, so Before/After doesn't pause the first time (review E, finding 6).
        let written = UnsafeTransfer(snapshot)
        Task { [weak self] in
            let image = await Task.detached(priority: .utility) {
                UnsafeTransfer(written.value.flattened)
            }.value
            guard let self, self.lastSavedSnapshot?.canvas === written.value.canvas, self.lastSavedImage == nil else { return }
            self.lastSavedImage = image.value
        }
        savedGeometrySteps = snapshot.geometrySteps
        if let savedPage { saved = savedPage }
    }
}
