import ColorbeeCore
import Testing
@testable import Colorbee

/// Sharpness's and Noise Reduction's finer settings (FR-9.7 item 5) in the app.
@MainActor
struct PhotoDetailAppTests {
    /// A light square on a dark ground, so sharpening and its mask both show.
    private func picture() -> Editor {
        let editor = makeEditor(width: 32, height: 32, background: Pixel(r: 60, g: 60, b: 60))
        editor.canvas.activeLayer.buffer.fill(Pixel(r: 190, g: 190, b: 190), in: IntRect(x: 8, y: 8, width: 16, height: 16))
        return editor
    }

    private func sharpening(masking: Double) -> PhotoEdit {
        var detail = PhotoDetail()
        detail.masking = masking
        return PhotoEdit(adjustments: PhotoAdjustments([.sharpness: 70]), detail: detail)
    }

    @Test func applyNeverAppliesTheMaskView() {
        let editor = picture(), expected = picture()
        for target in [editor, expected] {
            target.beginEffect(.adjustPhoto)
            var edit = sharpening(masking: 60)
            edit.showsSharpeningMask = target === editor
            target.setPhotoEdit(edit)
        }
        editor.applyEffect()
        expected.applyEffect()
        #expect(editor.imageHash == expected.imageHash)
        #expect(PhotoSettingsStore.shared.last?.showsSharpeningMask == false)
        #expect(PhotoSettingsStore.shared.last?.detail?.masking == 60)
    }

    @Test func asAnAdjustmentLayerTheSettingsAreKeptWithoutTheMaskView() {
        let editor = picture()
        editor.beginEffect(.adjustPhoto)
        var edit = sharpening(masking: 40)
        edit.showsSharpeningMask = true
        editor.setPhotoEdit(edit)
        editor.photoAsAdjustmentLayer()
        guard case .photo(let kept) = editor.canvas.activeLayer.adjustment else { Issue.record("No Adjust Photo layer"); return }
        #expect(!kept.showsSharpeningMask && kept.detail?.masking == 40)
    }

    /// QuadUniforms must lay out as Shaders.metal's struct does: float4s on 16-byte boundaries.
    @Test func theShaderSeesTheDetailSettingsWhereItLooks() {
        #expect(MemoryLayout<QuadUniforms>.offset(of: \.detailParams) == 144)
        #expect(MemoryLayout<QuadUniforms>.offset(of: \.detailParams2) == 160)
        #expect(MemoryLayout<QuadUniforms>.offset(of: \.clipWarnings) == 176)
        #expect(MemoryLayout<QuadUniforms>.stride == 192)
    }
}
