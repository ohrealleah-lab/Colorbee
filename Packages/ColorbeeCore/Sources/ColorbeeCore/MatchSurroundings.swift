import Dispatch

/// Match Surroundings (FR-4.6): fills an area from the picture around it, using only the picture's own pixels; no
/// AI model. It's PatchMatch image completion (Barnes et al. 2009; Wexler et al. 2007): coarse to fine, every pixel
/// in the area is rebuilt from the small pieces of the surroundings that fit best where it is.
///
/// The same image and area always give the same fill: the random search is seeded from each pixel's position, and the
/// work is split into fixed bands of rows that each read the others' results from the previous pass only.
public enum MatchSurroundings {
    /// Patches are (2 × radius + 1) pixels square.
    static let patchRadius = 3
    /// The coarsest level is shrunk until the area's longer side is about this many pixels.
    static let coarsestSide = 24
    /// Rows are split into this many bands, whatever the Mac, so the result doesn't depend on the number of cores.
    static let bands = 32

    public struct Cancelled: Error {}

    /// What's needed to fill an area: the pixels around it, copied, so the fill can run in the background while
    /// the layer changes.
    public struct Job: Sendable {
        /// The part of the canvas the fill looks at, and the area's bounding box, in canvas coordinates.
        let context: IntRect
        let area: IntRect
        let pixels: [SIMD4<Float>]
        let hole: [Bool]

        /// Whether the fill's tone is evened out to its surroundings afterwards (Spot Heal).
        let matchesTone: Bool

