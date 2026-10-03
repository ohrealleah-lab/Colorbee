import Foundation

/// Straighten and Perspective Correction (FR-9.5): every output pixel is looked up in the original image,
/// with bilinear sampling in premultiplied color so transparent areas don't darken the edges.
public enum Warp {
    /// The rotation (degrees, clockwise) that makes a line drawn from `start` to `end` level, or upright when
    /// it's closer to vertical. Within -45...45.
    public static func straighteningAngle(from start: Point2D, to end: Point2D) -> Double {
        let dx = end.x - start.x, dy = end.y - start.y
        guard dx != 0 || dy != 0 else { return 0 }
        // In image coordinates y points down, so a line rising to the right has a negative angle.
        var angle = atan2(dy, dx) * 180 / .pi
        while angle > 45 { angle -= 90 }
        while angle < -45 { angle += 90 }
        return -angle
    }

    /// The canvas size after turning by `angle` degrees. Crop to Fit keeps the largest rectangle of the
    /// same shape that has no empty corners; otherwise the canvas grows to hold the whole turned image.
    public static func straightenedSize(_ size: IntSize, angle: Double, cropToFit: Bool) -> IntSize {
        let radians = abs(angle) * .pi / 180
        let c = cos(radians), s = sin(radians)
        let w = Double(size.width), h = Double(size.height)
        if cropToFit {
            let scale = min(w / (w * c + h * s), h / (w * s + h * c))
            // A pixel less than the exact fit, so smooth sampling never reaches past the turned edges.
            return IntSize(width: max(1, Int((w * scale).rounded(.down)) - 1), height: max(1, Int((h * scale).rounded(.down)) - 1))
        }
        return IntSize(width: Int((w * c + h * s - 1e-9).rounded(.up)), height: Int((w * s + h * c - 1e-9).rounded(.up)))
    }

    /// `buffer` turned clockwise by `angle` degrees about its center, onto `size` (centered), over `fill`.
    static func rotated(_ buffer: PixelBuffer, angle: Double, size: IntSize, fill: Pixel) -> PixelBuffer {
        let radians = angle * .pi / 180
        let c = cos(radians), s = sin(radians)
        let sourceCenter = Point2D(x: Double(buffer.width) / 2, y: Double(buffer.height) / 2)
        let targetCenter = Point2D(x: Double(size.width) / 2, y: Double(size.height) / 2)
        return warped(buffer, size: size, fill: fill) { x, y in
            let u = x - targetCenter.x, v = y - targetCenter.y
            // The inverse turn: counterclockwise, back into the original.
            return Point2D(x: u * c + v * s + sourceCenter.x, y: -u * s + v * c + sourceCenter.y)
        }
    }

    /// The four corners (top left, top right, bottom right, bottom left, in image coordinates) stretched to a
    /// rectangle as wide as the longer of the top and bottom edges and as tall as the longer side.
    public static func perspectiveSize(_ corners: [Point2D]) -> IntSize {
        func length(_ a: Point2D, _ b: Point2D) -> Double { hypot(b.x - a.x, b.y - a.y) }
        let width = max(length(corners[0], corners[1]), length(corners[3], corners[2]))
        let height = max(length(corners[0], corners[3]), length(corners[1], corners[2]))
        return IntSize(width: max(1, Int(width.rounded())), height: max(1, Int(height.rounded())))
    }

    static func perspectiveCorrected(_ buffer: PixelBuffer, corners: [Point2D], size: IntSize) -> PixelBuffer {
        let map = Homography(square: corners)
        return warped(buffer, size: size, fill: .clear) { x, y in
            map.apply(x / Double(size.width), y / Double(size.height))
        }
    }

    /// Fills each pixel of a new `size` buffer from where `source(x, y)` says it came from (pixel centers in, image
    /// coordinates out). Anything from outside the original shows `fill`.
    private static func warped(_ buffer: PixelBuffer, size: IntSize, fill: Pixel, source: @escaping (Double, Double) -> Point2D) -> PixelBuffer {
        let result = PixelBuffer(width: size.width, height: size.height)
        let background = Compositing.premultiplied(fill)
        ParallelRows.forEach(0..<size.height) { rows in
            for y in rows {
                let target = result.row(y)
                for x in 0..<size.width {
                    let point = source(Double(x) + 0.5, Double(y) + 0.5)
                    let sample = Self.sample(buffer, point.x - 0.5, point.y - 0.5)
                    target[x] = Compositing.pixel(sample + background * (1 - sample.w))
                }
            }
        }
        return result
    }

