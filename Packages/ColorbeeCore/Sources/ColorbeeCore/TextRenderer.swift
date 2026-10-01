import Accelerate
import CoreGraphics
import CoreText
import Foundation

public enum TextAlignment: CaseIterable, Sendable {
    case left
    case center
    case right
}

/// Text to draw into the image. Sizes and positions are in image pixels.
public struct TextSpec: Equatable, Sendable {
    public var text: String
    /// Top-left corner of the text box.
    public var origin: Point2D
    /// Wrap lines at this width; nil lets lines run as long as they need.
    public var wrapWidth: Double?
    /// The box is at least this tall (a dragged-out text box); it grows if the text needs more.
    public var minimumHeight: Double = 0
    public var fontFamily: String
    public var fontSize: Double
    public var bold = false
    public var italic = false
    public var underline = false
    public var strikethrough = false
    public var alignment: TextAlignment = .left
    public var color: Pixel
    /// Opaque background mode fills the box with this color; nil is transparent (FR-6.1).
    public var background: Pixel?

    public init(text: String, origin: Point2D, wrapWidth: Double? = nil, fontFamily: String, fontSize: Double, color: Pixel, background: Pixel? = nil) {
        self.text = text
        self.origin = origin
        self.wrapWidth = wrapWidth
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.color = color
        self.background = background
    }
}

public enum TextRenderer {
    /// The box the text occupies, in image coordinates.
    public static func box(for spec: TextSpec) -> IntRect {
        let size = layoutSize(of: spec, colorSpace: nil)
        return IntRect(enclosingMinX: spec.origin.x, minY: spec.origin.y, maxX: spec.origin.x + size.width, maxY: spec.origin.y + size.height)
    }

    /// Draws the text (and background, if any) into a straight-alpha buffer. Nil when there's nothing to draw.
    public static func render(_ spec: TextSpec, colorSpace: CGColorSpace, clippedTo canvasBounds: IntRect) -> (pixels: PixelBuffer, origin: IntPoint)? {
        guard !spec.text.isEmpty else { return nil }
        let size = layoutSize(of: spec, colorSpace: colorSpace)
        let box = CGRect(x: spec.origin.x, y: spec.origin.y, width: size.width, height: size.height)
        let area = IntRect(enclosingMinX: box.minX, minY: box.minY, maxX: box.maxX, maxY: box.maxY).intersection(canvasBounds)
        guard !area.isEmpty else { return nil }

        let buffer = PixelBuffer(width: area.width, height: area.height)
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(
            data: buffer.baseAddress, width: area.width, height: area.height, bitsPerComponent: 8,
            bytesPerRow: buffer.bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo
        ) else { return nil }

        // Core Text draws with y up, so map the box into the buffer's y-up space instead of flipping.
        let frameRect = CGRect(
            x: box.minX - CGFloat(area.minX),
            y: CGFloat(area.maxY) - box.maxY,
            width: box.width,
            height: box.height
        )
        if let background = spec.background {
            context.setFillColor(cgColor(background, colorSpace))
            context.fill(frameRect)
        }

        let framesetter = CTFramesetterCreateWithAttributedString(attributedString(for: spec, colorSpace: colorSpace))
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), CGPath(rect: frameRect, transform: nil), nil)
        CTFrameDraw(frame, context)
        if spec.strikethrough {
            drawStrikethrough(frame, in: frameRect, spec: spec, context: context, colorSpace: colorSpace)
        }

        var image = buffer.vImageBuffer
        vImageUnpremultiplyData_RGBA8888(&image, &image, vImage_Flags(kvImageNoFlags))
        return (buffer, IntPoint(x: area.minX, y: area.minY))
    }

    /// The font Colorbee uses for a spec, so the on-screen editor can match the rendered result.
    public static func font(for spec: TextSpec) -> CTFont {
        var traits: CTFontSymbolicTraits = []
        if spec.bold { traits.insert(.traitBold) }
        if spec.italic { traits.insert(.traitItalic) }
        let attributes: [CFString: Any] = [
            kCTFontFamilyNameAttribute: spec.fontFamily,
            kCTFontTraitsAttribute: [kCTFontSymbolicTrait: traits.rawValue],
        ]
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, spec.fontSize, nil)
    }

    private static func layoutSize(of spec: TextSpec, colorSpace: CGColorSpace?) -> Size2D {
        let space = colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let text = spec.text.isEmpty ? " " : spec.text
        var measured = spec
        measured.text = text
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString(for: measured, colorSpace: space))
        let constraint = CGSize(width: spec.wrapWidth ?? .greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(location: 0, length: 0), nil, constraint, nil)
        // A pixel of slack keeps the last character from wrapping on rounding.
        let width = spec.wrapWidth ?? (suggested.width.rounded(.up) + 1)
        return Size2D(width: max(1, width), height: max(1, suggested.height.rounded(.up), spec.minimumHeight.rounded(.up)))
    }

    private static func attributedString(for spec: TextSpec, colorSpace: CGColorSpace) -> CFAttributedString {
        var alignment: CTTextAlignment = switch spec.alignment {
        case .left: .left
        case .center: .center
        case .right: .right
        }
        let paragraph = withUnsafeMutablePointer(to: &alignment) { pointer in
            var setting = CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: pointer)
            return CTParagraphStyleCreate(&setting, 1)
        }
        var attributes: [CFString: Any] = [
            kCTFontAttributeName: font(for: spec),
            kCTForegroundColorAttributeName: cgColor(spec.color, colorSpace),
            kCTParagraphStyleAttributeName: paragraph,
        ]
        if spec.underline {
            attributes[kCTUnderlineStyleAttributeName] = CTUnderlineStyle.single.rawValue
        }
        return CFAttributedStringCreate(nil, spec.text as CFString, attributes as CFDictionary)
    }

    private static func drawStrikethrough(_ frame: CTFrame, in rect: CGRect, spec: TextSpec, context: CGContext, colorSpace: CGColorSpace) {
        let lines = CTFrameGetLines(frame) as? [CTLine] ?? []
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        let thickness = max(1, spec.fontSize / 15)
        let xHeight = CTFontGetXHeight(font(for: spec))
        context.setFillColor(cgColor(spec.color, colorSpace))
        for (line, origin) in zip(lines, origins) {
            let width = CTLineGetTypographicBounds(line, nil, nil, nil) - CTLineGetTrailingWhitespaceWidth(line)
            guard width > 0 else { continue }
            let range = CTLineGetStringRange(line)
            let startX = CTLineGetOffsetForStringIndex(line, range.location, nil)
            context.fill(CGRect(
                x: rect.minX + origin.x + startX,
                y: rect.minY + origin.y + xHeight / 2 - thickness / 2,
                width: width,
                height: thickness
            ))
        }
    }

    private static func cgColor(_ pixel: Pixel, _ colorSpace: CGColorSpace) -> CGColor {
        CGColor(colorSpace: colorSpace, components: [pixel.r, pixel.g, pixel.b, pixel.a].map { CGFloat($0) / 255 })!
    }
}
