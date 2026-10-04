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

    /// A float mask from Vision as bytes, resampled to `size` if Vision's differs.
    private static func bytes(of buffer: CVPixelBuffer, size: IntSize) -> [UInt8] {
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
        let index = canvas.activeLayerIndex + 1
        canvas.insertLayer(Layer(name: "Subject", buffer: lifted), at: index)
        canvas.activeLayerIndex = index
        return history.commit(edit)
    }

    /// Selects the subject. Selections are all-or-nothing, so the soft edge is cut at half.
    public static func select(_ mask: [UInt8], canvas: Canvas, history: History, context: SelectionContext) {
        let values = mask.map { $0 >= 128 ? UInt8(255) : 0 }
        let selection = SelectionMask(bounds: canvas.bounds, values: values).trimmed()
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
