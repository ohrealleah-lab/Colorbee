/// Commands on several chosen layers at once (FR-8.6), each one undo step. `ids` are the chosen layers; the active
/// layer is always one of them.
extension LayerActions {
    // MARK: Merge Layers

    /// Combines the chosen visible layers into one, as they look together, where the topmost of them was and with its
    /// name (Leah, 2026-10-27). A chosen adjustment layer is baked into the chosen layers below it. Each chosen pixel
    /// layer's "Only the layer below" adjustments go with it, as in Merge Down. Hidden chosen layers stay as they are.
    @discardableResult
    public static func mergeLayers(_ ids: Set<LayerID>, canvas: Canvas, history: History, context: SelectionContext) -> Bool {
        guard canMergeLayers(ids, in: canvas) else { return false }
        return change("Merge Layers", canvas: canvas, history: history, context: context) {
            let merging = mergedIndices(ids, in: canvas)
            let stack = merging.map { canvas.layers[$0] }
            let going = Set(merging.flatMap { [$0] + clipIndices(onLayerAt: $0, in: canvas) }.map { canvas.layers[$0].id })
            let name = stack.last { ids.contains($0.id) }!.name
            // Above the merge, where the result goes.
            let anchor = canvas.layers.suffix(from: merging.last! + 1).first { !going.contains($0.id) }
            // The lowest pixel layer holds the result, so a merge that starts at the background keeps it the background.
            let holder = stack.first { $0.adjustment == nil }!
            let merged = canvas.composite(stack)
            for layer in canvas.layers where going.contains(layer.id) && layer !== holder {
                canvas.removeLayer(at: canvas.layers.firstIndex { $0 === layer }!)
            }
            holder.buffer = merged
            holder.name = name
            holder.opacity = 1
            holder.blendMode = .normal
            holder.isVisible = true
            holder.adjustment = nil
            holder.clipsToLayerBelow = false
            let from = canvas.layers.firstIndex { $0 === holder }!
            let above = anchor.flatMap { anchor in canvas.layers.firstIndex { $0 === anchor } } ?? canvas.layers.count
            canvas.moveLayer(from: from, to: above - 1)
            canvas.activeLayerIndex = above - 1
            return true
        }
    }

    /// At least two visible chosen layers, one with pixels, and nothing locked among the chosen layers or what goes
    /// with them (locked layers can't be merged into).
    public static func canMergeLayers(_ ids: Set<LayerID>, in canvas: Canvas) -> Bool {
        let merging = mergedIndices(ids, in: canvas)
        guard merging.count > 1, merging.contains(where: { canvas.layers[$0].adjustment == nil }) else { return false }
        let involved = merging.flatMap { [$0] + clipIndices(onLayerAt: $0, in: canvas) }.map { canvas.layers[$0] }
        return !involved.contains(where: \.isLocked) && !canvas.layers.contains { ids.contains($0.id) && $0.isLocked }
    }

    /// The layers Merge Layers combines, bottom to top: the visible chosen ones, with each chosen pixel layer's visible
    /// clipped adjustments. A chosen clipped adjustment whose layer isn't merged stays as it is.
    static func mergedIndices(_ ids: Set<LayerID>, in canvas: Canvas) -> [Int] {
        var result = Set<Int>()
        for (index, layer) in canvas.layers.enumerated() where ids.contains(layer.id) && layer.isVisible {
            if layer.adjustment == nil {
                result.insert(index)
                result.formUnion(clipIndices(onLayerAt: index, in: canvas).filter { canvas.layers[$0].isVisible })
            } else if !layer.clipsToLayerBelow {
                result.insert(index)
            }
        }
        return result.sorted()
    }

    /// The indices of the clipped adjustments on the pixel layer at `index`, bottom to top.
    private static func clipIndices(onLayerAt index: Int, in canvas: Canvas) -> [Int] {
        Array((index + 1)..<(index + 1 + canvas.clippedAdjustments(onLayerAt: index).count))
    }

    // MARK: Delete, Duplicate, Move

