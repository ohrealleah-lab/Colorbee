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
        try await closerSubject(at: point, in: image)?.mask
    }

    /// The closer look's subject under `point`, and the square it was found in.
    static func closerSubject(at point: IntPoint, in image: CGImage) async throws -> (mask: [UInt8], square: IntRect)? {
        let size = IntSize(width: image.width, height: image.height)
        for square in closerSquares(around: point, in: size) {
            guard let crop = image.cropping(to: CGRect(x: square.x, y: square.y, width: square.width, height: square.height)) else { continue }
            let scan = try await find(in: crop)
            if let index = scan.subject(at: IntPoint(x: point.x - square.x, y: point.y - square.y)) {
                return (placed(scan.masks[index], from: square, in: size), square)
            }
        }
        return nil
    }

    /// The subject under `point` in `mask`'s place, when Vision's first look joined it with its neighbors: a closer
    /// look around the click often sees them apart (Leah, 2026-11-01). Otherwise `mask` itself.
    public static func untangled(_ mask: [UInt8], at point: IntPoint, in image: CGImage) async throws -> [UInt8] {
        guard let closer = try await closerSubject(at: point, in: image) else { return mask }
        let size = IntSize(width: image.width, height: image.height)
        return !isCut(closer.mask, by: closer.square, in: size) && prefers(closer.mask, over: mask) ? closer.mask : mask
    }

    /// Whether a subject found in `square` runs into one of its sides inside the picture: then the square cut it off,
    /// and it only looks smaller than the first look's. In a tall portrait, the square as wide as the picture cut off
    /// the head and the dress (Leah, 2026-11-02). A few stray pixels on a side don't count.
    static func isCut(_ mask: [UInt8], by square: IntRect, in size: IntSize) -> Bool {
        var touching = 0
        func count(_ x: Int, _ y: Int) { if mask[y * size.width + x] >= 128 { touching += 1 } }
        for x in square.x..<square.maxX {
            if square.y > 0 { count(x, square.y) }
            if square.maxY < size.height { count(x, square.maxY - 1) }
        }
        for y in square.y..<square.maxY {
            if square.x > 0 { count(square.x, y) }
            if square.maxX < size.width { count(square.maxX - 1, y) }
        }
        return touching > 8
    }

    /// Whether a closer look's subject is a separate one inside the first look's: mostly within it, clearly smaller,
    /// and at least a fifth of its size, so a click on someone never takes just their hat (Leah, 2026-11-01).
    static func prefers(_ closer: [UInt8], over mask: [UInt8]) -> Bool {
        guard closer.count == mask.count else { return false }
        var area = 0, closerArea = 0, inside = 0
        for index in mask.indices {
            let inMask = mask[index] >= 128, inCloser = closer[index] >= 128
            if inMask { area += 1 }
            if inCloser { closerArea += 1 }
            if inMask && inCloser { inside += 1 }
        }
        return closerArea * 5 >= area && closerArea * 10 <= area * 9 && inside * 5 >= closerArea * 4
    }

    /// The squares to look in, largest first, kept inside the image. Vision looks at about 512 × 512, so each is 0.7 of
    /// the one before, down to about 200 px. The first is the image's whole shorter side, so a tall subject isn't cut
    /// off (Leah, 2026-11-01), unless that is the whole picture.
    static func closerSquares(around point: IntPoint, in size: IntSize) -> [IntRect] {
        let shorter = min(size.width, size.height)
        var squares: [IntRect] = []
        var side = Double(shorter)
        while side >= 200 || squares.isEmpty {
            let length = max(1, Int(side.rounded()))
            defer { side *= 0.7 }
            // On a square picture the first square is the whole picture: Vision would see what it saw the first time
            // (review AG, finding 1).
            if length >= size.width && length >= size.height { continue }
            let x = min(max(0, point.x - length / 2), size.width - length)
            let y = min(max(0, point.y - length / 2), size.height - length)
            squares.append(IntRect(x: x, y: y, width: length, height: length))
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

    /// What a click at `point` takes: the subject found there, untangled from its neighbors, or else one a closer look
    /// finds (Leah, 2026-10-27 and 2026-11-01).
    public func subjectMask(at point: IntPoint, in image: CGImage) async throws -> [UInt8]? {
        if let index = subject(at: point) { return try await Self.untangled(masks[index], at: point, in: image) }
        return try await Self.findCloser(at: point, in: image)
    }

    /// Which subject each pixel shows, for outlining them: 0 for none, otherwise the subject's index plus 1. Where
    /// subjects overlap the strongest wins, and on a tie the later one, since a subject added after a closer look sits
    /// inside the one it was untangled from.
    public func labels() -> [UInt8] {
        var result = [UInt8](repeating: 0, count: size.width * size.height)
        let count = min(masks.count, 255), width = size.width
        result.withUnsafeMutableBufferPointer { labels in
            // Each band writes only its own rows.
            let labels = UnsafeSendable(labels)
            ParallelRows.forEach(0..<size.height) { rows in
                for index in (rows.lowerBound * width)..<(rows.upperBound * width) {
                    var best: UInt8 = 127, label: UInt8 = 0
                    for subject in 0..<count where masks[subject][index] >= max(best, 128) {
                        best = masks[subject][index]
                        label = UInt8(subject + 1)
                    }
                    labels.value[index] = label
                }
            }
        }
        return result
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
        guard layer.isPixelLayer, !canvas.isLocked(layer), mask.count == canvas.size.width * canvas.size.height else { return false }
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
        guard source.isPixelLayer, mask.count == canvas.size.width * canvas.size.height else { return false }
        let lifted = source.buffer.copy()
        apply(mask, to: lifted)
        let edit = history.beginEdit("Lift Subject", on: canvas)
        edit.willChangeLayers()
        // The picture's layer stays active, so the next lift finds subjects in the picture, not in this one
        // (Leah, 2026-10-28).
        let subject = Layer(name: "Subject", buffer: lifted)
        subject.groupID = source.groupID
        canvas.insertLayer(subject, at: canvas.indexAboveActiveLayer)
        return history.commit(edit)
    }

    /// Selects the subject, keeping Vision's soft edge (FR-3.4), or adds it to the selection or takes it away, for the
    /// Magic Wand's Object mode.
    public static func select(_ mask: [UInt8], mode: SelectionCombineMode = .replace, canvas: Canvas, history: History, context: SelectionContext) {
        guard mask.count == canvas.bounds.area else { return }
        let selection = SelectionMask(bounds: canvas.bounds, values: mask).trimmed()
        SelectionActions.select(selection, mode: mode, canvas: canvas, history: history, context: context)
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
