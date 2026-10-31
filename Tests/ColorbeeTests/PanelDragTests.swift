import AppKit
import ColorbeeCore
import Foundation
import SwiftUI
import Testing
@testable import Colorbee

/// What dragging in the photo panels does: points on the Curves graph, the tone curve's split handles, the color
/// wheels, and sliding on a slider's name or scrubbing a number.
@MainActor
struct PanelDragTests {
    // MARK: Curves graph

    /// 265 points square, so the plot inside its 5-point inset is exactly 255 across: one point per level.
    private let graph = CurveDrag(size: CGSize(width: 265, height: 265))
    private let straight = [Curves.Point(x: 0, y: 0), Curves.Point(x: 255, y: 255)]

    private func drag(_ points: [Curves.Point], from start: CGPoint, by moves: [CGSize]) -> (points: [Curves.Point]?, drag: CurveDrag) {
        var drag = graph
        var result: [Curves.Point]? = points
        for move in moves {
            result = drag.moved(result ?? points, start: start, location: CGPoint(x: start.x + move.width, y: start.y + move.height), translation: move)
        }
        return (result, drag)
    }

    @Test func aGraphPositionIsALevelUpwardFromTheBottomLeft() {
        #expect(graph.location(of: Curves.Point(x: 0, y: 0)) == CGPoint(x: 5, y: 260))
        #expect(graph.location(of: Curves.Point(x: 255, y: 255)) == CGPoint(x: 260, y: 5))
        #expect(graph.value(at: CGPoint(x: 133, y: 132)) == Curves.Point(x: 128, y: 128))
        // Past the edges it stops at 0 and 255.
        #expect(graph.value(at: CGPoint(x: -40, y: 400)) == Curves.Point(x: 0, y: 0))
        #expect(graph.value(at: CGPoint(x: 900, y: -9)) == Curves.Point(x: 255, y: 255))
    }

    @Test func aClickOnEmptyGraphAddsAPointThere() {
        let (points, drag) = drag(straight, from: CGPoint(x: 105, y: 200), by: [.zero])
        #expect(points == [Curves.Point(x: 0, y: 0), Curves.Point(x: 100, y: 60), Curves.Point(x: 255, y: 255)])
        #expect(drag.dragging == 1)
    }

    /// A press within 10 points of a point grabs it, and it moves by the drag from where it was, so a click that
    /// misses its center doesn't shift it.
    @Test func aPressNearAPointGrabsItAndMovesItByTheDrag() {
        let curve = [straight[0], Curves.Point(x: 128, y: 128), straight[1]]
        #expect(drag(curve, from: CGPoint(x: 137, y: 129), by: [.zero]).points == curve)
        let (points, _) = drag(curve, from: CGPoint(x: 137, y: 129), by: [CGSize(width: 4, height: -6), CGSize(width: 10, height: -20)])
        #expect(points == [straight[0], Curves.Point(x: 138, y: 148), straight[1]])
    }

    /// Review D, finding 3: a press at an end point's level, away from it, moves that end point instead of adding a
    /// second point at the same level.
    @Test func aPressAtAnEndPointsLevelGrabsTheEndPoint() {
        let (points, _) = drag(straight, from: CGPoint(x: 5, y: 100), by: [CGSize(width: 0, height: -50)])
        #expect(points == [Curves.Point(x: 0, y: 50), straight[1]])
    }

    @Test func aPointStaysBetweenItsNeighbors() {
        let curve = [straight[0], Curves.Point(x: 100, y: 80), Curves.Point(x: 150, y: 160), straight[1]]
        let start = graph.location(of: curve[1])
        #expect(drag(curve, from: start, by: [CGSize(width: 150, height: 0)]).points?[1] == Curves.Point(x: 149, y: 80))
        #expect(drag(curve, from: start, by: [CGSize(width: -115, height: 0)]).points?[1] == Curves.Point(x: 1, y: 80))
    }

