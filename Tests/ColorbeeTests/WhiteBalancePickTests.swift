import ColorbeeCore
import Foundation
import Testing
@testable import Colorbee

/// The white-balance eyedropper (FR-9.7, stage 1b), driven the way `CanvasView` does: a click while it's on.
@MainActor
@Suite(.serialized)
struct WhiteBalancePickTests {
    /// Color Cast.png's gray card: blue, within Warmth and Tint's reach.
    private let card = Pixel(r: 132, g: 144, b: 165)

    private func isGray(_ pixel: Pixel) -> Bool {
        let channels = [Int(pixel.r), Int(pixel.g), Int(pixel.b)]
        return channels.max()! - channels.min()! <= 1
    }

    @Test func aClickInAdjustPhotoSetsWarmthAndTintAndTurnsTheDropperOff() {
        let editor = makeEditor(width: 32, height: 24, background: card)
        let before = editor.imageHash
        editor.beginEffect(.adjustPhoto)
        editor.toggleWhiteBalancePick()
        #expect(editor.isPickingWhiteBalance)
        #expect(editor.pickWhiteBalance(at: pt(10.5, 10.5)))
        #expect(!editor.isPickingWhiteBalance)
        #expect(editor.photoEdit.adjustments[.warmth] > 0)
        #expect(isGray(editor.photoEdit.colorTransform(card)))
        editor.applyEffect()
        #expect(editor.stepNames.count == 1)
        editor.undo()
        #expect(editor.imageHash == before)
    }

    @Test func itReadsThePictureBeforeAdjustPhotosOtherSettings() {
        let editor = makeEditor(width: 32, height: 24, background: card)
        editor.beginEffect(.adjustPhoto)
        editor.setPhotoEdit(PhotoEdit(filter: PhotoFilter.builtIn[1]))
        editor.toggleWhiteBalancePick()
        _ = editor.pickWhiteBalance(at: pt(5, 5))
        #expect(isGray(editor.photoEdit.colorTransform(card)))
        #expect(editor.photoEdit.filter?.name == "Vivid Warm")
        editor.cancelEffect()
    }

    @Test func aClickOnNothingBeepsAndKeepsTheDropperOn() {
        let editor = makeEditor(width: 32, height: 24, background: .clear)
        var refusals = 0
        editor.onRefused = { refusals += 1 }
        editor.beginEffect(.adjustPhoto)
        editor.toggleWhiteBalancePick()
        #expect(editor.pickWhiteBalance(at: pt(10, 10)))
        #expect(refusals == 1)
        #expect(editor.isPickingWhiteBalance)
        #expect(editor.photoEdit.isNeutral)
        editor.cancelWhiteBalancePick()
        #expect(!editor.isPickingWhiteBalance)
        #expect(editor.activeEffect == .adjustPhoto)
        editor.cancelEffect()
    }

    @Test func closingAdjustPhotoTurnsTheDropperOff() {
        let editor = makeEditor(width: 16, height: 16, background: card)
        editor.beginEffect(.adjustPhoto)
        editor.toggleWhiteBalancePick()
        editor.cancelEffect()
        #expect(!editor.isPickingWhiteBalance)
        // A click is then an ordinary click again.
        #expect(!editor.pickWhiteBalance(at: pt(4, 4)))
    }

    @Test func onAnAdjustPhotoLayerItReadsTheLayersBelowAsOneStep() {
        let editor = makeEditor(width: 32, height: 24, background: card)
        editor.addAdjustmentLayer(.photo(PhotoEdit(adjustments: PhotoAdjustments([.exposure: 10]))), named: "Adjust Photo")
        let steps = editor.stepNames.count
        let pixels = editor.canvas.layers[0].buffer.contentHash()
        editor.toggleWhiteBalancePick()
        #expect(editor.isPickingWhiteBalance)
        #expect(editor.pickWhiteBalance(at: pt(12, 12)))
        guard case .photo(let edit) = editor.canvas.activeLayer.adjustment else {
            Issue.record("Not an Adjust Photo layer")
            return
        }
        #expect(edit.adjustments[.exposure] == 10)
        #expect(isGray(edit.colorTransform(card)))
        #expect(editor.stepNames.count == steps + 1)
        #expect(editor.canvas.layers[0].buffer.contentHash() == pixels)
        // Choosing another layer leaves the dropper behind.
        editor.toggleWhiteBalancePick()
        editor.selectLayer(at: 0)
        #expect(!editor.isPickingWhiteBalance)
    }
}
