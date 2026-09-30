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
    public let buffer: PixelBuffer

    public init(name: String, buffer: PixelBuffer, id: LayerID = LayerID()) {
        self.id = id
        self.name = name
        self.buffer = buffer
        isVisible = true
        opacity = 1
    }
}
