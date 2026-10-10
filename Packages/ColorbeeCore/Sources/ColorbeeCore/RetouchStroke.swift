/// Which tones Lighten and Darken change most (FR-4.6).
public enum ToneRange: String, CaseIterable, Sendable {
    case shadows, midtones, highlights

    /// How much a pixel of luminance `l` (0...1) is changed.
    func weight(_ l: Float) -> Float {
        switch self {
        case .shadows: max(0, 1 - l / 0.6)
        case .midtones: max(0, 1 - abs(l - 0.5) * 2)
        case .highlights: max(0, (l - 0.4) / 0.6)
        }
    }
}

/// What a local brush does where it paints (FR-4.6).
public enum LocalAdjustment: Sendable, Equatable {
    case lighten(ToneRange)
    case darken(ToneRange)
    case saturate
    case desaturate
    case blur
    case sharpen
}

/// A soft round retouching brush: the local brushes and the Clone Stamp (FR-4.6). Each pixel moves from its value
/// before the stroke towards what the tool makes of it, by the brush's coverage there (Strength × the Hardness
/// edge). Like the brushes, going over a place again in one stroke doesn't add up; a new stroke adds more.
public final class RetouchStroke: Stroke {
    public enum Kind {
        case adjust(LocalAdjustment)
        /// Each pixel takes the one `offset` away: from `source` (all visible layers, Sample All Layers) or from the
        /// layer as it was before the stroke.
        case clone(offset: IntPoint, source: PixelBuffer?)
    }

    public let diameter: Double
    let painter: CoveragePainter
    private let hardness: Double
    private let strength: Double
    private var walker = DabWalker()

    public init(diameter: Double, hardness: Double, strength: Double, kind: Kind, layer: Layer, edit: Edit) {
        self.diameter = max(1, diameter)
        self.hardness = min(1, max(0, hardness))
        self.strength = min(1, max(0, strength))
        painter = CoveragePainter(layer: layer, edit: edit, effect: .over(.clear))
        let painter = painter
        let bounds = layer.buffer.bounds
        switch kind {
        case .adjust(let adjustment):
            // Unowned: the painter keeps this closure, so a strong reference back would keep every stroke alive.
            painter.transform = { [unowned painter] x, y, original in
                Self.adjust(original, adjustment) { dx, dy in
                    painter.original(atX: min(bounds.maxX - 1, max(0, x + dx)), y: min(bounds.maxY - 1, max(0, y + dy)))
                }
            }
        case .clone(let offset, let source):
            painter.transform = { [unowned painter] x, y, original in
                let sx = x + offset.x, sy = y + offset.y
                guard sx >= 0, sy >= 0, sx < bounds.maxX, sy < bounds.maxY else { return original }
                return source?[sx, sy] ?? painter.original(atX: sx, y: sy)
            }
        }
    }

    public var dirtyRect: IntRect { painter.dirtyRect }

    /// What the stroke covered, for the Clone Stamp's Match Tone.
    public var coverage: SelectionMask? { painter.coverageMask() }

    @discardableResult
    public func move(to point: Point2D, pressure: Double) -> IntRect {
        var changed = IntRect.zero
        for dab in walker.walk(to: point, pressure: pressure, spacing: { max(0.5, self.size($0) * 0.1) }) {
            changed = changed.union(self.dab(at: dab.center, size: size(dab.pressure)))
        }
        return changed
    }

    private func size(_ pressure: Double) -> Double {
        diameter * Brush.sizeFactor(pressure: pressure)
    }

    private func dab(at center: Point2D, size: Double) -> IntRect {
        let radius = max(0.5, size / 2)
        let area = IntRect(enclosingMinX: center.x - radius - 1, minY: center.y - radius - 1, maxX: center.x + radius + 1, maxY: center.y + radius + 1)
        return painter.paint(area) { x, y in
            let dx = Double(x) + 0.5 - center.x, dy = Double(y) + 0.5 - center.y
            let amount = Self.profile(distance: (dx * dx + dy * dy).squareRoot(), radius: radius, hardness: hardness) * strength
            return UInt8((min(1, amount) * 255).rounded())
        }
    }

    /// 1 inside the hard part of the brush, falling smoothly to 0 at its edge; at full hardness, just the
    /// anti-aliased edge.
    static func profile(distance: Double, radius: Double, hardness: Double) -> Double {
        let inner = radius * hardness
        if distance <= inner { return min(1, radius + 0.5 - distance) }
        let t = min(1, max(0, (radius - distance) / max(0.5, radius - inner)))
        return t * t * (3 - 2 * t)
    }

