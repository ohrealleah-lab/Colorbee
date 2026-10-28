import ColorbeeCore
import Testing
@testable import Colorbee

/// Edit ▸ Paste in Place (FR-10.1). The clipboard itself isn't used here, so a test never replaces what Leah copied:
/// these check the place Copy records and where Paste in Place puts the pixels.
@MainActor
struct PasteInPlaceTests {
    private func boxed(_ editor: Editor = makeEditor()) -> Editor {
        editor.selectionDrag(from: pt(30.5, 40.5), to: pt(50.5, 55.5))
        return editor
    }

    @Test func copyRecordsWhereTheSelectionIs() throws {
        let editor = boxed()
        let bounds = try #require(editor.canvas.selection.marquee).bounds
        _ = editor.selectedPixels()
        #expect(editor.copiedPlace(merged: false) == IntPoint(x: bounds.minX, y: bounds.minY))
        // With nothing selected, Copy takes the whole image, from the top-left.
        editor.deselect()
        #expect(editor.copiedPlace(merged: false) == IntPoint(x: 0, y: 0))
    }

    @Test func aMovedSelectionRecordsWhereItIsNow() throws {
        let editor = boxed()
        let bounds = try #require(editor.canvas.selection.marquee).bounds
        editor.nudgeSelection(dx: 5, dy: -3)
        #expect(editor.copiedPlace(merged: false) == IntPoint(x: bounds.minX + 5, y: bounds.minY - 3))
    }

    @Test func pastesExactlyWhereItWasCopied() throws {
        let editor = boxed()
        let bounds = try #require(editor.canvas.selection.marquee).bounds
        let pixels = try #require(editor.selectedPixels())
        let place = editor.copiedPlace(merged: false)
        editor.deselect()
        editor.paste(pixels, inPlaceAt: place)
        #expect(editor.canvas.selection.floating?.destination == bounds)
    }

    @Test func inAnotherImageItLandsAtTheSamePlaceWhenItFits() throws {
        let source = boxed(makeEditor(width: 64, height: 64))
        let pixels = try #require(source.selectedPixels())
        let place = source.copiedPlace(merged: false)
        let other = makeEditor(width: 48, height: 48)
        other.paste(pixels, inPlaceAt: place)
        #expect(other.canvas.selection.floating?.destination.minX == place.x)
        #expect(other.canvas.selection.floating?.destination.minY == place.y)
    }

    @Test func offTheCanvasOrWithNoPlaceItPastesAsPasteDoes() throws {
        let source = boxed()
        let pixels = try #require(source.selectedPixels())
        let small = makeEditor(width: 20, height: 20)
        small.paste(pixels, inPlaceAt: source.copiedPlace(merged: false))
        let plain = makeEditor(width: 20, height: 20)
        plain.paste(pixels)
        #expect(small.canvas.selection.floating?.destination == plain.canvas.selection.floating?.destination)
        let fromAnotherApp = makeEditor()
        fromAnotherApp.paste(pixels, inPlaceAt: nil)
        let plainBig = makeEditor()
        plainBig.paste(pixels)
        #expect(fromAnotherApp.canvas.selection.floating?.destination == plainBig.canvas.selection.floating?.destination)
    }
}
