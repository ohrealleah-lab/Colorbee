/// Text layers (FR-6.3, stages 29 and 30): text placed with Editable on stays editable on a layer of its own.
extension LayerActions {
    /// Places text as a new text layer just above the active layer.
    @discardableResult
    public static func addText(_ spec: TextSpec, canvas: Canvas, history: History, context: SelectionContext) -> Bool {
        guard !spec.text.isEmpty else { return false }
        return change("Text", canvas: canvas, history: history, context: context) {
            let text = TextLayer(spec: spec)
            let layer = Layer(name: text.name, buffer: text.drawn(size: canvas.size, colorSpace: canvas.colorSpace))
            layer.text = text
            canvas.insertLayerAboveActive(layer)
            return true
        }
    }

    /// Places an edited text layer's box: the new words and settings, drawn again. The layer's name follows the
    /// words unless it was renamed. With every word deleted, the layer goes (my choice, veto any).
    @discardableResult
    public static func setText(_ spec: TextSpec, layerAt index: Int, canvas: Canvas, history: History, context: SelectionContext) -> Bool {
        guard canvas.layers.indices.contains(index) else { return false }
        let layer = canvas.layers[index]
        guard canEditText(of: layer, in: canvas), let old = layer.text, spec != old.spec else { return false }
        if spec.text.isEmpty {
            guard canvas.layers.count > 1 else { return false }
            return change("Delete Text", canvas: canvas, history: history, context: context) {
                canvas.removeLayer(at: index)
                canvas.activeLayerIndex = min(max(0, index - 1), canvas.layers.count - 1)
                return true
            }
        }
        return change("Edit Text", canvas: canvas, history: history, context: context) {
            let text = TextLayer(spec: spec)
            if layer.name == old.name { layer.name = text.name }
            layer.buffer = text.drawn(size: canvas.size, colorSpace: canvas.colorSpace)
            layer.text = text
            canvas.activeLayerIndex = index
            return true
        }
    }

    /// A text layer whose words can be changed: upright and not locked.
    public static func canEditText(of layer: Layer, in canvas: Canvas) -> Bool {
        layer.text?.isUpright == true && !canvas.isLocked(layer)
    }

    /// Layer ▸ Rasterize Text (stage 30): the active text layer becomes plain pixels, looking the same.
    @discardableResult
    public static func rasterizeText(canvas: Canvas, history: History, context: SelectionContext) -> Bool {
        guard canvas.activeLayer.text != nil, !canvas.isLocked(canvas.activeLayer) else { return false }
        return change("Rasterize Text", canvas: canvas, history: history, context: context) {
            canvas.activeLayer.text = nil
            return true
        }
    }
}
