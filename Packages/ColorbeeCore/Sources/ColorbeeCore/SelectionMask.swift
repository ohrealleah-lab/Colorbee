import Accelerate
import Synchronization

private let nextRevision = Atomic<UInt64>(1)

public enum SelectionCombineMode: Sendable {
    case replace
    case add
    case subtract
    case intersect
}

public enum SelectionShape: Sendable {
    case rectangle
    case ellipse
}

/// Which pixels are selected, and how much: 0 not at all, 255 fully, and in between for a soft edge (a feathered
/// selection or Select Subject; FR-3.4). Stored only for `bounds`; everything outside `bounds` is unselected.
/// Masks are immutable; `revision` identifies each one.
public struct SelectionMask: Sendable {
    public let bounds: IntRect
    public let values: [UInt8]
    public let revision: UInt64

    init(bounds: IntRect, values: [UInt8]) {
        precondition(values.count == bounds.area, "Mask values must cover the bounds")
        self.bounds = bounds
        self.values = values
        revision = nextRevision.add(1, ordering: .relaxed).oldValue
    }

    /// A fully selected rectangle, clipped to `canvasBounds`.
    public static func rectangle(_ rect: IntRect, clippedTo canvasBounds: IntRect) -> SelectionMask? {
        let bounds = rect.intersection(canvasBounds)
        guard !bounds.isEmpty else { return nil }
        return SelectionMask(bounds: bounds, values: [UInt8](repeating: 255, count: bounds.area))
    }

    /// An ellipse inscribed in `rect`, hard-edged, clipped to `canvasBounds`.
    public static func ellipse(in rect: IntRect, clippedTo canvasBounds: IntRect) -> SelectionMask? {
        guard !rect.isEmpty else { return nil }
        let radiusX = Double(rect.width) / 2
        let radiusY = Double(rect.height) / 2
        let centerX = Double(rect.minX) + radiusX
        let centerY = Double(rect.minY) + radiusY
        return build(in: rect.intersection(canvasBounds)) { x, y in
            let dx = (Double(x) + 0.5 - centerX) / radiusX
            let dy = (Double(y) + 0.5 - centerY) / radiusY
            return dx * dx + dy * dy <= 1
        }
    }

    /// A polygon filled with the even-odd rule, sampled at pixel centers.
    public static func polygon(_ points: [Point2D], clippedTo canvasBounds: IntRect) -> SelectionMask? {
        guard points.count >= 3 else { return nil }
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let area = IntRect(enclosingMinX: xs.min()!, minY: ys.min()!, maxX: xs.max()!, maxY: ys.max()!)
            .intersection(canvasBounds)
        guard !area.isEmpty else { return nil }

        var values = [UInt8](repeating: 0, count: area.area)
        for y in area.minY..<area.maxY {
            let sampleY = Double(y) + 0.5
            var crossings: [Double] = []
            for index in points.indices {
                let a = points[index]
                let b = points[(index + 1) % points.count]
                if (a.y <= sampleY) != (b.y <= sampleY) {
                    crossings.append(a.x + (sampleY - a.y) / (b.y - a.y) * (b.x - a.x))
                }
            }
            crossings.sort()
            let rowStart = (y - area.minY) * area.width
            var pair = 0
            while pair + 1 < crossings.count {
                let first = max(area.minX, Int((crossings[pair] - 0.5).rounded(.up)))
                let last = min(area.maxX - 1, Int((crossings[pair + 1] - 0.5).rounded(.up)) - 1)
                if first <= last {
                    for x in first...last { values[rowStart + x - area.minX] = 255 }
                }
                pair += 2
            }
        }
        return SelectionMask(bounds: area, values: values).trimmed()
    }

    public func contains(_ point: IntPoint) -> Bool {
        self[point.x, point.y] > 0
    }

    public subscript(x: Int, y: Int) -> UInt8 {
        guard bounds.contains(IntPoint(x: x, y: y)) else { return 0 }
        return values[(y - bounds.minY) * bounds.width + (x - bounds.minX)]
    }

