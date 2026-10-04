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
        // Anonymous mapped memory arrives zeroed and page-aligned, and pages are only committed once
        // written, so a new transparent layer (or an adjustment layer, which never stores pixels) is cheap.
        guard let mapped = mmap(nil, byteCount, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0), mapped != MAP_FAILED else {
            fatalError("Out of memory for a \(width) × \(height) image")
        }
        baseAddress = mapped
        pixels = baseAddress.bindMemory(to: Pixel.self, capacity: byteCount / 4)
        if fill != .clear {
            self.fill(fill)
        }
    }

    deinit {
        munmap(baseAddress, byteCount)
    }

    /// Changes whenever the memory is replaced, so anything wrapping it (a GPU texture) knows to wrap it again.
    public private(set) var generation = 0

    /// True when no page has ever been written (or the contents were discarded): the buffer reads as all
    /// clear and costs no memory. Pages the system compressed or swapped out count as written.
    var isUntouched: Bool {
        let pageSize = PixelBuffer.pageSize
        var pages = [CChar](repeating: 0, count: byteCount / pageSize)
        guard mincore(baseAddress, byteCount, &pages) == 0 else { return false }
        // Every page of anonymous memory carries MINCORE_ANONYMOUS; any other flag means it holds data.
        let anonymous = CChar(bitPattern: UInt8(MINCORE_ANONYMOUS))
        return pages.allSatisfy { $0 & ~anonymous == 0 }
    }

    /// Hands the memory back to the system, the same way the system allocator returns freed memory; the
    /// contents are undefined until `reuseContents()`. History uses this for layers it has written to its
    /// spill file, and writes every pixel back before anything reads them.
    func discardContents() {
        guard !isDiscarded else { return }
        generation += 1
        madvise(baseAddress, byteCount, MADV_FREE_REUSABLE)
        isDiscarded = true
    }

    /// Takes discarded memory back for writing. The caller then writes every pixel.
    func reuseContents() {
        guard isDiscarded else { return }
        madvise(baseAddress, byteCount, MADV_FREE_REUSE)
        isDiscarded = false
    }

    private(set) var isDiscarded = false

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

    /// Whether any pixel is less than fully opaque.
    public var hasTransparency: Bool {
        for y in 0..<height {
            let row = row(y)
            for x in 0..<width where row[x].a < 255 {
                return true
            }
        }
        return false
    }

    public func copy() -> PixelBuffer {
        let result = PixelBuffer(width: width, height: height)
        result.baseAddress.copyMemory(from: baseAddress, byteCount: bytesPerRow * height)
        return result
    }

    /// A hash of the visible pixels, computed in bands on all cores; for telling whether a large buffer
    /// changed. Not the same value as `contentHash()`.
    func fingerprint() -> Int {
        let bands = GeometryChange.bands(of: size)
        return Self.fingerprint(combining: ParallelRows.map(bands.count) { index in
            var hasher = Hasher()
            for y in bands[index].y..<bands[index].maxY {
                hasher.combine(bytes: UnsafeRawBufferPointer(start: row(y), count: width * MemoryLayout<Pixel>.stride))
            }
            return hasher.finalize()
        })
    }

    /// One band's share of `fingerprint()`, from the band's pixels packed row after row.
    static func fingerprint(band pixels: [Pixel], width: Int) -> Int {
        var hasher = Hasher()
        pixels.withUnsafeBytes { bytes in
            let rowBytes = width * MemoryLayout<Pixel>.stride
            for start in stride(from: 0, to: bytes.count, by: rowBytes) {
                hasher.combine(bytes: UnsafeRawBufferPointer(rebasing: bytes[start..<(start + rowBytes)]))
            }
        }
        return hasher.finalize()
    }

    static func fingerprint(combining bandHashes: [Int]) -> Int {
        var hasher = Hasher()
        for hash in bandHashes { hasher.combine(hash) }
        return hasher.finalize()
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
