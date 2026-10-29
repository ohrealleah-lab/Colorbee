/// Everything that changes the layer stack (FR-8.2), each as one undo step. A floating selection is
/// placed first, since it belongs to a layer that may move, merge or go away.
public enum LayerActions {
    /// A new transparent layer above the active one, which becomes active.
    @discardableResult
    public static func add(canvas: Canvas, history: History, context: SelectionContext) -> Bool {
        change("New Layer", canvas: canvas, history: history, context: context) {
            let layer = Layer(name: nextName(in: canvas), buffer: PixelBuffer(width: canvas.size.width, height: canvas.size.height))
            let index = canvas.indexAboveActiveLayer
            canvas.insertLayer(layer, at: index)
            canvas.activeLayerIndex = index
            return true
        }
    }

    /// A new adjustment layer above the active one, which becomes active (FR-8.4).
    @discardableResult
    public static func addAdjustment(_ adjustment: Effect, named name: String, canvas: Canvas, history: History, context: SelectionContext) -> Bool {
        guard Layer.isAdjustable(adjustment) else { return false }
        return change("New Adjustment Layer", canvas: canvas, history: history, context: context) {
            let layer = Layer(name: name, buffer: PixelBuffer(width: canvas.size.width, height: canvas.size.height))
            layer.adjustment = adjustment
            let index = canvas.indexAboveActiveLayer
            canvas.insertLayer(layer, at: index)
            canvas.activeLayerIndex = index
            return true
        }
    }

    /// Merge Adjustment: the active adjustment layer and every visible layer below it become one pixel layer, at the
    /// lowest of them, so the picture looks exactly the same (Leah, 2026-10-09). Baking it into the layer just below
    /// changed the look whenever that layer didn't cover everything the adjustment did. Hidden layers below stay as
    /// they are, like Merge Visible, and layers above aren't touched.
    @discardableResult
    public static func applyAdjustment(canvas: Canvas, history: History, context: SelectionContext) -> Bool {
        guard canApplyAdjustment(canvas) else { return false }
        if canvas.activeLayer.clipsToLayerBelow { return applyClippedAdjustment(canvas: canvas, history: history, context: context) }
        return change("Merge Adjustment", canvas: canvas, history: history, context: context) {
            let merged = canvas.layers.prefix(canvas.activeLayerIndex + 1).filter(\.isVisible)
            let target = merged[0]
            target.buffer = canvas.composite(merged)
            target.opacity = 1
            target.blendMode = .normal
            target.adjustment = nil
            target.clipsToLayerBelow = false
            for layer in merged.dropFirst() {
                canvas.removeLayer(at: canvas.layers.firstIndex { $0 === layer }!)
            }
            canvas.activeLayerIndex = canvas.layers.firstIndex { $0 === target }!
            return true
        }
    }

    /// A clipped adjustment goes into the layer it changes, with the visible clipped adjustments below it on that
    /// layer, in order, so the picture keeps its look; hidden ones stay as they are.
    private static func applyClippedAdjustment(canvas: Canvas, history: History, context: SelectionContext) -> Bool {
        change("Merge Adjustment", canvas: canvas, history: history, context: context) {
            let index = canvas.activeLayerIndex
            guard let baseIndex = canvas.clipBaseIndex(forLayerAt: index) else { return false }
            let base = canvas.layers[baseIndex]
            let merged = canvas.layers[(baseIndex + 1)...index].filter(\.isVisible)
            for clip in merged {
                base.buffer = Compositing.adjust(base.buffer, by: clip.adjustment!, opacity: clip.opacity, mode: clip.blendMode)
            }
            for clip in merged {
                canvas.removeLayer(at: canvas.layers.firstIndex { $0 === clip }!)
            }
            canvas.activeLayerIndex = canvas.layers.firstIndex { $0 === base }!
            return true
        }
    }

    /// A hidden adjustment changes nothing, so there's nothing to apply.
    public static func canApplyAdjustment(_ canvas: Canvas) -> Bool {
        let index = canvas.activeLayerIndex
        let layer = canvas.layers[index]
        guard index > 0, layer.adjustment != nil, layer.isVisible else { return false }
        if layer.clipsToLayerBelow {
            guard let baseIndex = canvas.clipBaseIndex(forLayerAt: index) else { return false }
            return !canvas.layers[baseIndex...index].contains { $0.isLocked && ($0.isVisible || $0 === canvas.layers[baseIndex]) }
        }
        let merged = canvas.layers.prefix(index + 1).filter(\.isVisible)
        return merged.count > 1 && !merged.contains(where: \.isLocked)
    }

