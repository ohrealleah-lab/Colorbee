import ColorbeeCore
import CoreGraphics
import Foundation
import Observation

extension Editor {
    // MARK: Shapes

    /// What a shape's fill is painted with (Leah, 2026-10-31): under an outline, Color 2 as in Paint; on its own, Color 1,
    /// like an outline on its own, so picking a color and drawing gives a shape in that color. Right-click swaps them.
    func shapeFillColor(swapped: Bool) -> Pixel {
        let outlined = shapeOutline != nil
        return outlined != swapped ? color2 : color1
    }

    /// The pending shape with the current toolbar settings applied.
    var pendingShapeSpec: ShapeSpec? {
        guard let pendingShape else { return nil }
        let outlineColor = pendingShape.swapped ? color2 : color1
        let fillColor = shapeFillColor(swapped: pendingShape.swapped)
        return ShapeSpec(
            kind: pendingShape.kind,
            start: pendingShape.start,
            end: pendingShape.end,
            points: pendingShape.points,
            rotation: pendingShape.rotation,
            lineWidth: shapeLineWidth,
            outline: shapeOutline != nil || pendingShape.kind.isOpen ? outlineColor : nil,
            fill: shapeFill != nil ? fillColor : nil,
            outlineStyle: shapeOutline ?? .solid,
            fillStyle: shapeFill ?? .solid
        )
    }

    /// The pending shape drawn into pixels, cached until it changes.
    /// For display. A textured shape may briefly show its previous frame while the new one draws in the background.
    func renderedPendingShape() -> (pixels: PixelBuffer, origin: IntPoint)? {
        guard let spec = pendingShapeSpec else { return nil }
        if let cache = shapeRenderCache, cache.spec == spec { return (cache.pixels, cache.origin) }
        if spec.outlineStyle == .solid, spec.fillStyle == .solid {
            return renderShapeNow(spec)
        }
        renderShapeInBackground(spec)
        return shapeRenderCache.map { ($0.pixels, $0.origin) }
    }

    private func renderShapeNow(_ spec: ShapeSpec) -> (pixels: PixelBuffer, origin: IntPoint)? {
        guard let rendered = ShapeRenderer.render(spec, colorSpace: canvas.colorSpace, clippedTo: canvas.bounds) else {
            shapeRenderCache = nil
            return nil
        }
        shapeRenderCache = (spec, rendered.pixels, rendered.origin)
        return rendered
    }

    private func renderShapeInBackground(_ spec: ShapeSpec) {
        guard !shapeRenderInFlight else {
            shapeRenderWanted = spec
            return
        }
        shapeRenderInFlight = true
        let generation = shapeRenderGeneration
        let colorSpace = canvas.colorSpace, bounds = canvas.bounds
        Task { [weak self] in
            let rendered = await Task.detached(priority: .userInitiated) {
                ShapeRenderer.render(spec, colorSpace: colorSpace, clippedTo: bounds).map { RenderedShape(pixels: $0.pixels, origin: $0.origin) }
            }.value
            guard let self else { return }
            self.shapeRenderInFlight = false
            guard generation == self.shapeRenderGeneration else { return }
            self.shapeRenderCache = rendered.map { (spec, $0.pixels, $0.origin) }
            if let wanted = self.shapeRenderWanted {
                self.shapeRenderWanted = nil
                if wanted != spec { self.renderShapeInBackground(wanted) }
            }
            self.renderSoon()
        }
    }

    private func forgetShapeRender() {
        shapeRenderCache = nil
        shapeRenderWanted = nil
        shapeRenderGeneration += 1
    }

    /// The rotate handle sits a fixed on-screen distance above the box's top edge.
    private func rotateHandlePoint(for spec: ShapeSpec) -> Point2D {
        let center = spec.boxCenter
        let top = min(spec.start.y, spec.end.y)
        return spec.rotated(Point2D(x: center.x, y: top - 24 / viewport.zoom))
    }

    /// Where the pending shape's handles are, in image coordinates.
    var pendingShapeHandlePoints: [Point2D] {
        guard let spec = pendingShapeSpec else { return [] }
        if spec.kind.isLinear { return [spec.start, spec.end] }
        if spec.kind.isPointBased { return spec.points }
        return SelectionHandle.allCases.map { spec.rotated($0.point(on: spec.box)) }
    }

    /// The round rotate handle above a box shape.
    var pendingShapeRotateHandle: Point2D? {
        guard let spec = pendingShapeSpec, spec.kind.isBoxShape, pendingShape?.isBuilding == false else { return nil }
        return rotateHandlePoint(for: spec)
    }

    /// Guide lines for the pending shape: the rotate handle's stem, and a curve's control arms.
    var pendingShapeGuides: [(Point2D, Point2D)] {
        guard let spec = pendingShapeSpec else { return [] }
        if spec.kind.isBoxShape {
            return [(spec.rotated(SelectionHandle.top.point(on: spec.box)), rotateHandlePoint(for: spec))]
        }
        if spec.kind == .curve, spec.points.count == 4 {
            return [(spec.points[0], spec.points[1]), (spec.points[3], spec.points[2])]
        }
        return []
    }

