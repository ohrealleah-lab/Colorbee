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

/// Which pixels are selected. Values are 0 (not selected) or 255 (selected), stored only for `bounds`;
/// everything outside `bounds` is unselected. Masks are immutable; `revision` identifies each one.
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

    public func translatedBy(dx: Int, dy: Int) -> SelectionMask {
        SelectionMask(bounds: bounds.offsetBy(dx: dx, dy: dy), values: values)
    }

    /// Everything in `canvasBounds` that this mask doesn't select.
    public func inverted(in canvasBounds: IntRect) -> SelectionMask? {
        SelectionMask.build(in: canvasBounds) { x, y in self[x, y] == 0 }
    }

    /// Combines `new` with `existing`. Returns nil when nothing is left selected.
    public static func combine(_ existing: SelectionMask?, with new: SelectionMask?, mode: SelectionCombineMode) -> SelectionMask? {
        switch mode {
        case .replace:
            return new
        case .add:
            guard let existing else { return new }
            guard let new else { return existing }
            return build(in: existing.bounds.union(new.bounds)) { x, y in existing[x, y] > 0 || new[x, y] > 0 }
        case .subtract:
            guard let existing else { return nil }
            guard let new else { return existing }
            return build(in: existing.bounds) { x, y in existing[x, y] > 0 && new[x, y] == 0 }
        case .intersect:
            guard let existing, let new else { return nil }
            return build(in: existing.bounds.intersection(new.bounds)) { x, y in existing[x, y] > 0 && new[x, y] > 0 }
        }
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
        return SelectionMask.build(in: trimmedBounds) { x, y in self[x, y] > 0 }
    }

    private static func build(in area: IntRect, _ isSelected: (Int, Int) -> Bool) -> SelectionMask? {
        guard !area.isEmpty else { return nil }
        var values = [UInt8](repeating: 0, count: area.area)
        var any = false
        for y in area.minY..<area.maxY {
            let rowStart = (y - area.minY) * area.width
            for x in area.minX..<area.maxX where isSelected(x, y) {
                values[rowStart + x - area.minX] = 255
                any = true
            }
        }
        return any ? SelectionMask(bounds: area, values: values).trimmed() : nil
    }
}
