public enum Compositing {
    /// Source-over in straight alpha. `coverage` (0...1) scales the source's alpha.
    @inline(__always)
    public static func over(_ destination: Pixel, _ source: Pixel, coverage: Float = 1) -> Pixel {
        let sourceAlpha = Float(source.a) / 255 * coverage
        if sourceAlpha <= 0 { return destination }
        let destinationWeight = Float(destination.a) / 255 * (1 - sourceAlpha)
        let outAlpha = sourceAlpha + destinationWeight

        @inline(__always)
        func channel(_ s: UInt8, _ d: UInt8) -> UInt8 {
            let value = (Float(s) * sourceAlpha + Float(d) * destinationWeight) / outAlpha
            return UInt8(Swift.min(255, value.rounded()))
        }

        return Pixel(
            r: channel(source.r, destination.r),
            g: channel(source.g, destination.g),
            b: channel(source.b, destination.b),
            a: UInt8(Swift.min(255, (outAlpha * 255).rounded()))
        )
    }

    /// Composites `image` over `layer` with its top-left corner at `origin`, recording the change in `edit`.
    @discardableResult
    public static func draw(_ image: PixelBuffer, at origin: IntPoint, onto layer: Layer, edit: Edit) -> IntRect {
        let target = IntRect(x: origin.x, y: origin.y, width: image.width, height: image.height)
            .intersection(layer.buffer.bounds)
        guard !target.isEmpty else { return .zero }
        edit.willModify(target, in: layer)
        for y in target.minY..<target.maxY {
            let source = image.row(y - origin.y)
            let destination = layer.buffer.row(y)
            for x in target.minX..<target.maxX {
                destination[x] = over(destination[x], source[x - origin.x])
            }
        }
        return target
    }

    /// For the screen while a shape or text not yet placed sits on a layer that locks its transparency: that layer's
    /// pixels under `image`, with `image` drawn over them as placing it and the lock will leave them, and where they go
    /// (review U, finding 3). Nil when nothing overlaps.
    public static func lockedPatch(of layer: Layer, under image: PixelBuffer, at origin: IntPoint) -> (pixels: PixelBuffer, area: IntRect)? {
        let area = IntRect(x: origin.x, y: origin.y, width: image.width, height: image.height).intersection(layer.buffer.bounds)
        guard !area.isEmpty else { return nil }
        let patch = PixelBuffer(width: area.width, height: area.height)
        ParallelRows.forEach(area.minY..<area.maxY) { rows in
            for y in rows {
                let source = image.row(y - origin.y), base = layer.buffer.row(y), target = patch.row(y - area.minY)
                for x in area.minX..<area.maxX {
                    let old = base[x]
                    guard old.a > 0 else {
                        target[x - area.minX] = old
                        continue
                    }
                    let drawn = over(old, source[x - origin.x])
                    target[x - area.minX] = Pixel(r: drawn.r, g: drawn.g, b: drawn.b, a: old.a)
                }
            }
        }
        return (patch, area)
    }
}
