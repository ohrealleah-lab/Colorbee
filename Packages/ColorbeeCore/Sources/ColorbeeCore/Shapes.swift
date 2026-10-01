import Accelerate
import CoreGraphics
import Foundation

/// The shapes gallery (FR-5.1), plus Arrow, a line with an arrowhead for annotations.
public enum ShapeKind: CaseIterable, Sendable {
    case line
    case arrow
    case curve
    case rectangle
    case roundedRectangle
    case ellipse
    case triangle
    case rightTriangle
    case diamond
    case pentagon
    case hexagon
    case rightArrow
    case leftArrow
    case upArrow
    case downArrow
    case star4
    case star5
    case star6
    case roundedRectangleCallout
    case ovalCallout
    case cloudCallout
    case heart
    case lightning
    case polygon

    /// Lines and arrows are defined by two end points.
    public var isLinear: Bool { self == .line || self == .arrow }
    /// Polygons and curves are defined by a list of points placed one at a time.
    public var isPointBased: Bool { self == .polygon || self == .curve }
    /// Box shapes: everything drawn inside a dragged rectangle. Only these rotate.
    public var isBoxShape: Bool { !isLinear && !isPointBased }
    /// Open shapes have no inside to fill.
    public var isOpen: Bool { isLinear || self == .curve }

    public var name: String {
        switch self {
        case .line: "Line"
        case .arrow: "Arrow"
        case .curve: "Curve"
        case .rectangle: "Rectangle"
        case .roundedRectangle: "Rounded Rectangle"
        case .ellipse: "Ellipse"
        case .triangle: "Triangle"
        case .rightTriangle: "Right Triangle"
        case .diamond: "Diamond"
        case .pentagon: "Pentagon"
        case .hexagon: "Hexagon"
        case .rightArrow: "Right Arrow"
        case .leftArrow: "Left Arrow"
        case .upArrow: "Up Arrow"
        case .downArrow: "Down Arrow"
        case .star4: "4-Point Star"
        case .star5: "5-Point Star"
        case .star6: "6-Point Star"
        case .roundedRectangleCallout: "Rounded Rectangle Callout"
        case .ovalCallout: "Oval Callout"
        case .cloudCallout: "Cloud Callout"
        case .heart: "Heart"
        case .lightning: "Lightning"
        case .polygon: "Polygon"
        }
    }
}

/// A shape ready to draw. Coordinates are in image pixels.
public struct ShapeSpec: Equatable, Sendable {
    public var kind: ShapeKind
    /// Line end points, or opposite corners of the (unrotated) bounding box.
    public var start: Point2D
    public var end: Point2D
    /// Polygon vertices, or a curve's start, two control points and end.
    public var points: [Point2D]
    /// Box shapes only: radians clockwise around the box's center.
    public var rotation: Double
    public var lineWidth: Double
    /// Nil draws no outline.
    public var outline: Pixel?
    /// Nil draws no fill. Ignored for open shapes.
    public var fill: Pixel?

    public init(
        kind: ShapeKind, start: Point2D, end: Point2D, points: [Point2D] = [], rotation: Double = 0,
        lineWidth: Double, outline: Pixel?, fill: Pixel?
    ) {
        self.kind = kind
        self.start = start
        self.end = end
        self.points = points
        self.rotation = rotation
        self.lineWidth = max(1, lineWidth)
        self.outline = outline
        self.fill = fill
    }

    /// The dragged box, for box shapes, before rotation.
    public var box: IntRect {
        IntRect(
            enclosingMinX: min(start.x, end.x), minY: min(start.y, end.y),
            maxX: max(start.x, end.x), maxY: max(start.y, end.y)
        )
    }

