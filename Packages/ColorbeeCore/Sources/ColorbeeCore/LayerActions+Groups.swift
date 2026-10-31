/// Where dragged layers land in the Layers panel (stage 26): just above or below a row, or inside a group, at its top.
public enum LayerDrop: Equatable, Sendable {
    case above(LayerID)
    case below(LayerID)
    case into(LayerID)
}

/// Layer groups (FR-8.7, stages 25 and 26), each one undo step.
extension LayerActions {
    // MARK: Group and Ungroup

    /// Layer ▸ Group (⌘G): the chosen layers into a new group, "Group 1" and so on (Q25.7), where the topmost of them
    /// was. A chosen layer's "Only the layer below" adjustments go with it. The group becomes active.
    @discardableResult
    public static func group(_ ids: Set<LayerID>, canvas: Canvas, history: History, context: SelectionContext) -> Bool {
        guard canGroup(ids, in: canvas) else { return false }
        return change("Group Layers", canvas: canvas, history: history, context: context) {
            let moving = movingLayers(ids, in: canvas)
            let roots = moving.filter { layer in !moving.contains { $0.id == layer.groupID } }
            let group = Layer.group(named: canvas.nextGroupName(), size: canvas.size)
            group.groupID = roots.last!.groupID
            for root in roots { root.groupID = group.id }
            // Above the topmost of them; keeping groups together then gathers the rest just below it.
            canvas.insertLayer(group, at: canvas.layers.firstIndex { $0 === moving.last! }! + 1)
            canvas.keepGroupsTogether()
            canvas.activeLayerIndex = canvas.layers.firstIndex { $0 === group }!
            return true
        }
    }

    public static func canGroup(_ ids: Set<LayerID>, in canvas: Canvas) -> Bool {
        !movingLayers(ids, in: canvas).isEmpty
    }

    /// Layer ▸ Ungroup (⇧⌘G): the active group's layers stay where they are, in the group it was in. The topmost of
    /// them becomes active.
    @discardableResult
    public static func ungroup(canvas: Canvas, history: History, context: SelectionContext) -> Bool {
        guard canUngroup(canvas) else { return false }
        return change("Ungroup", canvas: canvas, history: history, context: context) {
            let index = canvas.activeLayerIndex
            canvas.removeLayer(at: index)
            canvas.activeLayerIndex = max(0, index - 1)
            return true
        }
    }

    public static func canUngroup(_ canvas: Canvas) -> Bool {
        canvas.activeLayer.isGroup && canvas.layers.count > 1
    }

    // MARK: Merge Group

    /// Merge Down on a group (Q25.6): the group becomes one layer that looks the same, with its name, opacity and
    /// blend mode (Normal for Pass Through). Hidden layers inside it are dropped. An adjustment inside a Pass Through
    /// group that changed what's below the group can't be kept that way, as with Merge Layers.
    @discardableResult
    static func mergeGroup(canvas: Canvas, history: History, context: SelectionContext) -> Bool {
        guard canMergeGroup(canvas, at: canvas.activeLayerIndex) else { return false }
        return change("Merge Group", canvas: canvas, history: history, context: context) {
            let index = canvas.activeLayerIndex
            let group = canvas.layers[index]
            let span = canvas.span(ofLayerAt: index)
            // What shows inside the group, as if the group itself were showing.
            let inside = canvas.layers[span.dropLast()].filter { layer in
                layer.isVisible && layer.opacity > 0
                    && canvas.ancestors(of: layer).prefix { $0 !== group }.allSatisfy { $0.isVisible && $0.opacity > 0 }
            }
            let merged = Layer(name: group.name, buffer: canvas.composite(inside))
            merged.isVisible = group.isVisible
            merged.opacity = group.opacity
            merged.blendMode = group.passesThrough ? .normal : group.blendMode
            merged.groupID = group.groupID
            // The group's mask stays a mask, on the layer that takes its place.
            merged.mask = group.mask
            merged.maskEnabled = group.maskEnabled
            for at in span.reversed() { canvas.removeLayer(at: at) }
            canvas.insertLayer(merged, at: span.lowerBound)
            canvas.activeLayerIndex = span.lowerBound
            return true
        }
    }

