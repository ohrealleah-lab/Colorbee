import ColorbeeCore
import Testing
@testable import Colorbee

/// Smoothing (stage 31), driven as `CanvasView` feeds strokes. `smoothing` is set directly: only the palette bar's
/// slider saves it.
@MainActor
struct SmoothingAppTests {
    private func editor(tool: Tool, smoothing: Double) -> Editor {
        let editor = makeEditor(width: 96, height: 48)
        editor.selectTool(tool)
        editor.color1 = .black
        editor.smoothing = smoothing
        return editor
    }

    /// The columns with any paint on them.
    private func paintedColumns(_ editor: Editor) -> ClosedRange<Int>? {
        let layer = editor.canvas.activeLayer.buffer
        let columns = (0..<layer.width).filter { x in (0..<layer.height).contains { layer[x, $0] != paper } }
        guard let first = columns.first, let last = columns.last else { return nil }
        return first...last
    }

    @Test func smallWobblesDontReachThePictureUntilYouLetGo() throws {
        let editor = editor(tool: .brush, smoothing: 1)
        editor.beginStroke(at: pt(20.5, 24.5), secondary: false)
        for point in [pt(26.5, 27.5), pt(15.5, 21.5), pt(24.5, 20.5)] { editor.continueStroke(to: point, constrain: false) }
        // Only the dab where the stroke began.
        let started = try #require(paintedColumns(editor))
        #expect(started.upperBound < 24)
        editor.endStroke()
        // Letting go catches the line up to the pointer.
        #expect(try #require(paintedColumns(editor)).upperBound >= 24)
    }

    @Test func aSmoothedStrokeEndsWhereYouLetGo() throws {
        let editor = editor(tool: .brush, smoothing: 1)
        editor.stroke([pt(4.5, 24.5), pt(40.5, 24.5), pt(80.5, 24.5)])
        #expect(try #require(paintedColumns(editor)).upperBound >= 80)
    }

    @Test func thePencilIsNeverSmoothed() throws {
        let smooth = editor(tool: .pencil, smoothing: 1), plain = editor(tool: .pencil, smoothing: 0)
        for target in [smooth, plain] {
            target.beginStroke(at: pt(20.5, 24.5), secondary: false)
            target.continueStroke(to: pt(30.5, 30.5), constrain: false)
        }
        #expect(smooth.imageHash == plain.imageHash)
    }

    @Test func atZeroItDrawsAsBefore() {
        let points = [pt(4.5, 10.5), pt(20.5, 30.5), pt(22.5, 12.5), pt(70.5, 40.5)]
        let smoothed = editor(tool: .brush, smoothing: 0)
        smoothed.stroke(points)
        let plain = makeEditor(width: 96, height: 48)
        plain.selectTool(.brush)
        plain.color1 = .black
        plain.smoothing = 0
        plain.stroke(points)
        #expect(smoothed.imageHash == plain.imageHash && smoothed.stepNames.count == 1)
    }

    @Test func shiftStillDrawsAStraightLine() {
        let editor = editor(tool: .brush, smoothing: 1)
        editor.stroke([pt(10.5, 24.5), pt(40.5, 27.5), pt(80.5, 21.5)], constrain: true)
        let rows = editor.canvas.activeLayer.buffer.rowsChanged(from: paper)
        #expect(rows.allSatisfy { abs($0 - 24) <= 3 })
    }
}