    @Test func draggingAMiddlePointOffTheGraphRemovesItButNotAnEndPoint() {
        let curve = [straight[0], Curves.Point(x: 128, y: 128), straight[1]]
        let (points, drag) = drag(curve, from: graph.location(of: curve[1]), by: [CGSize(width: 0, height: 200)])
        #expect(points == straight)
        #expect(drag.dragging == -1)
        // Once it's gone, the rest of the drag changes nothing, even back over the graph.
        var after = drag
        #expect(after.moved(straight, start: .zero, location: CGPoint(x: 100, y: 100), translation: CGSize(width: 100, height: 100)) == nil)
        // An end point dragged off stays, at the edge.
        let end = self.drag(curve, from: graph.location(of: straight[1]), by: [CGSize(width: 300, height: -300)]).points
        #expect(end == curve)
    }

    @Test func aDoubleClickRemovesAMiddlePointOnly() {
        let curve = [straight[0], Curves.Point(x: 128, y: 128), straight[1]]
        #expect(graph.removing(near: CGPoint(x: 136, y: 135), from: curve) == straight)
        #expect(graph.removing(near: graph.location(of: straight[0]), from: curve) == nil)
        #expect(graph.removing(near: CGPoint(x: 60, y: 30), from: curve) == nil)
    }

    // MARK: Tone curve split handles

    @Test func aDragMovesTheNearestSplitHandle() {
        let splits = [25.0, 50, 75]
        #expect(SplitSlider.handle(nearest: 60, splits: splits, width: 200) == 0)
        #expect(SplitSlider.handle(nearest: 95, splits: splits, width: 200) == 1)
        #expect(SplitSlider.handle(nearest: 199, splits: splits, width: 200) == 2)
        #expect(SplitSlider.split(at: 30, width: 200) == 15)
        #expect(SplitSlider.split(at: 30, width: 0) == 3000, "a line with no width yet doesn't divide by zero")
    }

    @Test func splitsDraggedPastEachOtherStayInOrder() {
        var curve = ToneCurve()
        curve.setSplit(0, to: SplitSlider.split(at: 190, width: 200))
        #expect(curve.splits == [45, 50, 75])
        curve.setSplit(2, to: SplitSlider.split(at: 400, width: 200))
        #expect(curve.splits == [45, 50, 95])
    }

    // MARK: Color wheels

    @Test func aPressOnTheWheelsPointMovesItFromThereAndAnywhereElseLandsIt() {
        let point = CGPoint(x: 100, y: 70)
        let onPoint = ColorWheel.dragStart(at: CGPoint(x: 104, y: 75), point: point)
        #expect(onPoint.point == point && onPoint.location == CGPoint(x: 104, y: 75))
        #expect(ColorWheel.dragged(from: onPoint, to: CGPoint(x: 114, y: 55), finely: false) == CGPoint(x: 110, y: 50))
        let elsewhere = ColorWheel.dragStart(at: CGPoint(x: 30, y: 40), point: point)
        #expect(elsewhere.point == CGPoint(x: 30, y: 40))
        #expect(ColorWheel.dragged(from: elsewhere, to: CGPoint(x: 30, y: 40), finely: false) == CGPoint(x: 30, y: 40))
    }

    @Test func optionMovesTheWheelsPointAQuarterAsFar() {
        let start = ColorWheel.dragStart(at: CGPoint(x: 70, y: 70), point: CGPoint(x: 70, y: 70))
        #expect(ColorWheel.dragged(from: start, to: CGPoint(x: 110, y: 50), finely: true) == CGPoint(x: 80, y: 65))
        let wheel = ColorWheel.wheel(at: ColorWheel.dragged(from: start, to: CGPoint(x: 140, y: 70), finely: true), radius: 70, keeping: .init())
        #expect(wheel == ColorGrading.Wheel(hue: 0, strength: 25))
    }

