import ColorbeeCore
import Testing
@testable import Colorbee

/// Stage 34b (§23, 2026-11-20): Esc on floating pixels, hidden layers refusing pixel changes, and Batch Redact needing a
/// selection.
@MainActor
@Suite(.serialized)
struct SelectionsAndLayersTests {
    private func picture() -> Editor {
        let editor = makeEditor(width: 40, height: 30)
        editor.canvas.activeLayer.buffer.fill(Pixel(r: 200, g: 30, b: 30), in: IntRect(x: 8, y: 8, width: 10, height: 8))
        editor.selectTool(.rectangleSelect)
        return editor
    }

    private final class Changes { var count = 0 }

    @Test func escOnAMovedPasteTakesItAwayWithNothingToRedo() {
        let editor = picture()
        let before = editor.imageHash
        // The document's changed mark: back to zero means a saved picture isn't marked as changed after Esc.
        let changes = Changes()
        editor.onDocumentChange = { change in
            switch change {
            case .undone: changes.count -= 1
            default: changes.count += 1
            }
        }
        editor.paste(PixelBuffer(width: 5, height: 5, fill: .black), at: IntPoint(x: 2, y: 2))
        editor.selectionDrag(from: pt(4, 4), to: pt(14, 9))
        editor.nudgeSelection(dx: 1, dy: 0)
        #expect(editor.canvas.selection.floating != nil)

        #expect(editor.cancelFloating())
        #expect(editor.imageHash == before && editor.canvas.selection.isEmpty && editor.redoActionName == nil)
        #expect(changes.count == 0)
    }

    @Test func escPutsLiftedPixelsBackAndKeepsTheMarquee() {
        let editor = picture()
        let before = editor.imageHash
        editor.selectionDrag(from: pt(8, 8), to: pt(17.9, 15.9))
        editor.selectionDrag(from: pt(10, 10), to: pt(25, 18))
        editor.nudgeSelection(dx: 0, dy: -1)
        #expect(editor.imageHash != before)

        #expect(editor.cancelFloating())
        #expect(editor.imageHash == before && editor.canvas.selection.marquee != nil && editor.redoActionName == nil)
    }

    @Test func escOnAPlainMarqueeStillDeselects() {
        let editor = picture()
        editor.selectionDrag(from: pt(8, 8), to: pt(17.9, 15.9))
        #expect(!editor.cancelFloating())
        #expect(editor.canvas.selection.marquee != nil)
    }

    @Test func aHiddenLayerRefusesPaintAndSaysWhy() {
        let editor = picture()
        editor.setLayerVisible(false, at: 0)
        let pixels = editor.canvas.activeLayer.buffer.contentHash()
        editor.selectTool(.brush)
        editor.stroke([pt(2.5, 4.5), pt(30.5, 4.5)])
        #expect(editor.canvas.activeLayer.buffer.contentHash() == pixels)
        #expect(editor.notice?.text == "This layer is hidden. Show it to change it." && !editor.activeLayerTakesEdits)
        #expect(editor.activeLayerIsHidden)

        editor.setLayerVisible(true, at: 0)
        editor.stroke([pt(2.5, 4.5), pt(30.5, 4.5)])
        #expect(editor.canvas.activeLayer.buffer.contentHash() != pixels)
    }

    @Test func aLayerInAHiddenGroupIsHiddenToo() throws {
        let editor = picture()
        editor.addLayer()
        editor.groupLayers()
        let group = try #require(editor.canvas.layers.firstIndex { $0.isGroup })
        let inside = try #require(editor.canvas.layers.firstIndex { !$0.isGroup && $0.groupID != nil })
        editor.setLayerVisible(false, at: group)
        editor.selectLayer(at: inside)
        #expect(editor.activeLayerIsHidden && !editor.activeLayerTakesEdits)
    }

    @Test func redactionAndWholeImageCommandsStillWorkOnAHiddenLayer() {
        let editor = picture()
        editor.setLayerVisible(false, at: 0)
        let size = editor.canvas.size
        editor.apply(Orientation.rotate90Clockwise)
        #expect(editor.canvas.size == IntSize(width: size.height, height: size.width))

        editor.selectionDrag(from: pt(2, 2), to: pt(10, 10))
        let pixels = editor.canvas.layers[0].buffer.contentHash()
        editor.applySolidFill()
        #expect(editor.canvas.layers[0].buffer.contentHash() != pixels)
    }

    @Test func batchRedactWaitsForASelection() {
        let editor = picture()
        editor.beginBatchRedact(.gaussianBlur)
        #expect(editor.activeEffect == nil)
        editor.selectionDrag(from: pt(2, 2), to: pt(10, 10))
        editor.beginBatchRedact(.pixelate)
        #expect(editor.activeEffect == .pixelate)
        editor.cancelEffect()
    }
}
