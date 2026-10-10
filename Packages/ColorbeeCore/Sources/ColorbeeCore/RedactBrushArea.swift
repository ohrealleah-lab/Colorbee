/// The area a Redact Brush stroke covers (FR-9.6): every pixel whose center is within the brush's radius of the
/// path, hard-edged, so nothing under the stroke is left half-hidden. It also keeps a see-through picture of the
/// area for the screen while painting. The pixels are only changed when the stroke ends, through Batch Redact.
public final class RedactBrushArea {
    public let diameter: Double
    private let canvasBounds: IntRect
    private let overlayColor: Pixel
    private var last: Point2D?
    /// The see-through picture, over `region`, which grows as the stroke does.
    private var overlay: PixelBuffer?
    private var region: IntRect = .zero
    /// What the stroke has covered so far.
    public private(set) var covered: IntRect = .zero

    /// How much room the picture gains each time the stroke outgrows it, so it isn't remade on every move.
    private static let growth = 128

    public init(diameter: Double, canvasBounds: IntRect, overlayColor: Pixel) {
        self.diameter = max(1, diameter)
        self.canvasBounds = canvasBounds
        self.overlayColor = overlayColor
    }

    /// Extends the stroke to `point`: the first call covers a dot, each later one the band from the last point.
    @discardableResult
    public func move(to point: Point2D) -> IntRect {
        let start = last ?? point
        last = point
        let radius = diameter / 2
        let box = IntRect(enclosingMinX: min(start.x, point.x) - radius, minY: min(start.y, point.y) - radius,
                          maxX: max(start.x, point.x) + radius, maxY: max(start.y, point.y) + radius).intersection(canvasBounds)
        guard !box.isEmpty else { return .zero }
        grow(toInclude: box)
        guard let overlay else { return .zero }
        let dx = point.x - start.x, dy = point.y - start.y
        let lengthSquared = dx * dx + dy * dy
        let radiusSquared = radius * radius
        for y in box.minY..<box.maxY {
            let row = overlay.row(y - region.minY)
            let cy = Double(y) + 0.5
            for x in box.minX..<box.maxX {
                let cx = Double(x) + 0.5
                // Distance from the pixel's center to the segment from start to point.
                let t = lengthSquared > 0 ? min(1, max(0, ((cx - start.x) * dx + (cy - start.y) * dy) / lengthSquared)) : 0
                let nx = start.x + t * dx - cx, ny = start.y + t * dy - cy
                if nx * nx + ny * ny <= radiusSquared { row[x - region.minX] = overlayColor }
            }
        }
        covered = covered.isEmpty ? box : covered.union(box)
        return box
    }

    /// The covered area as a selection, for Batch Redact; nil if the stroke covered nothing.
    public var mask: SelectionMask? {
        guard let overlay, !covered.isEmpty else { return nil }
        var values = [UInt8](repeating: 0, count: covered.area)
        for y in covered.minY..<covered.maxY {
            let row = overlay.row(y - region.minY)
            for x in covered.minX..<covered.maxX where row[x - region.minX].a > 0 {
                values[(y - covered.minY) * covered.width + x - covered.minX] = 255
            }
        }
        return SelectionMask(bounds: covered, values: values)
    }

    /// The see-through picture of the area, for the screen.
    public var picture: (pixels: PixelBuffer, origin: IntPoint)? {
        overlay.map { ($0, IntPoint(x: region.minX, y: region.minY)) }
    }

    private func grow(toInclude box: IntRect) {
        if overlay != nil, region.contains(box) { return }
        let wanted = (region.isEmpty ? box : region.union(box))
        let grown = IntRect(x: wanted.minX - Self.growth, y: wanted.minY - Self.growth,
                            width: wanted.width + 2 * Self.growth, height: wanted.height + 2 * Self.growth).intersection(canvasBounds)
        let buffer = PixelBuffer(width: grown.width, height: grown.height)
        if let overlay {
            for y in region.minY..<region.maxY {
                (buffer.row(y - grown.minY) + (region.minX - grown.minX)).update(from: overlay.row(y - region.minY), count: region.width)
            }
        }
        overlay = buffer
        region = grown
    }
}