    func shapeHandle(atView point: Point2D) -> ShapeHandle? {
        guard let spec = pendingShapeSpec, pendingShape?.isBuilding == false else { return nil }
        func near(_ imagePoint: Point2D) -> Bool {
            let center = viewport.viewPoint(fromImage: imagePoint)
            return abs(center.x - point.x) <= 6 && abs(center.y - point.y) <= 6
        }
        if spec.kind.isLinear {
            if near(spec.end) { return .end }
            if near(spec.start) { return .start }
            return nil
        }
        if spec.kind.isPointBased {
            return spec.points.indices.last { near(spec.points[$0]) }.map(ShapeHandle.vertex)
        }
        if near(rotateHandlePoint(for: spec)) { return .rotate }
        return SelectionHandle.allCases.first { near(spec.rotated($0.point(on: spec.box))) }.map(ShapeHandle.box)
    }

    /// Whether `point` is on the pending shape, so a drag there moves it.
    func pendingShapeContains(_ point: Point2D) -> Bool {
        guard let spec = pendingShapeSpec, pendingShape?.isBuilding == false else { return false }
        if spec.kind.isBoxShape {
            let local = spec.unrotated(point)
            return spec.box.contains(IntPoint(x: Int(local.x.rounded(.down)), y: Int(local.y.rounded(.down))))
        }
        let tolerance = spec.lineWidth / 2 + 4 / viewport.zoom
        if let path = spec.path {
            let cgPoint = CGPoint(x: point.x, y: point.y)
            if spec.kind == .polygon, path.contains(cgPoint) { return true }
            return path.copy(strokingWithWidth: tolerance * 2, lineCap: .round, lineJoin: .round, miterLimit: 10).contains(cgPoint)
        }
        let dx = spec.end.x - spec.start.x, dy = spec.end.y - spec.start.y
        let lengthSquared = max(dx * dx + dy * dy, 1e-9)
        let t = min(1, max(0, ((point.x - spec.start.x) * dx + (point.y - spec.start.y) * dy) / lengthSquared))
        let nearestX = spec.start.x + t * dx, nearestY = spec.start.y + t * dy
        return ((point.x - nearestX) * (point.x - nearestX) + (point.y - nearestY) * (point.y - nearestY)).squareRoot() <= tolerance
    }

    func beginShapeDrag(at point: Point2D, viewPoint: Point2D, secondary: Bool, clickCount: Int) {
        if pendingShape == nil, refusedBecauseLocked() { return }
        if var pending = pendingShape {
            if pending.isBuilding {
                continueBuilding(&pending, at: point, viewPoint: viewPoint, clickCount: clickCount)
                return
            }
            if let handle = shapeHandle(atView: viewPoint) {
                shapeDrag = .handle(handle, grab: point, original: pending)
                return
            }
            if pendingShapeContains(point) {
                shapeDrag = .move(grab: point, original: pending)
                return
            }
        }
        finishInteractions()
        placeFloatingSelection()
        var shape = PendingShape(kind: shapeKind, start: point, end: point, swapped: secondary)
        switch shapeKind {
        case .polygon:
            shape.points = [point, point]
            shape.isBuilding = true
            shapeDrag = .handle(.vertex(1), grab: point, original: shape)
        case .curve:
            shape.points = [point, point, point, point]
            shape.isBuilding = true
            shapeDrag = .curveLine
        default:
            shapeDrag = .draw
        }
        pendingShape = shape
        onRender()
    }

    /// Polygons: each click adds a corner; clicking the first corner or double-clicking closes it.
    /// Curves: after the line, two more drags bend it.
    private func continueBuilding(_ pending: inout PendingShape, at point: Point2D, viewPoint: Point2D, clickCount: Int) {
        if pending.kind == .polygon {
            let first = viewport.viewPoint(fromImage: pending.points[0])
            let closesOnFirst = abs(first.x - viewPoint.x) <= 8 && abs(first.y - viewPoint.y) <= 8 && pending.points.count >= 3
            if clickCount >= 2 || closesOnFirst {
                finishBuilding()
                return
            }
            pending.points.append(point)
            pendingShape = pending
            shapeDrag = .handle(.vertex(pending.points.count - 1), grab: point, original: pending)
        } else {
            let control = pending.curveStage == 1 ? 1 : 2
            pending.points[control] = point
            pendingShape = pending
            shapeDrag = .handle(.vertex(control), grab: point, original: pending)
        }
        onRender()
    }

    /// Ends point-by-point placement; the shape stays editable until placed.
    func finishBuilding() {
        guard var pending = pendingShape, pending.isBuilding else { return }
        if pending.kind == .polygon, pending.points.count > 2,
           let last = pending.points.last, let previous = pending.points.dropLast().last,
           abs(last.x - previous.x) < 0.5, abs(last.y - previous.y) < 0.5 {
            pending.points.removeLast()
        }
        pending.isBuilding = false
        pendingShape = pending
        onRender()
    }

