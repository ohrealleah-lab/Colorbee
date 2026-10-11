import Synchronization

/// Remembers a per-color function's result for each color it has seen, so each different color is worked out once.
/// A photo has far fewer different colors than pixels (a 45 MP photo had 2.7% as many), so this made Adjust Photo's
/// color step about 25× faster with exactly the same result (Docs/GPU-AUDIT.md). Alpha passes through unchanged:
/// only red, green and blue are looked up.
///
/// One entry per possible color (16.7 million, 64 MB), so it's only worth it on large images. Several cores share
/// it: an entry is written whole with an atomic store, and two cores working out the same color write the same value.
final class ColorMemory: @unchecked Sendable {
    /// Below this many pixels, clearing the table costs more than it saves.
    static let minimumPixels = 2_000_000

    private static let count = 1 << 24
    /// Set on a remembered entry; the low 24 bits are the result's red, green and blue.
    private static let known: UInt32 = 1 << 24

    private let entries: UnsafeMutablePointer<Atomic<UInt32>>
    private let transform: (Pixel) -> Pixel

    init(_ transform: @escaping (Pixel) -> Pixel) {
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Self.count * MemoryLayout<UInt32>.stride,
                                                   alignment: MemoryLayout<Atomic<UInt32>>.alignment)
        raw.initializeMemory(as: UInt8.self, repeating: 0, count: Self.count * MemoryLayout<UInt32>.stride)
        // Atomic<UInt32> is laid out as a UInt32, so zeroed memory is a table of zeros.
        entries = raw.bindMemory(to: Atomic<UInt32>.self, capacity: Self.count)
        self.transform = transform
    }

    deinit {
        UnsafeMutableRawPointer(entries).deallocate()
    }

    func callAsFunction(_ pixel: Pixel) -> Pixel {
        let key = Int(pixel.r) << 16 | Int(pixel.g) << 8 | Int(pixel.b)
        let entry = entries[key].load(ordering: .relaxed)
        if entry & Self.known != 0 {
            return Pixel(r: UInt8(truncatingIfNeeded: entry >> 16), g: UInt8(truncatingIfNeeded: entry >> 8),
                         b: UInt8(truncatingIfNeeded: entry), a: pixel.a)
        }
        // Worked out as fully opaque so the result can't depend on alpha, then given the pixel's own alpha.
        let result = transform(Pixel(r: pixel.r, g: pixel.g, b: pixel.b, a: 255))
        entries[key].store(Self.known | UInt32(result.r) << 16 | UInt32(result.g) << 8 | UInt32(result.b), ordering: .relaxed)
        return Pixel(r: result.r, g: result.g, b: result.b, a: pixel.a)
    }
}
