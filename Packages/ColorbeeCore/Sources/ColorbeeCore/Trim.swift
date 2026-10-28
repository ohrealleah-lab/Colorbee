/// Image ▸ Trim (FR-7, §23 2026-10-28): crops away the picture's border in one click, like Crop with the box found for
/// you. The border is transparency if a corner is transparent, otherwise the top-left pixel's color within about 2%,
/// so a JPEG's slightly uneven edges still go.
public enum Trim {
    /// How far a channel may differ from the border's color and still be border: 2% of 255.
    static let tolerance = 5

    /// The part of `picture` to keep, or nil when there's no border to trim, or nothing but border.
    public static func keptBounds(of picture: PixelBuffer) -> IntRect? {
        let bounds = picture.bounds
        guard !bounds.isEmpty else { return nil }
        let corners = [picture[0, 0], picture[bounds.maxX - 1, 0], picture[0, bounds.maxY - 1], picture[bounds.maxX - 1, bounds.maxY - 1]]
        let transparent = corners.contains { $0.a == 0 }
        let border = picture[0, 0]
        func isBorder(_ pixel: Pixel) -> Bool {
            if transparent { return pixel.a == 0 }
            return abs(Int(pixel.r) - Int(border.r)) <= tolerance && abs(Int(pixel.g) - Int(border.g)) <= tolerance
                && abs(Int(pixel.b) - Int(border.b)) <= tolerance && abs(Int(pixel.a) - Int(border.a)) <= tolerance
        }
        // Each row's first and last pixel that isn't border, on all cores.
        let rows = ParallelRows.map(bounds.height) { y -> (Int, Int)? in
            let row = picture.row(y)
            guard let first = (0..<bounds.width).first(where: { !isBorder(row[$0]) }) else { return nil }
            let last = (first..<bounds.width).last { !isBorder(row[$0]) }!
            return (first, last)
        }
        guard let top = rows.firstIndex(where: { $0 != nil }), let bottom = rows.lastIndex(where: { $0 != nil }) else { return nil }
        let spans = rows.compactMap { $0 }
        let left = spans.map(\.0).min()!, right = spans.map(\.1).max()!
        let kept = IntRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
        return kept == bounds ? nil : kept
    }
}
