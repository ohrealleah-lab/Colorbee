/// How many pixels have each value, for Levels' histogram and its Auto button (FR-9.5).
/// Transparent pixels are left out, since they show nothing.
public struct Histogram: Sendable, Equatable {
    /// Counts of each luminance value, 0...255.
    public private(set) var luminance = [Int](repeating: 0, count: 256)
    /// The lowest and highest value of any channel, among the pixels counted.
    public private(set) var lowestValue: UInt8?
    public private(set) var highestValue: UInt8?

    /// The pixels of `buffer` inside `selection` (or all of them).
    public init(_ buffer: PixelBuffer, selection: SelectionMask? = nil) {
        let region = (selection?.bounds ?? buffer.bounds).intersection(buffer.bounds)
        guard !region.isEmpty else { return }
        // Each band counts on its own; the bands are added up afterwards.
        let bandCount = max(1, min(16, region.height / 64))
        let bands = ParallelRows.map(bandCount) { band in
            Self.count(buffer, selection: selection, columns: region.minX..<region.maxX,
                       rows: (region.minY + region.height * band / bandCount)..<(region.minY + region.height * (band + 1) / bandCount))
        }
        for band in bands where band.low <= band.high {
            for value in 0..<256 { luminance[value] += band.counts[value] }
            lowestValue = min(lowestValue ?? 255, band.low)
            highestValue = max(highestValue ?? 0, band.high)
        }
    }

    private static func count(_ buffer: PixelBuffer, selection: SelectionMask?, columns: Range<Int>, rows: Range<Int>) -> (counts: [Int], low: UInt8, high: UInt8) {
        var counts = [Int](repeating: 0, count: 256)
        var low: UInt8 = 255, high: UInt8 = 0
        for y in rows {
            let row = buffer.row(y)
            for x in columns {
                let pixel = row[x]
                if pixel.a == 0 { continue }
                if let selection, selection[x, y] == 0 { continue }
                counts[Int(pixel.luminance)] += 1
                low = min(low, pixel.r, pixel.g, pixel.b)
                high = max(high, pixel.r, pixel.g, pixel.b)
            }
        }
        return (counts, low, high)
    }

    public var isEmpty: Bool { lowestValue == nil }
}

extension Pixel {
    /// Rec. 709 luminance, as Desaturate uses.
    var luminance: UInt8 {
        let red: Double = 0.2126 * Double(r), green: Double = 0.7152 * Double(g), blue: Double = 0.0722 * Double(b)
        return UInt8((red + green + blue).rounded())
    }
}
