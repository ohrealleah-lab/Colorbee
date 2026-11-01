import ColorbeeCore
import CoreGraphics
import Foundation
import Observation

extension Editor {
    // MARK: Painting

    func beginStroke(at point: Point2D, secondary: Bool, pressure: Double = 1) {
        guard !refusedBecauseLocked() else { return }
        finishInteractions()
        placeFloatingSelection()
        let layer = canvas.paintLayer
        let color = secondary ? color2 : color1
        let name: String
        // Each copy gets whether it's mirrored across one axis only (which turns a `/` nib into `\`), how its
        // pixels are reflected, and the first copy, whose painting it shares so overlaps don't fight
        // (review I, findings 4 and 5).
        let makeStroke: (Edit, Bool, StrokeMirror?, Stroke?) -> Stroke
        switch tool {
        case .pencil:
            name = "Pencil"
            makeStroke = { edit, _, mirror, first in PencilStroke(color: color, layer: layer, edit: edit, mirror: mirror, sharingPainterWith: first) }
        case .brush:
            name = brush == .round ? "Brush Stroke" : brush.name
            makeStroke = { [brush, brushDiameter] edit, mirrored, _, first in
                (mirrored ? brush.mirrored : brush).makeStroke(diameter: brushDiameter, color: color, layer: layer, edit: edit, sharingPainterWith: first)
            }
        case .eraser:
            // Right-drag is the Color Eraser: only Color 1 pixels (within the tolerance) become Color 2.
            let tolerance = UInt8((min(max(colorEraserTolerance, 0), 1) * 255).rounded())
            let colorErasing = secondary || colorEraserMode
            let effect: StrokeEffect = colorErasing
                ? .replaceMatching(target: color1, tolerance: tolerance, with: color2)
                : .replace(canvas.erasedFill(for: layer, color2: color2))
            name = colorErasing ? "Color Erase" : "Erase"
            makeStroke = { [eraserSize] edit, _, mirror, first in
                EraserStroke(size: eraserSize, effect: effect, layer: layer, edit: edit, mirror: mirror, sharingPainterWith: first)
            }
        default:
            return
        }
        let edit = history.beginEdit(name, on: canvas)
        let copies: [(mirroredOnce: Bool, flipsX: Bool, flipsY: Bool)] = switch symmetry {
        case .off: [(false, false, false)]
        case .vertical: [(false, false, false), (true, true, false)]
        case .horizontal: [(false, false, false), (true, false, true)]
        case .both: [(false, false, false), (true, true, false), (true, false, true), (false, true, true)]
        }
        // Pixel tools reflect their pixels, so they're all fed the same point; brushes are fed mirrored points.
        let size = canvas.size
        var strokes: [Stroke] = []
        for copy in copies {
            let mirror = pixelToolMirrors && (copy.flipsX || copy.flipsY) ? StrokeMirror(canvasSize: size, flipsX: copy.flipsX, flipsY: copy.flipsY) : nil
            strokes.append(makeStroke(edit, copy.mirroredOnce, mirror, strokes.first))
        }
        // Pixel art wants exact pixels: the Pencil is never smoothed (Q31.1).
        activeStroke = ActiveStroke(edit: edit, strokes: strokes, path: StrokePath(start: point, reach: tool == .pencil ? 0 : smoothingReach),
                                    pressureRange: pressure...pressure, pressure: pressure)
        moveStrokes(strokes, to: point, pressure: pressure)
    }

    /// How a point is reflected for each active mirror; the first is always the point itself.
    private var mirrors: [(Point2D) -> Point2D] {
        let width = Double(canvas.size.width), height = Double(canvas.size.height)
        let flipX: (Point2D) -> Point2D = { Point2D(x: width - $0.x, y: $0.y) }
        let flipY: (Point2D) -> Point2D = { Point2D(x: $0.x, y: height - $0.y) }
        switch symmetry {
        case .off: return [{ $0 }]
        case .vertical: return [{ $0 }, flipX]
        case .horizontal: return [{ $0 }, flipY]
        case .both: return [{ $0 }, flipX, flipY, { flipY(flipX($0)) }]
        }
    }

