import AppKit
import ColorbeeCore
import Foundation
import Testing
@testable import Colorbee

/// Using Adjust Photo settings again (FR-9.7 item 4, stage 2): Same as Last, and copying and pasting settings.
@MainActor
@Suite(.serialized)
struct PhotoSettingsTests {
    private let look = PhotoEdit(adjustments: PhotoAdjustments([.exposure: 20]), filter: PhotoFilter.builtIn[0], filterIntensity: 100)
    private let store = PhotoSettingsStore.shared

    private func picture() -> Editor {
        let editor = makeEditor(width: 24, height: 16)
        let buffer = editor.canvas.activeLayer.buffer
        for y in 0..<16 { for x in 0..<24 { buffer.row(y)[x] = Pixel(r: UInt8(40 + x * 6), g: UInt8(90 + y * 4), b: 120) } }
        return editor
    }

    private func adjustPhoto(_ editor: Editor, _ edit: PhotoEdit) {
        editor.beginEffect(.adjustPhoto)
        editor.setPhotoEdit(edit)
        editor.applyEffect()
    }

    /// Same as Last is worked out in the background (review V, finding 4).
    private func waitForSameAsLast(_ editor: Editor) async throws {
        for _ in 0..<500 where editor.sameAsLastRunning { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!editor.sameAsLastRunning)
    }

    @Test func sameAsLastAppliesTheLastSettingsAsOneStep() async throws {
        store.last = nil
        let first = picture(), second = picture()
        adjustPhoto(first, look)
        #expect(store.last == look)
        second.applySameAsLastPhoto()
        #expect(second.stepNames.isEmpty)
        try await waitForSameAsLast(second)
        #expect(second.stepNames == ["Adjust Photo"])
        #expect(second.imageHash == first.imageHash)
        second.undo()
        #expect(second.imageHash == picture().imageHash)
    }

    @Test func sameAsLastAppliesNothingIfTheImageChangesMeanwhile() async throws {
        let editor = picture()
        store.last = look
        editor.applySameAsLastPhoto()
        editor.applyAdjustment(.invert)
        try await waitForSameAsLast(editor)
        #expect(editor.stepNames.count == 1 && editor.stepNames.last != "Adjust Photo")
    }

    @Test func asAdjustmentLayerAlsoCountsAsLast() {
        store.last = nil
        let editor = picture()
        editor.beginEffect(.adjustPhoto)
        editor.setPhotoEdit(look)
        editor.photoAsAdjustmentLayer()
        #expect(store.last == look)
    }

    @Test func pasteOpensAdjustPhotoWithTheCopiedSettings() {
        let source = picture(), target = picture()
        source.beginEffect(.adjustPhoto)
        source.setPhotoEdit(look)
        let clipboard = NSPasteboard.general.changeCount
        source.copyPhotoSettings()
        source.cancelEffect()
        #expect(store.copied == look)
        #expect(NSPasteboard.general.changeCount == clipboard)
        let before = target.imageHash
        target.pastePhotoSettings()
        #expect(target.activeEffect == .adjustPhoto)
        #expect(target.photoEdit == look)
        target.cancelEffect()
        #expect(target.imageHash == before)
        target.pastePhotoSettings()
        target.applyEffect()
        #expect(target.stepNames == ["Adjust Photo"])
    }

    @Test func layersCopyAndPasteToo() {
        let source = picture(), target = picture()
        source.addAdjustmentLayer(.photo(look), named: "Adjust Photo")
        source.copyPhotoSettings()
        #expect(store.copied == look)
        target.addAdjustmentLayer(.photo(PhotoEdit()), named: "Adjust Photo")
        let steps = target.stepNames.count
        target.pastePhotoSettings()
        #expect(target.activePhotoLayerEdit == look)
        #expect(target.stepNames.count == steps + 1)
        let other = picture()
        other.pastePhotoSettingsAsLayer()
        #expect(other.canvas.layers.count == 2)
        #expect(other.activePhotoLayerEdit == look)
        #expect(other.canvas.activeLayer.name == "Vivid")
    }

    @Test func nothingToUseBeeps() {
        store.last = nil
        store.copied = nil
        let editor = picture()
        var refusals = 0
        editor.onRefused = { refusals += 1 }
        editor.applySameAsLastPhoto()
        editor.pastePhotoSettings()
        editor.copyPhotoSettings()
        #expect(refusals == 3)
        #expect(editor.stepNames.isEmpty)
    }
}
