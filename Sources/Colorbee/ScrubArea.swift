import AppKit
import SwiftUI

extension View {
    /// Dragging down on this raises `value` by `step` for every few points, and dragging up lowers it, five times as
    /// fast with Shift (Leah, 2026-10-05), so a number can be set without the keyboard. Down is "more" because these
    /// fields sit at the top of the window. A click without dragging still reaches a
    /// text field underneath, to type in it.
    func scrubs(_ value: Binding<Double>, in range: ClosedRange<Double>, step: Double = 1) -> some View {
        overlay(ScrubArea(value: value, range: range, step: step))
    }
}

private struct ScrubArea: NSViewRepresentable {
    let value: Binding<Double>
    let range: ClosedRange<Double>
    let step: Double

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
    }
}

final class ScrubView: NSView {
    var value: Binding<Double> = .constant(0)
    var range: ClosedRange<Double> = 0...1
    var step = 1.0

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
            // A field being typed in shows the new numbers as they change.
            window?.makeFirstResponder(nil)
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
        defer { pressedAt = nil }
        guard !isScrubbing, let point = pressedAt else { return }
        // A click: hand it to a text field underneath, ready to type.
        isHidden = true
        let below = window?.contentView?.hitTest(window?.contentView?.convert(point, from: nil) ?? point)
        isHidden = false
        var view = below
        while let candidate = view, !(candidate is NSTextField) { view = candidate.superview }
        if let field = view as? NSTextField, field.isEditable { window?.makeFirstResponder(field) }
    }
}