    /// The Pencil and Eraser mirror whole pixel squares themselves (`StrokeMirror`).
    private var pixelToolMirrors: Bool { tool == .pencil || tool == .eraser }

    private func moveStrokes(_ strokes: [Stroke], to point: Point2D, pressure: Double) {
        var changed = false
        let same: (Point2D) -> Point2D = { $0 }
        let mirrors = pixelToolMirrors ? Array(repeating: same, count: strokes.count) : self.mirrors
        for (stroke, mirror) in zip(strokes, mirrors) where !stroke.move(to: mirror(point), pressure: pressure).isEmpty {
            changed = true
        }
        if changed { onRender() }
    }

    /// Whether the stroke under way should keep being fed `holdStroke()` while the pointer is still (the airbrush).
    var strokeSpraysWhileHeld: Bool {
        activeStroke != nil && tool == .brush && brush == .airbrush
    }

    func holdStroke() {
        guard let strokes = activeStroke?.strokes else { return }
        var changed = false
        for stroke in strokes where !stroke.hold().isEmpty { changed = true }
        if changed { onRender() }
    }

    /// With `constrain`, the pencil, brush or eraser stays on one horizontal or vertical line from where it started
    /// (`AxisLock`), for highlighting a line of text (Leah, 2026-10-10). Otherwise Smoothing steadies it (`StrokePath`).
    func continueStroke(to point: Point2D, constrain: Bool, pressure: Double = 1) {
        guard var active = activeStroke else { return }
        let target = active.path.next(point, constrain: constrain)
        active.pressureRange = min(active.pressureRange.lowerBound, pressure)...max(active.pressureRange.upperBound, pressure)
        active.pressure = pressure
        activeStroke = active
        moveStrokes(active.strokes, to: target, pressure: pressure)
    }

    /// The size of the eraser stroke under way. Size changes apply from the next stroke, so the outline shows this one.
    var strokeEraserSize: Int? {
        (activeStroke?.strokes.first as? EraserStroke)?.size
    }

    func endStroke() {
        guard let active = activeStroke else { return }
        // A smoothed line ends where you let go (Q31.3).
        if let point = active.path.catchUp { moveStrokes(active.strokes, to: point, pressure: active.pressure) }
        activeStroke = nil
        if active.strokes.contains(where: { !$0.finish().isEmpty }) { onRender() }
        if tool == .brush {
            let range = active.pressureRange
            Diagnostics.logger.notice("Brush pressure \(range.lowerBound, format: .fixed(precision: 2))–\(range.upperBound, format: .fixed(precision: 2))")
        }
        recordingChanges { history.commit(active.edit) }
    }

    func fill(at point: Point2D, secondary: Bool) {
        guard !refusedBecauseLocked() else { return }
        finishInteractions()
        placeFloatingKeepingOutline()
        let seed = IntPoint(x: Int(point.x.rounded(.down)), y: Int(point.y.rounded(.down)))
        let edit = history.beginEdit("Fill", on: canvas)
        FloodFill.fill(
            layer: canvas.paintLayer,
            at: seed,
            with: secondary ? color2 : color1,
            tolerance: fillTolerance,
            selection: canvas.selection.marquee,
            edit: edit,
            sampling: fillSamplesAllLayers ? canvas.flattened() : nil
        )
        recordingChanges { history.commit(edit) }
        onRender()
    }

    /// The square `size` pixels across centered on `pixel`.
    private func sample(around pixel: IntPoint, size: Int) -> IntRect {
        IntRect(x: pixel.x - size / 2, y: pixel.y - size / 2, width: size, height: size)
    }

    /// Picks a color, averaging the Eyedropper's Sample Size. With `allLayers`, samples what's visible rather than
    /// only the active layer.
    func pickColor(at point: Point2D, secondary: Bool, allLayers: Bool) {
        let pixel = IntPoint(x: Int(point.x.rounded(.down)), y: Int(point.y.rounded(.down)))
        guard canvas.bounds.contains(pixel) else { return }
        let area = sample(around: pixel, size: eyedropperSampleSize)
        let picked: Pixel
        if allLayers {
            // As shown: blend modes and adjustment layers included (review I, finding 8).
            picked = canvas.colorAsShown(in: area) ?? .clear
        } else {
            picked = canvas.paintLayer.buffer.averagedPixel(in: area)
        }
        if secondary { color2 = picked } else { color1 = picked }
    }

