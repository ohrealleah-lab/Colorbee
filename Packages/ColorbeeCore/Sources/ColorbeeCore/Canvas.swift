import CoreGraphics

/// The document: a stack of equally sized layers in one color space, plus the current selection.
public final class Canvas {
    public let size: IntSize
    public let colorSpace: CGColorSpace
    public private(set) var layers: [Layer]
    public var activeLayerIndex: Int
    public var selection: SelectionState = .none
    /// Whether the bottom layer is transparent rather than a solid background (FR-2.2).
    public var hasTransparentBackground: Bool

    public static var defaultColorSpace: CGColorSpace {
        CGColorSpace(name: CGColorSpace.displayP3)!
    }

    public init(size: IntSize, colorSpace: CGColorSpace, background: Pixel) {
        self.size = size
        self.colorSpace = colorSpace
        layers = [Layer(name: "Background", buffer: PixelBuffer(width: size.width, height: size.height, fill: background))]
        activeLayerIndex = 0
        hasTransparentBackground = background.a < 255
    }

    public init(colorSpace: CGColorSpace, layers: [Layer], hasTransparentBackground: Bool) {
        precondition(!layers.isEmpty, "A canvas needs at least one layer")
        let size = layers[0].buffer.size
        precondition(layers.allSatisfy { $0.buffer.size == size }, "All layers must be the same size")
        self.size = size
        self.colorSpace = colorSpace
        self.layers = layers
        self.hasTransparentBackground = hasTransparentBackground
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

    /// What erasing or lifting pixels leaves behind on `layer`: Color 2 on a solid background, otherwise transparency.
    public func vacatedFill(for layer: Layer, color2: Pixel) -> Pixel {
        layer.id == layers.first?.id && !hasTransparentBackground ? color2 : .clear
    }

    /// All visible layers composited bottom to top in straight alpha, with any floating selection
    /// shown above its layer.
    public func flattened(transparentKey: Pixel? = nil) -> PixelBuffer {
        let visible = layers.filter { $0.isVisible && $0.opacity > 0 }
        let floating = selection.floating
        if floating == nil, visible.count == 1, visible[0].opacity >= 1 {
            return visible[0].buffer.copy()
        }
        let result = PixelBuffer(width: size.width, height: size.height)
        for layer in visible {
            composite(layer.buffer, at: IntPoint(x: 0, y: 0), opacity: Float(layer.opacity), into: result)
            if let floating, floating.layerID == layer.id {
                let pixels = floating.rendered(using: .nearestNeighbor, transparentKey: transparentKey)
                composite(pixels, at: IntPoint(x: floating.destination.minX, y: floating.destination.minY),
                          opacity: Float(layer.opacity), into: result)
            }
        }
        return result
    }

    private func composite(_ source: PixelBuffer, at origin: IntPoint, opacity: Float, into result: PixelBuffer) {
        let target = IntRect(x: origin.x, y: origin.y, width: source.width, height: source.height).intersection(result.bounds)
        guard !target.isEmpty else { return }
        for y in target.minY..<target.maxY {
            let sourceRow = source.row(y - origin.y)
            let destination = result.row(y)
            for x in target.minX..<target.maxX {
                destination[x] = Compositing.over(destination[x], sourceRow[x - origin.x], coverage: opacity)
            }
        }
    }
}
