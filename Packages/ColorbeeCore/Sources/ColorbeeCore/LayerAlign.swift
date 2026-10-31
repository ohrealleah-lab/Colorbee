/// Layer ▸ Align and Distribute (FR-8.6, stage 24). Layers have no position of their own: each is a canvas-sized
/// picture, so lining layers up moves the pixels inside each one, by the box around its visible pixels.
public enum LayerAlignment: CaseIterable, Sendable {
    case left, centers, right, top, middle, bottom

    public var title: String {
        switch self {
        case .left: "Left"
        case .centers: "Centers"
        case .right: "Right"
        case .top: "Top"
        case .middle: "Middle"
        case .bottom: "Bottom"
        }
    }
}

public enum LayerDistribution: CaseIterable, Sendable {
    case horizontally, vertically

    public var title: String {
        switch self {
        case .horizontally: "Distribute Horizontally"
        case .vertically: "Distribute Vertically"
        }
    }
}

public enum LayerAlign {
    /// Why nothing moved.
    public enum Refusal: Error, Equatable {
        /// This layer's pixels would go past the canvas's edge, where they'd be lost (Q24.1).
        case offCanvas(String)
    }

    /// What moves as one: a chosen pixel layer, or a chosen group's pixel layers together (stage 26).
    public struct Unit {
        public let layers: [Layer]
        /// The chosen group they're in, whose mask moves with them (review X, finding 8).
        public var group: Layer? = nil

        /// The box around all their visible pixels.
        public var box: IntRect? {
            let boxes = layers.compactMap(\.buffer.visibleBounds)
            return boxes.dropFirst().reduce(boxes.first) { $0?.union($1) }
        }
    }

    /// The chosen layers as units: each pixel layer on its own, and each group with its pixel layers, a layer inside a
    /// chosen group going with the group.
    public static func units(_ ids: Set<LayerID>, in canvas: Canvas) -> [Unit] {
        canvas.layers.filter { layer in
            ids.contains(layer.id) && (layer.isPixelLayer || layer.isGroup) && !canvas.ancestors(of: layer).contains { ids.contains($0.id) }
        }.map { layer in
            guard layer.isGroup, let index = canvas.layers.firstIndex(where: { $0 === layer }) else { return Unit(layers: [layer]) }
            return Unit(layers: canvas.layers[canvas.memberRange(ofGroupAt: index)].filter(\.isPixelLayer), group: layer)
        }.filter { !$0.layers.isEmpty }
    }

    /// Where `layers` move: each one's box set against `reference` (the canvas, the selection, or the box around them
    /// all). Layers with no visible pixels stay put.
    public static func offsets(aligning layers: [Layer], to alignment: LayerAlignment, reference: IntRect) -> [LayerID: IntPoint] {
        offsets(aligning: layers.map { Unit(layers: [$0]) }, to: alignment, reference: reference)
    }

    /// Where `units` move: each one's box set against `reference`, every layer in it by the same amount.
    public static func offsets(aligning units: [Unit], to alignment: LayerAlignment, reference: IntRect) -> [LayerID: IntPoint] {
        var offsets: [LayerID: IntPoint] = [:]
        for unit in units {
            guard let box = unit.box else { continue }
            let dx: Int, dy: Int
            switch alignment {
            case .left: (dx, dy) = (reference.minX - box.minX, 0)
            case .right: (dx, dy) = (reference.maxX - box.maxX, 0)
            case .centers: (dx, dy) = ((reference.minX + reference.maxX - box.minX - box.maxX) / 2, 0)
            case .top: (dx, dy) = (0, reference.minY - box.minY)
            case .bottom: (dx, dy) = (0, reference.maxY - box.maxY)
            case .middle: (dx, dy) = (0, (reference.minY + reference.maxY - box.minY - box.maxY) / 2)
            }
            for layer in unit.layers + [unit.group].compactMap({ $0 }) { offsets[layer.id] = IntPoint(x: dx, y: dy) }
        }
        return offsets
    }

    /// Equal gaps between the layers' boxes, in their order across (or down) the picture: the first and last stay
    /// where they are.
    public static func offsets(distributing layers: [Layer], _ distribution: LayerDistribution) -> [LayerID: IntPoint] {
        offsets(distributing: layers.map { Unit(layers: [$0]) }, distribution)
    }

