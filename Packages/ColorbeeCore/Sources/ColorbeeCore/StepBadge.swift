import Accelerate
import CoreGraphics
import CoreText
import Foundation

/// A numbered circle for how-to screenshots (FR-5.3): filled with one color, with a thin outline and a bold number
/// in the other (Leah, 2026-10-10), and an arrow from the circle to `arrowTip` when one was dragged out.
public struct StepBadgeSpec: Equatable, Sendable {
    public var label: String
    public var center: Point2D
    public var diameter: Double
    /// The circle and the arrow.
    public var fill: Pixel
    /// The number and the outline.
    public var ink: Pixel
    public var arrowTip: Point2D?

    public init(label: String, center: Point2D, diameter: Double, fill: Pixel, ink: Pixel, arrowTip: Point2D? = nil) {
        self.label = label
        self.center = center
        self.diameter = diameter
        self.fill = fill
        self.ink = ink
        self.arrowTip = arrowTip
    }

    var radius: Double { diameter / 2 }
    var outlineWidth: Double { max(1, diameter / 16) }
    var arrowWidth: Double { max(2, diameter / 8) }
    var arrowHeadLength: Double { arrowWidth * 3 }

    /// Whether `point` is on the circle, for moving a badge before it's placed.
    public func contains(_ point: Point2D) -> Bool {
        let dx = point.x - center.x, dy = point.y - center.y
        return (dx * dx + dy * dy).squareRoot() <= radius + outlineWidth
    }

    /// The arrow only shows once its tip is clear of the circle.
    public var showsArrow: Bool {
        guard let arrowTip else { return false }
        let dx = arrowTip.x - center.x, dy = arrowTip.y - center.y
        return (dx * dx + dy * dy).squareRoot() > radius + arrowHeadLength
    }

    public mutating func translate(by dx: Double, _ dy: Double) {
        center = Point2D(x: center.x + dx, y: center.y + dy)
        arrowTip = arrowTip.map { Point2D(x: $0.x + dx, y: $0.y + dy) }
    }
}

public enum BadgeStyle: String, CaseIterable, Codable, Sendable {
    case numbers, letters
}

public enum StepBadge {
    /// 1, 2, 3… or A, B, … Z, AA, AB… (the column-name way, so every number has a label).
    public static func label(for value: Int, style: BadgeStyle) -> String {
        let value = max(1, value)
        guard style == .letters else { return String(value) }
        var remaining = value, label = ""
        while remaining > 0 {
            remaining -= 1
            label = String(UnicodeScalar(UInt8(65 + remaining % 26))) + label
            remaining /= 26
        }
        return label
    }

