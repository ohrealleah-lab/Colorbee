/// What a stroke does to the pixels it covers.
public enum StrokeEffect: Sendable {
    /// Composites the color over the original (brushes, pencil).
    case over(Pixel)
    /// Replaces covered pixels with the color (eraser).
    case replace(Pixel)
    /// Replaces only pixels whose original color matches `target` within `tolerance` (color eraser).
    case replaceMatching(target: Pixel, tolerance: UInt8, with: Pixel)
}

/// A stroke that grows as the pointer moves.
public protocol Stroke: AnyObject {
    /// Extends the stroke to `point` and returns the region repainted.
    @discardableResult
    func move(to point: Point2D) -> IntRect
}

/// Paints one stroke into a layer. Each pixel keeps the strongest coverage it has received and is
/// recomputed from its pre-stroke value, so overlapping dabs never compound.
final class CoveragePainter {
    let layer: Layer
    let edit: Edit
    let effect: StrokeEffect
    private(set) var dirtyRect: IntRect = .zero
    private var coverage: [TileKey: TileCoverage] = [:]

    init(layer: Layer, edit: Edit, effect: StrokeEffect) {
        self.layer = layer
        self.edit = edit
        self.effect = effect
    }

    /// Paints `area` with per-pixel coverage (0...255) from `amount`. Returns the clipped area.
    @discardableResult
    func paint(_ area: IntRect, amount: (_ x: Int, _ y: Int) -> UInt8) -> IntRect {
        let area = area.intersection(layer.buffer.bounds)
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
                let row = layer.buffer.row(y)
                let rowStart = (y - tile.minY) * tile.width - tile.minX
                for x in region.minX..<region.maxX {
                    let value = amount(x, y)
                    let index = rowStart + x
                    guard value > tileCoverage.values[index] else { continue }
                    tileCoverage.values[index] = value
                    row[x] = apply(to: original.pixels[index], coverage: value)
                }
            }
        }
        dirtyRect = dirtyRect.union(area)
        return area
    }

    private func apply(to original: Pixel, coverage: UInt8) -> Pixel {
        switch effect {
        case .over(let color):
            return Compositing.over(original, color, coverage: Float(coverage) / 255)
        case .replace(let color):
            return coverage == 255 ? color : Compositing.lerp(original, color, Float(coverage) / 255)
        case .replaceMatching(let target, let tolerance, let replacement):
            return original.matches(target, tolerance: tolerance) ? replacement : original
        }
    }
}

private final class TileCoverage {
    var values: [UInt8]

    init(count: Int) {
        values = [UInt8](repeating: 0, count: count)
    }
}

extension Pixel {
    /// Whether every channel, including alpha, is within `tolerance` of `other`.
    public func matches(_ other: Pixel, tolerance: UInt8) -> Bool {
        func close(_ a: UInt8, _ b: UInt8) -> Bool { (a > b ? a - b : b - a) <= tolerance }
        return close(r, other.r) && close(g, other.g) && close(b, other.b) && close(a, other.a)
    }
}

extension Compositing {
    /// Straight interpolation between two pixels, used where a value is replaced rather than layered.
    static func lerp(_ a: Pixel, _ b: Pixel, _ t: Float) -> Pixel {
        func mix(_ x: UInt8, _ y: UInt8) -> UInt8 { UInt8((Float(x) + (Float(y) - Float(x)) * t).rounded()) }
        return Pixel(r: mix(a.r, b.r), g: mix(a.g, b.g), b: mix(a.b, b.b), a: mix(a.a, b.a))
    }
}
