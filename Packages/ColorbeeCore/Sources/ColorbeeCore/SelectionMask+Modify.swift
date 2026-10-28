import Accelerate

/// Edit ▸ Modify Selection (FR-9.7 item 3): grow, shrink or smooth a selection by a number of pixels. Each pixel takes
/// the most (Expand) or least (Contract) selected value within a round area around it, so a soft edge moves out or in
/// and stays as soft (FR-3.4). At the canvas's edge the selection carries on, as with Feather, so a selection reaching
/// the edge stays there.
extension SelectionMask {
    /// Grown by `radius` pixels in every direction.
    public func expanded(by radius: Int, clippedTo canvasBounds: IntRect) -> SelectionMask? {
        guard radius > 0 else { return self }
        return modified(padding: radius + 1, clippedTo: canvasBounds) { $0.spread(radius, growing: true) }
    }

    /// Shrunk by `radius` pixels from every edge; nil when nothing is left.
    public func contracted(by radius: Int, clippedTo canvasBounds: IntRect) -> SelectionMask? {
        guard radius > 0 else { return self }
        return modified(padding: radius + 1, clippedTo: canvasBounds) { $0.spread(radius, growing: false) }
    }

    /// Ragged edges rounded off by `radius` pixels: notches and holes narrower than that fill in, then specks and
    /// spurs narrower than that go (a closing, then an opening).
    public func smoothed(radius: Int, clippedTo canvasBounds: IntRect) -> SelectionMask? {
        guard radius > 0 else { return self }
        return modified(padding: 2 * radius + 1, clippedTo: canvasBounds) { plane in
            plane.spread(radius, growing: true)
            plane.spread(radius, growing: false)
            plane.spread(radius, growing: false)
            plane.spread(radius, growing: true)
        }
    }

    /// The mask copied into an area `padding` wider on each side (within the canvas), changed, then trimmed. Inside
    /// the canvas the padding is unselected, so the edge shrinks there; at the canvas's edge there's nothing beyond.
    private func modified(padding: Int, clippedTo canvasBounds: IntRect, _ change: (inout MaskPlane) -> Void) -> SelectionMask? {
        let area = IntRect(x: bounds.minX - padding, y: bounds.minY - padding, width: bounds.width + 2 * padding,
                           height: bounds.height + 2 * padding).intersection(canvasBounds)
        guard !area.isEmpty else { return nil }
        var plane = MaskPlane(width: area.width, height: area.height)
        let inside = bounds.intersection(area)
        if !inside.isEmpty {
            plane.values.withUnsafeMutableBufferPointer { target in
                values.withUnsafeBufferPointer { source in
                    for y in inside.minY..<inside.maxY {
                        let from = (y - bounds.minY) * bounds.width + inside.minX - bounds.minX
                        let to = (y - area.minY) * area.width + inside.minX - area.minX
                        (target.baseAddress! + to).update(from: source.baseAddress! + from, count: inside.width)
                    }
                }
            }
        }
        change(&plane)
        return SelectionMask(bounds: area, values: plane.values).trimmed()
    }

    /// The round area as the rectangles it's made of: a disk is the union of the widest rectangle at each height, so
    /// the most (or least) over the disk is the most (or least) of the rectangles', and vImage works out each of those
    /// quickly at any size. Only the rectangles at the disk's steps are needed. Each is (half width, half height).
    static func diskRectangles(radius: Int) -> [(Int, Int)] {
        // (r + 0.5)² rather than r², so the disk is round rather than pointed at its tips: 1 px is a 3 × 3 square.
        let limit = (Double(radius) + 0.5) * (Double(radius) + 0.5)
        func halfWidth(_ h: Int) -> Int { Int((limit - Double(h * h)).squareRoot()) }
        return (0...radius).compactMap { h in
            h == radius || halfWidth(h + 1) < halfWidth(h) ? (halfWidth(h), h) : nil
        }
    }
}

