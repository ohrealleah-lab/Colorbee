import Accelerate
import CoreGraphics
import CoreText
import Foundation

/// The arc curved text bends along (FR-6.4), in the text box's own coordinates: x across from its left edge, y down from
/// its top. Every line bends around one centre, nested like rainbow bands, and keeps its letter spacing: a point's
/// distance along its line becomes the same distance along its own circle.
struct TextArc {
    /// The box's width and height, straight.
    let width: Double
    let height: Double
    /// A smile (+) has its centre above the text; a frown (−) below.
    let smiles: Bool
    /// The radius at the box's middle height.
    let radius: Double

    /// Nil for straight text. At ±100 the middle line makes half a circle (Leah, 2026-11-21).
    init?(_ spec: TextSpec) {
        guard abs(spec.curve) >= 0.5 else { return nil }
        let size = TextRenderer.layoutSize(of: spec, colorSpace: nil)
        width = size.width
        height = size.height
        smiles = spec.curve > 0
        let angle = Double.pi * abs(spec.curve) / 100
        // Never so tight that the innermost line turns inside out.
        radius = max(width / angle, height + spec.fontSize)
    }

    private var centre: Point2D {
        Point2D(x: width / 2, y: smiles ? height / 2 - radius : height / 2 + radius)
    }

    /// The radius of the circle that a point `y` down the box lies on.
    func radius(at y: Double) -> Double {
        smiles ? radius + y - height / 2 : radius + height / 2 - y
    }

    /// The angle a point `x` across sits at on a circle of `radius`, clockwise from the middle of the arc.
    func angle(at x: Double, radius: Double) -> Double {
        (x - width / 2) / radius * (smiles ? -1 : 1)
    }

    /// Where a point of the straight box goes. `angleRadius` is the circle its distance across is measured on: a
    /// letter's whole shape uses its baseline's, so it turns rigidly.
    func place(x: Double, y: Double, angleRadius: Double? = nil) -> Point2D {
        let r = radius(at: y)
        let turn = angle(at: x, radius: angleRadius ?? r)
        // A frown's letters stand outward from a centre below; a smile's lean in toward a centre above.
        return smiles
            ? Point2D(x: centre.x - r * sin(turn), y: centre.y + r * cos(turn))
            : Point2D(x: centre.x + r * sin(turn), y: centre.y - r * cos(turn))
    }

    /// Points along the straight segment from `start` to `end`, each placed on the arc, about two pixels apart.
    func placedPath(from start: Point2D, to end: Point2D, angleRadius: Double? = nil) -> [Point2D] {
        let length = max(abs(end.x - start.x), abs(end.y - start.y))
        let count = max(2, Int((length / 2).rounded(.up)) + 1)
        return (0..<count).map { index in
            let t = Double(index) / Double(count - 1)
            return place(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t, angleRadius: angleRadius)
        }
    }

    /// The straight box's outline, bent: the shape an opaque background fills.
    var band: [Point2D] {
        placedPath(from: Point2D(x: 0, y: 0), to: Point2D(x: width, y: 0))
            + placedPath(from: Point2D(x: width, y: 0), to: Point2D(x: width, y: height))
            + placedPath(from: Point2D(x: width, y: height), to: Point2D(x: 0, y: height))
            + placedPath(from: Point2D(x: 0, y: height), to: Point2D(x: 0, y: 0))
    }
}

extension TextRenderer {
    /// One glyph of curved text: where its baseline's middle lands, in the box's coordinates, and how far it turns
    /// clockwise.
    private struct PlacedGlyph {
        let glyph: CGGlyph
        let font: CTFont
        let advance: Double
        let position: Point2D
        let turn: Double
    }

    /// One line's span along its baseline, for its underline and strikethrough.
    private struct LineSpan {
        let startX: Double
        let endX: Double
        let baseline: Double
    }

