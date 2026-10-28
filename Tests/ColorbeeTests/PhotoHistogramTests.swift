import ColorbeeCore
import Testing
@testable import Colorbee

/// Adjust Photo's histogram and clipping warnings (FR-9.7 item 6).
@MainActor
struct PhotoHistogramTests {
    /// Waits for the histogram to be worked out again, as it is soon after a change.
    private func refreshed(_ editor: Editor) async -> Histogram? {
        let old = editor.photoHistogram
        editor.refreshPhotoHistogram()
        for _ in 0..<50 where editor.photoHistogram == old { try? await Task.sleep(for: .milliseconds(10)) }
        return editor.photoHistogram
    }

    @Test func theHistogramFollowsTheSliders() async {
        let editor = makeEditor(width: 24, height: 24)
        editor.beginEffect(.adjustPhoto)
        let before = await refreshed(editor)?.highestValue
        editor.setPhotoEdit(PhotoEdit(adjustments: PhotoAdjustments([.exposure: 80])))
        editor.applyEffect()
        editor.beginEffect(.adjustPhoto)
        let after = await refreshed(editor)?.highestValue
        #expect(before != nil && (after ?? 0) > before!)
        editor.cancelEffect()
    }

    @Test func manyChangesInARowMakeOneHistogramAndTheLastIsShown() async {
        let editor = makeEditor(width: 24, height: 24)
        editor.beginEffect(.adjustPhoto)
        _ = await refreshed(editor)
        // Right after one, the next waits; changes meanwhile join it.
        for _ in 0..<5 { editor.refreshPhotoHistogram() }
        let shown = editor.photoHistogram
        editor.setPhotoEdit(PhotoEdit(adjustments: PhotoAdjustments([.exposure: 80])))
        editor.applyEffect()
        editor.beginEffect(.adjustPhoto)
        editor.refreshPhotoHistogram()
        #expect(editor.photoHistogram == shown)
        try? await Task.sleep(for: .milliseconds(300))
        #expect(editor.photoHistogram != shown)
        editor.cancelEffect()
    }

    @Test func warningsShowOnlyWithAdjustPhotosControlsAndNeverChangePixels() {
        let editor = makeEditor()
        editor.clipsHighlights = true
        #expect(!editor.showsPhotoControls)
        let hash = editor.imageHash
        editor.beginEffect(.adjustPhoto)
        #expect(editor.showsPhotoControls)
        editor.applyEffect()
        #expect(editor.imageHash == hash)
        editor.clipsHighlights = false
    }

    @Test func anAdjustPhotoLayerShowsTheControlsInTheAdjustmentsPanel() {
        let editor = makeEditor()
        editor.addAdjustmentLayer(.adjustPhoto)
        editor.isSidebarOpen = true
        editor.showsAdjustmentsPanel = true
        #expect(editor.showsPhotoControls)
        editor.showsAdjustmentsPanel = false
        #expect(!editor.showsPhotoControls)
    }
}
