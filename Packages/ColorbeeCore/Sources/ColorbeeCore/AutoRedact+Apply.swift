extension AutoRedact {
    public enum Outcome: Equatable, Sendable {
        case redacted
        case nothingChanged
        /// A locked layer has pixels under a box, so nothing was redacted.
        case locked(layerName: String)
    }

    /// The pixel layers with anything in `selection` (or anywhere, with none), bottom to top, and the first of
    /// them that's locked. Batch Redact changes all of them, so a locked one stops it.
    public static func layersWithPixels(in selection: SelectionMask?, canvas: Canvas) -> (layers: [Layer], locked: Layer?) {
        let area = (selection?.bounds ?? canvas.bounds).intersection(canvas.bounds)
        guard !area.isEmpty else { return ([], nil) }
        func hasPixels(_ layer: Layer) -> Bool {
            for y in area.minY..<area.maxY {
                let row = layer.buffer.row(y)
                for x in area.minX..<area.maxX where row[x].a > 0 && (selection.map { $0[x, y] > 0 } ?? true) { return true }
            }
            return false
        }
        let layers = canvas.layers.filter { $0.adjustment == nil && hasPixels($0) }
        return (layers, layers.first(where: \.isLocked))
    }

    /// Batch Redact (FR-9.4): `effect` in `selection` on every layer with pixels under it, as one step, like
    /// Auto-Redact (Leah; review H, finding 3). If a locked layer has pixels there, nothing is changed.
    public static func apply(_ effect: Effect, in selection: SelectionMask, canvas: Canvas, history: History) -> Outcome {
        let (layers, locked) = layersWithPixels(in: selection, canvas: canvas)
        if let locked { return .locked(layerName: locked.name) }
        guard !layers.isEmpty else { return .nothingChanged }
        let edit = history.beginEdit(effect.name, on: canvas)
        for layer in layers {
            Effects.apply(effect, to: layer, selection: selection, edit: edit)
        }
        return history.commit(edit) ? .redacted : .nothingChanged
    }

    /// Redacts each item's whole box on every layer with pixels under it, as one step, so text is covered
    /// whichever layer holds it (review E, finding 1). Blur and Pixelate are as strong as each item's own
    /// text needs (finding 3). If a locked layer has pixels under a box, nothing is redacted.
    public static func apply(_ matches: [RedactionMatch], treatment: RedactionTreatment, fill: Pixel,
                             canvas: Canvas, history: History) -> Outcome {
        if let locked = lockedLayer(under: matches, canvas: canvas) { return .locked(layerName: locked.name) }
        let boxes = boxes(of: matches, canvas: canvas)
        let pixelLayers = canvas.layers.filter { $0.adjustment == nil }
        let edit = history.beginEdit("Auto-Redact", on: canvas)
        for box in boxes {
            let strength = max(6, Double(box.height) / 3)
            let effect: Effect = switch treatment {
            case .blur: .gaussianBlur(radius: strength)
            case .pixelate: .pixelate(cellSize: Int(strength.rounded()))
            case .solidFill: .solidFill(fill)
            }
            let mask = SelectionMask.rectangle(box, clippedTo: canvas.bounds)
            for layer in pixelLayers where hasPixels(layer, in: box) {
                Effects.apply(effect, to: layer, selection: mask, edit: edit)
            }
        }
        return history.commit(edit) ? .redacted : .nothingChanged
    }

    /// The first locked layer with pixels under an item's box: Apply would stop there, so it's checked on every
    /// page before any is redacted.
    public static func lockedLayer(under matches: [RedactionMatch], canvas: Canvas) -> Layer? {
        let boxes = boxes(of: matches, canvas: canvas)
        return canvas.layers.first { layer in
            layer.adjustment == nil && layer.isLocked && boxes.contains { hasPixels(layer, in: $0) }
        }
    }

    private static func boxes(of matches: [RedactionMatch], canvas: Canvas) -> [IntRect] {
        matches.map { $0.rect.intersection(canvas.bounds) }.filter { !$0.isEmpty }
    }

    private static func hasPixels(_ layer: Layer, in rect: IntRect) -> Bool {
        for y in rect.minY..<rect.maxY {
            let row = layer.buffer.row(y)
            for x in rect.minX..<rect.maxX where row[x].a > 0 { return true }
        }
        return false
    }
}
