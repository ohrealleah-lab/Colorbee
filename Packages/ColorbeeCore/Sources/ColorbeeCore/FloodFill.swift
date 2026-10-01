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
        let buffer = layer.buffer
        guard buffer.bounds.contains(seed), selection?.contains(seed) ?? true else { return .zero }
        let target = buffer[seed.x, seed.y]
        let limit = UInt8((min(max(tolerance, 0), 1) * 255).rounded())
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
        func fillable(_ x: Int, _ y: Int) -> Bool {
            !isVisited(x, y) && buffer[x, y].matches(target, tolerance: limit) && (selection?[x, y] ?? 255) > 0
        }

        // Scanline fill: find each horizontal run, then queue the rows above and below it.
        var spans: [(y: Int, minX: Int, maxX: Int)] = []
        var pending = [seed]
        var area = IntRect.zero
        while let point = pending.popLast() {
            guard fillable(point.x, point.y) else { continue }
            var minX = point.x, maxX = point.x
            while minX > 0, fillable(minX - 1, point.y) { minX -= 1 }
            while maxX < width - 1, fillable(maxX + 1, point.y) { maxX += 1 }
            for x in minX...maxX { markVisited(x, point.y) }
            spans.append((point.y, minX, maxX))
            area = area.union(IntRect(x: minX, y: point.y, width: maxX - minX + 1, height: 1))
            for neighborY in [point.y - 1, point.y + 1] where neighborY >= 0 && neighborY < buffer.height {
                var x = minX
                while x <= maxX {
                    if fillable(x, neighborY) {
                        pending.append(IntPoint(x: x, y: neighborY))
                        while x <= maxX, fillable(x, neighborY) { x += 1 }
                    }
                    x += 1
                }
            }
        }

        edit.willModify(area, in: layer)
        for span in spans {
            (buffer.row(span.y) + span.minX).update(repeating: color, count: span.maxX - span.minX + 1)
        }
        return area
    }
}
