extension AutoRedact {
    public enum Outcome: Equatable, Sendable {
        case redacted
        case nothingChanged
        /// A locked layer has pixels under a box, so nothing was redacted.
        case locked(layerName: String)
    }

    /// The items to list when Auto-Redact searched `region` (a selection): every one that touches it, even
    /// partly, since each is redacted whole (review E, finding 4).
    public static func matches(_ matches: [RedactionMatch], touching region: SelectionMask?) -> [RedactionMatch] {
        guard let region else { return matches }
        return matches.filter { match in
            let overlap = match.rect.intersection(region.bounds)
            guard !overlap.isEmpty else { return false }
            for y in overlap.minY..<overlap.maxY {
                for x in overlap.minX..<overlap.maxX where region[x, y] > 0 { return true }
            }
            return false
        }
    }

    /// Redacts each item's whole box on every layer with pixels under it, as one step, so text is covered
    /// whichever layer holds it (review E, finding 1). Blur and Pixelate are as strong as each item's own
    /// text needs (finding 3). If a locked layer has pixels under a box, nothing is redacted.
    public static func apply(_ matches: [RedactionMatch], treatment: RedactionTreatment, fill: Pixel,
                             canvas: Canvas, history: History) -> Outcome {
        let boxes = matches.map { $0.rect.intersection(canvas.bounds) }.filter { !$0.isEmpty }
        func hasPixels(_ layer: Layer, in rect: IntRect) -> Bool {
            for y in rect.minY..<rect.maxY {
                let row = layer.buffer.row(y)
                for x in rect.minX..<rect.maxX where row[x].a > 0 { return true }
            }
            return false
        }
        let pixelLayers = canvas.layers.filter { $0.adjustment == nil }
        if let locked = pixelLayers.first(where: { layer in layer.isLocked && boxes.contains { hasPixels(layer, in: $0) } }) {
            return .locked(layerName: locked.name)
        }
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
}