    // MARK: Sliding on a name, and scrubbing a number

    private final class Value {
        var current: Double
        var clicks = 0, starts = 0, ends = 0
        init(_ value: Double) { current = value }
    }

    /// A ScrubView `width` points wide, fed presses and drags in its window's coordinates as AppKit would.
    private func scrubber(_ value: Value, range: ClosedRange<Double>, step: Double = 1, followsWidth: Bool, width: CGFloat = 200) -> ScrubView {
        let view = ScrubView(frame: NSRect(x: 0, y: 0, width: width, height: 20))
        view.value = Binding(get: { value.current }, set: { value.current = $0 })
        view.range = range
        view.step = step
        view.followsWidth = followsWidth
        view.onClick = { value.clicks += 1 }
        view.onScrubStart = { value.starts += 1 }
        view.onScrubEnd = { value.ends += 1 }
        return view
    }

    private func event(_ type: NSEvent.EventType, _ x: Double, _ y: Double, shift: Bool = false) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: y), modifierFlags: shift ? .shift : [], timestamp: 0,
                           windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    private func drag(_ view: ScrubView, through points: [(Double, Double)], shift: Bool = false) {
        view.mouseDown(with: event(.leftMouseDown, points[0].0, points[0].1))
        for point in points.dropFirst() { view.mouseDragged(with: event(.leftMouseDragged, point.0, point.1, shift: shift)) }
        view.mouseUp(with: event(.leftMouseUp, points.last!.0, points.last!.1))
    }

    @Test func slidingAcrossANameMovesTheValueAsItsSliderWould() {
        let value = Value(0)
        let view = scrubber(value, range: -100...100, followsWidth: true)
        drag(view, through: [(50, 10), (51, 12), (100, 10)])
        // A quarter of the width is a quarter of the range.
        #expect(value.current == 50)
        #expect(value.starts == 1 && value.ends == 1 && value.clicks == 0)
        drag(view, through: [(150, 10), (0, 10)])
        #expect(value.current == -100, "stops at the end of the range")
    }

    @Test func aClickAloneChangesNothing() {
        let value = Value(20)
        let view = scrubber(value, range: -100...100, followsWidth: true)
        drag(view, through: [(50, 10), (52, 11)])
        #expect(value.current == 20)
        #expect(value.clicks == 1 && value.starts == 0 && value.ends == 0)
    }

    @Test func draggingDownRaisesANumberAndShiftIsFiveTimesAsFast() {
        let value = Value(10)
        let view = scrubber(value, range: 0...100, followsWidth: false)
        // Window coordinates grow upward: down is a smaller y. Three points a step.
        drag(view, through: [(20, 100), (20, 70)])
        #expect(value.current == 20)
        drag(view, through: [(20, 100), (20, 109)])
        #expect(value.current == 17)
        drag(view, through: [(20, 100), (20, 94)], shift: true)
        #expect(value.current == 27)
    }

    @Test func slowDragsAddUp() {
        let value = Value(0)
        let view = scrubber(value, range: 0...100, followsWidth: false)
        view.mouseDown(with: event(.leftMouseDown, 20, 100))
        view.mouseDragged(with: event(.leftMouseDragged, 20, 97))
        #expect(value.current == 1)
        // Half a step at a time.
        for step in 1...2 { view.mouseDragged(with: event(.leftMouseDragged, 20, 97 - Double(step) * 1.5)) }
        #expect(value.current == 2)
        view.mouseUp(with: event(.leftMouseUp, 20, 94))
    }

    @Test func aSliderWithBiggerStepsMovesInWholeSteps() {
        let value = Value(0)
        let view = scrubber(value, range: 0...100, step: 5, followsWidth: true)
        drag(view, through: [(0, 10), (23, 10)])
        // 23 points of 200 is 11.5 of 100: two whole steps of 5, the rest kept for the next movement.
        #expect(value.current == 10)
    }
}
