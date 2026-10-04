import Foundation

/// A stroke of one of the textured or shaped brushes: calligraphy, airbrush, oil, crayon, natural pencil
/// and watercolor (FR-4.2). Round and Marker use `RoundBrushStroke`. Pressure scales the size, and also
/// the strength where a real tool would get stronger with pressure (crayon, pencil).
public final class BrushStroke: CoveragePainting {
    public let brush: Brush
    public let diameter: Double
    public let color: Pixel

    let painter: CoveragePainter
    private var walker = DabWalker()
    private var random: SplitMix64
    private let bristles: [Bristle]
    /// Every oil dab, so the tail can be repainted tapered when the stroke ends.
    private var dabs: [DabWalker.Dab] = []

    private struct Bristle {
        /// Across the brush, from −1 (one edge) to 1 (the other).
        let offset: Double
        let strength: Double
        let width: Double
    }

    public init(brush: Brush, diameter: Double, color: Pixel, layer: Layer, edit: Edit, seed: UInt64, sharingPainterWith other: Stroke? = nil) {
        precondition(brush != .round && brush != .marker, "Round and Marker use RoundBrushStroke")
        self.brush = brush
        self.diameter = max(1, diameter)
        self.color = color
        var generator = SplitMix64(seed: seed)
        painter = other?.sharedPainter() ?? CoveragePainter(
            layer: layer, edit: edit, effect: .over(color),
            transfer: brush == .watercolor ? Self.watercolorTransfer : nil
        )
        if brush == .oil {
            let count = min(24, max(4, Int(max(1, diameter) / 2.5)))
            bristles = (0..<count).map { index in
                Bristle(
                    offset: (Double(index) + 0.5) / Double(count) * 2 - 1 + Double.random(in: -0.15...0.15, using: &generator) / Double(count),
                    strength: Double.random(in: 0.55...1, using: &generator),
                    width: Double.random(in: 0.8...1.4, using: &generator)
                )
            }
        } else {
            bristles = []
        }
        random = generator
    }

    public var dirtyRect: IntRect { painter.dirtyRect }

    @discardableResult
    public func move(to point: Point2D, pressure: Double) -> IntRect {
        guard color.a > 0 else { return .zero }
        var changed = IntRect.zero
        for dab in walker.walk(to: point, pressure: pressure, spacing: spacing) {
            if brush == .oil { dabs.append(dab) }
            changed = changed.union(paint(dab, taper: brush == .oil ? startTaper(dab.distance) : 1))
        }
        return changed
    }

    /// The airbrush keeps spraying while the pointer holds still, so the paint builds up.
    @discardableResult
    public func hold() -> IntRect {
        guard brush == .airbrush, color.a > 0, let current = walker.current else { return .zero }
        return spray(at: current.point, pressure: current.pressure)
    }

    /// The oil brush tapers its tail: the last stretch is cleared and repainted narrowing to a point.
    @discardableResult
    public func finish() -> IntRect {
        guard brush == .oil, !dabs.isEmpty else { return .zero }
        let total = walker.length
        let tail = dabs.filter { $0.distance > total - taperLength }
        let region = tail.reduce(IntRect.zero) { $0.union(bounds(of: $1)) }
        guard !region.isEmpty else { return .zero }
        painter.clear(region)
        for dab in dabs where !bounds(of: dab).intersection(region).isEmpty {
            paint(dab, taper: startTaper(dab.distance) * endTaper(total - dab.distance))
        }
        return region
    }

    // MARK: Dabs

    private func radius(_ pressure: Double) -> Double {
        diameter / 2 * Brush.sizeFactor(pressure: pressure)
    }

    private var nibThickness: Double { max(1, diameter * 0.2) }

    private func spacing(_ pressure: Double) -> Double {
        let r = radius(pressure)
        return switch brush {
        case .calligraphyForward, .calligraphyBack: max(0.25, nibThickness * 0.4)
        case .airbrush: max(1, r * 0.5)
        // Oil's thin bristles need close dabs or they break into dots.
        case .oil: max(0.5, r * 0.15)
        case .naturalPencil: max(0.3, r * 0.25)
        default: max(0.5, r * 0.25)
        }
    }

