import ColorbeeCore
import CoreGraphics
import Foundation
import Observation

extension Editor {
    // MARK: Pages (FR-11.6)

    var pageCount: Int {
        _ = layersRevision
        return pages.pages.count
    }

    var currentPageIndex: Int {
        _ = layersRevision
        return pages.currentIndex
    }

    /// A page's small picture for the page sidebar.
    func pageThumbnail(at index: Int) -> Thumbnail? {
        _ = layersRevision
        guard pages.pages.indices.contains(index) else { return nil }
        return pages.pages[index].thumbnail()
    }

    func showPage(at index: Int) {
        guard index != pages.currentIndex else { return }
        changePages { try pages.show(index) }
    }

    /// New Page: blank, the size of the shown page, filled with Color 2, after it.
    func newPage() {
        let size = canvas.size
        let blank = Canvas(size: size, colorSpace: canvas.colorSpace, background: color2)
        let added = Page(canvas: blank, history: Editor.makeHistory(), resolution: page.resolution)
        changePages(recorded: true) { try pages.insert(added, at: pages.currentIndex + 1) }
    }

    func duplicatePage() {
        finishInteractions()
        placeFloatingSelection()
        let copy = Page(canvas: canvas.copy(), history: Editor.makeHistory(), resolution: page.resolution)
        changePages(recorded: true) { try pages.insert(copy, at: pages.currentIndex + 1) }
    }

    func deletePage() {
        guard pages.pages.count > 1 else { return onRefused() }
        changePages(recorded: true) { try pages.remove(at: pages.currentIndex) }
    }

    func movePage(from source: Int, to destination: Int) {
        guard source != destination, pages.pages.indices.contains(destination) else { return }
        changePages(recorded: true) { pages.move(from: source, to: destination) }
    }

    /// Runs a page change: what's under way on the shown page is finished first, then the Editor follows the
    /// page now shown. `recorded` changes are steps (undoable, and they mark the document edited).
    /// Whether the change was made. A page that can't be brought back changes nothing (review K, finding 5).
    @discardableResult
    func changePages(recorded: Bool = false, _ body: () throws -> Void) -> Bool {
        finishInteractions()
        placeFloatingSelection()
        comparison = nil
        do {
            try body()
        } catch {
            onRefused()
            if pages.current !== page { pageDidChange() }
            return false
        }
        if recorded {
            undone = []
            onDocumentChange(.done)
        }
        pageDidChange()
        return true
    }

    /// After the shown page changed (or the page list did): remembers the old page's view and saved state, and
    /// brings back the new one's.
    private func pageDidChange() {
        stopFillForChange()
        otherChosenLayerIDs = []
        if pages.current !== page {
            opened.pack()
            saved.pack()
            pageMemory[page.id] = PageMemory(viewport: viewport, opened: opened, saved: saved, savedGeometrySteps: savedGeometrySteps)
            page = pages.current
            canvasSize = canvas.size
            if let memory = pageMemory.removeValue(forKey: page.id) {
                opened = memory.opened
                saved = memory.saved
                savedGeometrySteps = memory.savedGeometrySteps
                if let shown = memory.viewport {
                    updateViewport { $0 = Viewport(zoom: shown.zoom, center: shown.center, viewSize: $0.viewSize) }
                } else {
                    zoomToFit()
                }
            } else {
                // A page added since the document opened: as opened is as it is now.
                opened = PageBaseline(canvas: canvas.copy())
                saved = opened
                savedGeometrySteps = history.geometrySteps
                zoomToFit()
            }
        }
        // Pages out of the document are forgotten once undo can't bring them back (review L, finding 10).
        let kept = Set((pages.pages + pages.restorablePages).map(\.id))
        pageMemory = pageMemory.filter { kept.contains($0.key) }
        layersRevision += 1
        selectionDidChange()
        onRender()
    }

    // MARK: History panel (FR-13.2)

    var historySteps: [(name: String, thumbnail: Thumbnail?, isUndone: Bool)] {
        _ = layersRevision
        return history.steps
    }

    /// Undoes or redoes until exactly `count` steps are done, for a click in the History panel.
    /// Steps only the page shown, never a page change, which isn't in its list (review L, finding 1).
    func jump(toStep count: Int) {
        finishInteractions()
        // Like Undo and Redo, it leaves just the active layer chosen (review T, finding 4).
        otherChosenLayerIDs = []
        while history.undoCount > count, history.canUndo, stepShownPage(undoing: true) {}
        while history.undoCount < count, history.canRedo, stepShownPage(undoing: false) {}
    }

    // MARK: History Snapshots (FR-9.7 item 4)

    /// The page's snapshots, oldest first.
    var historySnapshots: [HistorySnapshot] {
        _ = layersRevision
        return history.snapshots
    }

    /// What New Snapshot… suggests: "Snapshot 1", "Snapshot 2" and so on, skipping names in use.
    var nextSnapshotName: String {
        let names = Set(history.snapshots.map(\.name))
        return (1...).lazy.map { "Snapshot \($0)" }.first { !names.contains($0) }!
    }

    /// Copies the image as it is now. A floating selection is placed first, keeping its outline, since a snapshot
    /// holds only layers and a marquee.
    func takeSnapshot(named name: String) throws(HistorySnapshot.Failure) {
        guard !blocksDocumentCommands else { return }
        finishInteractions()
        placeFloatingKeepingOutline()
        try history.takeSnapshot(named: name, of: canvas)
        layersRevision += 1
    }

    /// Puts the image back as the snapshot has it, as one step that ⌘Z takes back (Q12.5).
    func goToSnapshot(_ id: HistorySnapshot.ID) {
        guard !blocksDocumentCommands else { return onRefused() }
        finishInteractions()
        placeFloatingKeepingOutline()
        stopFillForChange()
        otherChosenLayerIDs = []
        var failed = false
        performSelectionCommand {
            do { try history.goToSnapshot(id, on: canvas) } catch { failed = true }
        }
        if failed { onRefused() }
    }

    func renameSnapshot(_ id: HistorySnapshot.ID, to name: String) {
        history.renameSnapshot(id, to: name)
        layersRevision += 1
    }

    func deleteSnapshot(_ id: HistorySnapshot.ID) {
        history.deleteSnapshot(id)
        layersRevision += 1
    }
}
