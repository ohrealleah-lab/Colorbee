/// A one-click PNG export at a set size (FR-11.2).
public struct ExportPreset: Hashable, Sendable {
    public enum Size: Hashable, Sendable {
        /// Scale to this width, keeping the aspect ratio.
        case width(Int)
        /// Scale so the image fits in a square of this side, keeping the aspect ratio.
        case fitSquare(Int)
    }

    public let name: String
    public let size: Size

    public init(name: String, size: Size) {
        self.name = name
        self.size = size
    }

    public static let defaults = [
        ExportPreset(name: "Slack", size: .width(760)),
        ExportPreset(name: "1280 wide", size: .width(1280)),
        ExportPreset(name: "1920 wide", size: .width(1920)),
        ExportPreset(name: "Mobile", size: .width(750)),
        ExportPreset(name: "Square 1024", size: .fitSquare(1024)),
    ]

    /// The exported size. Images are never enlarged unless `allowEnlarging` is set.
    public func targetSize(for original: IntSize, allowEnlarging: Bool = false) -> IntSize {
        let width = Double(original.width), height = Double(original.height)
        var scale = switch size {
        case .width(let target): Double(target) / width
        case .fitSquare(let side): Double(side) / max(width, height)
        }
        if !allowEnlarging { scale = min(scale, 1) }
        // A preset's size is typed in Settings, so it can be anything; no side goes past what Colorbee edits.
        scale = min(scale, Double(ResizeSkew.maxSide) / max(width, height))
        return IntSize(width: max(1, Int((width * scale).rounded())), height: max(1, Int((height * scale).rounded())))
    }

    /// Sharp pixels for small, pixel-art-sized images; smooth scaling for everything else.
    public static func resampling(for size: IntSize) -> Resampling {
        size.width <= 256 && size.height <= 256 ? .nearestNeighbor : .smooth
    }
}
