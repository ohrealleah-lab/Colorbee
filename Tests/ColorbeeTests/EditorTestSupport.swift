import ColorbeeCore
import Foundation
import Testing
@testable import Colorbee

/// Light gray, so black paint and a white eraser both show.
let paper = Pixel(r: 200, g: 200, b: 200, a: 255)

/// A small canvas: Debug pixel loops are slow, and every behavior here shows at this size.
@MainActor
func makeEditor(width: Int = 64, height: Int = 64, background: Pixel = paper) -> Editor {
    Editor(canvas: Canvas(size: IntSize(width: width, height: height), colorSpace: Canvas.defaultColorSpace, background: background))
}

func pt(_ x: Double, _ y: Double) -> Point2D {
    Point2D(x: x, y: y)
}

/// A wobbly, mostly horizontal path, as a hand drags along a line of text.
let wobblyPath = [pt(10.5, 20.5), pt(14.5, 21.4), pt(20.5, 19.6), pt(30.5, 22.4), pt(40.5, 20.9), pt(50.5, 19.2)]

@MainActor
extension Editor {
    /// The whole image as shown, so changes on any layer count.
    var imageHash: Int { canvas.flattened().contentHash() }

    var stepNames: [String] { history.steps.filter { !$0.isUndone }.map(\.name) }

    /// A Pencil, Brush or Eraser drag, the way `CanvasView` feeds it: press, moves, release.
    func stroke(_ points: [Point2D], constrain: Bool = false, secondary: Bool = false) {
        beginStroke(at: points[0], secondary: secondary)
        for point in points.dropFirst() { continueStroke(to: point, constrain: constrain) }
        endStroke()
    }

    func selectionDrag(from start: Point2D, to end: Point2D, shift: Bool = false, option: Bool = false, shiftDown: Bool? = nil) {
        beginSelectionDrag(at: start, modifiers: DragModifiers(shift: shift, option: option))
        continueSelectionDrag(to: end, shiftDown: shiftDown ?? shift)
        endSelectionDrag(at: end)
    }

    func shapeDrag(from start: Point2D, to end: Point2D) {
        beginShapeDrag(at: start, viewPoint: viewport.viewPoint(fromImage: start), secondary: false, clickCount: 1)
        continueShapeDrag(to: end, shiftDown: false)
        endShapeDrag()
    }

    /// A click with the Step Badge tool: places any badge waiting and starts the next one here.
    func badgeClick(at point: Point2D) {
        beginBadge(at: point, secondary: false)
        endBadge()
    }

    func isSelected(_ x: Int, _ y: Int) -> Bool {
        canvas.selection.contains(IntPoint(x: x, y: y))
    }
}

extension PixelBuffer {
    /// The rows with any pixel that isn't `background`.
    func rowsChanged(from background: Pixel) -> Set<Int> {
        var rows = Set<Int>()
        for y in 0..<height {
            for x in 0..<width where self[x, y] != background {
                rows.insert(y)
                break
            }
        }
        return rows
    }

    func columnsChanged(from background: Pixel) -> Set<Int> {
        var columns = Set<Int>()
        for x in 0..<width {
            for y in 0..<height where self[x, y] != background {
                columns.insert(x)
                break
            }
        }
        return columns
    }
}

/// Waits for background work the Editor started (a Remove fill) to land on the main actor.
@MainActor
func waitUntil(timeout: Duration = .seconds(20), _ condition: () -> Bool) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while !condition() {
        guard clock.now < deadline else {
            Issue.record("Timed out waiting")
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}
