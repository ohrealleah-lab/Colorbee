import Foundation
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
    /// The Clipboard History items this picture was pasted from, kept with it so a redaction can still offer to remove
    /// them after a relaunch (Leah, 2026-10-31; review AA, finding 4).
    public var pastedFrom: Set<UUID> = []
    /// For a patch worked out on its own (`patchAsShown`): where it sits in the whole canvas.
    var placement: Effects.Placement?
    /// Edits that have written on a layer with locked transparency (stage 23), to finish before the canvas is shown.
    private var lockedEdits: [WeakEdit] = []

    private struct WeakEdit {
        weak var edit: Edit?
    }

    func noteLockedEdit(_ edit: Edit) {
        lockedEdits.append(WeakEdit(edit: edit))
    }

    /// Puts back locked transparency on everything written since the last time, so paint never shows in a locked
    /// layer's clear area, even mid-stroke. The display calls this before drawing.
    public func keepLockedTransparency() {
        guard !lockedEdits.isEmpty else { return }
        let edits = lockedEdits.compactMap(\.edit)
        lockedEdits = []
        edits.forEach { $0.keepLockedTransparency() }
    }

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

    /// A one-layer picture of `buffer`, its Background layer, with a transparent background where it has clear pixels
    /// unless `transparent` says otherwise. Whatever opens a single picture makes it this way (review round 11, AC 9).
    public convenience init(picture buffer: PixelBuffer, colorSpace: CGColorSpace, transparent: Bool? = nil) {
        self.init(colorSpace: colorSpace, layers: [Layer(name: "Background", buffer: buffer)],
                  hasTransparentBackground: transparent ?? buffer.hasTransparency)
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
        let copies = layers.map { $0.copy(buffer: $0.isPixelLayer ? $0.buffer.copy() : $0.buffer).withOwnMask() }
        let canvas = Canvas(colorSpace: colorSpace, layers: copies, hasTransparentBackground: hasTransparentBackground,
                            backgroundLayerID: backgroundLayerID, activeLayerIndex: activeLayerIndex)
        canvas.selection = selection
        canvas.cameraDetails = cameraDetails
        canvas.locationRemoved = locationRemoved
        canvas.pastedFrom = pastedFrom
        return canvas
    }

    public var bounds: IntRect { IntRect(size: size) }
    public var activeLayer: Layer { layers[activeLayerIndex] }

    /// A layer, or a layer's mask, which tools paint and history records like a layer (stage 27).
    public func layer(withID id: LayerID) -> Layer? {
        layers.first { $0.id == id } ?? layers.lazy.compactMap(\.mask).first { $0.id == id }
    }

    /// Every layer, each followed by its mask if it has one: what holds pixels the canvas size.
    public var allLayers: [Layer] {
        layers.flatMap { layer in [layer] + (layer.mask.map { [$0] } ?? []) }
    }

    /// The layer whose mask `mask` is.
    public func owner(ofMask mask: Layer) -> Layer? {
        layers.first { $0.mask === mask }
    }

    public func insertLayer(_ layer: Layer, at index: Int) {
        precondition(layer.buffer.size == size, "Layer size doesn't match the canvas")
        layers.insert(layer, at: index)
    }

    /// While the active layer's mask is chosen, tools paint on it rather than on the layer (stage 27). Not saved, and not
    /// an undo step; it ends when another layer becomes active (`Editor`).
    public var editsMask = false

    /// Where tools paint: the active layer, or its mask while that's chosen.
    public var paintLayer: Layer {
        editsMask ? activeLayer.mask ?? activeLayer : activeLayer
    }

    /// Puts `layer` "above the active one" (`indexAboveActiveLayer`), in the active layer's group, and makes it active.
    func insertLayerAboveActive(_ layer: Layer) {
        layer.groupID = activeLayer.groupID
        let index = indexAboveActiveLayer
        insertLayer(layer, at: index)
        activeLayerIndex = index
    }

    /// Swaps in new pixel buffers of `size` for every layer. Used by geometry changes and their undo.
    /// A mask that Undo on Active Layer brought back out of order wasn't there when the size changed, so it has no buffer
    /// of that size: it gets an empty one, which shows the whole layer, rather than stopping Colorbee (the monkey test,
    /// 2026-10-31).
    func replaceContents(size: IntSize, buffers: [LayerID: PixelBuffer]) {
        precondition(buffers.values.allSatisfy { $0.size == size }, "Every buffer must be the new size")
        self.size = size
        for layer in allLayers {
            layer.buffer = buffers[layer.id] ?? PixelBuffer(size: size)
        }
    }

    /// Rotates or flips every layer. A layer with pixels keeps its buffer object and gets the turned pixels
    /// in it, since history steps (a blend mode change, say) share that object and must see later edits.
    func transform(_ orientation: Orientation) {
        let newSize = orientation.transformedSize(size)
        for layer in allLayers {
            if layer.holdsNoPixels {
                layer.buffer = PixelBuffer(size: newSize)
            } else {
                layer.buffer.swapContents(with: layer.buffer.transformed(orientation))
            }
            layer.text?.turn(orientation)
        }
        size = newSize
    }

    var currentGeometry: GeometryChange {
        GeometryChange(size: size, buffers: Dictionary(uniqueKeysWithValues: allLayers.map { ($0.id, $0.buffer) }))
    }

    /// What the Eraser, Cut and Delete leave on `layer`: as `vacatedFill`, but a layer that locks its transparency can't
    /// get holes, so they paint Color 2 inside its shape (Q23.2). New canvas space and moved edges use `vacatedFill`,
    /// since those move the layer's outline rather than paint on it (Q23.4).
    public func erasedFill(for layer: Layer, color2: Pixel) -> Pixel {
        locksTransparency(layer) ? Pixel(r: color2.r, g: color2.g, b: color2.b) : vacatedFill(for: layer, color2: color2)
    }

    /// What erasing or lifting pixels leaves behind on `layer`: Color 2 on a solid background, otherwise transparency.
    public func vacatedFill(for layer: Layer, color2: Pixel) -> Pixel {
        layer.id == backgroundLayerID && layer.id == layers.first?.id && !hasTransparentBackground ? color2 : .clear
    }

    // MARK: Clipped adjustments

    /// The pixel layer a clipped adjustment at `index` changes: the nearest layer below that isn't itself a clipped
    /// adjustment, if that's a pixel layer in the same group. Nil (no effect) when it's an adjustment, a group or
    /// there's nothing below.
    public func clipBaseIndex(forLayerAt index: Int) -> Int? {
        guard layers.indices.contains(index) else { return nil }
        let parent = layers[index].groupID
        var below = index - 1
        while below >= 0, !layers[below].isGroup, layers[below].clipsToLayerBelow, layers[below].groupID == parent { below -= 1 }
        return below >= 0 && layers[below].isPixelLayer && layers[below].groupID == parent ? below : nil
    }

    /// Whether the adjustment or pixel layer at `index` could be set to change or show on only the layer below.
    public func canClip(layerAt index: Int) -> Bool {
        layers.indices.contains(index) && !layers[index].isGroup && clipBaseIndex(forLayerAt: index) != nil
    }

    /// Where a new layer goes "above the active one": above the active layer's clipped adjustments too, so they keep
    /// changing the layer they're on (Leah, 2026-10-13). On a clipped adjustment, above its whole group.
    public var indexAboveActiveLayer: Int {
        let active = activeLayerIndex
        let base = layers[active].clipsToLayerBelow && !layers[active].isGroup ? clipBaseIndex(forLayerAt: active)
            : layers[active].isPixelLayer ? active : nil
        guard let base else { return active + 1 }
        return base + 1 + clippedLayers(onLayerAt: base).count
    }

    /// The layers set to "Only the layer below" on the pixel layer at `index` (adjustments, and pixel layers since stage
    /// 28b), bottom to top. They belong to it: they move, merge and go with it.
    public func clippedLayers(onLayerAt index: Int) -> [Layer] {
        guard layers.indices.contains(index), layers[index].isPixelLayer, !layers[index].clipsToLayerBelow else { return [] }
        let parent = layers[index].groupID
        var result: [Layer] = []
        var above = index + 1
        while above < layers.count, !layers[above].isGroup, layers[above].clipsToLayerBelow, layers[above].groupID == parent {
            result.append(layers[above])
            above += 1
        }
        return result
    }

    /// `stack` with each pixel layer's clipped layers put into its own pixels (in a stand-in with the same id, settings
    /// and mask): its adjustments applied, and its pixel layers blended on only where it has pixels (stage 28b). The
    /// clipped layers themselves are left out.
    private func clipped(_ stack: [Layer], transparentKey: Pixel?, resampling: Resampling) -> [Layer] {
        guard stack.contains(where: { $0.clipsToLayerBelow && !$0.isGroup }) else { return stack }
        return stack.compactMap { layer in
            if layer.clipsToLayerBelow, !layer.isGroup, let index = layers.firstIndex(where: { $0 === layer }),
               clipBaseIndex(forLayerAt: index) != nil { return nil }
            guard layer.isPixelLayer, let index = layers.firstIndex(where: { $0 === layer }) else { return layer }
            let clips = clippedLayers(onLayerAt: index).filter { clip in stack.contains { $0 === clip } }
            guard !clips.isEmpty else { return layer }
            // A floating piece goes in before the clipped layers, as on screen and as placing will (review Z, finding 1);
            // the stand-in then gets an id of its own, so it isn't drawn on top again.
            let floating = selection.floating.flatMap { $0.layerID == layer.id ? $0 : nil }
            var buffer = floating?.placedCopy(of: layer, locked: locksTransparency(layer), resampling: resampling, transparentKey: transparentKey)
                ?? layer.buffer
            for clip in clips {
                if let adjustment = clip.adjustment {
                    buffer = Compositing.adjust(buffer, by: adjustment, opacity: clip.opacity, mode: clip.blendMode, mask: clip.activeMask, placement: placement)
                } else {
                    // A piece floating on the clipped layer itself shows in it too, as placing will leave it (the monkey
                    // test, 2026-10-31).
                    let pixels = selection.floating.flatMap { $0.layerID == clip.id ? $0 : nil }.map {
                        $0.placedCopy(of: clip, locked: locksTransparency(clip), resampling: resampling, transparentKey: transparentKey)
                    } ?? clip.buffer
                    buffer = Compositing.blendAtop(buffer, pixels, opacity: clip.opacity, mode: clip.blendMode, mask: clip.activeMask)
                }
            }
            return layer.copy(buffer: buffer, id: floating == nil ? nil : LayerID())
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
        let visible = shownLayers
        let nodes = tree(of: visible)
        // A pixel layer's clipped adjustments change its own pixels before it's blended.
        let clips = Dictionary(uniqueKeysWithValues: visible.map { layer in
            (ObjectIdentifier(layer), layers.firstIndex { $0 === layer }.map { clippedLayers(onLayerAt: $0).filter { clip in visible.contains { $0 === clip } } } ?? [])
        })
        // Each adjustment's color change, worked out once: Adjust Photo's color and tone count too, though not its
        // detail or vignette, so the Adjust Photo histogram follows its sliders (stage 15).
        let transforms = Dictionary(uniqueKeysWithValues: visible.compactMap { layer in
            layer.adjustment?.colorTransform.map { (ObjectIdentifier(layer), $0) }
        })
        // A floating piece shows placed in its layer or mask, as in `flattened` (review round 11, AE B).
        let placed = selection.floating.flatMap { floating in
            allLayers.first { $0.id == floating.layerID }.map { layer in
                (id: layer.id, buffer: floating.placedCopy(of: layer, locked: locksTransparency(layer), resampling: .nearestNeighbor, transparentKey: nil))
            }
        }
        func buffer(of layer: Layer) -> PixelBuffer { placed?.id == layer.id ? placed!.buffer : layer.buffer }
        func reveal(_ layer: Layer, _ x: Int, _ y: Int) -> Float {
            guard layer.maskEnabled, let mask = layer.mask else { return 1 }
            return Compositing.reveal((placed?.id == mask.id ? placed!.buffer : mask.buffer)[x, y])
        }
        for ty in 0..<height {
            let y = min(size.height - 1, Int((Double(ty) + 0.5) / scale))
            for tx in 0..<width {
                let x = min(size.width - 1, Int((Double(tx) + 0.5) / scale))
                // Groups as `composite` does them: Pass Through over what's below, any other on their own first.
                // Rounded to bytes where `composite` keeps a picture between steps, so the two match (the monkey test,
                // 2026-10-31): Saturation and hue shifts make much of a near-gray pixel's rounding.
                func rounded(_ color: SIMD4<Float>) -> SIMD4<Float> { Compositing.premultiplied(Compositing.pixel(color)) }
                func shade(_ nodes: [LayerNode], onto start: SIMD4<Float>) -> SIMD4<Float> {
                    var color = start
                    for node in nodes {
                        let layer = node.layer
                        if layer.isGroup {
                            let opacity = Float(layer.opacity) * reveal(layer, x, y)
                            if layer.passesThrough {
                                let backdrop = rounded(color)
                                let inside = rounded(shade(node.children, onto: backdrop))
                                color = layer.opacity >= 1 && layer.activeMask == nil ? inside
                                    : rounded(Compositing.mixed(backdrop, Compositing.pixel(inside), fade: opacity, mode: .normal))
                            } else {
                                Compositing.blend(&color, Compositing.pixel(shade(node.children, onto: .zero)), opacity: opacity, mode: layer.blendMode)
                            }
                        } else if layer.clipsToLayerBelow {
                            continue
                        } else if layer.adjustment != nil {
                            guard let transform = transforms[ObjectIdentifier(layer)] else { continue }
                            let below = Compositing.pixel(color)
                            var adjusted = transform(below)
                            adjusted.a = below.a
                            color = rounded(Compositing.mixed(Compositing.premultiplied(below), adjusted, fade: Float(layer.opacity) * reveal(layer, x, y), mode: layer.blendMode))
                        } else {
                            var pixel = buffer(of: layer)[x, y]
                            for clip in clips[ObjectIdentifier(layer)] ?? [] {
                                let fade = Float(clip.opacity) * reveal(clip, x, y)
                                if clip.isPixelLayer {
                                    pixel = Compositing.blendAtop(pixel, buffer(of: clip)[x, y], opacity: fade, mode: clip.blendMode)
                                    continue
                                }
                                guard let transform = transforms[ObjectIdentifier(clip)] else { continue }
                                var adjusted = transform(pixel)
                                adjusted.a = pixel.a
                                pixel = Compositing.pixel(Compositing.mixed(Compositing.premultiplied(pixel), adjusted, fade: fade, mode: clip.blendMode))
                            }
                            Compositing.blend(&color, pixel, opacity: Float(layer.opacity) * reveal(layer, x, y), mode: layer.blendMode)
                        }
                    }
                    return color
                }
                pixels.append(Compositing.pixel(shade(nodes, onto: .zero)))
            }
        }
        return Thumbnail(width: width, height: height, pixels: pixels)
    }

    // MARK: Layer stack

    /// Every layer's properties and buffer, for undoing changes to the stack (FR-8).
    var layerStackState: LayerStackState {
        LayerStackState(
            records: layers.map {
                LayerStackState.Record($0)
            },
            activeIndex: activeLayerIndex,
            hasTransparentBackground: hasTransparentBackground,
            size: size
        )
    }

    func restore(_ state: LayerStackState) {
        layers = state.records.map { record in
            let layer = record.layer
            layer.settings = record.settings
            layer.mask = record.mask
            layer.buffer = record.buffer
            return layer
        }
        activeLayerIndex = min(max(0, state.activeIndex), layers.count - 1)
        hasTransparentBackground = state.hasTransparentBackground
        size = state.size
    }

    /// Removing a group leaves the layers in it in the group it was in.
    func removeLayer(at index: Int) {
        precondition(layers.count > 1, "A canvas needs at least one layer")
        let removed = layers.remove(at: index)
        if removed.isGroup {
            for layer in layers where layer.groupID == removed.id { layer.groupID = removed.groupID }
        }
        activeLayerIndex = min(activeLayerIndex, layers.count - 1)
    }

    /// The same layers in a new order. The active layer stays active.
    func reorder(_ order: [Layer]) {
        precondition(order.count == layers.count && order.allSatisfy { layer in layers.contains { $0 === layer } }, "Only the order may change")
        let active = activeLayer
        layers = order
        activeLayerIndex = layers.firstIndex { $0 === active }!
    }

    func moveLayer(from source: Int, to destination: Int) {
        let layer = layers.remove(at: source)
        layers.insert(layer, at: destination)
    }

    /// `layers` composited bottom to top with their blend modes and opacity, onto `base` if given.
    /// An adjustment layer changes everything composited so far. The floating selection is drawn into its
    /// layer before the layer is blended, as it will be once placed (review F, finding 1), at `resampling`
    /// when it's stretched.
    /// A group in `stack` is put together as the screen shows it (stage 25): a Pass Through group's layers go straight
    /// onto what's below, faded in by its opacity; any other group's layers are composited on their own, then blended
    /// in like one layer.
    func composite(_ stack: [Layer], onto base: PixelBuffer? = nil, transparentKey: Pixel? = nil, resampling: Resampling = .nearestNeighbor) -> PixelBuffer {
        composite(tree(of: clipped(stack, transparentKey: transparentKey, resampling: resampling)), onto: base, transparentKey: transparentKey, resampling: resampling)
    }

    /// `Renderer.encode` draws the same on screen: groups, clipped layers and layers drawn on their own.
    private func composite(_ nodes: [LayerNode], onto base: PixelBuffer?, transparentKey: Pixel?, resampling: Resampling) -> PixelBuffer {
        var current = base
        var segment: [Layer] = []
        func below() -> PixelBuffer {
            defer { segment = [] }
            return segment.isEmpty && current != nil ? current! : compositePixels(segment, onto: current, transparentKey: transparentKey, resampling: resampling)
        }
        for node in nodes {
            let layer = node.layer
            if layer.isGroup {
                if layer.passesThrough {
                    let backdrop = below()
                    let inside = composite(node.children, onto: backdrop, transparentKey: transparentKey, resampling: resampling)
                    current = layer.opacity >= 1 && layer.activeMask == nil ? inside
                        : Compositing.mixed(backdrop, inside, opacity: layer.opacity, mode: .normal, mask: layer.activeMask)
                } else {
                    let inside = composite(node.children, onto: nil, transparentKey: transparentKey, resampling: resampling)
                    let standIn = Layer(name: layer.name, buffer: inside, id: layer.id)
                    standIn.opacity = layer.opacity
                    standIn.blendMode = layer.blendMode
                    standIn.mask = layer.mask
                    standIn.maskEnabled = layer.maskEnabled
                    segment.append(standIn)
                }
            } else if let adjustment = layer.adjustment {
                current = Compositing.adjust(below(), by: adjustment, opacity: layer.opacity, mode: layer.blendMode, mask: layer.activeMask, placement: placement)
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
                    if let mask = layer.activeMask?.row(y) {
                        // Masked (stage 27): rarer, so its own loop, with the floating selection placed as below.
                        let floating = floating.flatMap { $0.layerID == layer.id && y >= $0.destination.minY && y < $0.destination.maxY ? $0 : nil }
                        let floatingRow = floating.flatMap { f in floatingPixels.map { $0.row(y - f.destination.minY) - f.destination.minX } }
                        let locked = locksTransparency(layer)
                        for x in 0..<width {
                            var pixel = source[x]
                            if let floating, let floatingRow, x >= floating.destination.minX, x < floating.destination.maxX {
                                pixel = locked ? Pixel.placedOnLocked(pixel, floatingRow[x]) : Compositing.over(pixel, floatingRow[x])
                            }
                            Compositing.blend(&row[x], pixel, opacity: opacity * Compositing.reveal(mask[x]), mode: mode)
                        }
                        continue
                    }
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
                        let locked = locksTransparency(layer)
                        for x in floatingSpan {
                            let placed = locked ? Pixel.placedOnLocked(source[x], floatingRow[x]) : Compositing.over(source[x], floatingRow[x])
                            Compositing.blend(&row[x], placed, opacity: opacity, mode: mode)
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

    /// The average of `rect` as shown, opacity included, for the color readout and the Eyedropper's Sample Size
    /// (FR-9.7 item 9). Nil off the canvas.
    public func colorAsShown(in rect: IntRect) -> Pixel? {
        let area = rect.intersection(bounds)
        guard !area.isEmpty else { return nil }
        let shown = patchAsShown(area, through: layers.count - 1)
        return withExtendedLifetime(shown) { shown.averagedPixel(in: shown.bounds) }
    }

    /// `rect` (inside the canvas) as the visible layers from the bottom up to `index` show it: what an adjustment
    /// above `index` sees there, for the eyedroppers and the color readout. It's worked out on a patch around `rect`
    /// wide enough for blurs to reach in, and placed where it sits on the canvas, so vignettes and grain land as they
    /// do on the whole picture: it matches an export (FR-9.7 item 9). A floating selection shows as it does on screen
    /// (review W, finding 1).
    public func patchAsShown(_ rect: IntRect, through index: Int) -> PixelBuffer {
        patch(rect, of: Array(layers.prefix(max(0, index + 1))))
    }

    /// `rect` of the layer that the adjustment at `index`, set to "Only the layer below", changes, as it sees it: that
    /// layer's own pixels at full opacity and Normal, with the clipped adjustments under `index` applied (review V,
    /// finding 9). Nil when the adjustment at `index` isn't clipped.
    public func clipBasePatch(_ rect: IntRect, under index: Int) -> PixelBuffer? {
        guard layers.indices.contains(index), layers[index].adjustment != nil, layers[index].clipsToLayerBelow,
              let base = clipBaseIndex(forLayerAt: index) else { return nil }
        return patch(rect, of: Array(layers[base..<index]), alone: true)
    }

    /// `rect` as `stack` shows it, worked out on a patch. With `alone`, the stack's first layer is shown fully, at
    /// Normal.
    private func patch(_ rect: IntRect, of stack: [Layer], alone: Bool = false) -> PixelBuffer {
        // Blurs one after another reach as far as their reaches added up (review W, finding 3).
        let reach = min(stack.filter(\.isVisible).compactMap { $0.adjustment?.reach }.reduce(0, +), 400)
        let padded = rect.insetBy(-reach).intersection(bounds)
        // Every layer, hidden ones too, so an adjustment set to "Only the layer below" finds the same layer below.
        let patch = stack.enumerated().map { offset, layer -> Layer in
            let buffer = PixelBuffer(width: padded.width, height: padded.height)
            if layer.adjustment == nil {
                for y in 0..<padded.height {
                    (buffer.row(y)).update(from: layer.buffer.row(padded.minY + y) + padded.minX, count: padded.width)
                }
            }
            let copy = layer.copy(buffer: buffer)
            copy.mask = layer.mask.map { mask in
                let part = PixelBuffer(width: padded.width, height: padded.height)
                for y in 0..<padded.height {
                    (part.row(y)).update(from: mask.buffer.row(padded.minY + y) + padded.minX, count: padded.width)
                }
                return mask.copy(buffer: part)
            }
            if alone && offset == 0 {
                copy.isVisible = true
                copy.opacity = 1
                copy.blendMode = .normal
            }
            return copy
        }
        let canvas = Canvas(colorSpace: colorSpace, layers: patch.isEmpty ? [Layer(name: "Empty", buffer: PixelBuffer(width: padded.width, height: padded.height))] : Array(patch),
                            hasTransparentBackground: true)
        canvas.placement = Effects.Placement(origin: IntPoint(x: padded.minX, y: padded.minY), canvas: bounds)
        if var floating = selection.floating, stack.contains(where: { $0.id == floating.layerID }) {
            floating.destination = floating.destination.offsetBy(dx: -padded.minX, dy: -padded.minY)
            canvas.selection = .floating(floating)
        }
        let shown = canvas.flattened()
        guard padded != rect else { return shown }
        let inner = PixelBuffer(width: rect.width, height: rect.height)
        inner.setPixels(shown.pixels(in: rect.offsetBy(dx: -padded.minX, dy: -padded.minY)), in: inner.bounds)
        return inner
    }

    /// Each pixel layer's buffer as a save writes it: a floating selection is drawn into a copy of its layer, so
    /// a project, and Revert Layer, get the layer as the screen shows it (review G, finding 3). Other buffers
    /// are the layers' own.
    public func layerBuffersAsSaved(transparentKey: Pixel?, resampling: Resampling) -> [LayerID: PixelBuffer] {
        var buffers: [LayerID: PixelBuffer] = [:]
        // Masks too: a piece moved on a mask floats on the mask (review X, finding 6).
        for layer in allLayers where layer.adjustment == nil {
            guard let floating = selection.floating, floating.layerID == layer.id else {
                buffers[layer.id] = layer.buffer
                continue
            }
            buffers[layer.id] = floating.placedCopy(of: layer, locked: locksTransparency(layer), resampling: resampling, transparentKey: transparentKey)
        }
        return buffers
    }

    /// The visible layers from the bottom up to and including `index`, as they look together.
    /// What an adjustment layer added above `index` would see.
    public func composited(through index: Int) -> PixelBuffer {
        composite(layers.prefix(index + 1).filter(isShown))
    }

    /// All visible layers composited bottom to top with their blend modes, in straight alpha, with any
    /// floating selection shown above its layer. This is what's exported.
    public func flattened(transparentKey: Pixel? = nil, resampling: Resampling = .nearestNeighbor) -> PixelBuffer {
        // A piece moved on a mask is drawn as placed, as a save keeps it (the monkey test, 2026-10-31): in a stand-in
        // canvas sharing every other layer, so nothing here changes.
        if let floating = selection.floating, let index = layers.firstIndex(where: { $0.mask?.id == floating.layerID }), let mask = layers[index].mask {
            let owner = layers[index].copy(buffer: layers[index].buffer)
            owner.mask = mask.copy(buffer: floating.placedCopy(of: mask, locked: false, resampling: resampling, transparentKey: transparentKey))
            var standIns = layers
            standIns[index] = owner
            let canvas = Canvas(colorSpace: colorSpace, layers: standIns, hasTransparentBackground: hasTransparentBackground,
                                backgroundLayerID: backgroundLayerID, activeLayerIndex: activeLayerIndex)
            return canvas.flattened(transparentKey: transparentKey, resampling: resampling)
        }
        let visible = shownLayers
        // Not for a layer shown only on a hidden layer below: it shows nowhere, as on screen (the monkey test, 2026-10-31).
        if selection.floating == nil, visible.count == 1, visible[0].isPixelLayer, visible[0].opacity >= 1, visible[0].activeMask == nil,
           !visible[0].clipsToLayerBelow {
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
        let settings: LayerSettings
        let mask: Layer?
        let buffer: PixelBuffer

        /// `layer` as it is now.
        init(_ layer: Layer) {
            self.init(layer: layer, settings: layer.settings, mask: layer.mask, buffer: layer.buffer)
        }

        init(layer: Layer, settings: LayerSettings, mask: Layer?, buffer: PixelBuffer) {
            self.layer = layer
            self.settings = settings
            self.mask = mask
            self.buffer = buffer
        }

        /// The pixels it holds: the layer's, and its mask's.
        var buffers: [PixelBuffer] { [buffer] + (mask.map { [$0.buffer] } ?? []) }

        /// The same settings and pixels as `other`.
        func matches(_ other: Record) -> Bool {
            settings == other.settings && buffer === other.buffer && mask === other.mask
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