    /// The straight layout's lines, cut into glyphs and placed on the arc.
    private static func curvedLayout(of spec: TextSpec, arc: TextArc, colorSpace: CGColorSpace) -> (glyphs: [PlacedGlyph], lines: [LineSpan]) {
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString(for: spec, colorSpace: colorSpace))
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: arc.width, height: arc.height), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        let lines = CTFrameGetLines(frame) as? [CTLine] ?? []
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        var glyphs: [PlacedGlyph] = []
        var spans: [LineSpan] = []
        for (line, origin) in zip(lines, origins) {
            // Core Text's origins are y up from the box's bottom.
            let baseline = arc.height - origin.y
            let baselineRadius = arc.radius(at: baseline)
            for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
                let count = CTRunGetGlyphCount(run)
                guard count > 0 else { continue }
                var runGlyphs = [CGGlyph](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                var advances = [CGSize](repeating: .zero, count: count)
                CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &runGlyphs)
                CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
                CTRunGetAdvances(run, CFRange(location: 0, length: 0), &advances)
                let attributes = CTRunGetAttributes(run) as? [CFString: Any] ?? [:]
                let runFont = attributes[kCTFontAttributeName].map { $0 as! CTFont } ?? font(for: spec)
                for index in 0..<count {
                    let advance = advances[index].width
                    let middle = origin.x + positions[index].x + advance / 2
                    glyphs.append(PlacedGlyph(glyph: runGlyphs[index], font: runFont, advance: advance,
                                              position: arc.place(x: middle, y: baseline, angleRadius: baselineRadius),
                                              turn: arc.angle(at: middle, radius: baselineRadius)))
                }
            }
            let width = CTLineGetTypographicBounds(line, nil, nil, nil) - CTLineGetTrailingWhitespaceWidth(line)
            if width > 0 {
                let startX = origin.x + CTLineGetOffsetForStringIndex(line, CTLineGetStringRange(line).location, nil)
                spans.append(LineSpan(startX: startX, endX: startX + width, baseline: baseline))
            }
        }
        return (glyphs, spans)
    }

    /// A glyph's ink corners, placed, in the box's coordinates.
    private static func corners(of glyph: PlacedGlyph) -> [Point2D] {
        var glyphID = glyph.glyph
        var rect = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(glyph.font, .default, &glyphID, &rect, 1)
        guard !rect.isNull, rect.width > 0 || rect.height > 0 else { return [] }
        let c = cos(glyph.turn), s = sin(glyph.turn)
        // Glyph space is y up from the baseline, starting at its left; it's drawn centred on `position`.
        return [(rect.minX, rect.minY), (rect.maxX, rect.minY), (rect.minX, rect.maxY), (rect.maxX, rect.maxY)].map { x, y in
            let u = Double(x) - glyph.advance / 2, v = -Double(y)
            return Point2D(x: glyph.position.x + u * c - v * s, y: glyph.position.y + u * s + v * c)
        }
    }

    /// The lines under or through each line's words, placed on the arc. `offset` is how far below the baseline.
    private static func strokes(_ spans: [LineSpan], arc: TextArc, offset: Double) -> [[Point2D]] {
        spans.map { span in
            arc.placedPath(from: Point2D(x: span.startX, y: span.baseline + offset), to: Point2D(x: span.endX, y: span.baseline + offset),
                           angleRadius: arc.radius(at: span.baseline))
        }
    }

    private static func decorations(of spec: TextSpec, spans: [LineSpan], arc: TextArc) -> [(path: [Point2D], thickness: Double)] {
        let font = font(for: spec)
        var result: [(path: [Point2D], thickness: Double)] = []
        if spec.underline {
            let thickness = max(1, Double(CTFontGetUnderlineThickness(font)))
            result += strokes(spans, arc: arc, offset: -Double(CTFontGetUnderlinePosition(font))).map { ($0, thickness) }
        }
        if spec.strikethrough {
            let thickness = max(1, spec.fontSize / 15)
            result += strokes(spans, arc: arc, offset: -Double(CTFontGetXHeight(font)) / 2).map { ($0, thickness) }
        }
        return result
    }

    /// Everything curved text draws, in the box's coordinates, as a rectangle.
    private static func curvedExtent(of spec: TextSpec, arc: TextArc, colorSpace: CGColorSpace) -> (minX: Double, minY: Double, maxX: Double, maxY: Double) {
        let layout = curvedLayout(of: spec, arc: arc, colorSpace: colorSpace)
        var points = layout.glyphs.flatMap(corners)
        if spec.background != nil { points += arc.band }
        let lines = decorations(of: spec, spans: layout.lines, arc: arc)
        let widest = lines.map(\.thickness).max() ?? 0
        points += lines.flatMap(\.path)
        guard let first = points.first else { return (0, 0, 1, 1) }
        var extent = (minX: first.x, minY: first.y, maxX: first.x, maxY: first.y)
        for point in points {
            extent = (min(extent.minX, point.x), min(extent.minY, point.y), max(extent.maxX, point.x), max(extent.maxY, point.y))
        }
        // A pixel of slack, and half the thickest line, so anti-aliased edges aren't clipped.
        let pad = 1 + widest / 2
        return (extent.minX - pad, extent.minY - pad, extent.maxX + pad, extent.maxY + pad)
    }

    static func curvedBounds(of spec: TextSpec, arc: TextArc) -> IntRect {
        let extent = curvedExtent(of: spec, arc: arc, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        return IntRect(enclosingMinX: spec.origin.x + extent.minX, minY: spec.origin.y + extent.minY,
                       maxX: spec.origin.x + extent.maxX, maxY: spec.origin.y + extent.maxY)
    }

    static func renderCurved(_ spec: TextSpec, arc: TextArc, colorSpace: CGColorSpace, clippedTo canvasBounds: IntRect) -> (pixels: PixelBuffer, origin: IntPoint)? {
        let area = curvedBounds(of: spec, arc: arc).intersection(canvasBounds)
        guard !area.isEmpty else { return nil }
        let buffer = PixelBuffer(width: area.width, height: area.height)
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(
            data: buffer.baseAddress, width: area.width, height: area.height, bitsPerComponent: 8,
            bytesPerRow: buffer.bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo
        ) else { return nil }
        // From the box's coordinates (y down) to the buffer's (y up).
        func point(_ p: Point2D) -> CGPoint {
            CGPoint(x: spec.origin.x + p.x - Double(area.minX), y: Double(area.maxY) - (spec.origin.y + p.y))
        }
        func polyline(_ points: [Point2D]) -> CGPath {
            let path = CGMutablePath()
            path.addLines(between: points.map(point))
            return path
        }

        if let background = spec.background {
            context.setFillColor(cgColor(background, colorSpace))
            let band = polyline(arc.band).mutableCopy()!
            band.closeSubpath()
            context.addPath(band)
            context.fillPath()
        }
        let layout = curvedLayout(of: spec, arc: arc, colorSpace: colorSpace)
        context.setFillColor(cgColor(spec.color, colorSpace))
        for glyph in layout.glyphs {
            context.saveGState()
            let at = point(glyph.position)
            context.translateBy(x: at.x, y: at.y)
            // Clockwise in the box's y-down coordinates is the other way in the buffer's y-up ones.
            context.rotate(by: -glyph.turn)
            var id = glyph.glyph
            var position = CGPoint(x: -glyph.advance / 2, y: 0)
            CTFontDrawGlyphs(glyph.font, &id, &position, 1, context)
            context.restoreGState()
        }
        context.setStrokeColor(cgColor(spec.color, colorSpace))
        context.setLineCap(.butt)
        context.setLineJoin(.round)
        for line in decorations(of: spec, spans: layout.lines, arc: arc) {
            context.setLineWidth(line.thickness)
            context.addPath(polyline(line.path))
            context.strokePath()
        }

        var image = buffer.vImageBuffer
        vImageUnpremultiplyData_RGBA8888(&image, &image, vImage_Flags(kvImageNoFlags))
        return (buffer, IntPoint(x: area.minX, y: area.minY))
    }
}
