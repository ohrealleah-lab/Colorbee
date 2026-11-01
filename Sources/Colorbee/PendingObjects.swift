import ColorbeeCore
import CoreGraphics
import Foundation

/// A shape still being edited, before it's placed into the layer (FR-5.1).
struct PendingShape: Equatable {
    var kind: ShapeKind
    var start: Point2D
    var end: Point2D
    /// Polygon vertices, or a curve's start, two control points and end.
    var points: [Point2D] = []
    var rotation = 0.0
    /// Right-dragged: outline uses Color 2 and fill uses Color 1.
    var swapped: Bool
    /// A polygon or curve still being placed point by point.
    var isBuilding = false
    /// Curve construction: 0 the line, 1 the first bend, 2 the second bend.
    var curveStage = 0

    mutating func translate(by dx: Double, _ dy: Double) {
        start = Point2D(x: start.x + dx, y: start.y + dy)
        end = Point2D(x: end.x + dx, y: end.y + dy)
        points = points.map { Point2D(x: $0.x + dx, y: $0.y + dy) }
    }
}

/// A step badge still being placed (FR-5.3): it can be moved or removed until the next one, or another command,
/// places it.
struct PendingBadge: Equatable {
    var style: BadgeStyle
    var value: Int
    var center: Point2D
    var arrowTip: Point2D?
    /// Right-clicked: the circle in Color 2 and the number in Color 1.
    var swapped: Bool
}

/// Text formatting for the text tool (FR-6.1).
struct TextStyle: Equatable, Codable {
    var fontFamily = "Helvetica Neue"
    /// In image pixels at 100% zoom.
    var fontSize = 24.0
    var bold = false
    var italic = false
    var underline = false
    var strikethrough = false
    var alignment: TextAlignment = .left
    /// Opaque draws a Color 2 rectangle behind the text.
    var opaqueBackground = false
}

// Each text setting crosses between the Text tool's settings and a text here, both ways, so a new one is added to
// both at once (review round 11, AB 6).
extension TextStyle {
    /// The style `spec` was set in.
    init(_ spec: TextSpec) {
        fontFamily = spec.fontFamily
        fontSize = spec.fontSize
        bold = spec.bold
        italic = spec.italic
        underline = spec.underline
        strikethrough = spec.strikethrough
        alignment = spec.alignment
        opaqueBackground = spec.background != nil
    }

    /// `text` set in this style, in `color`, on `background` when the style's background is opaque.
    func spec(_ text: String, origin: Point2D, wrapWidth: Double?, minimumHeight: Double, color: Pixel, background: Pixel) -> TextSpec {
        var spec = TextSpec(text: text, origin: origin, wrapWidth: wrapWidth, fontFamily: fontFamily, fontSize: fontSize, color: color,
                            background: opaqueBackground ? background : nil)
        spec.bold = bold
        spec.italic = italic
        spec.underline = underline
        spec.strikethrough = strikethrough
        spec.alignment = alignment
        spec.minimumHeight = minimumHeight
        return spec
    }
}

/// A text box still being typed into.
struct PendingText: Equatable {
    var origin: Point2D
    /// Set when the box was dragged out; otherwise lines run as long as they need.
    var wrapWidth: Double?
    /// A dragged-out box keeps at least its dragged height.
    var minimumHeight: Double = 0
    var string = ""
    /// The text layer being edited; nil for new text.
    var layerID: LayerID?
}

/// What a press on the open text box grabbed: a handle resizes it, the border moves it (FR-6.1).
enum TextBoxGrab: Equatable {
    case handle(SelectionHandle)
    case border
}

/// What a press on a pending shape grabbed.
enum ShapeHandle: Equatable {
    case box(SelectionHandle)
    case start
    case end
    case vertex(Int)
    case rotate
}
