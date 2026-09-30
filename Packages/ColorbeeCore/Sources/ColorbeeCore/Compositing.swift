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
}