    func continueShapeDrag(to point: Point2D, shiftDown: Bool) {
        guard var shape = pendingShape, let drag = shapeDrag else { return }
        switch drag {
        case .draw:
            shape.end = point
            if shiftDown, var spec = pendingShapeSpec {
                spec.end = point
                shape.end = spec.constrained().end
            }
        case .curveLine:
            let start = shape.points[0]
            shape.points[3] = point
            shape.points[1] = Point2D(x: start.x + (point.x - start.x) / 3, y: start.y + (point.y - start.y) / 3)
            shape.points[2] = Point2D(x: start.x + (point.x - start.x) * 2 / 3, y: start.y + (point.y - start.y) * 2 / 3)
            shape.start = start
            shape.end = point
        case .move(let grab, let original):
            shape = original
            shape.translate(by: point.x - grab.x, point.y - grab.y)
        case .handle(let handle, let grab, let original):
            let delta = Point2D(x: point.x - grab.x, y: point.y - grab.y)
            switch handle {
            case .start:
                shape.start = Point2D(x: original.start.x + delta.x, y: original.start.y + delta.y)
            case .end:
                shape.end = Point2D(x: original.end.x + delta.x, y: original.end.y + delta.y)
            case .vertex(let index):
                guard original.points.indices.contains(index) else { break }
                shape.points[index] = Point2D(x: original.points[index].x + delta.x, y: original.points[index].y + delta.y)
                if shape.kind == .curve {
                    shape.start = shape.points[0]
                    shape.end = shape.points[3]
                }
            case .rotate:
                let center = Point2D(x: (original.start.x + original.end.x) / 2, y: (original.start.y + original.end.y) / 2)
                let turned = atan2(point.y - center.y, point.x - center.x) - atan2(grab.y - center.y, grab.x - center.x)
                var rotation = original.rotation + turned
                if shiftDown {
                    let step = Double.pi / 12
                    rotation = (rotation / step).rounded() * step
                }
                shape.rotation = rotation
            case .box(let boxHandle):
                resizeBox(&shape, original: original, handle: boxHandle, delta: delta, keepProportions: shiftDown)
            }
        }
        pendingShape = shape
        onRender()
    }

    /// Resizes in the shape's own (rotated) frame, keeping the opposite side fixed on the canvas.
    private func resizeBox(_ shape: inout PendingShape, original: PendingShape, handle: SelectionHandle, delta: Point2D, keepProportions: Bool) {
        let cosine = cos(original.rotation), sine = sin(original.rotation)
        let localDelta = Point2D(x: delta.x * cosine + delta.y * sine, y: -delta.x * sine + delta.y * cosine)
        let box = IntRect(
            enclosingMinX: min(original.start.x, original.end.x), minY: min(original.start.y, original.end.y),
            maxX: max(original.start.x, original.end.x), maxY: max(original.start.y, original.end.y)
        )
        let resized = handle.resize(box, by: localDelta, keepProportions: keepProportions)
        let oldCenter = Point2D(x: Double(box.minX) + Double(box.width) / 2, y: Double(box.minY) + Double(box.height) / 2)
        let shift = Point2D(
            x: Double(resized.minX) + Double(resized.width) / 2 - oldCenter.x,
            y: Double(resized.minY) + Double(resized.height) / 2 - oldCenter.y
        )
        // The box rotates around its own center, so move that center by the rotated shift.
        let newCenter = Point2D(x: oldCenter.x + shift.x * cosine - shift.y * sine, y: oldCenter.y + shift.x * sine + shift.y * cosine)
        shape.start = Point2D(x: newCenter.x - Double(resized.width) / 2, y: newCenter.y - Double(resized.height) / 2)
        shape.end = Point2D(x: newCenter.x + Double(resized.width) / 2, y: newCenter.y + Double(resized.height) / 2)
    }

    func endShapeDrag() {
        defer { shapeDrag = nil }
        guard var shape = pendingShape else { return }
        switch shapeDrag {
        case .draw where abs(shape.end.x - shape.start.x) < 1 && abs(shape.end.y - shape.start.y) < 1:
            pendingShape = nil
            onRender()
        case .curveLine:
            shape.curveStage = 1
            pendingShape = shape
        case .handle(.vertex, _, _) where shape.isBuilding && shape.kind == .curve:
            shape.curveStage += 1
            if shape.curveStage > 2 { shape.isBuilding = false }
            pendingShape = shape
            onRender()
        default:
            break
        }
    }

    /// Draws the pending shape into the active layer as one step.
    func commitPendingShape() {
        guard let spec = pendingShapeSpec else { return }
        // Placing always uses the finished drawing, never a frame still catching up.
        let rendered = shapeRenderCache.flatMap { $0.spec == spec ? ($0.pixels, $0.origin) : nil } ?? renderShapeNow(spec)
        pendingShape = nil
        forgetShapeRender()
        if let rendered {
            let edit = history.beginEdit(spec.kind.name, on: canvas)
            Compositing.draw(rendered.pixels, at: rendered.origin, onto: canvas.paintLayer, edit: edit)
            recordingChanges { history.commit(edit) }
        }
        onRender()
    }

    func cancelPendingShape() {
        pendingShape = nil
        forgetShapeRender()
        shapeDrag = nil
        onRender()
    }
}