    public static func offsets(distributing units: [Unit], _ distribution: LayerDistribution) -> [LayerID: IntPoint] {
        let boxes = units.compactMap { unit in unit.box.map { (unit.layers + [unit.group].compactMap { $0 }, $0) } }
        guard boxes.count >= 3 else { return [:] }
        let across = distribution == .horizontally
        let sorted = boxes.sorted { across ? $0.1.minX < $1.1.minX : $0.1.minY < $1.1.minY }
        func start(_ box: IntRect) -> Int { across ? box.minX : box.minY }
        func length(_ box: IntRect) -> Int { across ? box.width : box.height }
        let first = sorted.first!.1, last = sorted.last!.1
        let span = start(last) + length(last) - start(first)
        let gap = Double(span - sorted.map { length($0.1) }.reduce(0, +)) / Double(sorted.count - 1)
        var offsets: [LayerID: IntPoint] = [:]
        var position = Double(start(first))
        for (layers, box) in sorted {
            let move = Int(position.rounded()) - start(box)
            for layer in layers { offsets[layer.id] = across ? IntPoint(x: move, y: 0) : IntPoint(x: 0, y: move) }
            position += Double(length(box)) + gap
        }
        return offsets
    }

    /// Moves each layer's pixels by its offset as one step named `name`, or refuses (nothing moves) if any would go
    /// off the canvas. Nil when it moved, or there was nothing to move.
    @discardableResult
    public static func move(_ offsets: [LayerID: IntPoint], named name: String, canvas: Canvas, history: History,
                            context: SelectionContext) -> Refusal? {
        let moving = canvas.layers.filter { offsets[$0.id].map { $0 != IntPoint(x: 0, y: 0) } ?? false }
        for layer in moving {
            guard let box = layer.buffer.visibleBounds, let offset = offsets[layer.id] else { continue }
            if !canvas.bounds.contains(box.offsetBy(dx: offset.x, dy: offset.y)) { return .offCanvas(layer.name) }
        }
        guard !moving.isEmpty else { return nil }
        _ = LayerActions.change(name, canvas: canvas, history: history, context: context) {
            func shifted(_ buffer: PixelBuffer, by offset: IntPoint) -> PixelBuffer {
                let moved = PixelBuffer(width: canvas.size.width, height: canvas.size.height)
                let kept = canvas.bounds.intersection(canvas.bounds.offsetBy(dx: -offset.x, dy: -offset.y))
                moved.setPixels(buffer.pixels(in: kept), in: kept.offsetBy(dx: offset.x, dy: offset.y))
                return moved
            }
            for layer in moving {
                let offset = offsets[layer.id]!
                if layer.isPixelLayer { layer.buffer = shifted(layer.buffer, by: offset) }
                // The mask moves with its layer, as in Photoshop (review X, finding 8).
                if let mask = layer.mask, !mask.buffer.isUntouched {
                    layer.mask = mask.copy(buffer: shifted(mask.buffer, by: offset))
                }
                // A text layer's words move with its pixels, and are drawn again if words past the edge came on
                // (review X, finding 4; Y, finding 4).
                if let text = layer.text {
                    guard text.isUpright else {
                        layer.text = nil
                        continue
                    }
                    let fitted = text.fitted(scale: 1, dx: Double(offset.x), dy: Double(offset.y))
                    if fitted.hasFont { layer.buffer = fitted.drawn(size: canvas.size, colorSpace: canvas.colorSpace) }
                    layer.text = fitted
                }
            }
            return true
        }
        return nil
    }
}

extension PixelBuffer {
    /// The box around every pixel that isn't fully clear; nil when there are none.
    public var visibleBounds: IntRect? {
        let rows = ParallelRows.map(height) { y -> (Int, Int)? in
            let row = row(y)
            guard let first = (0..<width).first(where: { row[$0].a > 0 }) else { return nil }
            return (first, (first..<width).last { row[$0].a > 0 }!)
        }
        guard let top = rows.firstIndex(where: { $0 != nil }), let bottom = rows.lastIndex(where: { $0 != nil }) else { return nil }
        let spans = rows.compactMap { $0 }
        let left = spans.map(\.0).min()!, right = spans.map(\.1).max()!
        return IntRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
    }
}
