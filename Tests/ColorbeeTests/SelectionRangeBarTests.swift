import ColorbeeCore
import Testing
@testable import Colorbee

/// Edit ▸ Color Range… and Luminance Range… (FR-9.7 item 3), driven the way `CanvasView` and the bar do.
@MainActor
struct SelectionRangeBarTests {
    private let red = Pixel(r: 210, g: 40, b: 40)
    private let green = Pixel(r: 40, g: 180, b: 70)

    /// Gray paper with a red box at the left and a green one at the right.
    private func boxes() -> Editor {
        let editor = makeEditor()
        let buffer = editor.canvas.activeLayer.buffer
        for y in 10..<30 {
            for x in 5..<25 { buffer.row(y)[x] = red }
            for x in 40..<60 { buffer.row(y)[x] = green }
        }
        return editor
    }

    @Test func aClickedColorBecomesTheSelection() throws {
        let editor = boxes()
        editor.beginEffect(.colorRange)
        editor.beginCanvasToolDrag(at: pt(15.5, 20.5), viewPoint: .zero)
        #expect(editor.rangeColors == [red])
        editor.applyEffect()
        #expect(editor.activeEffect == nil)
        let mask = try #require(editor.canvas.selection.marquee)
        #expect(mask.bounds == IntRect(x: 5, y: 10, width: 20, height: 20))
        #expect(editor.stepNames.isEmpty)
    }

    @Test func shiftClickAddsAnotherColor() throws {
        let editor = boxes()
        editor.beginEffect(.colorRange)
        editor.beginCanvasToolDrag(at: pt(15.5, 20.5), viewPoint: .zero)
        editor.beginCanvasToolDrag(at: pt(50.5, 20.5), viewPoint: .zero, adding: true)
        #expect(editor.rangeColors == [red, green])
        editor.applyEffect()
        let mask = try #require(editor.canvas.selection.marquee)
        #expect(mask[10, 20] == 255 && mask[50, 20] == 255 && mask[32, 20] == 0)
    }

    @Test func returnWithNoColorClickedWaits() {
        let editor = boxes()
        editor.beginEffect(.colorRange)
        editor.applyEffect()
        #expect(editor.activeEffect == .colorRange)
        editor.cancelEffect()
        #expect(editor.canvas.selection.marquee == nil && editor.marqueePreview == nil)
    }

    @Test func itCombinesWithTheSelectionAsTheBarSays() throws {
        let editor = boxes()
        editor.selectionDrag(from: pt(40.5, 10.5), to: pt(60.5, 30.5))
        editor.beginEffect(.colorRange)
        editor.effectValues[1] = 1
        editor.beginCanvasToolDrag(at: pt(15.5, 20.5), viewPoint: .zero)
        editor.applyEffect()
        let mask = try #require(editor.canvas.selection.marquee)
        #expect(mask[10, 20] == 255 && mask[50, 20] == 255)
    }

    @Test func itReadsTheActiveLayerOrEverythingShown() throws {
        let editor = makeEditor()
        editor.addLayer()
        let top = editor.canvas.activeLayer.buffer
        for y in 0..<10 { for x in 0..<10 { top.row(y)[x] = red } }
        editor.selectLayer(at: 0)
        editor.beginEffect(.colorRange)
        editor.rangeSamplesAllLayers = false
        // On the gray layer underneath, the red isn't there to click.
        editor.beginCanvasToolDrag(at: pt(5.5, 5.5), viewPoint: .zero)
        #expect(editor.rangeColors.first == paper)
        editor.rangeSamplesAllLayers = true
        editor.beginCanvasToolDrag(at: pt(5.5, 5.5), viewPoint: .zero)
        #expect(editor.rangeColors.first == red)
        editor.cancelEffect()
        editor.wandSamplesAllLayers = false
    }

    @Test func luminanceRangeSelectsTheShadowsSoftly() throws {
        let editor = makeEditor(width: 64, height: 8)
        let buffer = editor.canvas.activeLayer.buffer
        for y in 0..<8 {
            for x in 0..<64 {
                let v = UInt8(x * 4)
                buffer.row(y)[x] = Pixel(r: v, g: v, b: v)
            }
        }
        editor.beginEffect(.luminanceRange)
        #expect(editor.effectValues[0] == 0 && editor.effectValues[1] == 30)
        editor.applyEffect()
        let mask = try #require(editor.canvas.selection.marquee)
        #expect(mask[0, 4] == 255 && mask[63, 4] == 0)
        #expect(mask.isSoft)
        // Highlights picks the other end.
        editor.beginEffect(.luminanceRange)
        editor.setLuminanceRange(.highlights)
        editor.applyEffect()
        let highlights = try #require(editor.canvas.selection.marquee)
        #expect(highlights[63, 4] == 255 && highlights[0, 4] == 0)
    }
}

/// Edit ▸ Graduated Selection (FR-9.7 item 3), dragged the way `CanvasView` does.
@MainActor
struct GraduatedSelectionBarTests {
    private func drag(_ editor: Editor, from start: Point2D, to end: Point2D, shift: Bool = false) {
        editor.beginCanvasToolDrag(at: start, viewPoint: editor.viewport.viewPoint(fromImage: start))
        editor.continueCanvasToolDrag(to: end, constrain: shift)
        editor.endCanvasToolDrag()
    }

    @Test func aDraggedLineFadesFromItsStartToItsEnd() throws {
        let editor = makeEditor()
        editor.beginEffect(.graduatedSelection)
        editor.applyEffect()
        #expect(editor.activeEffect == .graduatedSelection)
        drag(editor, from: pt(32, 10), to: pt(32, 50))
        editor.applyEffect()
        #expect(editor.activeEffect == nil)
        let mask = try #require(editor.canvas.selection.marquee)
        #expect(mask[20, 5] == 255 && mask[20, 55] == 0)
        #expect(mask[20, 25] > mask[20, 35] && mask.isSoft)
        #expect(editor.stepNames.isEmpty)
    }

    @Test func anEndCanBeDraggedBeforeApplying() throws {
        let editor = makeEditor()
        editor.beginEffect(.graduatedSelection)
        drag(editor, from: pt(32, 10), to: pt(32, 30))
        drag(editor, from: pt(32, 30), to: pt(32, 60))
        #expect(editor.graduatedLine == GraduatedSelection(start: pt(32, 10), end: pt(32, 60)))
        // A drag away from both ends draws a new line.
        drag(editor, from: pt(5, 5), to: pt(50, 5))
        #expect(editor.graduatedLine?.start == pt(5, 5))
        editor.cancelEffect()
        #expect(editor.canvas.selection.marquee == nil && editor.marqueePreview == nil)
    }

    @Test func shiftKeepsTheLineStraight() {
        let editor = makeEditor()
        editor.beginEffect(.graduatedSelection)
        drag(editor, from: pt(10, 10), to: pt(50, 13), shift: true)
        #expect(editor.graduatedLine?.end == pt(50, 10))
        editor.cancelEffect()
    }
}
