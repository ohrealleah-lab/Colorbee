/// One anti-aliased round-brush stroke (also used for the marker, with a translucent color).
public final class RoundBrushStroke: Stroke {
    public let diameter: Double
    public let color: Pixel

    private let painter: CoveragePainter
    private var lastPoint: Point2D?
    private var distanceToNextDab: Double = 0

    public init(diameter: Double, color: Pixel, layer: Layer, edit: Edit) {
        self.diameter = max(1, diameter)
        self.color = color
        painter = CoveragePainter(layer: layer, edit: edit, effect: .over(color))
    }

    public var dirtyRect: IntRect { painter.dirtyRect }

    private var spacing: Double { max(0.25, diameter * 0.1) }

    @discardableResult
    public func move(to point: Point2D) -> IntRect {
        guard let last = lastPoint else {
            lastPoint = point
            distanceToNextDab = spacing
            return dab(at: point)
        }
        let dx = point.x - last.x
        let dy = point.y - last.y
        let distance = (dx * dx + dy * dy).squareRoot()
        var changed = IntRect.zero
        var travelled = distanceToNextDab
        while travelled <= distance {
            let fraction = travelled / distance
            changed = changed.union(dab(at: Point2D(x: last.x + dx * fraction, y: last.y + dy * fraction)))
            travelled += spacing
        }
        distanceToNextDab = travelled - distance
        lastPoint = point
        return changed
    }

    private func dab(at center: Point2D) -> IntRect {
        guard color.a > 0 else { return .zero }
        let radius = diameter / 2
        let area = IntRect(
            enclosingMinX: center.x - radius - 1, minY: center.y - radius - 1,
            maxX: center.x + radius + 1, maxY: center.y + radius + 1
        )
        return painter.paint(area) { x, y in
            let offsetX = Double(x) + 0.5 - center.x
            let offsetY = Double(y) + 0.5 - center.y
            let amount = min(1, radius + 0.5 - (offsetX * offsetX + offsetY * offsetY).squareRoot())
            return amount > 0 ? UInt8((amount * 255).rounded()) : 0
        }
    }
}

/// A 1-pixel hard-edged line with no anti-aliasing (FR-4.1).
public final class PencilStroke: Stroke {
    private let painter: CoveragePainter
    private var lastPixel: IntPoint?

    public init(color: Pixel, layer: Layer, edit: Edit) {
        painter = CoveragePainter(layer: layer, edit: edit, effect: .over(color))
    }

    @discardableResult
    public func move(to point: Point2D) -> IntRect {
        let pixel = IntPoint(x: Int(point.x.rounded(.down)), y: Int(point.y.rounded(.down)))
        defer { lastPixel = pixel }
        var changed = IntRect.zero
        for step in Line.pixels(from: lastPixel ?? pixel, to: pixel) {
            changed = changed.union(painter.paint(IntRect(x: step.x, y: step.y, width: 1, height: 1)) { _, _ in 255 })
        }
        return changed
    }
}

/// A square eraser (FR-4.3). The effect decides between plain erasing and the color eraser.
public final class EraserStroke: Stroke {
    public let size: Int
    private let painter: CoveragePainter
    private var lastPixel: IntPoint?

    public init(size: Int, effect: StrokeEffect, layer: Layer, edit: Edit) {
        self.size = max(1, size)
        painter = CoveragePainter(layer: layer, edit: edit, effect: effect)
    }

    /// The square of pixels the eraser covers with the pointer at `point`.
    public static func footprint(at point: Point2D, size: Int) -> IntRect {
        let size = max(1, size)
        let x = Int(point.x.rounded(.down)), y = Int(point.y.rounded(.down))
        return IntRect(x: x - size / 2, y: y - size / 2, width: size, height: size)
    }

    @discardableResult
    public func move(to point: Point2D) -> IntRect {
        let pixel = IntPoint(x: Int(point.x.rounded(.down)), y: Int(point.y.rounded(.down)))
        defer { lastPixel = pixel }
        var changed = IntRect.zero
        for center in Line.pixels(from: lastPixel ?? pixel, to: pixel) {
            let square = Self.footprint(at: Point2D(x: Double(center.x), y: Double(center.y)), size: size)
            changed = changed.union(painter.paint(square) { _, _ in 255 })
        }
        return changed
    }
}

enum Line {
    /// Every pixel on the line between two pixels, inclusive (Bresenham).
    static func pixels(from start: IntPoint, to end: IntPoint) -> [IntPoint] {
        var points: [IntPoint] = []
        var x = start.x, y = start.y
        let dx = abs(end.x - start.x), dy = -abs(end.y - start.y)
        let stepX = start.x < end.x ? 1 : -1, stepY = start.y < end.y ? 1 : -1
        var error = dx + dy
        while true {
            points.append(IntPoint(x: x, y: y))
            if x == end.x && y == end.y { return points }
            let doubled = 2 * error
            if doubled >= dy { error += dy; x += stepX }
            if doubled <= dx { error += dx; y += stepY }
        }
    }
}
