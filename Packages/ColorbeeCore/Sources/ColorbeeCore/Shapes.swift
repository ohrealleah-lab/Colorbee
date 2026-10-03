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
    public var outlineStyle: PaintStyle
    public var fillStyle: PaintStyle

    public init(
        kind: ShapeKind, start: Point2D, end: Point2D, points: [Point2D] = [], rotation: Double = 0,
        lineWidth: Double, outline: Pixel?, fill: Pixel?, outlineStyle: PaintStyle = .solid, fillStyle: PaintStyle = .solid
    ) {
        self.outlineStyle = outlineStyle
        self.fillStyle = fillStyle
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

    /// Where an arrow's shaft stops: inside the head, so its square end doesn't poke out of the point.
    var arrowShaftEnd: Point2D {
        let dx = end.x - start.x, dy = end.y - start.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else { return end }
        let head = min(arrowHeadLength, length)
        let back = head - min(head / 2, lineWidth)
        return Point2D(x: end.x - dx / length * back, y: end.y - dy / length * back)
    }

    /// Off draws only an arrow's head, which stays solid under a textured shaft.
    var drawsShaft = true

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
        let hasFill = shape.fill != nil && !shape.kind.isOpen
        guard !area.isEmpty, shape.outline != nil || hasFill else { return nil }
        let origin = IntPoint(x: area.minX, y: area.minY)
        if shape.outlineStyle == .solid, shape.fillStyle == .solid {
            return drawSolid(shape, fill: true, outline: true, area: area, colorSpace: colorSpace).map { ($0, origin) }
        }

        // Textured styles: the fill and the outline are made separately, then the outline goes on top.
        var result: PixelBuffer?
        if hasFill, let fill = shape.fill {
            result = shape.fillStyle == .solid
                ? drawSolid(shape, fill: true, outline: false, area: area, colorSpace: colorSpace)
                : texturedFill(shape, color: fill, area: area)
        }
        if let outline = shape.outline {
            let stroke = shape.outlineStyle == .solid
                ? drawSolid(shape, fill: false, outline: true, area: area, colorSpace: colorSpace)
                : texturedOutline(shape, color: outline, style: shape.outlineStyle, area: area, colorSpace: colorSpace)
            if let stroke {
                if let base = result {
                    for y in 0..<area.height {
                        let top = stroke.row(y), bottom = base.row(y)
                        for x in 0..<area.width where top[x].a > 0 {
                            bottom[x] = Compositing.over(bottom[x], top[x])
                        }
                    }
                } else {
                    result = stroke
                }
            }
        }
        return result.map { ($0, origin) }
    }

    /// Core Graphics drawing for solid fills and outlines.
    private static func drawSolid(_ shape: ShapeSpec, fill drawFill: Bool, outline drawOutline: Bool, area: IntRect, colorSpace: CGColorSpace) -> PixelBuffer? {
        let buffer = PixelBuffer(width: area.width, height: area.height)
        guard let context = imageContext(for: buffer, area: area, colorSpace: colorSpace) else { return nil }
        context.setLineWidth(shape.lineWidth)
        context.setLineJoin(.round)

        func cgColor(_ pixel: Pixel) -> CGColor {
            CGColor(colorSpace: colorSpace, components: [pixel.r, pixel.g, pixel.b, pixel.a].map { CGFloat($0) / 255 })!
        }

        if shape.kind.isLinear {
            if drawOutline { draw(line: shape, in: context, color: shape.outline.map(cgColor)) }
        } else if let path = shape.path {
            if drawFill, let fill = shape.fill, !shape.kind.isOpen {
                context.addPath(path)
                context.setFillColor(cgColor(fill))
                context.fillPath()
            }
            if drawOutline, let outline = shape.outline {
                context.addPath(path)
                context.setStrokeColor(cgColor(outline))
                context.strokePath()
            }
        }

        var image = buffer.vImageBuffer
        // BGRA keeps alpha last, which is all the RGBA8888 variant needs.
        vImageUnpremultiplyData_RGBA8888(&image, &image, vImage_Flags(kvImageNoFlags))
        return buffer
    }

    /// A context drawing into `buffer` in image coordinates: origin at the canvas's top-left, y down.
    private static func imageContext(for buffer: PixelBuffer, area: IntRect, colorSpace: CGColorSpace) -> CGContext? {
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(
            data: buffer.baseAddress, width: area.width, height: area.height, bitsPerComponent: 8,
            bytesPerRow: buffer.bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo
        ) else { return nil }
        context.translateBy(x: 0, y: CGFloat(area.height))
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: CGFloat(-area.minX), y: CGFloat(-area.minY))
        return context
    }

    /// The outline traced with the style's brush, one stroke per subpath. An arrow's head stays solid.
    private static func texturedOutline(_ shape: ShapeSpec, color: Pixel, style: PaintStyle, area: IntRect, colorSpace: CGColorSpace) -> PixelBuffer? {
        guard let brush = style.brush else { return nil }
        let scratch = Canvas(size: IntSize(width: area.width, height: area.height), colorSpace: colorSpace, background: .clear)
        let edit = Edit(name: "Shape", canvas: scratch)
        let offset = Point2D(x: Double(area.minX), y: Double(area.minY))

        var lines: [[Point2D]]
        if shape.kind.isLinear {
            lines = [[shape.start, shape.kind == .arrow ? shape.arrowShaftEnd : shape.end]]
        } else {
            lines = shape.path.map(flatten) ?? []
        }
        for line in lines where !line.isEmpty {
            // A fixed seed keeps the oil bristles from changing every time the preview redraws.
            let stroke = brush.makeStroke(diameter: shape.lineWidth, color: color, layer: scratch.activeLayer, edit: edit, seed: 1)
            for point in line { stroke.move(to: Point2D(x: point.x - offset.x, y: point.y - offset.y)) }
            stroke.finish()
        }
        let buffer = scratch.activeLayer.buffer
        if shape.kind == .arrow, let head = drawSolid(arrowHeadOnly(shape), fill: false, outline: true, area: area, colorSpace: colorSpace) {
            for y in 0..<area.height {
                let top = head.row(y), bottom = buffer.row(y)
                for x in 0..<area.width where top[x].a > 0 { bottom[x] = Compositing.over(bottom[x], top[x]) }
            }
        }
        return buffer
    }

    /// The arrow with its shaft shortened to nothing, so only the head is drawn.
    private static func arrowHeadOnly(_ shape: ShapeSpec) -> ShapeSpec {
        var head = shape
        head.outlineStyle = .solid
        head.drawsShaft = false
        return head
    }

    /// The fill area with the style's texture applied.
    private static func texturedFill(_ shape: ShapeSpec, color: Pixel, area: IntRect) -> PixelBuffer? {
        guard let path = shape.path else { return nil }
        let width = area.width, height = area.height
        var mask = [UInt8](repeating: 0, count: width * height)
        let drawn = mask.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.translateBy(x: CGFloat(-area.minX), y: CGFloat(-area.minY))
            context.addPath(path)
            context.setFillColor(gray: 1, alpha: 1)
            context.fillPath()
            return true
        }
        guard drawn else { return nil }
        // Watercolor pools at the edges: a blurred copy of the mask says how far inside each pixel is.
        let interior = shape.fillStyle == .watercolor ? blurred(mask, width: width, height: height, radius: max(3, min(width, height) / 12)) : mask

        let buffer = PixelBuffer(width: width, height: height)
        for y in 0..<height {
            let row = buffer.row(y)
            for x in 0..<width {
                let index = y * width + x
                guard mask[index] > 0 else { continue }
                let amount = shape.fillStyle.fillAmount(
                    x: x + area.minX, y: y + area.minY,
                    mask: Double(mask[index]) / 255, interior: Double(interior[index]) / 255
                )
                guard amount > 0 else { continue }
                var pixel = color
                pixel.a = UInt8((Double(color.a) * min(1, amount)).rounded())
                row[x] = pixel
            }
        }
        return buffer
    }

    private static func blurred(_ plane: [UInt8], width: Int, height: Int, radius: Int) -> [UInt8] {
        var source = plane, result = plane
        let kernel = UInt32(radius * 2 + 1)
        source.withUnsafeMutableBytes { input in
            result.withUnsafeMutableBytes { output in
                var from = vImage_Buffer(data: input.baseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: width)
                var to = vImage_Buffer(data: output.baseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: width)
                // Two box passes approximate a Gaussian; outside the shape counts as empty.
                vImageBoxConvolve_Planar8(&from, &to, nil, 0, 0, kernel, kernel, 0, vImage_Flags(kvImageBackgroundColorFill))
                vImageBoxConvolve_Planar8(&to, &from, nil, 0, 0, kernel, kernel, 0, vImage_Flags(kvImageBackgroundColorFill))
            }
        }
        return source
    }

    /// The path as polylines, one per subpath, with curves split into short straight pieces.
    static func flatten(_ path: CGPath) -> [[Point2D]] {
        var lines: [[Point2D]] = []
        var current: [Point2D] = []
        var start = CGPoint.zero, last = CGPoint.zero
        func add(_ point: CGPoint) {
            current.append(Point2D(x: point.x, y: point.y))
            last = point
        }
        func steps(_ points: [CGPoint]) -> Int {
            var length = 0.0
            for (a, b) in zip(points, points.dropFirst()) { length += hypot(b.x - a.x, b.y - a.y) }
            return max(4, Int(length / 2))
        }
        path.applyWithBlock { element in
            let e = element.pointee
            switch e.type {
            case .moveToPoint:
                if current.count > 1 { lines.append(current) }
                current = []
                start = e.points[0]
                add(start)
            case .addLineToPoint:
                add(e.points[0])
            case .addQuadCurveToPoint:
                let from = last, control = e.points[0], to = e.points[1]
                let count = steps([from, control, to])
                for step in 1...count {
                    let t = CGFloat(step) / CGFloat(count), u = 1 - t
                    add(CGPoint(x: u * u * from.x + 2 * u * t * control.x + t * t * to.x,
                                y: u * u * from.y + 2 * u * t * control.y + t * t * to.y))
                }
            case .addCurveToPoint:
                let from = last, c1 = e.points[0], c2 = e.points[1], to = e.points[2]
                let count = steps([from, c1, c2, to])
                for step in 1...count {
                    let t = CGFloat(step) / CGFloat(count), u = 1 - t
                    let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
                    add(CGPoint(x: a * from.x + b * c1.x + c * c2.x + d * to.x,
                                y: a * from.y + b * c1.y + c * c2.y + d * to.y))
                }
            case .closeSubpath:
                add(start)
            @unknown default:
                break
            }
        }
        if current.count > 1 { lines.append(current) }
        return lines
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
            lineEnd = CGPoint(x: shape.arrowShaftEnd.x, y: shape.arrowShaftEnd.y)
        }
        guard shape.drawsShaft else { return }
        context.move(to: start)
        context.addLine(to: lineEnd)
        context.strokePath()
    }
}
