/// The eight resize handles around a selection (FR-3.3).
public enum SelectionHandle: CaseIterable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    /// Where the handle sits on `rect`, in image coordinates.
    public func point(on rect: IntRect) -> Point2D {
        let midX = Double(rect.minX) + Double(rect.width) / 2
        let midY = Double(rect.minY) + Double(rect.height) / 2
        let minX = Double(rect.minX), maxX = Double(rect.maxX), minY = Double(rect.minY), maxY = Double(rect.maxY)
        switch self {
        case .topLeft: return Point2D(x: minX, y: minY)
        case .top: return Point2D(x: midX, y: minY)
        case .topRight: return Point2D(x: maxX, y: minY)
        case .right: return Point2D(x: maxX, y: midY)
        case .bottomRight: return Point2D(x: maxX, y: maxY)
        case .bottom: return Point2D(x: midX, y: maxY)
        case .bottomLeft: return Point2D(x: minX, y: maxY)
        case .left: return Point2D(x: minX, y: midY)
        }
    }

    var movesLeft: Bool { self == .topLeft || self == .left || self == .bottomLeft }
    var movesRight: Bool { self == .topRight || self == .right || self == .bottomRight }
    var movesTop: Bool { self == .topLeft || self == .top || self == .topRight }
    var movesBottom: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }
    var isCorner: Bool { (movesLeft || movesRight) && (movesTop || movesBottom) }

    /// `original` after dragging this handle by `delta` image pixels. Stretching is free; with
    /// `keepProportions` the aspect ratio is kept (edge handles grow the other side around the center).
    /// The result is never smaller than 1×1 and never flips over.
    public func resize(_ original: IntRect, by delta: Point2D, keepProportions: Bool) -> IntRect {
        var minX = Double(original.minX), maxX = Double(original.maxX)
        var minY = Double(original.minY), maxY = Double(original.maxY)
        if movesLeft { minX = min(minX + delta.x, maxX - 1) }
        if movesRight { maxX = max(maxX + delta.x, minX + 1) }
        if movesTop { minY = min(minY + delta.y, maxY - 1) }
        if movesBottom { maxY = max(maxY + delta.y, minY + 1) }

        if keepProportions {
            let width = Double(original.width), height = Double(original.height)
            if isCorner {
                // Follow whichever axis the pointer moved more, so corners can shrink as well as grow.
                let scaleX = (maxX - minX) / width, scaleY = (maxY - minY) / height
                let scale = abs(scaleX - 1) >= abs(scaleY - 1) ? scaleX : scaleY
                let newWidth = max(1, width * scale), newHeight = max(1, height * scale)
                if movesLeft { minX = maxX - newWidth } else { maxX = minX + newWidth }
                if movesTop { minY = maxY - newHeight } else { maxY = minY + newHeight }
            } else if movesLeft || movesRight {
                let newHeight = max(1, height * (maxX - minX) / width)
                let centerY = (minY + maxY) / 2
                minY = centerY - newHeight / 2
                maxY = centerY + newHeight / 2
            } else {
                let newWidth = max(1, width * (maxY - minY) / height)
                let centerX = (minX + maxX) / 2
                minX = centerX - newWidth / 2
                maxX = centerX + newWidth / 2
            }
        }
        let x = Int(minX.rounded()), y = Int(minY.rounded())
        return IntRect(x: x, y: y, width: max(1, Int(maxX.rounded()) - x), height: max(1, Int(maxY.rounded()) - y))
    }
}