    private var taperLength: Double { diameter * 1.5 }

    private func startTaper(_ distance: Double) -> Double {
        min(1, 0.35 + 0.65 * distance / taperLength)
    }

    private func endTaper(_ remaining: Double) -> Double {
        min(1, 0.35 + 0.65 * max(0, remaining) / taperLength)
    }

    private func bounds(of dab: DabWalker.Dab) -> IntRect {
        let reach = radius(dab.pressure) + 2
        return IntRect(enclosingMinX: dab.center.x - reach, minY: dab.center.y - reach, maxX: dab.center.x + reach, maxY: dab.center.y + reach)
    }

    @discardableResult
    private func paint(_ dab: DabWalker.Dab, taper: Double) -> IntRect {
        switch brush {
        case .calligraphyForward, .calligraphyBack: nib(dab)
        case .airbrush: spray(at: dab.center, pressure: dab.pressure)
        case .oil: bristleDab(dab, taper: taper)
        case .crayon: crayon(dab)
        case .naturalPencil: graphite(dab)
        case .watercolor: wash(dab)
        case .round, .marker: .zero
        }
    }

    /// A flat nib held at 45°: `/` for Calligraphy 1, `\` for Calligraphy 2. Pressure lengthens the nib.
    private func nib(_ dab: DabWalker.Dab) -> IntRect {
        let axis = brush == .calligraphyForward ? Point2D(x: 1, y: -1) : Point2D(x: 1, y: 1)
        let nx = axis.x / 2.squareRoot(), ny = axis.y / 2.squareRoot()
        let half = radius(dab.pressure)
        let thickness = nibThickness / 2
        let straight = max(0, half - thickness)
        let center = dab.center
        let area = IntRect(enclosingMinX: center.x - half - 1, minY: center.y - half - 1, maxX: center.x + half + 1, maxY: center.y + half + 1)
        return painter.paint(area) { x, y in
            let ox = Double(x) + 0.5 - center.x, oy = Double(y) + 0.5 - center.y
            let along = ox * nx + oy * ny
            let across = -ox * ny + oy * nx
            let nearest = min(straight, max(-straight, along))
            let distance = ((along - nearest) * (along - nearest) + across * across).squareRoot() - thickness
            return Self.coverage(min(1, max(0, 0.5 - distance)))
        }
    }

    /// Single-pixel droplets scattered over a disc. Each call adds more, so holding still fills it in.
    private func spray(at center: Point2D, pressure: Double) -> IntRect {
        let r = radius(pressure)
        let count = max(1, Int((r * r * 0.15).rounded()))
        var changed = IntRect.zero
        for _ in 0..<count {
            let distance = r * Double.random(in: 0...1, using: &random).squareRoot()
            let angle = Double.random(in: 0..<(2 * .pi), using: &random)
            let pixel = IntPoint(x: Int((center.x + distance * cos(angle)).rounded(.down)), y: Int((center.y + distance * sin(angle)).rounded(.down)))
            changed = changed.union(painter.paint(IntRect(x: pixel.x, y: pixel.y, width: 1, height: 1)) { _, _ in 255 })
        }
        return changed
    }

    /// A row of bristles across the direction of travel, each with its own strength, which streaks along the stroke.
    private func bristleDab(_ dab: DabWalker.Dab, taper: Double) -> IntRect {
        let r = radius(dab.pressure) * taper
        let across = Point2D(x: -dab.direction.y, y: dab.direction.x)
        var changed = IntRect.zero
        for (index, bristle) in bristles.enumerated() {
            let center = Point2D(x: dab.center.x + across.x * bristle.offset * r, y: dab.center.y + across.y * bristle.offset * r)
            let bristleRadius = max(0.5, r / Double(bristles.count) * 1.6 * bristle.width)
            let streak = 0.8 + 0.2 * BrushTexture.smooth(dab.distance / 6, Double(index) * 7.3, seed: 41)
            let strength = bristle.strength * streak
            let area = IntRect(
                enclosingMinX: center.x - bristleRadius - 1, minY: center.y - bristleRadius - 1,
                maxX: center.x + bristleRadius + 1, maxY: center.y + bristleRadius + 1
            )
            changed = changed.union(painter.paint(area) { x, y in
                let ox = Double(x) + 0.5 - center.x, oy = Double(y) + 0.5 - center.y
                let edge = min(1, max(0, bristleRadius + 0.5 - (ox * ox + oy * oy).squareRoot()))
                return Self.coverage(edge * strength)
            })
        }
        return changed
    }