    /// Bilinear, premultiplied; pixel (i, j) has its center at (i, j). Outside the buffer is transparent.
    static func sample(_ buffer: PixelBuffer, _ x: Double, _ y: Double) -> SIMD4<Float> {
        let x0 = Int(x.rounded(.down)), y0 = Int(y.rounded(.down))
        let tx = Float(x - Double(x0)), ty = Float(y - Double(y0))
        func tap(_ px: Int, _ py: Int) -> SIMD4<Float> {
            guard px >= 0, py >= 0, px < buffer.width, py < buffer.height else { return .zero }
            return Compositing.premultiplied(buffer.row(py)[px])
        }
        let top = tap(x0, y0) * (1 - tx) + tap(x0 + 1, y0) * tx
        let bottom = tap(x0, y0 + 1) * (1 - tx) + tap(x0 + 1, y0 + 1) * tx
        return top * (1 - ty) + bottom * ty
    }
}

/// The projective map from the unit square onto four corners (Heckbert's square-to-quad).
struct Homography {
    let a, b, c, d, e, f, g, h: Double

    /// `corners`: where (0, 0), (1, 0), (1, 1) and (0, 1) land.
    init(square corners: [Point2D]) {
        let (x0, y0) = (corners[0].x, corners[0].y), (x1, y1) = (corners[1].x, corners[1].y)
        let (x2, y2) = (corners[2].x, corners[2].y), (x3, y3) = (corners[3].x, corners[3].y)
        let dx1 = x1 - x2, dx2 = x3 - x2, dx3 = x0 - x1 + x2 - x3
        let dy1 = y1 - y2, dy2 = y3 - y2, dy3 = y0 - y1 + y2 - y3
        let denominator = dx1 * dy2 - dx2 * dy1
        if abs(dx3) < 1e-12 && abs(dy3) < 1e-12 || abs(denominator) < 1e-12 {
            (g, h) = (0, 0)
        } else {
            g = (dx3 * dy2 - dx2 * dy3) / denominator
            h = (dx1 * dy3 - dx3 * dy1) / denominator
        }
        a = x1 - x0 + g * x1
        b = x3 - x0 + h * x3
        c = x0
        d = y1 - y0 + g * y1
        e = y3 - y0 + h * y3
        f = y0
    }

    func apply(_ u: Double, _ v: Double) -> Point2D {
        let w = g * u + h * v + 1
        return Point2D(x: (a * u + b * v + c) / w, y: (d * u + e * v + f) / w)
    }
}

/// The crop box (FR-9.5): fitting a shape inside the image and keeping the box on it.
public enum CropBox {
    /// The largest rectangle of `aspect` (width ÷ height) that fits in `bounds`, centered in it.
    public static func fitted(aspect: Double, in bounds: IntRect) -> IntRect {
        guard aspect > 0 else { return bounds }
        var width = Double(bounds.width), height = width / aspect
        if height > Double(bounds.height) {
            height = Double(bounds.height)
            width = height * aspect
        }
        let w = max(1, Int(width.rounded())), h = max(1, Int(height.rounded()))
        return IntRect(x: bounds.minX + (bounds.width - w) / 2, y: bounds.minY + (bounds.height - h) / 2, width: w, height: h)
    }

    /// `rect` kept inside `bounds`: shrunk about its center if it's too big (keeping `aspect` when given),
    /// then moved back in.
    public static func clamped(_ rect: IntRect, to bounds: IntRect, aspect: Double?) -> IntRect {
        var width = min(rect.width, bounds.width), height = min(rect.height, bounds.height)
        if let aspect, aspect > 0 {
            if Double(width) / Double(height) > aspect {
                width = max(1, Int((Double(height) * aspect).rounded()))
            } else {
                height = max(1, Int((Double(width) / aspect).rounded()))
            }
        }
        let centerX = rect.minX + rect.width / 2, centerY = rect.minY + rect.height / 2
        let x = min(max(centerX - width / 2, bounds.minX), bounds.maxX - width)
        let y = min(max(centerY - height / 2, bounds.minY), bounds.maxY - height)
        return IntRect(x: x, y: y, width: width, height: height)
    }

