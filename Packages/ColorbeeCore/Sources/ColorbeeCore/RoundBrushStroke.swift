/// Reflects a stroke's pixels across the canvas's center lines, for Symmetry (FR-7.3). Pixel tools mirror
/// whole pixel areas, so even sizes land exactly (review I, finding 5).
public struct StrokeMirror: Sendable, Equatable {
    public let canvasSize: IntSize
    public let flipsX: Bool
    public let flipsY: Bool

    public init(canvasSize: IntSize, flipsX: Bool, flipsY: Bool) {
        self.canvasSize = canvasSize
        self.flipsX = flipsX
        self.flipsY = flipsY
    }

    func reflect(_ rect: IntRect) -> IntRect {
        IntRect(x: flipsX ? canvasSize.width - rect.maxX : rect.minX, y: flipsY ? canvasSize.height - rect.maxY : rect.minY,
                width: rect.width, height: rect.height)
    }
}

/// A stroke that paints through a `CoveragePainter`. Symmetry's mirrored copies share one, so where they
/// overlap the strongest coverage wins instead of the last copy painted (review I, finding 4).
protocol CoveragePainting: Stroke {
    var painter: CoveragePainter { get }
}

extension Stroke {
    func sharedPainter() -> CoveragePainter? { (self as? CoveragePainting)?.painter }
}

/// One anti-aliased round-brush stroke (also used for the marker, with a translucent color).
/// Pressure scales the size.
public final class RoundBrushStroke: CoveragePainting {
    public let diameter: Double
    public let color: Pixel

    let painter: CoveragePainter
    private var walker = DabWalker()

    public init(diameter: Double, color: Pixel, layer: Layer, edit: Edit, sharingPainterWith other: Stroke? = nil) {
        self.diameter = max(1, diameter)
        self.color = color
        painter = other?.sharedPainter() ?? CoveragePainter(layer: layer, edit: edit, effect: .over(color))
    }

    public var dirtyRect: IntRect { painter.dirtyRect }

    private func size(_ pressure: Double) -> Double {
        diameter * Brush.sizeFactor(pressure: pressure)
    }

    @discardableResult
    public func move(to point: Point2D, pressure: Double) -> IntRect {
        var changed = IntRect.zero
        for dab in walker.walk(to: point, pressure: pressure, spacing: { max(0.25, self.size($0) * 0.1) }) {
            changed = changed.union(self.dab(at: dab.center, size: size(dab.pressure)))
        }
        return changed
    }

    private func dab(at center: Point2D, size: Double) -> IntRect {
        guard color.a > 0 else { return .zero }
        let radius = max(0.5, size / 2)
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
public final class PencilStroke: CoveragePainting {
    let painter: CoveragePainter
    private let mirror: StrokeMirror?
    private var lastPixel: IntPoint?

    public init(color: Pixel, layer: Layer, edit: Edit, mirror: StrokeMirror? = nil, sharingPainterWith other: Stroke? = nil) {
        self.mirror = mirror
        painter = other?.sharedPainter() ?? CoveragePainter(layer: layer, edit: edit, effect: .over(color))
    }

    @discardableResult
    public func move(to point: Point2D, pressure: Double) -> IntRect {
        let pixel = IntPoint(x: Int(point.x.rounded(.down)), y: Int(point.y.rounded(.down)))
        defer { lastPixel = pixel }
        var changed = IntRect.zero
        for step in Line.pixels(from: lastPixel ?? pixel, to: pixel) {
            let pixel = IntRect(x: step.x, y: step.y, width: 1, height: 1)
            changed = changed.union(painter.paint(mirror?.reflect(pixel) ?? pixel) { _, _ in 255 })
        }
        return changed
    }
}

/// A square eraser (FR-4.3). The effect decides between plain erasing and the color eraser.
public final class EraserStroke: CoveragePainting {
    public let size: Int
    let painter: CoveragePainter
    private let mirror: StrokeMirror?
    private var lastPixel: IntPoint?

    public init(size: Int, effect: StrokeEffect, layer: Layer, edit: Edit, mirror: StrokeMirror? = nil, sharingPainterWith other: Stroke? = nil) {
        self.size = max(1, size)
        self.mirror = mirror
        painter = other?.sharedPainter() ?? CoveragePainter(layer: layer, edit: edit, effect: effect)
    }

    /// The square of pixels the eraser covers with the pointer at `point`.
    public static func footprint(at point: Point2D, size: Int) -> IntRect {
        let size = max(1, size)
        let x = Int(point.x.rounded(.down)), y = Int(point.y.rounded(.down))
        return IntRect(x: x - size / 2, y: y - size / 2, width: size, height: size)
    }

    @discardableResult
    public func move(to point: Point2D, pressure: Double) -> IntRect {
        let pixel = IntPoint(x: Int(point.x.rounded(.down)), y: Int(point.y.rounded(.down)))
        defer { lastPixel = pixel }
        var changed = IntRect.zero
        for center in Line.pixels(from: lastPixel ?? pixel, to: pixel) {
            let square = Self.footprint(at: Point2D(x: Double(center.x), y: Double(center.y)), size: size)
            changed = changed.union(painter.paint(mirror?.reflect(square) ?? square) { _, _ in 255 })
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
