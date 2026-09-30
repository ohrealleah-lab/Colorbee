import Darwin

/// A contiguous BGRA8, straight-alpha image. The memory is page-aligned and a whole number of pages
/// so the display layer can wrap it in a GPU buffer without copying.
public final class PixelBuffer {
    public static let pageSize = Int(getpagesize())
    public static let defaultRowAlignment = 256

    public let width: Int
    public let height: Int
    public let bytesPerRow: Int
    public let byteCount: Int
    public let baseAddress: UnsafeMutableRawPointer
    private let pixels: UnsafeMutablePointer<Pixel>
    private let pixelsPerRow: Int

    public init(width: Int, height: Int, fill: Pixel = .clear, rowAlignment: Int = PixelBuffer.defaultRowAlignment) {
        precondition(width > 0 && height > 0, "PixelBuffer needs a positive size")
        precondition(rowAlignment > 0 && rowAlignment % 4 == 0, "Row alignment must be a positive multiple of 4")
        self.width = width
        self.height = height
        bytesPerRow = (width * 4 + rowAlignment - 1) / rowAlignment * rowAlignment
        pixelsPerRow = bytesPerRow / 4
        let pageSize = PixelBuffer.pageSize
        byteCount = (bytesPerRow * height + pageSize - 1) / pageSize * pageSize
        baseAddress = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: pageSize)
        baseAddress.initializeMemory(as: UInt8.self, repeating: 0, count: byteCount)
        pixels = baseAddress.bindMemory(to: Pixel.self, capacity: byteCount / 4)
        if fill != .clear {
            self.fill(fill)
        }
    }

    deinit {
        baseAddress.deallocate()
    }

    public var size: IntSize { IntSize(width: width, height: height) }
    public var bounds: IntRect { IntRect(size: size) }

    @inline(__always)
    public func row(_ y: Int) -> UnsafeMutablePointer<Pixel> {
        pixels + y * pixelsPerRow
    }

    public subscript(x: Int, y: Int) -> Pixel {
        get { row(y)[x] }
        set { row(y)[x] = newValue }
    }

    public func fill(_ value: Pixel, in rect: IntRect? = nil) {
        let target = (rect ?? bounds).intersection(bounds)
        guard !target.isEmpty else { return }
        for y in target.minY..<target.maxY {
            (row(y) + target.minX).update(repeating: value, count: target.width)
        }
    }

    public func pixels(in rect: IntRect) -> [Pixel] {
        precondition(bounds.contains(rect), "Rect \(rect) is outside the buffer")
        var result = [Pixel]()
        result.reserveCapacity(rect.area)
        for y in rect.minY..<rect.maxY {
            result.append(contentsOf: UnsafeBufferPointer(start: row(y) + rect.minX, count: rect.width))
        }
        return result
    }

    public func setPixels(_ values: [Pixel], in rect: IntRect) {
        precondition(bounds.contains(rect), "Rect \(rect) is outside the buffer")
        precondition(values.count == rect.area, "Expected \(rect.area) pixels, got \(values.count)")
        values.withUnsafeBufferPointer { source in
            guard let start = source.baseAddress else { return }
            for (index, y) in (rect.minY..<rect.maxY).enumerated() {
                (row(y) + rect.minX).update(from: start + index * rect.width, count: rect.width)
            }
        }
    }

    public func copy() -> PixelBuffer {
        let result = PixelBuffer(width: width, height: height)
        result.baseAddress.copyMemory(from: baseAddress, byteCount: bytesPerRow * height)
        return result
    }

    /// A hash of the visible pixels only (row padding is ignored).
    public func contentHash() -> Int {
        var hasher = Hasher()
        for y in 0..<height {
            hasher.combine(bytes: UnsafeRawBufferPointer(start: row(y), count: width * 4))
        }
        return hasher.finalize()
    }
}
