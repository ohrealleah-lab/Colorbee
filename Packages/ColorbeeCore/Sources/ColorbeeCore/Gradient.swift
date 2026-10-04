import Foundation

public enum GradientMode: CaseIterable, Sendable {
    case linear
    case radial
    case reflected
    case diamond
    case conical

    public var name: String {
        switch self {
        case .linear: "Linear"
        case .radial: "Radial"
        case .reflected: "Reflected"
        case .diamond: "Diamond"
        case .conical: "Conical"
        }
    }
}

public enum Gradients {
    /// Draws a gradient from `startColor` at `start` to `endColor` at `end` over the layer (FR-5.2),
    /// inside `selection` when given. Each color's alpha is honored, so a gradient can fade to transparent.
    @discardableResult
    public static func draw(
        _ mode: GradientMode,
        from start: Point2D,
        to end: Point2D,
        startColor: Pixel,
        endColor: Pixel,
        onto layer: Layer,
        selection: SelectionMask?,
        edit: Edit
    ) -> IntRect {
        let region = (selection?.bounds ?? layer.buffer.bounds).intersection(layer.buffer.bounds)
        guard !region.isEmpty else { return .zero }
        let dx = end.x - start.x, dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        let length = lengthSquared.squareRoot()
        guard length > 0 else { return .zero }
        let unitX = dx / length, unitY = dy / length

        edit.willModify(region, in: layer)
        let buffer = layer.buffer
        // Rows on all cores; each band writes only its own rows (review I, finding 12).
        ParallelRows.forEach(region.minY..<region.maxY) { rows in
            for y in rows {
                let row = buffer.row(y)
                let py = Double(y) + 0.5 - start.y
                for x in region.minX..<region.maxX where selection.map({ $0[x, y] > 0 }) ?? true {
                    let px = Double(x) + 0.5 - start.x
                    let along = px * unitX + py * unitY
                    let across = px * -unitY + py * unitX
                    let t: Double = switch mode {
                    case .linear: along / length
                    case .reflected: abs(along) / length
                    case .radial: (px * px + py * py).squareRoot() / length
                    case .diamond: (abs(along) + abs(across)) / length
                    case .conical: (atan2(across, along) + .pi) / (2 * .pi)
                    }
                    row[x] = Compositing.over(row[x], mix(startColor, endColor, min(1, max(0, t))))
                }
            }
        }
        return region
    }

    /// Interpolates in premultiplied space so fading to transparent doesn't pass through dark fringes.
    static func mix(_ a: Pixel, _ b: Pixel, _ t: Double) -> Pixel {
        let alphaA = Double(a.a) / 255, alphaB = Double(b.a) / 255
        let alpha = alphaA * (1 - t) + alphaB * t
        guard alpha > 0 else { return .clear }
        func channel(_ first: UInt8, _ second: UInt8) -> UInt8 {
            let value = (Double(first) * alphaA * (1 - t) + Double(second) * alphaB * t) / alpha
            return UInt8(min(255, max(0, value.rounded())))
        }
        return Pixel(r: channel(a.r, b.r), g: channel(a.g, b.g), b: channel(a.b, b.b), a: UInt8((alpha * 255).rounded()))
    }
}
