/// Everything that changes the layer stack (FR-8.2), each as one undo step. A floating selection is
/// placed first, since it belongs to a layer that may move, merge or go away.
public enum LayerActions {
    /// A new transparent layer above the active one, which becomes active.
    @discardableResult
    public static func add(canvas: Canvas, history: History, context: SelectionContext) -> Bool {
        change("New Layer", canvas: canvas, history: history, context: context) {
            let layer = Layer(name: nextName(in: canvas), buffer: PixelBuffer(width: canvas.size.width, height: canvas.size.height))
            canvas.insertLayer(layer, at: canvas.activeLayerIndex + 1)
            canvas.activeLayerIndex += 1
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
            canvas.insertLayer(layer, at: canvas.activeLayerIndex + 1)
            canvas.activeLayerIndex += 1
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
        return change("Merge Adjustment", canvas: canvas, history: history, context: context) {
            let merged = canvas.layers.prefix(canvas.activeLayerIndex + 1).filter(\.isVisible)
            let target = merged[0]
            target.buffer = canvas.composite(merged)
            target.opacity = 1
            target.blendMode = .normal
            target.adjustment = nil
            for layer in merged.dropFirst() {
                canvas.removeLayer(at: canvas.layers.firstIndex { $0 === layer }!)
            }
            canvas.activeLayerIndex = canvas.layers.firstIndex { $0 === target }!
            return true
        }
    }

    /// A hidden adjustment changes nothing, so there's nothing to apply.
    public static func canApplyAdjustment(_ canvas: Canvas) -> Bool {
        let index = canvas.activeLayerIndex
        let layer = canvas.layers[index]
        guard index > 0, layer.adjustment != nil, layer.isVisible else { return false }
        let merged = canvas.layers.prefix(index + 1).filter(\.isVisible)
        return merged.count > 1 && !merged.contains(where: \.isLocked)
    }

    /// A copy of the active layer, with its settings, just above it.
    @discardableResult
    public static func duplicate(canvas: Canvas, history: History, context: SelectionContext) -> Bool {
        change("Duplicate Layer", canvas: canvas, history: history, context: context) {
            let source = canvas.activeLayer
            let copy = Layer(name: "\(source.name) copy", buffer: source.buffer.copy())
            copy.isVisible = source.isVisible
            copy.opacity = source.opacity
            copy.blendMode = source.blendMode
            copy.adjustment = source.adjustment
            canvas.insertLayer(copy, at: canvas.activeLayerIndex + 1)
            canvas.activeLayerIndex += 1
            return true
        }
    }

    /// Deletes the active layer unless it's locked or the only one. The layer below becomes active.
    @discardableResult
    public static func delete(canvas: Canvas, history: History, context: SelectionContext) -> Bool {
        guard canDelete(canvas) else { return false }
        return change("Delete Layer", canvas: canvas, history: history, context: context) {
            let index = canvas.activeLayerIndex
            canvas.removeLayer(at: index)
            canvas.activeLayerIndex = max(0, index - 1)
            return true
        }
    }

    public static func canDelete(_ canvas: Canvas) -> Bool {
        canvas.layers.count > 1 && !canvas.activeLayer.isLocked
    }

    /// Combines the active layer into the one below, using its blend mode and opacity. The result keeps
    /// the lower layer's name and settings. On an adjustment layer this is Merge Adjustment.
    @discardableResult
    public static func mergeDown(canvas: Canvas, history: History, context: SelectionContext) -> Bool {
        if canvas.activeLayer.adjustment != nil { return applyAdjustment(canvas: canvas, history: history, context: context) }
        guard canMergeDown(canvas) else { return false }
        return change("Merge Down", canvas: canvas, history: history, context: context) {
            let index = canvas.activeLayerIndex
            let upper = canvas.layers[index], lower = canvas.layers[index - 1]
            lower.buffer = canvas.composite([upper], onto: lower.buffer)
            canvas.removeLayer(at: index)
            canvas.activeLayerIndex = index - 1
            return true
        }
    }

    public static func canMergeDown(_ canvas: Canvas) -> Bool {
        if canvas.activeLayer.adjustment != nil { return canApplyAdjustment(canvas) }
        let index = canvas.activeLayerIndex
        // Pixels can't be merged into an adjustment layer, which has none.
        return index > 0 && !canvas.layers[index].isLocked && !canvas.layers[index - 1].isLocked && canvas.layers[index - 1].adjustment == nil
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
            let active = canvas.activeLayer
            for layer in visible.dropFirst() {
                canvas.removeLayer(at: canvas.layers.firstIndex { $0 === layer }!)
            }
            canvas.activeLayerIndex = canvas.layers.firstIndex { $0 === (active.isVisible ? target : active) } ?? 0
            return true
        }
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

    private static func change(_ name: String, canvas: Canvas, history: History, context: SelectionContext, _ body: () -> Bool) -> Bool {
        SelectionActions.placeFloating(canvas: canvas, history: history, context: context)
        let edit = history.beginEdit(name, on: canvas)
        edit.willChangeLayers()
        guard body() else { return false }
        return history.commit(edit)
    }
}
