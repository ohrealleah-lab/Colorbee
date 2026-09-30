import CoreGraphics

/// The document's image: a stack of equally sized layers in one color space.
public final class Canvas {
    public let size: IntSize
    public let colorSpace: CGColorSpace
    public private(set) var layers: [Layer]
    public var activeLayerIndex: Int

    public static var defaultColorSpace: CGColorSpace {
        CGColorSpace(name: CGColorSpace.displayP3)!
    }

    public init(size: IntSize, colorSpace: CGColorSpace, background: Pixel) {
        self.size = size
        self.colorSpace = colorSpace
        layers = [Layer(name: "Background", buffer: PixelBuffer(width: size.width, height: size.height, fill: background))]
        activeLayerIndex = 0
    }

    public init(colorSpace: CGColorSpace, layers: [Layer]) {
        precondition(!layers.isEmpty, "A canvas needs at least one layer")
        let size = layers[0].buffer.size
        precondition(layers.allSatisfy { $0.buffer.size == size }, "All layers must be the same size")
        self.size = size
        self.colorSpace = colorSpace
        self.layers = layers
        activeLayerIndex = layers.count - 1
    }

    public var bounds: IntRect { IntRect(size: size) }
    public var activeLayer: Layer { layers[activeLayerIndex] }

    public func layer(withID id: LayerID) -> Layer? {
        layers.first { $0.id == id }
    }

    public func insertLayer(_ layer: Layer, at index: Int) {
        precondition(layer.buffer.size == size, "Layer size doesn't match the canvas")
        layers.insert(layer, at: index)
    }

    /// All visible layers composited bottom to top, in straight alpha.
    public func flattened() -> PixelBuffer {
        let visible = layers.filter { $0.isVisible && $0.opacity > 0 }
        if visible.count == 1, visible[0].opacity >= 1 {
            return visible[0].buffer.copy()
        }
        let result = PixelBuffer(width: size.width, height: size.height)
        for layer in visible {
            let opacity = Float(layer.opacity)
            for y in 0..<size.height {
                let source = layer.buffer.row(y)
                let destination = result.row(y)
                for x in 0..<size.width {
                    destination[x] = Compositing.over(destination[x], source[x], coverage: opacity)
                }
            }
        }
        return result
    }
}
