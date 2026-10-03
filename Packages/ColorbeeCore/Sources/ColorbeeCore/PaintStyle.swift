/// How a shape's outline or fill is painted (FR-5.1). The textured styles reuse the brushes.
public enum PaintStyle: CaseIterable, Sendable {
    case solid
    case crayon
    case marker
    case oil
    case watercolor
    case naturalPencil

    public var name: String {
        switch self {
        case .solid: "Solid"
        case .crayon: "Crayon"
        case .marker: "Marker"
        case .oil: "Oil"
        case .watercolor: "Watercolor"
        case .naturalPencil: "Natural Pencil"
        }
    }

    /// The brush a textured outline is drawn with; nil for solid.
    var brush: Brush? {
        switch self {
        case .solid: nil
        case .crayon: .crayon
        case .marker: .marker
        case .oil: .oil
        case .watercolor: .watercolor
        case .naturalPencil: .naturalPencil
        }
    }

    /// How much of the fill color shows at a pixel, from the shape's coverage there (`mask`) and how
    /// far inside the shape it is (`interior`: 0 at the edge, 1 well inside). Fixed to image pixels,
    /// like the brush grain.
    func fillAmount(x: Int, y: Int, mask: Double, interior: Double) -> Double {
        switch self {
        case .solid:
            return mask
        case .crayon:
            let grain = 0.6 * BrushTexture.hash(x, y, seed: 3) + 0.4 * BrushTexture.smooth(Double(x) / 2.5, Double(y) / 2.5, seed: 5)
            return grain < 0.32 ? 0 : mask * (0.7 + 0.3 * grain)
        case .marker:
            return mask * Brush.markerOpacity
        case .oil:
            // Long horizontal streaks, like brush marks across a canvas.
            return mask * (0.55 + 0.45 * BrushTexture.smooth(Double(x) / 16, Double(y) / 1.6, seed: 41))
        case .watercolor:
            return mask * (0.35 + 0.45 * (1 - interior))
        case .naturalPencil:
            let grain = 0.5 * BrushTexture.hash(x, y, seed: 7) + 0.5 * BrushTexture.smooth(Double(x) / 1.7, Double(y) / 1.7, seed: 9)
            return mask * (0.25 + 0.6 * grain) * 0.85
        }
    }
}