    public var boxCenter: Point2D {
        Point2D(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
    }

    /// Turns a point in the shape's unrotated frame into image coordinates.
    public func rotated(_ point: Point2D) -> Point2D {
        guard rotation != 0 else { return point }
        let center = boxCenter
        let dx = point.x - center.x, dy = point.y - center.y
        return Point2D(x: center.x + dx * cos(rotation) - dy * sin(rotation), y: center.y + dx * sin(rotation) + dy * cos(rotation))
    }

    /// Turns an image point into the shape's unrotated frame.
    public func unrotated(_ point: Point2D) -> Point2D {
        guard rotation != 0 else { return point }
        let center = boxCenter
        let dx = point.x - center.x, dy = point.y - center.y
        return Point2D(x: center.x + dx * cos(rotation) + dy * sin(rotation), y: center.y - dx * sin(rotation) + dy * cos(rotation))
    }

    var arrowHeadLength: Double { max(10, lineWidth * 4) }

    /// Everything the shape can paint, including stroke width, arrow head and anti-aliasing.
    public var paintedBounds: IntRect {
        let margin = (kind == .arrow ? arrowHeadLength : lineWidth) + 2
        let corners: [Point2D]
        if kind.isPointBased {
            corners = points.isEmpty ? [start, end] : points
        } else if kind.isBoxShape {
            let minX = min(start.x, end.x), maxX = max(start.x, end.x), minY = min(start.y, end.y), maxY = max(start.y, end.y)
            corners = [Point2D(x: minX, y: minY), Point2D(x: maxX, y: minY), Point2D(x: maxX, y: maxY), Point2D(x: minX, y: maxY)].map(rotated)
        } else {
            corners = [start, end]
        }
        let xs = corners.map(\.x), ys = corners.map(\.y)
        return IntRect(enclosingMinX: xs.min()! - margin, minY: ys.min()! - margin, maxX: xs.max()! + margin, maxY: ys.max()! + margin)
    }

    /// Snaps the end point: squares and circles for box shapes, 45° steps for lines (FR-5.1).
    public func constrained() -> ShapeSpec {
        var result = self
        let dx = end.x - start.x, dy = end.y - start.y
        if kind.isLinear {
            let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
            let length = (dx * dx + dy * dy).squareRoot()
            result.end = Point2D(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length)
        } else if kind.isBoxShape {
            let side = max(abs(dx), abs(dy))
            result.end = Point2D(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
        }
        return result
    }

    /// The outline as a path in image coordinates (rotation applied). Nil for lines and arrows.
    public var path: CGPath? {
        switch kind {
        case .line, .arrow:
            return nil
        case .polygon:
            guard points.count >= 2 else { return nil }
            let path = CGMutablePath()
            path.addLines(between: points.map { CGPoint(x: $0.x, y: $0.y) })
            path.closeSubpath()
            return path
        case .curve:
            guard points.count == 4 else { return nil }
            let path = CGMutablePath()
            let cg = points.map { CGPoint(x: $0.x, y: $0.y) }
            path.move(to: cg[0])
            path.addCurve(to: cg[3], control1: cg[1], control2: cg[2])
            return path
        default:
            let box = CGRect(
                x: min(start.x, end.x), y: min(start.y, end.y),
                width: abs(end.x - start.x), height: abs(end.y - start.y)
            )
            // Inset so the outline stays inside the dragged box.
            let inset = outline == nil ? 0 : min(lineWidth / 2, min(box.width, box.height) / 2)
            let shape = ShapePaths.path(kind, in: box.insetBy(dx: inset, dy: inset))
            guard rotation != 0 else { return shape }
            let center = CGPoint(x: box.midX, y: box.midY)
            var transform = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: rotation).translatedBy(x: -center.x, y: -center.y)
            return shape.copy(using: &transform)
        }
    }
}

/// Unit outlines for the box shapes, scaled into a rect.
enum ShapePaths {
    static func path(_ kind: ShapeKind, in rect: CGRect) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        func polygon(_ points: [(CGFloat, CGFloat)]) -> CGPath {
            let path = CGMutablePath()
            path.addLines(between: points.map { point($0.0, $0.1) })
            path.closeSubpath()
            return path
        }
        func regular(_ sides: Int) -> CGPath {
            polygon((0..<sides).map { index in
                let angle = -CGFloat.pi / 2 + CGFloat(index) * 2 * .pi / CGFloat(sides)
                return (0.5 + 0.5 * cos(angle), 0.5 + 0.5 * sin(angle))
            })
        }
        func star(_ tips: Int, inner: CGFloat) -> CGPath {
            polygon((0..<(tips * 2)).map { index in
                let angle = -CGFloat.pi / 2 + CGFloat(index) * .pi / CGFloat(tips)
                let radius = index % 2 == 0 ? 0.5 : inner
                return (0.5 + radius * cos(angle), 0.5 + radius * sin(angle))
            })
        }
        let rightArrow: [(CGFloat, CGFloat)] = [(0, 0.25), (0.6, 0.25), (0.6, 0), (1, 0.5), (0.6, 1), (0.6, 0.75), (0, 0.75)]
        /// A speech bubble: the body in the top 80% with a tail pointing down-left.
        func callout(body: CGPath) -> CGPath {
            let tail = polygon([(0.2, 0.7), (0.4, 0.75), (0.12, 1)])
            return body.union(tail)
        }

