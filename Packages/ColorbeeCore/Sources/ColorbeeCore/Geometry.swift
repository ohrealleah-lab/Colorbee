public struct IntPoint: Hashable, Sendable {
    public var x: Int
    public var y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

public struct IntSize: Hashable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public struct IntRect: Hashable, Sendable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public static let zero = IntRect(x: 0, y: 0, width: 0, height: 0)

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(size: IntSize) {
        self.init(x: 0, y: 0, width: size.width, height: size.height)
    }

    /// The smallest pixel rect that covers the continuous region [minX, maxX) × [minY, maxY).
    public init(enclosingMinX minX: Double, minY: Double, maxX: Double, maxY: Double) {
        let x0 = Int(minX.rounded(.down))
        let y0 = Int(minY.rounded(.down))
        let x1 = Int(maxX.rounded(.up))
        let y1 = Int(maxY.rounded(.up))
        self.init(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
    }

    public var minX: Int { x }
    public var minY: Int { y }
    public var maxX: Int { x + width }
    public var maxY: Int { y + height }
    public var isEmpty: Bool { width <= 0 || height <= 0 }
    public var size: IntSize { IntSize(width: width, height: height) }
    public var area: Int { isEmpty ? 0 : width * height }

    public func contains(_ point: IntPoint) -> Bool {
        point.x >= minX && point.x < maxX && point.y >= minY && point.y < maxY
    }

    public func contains(_ rect: IntRect) -> Bool {
        rect.isEmpty || intersection(rect) == rect
    }

    public func intersection(_ other: IntRect) -> IntRect {
        let x0 = Swift.max(minX, other.minX)
        let y0 = Swift.max(minY, other.minY)
        let x1 = Swift.min(maxX, other.maxX)
        let y1 = Swift.min(maxY, other.maxY)
        guard x1 > x0, y1 > y0 else { return .zero }
        return IntRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    public func union(_ other: IntRect) -> IntRect {
        if isEmpty { return other }
        if other.isEmpty { return self }
        let x0 = Swift.min(minX, other.minX)
        let y0 = Swift.min(minY, other.minY)
        let x1 = Swift.max(maxX, other.maxX)
        let y1 = Swift.max(maxY, other.maxY)
        return IntRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    public func offsetBy(dx: Int, dy: Int) -> IntRect {
        IntRect(x: x + dx, y: y + dy, width: width, height: height)
    }
}

/// A continuous position, used where sub-pixel precision matters (stroke paths, view mapping).
public struct Point2D: Hashable, Sendable {
    public var x: Double
    public var y: Double

    public static let zero = Point2D(x: 0, y: 0)

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct Size2D: Hashable, Sendable {
    public var width: Double
    public var height: Double

    public static let zero = Size2D(width: 0, height: 0)

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}
