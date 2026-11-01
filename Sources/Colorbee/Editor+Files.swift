import ColorbeeCore
import CoreGraphics
import Foundation
import Observation

extension Editor {
    // MARK: Files

    /// The image as it looks, including any floating selection, encoded in `format`.
    /// Formats without transparency are flattened over Color 2.
    func encoded(as format: ImageFileFormat, quality: Double = 0.9) throws -> Data {
        try withoutEffectPreview { try snapshot(of: canvas).encoded(as: format, quality: quality) }
    }

    /// The whole document as a .colorproj (FR-8.5), without any live effect preview.
    func encodedProject() throws -> Data {
        try withoutEffectPreview { try snapshot(of: canvas).encodedProject() }
    }

    /// A copy of the document for saving or output, without any live effect preview. A shape, text or Step Badge still
    /// being edited is placed first, so what's written is what's shown (review K, finding 1); autosave passes false, so it
    /// doesn't fix in place what's still being edited.
    func saveSnapshot(placingPending: Bool = true) -> SaveSnapshot {
        // Every save, autosave too, waits for a Match Tone being worked out: closing or quitting autosaves, and the
        // tone would otherwise never be saved (review S, finding 2). A shape or text box is placed only when asked.
        finishPendingTone()
        if placingPending { placePendingObjects() }
        return withoutEffectPreview { snapshot(of: canvas.copy()) }
    }

    /// While a sheet or an effect's bar is open, the document's own commands (Save, Export, Share, Print, Revert) wait
    /// too, as the Edit commands do (review L, finding 2).
    var blocksDocumentCommands: Bool {
        // The selection sheet (Feather, Expand and the rest) too: OK puts back the selection as it was when the sheet opened (review P, finding 1).
        activeEffect != nil || autoRedact != nil || isResizeSkewOpen || isCanvasPropertiesOpen || selectionChange != nil
    }

    /// Auto-Redact is redacting page after page; a save now would hold only part of it.
    var isRedacting: Bool { autoRedact?.applying != nil }

    func placePendingObjects() {
        finishPendingTone()
        commitPendingShape()
        commitPendingText()
        commitPendingBadge()
    }

    private func snapshot(of canvas: ColorbeeCore.Canvas) -> SaveSnapshot {
        // Other pages are parked, so their bytes are taken as they are: no copying (FR-11.6).
        // A page left unparked by a failure is encoded now rather than left out (review K, finding 7).
        let others = pages.pages.enumerated().compactMap { index, other
            -> (index: Int, id: UUID, geometrySteps: [ObjectIdentifier], page: ProjectFile.StoredPage)? in
            guard other !== page, let project = try? other.projectData() else { return nil }
            return (index, other.id, other.history.geometrySteps,
                    ProjectFile.StoredPage(project: project, resolution: other.resolution, thumbnail: other.thumbnail()))
        }
        return SaveSnapshot(canvas: canvas, transparentKey: selectionContext.transparentKey, resampling: selectionContext.resampling, matte: color2,
                            geometrySteps: history.geometrySteps, pageID: page.id, pageResolution: page.resolution, otherPages: others,
                            currentIndex: pages.currentIndex)
    }

    /// More than one layer, or an adjustment layer: something only a project file can keep.
    /// More than one layer, an adjustment layer, or more than one page: something only a project file can keep.
    var isLayered: Bool {
        // A mask too: a picture saved as a PNG would lose it (stage 27).
        pages.pages.count > 1 || canvas.layers.count > 1 || canvas.layers.contains { !$0.isPixelLayer || $0.mask != nil || $0.text != nil }
    }

    /// An effect's live preview is drawn into the layer before it's applied; an autosave in the
    /// meantime must write the image without it, in case the effect is cancelled.
    private func withoutEffectPreview<T>(_ body: () throws -> T) rethrows -> T {
        // Drop Shadow, Border and Straighten preview as a real step, so it's taken back for the copy
        // (review B, finding 1).
        if activeEffect?.previewsAsStep == true, decorationPreviewed {
            history.undo(on: canvas)
            defer { history.redo(on: canvas) }
            return try body()
        }
        guard let edit = effectEdit else { return try body() }
        // The preview's pixels are put back as they were, not worked out again on the main thread
        // (review B, finding 3).
        let shown = edit.dirtyRect
        let layers = effectCoversAllLayers ? effectLayers : [canvas.paintLayer]
        let pixels = layers.map { $0.buffer.pixels(in: shown) }
        edit.restoreOriginals()
        defer { for (layer, values) in zip(layers, pixels) { layer.buffer.setPixels(values, in: shown) } }
        return try body()
    }

    func flattenedPNG() throws -> Data {
        placePendingObjects()
        return try encoded(as: .png)
    }
}