    /// `pointerColor` as the status bar writes it, "#RRGGBB", for Edit ▸ Copy Color as Hex.
    var pointerColorHex: String? {
        pointerColor.map(Self.hex)
    }

    /// A click while the status bar's eyedropper is on: the hex of the color there, as the readout shows it, or nil
    /// off the picture (a beep, and it stays on). The caller puts it on the clipboard.
    func pickHexToCopy(at point: Point2D) -> String? {
        let pixel = IntPoint(x: Int(point.x.rounded(.down)), y: Int(point.y.rounded(.down)))
        guard let hex = readoutColor(at: pixel).map(Self.hex) else {
            onRefused()
            return nil
        }
        picksHexToCopy = false
        showNotice("Copied \(hex)")
        return hex
    }

    /// The color under the pointer as shown, every layer included, in sRGB (FR-9.7 item 9, Q20.1 and Q20.2), for the
    /// status bar; averaged over the Sample Size while the Eyedropper is chosen (Q20.4). Nil off the picture.
    var pointerColor: Pixel? {
        _ = layersRevision
        // Mid-drag the readout keeps its last color, rather than working out a patch of every layer on each mouse move
        // while a stroke draws (review W, finding 4).
        guard !isPointerDragging else { return lastPointerColor }
        lastPointerColor = pointer.flatMap(readoutColor(at:))
        return lastPointerColor
    }

    /// What the readout shows for `pixel`: the color as shown, in sRGB, averaged over the Sample Size while the
    /// Eyedropper is chosen. Nil off the picture.
    private func readoutColor(at pixel: IntPoint) -> Pixel? {
        let size = tool == .eyedropper ? eyedropperSampleSize : 1
        guard let shown = canvas.colorAsShown(in: sample(around: pixel, size: size)) else { return nil }
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        return (try? ImageCodec.converted(PixelBuffer(width: 1, height: 1, fill: shown), from: canvas.colorSpace, to: srgb))?[0, 0] ?? shown
    }

    static func hex(_ color: Pixel) -> String {
        String(format: "#%02X%02X%02X", color.r, color.g, color.b)
    }

    // MARK: Gradient

    func beginGradient(at point: Point2D, secondary: Bool) {
        guard !refusedBecauseLocked() else { return }
        finishInteractions()
        placeFloatingKeepingOutline()
        gradientDrag = GradientDrag(
            edit: history.beginEdit("Gradient", on: canvas),
            start: point,
            end: point,
            reversed: secondary,
            selection: canvas.selection.marquee
        )
    }

    func continueGradient(to point: Point2D) {
        gradientDrag?.end = point
        guard !gradientRenderScheduled else { return }
        gradientRenderScheduled = true
        Task { @MainActor [weak self] in self?.renderGradient() }
    }

    private func renderGradient() {
        gradientRenderScheduled = false
        guard let drag = gradientDrag else { return }
        drag.edit.restoreOriginals()
        Gradients.draw(
            gradientMode,
            from: drag.start,
            to: drag.end,
            startColor: drag.reversed ? color2 : color1,
            endColor: drag.reversed ? color1 : color2,
            onto: canvas.paintLayer,
            selection: drag.selection,
            edit: drag.edit
        )
        onRender()
    }

    func endGradient() {
        guard let drag = gradientDrag else { return }
        if gradientRenderScheduled { renderGradient() }
        gradientDrag = nil
        recordingChanges { history.commit(drag.edit) }
    }

    // MARK: Measure

    func measure(from start: Point2D, to end: Point2D) {
        func pixel(_ point: Point2D) -> IntPoint { IntPoint(x: Int(point.x.rounded(.down)), y: Int(point.y.rounded(.down))) }
        measurement = Measurement(start: pixel(start), end: pixel(end))
        onRender()
    }
}
