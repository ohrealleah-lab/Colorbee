import CoreGraphics
import CoreVideo
import Vision

/// The subjects Apple Vision finds in an image, on this Mac (FR-9.5): one soft mask per subject, 0...255,
/// covering the whole image row by row.
public struct SubjectScan: Sendable {
    public let size: IntSize
    public let masks: [[UInt8]]

    public init(size: IntSize, masks: [[UInt8]]) {
        self.size = size
        self.masks = masks
    }

    public var isEmpty: Bool { masks.isEmpty }

    /// Finds the subjects in `image`. Nothing leaves the Mac.
    public static func find(in image: CGImage) async throws -> SubjectScan {
        try await Task.detached(priority: .userInitiated) {
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: image)
            try handler.perform([request])
            let size = IntSize(width: image.width, height: image.height)
            guard let observation = request.results?.first else { return SubjectScan(size: size, masks: []) }
            let masks = try observation.allInstances.map { instance in
                let scaled = try observation.generateScaledMaskForImage(forInstances: IndexSet(integer: instance), from: handler)
                return bytes(of: scaled, size: size)
            }
            return SubjectScan(size: size, masks: masks)
        }.value
    }

    /// Looks again in ever smaller squares around `point`, for a subject too small for Vision to see in the whole
    /// image, and returns the mask of the one under `point`, the size of the whole image (Leah, 2026-10-27).
    public static func findCloser(at point: IntPoint, in image: CGImage) async throws -> [UInt8]? {
        let size = IntSize(width: image.width, height: image.height)
        for square in closerSquares(around: point, in: size) {
            guard let crop = image.cropping(to: CGRect(x: square.x, y: square.y, width: square.width, height: square.height)) else { continue }
            let scan = try await find(in: crop)
            if let index = scan.subject(at: IntPoint(x: point.x - square.x, y: point.y - square.y)) {
                return placed(scan.masks[index], from: square, in: size)
            }
        }
        return nil
    }

    /// The squares to look in, largest first, kept inside the image. Vision looks at about 512 × 512, so the first is
    /// half the image's shorter side and each is 0.7 of the one before, down to about 200 px.
    static func closerSquares(around point: IntPoint, in size: IntSize) -> [IntRect] {
        let shorter = min(size.width, size.height)
        var squares: [IntRect] = []
        var side = Double(shorter) / 2
        while side >= 200 || squares.isEmpty {
            let length = max(1, Int(side.rounded()))
            let x = min(max(0, point.x - length / 2), size.width - length)
            let y = min(max(0, point.y - length / 2), size.height - length)
            squares.append(IntRect(x: x, y: y, width: length, height: length))
            side *= 0.7
        }
        return squares
    }

    /// A mask found in `square`, placed in an empty mask of the whole image.
    static func placed(_ mask: [UInt8], from square: IntRect, in size: IntSize) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: size.width * size.height)
        for row in 0..<square.height {
            let from = row * square.width, to = (square.y + row) * size.width + square.x
            result[to..<(to + square.width)] = mask[from..<(from + square.width)]
        }
        return result
    }

    /// A float mask from Vision as bytes, resampled to `size` if Vision's differs.
    static func bytes(of buffer: CVPixelBuffer, size: IntSize) -> [UInt8] {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        guard let base = CVPixelBufferGetBaseAddress(buffer), width > 0, height > 0 else {
            return [UInt8](repeating: 0, count: size.width * size.height)
        }
        var result = [UInt8](repeating: 0, count: size.width * size.height)
        for y in 0..<size.height {
            let row = (base + rowBytes * min(height - 1, y * height / size.height)).assumingMemoryBound(to: Float.self)
            for x in 0..<size.width {
                result[y * size.width + x] = UInt8((min(max(row[min(width - 1, x * width / size.width)], 0), 1) * 255).rounded())
            }
        }
        return result
    }

    /// The subject at `point`: the one whose mask is strongest there, if any is at least half.
    public func subject(at point: IntPoint) -> Int? {
        guard point.x >= 0, point.y >= 0, point.x < size.width, point.y < size.height else { return nil }
        let index = point.y * size.width + point.x
        let best = masks.indices.max { masks[$0][index] < masks[$1][index] }
        return best.flatMap { masks[$0][index] >= 128 ? $0 : nil }
    }

    /// The chosen subjects together (nil for all of them).
    public func mask(for subjects: [Int]? = nil) -> [UInt8] {
        let chosen = (subjects ?? Array(masks.indices)).filter { masks.indices.contains($0) }
        guard let first = chosen.first else { return [UInt8](repeating: 0, count: size.width * size.height) }
        var combined = masks[first]
        for other in chosen.dropFirst() {
            for index in combined.indices { combined[index] = max(combined[index], masks[other][index]) }
        }
        return combined
    }
}

/// Remove Background, Lift Subject to New Layer and Select Subject (FR-9.5), from a subject mask.
public enum SubjectActions {
    /// Writes the mask's soft edges into the active layer's transparency, as one step.
    @discardableResult
    public static func removeBackground(_ mask: [UInt8], canvas: Canvas, history: History, context: SelectionContext) -> Bool {
        SelectionActions.placeFloating(canvas: canvas, history: history, context: context)
        let layer = canvas.activeLayer
        guard layer.adjustment == nil, !layer.isLocked, mask.count == canvas.size.width * canvas.size.height else { return false }
        let edit = history.beginEdit("Remove Background", on: canvas)
        edit.willModify(canvas.bounds, in: layer)
        apply(mask, to: layer.buffer)
        return history.commit(edit)
    }

    /// Copies the subject onto a new layer just above the active one, leaving the original as it was.
    @discardableResult
    public static func liftToNewLayer(_ mask: [UInt8], canvas: Canvas, history: History, context: SelectionContext) -> Bool {
        SelectionActions.placeFloating(canvas: canvas, history: history, context: context)
        let source = canvas.activeLayer
        guard source.adjustment == nil, mask.count == canvas.size.width * canvas.size.height else { return false }
        let lifted = source.buffer.copy()
        apply(mask, to: lifted)
        let edit = history.beginEdit("Lift Subject", on: canvas)
        edit.willChangeLayers()
        // The picture's layer stays active, so the next lift finds subjects in the picture, not in this one
        // (Leah, 2026-10-28).
        canvas.insertLayer(Layer(name: "Subject", buffer: lifted), at: canvas.indexAboveActiveLayer)
        return history.commit(edit)
    }

    /// Selects the subject, keeping Vision's soft edge (FR-3.4).
    public static func select(_ mask: [UInt8], canvas: Canvas, history: History, context: SelectionContext) {
        let selection = SelectionMask(bounds: canvas.bounds, values: mask).trimmed()
        SelectionActions.select(selection, mode: .replace, canvas: canvas, history: history, context: context)
    }

    private static func apply(_ mask: [UInt8], to buffer: PixelBuffer) {
        let width = buffer.width
        ParallelRows.forEach(0..<buffer.height) { rows in
            for y in rows {
                let row = buffer.row(y)
                for x in 0..<width {
                    let keep = UInt16(mask[y * width + x])
                    let alpha = UInt8((UInt16(row[x].a) * keep + 127) / 255)
                    // Fully cut away means gone: no hidden color for an editor to bring back (review H, finding 7).
                    row[x] = alpha == 0 ? .clear : Pixel(r: row[x].r, g: row[x].g, b: row[x].b, a: alpha)
                }
            }
        }
    }
}
