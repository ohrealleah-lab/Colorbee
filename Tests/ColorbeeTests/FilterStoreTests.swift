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

    @Test func saveAsFilterKeepsTheVignetteShapeAndGrain() {
        let editor = makeEditor()
        var effects = PhotoEffects()
        effects.roundness = 80
        effects.grainRoughness = 20
        let edit = PhotoEdit(adjustments: PhotoAdjustments([.vignette: -30, .grain: 40, .noiseReduction: 20]), effects: effects)
        guard let after = editor.saveFilter(from: edit, named: "Film Test") else {
            Issue.record("Nothing saved")
            return
        }
        defer { FilterStore.shared.delete(after.filter?.name ?? "") }
        #expect(after.adjustments == PhotoAdjustments([.noiseReduction: 20]) && after.effects == nil)
        #expect(after.vignettes == edit.vignettes && after.grains == edit.grains)
    }

    private let looks = URL(filePath: #filePath).deletingLastPathComponent()
        .appending(path: "../../TestImages/Photo Editing/Looks")

    @Test func aCubeLookImportsAsAFilterNamedFromItsTitle() async throws {
        let store = FilterStore.shared
        let name = try await store.importFilter(from: looks.appending(path: "Warm.cube"))
        defer { store.delete(name) }
        #expect(name == "Warm")
        let filter = try #require(store.filter(named: name))
        guard case .look = filter.steps.first else { Issue.record("Not a look"); return }
        // Gray paper warms, and as an adjustment layer too.
        let editor = makeEditor(width: 8, height: 8)
        editor.beginEffect(.adjustPhoto)
        editor.setPhotoEdit(PhotoEdit(filter: filter, filterIntensity: 100))
        editor.photoAsAdjustmentLayer()
        let flat = editor.canvas.flattened()
        let pixel = withExtendedLifetime(flat) { flat.row(2)[2] }
        #expect(pixel.r > paper.r && pixel.b < paper.b)
        #expect(editor.canvas.activeLayer.adjustment == .photo(PhotoEdit(filter: filter, filterIntensity: 100)))
    }

    @Test func aLookWithNoTitleIsNamedFromTheFile() async throws {
        let name = try await FilterStore.shared.importFilter(from: looks.appending(path: "Identity.cube"))
        defer { FilterStore.shared.delete(name) }
        #expect(name == "Identity")
    }

    @Test func unreadableLooksAddNothing() async throws {
        let store = FilterStore.shared
        let count = store.custom.count
        await #expect(throws: CubeFile.ReadError.oneDimensional) { try await store.importFilter(from: looks.appending(path: "Curve 1D.cube")) }
        let text = FileManager.default.temporaryDirectory.appending(path: "Not a look \(UUID()).cube")
        try Data("Shopping list: eggs, milk".utf8).write(to: text)
        defer { try? FileManager.default.removeItem(at: text) }
        await #expect(throws: CubeFile.ReadError.damaged) { try await store.importFilter(from: text) }
        #expect(store.custom.count == count)
    }
}