    /// A copy of the active layer, with its settings, just above it.
    @discardableResult
    public static func duplicate(canvas: Canvas, history: History, context: SelectionContext) -> Bool {
        change("Duplicate Layer", canvas: canvas, history: history, context: context) {
            insertCopyOfActiveLayer(canvas: canvas)
            return true
        }
    }

    /// A copy of the active layer, with its settings, inserted just above it and made active. A copy of a clipped
    /// adjustment stays in its group; anything else goes above the group.
    @discardableResult
    static func insertCopyOfActiveLayer(canvas: Canvas) -> Layer {
        let source = canvas.activeLayer
        let copy = copy(of: source)
        let index = source.clipsToLayerBelow ? canvas.activeLayerIndex + 1 : canvas.indexAboveActiveLayer
        canvas.insertLayer(copy, at: index)
        canvas.activeLayerIndex = index
        return copy
    }

    /// "Name copy", with the same pixels and settings.
    static func copy(of source: Layer) -> Layer {
        let copy = Layer(name: "\(source.name) copy", buffer: source.buffer.copy())
        copy.isVisible = source.isVisible
        copy.opacity = source.opacity
        copy.blendMode = source.blendMode
        copy.locksTransparency = source.locksTransparency
        copy.adjustment = source.adjustment
        copy.clipsToLayerBelow = source.clipsToLayerBelow
        return copy
    }

    /// Deletes the active layer unless it's locked or the only one, with its clipped adjustments, which belonged to it
    /// (Leah, 2026-10-13). The layer below becomes active.
    @discardableResult
    public static func delete(canvas: Canvas, history: History, context: SelectionContext) -> Bool {
        guard canDelete(canvas) else { return false }
        return change("Delete Layer", canvas: canvas, history: history, context: context) {
            let index = canvas.activeLayerIndex
            for _ in 0...canvas.clippedAdjustments(onLayerAt: index).count { canvas.removeLayer(at: index) }
            canvas.activeLayerIndex = max(0, index - 1)
            return true
        }
    }

    /// Whether the layer at `index` (the active one if nil) could be deleted.
    public static func canDelete(_ canvas: Canvas, layerAt index: Int? = nil) -> Bool {
        let index = index ?? canvas.activeLayerIndex
        guard canvas.layers.indices.contains(index) else { return false }
        let going = [canvas.layers[index]] + canvas.clippedAdjustments(onLayerAt: index)
        return canvas.layers.count > going.count && !going.contains(where: \.isLocked)
    }

    /// Combines the active layer into the one below, using its blend mode and opacity. The result keeps
    /// the lower layer's name and settings. Unavailable on an adjustment layer, which Merge Adjustment merges with every
    /// layer below: "Down" should always mean the one layer below (Leah, 2026-10-10).
    @discardableResult
    public static func mergeDown(canvas: Canvas, history: History, context: SelectionContext) -> Bool {
        guard canMergeDown(canvas) else { return false }
        return change("Merge Down", canvas: canvas, history: history, context: context) {
            let index = canvas.activeLayerIndex
            let upper = canvas.layers[index], lower = canvas.layers[index - 1]
            // Its clipped adjustments are baked in, so the picture keeps its look (Leah, 2026-10-13).
            let clips = canvas.clippedAdjustments(onLayerAt: index)
            lower.buffer = canvas.composite([upper] + clips.filter(\.isVisible), onto: lower.buffer)
            for _ in 0...clips.count { canvas.removeLayer(at: index) }
            canvas.activeLayerIndex = index - 1
            return true
        }
    }

    /// Whether the layer at `index` (the active one if nil) could be merged down.
    public static func canMergeDown(_ canvas: Canvas, layerAt index: Int? = nil) -> Bool {
        let index = index ?? canvas.activeLayerIndex
        guard canvas.layers.indices.contains(index), canvas.layers[index].adjustment == nil else { return false }
        // Pixels can't be merged into an adjustment layer, which has none.
        return index > 0 && !canvas.layers[index].isLocked && !canvas.layers[index - 1].isLocked && canvas.layers[index - 1].adjustment == nil
            && !canvas.clippedAdjustments(onLayerAt: index).contains(where: \.isLocked)
    }

    /// Combines every visible layer into the lowest visible one, as they look together. Hidden layers stay.
    @discardableResult
    public static func mergeVisible(canvas: Canvas, history: History, context: SelectionContext) -> Bool {
        guard canMergeVisible(canvas) else { return false }
        return change("Merge Visible", canvas: canvas, history: history, context: context) {
            let visible = canvas.layers.filter(\.isVisible)
            let target = visible[0]
            target.buffer = canvas.composite(visible)
            target.opacity = 1
            target.blendMode = .normal
            target.adjustment = nil
            target.clipsToLayerBelow = false
            let active = canvas.activeLayer
            for layer in visible.dropFirst() {
                canvas.removeLayer(at: canvas.layers.firstIndex { $0 === layer }!)
            }
            canvas.activeLayerIndex = canvas.layers.firstIndex { $0 === (active.isVisible ? target : active) } ?? 0
            return true
        }
    }

