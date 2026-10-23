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
        /// The pixels in the stroke, as indices in `area` (row by row), and the correction for each.
        let cells: [Int32]
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
    /// Nil when there's nothing to match. Everything is kept per stroke pixel, not per pixel of the area, so a long
    /// stroke across a big image needs memory for the stroke only (review S, finding 1).
    public static func plan(_ pixels: [Pixel]?, area: IntRect, mask: SelectionMask, reference: Reference? = nil) -> Plan? {
        guard !area.isEmpty, reference != nil || pixels?.count == area.area else { return nil }
        let pixels = pixels ?? []
        func rgb(_ p: Pixel) -> SIMD4<Float> { SIMD4(Float(p.r), Float(p.g), Float(p.b), 0) }
        let width = area.width, height = area.height
        func inside(_ x: Int, _ y: Int) -> Bool { mask.bounds.contains(IntPoint(x: x, y: y)) && mask[x, y] > 0 }
        // The stroke's pixels, found on all cores, in order.
        let bands = (height + 63) / 64
        let cells: [Int32] = ParallelRows.map(bands) { band -> [Int32] in
            var found: [Int32] = []
            for y in (band * 64)..<min(height, (band + 1) * 64) {
                for x in 0..<width where inside(area.minX + x, area.minY + y) { found.append(Int32(y * width + x)) }
            }
            return found
        }.flatMap { $0 }
        guard !cells.isEmpty else { return nil }
        var cellAt = [Int32](repeating: -1, count: width * height)
        for (cell, index) in cells.enumerated() { cellAt[Int(index)] = Int32(cell) }

        // The edge: stroke pixels beside a pixel of the area outside it. Each gets the difference there.
        var edgeCells: [Int32] = []
        var edgeSlot = [Int32](repeating: -1, count: cells.count)
        var raw: [SIMD4<Float>] = [], weights: [Float] = []
        for (cell, index) in cells.enumerated() {
            let x = Int(index) % width, y = Int(index) / width
            var sum = SIMD4<Float>.zero, count: Float = 0
            for (nx, ny) in [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
            where nx >= 0 && ny >= 0 && nx < width && ny < height && cellAt[ny * width + nx] < 0 {
                if reference == nil { sum += rgb(pixels[ny * width + nx]) }
                count += 1
            }
            guard count > 0 else { continue }
            edgeSlot[cell] = Int32(edgeCells.count)
            edgeCells.append(Int32(cell))
            if let reference {
                let pair = reference.values[Int(index)]
                raw.append(pair.map { rgb($0.before) - rgb($0.copied) } ?? .zero)
                weights.append(pair.map { Float(min($0.before.a, $0.copied.a)) / 255 } ?? 0)
            } else {
                raw.append(sum / count - rgb(pixels[Int(index)]))
                weights.append(1)
            }
        }
        guard !edgeCells.isEmpty else { return nil }
        // Smoothed along the edge, so one odd pixel there doesn't streak inward. An edge with only see-through pixels
        // around it says nothing; the blend fills it in like the inside.
        var offsets = [SIMD4<Float>](repeating: .zero, count: cells.count)
        var known = [Bool](repeating: false, count: cells.count)
        for cell in edgeCells {
            let index = Int(cells[Int(cell)]), x = index % width, y = index / width
            var sum = SIMD4<Float>.zero, total: Float = 0
            for ny in max(0, y - 3)...min(height - 1, y + 3) {
                for nx in max(0, x - 3)...min(width - 1, x + 3) {
                    let other = cellAt[ny * width + nx]
                    guard other >= 0, case let slot = Int(edgeSlot[Int(other)]), slot >= 0 else { continue }
                    sum += raw[slot] * weights[slot]
                    total += weights[slot]
                }
            }
            offsets[Int(cell)] = total > 0 ? sum / total : .zero
            known[Int(cell)] = total > 0
        }
        smoothFill(&offsets, known: known, cells: cells, cellAt: cellAt, width: width, height: height)
        return Plan(area: area, mask: mask, cells: cells, offsets: offsets)
    }

    /// One level of `smoothFill`'s pyramid: its pixels (or blocks), which hold a value fixed by the edge, and the values.
    private struct Level {
        let width: Int, height: Int
        let cells: [Int32]
        let cellAt: [Int32]
        let known: [Bool]
        var values: [SIMD4<Float>]
    }

    /// Fills in the correction inside the stroke from the edge's, as smoothly as a stretched membrane (a solution of
    /// Laplace's equation, as healing brushes use), so it fades evenly with no seams; spreading it inward ring by ring
    /// left hard lines (Leah's video, 2026-10-22). Worked out on a pyramid of ever coarser copies: solved on the
    /// smallest, then carried down a level at a time and relaxed there, on all cores, so the time grows only with the
    /// stroke's size (review S, finding 1).
    static func smoothFill(_ values: inout [SIMD4<Float>], known: [Bool], cells: [Int32], cellAt: [Int32], width: Int, height: Int) {
        var levels = [Level(width: width, height: height, cells: cells, cellAt: cellAt, known: known, values: values)]
        while let finest = levels.last, finest.cells.count > 4096, finest.width > 1 || finest.height > 1 {
            let w = (finest.width + 1) / 2, h = (finest.height + 1) / 2
            var cellAt = [Int32](repeating: -1, count: w * h)
            var cells: [Int32] = [], sums: [SIMD4<Float>] = [], counts: [Float] = []
            for (cell, index) in finest.cells.enumerated() {
                let block = (Int(index) / finest.width / 2) * w + Int(index) % finest.width / 2
                if cellAt[block] < 0 {
                    cellAt[block] = Int32(cells.count)
                    cells.append(Int32(block))
                    sums.append(.zero)
                    counts.append(0)
                }
                if finest.known[cell] {
                    sums[Int(cellAt[block])] += finest.values[cell]
                    counts[Int(cellAt[block])] += 1
                }
            }
            levels.append(Level(width: w, height: h, cells: cells, cellAt: cellAt, known: counts.map { $0 > 0 },
                                values: zip(sums, counts).map { $1 > 0 ? $0 / $1 : .zero }))
        }
        // The smallest level is solved fully, starting from the edge's average and over-relaxed so it settles in a few
        // hundred passes; each finer one starts from the level above and needs only a few passes.
        let top = levels.count - 1
        let fixed = levels[top].values.indices.filter { levels[top].known[$0] }
        let average = fixed.isEmpty ? .zero : fixed.reduce(SIMD4<Float>.zero) { $0 + levels[top].values[$1] } / Float(fixed.count)
        for cell in levels[top].values.indices where !levels[top].known[cell] { levels[top].values[cell] = average }
        relax(&levels[top], passes: max(200, 6 * max(levels[top].width, levels[top].height)), overRelaxation: 1.85)
        for depth in stride(from: levels.count - 2, through: 0, by: -1) {
            let coarse = levels[depth + 1]
            var level = levels[depth]
            for (cell, index) in level.cells.enumerated() where !level.known[cell] {
                let x = Int(index) % level.width, y = Int(index) / level.width
                // Between the four nearest blocks above that hold part of the stroke.
                let gx = (Float(x) + 0.5) / 2 - 0.5, gy = (Float(y) + 0.5) / 2 - 0.5
                let x0 = Int(gx.rounded(.down)), y0 = Int(gy.rounded(.down)), tx = gx - Float(x0), ty = gy - Float(y0)
                var sum = SIMD4<Float>.zero, total: Float = 0
                for (bx, by, weight) in [(x0, y0, (1 - tx) * (1 - ty)), (x0 + 1, y0, tx * (1 - ty)), (x0, y0 + 1, (1 - tx) * ty), (x0 + 1, y0 + 1, tx * ty)]
                where weight > 0 && bx >= 0 && by >= 0 && bx < coarse.width && by < coarse.height {
                    let block = coarse.cellAt[by * coarse.width + bx]
                    guard block >= 0 else { continue }
                    sum += coarse.values[Int(block)] * weight
                    total += weight
                }
                level.values[cell] = total > 0 ? sum / total : coarse.values[Int(coarse.cellAt[(y / 2) * coarse.width + x / 2])]
            }
            relax(&level, passes: depth == 0 ? 8 : 6)
            levels[depth] = level
        }
        values = levels[0].values
    }

    /// Red–black Gauss–Seidel: each value that isn't fixed moves to the average of its neighbors in the stroke, half the
    /// pixels at a time (like the squares of a chessboard), so each half can be done on all cores at once.
    private static func relax(_ level: inout Level, passes: Int, overRelaxation: Float = 1) {
        let width = level.width, height = level.height, cells = level.cells, cellAt = level.cellAt, known = level.known
        level.values.withUnsafeMutableBufferPointer { buffer in
            let values = UnsafeSendableValues(buffer)
            for _ in 0..<passes {
                for color in 0..<2 {
                    ParallelRows.forEach(0..<cells.count, minimumRows: 4096) { range in
                        for cell in range where !known[cell] {
                            let index = Int(cells[cell]), x = index % width, y = index / width
                            guard (x + y) & 1 == color else { continue }
                            var sum = SIMD4<Float>.zero, count: Float = 0
                            if x + 1 < width, case let n = cellAt[index + 1], n >= 0 { sum += values.base[Int(n)]; count += 1 }
                            if x > 0, case let n = cellAt[index - 1], n >= 0 { sum += values.base[Int(n)]; count += 1 }
                            if y + 1 < height, case let n = cellAt[index + width], n >= 0 { sum += values.base[Int(n)]; count += 1 }
                            if y > 0, case let n = cellAt[index - width], n >= 0 { sum += values.base[Int(n)]; count += 1 }
                            if count > 0 { values.base[cell] += (sum / count - values.base[cell]) * overRelaxation }
                        }
                    }
                }
            }
        }
    }

    /// Writes `plan`'s correction into `layer`.
    public static func apply(_ plan: Plan, to layer: Layer, edit: Edit) {
        let area = plan.area, width = area.width, mask = plan.mask
        edit.willModify(mask.bounds.intersection(layer.buffer.bounds), in: layer)
        for (cell, index) in plan.cells.enumerated() {
            let x = area.minX + Int(index) % width, y = area.minY + Int(index) / width
            let p = layer.buffer[x, y]
            // How much of the pixel's color is the copy: the stroke's coverage over how opaque the pixel ended up.
            // Mixed into an opaque pixel that's the coverage; painted onto empty space it's all of it, since the
            // coverage is already in the pixel's alpha, and weighting by it again left a haze (Leah, 2026-10-22).
            let weight = p.a == 0 ? 0 : min(1, Float(mask[x, y]) / Float(p.a))
            let shifted = SIMD4<Float>(Float(p.r), Float(p.g), Float(p.b), 0) + plan.offsets[cell] * weight
            let clamped = pointwiseMin(pointwiseMax(shifted, .zero), SIMD4(repeating: 255)).rounded(.toNearestOrEven)
            layer.buffer[x, y] = Pixel(r: UInt8(clamped.x), g: UInt8(clamped.y), b: UInt8(clamped.z), a: p.a)
        }
    }
}

/// Lets `ToneMatch.relax` share the values across cores; each pass writes only the pixels of one color, reading the
/// other's.
private struct UnsafeSendableValues: @unchecked Sendable {
    let base: UnsafeMutablePointer<SIMD4<Float>>
    init(_ buffer: UnsafeMutableBufferPointer<SIMD4<Float>>) { base = buffer.baseAddress! }
}