        /// Nil when the area is empty or there's nothing around it to fill from. `nearby` looks only just around the
        /// area (Spot Heal) instead of as far again as the area is big; `matchingTone` evens out the result's tone.
        public init?(image: PixelBuffer, area mask: SelectionMask, nearby: Bool = false, matchingTone: Bool = false) {
            let bounds = IntRect(x: 0, y: 0, width: image.width, height: image.height)
            // The area's own extent, however loose the mask's bounds: the surroundings searched are measured from it,
            // and a far-off object must not be copied in.
            let loose = mask.bounds.intersection(bounds)
            var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min
            for y in loose.minY..<max(loose.minY, loose.maxY) {
                for x in loose.minX..<loose.maxX where mask[x, y] > 0 {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
            guard minX <= maxX else { return nil }
            let area = IntRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
            // Enough surroundings to draw from: at least as much again as the area, on every side; for a spot, a ring
            // about half its size, so it's healed from what's right there.
            let margin = nearby ? max(16, max(area.width, area.height) / 2) : max(48, max(area.width, area.height))
            let context = IntRect(x: area.minX - margin, y: area.minY - margin,
                                  width: area.width + 2 * margin, height: area.height + 2 * margin).intersection(bounds)
            var pixels = [SIMD4<Float>](repeating: .zero, count: context.area)
            var hole = [Bool](repeating: false, count: context.area)
            var holeCount = 0
            for y in context.minY..<context.maxY {
                let row = image.row(y)
                for x in context.minX..<context.maxX {
                    let index = (y - context.minY) * context.width + x - context.minX
                    let pixel = row[x]
                    pixels[index] = SIMD4(Float(pixel.r), Float(pixel.g), Float(pixel.b), Float(pixel.a))
                    if area.contains(IntPoint(x: x, y: y)), mask[x, y] > 0 {
                        hole[index] = true
                        holeCount += 1
                    }
                }
            }
            guard holeCount > 0, holeCount < context.area else { return nil }
            self.context = context
            self.area = area
            self.pixels = pixels
            self.hole = hole
            matchesTone = matchingTone
        }

        /// Fills the area. `progress` gets 0...1; `isCancelled` is checked between passes.
        public func run(progress: (Double) -> Void = { _ in }, isCancelled: () -> Bool = { false }) throws -> Fill {
            var levels = [Level(width: context.width, height: context.height, pixels: pixels, hole: hole)]
            // Around a flat area, as in screenshots, it's filled with that color (blended across a soft gradient).
            // Matching patches there would carry in whatever repeats nearby, such as other lines of text.
            if levels[0].hasFlatEdge {
                levels[0].fillFromEdges()
                progress(1)
                return fill(from: levels[0])
            }
            var longest = max(area.width, area.height)
            while longest > MatchSurroundings.coarsestSide, levels.last!.width >= 32, levels.last!.height >= 32 {
                levels.append(levels.last!.halved())
                longest = (longest + 1) / 2
            }
            let totalWork = levels.enumerated().reduce(0.0) { $0 + Double($1.element.holeCount * iterations(atCoarseIndex: levels.count - 1 - $1.offset)) }
            var done = 0.0
            var field: Field?
            for index in levels.indices.reversed() {
                let coarseIndex = levels.count - 1 - index
                var level = levels[index]
                guard let sources = level.sources() else { throw Cancelled() }
                var current = field.map { level.upsampled(from: $0, sources: sources) } ?? level.firstGuess(sources: sources)
                for iteration in 0..<iterations(atCoarseIndex: coarseIndex) {
                    if isCancelled() { throw Cancelled() }
                    for pass in 0..<2 {
                        level.improve(&current, sources: sources, seed: UInt64(index) << 40 | UInt64(iteration) << 8 | UInt64(pass), forward: pass == 0)
                    }
                    level.vote(current)
                    done += Double(level.holeCount)
                    progress(min(1, done / max(1, totalWork)))
                }
                levels[index] = level
                field = current
            }
            if matchesTone { levels[0].matchTone() }
            return fill(from: levels[0])
        }

        private func fill(from finest: Level) -> Fill {
            var result = [Pixel]()
            result.reserveCapacity(area.area)
            for y in area.minY..<area.maxY {
                for x in area.minX..<area.maxX {
                    let value = finest.pixels[(y - context.minY) * context.width + x - context.minX]
                    let clamped = pointwiseMin(pointwiseMax(value.rounded(.toNearestOrEven), SIMD4(repeating: 0)), SIMD4(repeating: 255))
                    result.append(Pixel(r: UInt8(clamped.x), g: UInt8(clamped.y), b: UInt8(clamped.z), a: UInt8(clamped.w)))
                }
            }
            let inArea = (area.minY..<area.maxY).flatMap { y in
                (area.minX..<area.maxX).map { x in hole[(y - context.minY) * context.width + x - context.minX] }
            }
            return Fill(area: area, pixels: result, filled: inArea)
        }

        /// More refining at the coarse levels, where it's cheap and decides the layout.
        private func iterations(atCoarseIndex index: Int) -> Int {
            max(2, 6 - index)
        }
    }

    /// The filled pixels over the area's bounding box; only those inside the area are new.
    public struct Fill: Sendable {
        public let area: IntRect
        public let pixels: [Pixel]
        /// Which pixels of `area` were filled.
        public let filled: [Bool]

        /// Writes the filled pixels into `layer`, recording them in `edit`.
        public func apply(to layer: Layer, edit: Edit) {
            edit.willModify(area, in: layer)
            for y in area.minY..<area.maxY {
                let row = layer.buffer.row(y)
                for x in area.minX..<area.maxX {
                    let index = (y - area.minY) * area.width + x - area.minX
                    if filled[index] { row[x] = pixels[index] }
                }
            }
        }
    }

    /// For every pixel in the area, the center of the source patch it's matched to, and how far off that match is.
    struct Field {
        var source: [Int32]
        var cost: [Float]
    }

    /// One size of the picture.
    struct Level {
        let width: Int
        let height: Int
        var pixels: [SIMD4<Float>]
        let hole: [Bool]
        /// The area's pixels, row by row, and where each band of rows starts in that list.
        let holeIndices: [Int32]
        let bandStarts: [Int]

        var holeCount: Int { holeIndices.count }

        init(width: Int, height: Int, pixels: [SIMD4<Float>], hole: [Bool]) {
            self.width = width
            self.height = height
            self.pixels = pixels
            self.hole = hole
            var indices: [Int32] = []
            var starts: [Int] = []
            for band in 0..<MatchSurroundings.bands {
                starts.append(indices.count)
                let rows = (height * band / MatchSurroundings.bands)..<(height * (band + 1) / MatchSurroundings.bands)
                for y in rows {
                    for x in 0..<width where hole[y * width + x] { indices.append(Int32(y * width + x)) }
                }
            }
            starts.append(indices.count)
            holeIndices = indices
            bandStarts = starts
        }

        /// Half the size: each pixel is the average of the known pixels under it; it's in the area if any is.
        func halved() -> Level {
            let w = (width + 1) / 2, h = (height + 1) / 2
            var small = [SIMD4<Float>](repeating: .zero, count: w * h)
            var smallHole = [Bool](repeating: false, count: w * h)
            for y in 0..<h {
                for x in 0..<w {
                    var sum = SIMD4<Float>.zero, count: Float = 0, inHole = false
                    for dy in 0..<2 {
                        for dx in 0..<2 {
                            let fx = 2 * x + dx, fy = 2 * y + dy
                            guard fx < width, fy < height else { continue }
                            if hole[fy * width + fx] {
                                inHole = true
                            } else {
                                sum += pixels[fy * width + fx]
                                count += 1
                            }
                        }
                    }
                    small[y * w + x] = count > 0 ? sum / count : .zero
                    smallHole[y * w + x] = inHole
                }
            }
            return Level(width: w, height: h, pixels: small, hole: smallHole)
        }

        /// Where source patches can be centered: wholly inside the picture and outside the area. If the area leaves
        /// no such place, patches that only start outside it.
        func sources() -> [Bool]? {
            let r = MatchSurroundings.patchRadius
            // Counts of area pixels, summed, so each patch is checked at once.
            var sums = [Int32](repeating: 0, count: (width + 1) * (height + 1))
            for y in 0..<height {
                var running: Int32 = 0
                for x in 0..<width {
                    running += hole[y * width + x] ? 1 : 0
                    sums[(y + 1) * (width + 1) + x + 1] = sums[y * (width + 1) + x + 1] + running
                }
            }
            func holes(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) -> Int32 {
                sums[y1 * (width + 1) + x1] - sums[y0 * (width + 1) + x1] - sums[y1 * (width + 1) + x0] + sums[y0 * (width + 1) + x0]
            }
            var valid = [Bool](repeating: false, count: width * height)
            var any = false
            if width > 2 * r, height > 2 * r {
                for y in r..<(height - r) {
                    for x in r..<(width - r) where holes(x - r, y - r, x + r + 1, y + r + 1) == 0 {
                        valid[y * width + x] = true
                        any = true
                    }
                }
                if !any {
                    for y in r..<(height - r) {
                        for x in r..<(width - r) where !hole[y * width + x] {
                            valid[y * width + x] = true
                            any = true
                        }
                    }
                }
            }
            return any ? valid : nil
        }

        /// The known pixels touching the area are all nearly one color: within a few levels in every channel, which
        /// a photo's grain never is.
        var hasFlatEdge: Bool {
            var low = SIMD4<Float>(repeating: .infinity), high = SIMD4<Float>(repeating: -.infinity)
            var any = false
            for index in holeIndices {
                let i = Int(index), x = i % width, y = i / width
                for dy in -1...1 {
                    for dx in -1...1 {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, ny >= 0, nx < width, ny < height, !hole[ny * width + nx] else { continue }
                        low = pointwiseMin(low, pixels[ny * width + nx])
                        high = pointwiseMax(high, pixels[ny * width + nx])
                        any = true
                    }
                }
            }
            return any && (high - low).max() <= 6
        }

        /// Evens out the fill's tone with its surroundings (a healing blend): at the edge, how far each filled pixel is
        /// from the known pixels beside it; that difference is spread smoothly over the area and added in, so the
        /// copied texture stays but its brightness and color meet the surroundings without a seam.
        mutating func matchTone() {
            var offsets = [SIMD4<Float>](repeating: .zero, count: width * height)
            var known = hole.map { !$0 }
            var edge: [Int] = []
            for index in holeIndices {
                let i = Int(index), x = i % width, y = i / width
                var sum = SIMD4<Float>.zero, count: Float = 0
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, ny >= 0, nx < width, ny < height, !hole[ny * width + nx] else { continue }
                    sum += pixels[ny * width + nx]
                    count += 1
                }
                if count > 0 {
                    offsets[i] = sum / count - pixels[i]
                    edge.append(i)
                }
            }
            // The edge's differences, smoothed along the edge, so only the tone is corrected, not each pixel's grain.
            var onEdge = [Bool](repeating: false, count: width * height)
            for i in edge { onEdge[i] = true }
            let raw = offsets
            for i in edge {
                let x = i % width, y = i / width
                var sum = SIMD4<Float>.zero, count: Float = 0
                for dy in -3...3 {
                    for dx in -3...3 {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, ny >= 0, nx < width, ny < height, onEdge[ny * width + nx] else { continue }
                        sum += raw[ny * width + nx]
                        count += 1
                    }
                }
                offsets[i] = sum / count
                known[i] = true
            }
            var remaining = holeIndices.map(Int.init).filter { !known[$0] }
            while !remaining.isEmpty {
                var next: [Int] = []
                var updates: [(Int, SIMD4<Float>)] = []
                for i in remaining {
                    let x = i % width, y = i / width
                    var sum = SIMD4<Float>.zero, count: Float = 0
                    for dy in -1...1 {
                        for dx in -1...1 where dx != 0 || dy != 0 {
                            let nx = x + dx, ny = y + dy
                            guard nx >= 0, ny >= 0, nx < width, ny < height, hole[ny * width + nx], known[ny * width + nx] else { continue }
                            sum += offsets[ny * width + nx]
                            count += 1
                        }
                    }
                    if count > 0 { updates.append((i, sum / count)) } else { next.append(i) }
                }
                guard !updates.isEmpty else { break }
                for (i, value) in updates {
                    offsets[i] = value
                    known[i] = true
                }
                remaining = next
            }
            // Alpha isn't toned: a spot on an opaque photo stays opaque.
            for index in holeIndices {
                let i = Int(index)
                var offset = offsets[i]
                offset.w = 0
                pixels[i] += offset
            }
        }

        /// Fills the area from its edge inward, each pixel the average of the ones already known around it.
        mutating func fillFromEdges() {
            var known = hole.map { !$0 }
            var remaining = holeIndices
            while !remaining.isEmpty {
                var next: [Int32] = []
                var updates: [(Int, SIMD4<Float>)] = []
                for index in remaining {
                    let i = Int(index), x = i % width, y = i / width
                    var sum = SIMD4<Float>.zero, count: Float = 0
                    for dy in -1...1 {
                        for dx in -1...1 where dx != 0 || dy != 0 {
                            let nx = x + dx, ny = y + dy
                            guard nx >= 0, ny >= 0, nx < width, ny < height, known[ny * width + nx] else { continue }
                            sum += pixels[ny * width + nx]
                            count += 1
                        }
                    }
                    if count > 0 { updates.append((i, sum / count)) } else { next.append(index) }
                }
                guard !updates.isEmpty else { break }
                for (i, value) in updates {
                    pixels[i] = value
                    known[i] = true
                }
                remaining = next
            }
        }

        /// The coarsest level's start: the area filled from its edges, and each pixel matched to a random source.
        mutating func firstGuess(sources: [Bool]) -> Field {
            fillFromEdges()
            let candidates = sources.indices.filter { sources[$0] }.map(Int32.init)
            var field = Field(source: [Int32](repeating: 0, count: width * height), cost: [Float](repeating: .infinity, count: width * height))
            for index in holeIndices {
                let i = Int(index)
                let pick = candidates[Int(MatchSurroundings.random(UInt64(i), 0, 0xF1257) % UInt64(candidates.count))]
                field.source[i] = pick
                field.cost[i] = distance(target: i, source: Int(pick), limit: .infinity)
            }
            return field
        }

        /// The next finer level's start: each pixel follows its coarse pixel's match, and takes the color it points at.
        mutating func upsampled(from coarse: Field, sources: [Bool]) -> Field {
            let coarseWidth = (width + 1) / 2
            let candidates = sources.indices.filter { sources[$0] }.map(Int32.init)
            var field = Field(source: [Int32](repeating: 0, count: width * height), cost: [Float](repeating: .infinity, count: width * height))
            for index in holeIndices {
                let i = Int(index), x = i % width, y = i / width
                let c = Int(coarse.source[(y / 2) * coarseWidth + x / 2])
                let sx = (c % coarseWidth) * 2 + x % 2, sy = (c / coarseWidth) * 2 + y % 2
                var source = sx < width && sy < height ? sy * width + sx : -1
                if source < 0 || !sources[source] {
                    source = Int(candidates[Int(MatchSurroundings.random(UInt64(i), 1, 0xF1257) % UInt64(candidates.count))])
                }
                field.source[i] = Int32(source)
                pixels[i] = pixels[source]
            }
            for index in holeIndices {
                let i = Int(index)
                field.cost[i] = distance(target: i, source: Int(field.source[i]), limit: .infinity)
            }
            return field
        }

        /// How different the patch around `target` is from the patch around `source`, summed over its pixels;
        /// stops counting once it's past `limit`.
        func distance(target: Int, source: Int, limit: Float) -> Float {
            let r = MatchSurroundings.patchRadius
            let tx = target % width, ty = target / width, sx = source % width, sy = source / width
            var total: Float = 0
            return pixels.withUnsafeBufferPointer { image in
                for dy in -r...r {
                    let tyy = ty + dy
                    guard tyy >= 0, tyy < height else { continue }
                    let targetRow = tyy * width, sourceRow = (sy + dy) * width
                    for dx in -r...r {
                        let txx = tx + dx
                        guard txx >= 0, txx < width else { continue }
                        let difference = image[targetRow + txx] - image[sourceRow + sx + dx]
                        total += (difference * difference).sum()
                    }
                    if total > limit { return total }
                }
                return total
            }
        }

        /// One PatchMatch pass: each pixel tries its neighbors' matches, shifted, then random ones nearby. Bands run
        /// at once; a neighbor in another band is read as it was before the pass.
        func improve(_ field: inout Field, sources: [Bool], seed: UInt64, forward: Bool) {
            let before = field
            let step = forward ? 1 : -1
            let searchRadius = max(width, height)
            field.source.withUnsafeMutableBufferPointer { source in
                field.cost.withUnsafeMutableBufferPointer { cost in
                    let shared = SharedField(source: source, cost: cost)
                    DispatchQueue.concurrentPerform(iterations: MatchSurroundings.bands) { band in
                        let range = bandStarts[band]..<bandStarts[band + 1]
                        guard !range.isEmpty else { return }
                        let rowsStart = height * band / MatchSurroundings.bands, rowsEnd = height * (band + 1) / MatchSurroundings.bands
                        let order = forward ? Array(range) : range.reversed()
                        for position in order {
                            let i = Int(holeIndices[position]), x = i % width, y = i / width
                            var best = Int(shared.source[i]), bestCost = shared.cost[i]
                            func consider(_ candidate: Int) {
                                guard candidate >= 0, candidate < sources.count, candidate != best, sources[candidate] else { return }
                                let candidateCost = distance(target: i, source: candidate, limit: bestCost)
                                if candidateCost < bestCost {
                                    best = candidate
                                    bestCost = candidateCost
                                }
                            }
                            // Propagation from the neighbor just done (left or right), and the one in the row before.
                            for (nx, ny) in [(x - step, y), (x, y - step)] {
                                guard nx >= 0, ny >= 0, nx < width, ny < height, hole[ny * width + nx] else { continue }
                                let neighbor = ny * width + nx
                                let sameBand = ny >= rowsStart && ny < rowsEnd
                                let matched = Int(sameBand ? shared.source[neighbor] : before.source[neighbor])
                                let mx = matched % width + (x - nx), my = matched / width + (y - ny)
                                if mx >= 0, my >= 0, mx < width, my < height { consider(my * width + mx) }
                            }
                            // Random search, in ever smaller windows around the best so far.
                            var radius = searchRadius, k: UInt64 = 0
                            while radius >= 1 {
                                let bx = best % width, by = best / width
                                let value = MatchSurroundings.random(UInt64(i), seed, k)
                                let rx = bx + Int(value % UInt64(2 * radius + 1)) - radius
                                let ry = by + Int((value >> 32) % UInt64(2 * radius + 1)) - radius
                                if rx >= 0, ry >= 0, rx < width, ry < height { consider(ry * width + rx) }
                                radius /= 2
                                k += 1
                            }
                            shared.source[i] = Int32(best)
                            shared.cost[i] = bestCost
                        }
                    }
                }
            }
        }

        /// Each pixel in the area becomes the average of what every patch covering it says it should be.
        mutating func vote(_ field: Field) {
            let r = MatchSurroundings.patchRadius
            var updated = pixels
            let snapshot = pixels
            updated.withUnsafeMutableBufferPointer { output in
                let shared = SharedPixels(output: output)
                DispatchQueue.concurrentPerform(iterations: MatchSurroundings.bands) { band in
                    for position in bandStarts[band]..<bandStarts[band + 1] {
                        let q = Int(holeIndices[position]), qx = q % width, qy = q / width
                        var sum = SIMD4<Float>.zero, count: Float = 0
                        for dy in -r...r {
                            for dx in -r...r {
                                let px = qx - dx, py = qy - dy
                                guard px >= 0, py >= 0, px < width, py < height, hole[py * width + px] else { continue }
                                let s = Int(field.source[py * width + px])
                                sum += snapshot[s + dy * width + dx]
                                count += 1
                            }
                        }
                        if count > 0 { shared.output[q] = sum / count }
                    }
                }
            }
            pixels = updated
        }
    }

    /// splitmix64 of a pixel's index and the pass, so every search is repeatable whatever runs it.
    static func random(_ index: UInt64, _ seed: UInt64, _ k: UInt64) -> UInt64 {
        var z = index &* 0x9E37_79B9_7F4A_7C15 &+ seed &* 0xBF58_476D_1CE4_E5B9 &+ k &* 0x94D0_49BB_1331_11EB &+ 0x2545_F491_4F6C_DD1D
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// The field's storage, written by bands of rows at once; each band writes only its own pixels.
private struct SharedField: @unchecked Sendable {
    let source: UnsafeMutableBufferPointer<Int32>
    let cost: UnsafeMutableBufferPointer<Float>
}

private struct SharedPixels: @unchecked Sendable {
    let output: UnsafeMutableBufferPointer<SIMD4<Float>>
}