/// A mask's values in a plain grid, for working on it as a whole.
private struct MaskPlane {
    let width: Int
    let height: Int
    var values: [UInt8]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        values = [UInt8](repeating: 0, count: width * height)
    }

    /// Each value replaced by the most (growing) or least selected value within `radius`, a round area.
    mutating func spread(_ radius: Int, growing: Bool) {
        if values.allSatisfy({ $0 == 0 || $0 == 255 }) { return spreadHard(radius, growing: growing) }
        spreadSoft(radius, growing: growing)
    }

    /// A hard-edged mask (the Magic Wand's, a marquee's): each pixel is selected when a selected pixel is within the
    /// round area (growing), or stays selected only when no unselected one is (shrinking). The distance to the
    /// nearest such pixel is worked out row by row, then column by column, so it takes about as long at 100 px as
    /// at 2 px; the rectangles took seconds at 100 px on a large selection.
    private mutating func spreadHard(_ radius: Int, growing: Bool) {
        let width = width, height = height
        let feature: UInt8 = growing ? 255 : 0
        let limit = (Double(radius) + 0.5) * (Double(radius) + 0.5)
        // Across each row: how far the nearest feature is, capped just past the radius, beyond which it can't count.
        let cap = radius + 1
        var across = [UInt8](repeating: UInt8(cap), count: values.count)
        values.withUnsafeBufferPointer { source in
            across.withUnsafeMutableBufferPointer { target in
                ParallelRows.forEach(0..<height) { rows in
                    for y in rows {
                        let row = y * width
                        var distance = cap
                        for x in 0..<width {
                            distance = source[row + x] == feature ? 0 : min(distance + 1, cap)
                            target[row + x] = UInt8(distance)
                        }
                        distance = cap
                        for x in stride(from: width - 1, through: 0, by: -1) {
                            distance = source[row + x] == feature ? 0 : min(distance + 1, cap)
                            target[row + x] = min(target[row + x], UInt8(distance))
                        }
                    }
                }
            }
        }
        // Down each column: the nearest feature in 2D is the least of (distance across)² + (rows apart)², the lower
        // envelope of one parabola per row (Felzenszwalb and Huttenlocher's distance transform).
        var result = [UInt8](repeating: 0, count: values.count)
        across.withUnsafeBufferPointer { source in
            result.withUnsafeMutableBufferPointer { target in
                ParallelRows.forEach(0..<width) { columns in
                    var f = [Double](repeating: 0, count: height), z = [Double](repeating: 0, count: height + 1)
                    var v = [Int](repeating: 0, count: height)
                    for x in columns {
                        for y in 0..<height {
                            let d = Double(source[y * width + x])
                            f[y] = d * d
                        }
                        var k = 0
                        v[0] = 0
                        z[0] = -.infinity
                        z[1] = .infinity
                        for q in 1..<max(height, 1) {
                            var crossing: Double
                            repeat {
                                let p = v[k]
                                crossing = ((f[q] + Double(q * q)) - (f[p] + Double(p * p))) / Double(2 * (q - p))
                                if crossing <= z[k] { k -= 1 } else { break }
                            } while k >= 0
                            k += 1
                            v[k] = q
                            z[k] = crossing
                            z[k + 1] = .infinity
                        }
                        k = 0
                        for y in 0..<height {
                            while z[k + 1] < Double(y) { k += 1 }
                            let p = v[k], dy = Double(y - p)
                            let near = f[p] + dy * dy <= limit
                            target[y * width + x] = near == growing ? 255 : 0
                        }
                    }
                }
            }
        }
        values = result
    }

    /// A soft-edged mask: the most or least value over the round area, from the rectangles it's made of.
    private mutating func spreadSoft(_ radius: Int, growing: Bool) {
        let rectangles = SelectionMask.diskRectangles(radius: radius)
        var result = [UInt8](repeating: 0, count: values.count)
        var pass = result
        for (index, (halfWidth, halfHeight)) in rectangles.enumerated() {
            if index == 0 {
                filter(into: &result, halfWidth: halfWidth, halfHeight: halfHeight, growing: growing)
            } else {
                filter(into: &pass, halfWidth: halfWidth, halfHeight: halfHeight, growing: growing)
                for i in result.indices { result[i] = growing ? max(result[i], pass[i]) : min(result[i], pass[i]) }
            }
        }
        values = result
    }

    /// The most or least value within a rectangle around each pixel. Pixels beyond the grid are left out of each area
    /// rather than counted, which is what lets the selection carry on at the canvas's edge.
    private func filter(into target: inout [UInt8], halfWidth: Int, halfHeight: Int, growing: Bool) {
        var source = values
        let height = vImagePixelCount(height), width = vImagePixelCount(width), rowBytes = self.width
        let kernelHeight = vImagePixelCount(2 * halfHeight + 1), kernelWidth = vImagePixelCount(2 * halfWidth + 1)
        source.withUnsafeMutableBytes { from in
            target.withUnsafeMutableBytes { to in
                var input = vImage_Buffer(data: from.baseAddress, height: height, width: width, rowBytes: rowBytes)
                var output = vImage_Buffer(data: to.baseAddress, height: height, width: width, rowBytes: rowBytes)
                if growing {
                    vImageMax_Planar8(&input, &output, nil, 0, 0, kernelHeight, kernelWidth, vImage_Flags(kvImageNoFlags))
                } else {
                    vImageMin_Planar8(&input, &output, nil, 0, 0, kernelHeight, kernelWidth, vImage_Flags(kvImageNoFlags))
                }
            }
        }
    }
}

/// The Edit menu's ways of changing a selection's edge by a number of pixels, which share one sheet.
public enum SelectionModification: Sendable, CaseIterable {
    case feather, expand, contract, smooth

    public var title: String {
        switch self {
        case .feather: "Feather Selection"
        case .expand: "Expand Selection"
        case .contract: "Contract Selection"
        case .smooth: "Smooth Selection"
        }
    }

    /// Where the sheet's slider starts: Feather's 10 px as before; the others 2 px (Leah, 2026-10-28).
    public var startingRadius: Int { self == .feather ? 10 : 2 }

    /// `mask` changed by `radius` pixels (1...100); nil when nothing is left selected.
    public func applied(to mask: SelectionMask, radius: Int, clippedTo canvasBounds: IntRect) -> SelectionMask? {
        switch self {
        case .feather: mask.feathered(radius: Double(radius), clippedTo: canvasBounds)
        case .expand: mask.expanded(by: radius, clippedTo: canvasBounds)
        case .contract: mask.contracted(by: radius, clippedTo: canvasBounds)
        case .smooth: mask.smoothed(radius: radius, clippedTo: canvasBounds)
        }
    }
}
