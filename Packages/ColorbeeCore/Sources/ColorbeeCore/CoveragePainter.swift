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
    /// Extends the stroke to `point` and returns the region repainted. `pressure` is 0...1; devices
    /// without pressure report 1. Strokes that ignore pressure (pencil, eraser) disregard it.
    @discardableResult
    func move(to point: Point2D, pressure: Double) -> IntRect

    /// Called repeatedly while the pointer holds still mid-stroke (the airbrush keeps spraying).
    @discardableResult
    func hold() -> IntRect

    /// Called once when the stroke ends (the oil brush tapers its tail).
    @discardableResult
    func finish() -> IntRect
}

extension Stroke {
    @discardableResult
    public func move(to point: Point2D) -> IntRect { move(to: point, pressure: 1) }

    @discardableResult
    public func hold() -> IntRect { .zero }

    @discardableResult
    public func finish() -> IntRect { .zero }
}

/// Paints one stroke into a layer. Each pixel keeps the strongest coverage it has received and is
/// recomputed from its pre-stroke value, so overlapping dabs never compound.
final class CoveragePainter {
    let layer: Layer
    let edit: Edit
    let effect: StrokeEffect
    /// Maps each pixel's strongest value to the coverage actually painted. Watercolor uses it to make
    /// the rim of a stroke darker than its middle, which max-coverage alone can't do.
    let transfer: [UInt8]?
    private(set) var dirtyRect: IntRect = .zero
    private var coverage: [TileKey: TileCoverage] = [:]
    /// What a retouching tool makes of a pixel (FR-4.6), from its position and its value before the stroke; the
    /// coverage mixes towards it. When set, it's used instead of `effect`.
    var transform: ((_ x: Int, _ y: Int, _ original: Pixel) -> Pixel)?

    init(layer: Layer, edit: Edit, effect: StrokeEffect, transfer: [UInt8]? = nil) {
        precondition(transfer == nil || transfer?.count == 256)
        self.layer = layer
        self.edit = edit
        self.effect = effect
        self.transfer = transfer
    }

    /// Puts `area` back to its pre-stroke pixels and forgets its coverage, so it can be painted again
    /// with different dabs (the oil brush's tapered tail).
    func clear(_ area: IntRect) {
        let area = area.intersection(layer.buffer.bounds)
        guard !area.isEmpty else { return }
        for cell in TileGrid.cells(covering: area) {
            let key = TileKey(layer: layer.id, column: cell.column, row: cell.row)
            guard let original = edit.originalTile(key), let tileCoverage = coverage[key] else { continue }
            let tile = original.rect
            let region = area.intersection(tile)
            for y in region.minY..<region.maxY {
                let row = layer.buffer.row(y)
                let rowStart = (y - tile.minY) * tile.width - tile.minX
                for x in region.minX..<region.maxX {
                    tileCoverage.values[rowStart + x] = 0
                    row[x] = original.pixels[rowStart + x]
                }
            }
        }
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
                    let covered = transfer?[Int(value)] ?? value
                    if let transform {
                        let source = original.pixels[index]
                        row[x] = Compositing.lerp(source, transform(x, y, source), Float(covered) / 255)
                    } else {
                        row[x] = apply(to: original.pixels[index], coverage: covered)
                    }
                }
            }
        }
        dirtyRect = dirtyRect.union(area)
        return area
    }

    /// A pixel as it was before the stroke, whether or not the stroke has reached it.
    func original(atX x: Int, y: Int) -> Pixel {
        let key = TileKey(layer: layer.id, column: x / TileGrid.tileSize, row: y / TileGrid.tileSize)
        if let tile = edit.originalTile(key) {
            return tile.pixels[(y - tile.rect.minY) * tile.rect.width + x - tile.rect.minX]
        }
        return layer.buffer[x, y]
    }

    /// Everything the stroke covered, at its strongest coverage, as a mask.
    func coverageMask() -> SelectionMask? {
        guard !dirtyRect.isEmpty else { return nil }
        let area = dirtyRect
        var values = [UInt8](repeating: 0, count: area.area)
        for (key, tileCoverage) in coverage {
            guard let tile = edit.originalTile(key)?.rect else { continue }
            let region = tile.intersection(area)
            guard !region.isEmpty else { continue }
            for y in region.minY..<region.maxY {
                for x in region.minX..<region.maxX {
                    values[(y - area.minY) * area.width + x - area.minX] = tileCoverage.values[(y - tile.minY) * tile.width + x - tile.minX]
                }
            }
        }
        return SelectionMask(bounds: area, values: values)
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
    @inlinable @inline(__always)
    public func matches(_ other: Pixel, tolerance: UInt8) -> Bool {
        // Fully transparent pixels are one color, whatever their hidden channels (review I, finding 3).
        if a | other.a == 0 { return true }
        // All four channels at once, without branches, since fill and the magic wand test every pixel.
        let lhs = SIMD4(b, g, r, a), rhs = SIMD4(other.b, other.g, other.r, other.a)
        let difference = pointwiseMax(lhs, rhs) &- pointwiseMin(lhs, rhs)
        return difference.max() <= tolerance
    }
}

extension Compositing {
    /// Straight interpolation between two pixels, used where a value is replaced rather than layered.
    static func lerp(_ a: Pixel, _ b: Pixel, _ t: Float) -> Pixel {
        func mix(_ x: UInt8, _ y: UInt8) -> UInt8 { UInt8((Float(x) + (Float(y) - Float(x)) * t).rounded()) }
        return Pixel(r: mix(a.r, b.r), g: mix(a.g, b.g), b: mix(a.b, b.b), a: mix(a.a, b.a))
    }
}
