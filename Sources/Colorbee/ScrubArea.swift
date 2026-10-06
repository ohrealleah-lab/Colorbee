import AppKit
import SwiftUI

extension View {
    /// Dragging down on this raises `value` by `step` for every few points, and dragging up lowers it, five times as
    /// fast with Shift (Leah, 2026-10-05), so a number can be set without the keyboard. Down is "more" because these
    /// fields sit at the top of the window. On a text field, pass `focus`: a click without dragging focuses the field
    /// to type in it, and a drag ends typing in it so it shows the new numbers. Other focus, such as text being typed
    /// on the canvas, is left alone (Leah's test, 2026-10-05).
    ///
    /// A field in the window's toolbar can't be focused that way (macOS hosts toolbar items apart from the window's
    /// content), so `passingClicksThrough` instead hands a click to whatever is underneath, as if this weren't there.
    func scrubs(_ value: Binding<Double>, in range: ClosedRange<Double>, step: Double = 1,
                focus: FocusState<Bool>.Binding? = nil, passingClicksThrough: Bool = false) -> some View {
        overlay(ScrubArea(value: value, range: range, step: step,
                          onClick: focus.map { focus in { focus.wrappedValue = true } },
                          onScrubStart: focus.map { focus in { focus.wrappedValue = false } },
                          passesClicksThrough: passingClicksThrough))
    }
}

private struct ScrubArea: NSViewRepresentable {
    let value: Binding<Double>
    let range: ClosedRange<Double>
    let step: Double
    let onClick: (() -> Void)?
    let onScrubStart: (() -> Void)?
    let passesClicksThrough: Bool

    func makeNSView(context: Context) -> ScrubView {
        let view = ScrubView()
        update(view)
        return view
    }

    func updateNSView(_ view: ScrubView, context: Context) {
        update(view)
    }

    private func update(_ view: ScrubView) {
        view.value = value
        view.range = range
        view.step = step
        view.onClick = onClick
        view.onScrubStart = onScrubStart
        view.passesClicksThrough = passesClicksThrough
    }
}

final class ScrubView: NSView {
    var value: Binding<Double> = .constant(0)
    var range: ClosedRange<Double> = 0...1
    var step = 1.0
    var onClick: (() -> Void)?
    var onScrubStart: (() -> Void)?
    var passesClicksThrough = false
    /// The press that started this drag or click, kept to hand on as a click.
    private var pressEvent: NSEvent?

    /// How far the mouse moves, in points, for one step.
    private static let pointsPerStep = 3.0
    /// Movement before a press counts as a drag rather than a click.
    private static let dragThreshold = 3.0

    private var pressedAt: NSPoint?
    private var lastY = 0.0
    private var isScrubbing = false
    /// Movement not yet worth a whole step, so slow drags still add up.
    private var remainder = 0.0

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeUpDown)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        pressEvent = event
        pressedAt = event.locationInWindow
        lastY = event.locationInWindow.y
        isScrubbing = false
        remainder = 0
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = pressedAt else { return }
        let point = event.locationInWindow
        if !isScrubbing {
            guard hypot(point.x - start.x, point.y - start.y) >= Self.dragThreshold else { return }
            isScrubbing = true
            onScrubStart?()
        }
        // Window coordinates grow upward, so moving down (a smaller y) makes the number bigger.
        let speed = event.modifierFlags.contains(.shift) ? 5.0 : 1.0
        remainder += (lastY - point.y) * speed / Self.pointsPerStep
        lastY = point.y
        let steps = remainder.rounded(.towardZero)
        guard steps != 0 else { return }
        remainder -= steps
        value.wrappedValue = min(max(value.wrappedValue + steps * step, range.lowerBound), range.upperBound)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            pressedAt = nil
            pressEvent = nil
        }
        guard !isScrubbing, pressedAt != nil else { return }
        if passesClicksThrough, let press = pressEvent, let window {
            // Out of the way while the click is sent again, so it lands on the field underneath. The release is queued
            // first: a text field's press waits for it.
            isHidden = true
            NSApp.postEvent(event, atStart: false)
            window.sendEvent(press)
            isHidden = false
        } else {
            onClick?()
        }
    }
}
