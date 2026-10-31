/// One entry of the layer stack as a tree: a layer, or a group with the layers in it, bottom to top (stage 25).
public struct LayerNode {
    public let layer: Layer
    public let children: [LayerNode]
}

/// Layer groups (FR-8.7, stages 25 and 26). `Canvas.layers` stays one flat list: a group's layers sit just below its
/// row, and each names the group it's in. These answer the questions every walk over the layers needs.
extension Canvas {
    /// The group `layer` is in, if any.
    public func group(of layer: Layer) -> Layer? {
        layer.groupID.flatMap(self.layer(withID:))
    }

    /// The groups `layer` is in, innermost first.
    public func ancestors(of layer: Layer) -> [Layer] {
        var result: [Layer] = []
        var current = group(of: layer)
        while let group = current, !result.contains(where: { $0 === group }) {
            result.append(group)
            current = self.group(of: group)
        }
        return result
    }

    /// How deep `layer` sits: 0 at the top, 1 inside a group, and so on.
    public func depth(of layer: Layer) -> Int {
        ancestors(of: layer).count
    }

    /// Whether `layer` shows: it and every group it's in are visible and not fully faded (Q25.4).
    public func isShown(_ layer: Layer) -> Bool {
        layer.isVisible && layer.opacity > 0 && ancestors(of: layer).allSatisfy { $0.isVisible && $0.opacity > 0 }
    }

    /// The layers that show, bottom to top, group rows included.
    public var shownLayers: [Layer] {
        layers.filter(isShown)
    }

    /// Whether `layer` is locked, by its own padlock or its group's (Q25.4).
    public func isLocked(_ layer: Layer) -> Bool {
        layer.isLocked || ancestors(of: layer).contains(where: \.isLocked)
    }

    /// Whether `layer` keeps its transparent pixels, by its own setting or its group's.
    public func locksTransparency(_ layer: Layer) -> Bool {
        layer.isPixelLayer && (layer.locksTransparency || ancestors(of: layer).contains(where: \.locksTransparency))
    }

    /// The indices of the layers inside the group at `index` (at any depth), bottom to top: just below its row.
    public func memberRange(ofGroupAt index: Int) -> Range<Int> {
        guard layers.indices.contains(index), layers[index].isGroup else { return index..<index }
        let group = layers[index]
        var start = index
        while start > 0, ancestors(of: layers[start - 1]).contains(where: { $0 === group }) { start -= 1 }
        return start..<index
    }

    /// The indices `layer` covers: just itself, or a group with everything in it.
    public func span(ofLayerAt index: Int) -> Range<Int> {
        layers[index].isGroup ? memberRange(ofGroupAt: index).lowerBound..<(index + 1) : index..<(index + 1)
    }

    /// `stack` (in canvas order) as a tree. A layer whose group isn't in `stack` sits with the nearest group that is,
    /// or at the top, so a stack cut short inside a group (the layers an adjustment sees) still composites.
    public func tree(of stack: [Layer]) -> [LayerNode] {
        let present = Set(stack.filter(\.isGroup).map(\.id))
        var members: [LayerID?: [Layer]] = [:]
        for layer in stack {
            var parent = layer.groupID
            while let id = parent, !present.contains(id) { parent = self.layer(withID: id)?.groupID }
            members[parent, default: []].append(layer)
        }
        func nodes(in parent: LayerID?) -> [LayerNode] {
            (members[parent] ?? []).map { LayerNode(layer: $0, children: $0.isGroup ? nodes(in: $0.id) : []) }
        }
        return nodes(in: nil)
    }

    /// Puts every group's layers together just below its row, keeping their order, and takes out of a group any layer
    /// whose group is gone. Every layer command ends with this (`LayerActions.change`), so none can leave a group torn
    /// apart. The active layer stays active.
    func keepGroupsTogether() {
        let groups = Set(layers.filter(\.isGroup).map(\.id))
        for layer in layers where layer.groupID.map({ !groups.contains($0) }) == true { layer.groupID = nil }
        // A group can't end up inside itself.
        for layer in layers where layer.isGroup && ancestors(of: layer).contains(where: { $0 === layer }) { layer.groupID = nil }
        func flat(_ nodes: [LayerNode]) -> [Layer] {
            nodes.flatMap { $0.layer.isGroup ? flat($0.children) + [$0.layer] : [$0.layer] }
        }
        let ordered = flat(tree(of: layers))
        guard !zip(ordered, layers).allSatisfy({ $0 === $1 }) else { return }
        reorder(ordered)
    }

    /// "Group 1", "Group 2"… one more than the highest number in use (Q25.7).
    func nextGroupName() -> String {
        let numbers = layers.compactMap { layer -> Int? in
            guard layer.isGroup, layer.name.hasPrefix("Group ") else { return nil }
            return Int(layer.name.dropFirst("Group ".count))
        }
        return "Group \((numbers.max() ?? 0) + 1)"
    }
}