    /// `rect` moved by `delta`, staying inside `bounds`.
    public static func moved(_ rect: IntRect, by delta: IntPoint, within bounds: IntRect) -> IntRect {
        let x = min(max(rect.minX + delta.x, bounds.minX), bounds.maxX - rect.width)
        let y = min(max(rect.minY + delta.y, bounds.minY), bounds.maxY - rect.height)
        return IntRect(x: x, y: y, width: rect.width, height: rect.height)
    }
}

extension ImageActions {
    /// Straighten (FR-9.5): turns every layer by `angle` degrees clockwise, smoothly, as one step. With Crop to
    /// Fit the empty corners are trimmed; otherwise the canvas grows and they get Color 2 on a solid image.
    @discardableResult
    public static func straighten(angle: Double, cropToFit: Bool, canvas: Canvas, history: History, context: SelectionContext) -> Bool {
        let angle = min(max(angle, -45), 45)
        guard abs(angle) >= 0.05 else { return false }
        let size = Warp.straightenedSize(canvas.size, angle: angle, cropToFit: cropToFit)
        return replaceEveryLayer("Straighten", size: size, canvas: canvas, history: history, context: context) { layer in
            Warp.rotated(layer.buffer, angle: angle, size: size, fill: canvas.vacatedFill(for: layer, color2: context.color2))
        }
    }

    /// Perspective Correction (FR-9.5): the four corners (top left, top right, bottom right, bottom left) become
    /// the corners of the new canvas, on every layer, as one step.
    @discardableResult
    public static func correctPerspective(corners: [Point2D], canvas: Canvas, history: History, context: SelectionContext) -> Bool {
        guard corners.count == 4 else { return false }
        let size = Warp.perspectiveSize(corners)
        guard size.width <= ResizeSkew.maxSide, size.height <= ResizeSkew.maxSide, size.width * size.height <= ResizeSkew.maxArea else { return false }
        return replaceEveryLayer("Perspective Correction", size: size, canvas: canvas, history: history, context: context) { layer in
            Warp.perspectiveCorrected(layer.buffer, corners: corners, size: size)
        }
    }

    /// Crop… (FR-9.5): crops every layer to `rect`, and with a pixel-size preset resizes the result to exactly
    /// `size`, as one step.
    @discardableResult
    public static func crop(to rect: IntRect, resizingTo size: IntSize?, canvas: Canvas, history: History, context: SelectionContext) -> Bool {
        let target = rect.intersection(canvas.bounds)
        guard !target.isEmpty else { return false }
        let finalSize = size ?? target.size
        guard target != canvas.bounds || finalSize != canvas.size else { return false }
        return replaceEveryLayer(size == nil ? "Crop" : "Crop and Resize", size: finalSize, canvas: canvas, history: history, context: context) { layer in
            let cropped = PixelBuffer(width: target.width, height: target.height)
            cropped.setPixels(layer.buffer.pixels(in: target), in: cropped.bounds)
            return cropped.resampled(to: finalSize, using: .smooth)
        }
    }

    /// A geometry step that gives every layer a new buffer of `size`. Layers with no pixels get an empty one.
    private static func replaceEveryLayer(_ name: String, size: IntSize, canvas: Canvas, history: History, context: SelectionContext,
                                          _ make: (Layer) -> PixelBuffer) -> Bool {
        SelectionActions.placeFloating(canvas: canvas, history: history, context: context)
        let edit = history.beginEdit(name, on: canvas)
        edit.willChangeGeometry()
        var buffers: [LayerID: PixelBuffer] = [:]
        for layer in canvas.layers {
            buffers[layer.id] = layer.holdsNoPixels ? PixelBuffer(size: size) : make(layer)
        }
        canvas.replaceContents(size: size, buffers: buffers)
        canvas.selection = .none
        return history.commit(edit)
    }
}