    static func canMergeGroup(_ canvas: Canvas, at index: Int) -> Bool {
        canvas.layers.indices.contains(index) && canvas.layers[index].isGroup
            && !canvas.layers[canvas.span(ofLayerAt: index)].contains(where: canvas.isLocked)
    }

    // MARK: Moving into and out of groups

    /// Moves the chosen layers (a group with everything in it, a layer with its clipped adjustments) together, keeping
    /// their order, to `drop` (stage 26). Above or below a row puts them in that row's group; into a group puts them at
    /// its top. Nothing moves into itself. The active layer stays active.
    @discardableResult
    public static func moveLayers(_ ids: Set<LayerID>, to drop: LayerDrop, canvas: Canvas, history: History, context: SelectionContext) -> Bool {
        guard let (order, parent, roots) = plannedMove(ids, to: drop, in: canvas) else { return false }
        return change("Move Layers", canvas: canvas, history: history, context: context) {
            for root in roots { root.groupID = parent }
            canvas.reorder(order)
            return true
        }
    }

    public static func canMove(_ ids: Set<LayerID>, to drop: LayerDrop, in canvas: Canvas) -> Bool {
        plannedMove(ids, to: drop, in: canvas) != nil
    }

    /// The new order, the group the moved layers go into, and those of them that change group; nil if nothing would
    /// change or the drop is inside what's moving.
    private static func plannedMove(_ ids: Set<LayerID>, to drop: LayerDrop, in canvas: Canvas) -> (order: [Layer], parent: LayerID?, roots: [Layer])? {
        let moving = spans(of: movingLayers(ids, in: canvas), in: canvas)
        guard !moving.isEmpty else { return nil }
        let target: LayerID = switch drop {
        case .above(let id), .below(let id), .into(let id): id
        }
        guard let targetLayer = canvas.layer(withID: target), !moving.contains(where: { $0 === targetLayer }) else { return nil }
        let rest = canvas.layers.filter { layer in !moving.contains { $0 === layer } }
        let at = rest.firstIndex { $0 === targetLayer }!
        let parent: LayerID?
        let index: Int
        switch drop {
        case .above:
            parent = targetLayer.groupID
            index = at + 1
        case .below:
            parent = targetLayer.groupID
            var start = at
            if targetLayer.isGroup {
                while start > 0, canvas.ancestors(of: rest[start - 1]).contains(where: { $0 === targetLayer }) { start -= 1 }
            }
            index = start
        case .into:
            guard targetLayer.isGroup else { return nil }
            parent = targetLayer.id
            index = at
        }
        let roots = moving.filter { layer in !moving.contains { $0.id == layer.groupID } }
        let order = Array(rest[..<index]) + moving + Array(rest[index...])
        let unchanged = zip(order, canvas.layers).allSatisfy { $0 === $1 } && roots.allSatisfy { $0.groupID == parent }
        return unchanged ? nil : (order, parent, roots)
    }

    // MARK: Helpers

    /// The chosen layers that move as themselves, in canvas order: not those inside a chosen group (they come with it),
    /// nor a clipped adjustment whose layer is chosen. A chosen pixel layer brings its clipped adjustments.
    static func movingLayers(_ ids: Set<LayerID>, in canvas: Canvas) -> [Layer] {
        var result: [Layer] = []
        for (index, layer) in canvas.layers.enumerated() where ids.contains(layer.id) {
            if canvas.ancestors(of: layer).contains(where: { ids.contains($0.id) }) { continue }
            if layer.adjustment != nil, layer.clipsToLayerBelow, let base = canvas.clipBaseIndex(forLayerAt: index),
               ids.contains(canvas.layers[base].id) { continue }
            result.append(layer)
            if layer.isPixelLayer {
                result += canvas.clippedLayers(onLayerAt: index).filter { clip in !result.contains { $0 === clip } }
            }
        }
        return canvas.layers.filter { layer in result.contains { $0 === layer } }
    }

    /// `layers` with each group's whole span, in canvas order.
    static func spans(of layers: [Layer], in canvas: Canvas) -> [Layer] {
        var indices = Set<Int>()
        for layer in layers {
            guard let index = canvas.layers.firstIndex(where: { $0 === layer }) else { continue }
            indices.formUnion(canvas.span(ofLayerAt: index))
        }
        return indices.sorted().map { canvas.layers[$0] }
    }
}
