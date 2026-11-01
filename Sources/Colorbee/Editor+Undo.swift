import ColorbeeCore
import CoreGraphics
import Foundation
import Observation

extension Editor {
    // MARK: Undo

    var undoActionName: String? { pages.undoName ?? history.undoActionName }

    var redoActionName: String? { undone.last == .pageChange ? pages.redoName : history.redoActionName }

    func undo() {
        // Undo first discards a shape that hasn't been placed yet.
        if pendingShape != nil {
            cancelPendingShape()
            return
        }
        if pendingBadge != nil {
            cancelPendingBadge()
            return
        }
        finishInteractions()
        stopFillForChange()
        otherChosenLayerIDs = []
        // Adding, deleting or moving a page is undone while it's the newest thing done (FR-11.6).
        if pages.undoName != nil {
            guard changePages({ try pages.undo() }) else { return }
            undone.append(.pageChange)
            onDocumentChange(.undone)
            return
        }
        let step = history.undoStepID
        // Undoing a badge steps the next number back to it (FR-5.3).
        if stepShownPage(undoing: true), let step, let badge = badgeSteps[step] { nextBadges[badge.style] = badge.value }
    }

    func redo() {
        finishInteractions()
        stopFillForChange()
        otherChosenLayerIDs = []
        if undone.last == .pageChange, pages.redoName != nil {
            guard changePages({ try pages.redo() }) else { return }
            undone.removeLast()
            onDocumentChange(.redone)
            return
        }
        let step = history.redoStepID
        if stepShownPage(undoing: false), let step, let badge = badgeSteps[step] { nextBadges[badge.style] = badge.value + 1 }
    }

    /// Undoes or redoes the newest step of the page shown, or of every page of a multi-page Auto-Redact it's part of.
    @discardableResult
    func stepShownPage(undoing: Bool) -> Bool {
        if let group = redactionGroup(undoing: undoing) {
            let stepped = stepPages(group, undoing: undoing)
            // Some pages may have stepped before one failed; they're recorded as changed either way.
            if stepped < group.count { onRefused() }
            guard stepped > 0 else { return false }
        } else {
            guard (undoing ? history.undo(on: canvas) : history.redo(on: canvas)) != nil else { return false }
        }
        if undoing {
            undone.append(.pageEdit)
        } else if undone.last == .pageEdit {
            undone.removeLast()
        }
        undoRedoCount += 1
        layersRevision += 1
        onDocumentChange(undoing ? .undone : .redone)
        selectionDidChange()
        return true
    }

    /// The pages of the multi-page Auto-Redact that ⌘Z (or ⇧⌘Z) would step on the page shown, if it's still the
    /// newest change on every one of them. If another page has changed since, only this page's part steps.
    private func redactionGroup(undoing: Bool) -> [Page]? {
        guard let top = undoing ? history.undoStepID : history.redoStepID,
              let group = redactionGroups.first(where: { $0.contains { $0.step == top } }) else { return nil }
        let parts = group.compactMap { part in pages.pages.first { $0.id == part.page }.map { (page: $0, step: part.step) } }
        let ready = parts.allSatisfy { (undoing ? $0.page.history.undoStepID : $0.page.history.redoStepID) == $0.step }
        return ready && parts.count > 1 ? parts.map(\.page) : nil
    }

    /// Undoes or redoes the newest step on each of `group`, bringing back parked pages just long enough. Returns how
    /// many pages stepped. A page that stepped but couldn't be parked again stays unparked; saving still includes it.
    private func stepPages(_ group: [Page], undoing: Bool) -> Int {
        var stepped = 0
        for page in group {
            let step = { undoing ? page.history.undo(on: page.canvas) : page.history.redo(on: page.canvas) }
            if page === self.page {
                _ = step()
                stepped += 1
                continue
            }
            do {
                try page.unpark()
                _ = step()
                stepped += 1
                try page.park()
            } catch {
                break
            }
        }
        return stepped
    }
}
