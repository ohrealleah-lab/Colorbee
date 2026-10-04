/// The nine brushes (FR-4.2).
public enum Brush: CaseIterable, Sendable {
    case round
    case calligraphyForward
    case calligraphyBack
    case airbrush
    case oil
    case crayon
    case marker
    case naturalPencil
    case watercolor

    public var name: String {
        switch self {
        case .round: "Round"
        case .calligraphyForward: "Calligraphy 1"
        case .calligraphyBack: "Calligraphy 2"
        case .airbrush: "Airbrush"
        case .oil: "Oil"
        case .crayon: "Crayon"
        case .marker: "Marker"
        case .naturalPencil: "Natural Pencil"
        case .watercolor: "Watercolor"
        }
    }

    /// The marker paints at half the chosen color's opacity.
    public static let markerOpacity = 0.5

    /// The share of the brush size used at a pressure; the lightest touch still draws a quarter-size line.
    static func sizeFactor(pressure: Double) -> Double {
        0.25 + 0.75 * min(1, max(0, pressure))
    }

    /// The brush mirrored left to right, for Symmetry: a `/` nib's reflection is a `\` nib.
    public var mirrored: Brush {
        switch self {
        case .calligraphyForward: .calligraphyBack
        case .calligraphyBack: .calligraphyForward
        default: self
        }
    }

    /// A stroke of this brush. `seed` fixes the airbrush spray and oil bristles; pass one in tests.
    /// `sharingPainterWith` is another stroke of the same brush (a Symmetry mirror), whose painting this one joins.
    public func makeStroke(diameter: Double, color: Pixel, layer: Layer, edit: Edit, seed: UInt64 = .random(in: 0...UInt64.max),
                           sharingPainterWith other: Stroke? = nil) -> Stroke {
        switch self {
        case .round:
            return RoundBrushStroke(diameter: diameter, color: color, layer: layer, edit: edit, sharingPainterWith: other)
        case .marker:
            var translucent = color
            translucent.a = UInt8((Double(color.a) * Self.markerOpacity).rounded())
            return RoundBrushStroke(diameter: diameter, color: translucent, layer: layer, edit: edit, sharingPainterWith: other)
        default:
            return BrushStroke(brush: self, diameter: diameter, color: color, layer: layer, edit: edit, seed: seed, sharingPainterWith: other)
        }
    }
}
