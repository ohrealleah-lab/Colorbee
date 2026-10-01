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
        let target = buffer[seed.x, seed.y]
        let limit = toleranceLimit(tolerance)
        let width = buffer.width
        var visited = [UInt64](repeating: 0, count: (width * buffer.height + 63) / 64)

        func isVisited(_ x: Int, _ y: Int) -> Bool {
            let index = y * width + x
            return visited[index >> 6] & (1 << UInt64(index & 63)) != 0
        }
        func markVisited(_ x: Int, _ y: Int) {
            let index = y * width + x
            visited[index >> 6] |= 1 << UInt64(index & 63)
        }
        func matches(_ x: Int, _ y: Int) -> Bool {
            !isVisited(x, y) && buffer[x, y].matches(target, tolerance: limit) && (selection?[x, y] ?? 255) > 0
        }

        var spans: [Span] = []
        var pending = [seed]
        var bounds = IntRect.zero
        while let point = pending.popLast() {
            guard matches(point.x, point.y) else { continue }
            var minX = point.x, maxX = point.x
            while minX > 0, matches(minX - 1, point.y) { minX -= 1 }
            while maxX < width - 1, matches(maxX + 1, point.y) { maxX += 1 }
            for x in minX...maxX { markVisited(x, point.y) }
            spans.append(Span(y: point.y, minX: minX, maxX: maxX))
            bounds = bounds.union(IntRect(x: minX, y: point.y, width: maxX - minX + 1, height: 1))
            for neighborY in [point.y - 1, point.y + 1] where neighborY >= 0 && neighborY < buffer.height {
                var x = minX
                while x <= maxX {
                    if matches(x, neighborY) {
                        pending.append(IntPoint(x: x, y: neighborY))
                        while x <= maxX, matches(x, neighborY) { x += 1 }
                    }
                    x += 1
                }
            }
        }
        return (spans, bounds)
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
