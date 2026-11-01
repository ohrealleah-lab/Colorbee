import ColorbeeCore
import CoreGraphics
import Foundation
import Observation

extension Editor {
    // MARK: Step badges (FR-5.3)

    var pendingBadgeSpec: StepBadgeSpec? {
        guard let badge = pendingBadge else { return nil }
        return StepBadgeSpec(label: StepBadge.label(for: badge.value, style: badge.style), center: badge.center, diameter: badgeDiameter,
                             fill: badge.swapped ? color2 : color1, ink: badge.swapped ? color1 : color2, arrowTip: badge.arrowTip)
    }

    /// The badge being placed, drawn into pixels for the overlay.
    func renderedPendingBadge() -> (pixels: PixelBuffer, origin: IntPoint)? {
        pendingBadgeSpec.flatMap { StepBadge.render($0, colorSpace: canvas.colorSpace, clippedTo: canvas.bounds) }
    }

    func pendingBadgeContains(_ point: Point2D) -> Bool {
        pendingBadgeSpec?.contains(point) == true
    }

    /// A press on the badge being placed moves it; anywhere else places it and starts the next one there. Dragging
    /// out from a new badge points an arrow at where the drag ends.
    func beginBadge(at point: Point2D, secondary: Bool) {
        if let badge = pendingBadge, pendingBadgeContains(point) {
            badgeDrag = .move(grab: point, original: badge)
            return
        }
        guard !refusedBecauseLocked() else { return }
        finishInteractions()
        placeFloatingSelection()
        pendingBadge = PendingBadge(style: badgeStyle, value: nextBadge, center: point, swapped: secondary)
        nextBadge += 1
        badgeDrag = .create
        onRender()
    }

    func continueBadge(to point: Point2D) {
        guard var badge = pendingBadge, let drag = badgeDrag else { return }
        switch drag {
        case .create:
            badge.arrowTip = point
        case .move(let grab, let original):
            let dx = point.x - grab.x, dy = point.y - grab.y
            badge = original
            badge.center = Point2D(x: original.center.x + dx, y: original.center.y + dy)
            badge.arrowTip = original.arrowTip.map { Point2D(x: $0.x + dx, y: $0.y + dy) }
        }
        pendingBadge = badge
        onRender()
    }

    func endBadge() {
        badgeDrag = nil
        // A click, or a drag that stayed on the circle, has no arrow.
        if pendingBadgeSpec?.showsArrow == false { pendingBadge?.arrowTip = nil }
    }

    /// Draws the badge into the active layer as one step, "Step Badge".
    func commitPendingBadge() {
        guard let badge = pendingBadge, let spec = pendingBadgeSpec else { return }
        pendingBadge = nil
        badgeDrag = nil
        guard activeLayerTakesEdits, let rendered = StepBadge.render(spec, colorSpace: canvas.colorSpace, clippedTo: canvas.bounds) else {
            nextBadges[badge.style] = badge.value
            onRender()
            return
        }
        let edit = history.beginEdit("Step Badge", on: canvas)
        Compositing.draw(rendered.pixels, at: rendered.origin, onto: canvas.paintLayer, edit: edit)
        recordingChanges { history.commit(edit) }
        if let step = history.undoStepID { badgeSteps[step] = (badge.style, badge.value) }
        onRender()
    }

    /// Removes the badge being placed (Delete, Esc or ⌘Z); its number is used again by the next one.
    func cancelPendingBadge() {
        guard let badge = pendingBadge else { return }
        pendingBadge = nil
        badgeDrag = nil
        nextBadges[badge.style] = badge.value
        onRender()
    }
}
