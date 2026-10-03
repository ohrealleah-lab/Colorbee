import CoreGraphics
import simd

/// The document: a stack of equally sized layers in one color space, plus the current selection.
public final class Canvas {
    public private(set) var size: IntSize
    public let colorSpace: CGColorSpace
    public private(set) var layers: [Layer]
    public var activeLayerIndex: Int
    public var selection: SelectionState = .none
    /// Whether the bottom layer is transparent rather than a solid background (FR-2.2).
    public var hasTransparentBackground: Bool
    /// The original bottom layer. Erasing it leaves Color 2 while it's still at the bottom of a solid image.
    public private(set) var backgroundLayerID: LayerID?

    public static var defaultColorSpace: CGColorSpace {
        CGColorSpace(name: CGColorSpace.displayP3)!
    }

    public init(size: IntSize, colorSpace: CGColorSpace, background: Pixel) {
        self.size = size
        self.colorSpace = colorSpace
        layers = [Layer(name: "Background", buffer: PixelBuffer(width: size.width, height: size.height, fill: background))]
        activeLayerIndex = 0
        hasTransparentBackground = background.a < 255
        backgroundLayerID = layers[0].id
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
        backgroundLayerID = layers[0].id
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

    /// Swaps in new pixel buffers of `size` for every layer. Used by geometry changes and their undo.
    func replaceContents(size: IntSize, buffers: [LayerID: PixelBuffer]) {
        precondition(layers.allSatisfy { buffers[$0.id]?.size == size }, "Every layer needs a buffer of the new size")
        self.size = size
        for layer in layers {
            layer.buffer = buffers[layer.id]!
        }
    }

    var currentGeometry: GeometryChange {
        GeometryChange(size: size, buffers: Dictionary(uniqueKeysWithValues: layers.map { ($0.id, $0.buffer) }))
    }

    /// What erasing or lifting pixels leaves behind on `layer`: Color 2 on a solid background, otherwise transparency.
    public func vacatedFill(for layer: Layer, color2: Pixel) -> Pixel {
        layer.id == backgroundLayerID && layer.id == layers.first?.id && !hasTransparentBackground ? color2 : .clear
    }

    // MARK: Layer stack

    /// Every layer's properties and buffer, for undoing changes to the stack (FR-8).
    var layerStackState: LayerStackState {
        LayerStackState(
            records: layers.map {
                LayerStackState.Record(layer: $0, name: $0.name, isVisible: $0.isVisible, opacity: $0.opacity,
                                       blendMode: $0.blendMode, isLocked: $0.isLocked, adjustment: $0.adjustment, buffer: $0.buffer)
            },
            activeIndex: activeLayerIndex
        )
    }

    func restore(_ state: LayerStackState) {
        layers = state.records.map { record in
            let layer = record.layer
            layer.name = record.name
            layer.isVisible = record.isVisible
            layer.opacity = record.opacity
            layer.blendMode = record.blendMode
            layer.isLocked = record.isLocked
            layer.adjustment = record.adjustment
            layer.buffer = record.buffer
            return layer
        }
        activeLayerIndex = min(max(0, state.activeIndex), layers.count - 1)
    }

    func removeLayer(at index: Int) {
        precondition(layers.count > 1, "A canvas needs at least one layer")
        layers.remove(at: index)
        activeLayerIndex = min(activeLayerIndex, layers.count - 1)
    }

    func moveLayer(from source: Int, to destination: Int) {
        let layer = layers.remove(at: source)
        layers.insert(layer, at: destination)
    }

    /// `layers` composited bottom to top with their blend modes and opacity, onto `base` if given.
    /// An adjustment layer changes everything composited so far. The floating selection is drawn just
    /// above its layer, as on screen.
    func composite(_ stack: [Layer], onto base: PixelBuffer? = nil, transparentKey: Pixel? = nil) -> PixelBuffer {
        var current = base
        var segment: [Layer] = []
        for layer in stack {
            if let adjustment = layer.adjustment {
                let below = segment.isEmpty && current != nil ? current! : compositePixels(segment, onto: current, transparentKey: transparentKey)
                current = Compositing.adjust(below, by: adjustment, opacity: layer.opacity, mode: layer.blendMode)
                segment = []
            } else {
                segment.append(layer)
            }
        }
        if segment.isEmpty, let current, current !== base { return current }
        return compositePixels(segment, onto: current, transparentKey: transparentKey)
    }

    /// Pixel layers only, composited row by row in premultiplied floats.
    private func compositePixels(_ stack: [Layer], onto base: PixelBuffer?, transparentKey: Pixel?) -> PixelBuffer {
        let result = PixelBuffer(width: size.width, height: size.height)
        let floating = selection.floating
        let floatingPixels = floating.flatMap { floating in
            stack.contains { $0.id == floating.layerID } ? floating.rendered(using: .nearestNeighbor, transparentKey: transparentKey) : nil
        }
        var row = [SIMD4<Float>](repeating: .zero, count: size.width)
        for y in 0..<size.height {
            if let base {
                let source = base.row(y)
                for x in 0..<size.width { row[x] = Compositing.premultiplied(source[x]) }
            } else {
                for x in 0..<size.width { row[x] = .zero }
            }
            for layer in stack {
                let source = layer.buffer.row(y)
                let opacity = Float(layer.opacity)
                for x in 0..<size.width {
                    Compositing.blend(&row[x], source[x], opacity: opacity, mode: layer.blendMode)
                }
                if let floating, let floatingPixels, floating.layerID == layer.id {
                    let destination = floating.destination
                    guard y >= destination.minY, y < destination.maxY else { continue }
                    let floatingRow = floatingPixels.row(y - destination.minY)
                    for x in max(0, destination.minX)..<min(size.width, destination.maxX) {
                        Compositing.blend(&row[x], floatingRow[x - destination.minX], opacity: opacity, mode: layer.blendMode)
                    }
                }
            }
            let target = result.row(y)
            for x in 0..<size.width { target[x] = Compositing.pixel(row[x]) }
        }
        return result
    }


    /// All visible layers composited bottom to top with their blend modes, in straight alpha, with any
    /// floating selection shown above its layer. This is what's exported.
    public func flattened(transparentKey: Pixel? = nil) -> PixelBuffer {
        let visible = layers.filter { $0.isVisible && $0.opacity > 0 }
        if selection.floating == nil, visible.count == 1, visible[0].opacity >= 1 {
            return visible[0].buffer.copy()
        }
        return composite(visible, transparentKey: transparentKey)
    }
}

/// A snapshot of the layer stack: which layers, in what order, with what settings and buffers.
/// Undo swaps whole snapshots, so restoring a deleted or merged layer costs no copying.
struct LayerStackState {
    struct Record {
        let layer: Layer
        let name: String
        let isVisible: Bool
        let opacity: Double
        let blendMode: BlendMode
        let isLocked: Bool
        let adjustment: Effect?
        let buffer: PixelBuffer
    }

    let records: [Record]
    let activeIndex: Int

    func isSame(as other: LayerStackState) -> Bool {
        records.count == other.records.count && activeIndex == other.activeIndex
            && zip(records, other.records).allSatisfy { a, b in
                a.layer === b.layer && a.name == b.name && a.isVisible == b.isVisible && a.opacity == b.opacity
                    && a.blendMode == b.blendMode && a.isLocked == b.isLocked && a.adjustment == b.adjustment && a.buffer === b.buffer
            }
    }
}
