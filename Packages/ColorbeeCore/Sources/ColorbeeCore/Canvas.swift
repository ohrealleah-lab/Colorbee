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
    public internal(set) var hasTransparentBackground: Bool
    /// The original bottom layer. Erasing it leaves Color 2 while it's still at the bottom of a solid image.
    public private(set) var backgroundLayerID: LayerID?
    /// How the photo was taken, if it came from a camera or phone (FR-11.8). Written into an export only when asked.
    public var cameraDetails: CameraDetails?
    /// The file it came from had a GPS location, which Colorbee doesn't keep (FR-1.3, Info panel).
    public var locationRemoved = false

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

    /// A canvas read from a project: `backgroundLayerID` says which layer, if any, is the original background.
    public convenience init(colorSpace: CGColorSpace, layers: [Layer], hasTransparentBackground: Bool, backgroundLayerID: LayerID?, activeLayerIndex: Int) {
        self.init(colorSpace: colorSpace, layers: layers, hasTransparentBackground: hasTransparentBackground)
        self.backgroundLayerID = backgroundLayerID
        self.activeLayerIndex = min(max(0, activeLayerIndex), layers.count - 1)
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

    /// An independent copy with the same layers, settings and selection, for saving in the background
    /// while editing carries on. A floating selection's pixels are never modified, so they're shared.
    public func copy() -> Canvas {
        let copies = layers.map { layer in
            let copy = Layer(name: layer.name, buffer: layer.adjustment == nil ? layer.buffer.copy() : layer.buffer, id: layer.id)
            copy.isVisible = layer.isVisible
            copy.opacity = layer.opacity
            copy.blendMode = layer.blendMode
            copy.isLocked = layer.isLocked
            copy.adjustment = layer.adjustment
            copy.clipsToLayerBelow = layer.clipsToLayerBelow
            return copy
        }
        let canvas = Canvas(colorSpace: colorSpace, layers: copies, hasTransparentBackground: hasTransparentBackground,
                            backgroundLayerID: backgroundLayerID, activeLayerIndex: activeLayerIndex)
        canvas.selection = selection
        canvas.cameraDetails = cameraDetails
        canvas.locationRemoved = locationRemoved
        return canvas
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

    /// Rotates or flips every layer. A layer with pixels keeps its buffer object and gets the turned pixels
    /// in it, since history steps (a blend mode change, say) share that object and must see later edits.
    func transform(_ orientation: Orientation) {
        let newSize = orientation.transformedSize(size)
        for layer in layers {
            if layer.holdsNoPixels {
                layer.buffer = PixelBuffer(size: newSize)
            } else {
                layer.buffer.swapContents(with: layer.buffer.transformed(orientation))
            }
        }
        size = newSize
    }

    var currentGeometry: GeometryChange {
        GeometryChange(size: size, buffers: Dictionary(uniqueKeysWithValues: layers.map { ($0.id, $0.buffer) }))
    }

    /// What erasing or lifting pixels leaves behind on `layer`: Color 2 on a solid background, otherwise transparency.
    public func vacatedFill(for layer: Layer, color2: Pixel) -> Pixel {
        layer.id == backgroundLayerID && layer.id == layers.first?.id && !hasTransparentBackground ? color2 : .clear
    }

    // MARK: Clipped adjustments

    /// The pixel layer a clipped adjustment at `index` changes: the nearest layer below that isn't itself a clipped
    /// adjustment, if that's a pixel layer. Nil (no effect) when it's an adjustment or there's nothing below.
    public func clipBaseIndex(forLayerAt index: Int) -> Int? {
        guard layers.indices.contains(index) else { return nil }
        var below = index - 1
        while below >= 0, layers[below].adjustment != nil, layers[below].clipsToLayerBelow { below -= 1 }
        return below >= 0 && layers[below].adjustment == nil ? below : nil
    }

    /// Whether the adjustment layer at `index` could be set to change only the layer below.
    public func canClip(layerAt index: Int) -> Bool {
        layers.indices.contains(index) && layers[index].adjustment != nil && clipBaseIndex(forLayerAt: index) != nil
    }

    /// Where a new layer goes "above the active one": above the active layer's clipped adjustments too, so they keep
    /// changing the layer they're on (Leah, 2026-10-13). On a clipped adjustment, above its whole group.
    public var indexAboveActiveLayer: Int {
        let active = activeLayerIndex
        let base = layers[active].adjustment == nil ? active : layers[active].clipsToLayerBelow ? clipBaseIndex(forLayerAt: active) : nil
        guard let base else { return active + 1 }
        return base + 1 + clippedAdjustments(onLayerAt: base).count
    }

    /// The clipped adjustment layers on the pixel layer at `index`, bottom to top.
    public func clippedAdjustments(onLayerAt index: Int) -> [Layer] {
        guard layers.indices.contains(index), layers[index].adjustment == nil else { return [] }
        var result: [Layer] = []
        var above = index + 1
        while above < layers.count, layers[above].adjustment != nil, layers[above].clipsToLayerBelow {
            result.append(layers[above])
            above += 1
        }
        return result
    }

    /// `stack` with each pixel layer's clipped adjustments applied to its own pixels (in a stand-in with the same id
    /// and settings), and the clipped adjustments themselves left out.
    private func clipped(_ stack: [Layer]) -> [Layer] {
        guard stack.contains(where: { $0.clipsToLayerBelow && $0.adjustment != nil }) else { return stack }
        return stack.compactMap { layer in
            if layer.adjustment != nil { return layer.clipsToLayerBelow ? nil : layer }
            guard let index = layers.firstIndex(where: { $0 === layer }) else { return layer }
            let clips = clippedAdjustments(onLayerAt: index).filter { clip in stack.contains { $0 === clip } }
            guard !clips.isEmpty else { return layer }
            var buffer = layer.buffer
            for clip in clips {
                buffer = Compositing.adjust(buffer, by: clip.adjustment!, opacity: clip.opacity, mode: clip.blendMode)
            }
            let standIn = Layer(name: layer.name, buffer: buffer, id: layer.id)
            standIn.opacity = layer.opacity
            standIn.blendMode = layer.blendMode
            return standIn
        }
    }

    // MARK: Thumbnails

    /// A small picture of the whole image for the History panel, made by compositing only the sampled
    /// pixels, so it costs almost nothing even on a huge image. Blur and Sharpen adjustments are skipped.
    public func thumbnail(maxSide: Int) -> Thumbnail {
        let scale = min(1, Double(maxSide) / Double(max(size.width, size.height)))
        let width = max(1, Int(Double(size.width) * scale)), height = max(1, Int(Double(size.height) * scale))
        var pixels: [Pixel] = []
        pixels.reserveCapacity(width * height)
        let visible = layers.filter { $0.isVisible && $0.opacity > 0 }
        // A pixel layer's clipped adjustments change its own pixels before it's blended.
        let clips = Dictionary(uniqueKeysWithValues: visible.map { layer in
            (ObjectIdentifier(layer), layers.firstIndex { $0 === layer }.map { clippedAdjustments(onLayerAt: $0).filter { clip in visible.contains { $0 === clip } } } ?? [])
        })
        // Each adjustment's color change, worked out once: Adjust Photo's color and tone count too, though not its
        // detail or vignette, so the Adjust Photo histogram follows its sliders (stage 15).
        let transforms = Dictionary(uniqueKeysWithValues: visible.compactMap { layer in
            layer.adjustment?.colorTransform.map { (ObjectIdentifier(layer), $0) }
        })
        for ty in 0..<height {
            let y = min(size.height - 1, Int((Double(ty) + 0.5) / scale))
            for tx in 0..<width {
                let x = min(size.width - 1, Int((Double(tx) + 0.5) / scale))
                var color = SIMD4<Float>.zero
                for layer in visible {
                    if layer.adjustment != nil {
                        guard !layer.clipsToLayerBelow, let transform = transforms[ObjectIdentifier(layer)] else { continue }
                        let below = Compositing.pixel(color)
                        var adjusted = transform(below)
                        adjusted.a = below.a
                        let goal = Compositing.premultiplied(adjusted)
                        color += (goal - color) * Float(layer.opacity)
                    } else {
                        var pixel = layer.buffer[x, y]
                        for clip in clips[ObjectIdentifier(layer)] ?? [] {
                            guard let transform = transforms[ObjectIdentifier(clip)] else { continue }
                            var adjusted = transform(pixel)
                            adjusted.a = pixel.a
                            pixel = Compositing.lerp(pixel, adjusted, Float(clip.opacity))
                        }
                        Compositing.blend(&color, pixel, opacity: Float(layer.opacity), mode: layer.blendMode)
                    }
                }
                pixels.append(Compositing.pixel(color))
            }
        }
        return Thumbnail(width: width, height: height, pixels: pixels)
    }

    // MARK: Layer stack

    /// Every layer's properties and buffer, for undoing changes to the stack (FR-8).
    var layerStackState: LayerStackState {
        LayerStackState(
            records: layers.map {
                LayerStackState.Record(layer: $0, name: $0.name, isVisible: $0.isVisible, opacity: $0.opacity,
                                       blendMode: $0.blendMode, isLocked: $0.isLocked, adjustment: $0.adjustment,
                                       clipsToLayerBelow: $0.clipsToLayerBelow, buffer: $0.buffer)
            },
            activeIndex: activeLayerIndex,
            hasTransparentBackground: hasTransparentBackground,
            size: size
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
            layer.clipsToLayerBelow = record.clipsToLayerBelow
            layer.buffer = record.buffer
            return layer
        }
        activeLayerIndex = min(max(0, state.activeIndex), layers.count - 1)
        hasTransparentBackground = state.hasTransparentBackground
        size = state.size
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
    /// An adjustment layer changes everything composited so far. The floating selection is drawn into its
    /// layer before the layer is blended, as it will be once placed (review F, finding 1), at `resampling`
    /// when it's stretched.
    func composite(_ stack: [Layer], onto base: PixelBuffer? = nil, transparentKey: Pixel? = nil, resampling: Resampling = .nearestNeighbor) -> PixelBuffer {
        var current = base
        var segment: [Layer] = []
        for layer in clipped(stack) {
            if let adjustment = layer.adjustment {
                let below = segment.isEmpty && current != nil ? current! : compositePixels(segment, onto: current, transparentKey: transparentKey, resampling: resampling)
                current = Compositing.adjust(below, by: adjustment, opacity: layer.opacity, mode: layer.blendMode)
                segment = []
            } else {
                segment.append(layer)
            }
        }
        if segment.isEmpty, let current, current !== base { return current }
        return compositePixels(segment, onto: current, transparentKey: transparentKey, resampling: resampling)
    }

    /// Pixel layers only, composited row by row in premultiplied floats.
    private func compositePixels(_ stack: [Layer], onto base: PixelBuffer?, transparentKey: Pixel?, resampling: Resampling) -> PixelBuffer {
        let result = PixelBuffer(width: size.width, height: size.height)
        let floating = selection.floating
        let floatingPixels = floating.flatMap { floating in
            stack.contains { $0.id == floating.layerID } ? floating.rendered(using: resampling, transparentKey: transparentKey) : nil
        }
        let width = size.width
        // Rows are independent, so bands of them composite on all cores (NFR-6).
        ParallelRows.forEach(0..<size.height) { rows in
            let row = UnsafeMutablePointer<SIMD4<Float>>.allocate(capacity: width)
            defer { row.deallocate() }
            for y in rows {
                if let base {
                    let source = base.row(y)
                    for x in 0..<width { row[x] = Compositing.premultiplied(source[x]) }
                } else {
                    row.update(repeating: .zero, count: width)
                }
                for layer in stack {
                    let source = layer.buffer.row(y)
                    let opacity = Float(layer.opacity)
                    let mode = layer.blendMode
                    // The floating selection's pixels over the layer's, as placing will make them.
                    var floatingSpan = 0..<0
                    var floatingRow: UnsafeMutablePointer<Pixel>?
                    if let floating, let floatingPixels, floating.layerID == layer.id,
                       y >= floating.destination.minY, y < floating.destination.maxY {
                        // Empty when the paste is entirely off the canvas's sides.
                        let lower = min(max(0, floating.destination.minX), width)
                        floatingSpan = lower..<max(lower, min(width, floating.destination.maxX))
                        floatingRow = floatingPixels.row(y - floating.destination.minY) - floating.destination.minX
                    }
                    // Plain loops, so the common case (nothing floating) stays as fast as before.
                    if let floatingRow {
                        for x in 0..<floatingSpan.lowerBound {
                            Compositing.blend(&row[x], source[x], opacity: opacity, mode: mode)
                        }
                        for x in floatingSpan {
                            Compositing.blend(&row[x], Compositing.over(source[x], floatingRow[x]), opacity: opacity, mode: mode)
                        }
                        for x in floatingSpan.upperBound..<width {
                            Compositing.blend(&row[x], source[x], opacity: opacity, mode: mode)
                        }
                    } else {
                        for x in 0..<width {
                            Compositing.blend(&row[x], source[x], opacity: opacity, mode: mode)
                        }
                    }
                }
                let target = result.row(y)
                for x in 0..<width { target[x] = Compositing.pixel(row[x]) }
            }
        }
        return result
    }


    /// One pixel of the visible layers as they look together: blend modes, opacity and adjustment layers
    /// included, for the Eyedropper's Option-click (review I, finding 8). Blur and Sharpen adjustments, which
    /// need the neighbors, see just this pixel.
    public func pixelAsShown(at point: IntPoint) -> Pixel? {
        guard bounds.contains(point) else { return nil }
        // `row` points into the buffer, so it's kept alive until the pixel is read.
        let shown = patchAsShown(IntRect(x: point.x, y: point.y, width: 1, height: 1), through: layers.count - 1)
        return withExtendedLifetime(shown) { shown.row(0)[0] }
    }

    /// `rect` (inside the canvas) as the visible layers from the bottom up to `index` show it: what an adjustment
    /// above `index` sees there, for the white-balance eyedropper on an Adjust Photo layer. Like `pixelAsShown`, it
    /// works on the patch alone, so adjustments that look at neighbors or at the whole picture aren't exact.
    public func patchAsShown(_ rect: IntRect, through index: Int) -> PixelBuffer {
        // Every layer, hidden ones too, so an adjustment set to "Only the layer below" finds the same layer below.
        let patch = layers.prefix(max(0, index + 1)).map { layer -> Layer in
            let buffer = PixelBuffer(width: rect.width, height: rect.height)
            if layer.adjustment == nil {
                for y in 0..<rect.height {
                    (buffer.row(y)).update(from: layer.buffer.row(rect.minY + y) + rect.minX, count: rect.width)
                }
            }
            let copy = Layer(name: layer.name, buffer: buffer, id: layer.id)
            copy.isVisible = layer.isVisible
            copy.opacity = layer.opacity
            copy.blendMode = layer.blendMode
            copy.adjustment = layer.adjustment
            copy.clipsToLayerBelow = layer.clipsToLayerBelow
            return copy
        }
        return Canvas(colorSpace: colorSpace, layers: patch.isEmpty ? [Layer(name: "Empty", buffer: PixelBuffer(width: rect.width, height: rect.height))] : Array(patch),
                      hasTransparentBackground: true).flattened()
    }

    /// Each pixel layer's buffer as a save writes it: a floating selection is drawn into a copy of its layer, so
    /// a project, and Revert Layer, get the layer as the screen shows it (review G, finding 3). Other buffers
    /// are the layers' own.
    public func layerBuffersAsSaved(transparentKey: Pixel?, resampling: Resampling) -> [LayerID: PixelBuffer] {
        var buffers: [LayerID: PixelBuffer] = [:]
        for layer in layers where layer.adjustment == nil {
            guard let floating = selection.floating, floating.layerID == layer.id else {
                buffers[layer.id] = layer.buffer
                continue
            }
            let buffer = layer.buffer.copy()
            let pixels = floating.rendered(using: resampling, transparentKey: transparentKey)
            let origin = IntPoint(x: floating.destination.minX, y: floating.destination.minY)
            let area = IntRect(x: origin.x, y: origin.y, width: pixels.width, height: pixels.height).intersection(buffer.bounds)
            for y in area.minY..<area.maxY {
                let source = pixels.row(y - origin.y), target = buffer.row(y)
                for x in area.minX..<area.maxX { target[x] = Compositing.over(target[x], source[x - origin.x]) }
            }
            buffers[layer.id] = buffer
        }
        return buffers
    }

    /// The visible layers from the bottom up to and including `index`, as they look together.
    /// What an adjustment layer added above `index` would see.
    public func composited(through index: Int) -> PixelBuffer {
        composite(layers.prefix(index + 1).filter { $0.isVisible && $0.opacity > 0 })
    }

    /// All visible layers composited bottom to top with their blend modes, in straight alpha, with any
    /// floating selection shown above its layer. This is what's exported.
    public func flattened(transparentKey: Pixel? = nil, resampling: Resampling = .nearestNeighbor) -> PixelBuffer {
        let visible = layers.filter { $0.isVisible && $0.opacity > 0 }
        if selection.floating == nil, visible.count == 1, visible[0].opacity >= 1 {
            return visible[0].buffer.copy()
        }
        return composite(visible, transparentKey: transparentKey, resampling: resampling)
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
        let clipsToLayerBelow: Bool
        let buffer: PixelBuffer

        /// The same settings and pixels as `other`.
        func matches(_ other: Record) -> Bool {
            name == other.name && isVisible == other.isVisible && opacity == other.opacity && blendMode == other.blendMode
                && isLocked == other.isLocked && adjustment == other.adjustment && clipsToLayerBelow == other.clipsToLayerBelow
                && buffer === other.buffer
        }
    }

    let records: [Record]
    let activeIndex: Int
    let hasTransparentBackground: Bool
    /// The canvas size the buffers have. Only going to a History Snapshot changes it in a layer step.
    let size: IntSize

    func isSame(as other: LayerStackState) -> Bool {
        records.count == other.records.count && activeIndex == other.activeIndex && size == other.size
            && hasTransparentBackground == other.hasTransparentBackground
            && zip(records, other.records).allSatisfy { a, b in a.layer === b.layer && a.matches(b) }
    }
}

/// A small image kept as a plain array (a PixelBuffer would round up to a whole memory page).
public struct Thumbnail: Sendable {
    public let width: Int
    public let height: Int
    public let pixels: [Pixel]
}