        switch kind {
        case .ellipse:
            return CGPath(ellipseIn: rect, transform: nil)
        case .roundedRectangle:
            let radius = min(rect.width, rect.height) * 0.2
            return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        case .triangle:
            return polygon([(0.5, 0), (1, 1), (0, 1)])
        case .rightTriangle:
            return polygon([(0, 0), (1, 1), (0, 1)])
        case .diamond:
            return polygon([(0.5, 0), (1, 0.5), (0.5, 1), (0, 0.5)])
        case .pentagon:
            return regular(5)
        case .hexagon:
            return polygon([(0.25, 0), (0.75, 0), (1, 0.5), (0.75, 1), (0.25, 1), (0, 0.5)])
        case .rightArrow:
            return polygon(rightArrow)
        case .leftArrow:
            return polygon(rightArrow.map { (1 - $0.0, $0.1) })
        case .downArrow:
            return polygon(rightArrow.map { ($0.1, $0.0) })
        case .upArrow:
            return polygon(rightArrow.map { ($0.1, 1 - $0.0) })
        case .star4:
            return star(4, inner: 0.18)
        case .star5:
            return star(5, inner: 0.2)
        case .star6:
            return star(6, inner: 0.28)
        case .roundedRectangleCallout:
            let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.8)
            let radius = min(body.width, body.height) * 0.2
            return callout(body: CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil))
        case .ovalCallout:
            return callout(body: CGPath(ellipseIn: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.8), transform: nil))
        case .cloudCallout:
            // Overlapping puffs around an oval, merged into one outline, plus two small thought bubbles.
            var cloud: CGPath = CGPath(ellipseIn: CGRect(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.12,
                                                         width: rect.width * 0.76, height: rect.height * 0.5), transform: nil)
            for index in 0..<9 {
                let angle = CGFloat(index) * 2 * .pi / 9
                let center = point(0.5 + 0.38 * cos(angle), 0.37 + 0.27 * sin(angle))
                let puff = CGRect(x: center.x - rect.width * 0.14, y: center.y - rect.height * 0.12, width: rect.width * 0.28, height: rect.height * 0.24)
                cloud = cloud.union(CGPath(ellipseIn: puff, transform: nil))
            }
            let bubbles = CGMutablePath()
            bubbles.addPath(cloud)
            bubbles.addEllipse(in: CGRect(origin: point(0.2, 0.8), size: CGSize(width: rect.width * 0.08, height: rect.height * 0.08)))
            bubbles.addEllipse(in: CGRect(origin: point(0.1, 0.93), size: CGSize(width: rect.width * 0.05, height: rect.height * 0.05)))
            return bubbles
        case .heart:
            let path = CGMutablePath()
            path.move(to: point(0.5, 1))
            path.addCurve(to: point(0, 0.3), control1: point(0.2, 0.8), control2: point(0, 0.6))
            path.addCurve(to: point(0.5, 0.18), control1: point(0, 0.02), control2: point(0.4, -0.02))
            path.addCurve(to: point(1, 0.3), control1: point(0.6, -0.02), control2: point(1, 0.02))
            path.addCurve(to: point(0.5, 1), control1: point(1, 0.6), control2: point(0.8, 0.8))
            path.closeSubpath()
            return path
        case .lightning:
            return polygon([(0.4, 0), (0.78, 0), (0.56, 0.38), (0.86, 0.38), (0.24, 1), (0.42, 0.54), (0.14, 0.54)])
        default:
            return CGPath(rect: rect, transform: nil)
        }
    }
}

public enum ShapeRenderer {
    /// Draws the shape into a straight-alpha buffer covering its painted area within `canvasBounds`.
    /// Returns nil when nothing would be visible.
    public static func render(_ shape: ShapeSpec, colorSpace: CGColorSpace, clippedTo canvasBounds: IntRect) -> (pixels: PixelBuffer, origin: IntPoint)? {
        let area = shape.paintedBounds.intersection(canvasBounds)
        guard !area.isEmpty, shape.outline != nil || (shape.fill != nil && !shape.kind.isOpen) else { return nil }
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
        context.setLineJoin(.round)

        func cgColor(_ pixel: Pixel) -> CGColor {
            CGColor(colorSpace: colorSpace, components: [pixel.r, pixel.g, pixel.b, pixel.a].map { CGFloat($0) / 255 })!
        }

        if shape.kind.isLinear {
            draw(line: shape, in: context, color: shape.outline.map(cgColor))
        } else if let path = shape.path {
            if let fill = shape.fill, !shape.kind.isOpen {
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