    /// The full effect of an adjustment on one pixel; `neighbor` reads the pixels around it as they were.
    static func adjust(_ pixel: Pixel, _ adjustment: LocalAdjustment, neighbor: (Int, Int) -> Pixel) -> Pixel {
        var value = SIMD4<Float>(Float(pixel.r), Float(pixel.g), Float(pixel.b), Float(pixel.a))
        let luminance = (0.299 * value.x + 0.587 * value.y + 0.114 * value.z) / 255
        switch adjustment {
        case .lighten(let range):
            let amount = 0.6 * range.weight(luminance)
            value = value + (SIMD4(repeating: 255) - value) * amount
        case .darken(let range):
            let amount = 0.6 * range.weight(luminance)
            value = value - value * amount
        case .saturate, .desaturate:
            let gray = SIMD4<Float>(repeating: luminance * 255)
            value = gray + (value - gray) * (adjustment == .saturate ? 1.8 : 0)
        case .blur:
            value = blurred(neighbor)
        case .sharpen:
            value = value + (value - blurred(neighbor)) * 1.5
        }
        let rgb = pointwiseMin(pointwiseMax(value, .zero), SIMD4(repeating: 255)).rounded(.toNearestOrEven)
        return Pixel(r: UInt8(rgb.x), g: UInt8(rgb.y), b: UInt8(rgb.z), a: pixel.a)
    }

    /// A 5 × 5 Gaussian of the pixels around one.
    private static func blurred(_ neighbor: (Int, Int) -> Pixel) -> SIMD4<Float> {
        let weights: [Float] = [1, 4, 6, 4, 1]
        var sum = SIMD4<Float>.zero
        for dy in -2...2 {
            for dx in -2...2 {
                let p = neighbor(dx, dy)
                sum += SIMD4(Float(p.r), Float(p.g), Float(p.b), Float(p.a)) * (weights[dx + 2] * weights[dy + 2])
            }
        }
        return sum / 256
    }
}

/// The Smudge brush (FR-4.6): a finger through wet paint. Each dab lays down the color it carries, and picks up some
/// of what's under it; with more Strength it lays down more and keeps its color longer, so colors travel further.
public final class SmudgeStroke: Stroke {
    public let diameter: Double
    private let layer: Layer
    private let edit: Edit
    private let hardness: Double
    private let strength: Float
    private var walker = DabWalker()
    /// The carried color for each pixel of the brush, square, row by row; set by the first dab.
    private var carried: [SIMD4<Float>]?
    public private(set) var dirtyRect: IntRect = .zero

    public init(diameter: Double, hardness: Double, strength: Double, layer: Layer, edit: Edit) {
        self.diameter = max(2, diameter)
        self.hardness = min(1, max(0, hardness))
        self.strength = Float(min(1, max(0, strength)))
        self.layer = layer
        self.edit = edit
    }

    @discardableResult
    public func move(to point: Point2D, pressure: Double) -> IntRect {
        var changed = IntRect.zero
        for dab in walker.walk(to: point, pressure: pressure, spacing: { _ in max(1, self.diameter * 0.08) }) {
            changed = changed.union(self.dab(at: dab.center))
        }
        return changed
    }

    private func dab(at center: Point2D) -> IntRect {
        let side = Int(diameter.rounded(.up))
        let originX = Int((center.x - Double(side) / 2).rounded()), originY = Int((center.y - Double(side) / 2).rounded())
        let area = IntRect(x: originX, y: originY, width: side, height: side).intersection(layer.buffer.bounds)
        guard !area.isEmpty else { return .zero }
        edit.willModify(area, in: layer)
        let radius = Double(side) / 2
        let first = carried == nil
        if first { carried = [SIMD4<Float>](repeating: .zero, count: side * side) }
        for y in area.minY..<area.maxY {
            let row = layer.buffer.row(y)
            for x in area.minX..<area.maxX {
                let index = (y - originY) * side + x - originX
                let p = row[x]
                let current = SIMD4<Float>(Float(p.r), Float(p.g), Float(p.b), Float(p.a))
                if first {
                    carried![index] = current
                    continue
                }
                let dx = Double(x - originX) + 0.5 - radius, dy = Double(y - originY) + 0.5 - radius
                let cover = Float(RetouchStroke.profile(distance: (dx * dx + dy * dy).squareRoot(), radius: radius, hardness: hardness))
                guard cover > 0 else { continue }
                let laid = current + (carried![index] - current) * (cover * (0.35 + 0.6 * strength))
                carried![index] += (current - carried![index]) * (cover * (1 - strength) * 0.5)
                let clamped = pointwiseMin(pointwiseMax(laid, .zero), SIMD4(repeating: 255)).rounded(.toNearestOrEven)
                row[x] = Pixel(r: UInt8(clamped.x), g: UInt8(clamped.y), b: UInt8(clamped.z), a: UInt8(clamped.w))
            }
        }
        dirtyRect = dirtyRect.union(area)
        return area
    }
}

