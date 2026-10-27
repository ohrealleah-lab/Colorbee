import AppKit
import SwiftUI
import Testing
@testable import Colorbee

/// Dragging sideways on a slider's name line (Leah, 2026-10-27), driven with made-up mouse events.
@MainActor
struct SlideAreaTests {
    /// A name line 200 points wide for a slider from -100 to 100, so each point is one step.
    @MainActor
    private final class Line {
        var value = 0.0
        var ends = 0
        let view = ScrubView(frame: NSRect(x: 0, y: 0, width: 200, height: 20))

        init() {
            view.value = Binding(get: { self.value }, set: { self.value = $0 })
            view.range = -100...100
            view.followsWidth = true
            view.onScrubEnd = { self.ends += 1 }
        }

        func press(_ x: Double) { view.mouseDown(with: event(.leftMouseDown, x)) }
        func drag(_ x: Double) { view.mouseDragged(with: event(.leftMouseDragged, x)) }
        func release(_ x: Double) { view.mouseUp(with: event(.leftMouseUp, x)) }

        private func event(_ type: NSEvent.EventType, _ x: Double) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: 10), modifierFlags: [], timestamp: 0, windowNumber: 0,
                               context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
    }

    @Test func draggingRightMovesTheValueAsFarAsTheKnobWould() {
        let line = Line()
        line.press(20)
        line.drag(40)
        line.drag(70)
        line.release(70)
        #expect(line.value == 50)
        #expect(line.ends == 1)
    }

    @Test func draggingLeftLowersItAndStopsAtTheEnd() {
        let line = Line()
        line.value = -90
        line.press(150)
        line.drag(100)
        line.release(100)
        #expect(line.value == -100)
    }

    @Test func aClickAloneChangesNothing() {
        let line = Line()
        line.value = 12
        line.press(50)
        line.drag(51)
        line.release(51)
        #expect(line.value == 12)
        #expect(line.ends == 0)
    }

    @Test func aWiderRangeMovesFasterAcrossTheSameWidth() {
        let line = Line()
        line.view.range = 0...400
        line.press(0)
        line.drag(25)
        line.release(25)
        #expect(line.value == 50)
    }
}
