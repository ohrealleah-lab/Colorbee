import Foundation

/// The Resize and Skew dialog's settings (FR-7.2): a new size, then a slant in each direction.
public struct ResizeSkew: Equatable, Sendable {
    /// The size after resizing, before skewing.
    public var size: IntSize
    /// Degrees, −89...89. Positive leans the top to the right, like italic text.
    public var horizontalSkew: Double
    /// Degrees, −89...89. Positive raises the right side.
    public var verticalSkew: Double
    public var resampling: Resampling

    /// A steep skew can make an enormous image, so results past these limits are refused.
    public static let maxSide = 30_000
    public static let maxArea = 256_000_000

    public init(size: IntSize, horizontalSkew: Double = 0, verticalSkew: Double = 0, resampling: Resampling) {
        self.size = size
        self.horizontalSkew = min(89, max(-89, horizontalSkew))
        self.verticalSkew = min(89, max(-89, verticalSkew))
        self.resampling = resampling
    }

    private var horizontalSlope: Double { tan(horizontalSkew * .pi / 180) }
    private var verticalSlope: Double { tan(verticalSkew * .pi / 180) }

    /// The size after resizing and skewing.
    public var resultSize: IntSize {
        let width = size.width + Self.extent(horizontalSlope, over: size.height)
        let height = size.height + Self.extent(verticalSlope, over: width)
        return IntSize(width: width, height: height)
    }

    public var fits: Bool {
        let result = resultSize
        return size.width > 0 && size.height > 0 && result.width <= Self.maxSide && result.height <= Self.maxSide
            && result.width * result.height <= Self.maxArea
    }

    public func changes(_ original: IntSize) -> Bool {
        size != original || horizontalSkew != 0 || verticalSkew != 0
    }

    /// The name of the undo step: what actually changed.
    public func actionName(from original: IntSize) -> String {
        let skews = horizontalSkew != 0 || verticalSkew != 0
        return switch (size != original, skews) {
        case (true, true): "Resize and Skew"
        case (false, true): "Skew"
        default: "Resize"
        }
    }

    /// How many pixels a slant adds across `length` pixels.
    private static func extent(_ slope: Double, over length: Int) -> Int {
        Int((abs(slope) * Double(max(0, length - 1))).rounded(.up))
    }

    /// The offset of row (or column) `index` of `count`, kept non-negative whichever way it leans.
    fileprivate static func shift(_ slope: Double, index: Int, count: Int) -> Double {
        slope * Double(count - 1 - index) - min(0, slope * Double(count - 1))
    }

    fileprivate var slopes: (horizontal: Double, vertical: Double) { (horizontalSlope, verticalSlope) }
}

extension PixelBuffer {
    /// Resized, then skewed. Areas the slant exposes are transparent.
    public func resizedAndSkewed(_ settings: ResizeSkew) -> PixelBuffer {
        let slopes = settings.slopes
        var result = resampled(to: settings.size, using: settings.resampling)
        if slopes.horizontal != 0 { result = result.skewed(slopes.horizontal, horizontally: true, resampling: settings.resampling) }
        if slopes.vertical != 0 { result = result.skewed(slopes.vertical, horizontally: false, resampling: settings.resampling) }
        return result
    }

    /// Slides each row sideways (or each column up or down) in proportion to its position.
    private func skewed(_ slope: Double, horizontally: Bool, resampling: Resampling) -> PixelBuffer {
        let lines = horizontally ? height : width
        let length = horizontally ? width : height
        let extra = Int((abs(slope) * Double(max(0, lines - 1))).rounded(.up))
        let result = horizontally
            ? PixelBuffer(width: width + extra, height: height)
            : PixelBuffer(width: width, height: height + extra)
        for line in 0..<lines {
            let shift = ResizeSkew.shift(slope, index: line, count: lines)
            for target in 0..<(length + extra) {
                let source = Double(target) - shift
                let pixel: Pixel
                switch resampling {
                case .nearestNeighbor:
                    let nearest = Int((source + 0.5).rounded(.down))
                    pixel = nearest >= 0 && nearest < length ? (horizontally ? self[nearest, line] : self[line, nearest]) : .clear
                case .smooth:
                    let lower = Int(source.rounded(.down))
                    let fraction = source - Double(lower)
                    func sample(_ index: Int) -> Pixel {
                        guard index >= 0, index < length else { return .clear }
                        return horizontally ? self[index, line] : self[line, index]
                    }
                    pixel = Self.blend(sample(lower), sample(lower + 1), fraction)
                }
                if horizontally { result[target, line] = pixel } else { result[line, target] = pixel }
            }
        }
        return result
    }

    /// Linear blend in premultiplied space, so transparent neighbors don't darken the edge.
    private static func blend(_ a: Pixel, _ b: Pixel, _ t: Double) -> Pixel {
        let wa = Double(a.a) * (1 - t), wb = Double(b.a) * t
        let alpha = wa + wb
        guard alpha > 0 else { return .clear }
        func channel(_ x: UInt8, _ y: UInt8) -> UInt8 {
            UInt8(min(255, ((Double(x) * wa + Double(y) * wb) / alpha).rounded()))
        }
        return Pixel(r: channel(a.r, b.r), g: channel(a.g, b.g), b: channel(a.b, b.b), a: UInt8(min(255, alpha.rounded())))
    }
}

extension SelectionMask {
    /// The mask put through the same resize and skew as its pixels, kept hard-edged.
    func resizedAndSkewed(_ settings: ResizeSkew) -> SelectionMask {
        let shape = PixelBuffer(width: bounds.width, height: bounds.height)
        for y in 0..<bounds.height {
            for x in 0..<bounds.width {
                shape[x, y] = Pixel(r: 255, g: 255, b: 255, a: self[bounds.minX + x, bounds.minY + y])
            }
        }
        let result = shape.resizedAndSkewed(settings)
        var values = [UInt8](repeating: 0, count: result.bounds.area)
        for y in 0..<result.height {
            for x in 0..<result.width where result[x, y].a >= 128 {
                values[y * result.width + x] = 255
            }
        }
        return SelectionMask(bounds: IntRect(size: result.size), values: values)
    }
}
