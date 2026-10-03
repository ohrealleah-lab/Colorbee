public enum FloodFill {
    /// Fills the area connected to `seed` whose colors are within `tolerance` (0...1) of the seed's color.
    /// The fill never crosses the canvas edges, and stays inside `selection` when given. Returns the filled area.
    @discardableResult
    public static func fill(
        layer: Layer,
        at seed: IntPoint,
        with color: Pixel,
        tolerance: Double,
        selection: SelectionMask?,
        edit: Edit
    ) -> IntRect {
        let region = connectedRegion(in: layer.buffer, from: seed, tolerance: tolerance, selection: selection)
        guard !region.bounds.isEmpty else { return .zero }
        edit.willModify(region.bounds, in: layer)
        for span in region.spans {
            (layer.buffer.row(span.y) + span.minX).update(repeating: color, count: span.maxX - span.minX + 1)
        }
        return region.bounds
    }

    struct Span {
        let y: Int
        let minX: Int
        let maxX: Int
    }

    /// The horizontal runs of pixels connected to `seed` (4-connected) whose colors are within `tolerance`
    /// of the seed's color, found with a scanline search (no recursion).
    static func connectedRegion(in buffer: PixelBuffer, from seed: IntPoint, tolerance: Double, selection: SelectionMask?) -> (spans: [Span], bounds: IntRect) {
        guard buffer.bounds.contains(seed), selection?.contains(seed) ?? true else { return ([], .zero) }
        let search = RegionSearch(buffer: buffer, target: buffer[seed.x, seed.y], limit: toleranceLimit(tolerance))
        defer { search.visited.deallocate() }
        guard let selection else { return search.run(from: seed, mask: nil, maskBounds: .zero) }
        return selection.values.withUnsafeBufferPointer { search.run(from: seed, mask: $0.baseAddress, maskBounds: selection.bounds) }
    }

    /// The scanline search, on raw pointers so the per-pixel test has no bounds or copy-on-write checks (NFR-6).
    private struct RegionSearch {
        let buffer: PixelBuffer
        let target: Pixel
        let limit: UInt8
        let width: Int
        let height: Int
        let visited: UnsafeMutablePointer<UInt64>

        init(buffer: PixelBuffer, target: Pixel, limit: UInt8) {
            self.buffer = buffer
            self.target = target
            self.limit = limit
            width = buffer.width
            height = buffer.height
            let words = (width * height + 63) / 64
            visited = .allocate(capacity: words)
            visited.initialize(repeating: 0, count: words)
        }

        @inline(__always)
        private func isVisited(_ index: Int) -> Bool {
            visited[index >> 6] & (1 << UInt64(index & 63)) != 0
        }

        /// The first unvisited index in `start...end`, or `end + 1`. Skips whole words of visited pixels.
        @inline(__always)
        private func nextUnvisited(from start: Int, through end: Int) -> Int {
            var index = start
            while index <= end {
                let unvisited = ~visited[index >> 6] >> UInt64(index & 63)
                if unvisited != 0 { return min(index + unvisited.trailingZeroBitCount, end + 1) }
                index = (index | 63) + 1
            }
            return end + 1
        }

        private func markVisited(_ start: Int, through end: Int) {
            var index = start
            while index <= end {
                let bit = index & 63
                let count = min(64 - bit, end - index + 1)
                let bits: UInt64 = count == 64 ? ~0 : ((1 << UInt64(count)) - 1) << UInt64(bit)
                visited[index >> 6] |= bits
                index += count
            }
        }

        /// The pixel's color is close enough and it's inside the selection.
        @inline(__always)
        private func accepts(_ row: UnsafeMutablePointer<Pixel>, _ x: Int, _ y: Int, _ mask: UnsafePointer<UInt8>?, _ maskBounds: IntRect) -> Bool {
            guard row[x].matches(target, tolerance: limit) else { return false }
            guard let mask else { return true }
            guard x >= maskBounds.minX, x < maskBounds.maxX, y >= maskBounds.minY, y < maskBounds.maxY else { return false }
            return mask[(y - maskBounds.minY) * maskBounds.width + (x - maskBounds.minX)] > 0
        }

        func run(from seed: IntPoint, mask: UnsafePointer<UInt8>?, maskBounds: IntRect) -> (spans: [Span], bounds: IntRect) {
            var spans: [Span] = []
            var pending = [seed]
            var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min
            while let point = pending.popLast() {
                let y = point.y
                let row = buffer.row(y)
                guard !isVisited(y * width + point.x), accepts(row, point.x, y, mask, maskBounds) else { continue }
                // Spans are maximal runs, so a run grown from an unvisited pixel holds no visited pixels.
                var spanMin = point.x, spanMax = point.x
                while spanMin > 0, accepts(row, spanMin - 1, y, mask, maskBounds) { spanMin -= 1 }
                while spanMax < width - 1, accepts(row, spanMax + 1, y, mask, maskBounds) { spanMax += 1 }
                markVisited(y * width + spanMin, through: y * width + spanMax)
                spans.append(Span(y: y, minX: spanMin, maxX: spanMax))
                minX = min(minX, spanMin); maxX = max(maxX, spanMax); minY = min(minY, y); maxY = max(maxY, y)
                for neighborY in [y - 1, y + 1] where neighborY >= 0 && neighborY < height {
                    let neighborRow = buffer.row(neighborY)
                    let base = neighborY * width
                    var x = spanMin
                    while true {
                        x = nextUnvisited(from: base + x, through: base + spanMax) - base
                        guard x <= spanMax else { break }
                        if accepts(neighborRow, x, neighborY, mask, maskBounds) {
                            pending.append(IntPoint(x: x, y: neighborY))
                            x += 1
                            while x <= spanMax, !isVisited(base + x), accepts(neighborRow, x, neighborY, mask, maskBounds) { x += 1 }
                        }
                        x += 1
                    }
                }
            }
            guard !spans.isEmpty else { return ([], .zero) }
            return (spans, IntRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
        }
    }

    static func toleranceLimit(_ tolerance: Double) -> UInt8 {
        UInt8((min(max(tolerance, 0), 1) * 255).rounded())
    }
}

extension SelectionMask {
    /// Selects pixels whose colors are within `tolerance` (0...1) of the color at `seed` (FR-3.1).
    /// Contiguous selects only the connected area; otherwise every matching pixel in the image.
    public static func magicWand(in buffer: PixelBuffer, at seed: IntPoint, tolerance: Double, contiguous: Bool) -> SelectionMask? {
        guard buffer.bounds.contains(seed) else { return nil }
        if contiguous {
            let region = FloodFill.connectedRegion(in: buffer, from: seed, tolerance: tolerance, selection: nil)
            guard !region.bounds.isEmpty else { return nil }
            let bounds = region.bounds
            var values = [UInt8](repeating: 0, count: bounds.area)
            for span in region.spans {
                let start = (span.y - bounds.minY) * bounds.width + (span.minX - bounds.minX)
                for offset in 0...(span.maxX - span.minX) { values[start + offset] = 255 }
            }
            return SelectionMask(bounds: bounds, values: values)
        }
        let target = buffer[seed.x, seed.y]
        let limit = FloodFill.toleranceLimit(tolerance)
        var values = [UInt8](repeating: 0, count: buffer.bounds.area)
        for y in 0..<buffer.height {
            let row = buffer.row(y)
            for x in 0..<buffer.width where row[x].matches(target, tolerance: limit) {
                values[y * buffer.width + x] = 255
            }
        }
        return SelectionMask(bounds: buffer.bounds, values: values).trimmed()
    }
}