    /// Each separate (8-connected) area of the selection as its own mask.
    public func connectedRegions() -> [SelectionMask] {
        // A fully selected mask (a rectangle) is one region; labelling 64 megapixels one by one takes seconds.
        if !values.contains(0) { return [self] }
        let width = bounds.width, height = bounds.height
        var labelled = [Bool](repeating: false, count: values.count)
        var regions: [SelectionMask] = []
        for start in values.indices where values[start] > 0 && !labelled[start] {
            var members: [Int] = []
            var pending = [start]
            labelled[start] = true
            var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min
            while let index = pending.popLast() {
                members.append(index)
                let x = index % width, y = index / width
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                for ny in max(0, y - 1)...min(height - 1, y + 1) {
                    for nx in max(0, x - 1)...min(width - 1, x + 1) {
                        let neighbor = ny * width + nx
                        if values[neighbor] > 0 && !labelled[neighbor] {
                            labelled[neighbor] = true
                            pending.append(neighbor)
                        }
                    }
                }
            }
            let regionBounds = IntRect(x: bounds.minX + minX, y: bounds.minY + minY, width: maxX - minX + 1, height: maxY - minY + 1)
            var regionValues = [UInt8](repeating: 0, count: regionBounds.area)
            for index in members {
                regionValues[(index / width - minY) * regionBounds.width + (index % width - minX)] = values[index]
            }
            regions.append(SelectionMask(bounds: regionBounds, values: regionValues))
        }
        return regions
    }

    public func translatedBy(dx: Int, dy: Int) -> SelectionMask {
        SelectionMask(bounds: bounds.offsetBy(dx: dx, dy: dy), values: values)
    }

    /// Everything in `canvasBounds` that this mask doesn't select; a half-selected pixel stays half selected.
    public func inverted(in canvasBounds: IntRect) -> SelectionMask? {
        SelectionMask.build(in: canvasBounds) { x, y in 255 - self[x, y] }
    }

    /// Combines `new` with `existing`. Returns nil when nothing is left selected. With soft edges (FR-3.4), Add keeps
    /// the stronger of the two at each pixel, Subtract takes away as much as `new` selects, and Intersect keeps the
    /// weaker.
    public static func combine(_ existing: SelectionMask?, with new: SelectionMask?, mode: SelectionCombineMode) -> SelectionMask? {
        switch mode {
        case .replace:
            return new
        case .add:
            guard let existing else { return new }
            guard let new else { return existing }
            return build(in: existing.bounds.union(new.bounds)) { x, y in max(existing[x, y], new[x, y]) }
        case .subtract:
            guard let existing else { return nil }
            guard let new else { return existing }
            return build(in: existing.bounds) { x, y in
                UInt8((Int(existing[x, y]) * (255 - Int(new[x, y])) + 127) / 255)
            }
        case .intersect:
            guard let existing, let new else { return nil }
            return build(in: existing.bounds.intersection(new.bounds)) { x, y in min(existing[x, y], new[x, y]) }
        }
    }

    /// Whether any pixel is only partly selected.
    public var isSoft: Bool {
        values.contains { $0 != 0 && $0 != 255 }
    }

    /// Every partly selected pixel fully selected. Redaction uses this, so no part of a secret is left half-visible
    /// (FR-3.4).
    public func hardened() -> SelectionMask {
        isSoft ? SelectionMask(bounds: bounds, values: values.map { $0 > 0 ? 255 : 0 }) : self
    }