    /// Stamp Visible (FR-8.6, §23 2026-10-28): a new layer just above the active one, named "Stamp", holding everything
    /// visible merged as it looks, while the layers themselves stay. It becomes active.
    @discardableResult
    public static func stampVisible(canvas: Canvas, history: History, context: SelectionContext) -> Bool {
        guard canvas.layers.contains(where: \.isVisible) else { return false }
        return change("Stamp Visible", canvas: canvas, history: history, context: context) {
            let stamp = Layer(name: "Stamp", buffer: canvas.composite(canvas.layers.filter(\.isVisible)))
            let index = canvas.indexAboveActiveLayer
            canvas.insertLayer(stamp, at: index)
            canvas.activeLayerIndex = index
            return true
        }
    }

    /// Shows and hides layers together as one step named `name`, for isolating a layer with Option-click (FR-8.6).
    /// Layers not in `visibility` keep theirs.
    @discardableResult
    public static func setVisibility(_ visibility: [LayerID: Bool], named name: String, canvas: Canvas, history: History) -> Bool {
        let edit = history.beginEdit(name, on: canvas)
        edit.willChangeLayers()
        for layer in canvas.layers {
            if let visible = visibility[layer.id] { layer.isVisible = visible }
        }
        return history.commit(edit)
    }

    public static func canMergeVisible(_ canvas: Canvas) -> Bool {
        let visible = canvas.layers.filter(\.isVisible)
        return visible.count > 1 && !visible.contains(where: \.isLocked)
    }

    /// Combines all visible layers into one; hidden layers are dropped.
    @discardableResult
    public static func flatten(canvas: Canvas, history: History, context: SelectionContext) -> Bool {
        guard canFlatten(canvas) else { return false }
        return change("Flatten", canvas: canvas, history: history, context: context) {
            let visible = canvas.layers.filter(\.isVisible)
            let bottom = canvas.layers[0]
            bottom.buffer = canvas.composite(visible)
            bottom.opacity = 1
            bottom.blendMode = .normal
            bottom.isVisible = true
            bottom.adjustment = nil
            bottom.clipsToLayerBelow = false
            while canvas.layers.count > 1 { canvas.removeLayer(at: 1) }
            canvas.activeLayerIndex = 0
            return true
        }
    }

    public static func canFlatten(_ canvas: Canvas) -> Bool {
        guard !canvas.layers.contains(where: \.isLocked) else { return false }
        let only = canvas.layers[0]
        return canvas.layers.count > 1 || !only.isVisible || only.opacity < 1 || only.blendMode != .normal
    }

    /// Moves a layer to a new position in the stack (0 is the bottom). The active layer stays active.
    @discardableResult
    public static func move(from source: Int, to destination: Int, canvas: Canvas, history: History, context: SelectionContext) -> Bool {
        guard source != destination, canvas.layers.indices.contains(source), canvas.layers.indices.contains(destination) else { return false }
        return change("Move Layer", canvas: canvas, history: history, context: context) {
            let active = canvas.activeLayer
            canvas.moveLayer(from: source, to: destination)
            canvas.activeLayerIndex = canvas.layers.firstIndex { $0 === active } ?? destination
            return true
        }
    }

    /// Changes one layer's settings (name, visibility, opacity, blend mode, lock) as a step named `name`.
    @discardableResult
    public static func update(_ name: String, layerAt index: Int, canvas: Canvas, history: History, _ body: (Layer) -> Void) -> Bool {
        guard canvas.layers.indices.contains(index) else { return false }
        let edit = history.beginEdit(name, on: canvas)
        edit.willChangeLayers()
        body(canvas.layers[index])
        return history.commit(edit)
    }

    /// "Layer 1", "Layer 2"… one more than the highest number in use.
    static func nextName(in canvas: Canvas) -> String {
        let numbers = canvas.layers.compactMap { layer -> Int? in
            guard layer.name.hasPrefix("Layer ") else { return nil }
            return Int(layer.name.dropFirst("Layer ".count))
        }
        return "Layer \((numbers.max() ?? 0) + 1)"
    }

    static func change(_ name: String, canvas: Canvas, history: History, context: SelectionContext, _ body: () -> Bool) -> Bool {
        SelectionActions.placeFloating(canvas: canvas, history: history, context: context)
        let edit = history.beginEdit(name, on: canvas)
        edit.willChangeLayers()
        guard body() else { return false }
        return history.commit(edit)
    }
}