    /// The value a label stands for: "12", or "C" and "AA" for letters. Nil if it isn't one.
    public static func value(of label: String, style: BadgeStyle) -> Int? {
        let trimmed = label.trimmingCharacters(in: .whitespaces).uppercased()
        guard !trimmed.isEmpty else { return nil }
        if style == .numbers || trimmed.allSatisfy(\.isNumber) {
            return Int(trimmed).flatMap { $0 >= 1 && $0 <= 99_999 ? $0 : nil }
        }
        guard trimmed.count <= 3, trimmed.allSatisfy({ $0 >= "A" && $0 <= "Z" }) else { return nil }
        return trimmed.unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 64 }
    }

    /// The badge drawn into pixels, with where its top-left goes; nil if none of it is on the canvas.
    public static func render(_ spec: StepBadgeSpec, colorSpace: CGColorSpace, clippedTo canvasBounds: IntRect) -> (pixels: PixelBuffer, origin: IntPoint)? {
        var minX = spec.center.x - spec.radius, maxX = spec.center.x + spec.radius
        var minY = spec.center.y - spec.radius, maxY = spec.center.y + spec.radius
        if spec.showsArrow, let tip = spec.arrowTip {
            minX = min(minX, tip.x); maxX = max(maxX, tip.x)
            minY = min(minY, tip.y); maxY = max(maxY, tip.y)
        }
        let margin = spec.arrowHeadLength + spec.outlineWidth + 2
        let area = IntRect(enclosingMinX: minX - margin, minY: minY - margin, maxX: maxX + margin, maxY: maxY + margin).intersection(canvasBounds)
        guard !area.isEmpty else { return nil }
        let buffer = PixelBuffer(width: area.width, height: area.height)
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(data: buffer.baseAddress, width: area.width, height: area.height, bitsPerComponent: 8,
                                      bytesPerRow: buffer.bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo) else { return nil }
        // Image coordinates: origin at the canvas's top-left, y down.
        context.translateBy(x: 0, y: CGFloat(area.height))
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: CGFloat(-area.minX), y: CGFloat(-area.minY))
        func color(_ pixel: Pixel) -> CGColor {
            CGColor(colorSpace: colorSpace, components: [pixel.r, pixel.g, pixel.b, pixel.a].map { CGFloat($0) / 255 })!
        }

        if spec.showsArrow, let tip = spec.arrowTip { drawArrow(spec, to: tip, in: context, color: color(spec.fill)) }

        let circle = CGRect(x: spec.center.x - spec.radius, y: spec.center.y - spec.radius, width: spec.diameter, height: spec.diameter)
        context.setFillColor(color(spec.fill))
        context.fillEllipse(in: circle)
        context.setStrokeColor(color(spec.ink))
        context.setLineWidth(spec.outlineWidth)
        context.strokeEllipse(in: circle.insetBy(dx: spec.outlineWidth / 2, dy: spec.outlineWidth / 2))
        drawLabel(spec, in: context, color: color(spec.ink))

        var image = buffer.vImageBuffer
        vImageUnpremultiplyData_RGBA8888(&image, &image, vImage_Flags(kvImageNoFlags))
        return (buffer, IntPoint(x: area.minX, y: area.minY))
    }

    /// A line from the circle's edge to just short of the tip, and a solid head at the tip.
    private static func drawArrow(_ spec: StepBadgeSpec, to tip: Point2D, in context: CGContext, color: CGColor) {
        let dx = tip.x - spec.center.x, dy = tip.y - spec.center.y
        let length = (dx * dx + dy * dy).squareRoot()
        let ux = dx / length, uy = dy / length
        let headBase = Point2D(x: tip.x - ux * spec.arrowHeadLength, y: tip.y - uy * spec.arrowHeadLength)
        context.setStrokeColor(color)
        context.setLineWidth(spec.arrowWidth)
        context.setLineCap(.butt)
        context.move(to: CGPoint(x: spec.center.x + ux * spec.radius * 0.9, y: spec.center.y + uy * spec.radius * 0.9))
        context.addLine(to: CGPoint(x: headBase.x + ux, y: headBase.y + uy))
        context.strokePath()
        let halfWidth = spec.arrowWidth * 1.5
        context.setFillColor(color)
        context.move(to: CGPoint(x: tip.x, y: tip.y))
        context.addLine(to: CGPoint(x: headBase.x - uy * halfWidth, y: headBase.y + ux * halfWidth))
        context.addLine(to: CGPoint(x: headBase.x + uy * halfWidth, y: headBase.y - ux * halfWidth))
        context.closePath()
        context.fillPath()
    }

    /// The label, centered, smaller for longer labels so it stays inside the circle.
    private static func drawLabel(_ spec: StepBadgeSpec, in context: CGContext, color: CGColor) {
        let scale = spec.label.count <= 1 ? 0.6 : spec.label.count == 2 ? 0.5 : spec.label.count == 3 ? 0.38 : 0.3
        guard let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, spec.diameter * scale, nil) else { return }
        let attributes: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color]
        let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, spec.label as CFString, attributes as CFDictionary))
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        context.saveGState()
        // Text draws y up, so flip back around the center for it.
        context.translateBy(x: spec.center.x, y: spec.center.y)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = CGPoint(x: -bounds.midX, y: -bounds.midY)
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
