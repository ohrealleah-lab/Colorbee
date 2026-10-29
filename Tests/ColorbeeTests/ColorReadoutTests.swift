import ColorbeeCore
import Testing
@testable import Colorbee

/// The status bar's color readout and the Eyedropper's Sample Size (FR-9.7 item 9).
@MainActor
struct ColorReadoutTests {
    /// Black paper with one white pixel at (5, 5).
    private func picture() -> Editor {
        let editor = makeEditor(width: 12, height: 12, background: .black)
        editor.canvas.activeLayer.buffer.row(5)[5] = .white
        return editor
    }

    @Test func theEyedropperAveragesItsSampleSize() {
        let editor = picture()
        editor.pickColor(at: pt(5.5, 5.5), secondary: false, allLayers: false)
        #expect(editor.color1 == .white)
        editor.eyedropperSampleSize = 3
        editor.pickColor(at: pt(5.5, 5.5), secondary: false, allLayers: true)
        // One white pixel in nine.
        #expect(editor.color1 == Pixel(r: 28, g: 28, b: 28))
        editor.eyedropperSampleSize = 5
        editor.pickColor(at: pt(6.5, 6.5), secondary: true, allLayers: false)
        #expect(editor.color2 == Pixel(r: 10, g: 10, b: 10))
    }

    @Test func theReadoutShowsWhatsUnderThePointerInSRGB() {
        let editor = picture()
        #expect(editor.pointerColor == nil)
        editor.pointer = IntPoint(x: 5, y: 5)
        #expect(editor.pointerColor == .white)
        // Display P3's most vivid red is outside sRGB: it reads as sRGB's reddest red.
        editor.canvas.activeLayer.buffer.row(2)[2] = Pixel(r: 255, g: 0, b: 0)
        editor.pointer = IntPoint(x: 2, y: 2)
        #expect(editor.pointerColor?.r == 255 && editor.pointerColor?.g == 0)
        // It reads every layer, as shown: a hidden-below layer doesn't count, an adjustment does.
        editor.addAdjustmentLayer(.invert)
        editor.pointer = IntPoint(x: 5, y: 5)
        #expect(editor.pointerColor == .black)
    }

    @Test func withTheEyedropperTheReadoutFollowsTheSampleSize() {
        let editor = picture()
        editor.pointer = IntPoint(x: 5, y: 5)
        editor.eyedropperSampleSize = 3
        #expect(editor.pointerColor == .white)
        editor.selectTool(.eyedropper)
        #expect(editor.pointerColor == Pixel(r: 28, g: 28, b: 28))
    }
}

/// Copying a color's hex (Leah, 2026-10-28): the status bar's eyedropper, and Edit ▸ Copy Color as Hex. The clipboard
/// itself is left alone here; these check the hex each would copy.
@MainActor
struct CopyColorHexTests {
    @Test func theStatusBarEyedropperGivesTheClickedColorsHexOnce() {
        let editor = makeEditor(width: 12, height: 12, background: .black)
        editor.canvas.activeLayer.buffer.row(5)[5] = Pixel(r: 58, g: 123, b: 213)
        editor.picksHexToCopy = true
        var refused = 0
        editor.onRefused = { refused += 1 }
        // Off the picture: a beep, and it stays on.
        #expect(editor.pickHexToCopy(at: pt(40, 40)) == nil && refused == 1 && editor.picksHexToCopy)
        let hex = editor.pickHexToCopy(at: pt(5.5, 5.5))
        #expect(hex?.count == 7 && hex?.hasPrefix("#") == true && !editor.picksHexToCopy)
        // The same as the readout shows there.
        editor.pointer = IntPoint(x: 5, y: 5)
        #expect(editor.pointerColorHex == hex)
    }
}
