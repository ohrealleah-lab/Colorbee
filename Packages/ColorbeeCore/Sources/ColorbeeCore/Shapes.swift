import Accelerate
import CoreGraphics

public enum ShapeKind: CaseIterable, Sendable {
    case line
    case arrow
    case rectangle
    case roundedRectangle
    case ellipse

    /// Lines and arrows are defined by two end points; the others by a bounding box.
    public var isLinear: Bool { self == .line || self == .arrow }

    public var name: String {
        switch self {
        case .line: "Line"
        case .arrow: "Arrow"
        case .rectangle: "Rectangle"
        case .roundedRectangle: "Rounded Rectangle"
        case .ellipse: "Ellipse"
        }
    }
}

/// A shape ready to draw. Coordinates are in image pixels.
public struct ShapeSpec: Equatable, Sendable {
    public var kind: ShapeKind
    /// The drag's start and end: line end points, or opposite corners of the bounding box.
    public var start: Point2D
    public var end: Point2D
    public var lineWidth: Double
    /// Nil draws no outline.
    public var outline: Pixel?
    /// Nil draws no fill. Ignored for lines and arrows.
    public var fill: Pixel?

    public init(kind: ShapeKind, start: Point2D, end: Point2D, lineWidth: Double, outline: Pixel?, fill: Pixel?) {
        self.kind = kind
        self.start = start
        self.end = end
        self.lineWidth = max(1, lineWidth)
        self.outline = outline
        self.fill = fill
    }

    /// The dragged box, for box shapes.
    public var box: IntRect {
        IntRect(
            enclosingMinX: min(start.x, end.x), minY: min(start.y, end.y),
            maxX: max(start.x, end.x), maxY: max(start.y, end.y)
        )
    }

    var arrowHeadLength: Double { max(10, lineWidth * 4) }

    /// Everything the shape can paint, including stroke width, arrow head and anti-aliasing.
    public var paintedBounds: IntRect {
        let margin = (kind == .arrow ? arrowHeadLength : lineWidth) + 2
        return IntRect(
            enclosingMinX: min(start.x, end.x) - margin, minY: min(start.y, end.y) - margin,
            maxX: max(start.x, end.x) + margin, maxY: max(start.y, end.y) + margin
        )
    }

    /// Snaps the end point: squares and circles for box shapes, 45° steps for lines (FR-5.1).
    public func constrained() -> ShapeSpec {
        var result = self
        let dx = end.x - start.x, dy = end.y - start.y
        if kind.isLinear {
            let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
            let length = (dx * dx + dy * dy).squareRoot()
            result.end = Point2D(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length)
        } else {
            let side = max(abs(dx), abs(dy))
            result.end = Point2D(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
        }
        return result
    }
}

public enum ShapeRenderer {
    /// Draws the shape into a straight-alpha buffer covering its painted area within `canvasBounds`.
    /// Returns nil when nothing would be visible.
    public static func render(_ shape: ShapeSpec, colorSpace: CGColorSpace, clippedTo canvasBounds: IntRect) -> (pixels: PixelBuffer, origin: IntPoint)? {
        let area = shape.paintedBounds.intersection(canvasBounds)
        guard !area.isEmpty, shape.outline != nil || (shape.fill != nil && !shape.kind.isLinear) else { return nil }
        let buffer = PixelBuffer(width: area.width, height: area.height)
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(
            data: buffer.baseAddress, width: area.width, height: area.height, bitsPerComponent: 8,
            bytesPerRow: buffer.bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo
        ) else { return nil }

        // Image coordinates: origin at the top-left of the canvas, y down.
        context.translateBy(x: 0, y: CGFloat(area.height))
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: CGFloat(-area.minX), y: CGFloat(-area.minY))
        context.setLineWidth(shape.lineWidth)

        func cgColor(_ pixel: Pixel) -> CGColor {
            CGColor(colorSpace: colorSpace, components: [pixel.r, pixel.g, pixel.b, pixel.a].map { CGFloat($0) / 255 })!
        }

        if shape.kind.isLinear {
            draw(line: shape, in: context, color: shape.outline.map(cgColor))
        } else {
            // Inset the outline so it stays inside the dragged box.
            let box = CGRect(
                x: min(shape.start.x, shape.end.x), y: min(shape.start.y, shape.end.y),
                width: abs(shape.end.x - shape.start.x), height: abs(shape.end.y - shape.start.y)
            )
            let inset = shape.outline == nil ? 0 : min(shape.lineWidth / 2, min(box.width, box.height) / 2)
            let path = outlinePath(shape.kind, in: box.insetBy(dx: inset, dy: inset))
            if let fill = shape.fill {
                context.addPath(path)
                context.setFillColor(cgColor(fill))
                context.fillPath()
            }
            if let outline = shape.outline {
                context.addPath(path)
                context.setStrokeColor(cgColor(outline))
                context.strokePath()
            }
        }

        var image = buffer.vImageBuffer
        // BGRA keeps alpha last, which is all the RGBA8888 variant needs.
        vImageUnpremultiplyData_RGBA8888(&image, &image, vImage_Flags(kvImageNoFlags))
        return (buffer, IntPoint(x: area.minX, y: area.minY))
    }

    private static func outlinePath(_ kind: ShapeKind, in rect: CGRect) -> CGPath {
        switch kind {
        case .ellipse:
            return CGPath(ellipseIn: rect, transform: nil)
        case .roundedRectangle:
            let radius = min(rect.width, rect.height) * 0.2
            return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        default:
            return CGPath(rect: rect, transform: nil)
        }
    }

    private static func draw(line shape: ShapeSpec, in context: CGContext, color: CGColor?) {
        guard let color else { return }
        context.setStrokeColor(color)
        context.setFillColor(color)
        let start = CGPoint(x: shape.start.x, y: shape.start.y)
        var lineEnd = CGPoint(x: shape.end.x, y: shape.end.y)
        let dx = shape.end.x - shape.start.x, dy = shape.end.y - shape.start.y
        let length = (dx * dx + dy * dy).squareRoot()

        if shape.kind == .arrow, length > 0 {
            let head = min(shape.arrowHeadLength, length)
            let unit = CGPoint(x: dx / length, y: dy / length)
            let tip = CGPoint(x: shape.end.x, y: shape.end.y)
            let base = CGPoint(x: tip.x - unit.x * head, y: tip.y - unit.y * head)
            let halfWidth = head * 0.45
            context.move(to: tip)
            context.addLine(to: CGPoint(x: base.x - unit.y * halfWidth, y: base.y + unit.x * halfWidth))
            context.addLine(to: CGPoint(x: base.x + unit.y * halfWidth, y: base.y - unit.x * halfWidth))
            context.closePath()
            context.fillPath()
            // Stop the shaft inside the head so its square end doesn't poke out of the point.
            lineEnd = CGPoint(x: base.x + unit.x * min(head / 2, shape.lineWidth), y: base.y + unit.y * min(head / 2, shape.lineWidth))
        }
        context.move(to: start)
        context.addLine(to: lineEnd)
        context.strokePath()
    }
}
