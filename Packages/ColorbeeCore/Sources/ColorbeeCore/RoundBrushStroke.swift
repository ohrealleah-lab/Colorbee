/// One anti-aliased round-brush stroke. Each pixel keeps the maximum coverage it has received
/// and is recomposited from its pre-stroke value, so overlapping dabs never darken a translucent stroke.
public final class RoundBrushStroke {
    public let diameter: Double
    public let color: Pixel
    public private(set) var dirtyRect: IntRect = .zero

    private let layer: Layer
    private let edit: Edit
    private var coverage: [TileKey: TileCoverage] = [:]
    private var lastPoint: Point2D?
    private var distanceToNextDab: Double = 0

    public init(diameter: Double, color: Pixel, layer: Layer, edit: Edit) {
        self.diameter = max(1, diameter)
        self.color = color
        self.layer = layer
        self.edit = edit
    }

    private var spacing: Double { max(0.25, diameter * 0.1) }

    /// Extends the stroke to `point`. Returns the region repainted by this call.
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
        ).intersection(layer.buffer.bounds)
        guard !area.isEmpty else { return .zero }

        edit.willModify(area, in: layer)
        for cell in TileGrid.cells(covering: area) {
            let key = TileKey(layer: layer.id, column: cell.column, row: cell.row)
            guard let original = edit.originalTile(key) else { continue }
            let tile = original.rect
            let tileCoverage = coverage[key] ?? {
                let created = TileCoverage(count: tile.area)
                coverage[key] = created
                return created
            }()
            let region = area.intersection(tile)
            for y in region.minY..<region.maxY {
                let offsetY = Double(y) + 0.5 - center.y
                let row = layer.buffer.row(y)
                let tileRowStart = (y - tile.minY) * tile.width - tile.minX
                for x in region.minX..<region.maxX {
                    let offsetX = Double(x) + 0.5 - center.x
                    let distance = (offsetX * offsetX + offsetY * offsetY).squareRoot()
                    let amount = min(1, radius + 0.5 - distance)
                    guard amount > 0 else { continue }
                    let value = UInt8((amount * 255).rounded())
                    let index = tileRowStart + x
                    guard value > tileCoverage.values[index] else { continue }
                    tileCoverage.values[index] = value
                    row[x] = Compositing.over(original.pixels[index], color, coverage: Float(value) / 255)
                }
            }
        }
        dirtyRect = dirtyRect.union(area)
        return area
    }
}

private final class TileCoverage {
    var values: [UInt8]

    init(count: Int) {
        values = [UInt8](repeating: 0, count: count)
    }
}
