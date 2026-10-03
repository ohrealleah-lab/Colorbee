import Foundation

public struct LayerID: Hashable, Sendable {
    public let rawValue: UUID

    public init() {
        rawValue = UUID()
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