    /// Wax catching the paper's grain: a rough-edged dab with gaps. Harder pressure fills more of the gaps.
    private func crayon(_ dab: DabWalker.Dab) -> IntRect {
        let r = radius(dab.pressure)
        let gaps = 0.42 - 0.2 * dab.pressure
        return disc(around: dab.center, reach: r) { x, y, distance in
            let rough = r * (0.85 + 0.15 * BrushTexture.smooth(Double(x) / 3, Double(y) / 3, seed: 11))
            let shape = min(1, max(0, rough + 0.5 - distance))
            let grain = 0.6 * BrushTexture.hash(x, y, seed: 3) + 0.4 * BrushTexture.smooth(Double(x) / 2.5, Double(y) / 2.5, seed: 5)
            return grain < gaps ? 0 : shape * (0.7 + 0.3 * grain)
        }
    }

    /// Graphite: never fully opaque, with a fine grain. Pressure darkens it as well as widening it.
    private func graphite(_ dab: DabWalker.Dab) -> IntRect {
        let r = radius(dab.pressure)
        let strength = 0.55 + 0.45 * dab.pressure
        return disc(around: dab.center, reach: r) { x, y, distance in
            let shape = min(1, max(0, r + 0.5 - distance))
            let grain = 0.5 * BrushTexture.hash(x, y, seed: 7) + 0.5 * BrushTexture.smooth(Double(x) / 1.7, Double(y) / 1.7, seed: 9)
            return shape * (0.25 + 0.6 * grain) * strength
        }
    }

    /// Records how close each pixel is to the middle of the stroke, with a ragged outer edge;
    /// `watercolorTransfer` turns that into a wash that's darker at the rim.
    private func wash(_ dab: DabWalker.Dab) -> IntRect {
        let r = radius(dab.pressure)
        return disc(around: dab.center, reach: r * 1.2) { x, y, distance in
            let ragged = r * (0.8 + 0.4 * BrushTexture.smooth(Double(x) / 7, Double(y) / 7, seed: 17))
            return max(0, 1 - distance / ragged)
        }
    }

    /// Paints a disc of `reach` around `center`, with `amount` (0...1) from the pixel and its distance to the center.
    private func disc(around center: Point2D, reach: Double, amount: @escaping (Int, Int, Double) -> Double) -> IntRect {
        let area = IntRect(enclosingMinX: center.x - reach - 1, minY: center.y - reach - 1, maxX: center.x + reach + 1, maxY: center.y + reach + 1)
        let limit = (reach + 0.5) * (reach + 0.5)
        return painter.paint(area) { x, y in
            let ox = Double(x) + 0.5 - center.x, oy = Double(y) + 0.5 - center.y
            let squared = ox * ox + oy * oy
            // Most of the square around a disc is outside it; skip the grain math there.
            guard squared <= limit else { return 0 }
            return Self.coverage(amount(x, y, squared.squareRoot()))
        }
    }

    private static func coverage(_ amount: Double) -> UInt8 {
        UInt8((min(1, max(0, amount)) * 255).rounded())
    }

    /// Closeness to the middle of the stroke (0 at the edge, 255 in the middle) to watercolor coverage:
    /// a soft bleed outside, darkest just inside the rim, and a lighter wash in the middle.
    static let watercolorTransfer: [UInt8] = (0..<256).map { value in
        let closeness = Double(value) / 255
        let feather = 0.08, rim = 0.75, middle = 0.35, settle = 0.45
        let amount: Double = if closeness < feather {
            rim * closeness / feather
        } else if closeness < settle {
            rim + (middle - rim) * (closeness - feather) / (settle - feather)
        } else {
            middle
        }
        return coverage(amount)
    }
}