/// Evens out the tone of an area with its surroundings (the Clone Stamp's Match Tone, FR-4.6): the differences at
/// the area's edge, smoothed along the edge, spread across the area and added in, weighted by `mask`. The texture
/// stays; the brightness and color meet the surroundings without a seam.
public enum ToneMatch {
    public static func apply(to layer: Layer, in mask: SelectionMask, edit: Edit) {
        let bounds = layer.buffer.bounds
        let area = IntRect(x: mask.bounds.minX - 1, y: mask.bounds.minY - 1, width: mask.bounds.width + 2, height: mask.bounds.height + 2).intersection(bounds)
        guard !area.isEmpty else { return }
        let width = area.width, height = area.height
        func inside(_ x: Int, _ y: Int) -> Bool { mask.bounds.contains(IntPoint(x: x, y: y)) && mask[x, y] > 0 }
        func value(_ x: Int, _ y: Int) -> SIMD4<Float> {
            let p = layer.buffer[x, y]
            return SIMD4(Float(p.r), Float(p.g), Float(p.b), 0)
        }
        var offsets = [SIMD4<Float>](repeating: .zero, count: width * height)
        var known = [Bool](repeating: false, count: width * height)
        var edge: [(Int, Int)] = []
        var cells: [(Int, Int)] = []
        for y in area.minY..<area.maxY {
            for x in area.minX..<area.maxX where inside(x, y) {
                cells.append((x, y))
                var sum = SIMD4<Float>.zero, count: Float = 0
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = x + dx, ny = y + dy
                    guard area.contains(IntPoint(x: nx, y: ny)), !inside(nx, ny) else { continue }
                    sum += value(nx, ny)
                    count += 1
                }
                if count > 0 {
                    offsets[(y - area.minY) * width + x - area.minX] = sum / count - value(x, y)
                    edge.append((x, y))
                }
            }
        }
        guard !edge.isEmpty else { return }
        let raw = offsets
        var onEdge = [Bool](repeating: false, count: width * height)
        for (x, y) in edge { onEdge[(y - area.minY) * width + x - area.minX] = true }
        for (x, y) in edge {
            var sum = SIMD4<Float>.zero, count: Float = 0
            for dy in -3...3 {
                for dx in -3...3 {
                    let nx = x + dx - area.minX, ny = y + dy - area.minY
                    guard nx >= 0, ny >= 0, nx < width, ny < height, onEdge[ny * width + nx] else { continue }
                    sum += raw[ny * width + nx]
                    count += 1
                }
            }
            offsets[(y - area.minY) * width + x - area.minX] = sum / count
            known[(y - area.minY) * width + x - area.minX] = true
        }
        var remaining = cells.filter { !known[($0.1 - area.minY) * width + $0.0 - area.minX] }
        while !remaining.isEmpty {
            var next: [(Int, Int)] = []
            var updates: [(Int, SIMD4<Float>)] = []
            for (x, y) in remaining {
                var sum = SIMD4<Float>.zero, count: Float = 0
                for dy in -1...1 {
                    for dx in -1...1 where dx != 0 || dy != 0 {
                        let nx = x + dx - area.minX, ny = y + dy - area.minY
                        guard nx >= 0, ny >= 0, nx < width, ny < height, known[ny * width + nx] else { continue }
                        sum += offsets[ny * width + nx]
                        count += 1
                    }
                }
                if count > 0 { updates.append(((y - area.minY) * width + x - area.minX, sum / count)) } else { next.append((x, y)) }
            }
            guard !updates.isEmpty else { break }
            for (index, offset) in updates {
                offsets[index] = offset
                known[index] = true
            }
            remaining = next
        }
        edit.willModify(mask.bounds.intersection(bounds), in: layer)
        for (x, y) in cells {
            let weight = Float(mask[x, y]) / 255
            let p = layer.buffer[x, y]
            let shifted = SIMD4<Float>(Float(p.r), Float(p.g), Float(p.b), 0) + offsets[(y - area.minY) * width + x - area.minX] * weight
            let clamped = pointwiseMin(pointwiseMax(shifted, .zero), SIMD4(repeating: 255)).rounded(.toNearestOrEven)
            layer.buffer[x, y] = Pixel(r: UInt8(clamped.x), g: UInt8(clamped.y), b: UInt8(clamped.z), a: p.a)
        }
    }
}