    /// The edge softened by `radius` pixels (Edit ▸ Feather…, and the selection tools' Feather): a Gaussian blur of
    /// the mask, about `radius` wide each way. At the canvas's edge the selection carries on, so a selection reaching
    /// the edge stays fully selected there.
    public func feathered(radius: Double, clippedTo canvasBounds: IntRect) -> SelectionMask? {
        guard radius >= 0.5 else { return self }
        let sigma = radius / 2
        // Three box blurs come close to a Gaussian; each box is this wide.
        var box = Int((4 * sigma * sigma + 1).squareRoot())
        if box % 2 == 0 { box += 1 }
        let reach = 3 * (box / 2) + 1
        let area = IntRect(x: bounds.minX - reach, y: bounds.minY - reach, width: bounds.width + 2 * reach, height: bounds.height + 2 * reach)
            .intersection(canvasBounds)
        guard !area.isEmpty else { return nil }
        var first = [UInt8](repeating: 0, count: area.area)
        // Whole rows at a time: on a big selection, pixel by pixel took longer than the blurs (review O, finding 12).
        let inside = bounds.intersection(area)
        if !inside.isEmpty {
            first.withUnsafeMutableBufferPointer { target in
                values.withUnsafeBufferPointer { source in
                    for y in inside.minY..<inside.maxY {
                        let from = (y - bounds.minY) * bounds.width + inside.minX - bounds.minX
                        let to = (y - area.minY) * area.width + inside.minX - area.minX
                        (target.baseAddress! + to).update(from: source.baseAddress! + from, count: inside.width)
                    }
                }
            }
        }
        var second = [UInt8](repeating: 0, count: area.area)
        first.withUnsafeMutableBytes { a in
            second.withUnsafeMutableBytes { b in
                var one = vImage_Buffer(data: a.baseAddress, height: vImagePixelCount(area.height), width: vImagePixelCount(area.width), rowBytes: area.width)
                var two = vImage_Buffer(data: b.baseAddress, height: vImagePixelCount(area.height), width: vImagePixelCount(area.width), rowBytes: area.width)
                let size = UInt32(box)
                vImageBoxConvolve_Planar8(&one, &two, nil, 0, 0, size, size, 0, vImage_Flags(kvImageEdgeExtend))
                vImageBoxConvolve_Planar8(&two, &one, nil, 0, 0, size, size, 0, vImage_Flags(kvImageEdgeExtend))
                vImageBoxConvolve_Planar8(&one, &two, nil, 0, 0, size, size, 0, vImage_Flags(kvImageEdgeExtend))
            }
        }
        return SelectionMask(bounds: area, values: second).trimmed()
    }

    /// The same selection with its bounds shrunk to the selected pixels, or nil if none are selected.
    public func trimmed() -> SelectionMask? {
        var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min
        for row in 0..<bounds.height {
            let start = row * bounds.width
            for column in 0..<bounds.width where values[start + column] > 0 {
                minX = min(minX, column)
                maxX = max(maxX, column)
                minY = min(minY, row)
                maxY = max(maxY, row)
            }
        }
        guard minX <= maxX else { return nil }
        if minX == 0, minY == 0, maxX == bounds.width - 1, maxY == bounds.height - 1 { return self }
        let trimmedBounds = IntRect(x: bounds.minX + minX, y: bounds.minY + minY, width: maxX - minX + 1, height: maxY - minY + 1)
        var trimmedValues = [UInt8](repeating: 0, count: trimmedBounds.area)
        for row in 0..<trimmedBounds.height {
            let from = (minY + row) * bounds.width + minX
            trimmedValues.replaceSubrange((row * trimmedBounds.width)..<((row + 1) * trimmedBounds.width), with: values[from..<(from + trimmedBounds.width)])
        }
        return SelectionMask(bounds: trimmedBounds, values: trimmedValues)
    }

    private static func build(in area: IntRect, _ isSelected: (Int, Int) -> Bool) -> SelectionMask? {
        build(in: area) { x, y in isSelected(x, y) ? 255 : 0 }
    }

    /// A mask from how much each pixel of `area` is selected.
    private static func build(in area: IntRect, _ amount: (Int, Int) -> UInt8) -> SelectionMask? {
        guard !area.isEmpty else { return nil }
        var values = [UInt8](repeating: 0, count: area.area)
        var any = false
        for y in area.minY..<area.maxY {
            let rowStart = (y - area.minY) * area.width
            for x in area.minX..<area.maxX {
                let value = amount(x, y)
                guard value > 0 else { continue }
                values[rowStart + x - area.minX] = value
                any = true
            }
        }
        return any ? SelectionMask(bounds: area, values: values).trimmed() : nil
    }
}
