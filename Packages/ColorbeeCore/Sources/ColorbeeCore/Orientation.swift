/// A quarter-turn rotation or a mirror flip.
public enum Orientation: CaseIterable, Sendable {
    case rotate90Clockwise
    case rotate90CounterClockwise
    case rotate180
    case flipHorizontal
    case flipVertical

    public var name: String {
        switch self {
        case .rotate90Clockwise: "Rotate 90° Clockwise"
        case .rotate90CounterClockwise: "Rotate 90° Counter-Clockwise"
        case .rotate180: "Rotate 180°"
        case .flipHorizontal: "Flip Horizontal"
        case .flipVertical: "Flip Vertical"
        }
    }

    var swapsSides: Bool { self == .rotate90Clockwise || self == .rotate90CounterClockwise }

    func transformedSize(_ size: IntSize) -> IntSize {
        swapsSides ? IntSize(width: size.height, height: size.width) : size
    }

    /// Where the source pixel (x, y) of an image of `size` lands.
    @inline(__always)
    func destination(x: Int, y: Int, in size: IntSize) -> (x: Int, y: Int) {
        switch self {
        case .rotate90Clockwise: (size.height - 1 - y, x)
        case .rotate90CounterClockwise: (y, size.width - 1 - x)
        case .rotate180: (size.width - 1 - x, size.height - 1 - y)
        case .flipHorizontal: (size.width - 1 - x, y)
        case .flipVertical: (x, size.height - 1 - y)
        }
    }
}

extension PixelBuffer {
    public func transformed(_ orientation: Orientation) -> PixelBuffer {
        let result = PixelBuffer(size: orientation.transformedSize(size))
        for y in 0..<height {
            let source = row(y)
            for x in 0..<width {
                let target = orientation.destination(x: x, y: y, in: size)
                result.row(target.y)[target.x] = source[x]
            }
        }
        return result
    }

    convenience init(size: IntSize) {
        self.init(width: size.width, height: size.height)
    }
}

extension SelectionMask {
    /// The mask transformed within its own bounds; the result's bounds start at the same top-left.
    func transformed(_ orientation: Orientation) -> SelectionMask {
        let size = bounds.size
        let newSize = orientation.transformedSize(size)
        var result = [UInt8](repeating: 0, count: values.count)
        for y in 0..<size.height {
            for x in 0..<size.width {
                let target = orientation.destination(x: x, y: y, in: size)
                result[target.y * newSize.width + target.x] = values[y * size.width + x]
            }
        }
        return SelectionMask(bounds: IntRect(x: bounds.minX, y: bounds.minY, width: newSize.width, height: newSize.height), values: result)
    }
}
