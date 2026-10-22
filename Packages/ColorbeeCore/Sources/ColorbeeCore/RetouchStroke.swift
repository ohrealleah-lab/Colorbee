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
    /// What the Clone Stamp copies from with Sample All Layers: also what was shown before the stroke, for Match Tone.
    private var shown: PixelBuffer?
    /// Where the Clone Stamp has something to copy: where its source is on the image. Elsewhere it leaves the pixels
    /// as they were.
    private var copyable: IntRect?
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
            shown = source
            copyable = bounds.intersection(IntRect(x: bounds.minX - offset.x, y: bounds.minY - offset.y, width: bounds.width, height: bounds.height))
            painter.transform = { [unowned painter] x, y, original in
                let sx = x + offset.x, sy = y + offset.y
                guard sx >= 0, sy >= 0, sx < bounds.maxX, sy < bounds.maxY else { return original }
                return source?[sx, sy] ?? painter.original(atX: sx, y: sy)
            }
        }
    }

    public var dirtyRect: IntRect { painter.dirtyRect }

    /// What the stroke covered, for the Clone Stamp's Match Tone: only where it copied something, so Match Tone
    /// doesn't reshade pixels it left alone because its source was off the image (Leah's video, 2026-10-22).
    public var coverage: SelectionMask? {
        guard let mask = painter.coverageMask() else { return nil }
        guard let copyable else { return mask }
        guard !copyable.isEmpty, let area = SelectionMask.rectangle(copyable, clippedTo: mask.bounds) else { return nil }
        return SelectionMask.combine(mask, with: area, mode: .intersect)
    }

    /// For Match Tone: at the edge of `mask` within `area`, what was shown before the stroke and what the stroke
    /// copied there. Measuring the difference from these, not from the painted pixels, makes a soft brush blend in too:
    /// at its soft rim the painted pixels are still mostly the original (Leah's test, 2026-10-14). With Sample All
    /// Layers, what was shown is the layers below, not the empty layer painted on (review R, finding 2). Only the edge
    /// is read, a pixel at a time, so a long stroke doesn't pause the app as it ends (review R, finding 4).
    public func toneReference(over area: IntRect, mask: SelectionMask) -> ToneMatch.Reference? {
        guard let transform = painter.transform, !area.isEmpty else { return nil }
        var values: [Int: ToneMatch.EdgePair] = [:]
        for index in ToneMatch.edge(of: mask, in: area) {
            let x = area.minX + index % area.width, y = area.minY + index / area.width
            let original = painter.original(atX: x, y: y)
            values[index] = ToneMatch.EdgePair(before: shown?[x, y] ?? original, copied: transform(x, y, original))
        }
        return ToneMatch.Reference(values: values)
    }

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
            // Alpha is blurred too, so an edge against transparency softens (review O, finding 3).
            value = blurred(neighbor) ?? value
        case .sharpen:
            let soft = blurred(neighbor) ?? value
            value = value + (value - soft) * 1.5
            value.w = Float(pixel.a)
        }
        let rgba = pointwiseMin(pointwiseMax(value, .zero), SIMD4(repeating: 255)).rounded(.toNearestOrEven)
        return Pixel(r: UInt8(rgba.x), g: UInt8(rgba.y), b: UInt8(rgba.z), a: adjustment == .blur ? UInt8(rgba.w) : pixel.a)
    }

    /// A 5 × 5 Gaussian of the pixels around one, each color counted by how much of it shows, so transparent
    /// neighbors' hidden colors don't darken it. Nil when every neighbor is fully transparent.
    private static func blurred(_ neighbor: (Int, Int) -> Pixel) -> SIMD4<Float>? {
        let weights: [Float] = [1, 4, 6, 4, 1]
        var color = SIMD3<Float>.zero, alpha: Float = 0
        for dy in -2...2 {
            for dx in -2...2 {
                let p = neighbor(dx, dy)
                let w = weights[dx + 2] * weights[dy + 2] * Float(p.a)
                color += SIMD3(Float(p.r), Float(p.g), Float(p.b)) * w
                alpha += w
            }
        }
        guard alpha > 0 else { return nil }
        let straight = color / alpha
        return SIMD4(straight.x, straight.y, straight.z, alpha / 256)
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
    /// The carried paint for each pixel of the brush, square, row by row, premultiplied so see-through paint mixes
    /// without darkening (review O, finding 3); set by the first dab.
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
        let bounds = layer.buffer.bounds
        func premultiplied(_ p: Pixel) -> SIMD4<Float> {
            let a = Float(p.a)
            return SIMD4(Float(p.r) * a / 255, Float(p.g) * a / 255, Float(p.b) * a / 255, a)
        }
        if carried == nil {
            // The first dab only picks up paint. Where the brush hangs off the canvas it picks up the nearest edge
            // pixel, not nothing, so no see-through black is rubbed in from the edge (review O, finding 9).
            carried = (0..<side * side).map { index in
                let x = min(max(originX + index % side, bounds.minX), bounds.maxX - 1)
                let y = min(max(originY + index / side, bounds.minY), bounds.maxY - 1)
                return premultiplied(layer.buffer[x, y])
            }
            dirtyRect = dirtyRect.union(area)
            return area
        }
        for y in area.minY..<area.maxY {
            let row = layer.buffer.row(y)
            for x in area.minX..<area.maxX {
                let index = (y - originY) * side + x - originX
                let current = premultiplied(row[x])
                let dx = Double(x - originX) + 0.5 - radius, dy = Double(y - originY) + 0.5 - radius
                let cover = Float(RetouchStroke.profile(distance: (dx * dx + dy * dy).squareRoot(), radius: radius, hardness: hardness))
                guard cover > 0 else { continue }
                let laid = current + (carried![index] - current) * (cover * (0.35 + 0.6 * strength))
                carried![index] += (current - carried![index]) * (cover * (1 - strength) * 0.5)
                let alpha = min(255, max(0, laid.w))
                guard alpha > 0 else {
                    row[x] = Pixel(r: row[x].r, g: row[x].g, b: row[x].b, a: 0)
                    continue
                }
                let color = pointwiseMin(pointwiseMax(SIMD3(laid.x, laid.y, laid.z) * 255 / alpha, .zero), SIMD3(repeating: 255))
                    .rounded(.toNearestOrEven)
                row[x] = Pixel(r: UInt8(color.x), g: UInt8(color.y), b: UInt8(color.z), a: UInt8(alpha.rounded(.toNearestOrEven)))
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
    /// The correction for one area, worked out from a copy of the pixels around it, so it can run off the main
    /// thread (review O, finding 13).
    public struct Plan: @unchecked Sendable {
        let area: IntRect
        let mask: SelectionMask
        let cells: [(Int, Int)]
        let offsets: [SIMD4<Float>]
    }

    public struct EdgePair: Sendable {
        let before: Pixel
        let copied: Pixel
    }

    /// At the area's edge, keyed by index in the read area (row by row): what was shown before the stroke, and what
    /// the stroke copied there.
    public struct Reference: Sendable {
        let values: [Int: EdgePair]
    }

    public static func apply(to layer: Layer, in mask: SelectionMask, reference: Reference? = nil, edit: Edit) {
        let area = readArea(for: mask, in: layer.buffer.bounds)
        guard !area.isEmpty,
              let plan = plan(reference == nil ? layer.buffer.pixels(in: area) : nil, area: area, mask: mask, reference: reference)
        else { return }
        apply(plan, to: layer, edit: edit)
    }

    /// The indices in `area` (row by row) of the pixels inside `mask` with a pixel outside it beside them, found on all
    /// cores.
    static func edge(of mask: SelectionMask, in area: IntRect) -> [Int] {
        func inside(_ x: Int, _ y: Int) -> Bool { mask.bounds.contains(IntPoint(x: x, y: y)) && mask[x, y] > 0 }
        let bands = (area.height + 63) / 64
        return ParallelRows.map(bands) { band -> [Int] in
            var found: [Int] = []
            for y in (area.minY + band * 64)..<min(area.maxY, area.minY + (band + 1) * 64) {
                for x in area.minX..<area.maxX where inside(x, y) {
                    func outside(_ nx: Int, _ ny: Int) -> Bool { area.contains(IntPoint(x: nx, y: ny)) && !inside(nx, ny) }
                    if outside(x + 1, y) || outside(x - 1, y) || outside(x, y + 1) || outside(x, y - 1) {
                        found.append((y - area.minY) * area.width + x - area.minX)
                    }
                }
            }
            return found
        }.flatMap { $0 }
    }

    /// The pixels `plan` needs: the area's bounds and a pixel all round, on the canvas.
    public static func readArea(for mask: SelectionMask, in bounds: IntRect) -> IntRect {
        IntRect(x: mask.bounds.minX - 1, y: mask.bounds.minY - 1, width: mask.bounds.width + 2, height: mask.bounds.height + 2).intersection(bounds)
    }

    /// With a `reference`, the difference at the edge is what was shown before minus what was copied, counted by how
    /// opaque both are: a see-through pixel's color says nothing (review R, finding 2). Without one, it's the
    /// surroundings minus the painted pixel, from `pixels`: the layer's over `area` (from `readArea`), row by row.
    /// Nil when there's nothing to match.
    public static func plan(_ pixels: [Pixel]?, area: IntRect, mask: SelectionMask, reference: Reference? = nil) -> Plan? {
        guard !area.isEmpty, reference != nil || pixels?.count == area.area else { return nil }
        let pixels = pixels ?? []
        func rgb(_ p: Pixel) -> SIMD4<Float> { SIMD4(Float(p.r), Float(p.g), Float(p.b), 0) }
        let width = area.width, height = area.height
        func inside(_ x: Int, _ y: Int) -> Bool { mask.bounds.contains(IntPoint(x: x, y: y)) && mask[x, y] > 0 }
        func value(_ x: Int, _ y: Int) -> SIMD4<Float> {
            let p = pixels[(y - area.minY) * width + x - area.minX]
            return SIMD4(Float(p.r), Float(p.g), Float(p.b), 0)
        }
        var offsets = [SIMD4<Float>](repeating: .zero, count: width * height)
        var weights = [Float](repeating: 1, count: width * height)
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
                    if reference == nil { sum += value(nx, ny) }
                    count += 1
                }
                if count > 0 {
                    let index = (y - area.minY) * width + x - area.minX
                    if let reference {
                        let pair = reference.values[index]
                        offsets[index] = pair.map { rgb($0.before) - rgb($0.copied) } ?? .zero
                        weights[index] = pair.map { Float(min($0.before.a, $0.copied.a)) / 255 } ?? 0
                    } else {
                        offsets[index] = sum / count - value(x, y)
                    }
                    edge.append((x, y))
                }
            }
        }
        guard !edge.isEmpty else { return nil }
        let raw = offsets
        var onEdge = [Bool](repeating: false, count: width * height)
        for (x, y) in edge { onEdge[(y - area.minY) * width + x - area.minX] = true }
        for (x, y) in edge {
            var sum = SIMD4<Float>.zero, total: Float = 0
            for dy in -3...3 {
                for dx in -3...3 {
                    let nx = x + dx - area.minX, ny = y + dy - area.minY
                    guard nx >= 0, ny >= 0, nx < width, ny < height, onEdge[ny * width + nx] else { continue }
                    let weight = weights[ny * width + nx]
                    sum += raw[ny * width + nx] * weight
                    total += weight
                }
            }
            // An edge with only see-through pixels around it says nothing; the blend fills it in like the inside.
            offsets[(y - area.minY) * width + x - area.minX] = total > 0 ? sum / total : .zero
            known[(y - area.minY) * width + x - area.minX] = total > 0
        }
        offsets = smoothFill(offsets, known: known, cells: cells, area: area)
        return Plan(area: area, mask: mask, cells: cells, offsets: offsets)
    }

    /// Fills in the correction inside the area from the edge's, as smoothly as a stretched membrane (a solution of
    /// Laplace's equation, as healing brushes use), so it fades evenly with no seams. Spreading it inward ring by ring
    /// left hard lines where rings from different sides met (Leah's video, 2026-10-22). The membrane is worked out
    /// on a grid of about 40,000 blocks, then laid over the pixels and relaxed there, so a big stroke stays quick.
    static func smoothFill(_ offsets: [SIMD4<Float>], known: [Bool], cells: [(Int, Int)], area: IntRect) -> [SIMD4<Float>] {
        let width = area.width
        let scale = max(1, Int((Double(cells.count) / 40_000).squareRoot().rounded(.up)))
        let cw = (width + scale - 1) / scale, ch = (area.height + scale - 1) / scale
        var inside = [Bool](repeating: false, count: cw * ch)
        var fixed = [Bool](repeating: false, count: cw * ch)
        var sums = [SIMD4<Float>](repeating: .zero, count: cw * ch)
        var counts = [Float](repeating: 0, count: cw * ch)
        for (x, y) in cells {
            let fx = x - area.minX, fy = y - area.minY, block = (fy / scale) * cw + fx / scale
            inside[block] = true
            if known[fy * width + fx] {
                sums[block] += offsets[fy * width + fx]
                counts[block] += 1
                fixed[block] = true
            }
        }
        var grid = (0..<(cw * ch)).map { counts[$0] > 0 ? sums[$0] / counts[$0] : SIMD4<Float>.zero }
        func neighbors(_ block: Int) -> [Int] {
            let bx = block % cw, by = block / cw
            return [(bx + 1, by), (bx - 1, by), (bx, by + 1), (bx, by - 1)].compactMap { nx, ny in
                nx >= 0 && ny >= 0 && nx < cw && ny < ch && inside[ny * cw + nx] ? ny * cw + nx : nil
            }
        }
        let open = (0..<(cw * ch)).filter { inside[$0] && !fixed[$0] }
        let around = open.map(neighbors)
        // A first guess spread inward from the edge, so the relaxing below has little left to do.
        var reached = fixed
        var front = open.indices.filter { around[$0].contains { reached[$0] } }
        var pending = Set(open.indices).subtracting(front)
        while !front.isEmpty {
            for slot in front {
                let from = around[slot].filter { reached[$0] }
                grid[open[slot]] = from.reduce(.zero) { $0 + grid[$1] } / Float(from.count)
            }
            for slot in front { reached[open[slot]] = true }
            front = pending.filter { around[$0].contains { reached[$0] } }.sorted()
            pending.subtract(front)
        }
        // Over-relaxed Gauss–Seidel: each open block moves toward the average of its neighbors.
        for _ in 0..<max(60, 3 * max(cw, ch)) {
            var largest: Float = 0
            for slot in open.indices where !around[slot].isEmpty {
                let block = open[slot]
                let average = around[slot].reduce(.zero) { $0 + grid[$1] } / Float(around[slot].count)
                let change = (average - grid[block]) * 1.85
                grid[block] += change
                largest = max(largest, abs(change.x), abs(change.y), abs(change.z))
            }
            if largest < 0.02 { break }
        }
        var result = offsets
        if scale == 1 {
            for (x, y) in cells where !known[(y - area.minY) * width + x - area.minX] {
                result[(y - area.minY) * width + x - area.minX] = grid[(y - area.minY) * cw + x - area.minX]
            }
            return result
        }
        // Each pixel takes the membrane between the four nearest blocks inside the area.
        for (x, y) in cells where !known[(y - area.minY) * width + x - area.minX] {
            let gx = (Float(x - area.minX) + 0.5) / Float(scale) - 0.5, gy = (Float(y - area.minY) + 0.5) / Float(scale) - 0.5
            let x0 = Int(gx.rounded(.down)), y0 = Int(gy.rounded(.down)), tx = gx - Float(x0), ty = gy - Float(y0)
            var sum = SIMD4<Float>.zero, total: Float = 0
            for (bx, by, w) in [(x0, y0, (1 - tx) * (1 - ty)), (x0 + 1, y0, tx * (1 - ty)), (x0, y0 + 1, (1 - tx) * ty), (x0 + 1, y0 + 1, tx * ty)]
            where bx >= 0 && by >= 0 && bx < cw && by < ch && inside[by * cw + bx] && w > 0 {
                sum += grid[by * cw + bx] * w
                total += w
            }
            if total > 0 { result[(y - area.minY) * width + x - area.minX] = sum / total }
        }
        // Then relaxed at full size near the edge, where the pixels' own edge values meet the coarser membrane.
        var isCell = [Bool](repeating: false, count: width * area.height)
        for (x, y) in cells { isCell[(y - area.minY) * width + x - area.minX] = true }
        let loose = cells.map { ($0.0 - area.minX, $0.1 - area.minY) }.filter { !known[$0.1 * width + $0.0] }
        for _ in 0..<(2 * scale) {
            for (fx, fy) in loose {
                var sum = SIMD4<Float>.zero, count: Float = 0
                for (nx, ny) in [(fx + 1, fy), (fx - 1, fy), (fx, fy + 1), (fx, fy - 1)]
                where nx >= 0 && ny >= 0 && nx < width && ny < area.height {
                    let index = ny * width + nx
                    guard isCell[index] else { continue }
                    sum += result[index]
                    count += 1
                }
                if count > 0 { result[fy * width + fx] = sum / count }
            }
        }
        return result
    }

    /// Writes `plan`'s correction into `layer`.
    public static func apply(_ plan: Plan, to layer: Layer, edit: Edit) {
        let area = plan.area, width = area.width, mask = plan.mask
        edit.willModify(mask.bounds.intersection(layer.buffer.bounds), in: layer)
        for (x, y) in plan.cells {
            let p = layer.buffer[x, y]
            // How much of the pixel's color is the copy: the stroke's coverage over how opaque the pixel ended up.
            // Mixed into an opaque pixel that's the coverage; painted onto empty space it's all of it, since the
            // coverage is already in the pixel's alpha, and weighting by it again left a haze (Leah, 2026-10-22).
            let weight = p.a == 0 ? 0 : min(1, Float(mask[x, y]) / Float(p.a))
            let shifted = SIMD4<Float>(Float(p.r), Float(p.g), Float(p.b), 0) + plan.offsets[(y - area.minY) * width + x - area.minX] * weight
            let clamped = pointwiseMin(pointwiseMax(shifted, .zero), SIMD4(repeating: 255)).rounded(.toNearestOrEven)
            layer.buffer[x, y] = Pixel(r: UInt8(clamped.x), g: UInt8(clamped.y), b: UInt8(clamped.z), a: p.a)
        }
    }
}
