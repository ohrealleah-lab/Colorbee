import Foundation

public struct LayerID: Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public final class Layer {
    public let id: LayerID
    public var name: String
    public var isVisible: Bool
    public var opacity: Double
    public var blendMode: BlendMode = .normal
    /// A locked layer refuses every pixel change, move, merge and delete (FR-8.2).
    public var isLocked = false
    /// Set for an adjustment layer (FR-8.4): it changes how the layers below look and holds no pixels.
    public var adjustment: Effect?

    /// The adjustments an adjustment layer can be.
    public static func isAdjustable(_ effect: Effect) -> Bool {
        switch effect {
        case .invert, .desaturate, .brightnessContrast, .hueSaturation, .gaussianBlur, .sharpen,
             .levels, .curves, .sepia, .posterize: true
        case .pixelate, .solidFill, .addNoise, .motionBlur, .emboss, .vignette: false
        }
    }
    /// An adjustment layer, or a layer never painted on: its buffer is all clear and takes no memory,
    /// so whole-image changes give it a new empty buffer rather than touching (and filling) every page.
    var holdsNoPixels: Bool { adjustment != nil || buffer.isUntouched }

    /// Replaced (never resized in place) when the canvas size changes.
    public internal(set) var buffer: PixelBuffer

    public init(name: String, buffer: PixelBuffer, id: LayerID = LayerID()) {
        self.id = id
        self.name = name
        self.buffer = buffer
        isVisible = true
        opacity = 1
    }
}
