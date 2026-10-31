import CoreGraphics
import CoreText

/// What a text layer holds (FR-6.3, stage 29): its words and settings, laid out upright, and how the image has been
/// turned since. The layer's pixels are this drawn; rotations and flips turn those pixels exactly, so they stay crisp.
public struct TextLayer: Equatable, Sendable {
    public var spec: TextSpec
    /// Quarter turns clockwise, applied after `mirrored`.
    public private(set) var quarterTurns = 0
    /// Flipped left to right, before the quarter turns.
    public private(set) var mirrored = false

    public init(spec: TextSpec, quarterTurns: Int = 0, mirrored: Bool = false) {
        self.spec = spec
        self.quarterTurns = ((quarterTurns % 4) + 4) % 4
        self.mirrored = mirrored
    }

    /// The text reads as it was set. Only then can it be edited, resized or drawn again (stage 29, my choice).
    public var isUpright: Bool { quarterTurns == 0 && !mirrored }

    /// Follows a Rotate or Flip of the whole image. A flip after quarter turns is the same as the turns the other way
    /// after a flip, so any mix comes down to a mirror and up to three quarter turns.
    mutating func turn(_ orientation: Orientation) {
        switch orientation {
        case .rotate90Clockwise: quarterTurns = (quarterTurns + 1) % 4
        case .rotate90CounterClockwise: quarterTurns = (quarterTurns + 3) % 4
        case .rotate180: quarterTurns = (quarterTurns + 2) % 4
        case .flipHorizontal:
            quarterTurns = (4 - quarterTurns) % 4
            mirrored.toggle()
        case .flipVertical:
            quarterTurns = (6 - quarterTurns) % 4
            mirrored.toggle()
        }
    }

    /// The text drawn on a clear layer of `size`, upright.
    public func drawn(size: IntSize, colorSpace: CGColorSpace) -> PixelBuffer {
        let buffer = PixelBuffer(size: size)
        if let rendered = TextRenderer.render(spec, colorSpace: colorSpace, clippedTo: IntRect(size: size)) {
            buffer.setPixels(rendered.pixels.pixels(in: rendered.pixels.bounds),
                             in: IntRect(x: rendered.origin.x, y: rendered.origin.y, width: rendered.pixels.width, height: rendered.pixels.height))
        }
        return buffer
    }

    /// The layer's name: the text's first line, shortened.
    public var name: String {
        let line = spec.text.split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !line.isEmpty else { return "Text" }
        return line.count > 30 ? String(line.prefix(29)) + "…" : line
    }

    /// Whether this Mac has the text's font. Without it the layer keeps the pixels it was drawn with (Q29.4).
    public var hasFont: Bool { TextRenderer.hasFont(for: spec) }

    /// The text moved and scaled with the image: a point at p goes to p × scale + offset.
    func fitted(scale: Double, dx: Double, dy: Double) -> TextLayer {
        var fitted = self
        fitted.spec.origin = Point2D(x: spec.origin.x * scale + dx, y: spec.origin.y * scale + dy)
        fitted.spec.fontSize = spec.fontSize * scale
        fitted.spec.wrapWidth = spec.wrapWidth.map { $0 * scale }
        fitted.spec.minimumHeight = spec.minimumHeight * scale
        return fitted
    }
}

/// How a geometry change moves and scales text layers: a point at p goes to p × scale + offset. Nil where it can't
/// keep text crisp (a skew, a non-uniform resize, a straighten), and text layers become plain pixels.
struct TextFit {
    var scale = 1.0
    var dx = 0.0
    var dy = 0.0

    static func moved(dx: Int, dy: Int) -> TextFit { TextFit(dx: Double(dx), dy: Double(dy)) }

    /// From a resize of `old` to `new`, if both sides scale alike (to within a pixel's rounding).
    static func resized(from old: IntSize, to new: IntSize) -> TextFit? {
        let sx = Double(new.width) / Double(old.width), sy = Double(new.height) / Double(old.height)
        guard abs(sx * Double(old.height) - Double(new.height)) <= 1, abs(sy * Double(old.width) - Double(new.width)) <= 1 else { return nil }
        return TextFit(scale: sx)
    }
}

extension Canvas {
    /// After a geometry change replaced the buffers: each text layer follows `fit` and is drawn again, crisp. Without a
    /// fit, turned, cut off by the new edges, or with its font missing (when it must be scaled), it becomes plain pixels,
    /// kept as the change made them.
    func fitText(_ fit: TextFit?, edit: Edit) {
        for layer in layers {
            guard let text = layer.text else { continue }
            edit.willChangeText(of: layer)
            guard let fit, text.isUpright else {
                layer.text = nil
                continue
            }
            let fitted = text.fitted(scale: fit.scale, dx: fit.dx, dy: fit.dy)
            // Words the change cuts off would stay in the layer and come back later, out of Auto-Redact's sight
            // (Leah, 2026-10-31; review Y, finding 6): such a layer becomes pixels, as the change left them.
            guard bounds.contains(TextRenderer.box(for: fitted.spec)) else {
                layer.text = nil
                continue
            }
            if fitted.hasFont {
                layer.buffer = fitted.drawn(size: size, colorSpace: colorSpace)
            } else if fit.scale != 1 {
                layer.text = nil
                continue
            }
            layer.text = fitted
        }
    }
}
