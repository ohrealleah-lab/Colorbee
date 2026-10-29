import ColorbeeCore
import Testing
@testable import Colorbee

/// Adjust Photo's hand (FR-9.7 item 6): dragging on the picture changes the slider for what's under the pointer.
@MainActor
struct PictureDragTests {
    private let dark = Pixel(r: 30, g: 32, b: 28), sky = Pixel(r: 70, g: 110, b: 220)

    /// Dark hills along the bottom, blue sky at the top, gray paper between.
    private func picture() -> Editor {
        let editor = makeEditor()
        editor.canvas.activeLayer.buffer.fill(dark, in: IntRect(x: 0, y: 44, width: 64, height: 20))
        editor.canvas.activeLayer.buffer.fill(sky, in: IntRect(x: 0, y: 0, width: 64, height: 20))
        return editor
    }

    private func drag(_ editor: Editor, at point: Point2D, by dy: Double) -> Bool {
        guard editor.beginPictureDrag(at: point, viewY: 300) else { return false }
        editor.continuePictureDrag(viewY: 300 + dy / 2)
        editor.continuePictureDrag(viewY: 300 + dy)
        editor.endPictureDrag()
        return true
    }

    @Test func draggingUpOnShadowsRaisesTheirRegion() {
        let editor = picture()
        editor.beginEffect(.adjustPhoto)
        #expect(!drag(editor, at: pt(10, 50), by: -40))
        editor.togglePicturePick(.toneCurve)
        #expect(drag(editor, at: pt(10, 50), by: -40))
        // 30 is below the first split (25%): Shadows, 40 points up at half a step a point.
        #expect(editor.photoEdit.toneCurve?[.shadows] == 20)
        #expect(editor.photoEdit.toneCurve?[.darks] == 0)
        // The hand stays on for another drag; down is less.
        #expect(drag(editor, at: pt(10, 30), by: 60))
        #expect(editor.photoEdit.toneCurve?[.highlights] == -30)
        editor.cancelPicturePick()
        #expect(!editor.isPickingFromPicture)
        editor.cancelEffect()
    }

    @Test func theTargetIsReadFromThePictureBeforeAdjustPhoto() {
        let editor = picture()
        editor.beginEffect(.adjustPhoto)
        editor.setPhotoEdit(PhotoEdit(adjustments: PhotoAdjustments([.exposure: 100])))
        editor.togglePicturePick(.toneCurve)
        // Brightened, the hills might read as Darks; as they were, they're Shadows.
        #expect(drag(editor, at: pt(10, 50), by: -20))
        #expect(editor.photoEdit.toneCurve?[.shadows] == 10)
        editor.cancelEffect()
    }

    @Test func draggingDownOnTheSkyLowersBlueSaturation() {
        let editor = picture()
        editor.beginEffect(.adjustPhoto)
        editor.togglePicturePick(.colorMixer(.hue))
        editor.followMixerTab(.saturation)
        #expect(editor.isPicking(.colorMixer(.saturation)))
        #expect(drag(editor, at: pt(30, 10), by: 80))
        #expect(editor.photoEdit.mixer?[.saturation, .blue] == -40)
        // A gray has no color to change: a beep, and nothing changes.
        var refused = 0
        editor.onRefused = { refused += 1 }
        #expect(drag(editor, at: pt(30, 32), by: 80))
        #expect(refused == 1 && editor.photoEdit.mixer?[.saturation, .blue] == -40)
        editor.cancelEffect()
    }

    /// Review V, finding 6: Esc before letting go keeps the change as its step.
    @Test func escMidDragOnALayerKeepsItsStep() {
        let editor = picture()
        editor.addAdjustmentLayer(.adjustPhoto)
        let steps = editor.stepNames.count
        editor.togglePicturePick(.toneCurve)
        #expect(editor.beginPictureDrag(at: pt(10, 50), viewY: 300))
        editor.continuePictureDrag(viewY: 260)
        editor.cancelPicturePick()
        editor.endPictureDrag()
        #expect(editor.stepNames.count == steps + 1)
    }

    @Test func onAnAdjustPhotoLayerADragIsOneStep() {
        let editor = picture()
        editor.addAdjustmentLayer(.adjustPhoto)
        let steps = editor.stepNames.count
        editor.togglePicturePick(.toneCurve)
        #expect(drag(editor, at: pt(10, 50), by: -40))
        guard case .photo(let edit) = editor.canvas.activeLayer.adjustment else { Issue.record("No Adjust Photo layer"); return }
        #expect(edit.toneCurve?[.shadows] == 20)
        #expect(editor.stepNames.count == steps + 1)
        editor.undo()
        guard case .photo(let undone) = editor.canvas.activeLayer.adjustment else { Issue.record("No Adjust Photo layer"); return }
        #expect(undone.toneCurve == nil)
    }
}
