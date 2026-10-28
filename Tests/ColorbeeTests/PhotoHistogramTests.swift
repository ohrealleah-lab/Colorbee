import ColorbeeCore
import Testing
@testable import Colorbee

/// Adjust Photo's histogram and clipping warnings (FR-9.7 item 6).
@MainActor
struct PhotoHistogramTests {
    @Test func theHistogramFollowsTheSliders() async {
        let editor = makeEditor(width: 24, height: 24)
        editor.beginEffect(.adjustPhoto)
        editor.refreshPhotoHistogram()
        await Task.yield()
        let before = editor.photoHistogram?.highestValue
        editor.setPhotoEdit(PhotoEdit(adjustments: PhotoAdjustments([.exposure: 80])))
        editor.applyEffect()
        editor.beginEffect(.adjustPhoto)
        editor.refreshPhotoHistogram()
        await Task.yield()
        #expect(before != nil && (editor.photoHistogram?.highestValue ?? 0) > before!)
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