    /// Deletes every chosen layer, with each one's clipped adjustments. The layer below the lowest of them becomes active.
    @discardableResult
    public static func deleteLayers(_ ids: Set<LayerID>, canvas: Canvas, history: History, context: SelectionContext) -> Bool {
        guard canDeleteLayers(ids, in: canvas) else { return false }
        return change("Delete Layers", canvas: canvas, history: history, context: context) {
            let going = deletedIndices(ids, in: canvas)
            let lowest = going.first!
            for index in going.reversed() { canvas.removeLayer(at: index) }
            canvas.activeLayerIndex = max(0, lowest - 1)
            return true
        }
    }

    /// At least one layer must stay, and locked layers can't be deleted.
    public static func canDeleteLayers(_ ids: Set<LayerID>, in canvas: Canvas) -> Bool {
        let going = deletedIndices(ids, in: canvas)
        return !going.isEmpty && going.count < canvas.layers.count && !going.contains { canvas.layers[$0].isLocked }
    }

    private static func deletedIndices(_ ids: Set<LayerID>, in canvas: Canvas) -> [Int] {
        var result = Set<Int>()
        for (index, layer) in canvas.layers.enumerated() where ids.contains(layer.id) {
            result.insert(index)
            result.formUnion(clipIndices(onLayerAt: index, in: canvas))
        }
        return result.sorted()
    }

    /// A copy of every chosen layer, each just above its own. Returns the copies, with the active layer's copy active,
    /// or nil if nothing was copied.
    @discardableResult
    public static func duplicateLayers(_ ids: Set<LayerID>, canvas: Canvas, history: History, context: SelectionContext) -> [LayerID]? {
        var copies: [LayerID] = []
        let done = change("Duplicate Layers", canvas: canvas, history: history, context: context) {
            let active = canvas.activeLayer
            var activeCopy: Layer?
            // Top down, so inserting a copy never moves a layer still to be copied.
            for source in canvas.layers.reversed() where ids.contains(source.id) {
                canvas.activeLayerIndex = canvas.layers.firstIndex { $0 === source }!
                let copy = insertCopyOfActiveLayer(canvas: canvas)
                copies.append(copy.id)
                if source === active { activeCopy = copy }
            }
            guard !copies.isEmpty else { return false }
            canvas.activeLayerIndex = canvas.layers.firstIndex { $0 === activeCopy } ?? canvas.activeLayerIndex
            return true
        }
        return done ? copies : nil
    }

    /// Moves the chosen layers together, keeping their order, so the one dragged from `source` lands at `destination`
    /// (stack indices; 0 is the bottom). The active layer stays active.
    @discardableResult
    public static func moveLayers(_ ids: Set<LayerID>, dragging source: Int, to destination: Int, canvas: Canvas, history: History,
                                  context: SelectionContext) -> Bool {
        guard canvas.layers.indices.contains(source), ids.contains(canvas.layers[source].id) else { return false }
        let block = canvas.layers.filter { ids.contains($0.id) }
        let rest = canvas.layers.filter { !ids.contains($0.id) }
        let draggedLayer = canvas.layers[source]
        let start = min(max(0, destination - block.firstIndex { $0 === draggedLayer }!), rest.count)
        let order = Array(rest[..<start]) + block + Array(rest[start...])
        guard !zip(order, canvas.layers).allSatisfy({ $0 === $1 }) else { return false }
        return change("Move Layers", canvas: canvas, history: history, context: context) {
            let active = canvas.activeLayer
            for (target, layer) in order.enumerated() {
                canvas.moveLayer(from: canvas.layers.firstIndex { $0 === layer }!, to: target)
            }
            canvas.activeLayerIndex = canvas.layers.firstIndex { $0 === active }!
            return true
        }
    }

    // MARK: Settings

    /// Changes the settings of every chosen layer (visibility, lock, opacity, blend mode) as one step named `name`.
    @discardableResult
    public static func update(_ name: String, layersWithIDs ids: Set<LayerID>, canvas: Canvas, history: History, _ body: (Layer) -> Void) -> Bool {
        let chosen = canvas.layers.filter { ids.contains($0.id) }
        guard !chosen.isEmpty else { return false }
        let edit = history.beginEdit(name, on: canvas)
        edit.willChangeLayers()
        chosen.forEach(body)
        return history.commit(edit)
    }
}
