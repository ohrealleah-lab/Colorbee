import ColorbeeCore
import Foundation
import Testing
@testable import Colorbee

/// Saved filters (stage 1a): what Save as Filter keeps, and that tests never touch the filters on disk.
@MainActor
@Suite(.serialized)
struct FilterStoreTests {
    @Test func testsKeepFiltersInMemoryOnly() {
        #expect(SettingsFolder.current == nil)
    }

    @Test func saveAsFilterKeepsTheVignetteAndLeavesSharpnessOnThePanel() {
        let editor = makeEditor()
        let edit = PhotoEdit(adjustments: PhotoAdjustments([.saturation: 30, .vignette: 60, .sharpness: 25]))
        guard let after = editor.saveFilter(from: edit, named: "Dark Edges Test") else {
            Issue.record("Nothing saved")
            return
        }
        defer { FilterStore.shared.delete(after.filter?.name ?? "") }
        #expect(after.adjustments == PhotoAdjustments([.sharpness: 25]))
        #expect(after.filter?.steps == [.photo(PhotoEdit(adjustments: PhotoAdjustments([.saturation: 30, .vignette: 60])))])
        #expect(after.vignetteAmounts == edit.vignetteAmounts)
    }
}
