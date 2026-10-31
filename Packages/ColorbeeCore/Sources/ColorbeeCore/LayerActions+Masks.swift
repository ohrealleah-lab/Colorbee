/// How a new mask starts (stage 27).
public enum MaskStart: Sendable {
    /// Everything shows: an untouched mask, which takes no memory.
    case revealAll
    /// Nothing shows.
    case hideAll
    /// Only the selection shows, its soft edges partly (Q28.6).
    case selection
}

/// Layer masks (FR-8.8, stages 27 to 28b). A mask is black ink on white paper (`Compositing.reveal`), held as a layer
/// of its own (`Layer.mask`) so every tool paints on it and history records it like any layer.
extension LayerActions {
    /// Layer ▸ Layer Mask ▸ Add: on the active pixel layer, adjustment layer or group. The mask becomes what tools
    /// paint on.
    @discardableResult
    public static func addMask(_ start: MaskStart, canvas: Canvas, history: History, context: SelectionContext) -> Bool {
        guard canAddMask(canvas) else { return false }
        let selection = canvas.selection.marquee
        if start == .selection, selection == nil { return false }
        return change("Add Layer Mask", canvas: canvas, history: history, context: context) {
            let layer = canvas.activeLayer
            let mask = Layer(name: "\(layer.name) Mask", buffer: PixelBuffer(size: canvas.size))
            switch start {
            case .revealAll: break
            case .hideAll: mask.buffer.fill(.black, in: canvas.bounds)
            case .selection:
                let selected = selection!
                ParallelRows.forEach(0..<canvas.size.height) { rows in
                    for y in rows {
                        let row = mask.buffer.row(y)
                        for x in 0..<canvas.size.width {
                            let shown = selected[x, y]
                            if shown < 255 { row[x] = Pixel(r: 0, g: 0, b: 0, a: 255 - shown) }
                        }
                    }
                }
            }
            layer.mask = mask
            layer.maskEnabled = true
            canvas.editsMask = true
            return true
        }
    }

    public static func canAddMask(_ canvas: Canvas) -> Bool {
        let layer = canvas.activeLayer
        return layer.mask == nil && !canvas.isLocked(layer)
    }

    /// Layer ▸ Layer Mask ▸ Delete: the layer shows everywhere again.
    @discardableResult
    public static func deleteMask(canvas: Canvas, history: History, context: SelectionContext) -> Bool {
        guard canvas.activeLayer.mask != nil, !canvas.isLocked(canvas.activeLayer) else { return false }
        return change("Delete Layer Mask", canvas: canvas, history: history, context: context) {
            canvas.activeLayer.mask = nil
            canvas.editsMask = false
            return true
        }
    }

    /// Layer ▸ Layer Mask ▸ Apply: on a pixel layer, what the mask hides is gone for good, and the mask with it.
    @discardableResult
    public static func applyMask(canvas: Canvas, history: History, context: SelectionContext) -> Bool {
        guard canApplyMask(canvas) else { return false }
        return change("Apply Layer Mask", canvas: canvas, history: history, context: context) {
            bakeMask(of: canvas.activeLayer)
            canvas.editsMask = false
            return true
        }
    }

    public static func canApplyMask(_ canvas: Canvas) -> Bool {
        let layer = canvas.activeLayer
        return layer.isPixelLayer && layer.mask != nil && !canvas.isLocked(layer)
    }

    /// A pixel layer's mask put into its pixels' opacity, in a new buffer, and the mask removed. Inside a layer step.
    static func bakeMask(of layer: Layer) {
        guard let mask = layer.activeMask else {
            layer.mask = nil
            return
        }
        let baked = PixelBuffer(width: layer.buffer.width, height: layer.buffer.height)
        ParallelRows.forEach(0..<baked.height) { rows in
            for y in rows {
                let source = layer.buffer.row(y), masked = mask.row(y), target = baked.row(y)
                for x in 0..<baked.width {
                    var pixel = source[x]
                    pixel.a = UInt8((Float(pixel.a) * Compositing.reveal(masked[x])).rounded())
                    target[x] = pixel.a == 0 ? .clear : pixel
                }
            }
        }
        layer.buffer = baked
        layer.mask = nil
    }

    /// Shift-click on the mask (stage 28a): off, the layer shows everywhere; on again, as the mask says.
    @discardableResult
    public static func setMaskEnabled(_ enabled: Bool, canvas: Canvas, history: History) -> Bool {
        guard canvas.activeLayer.mask != nil, canvas.activeLayer.maskEnabled != enabled else { return false }
        return update(enabled ? "Turn On Layer Mask" : "Turn Off Layer Mask", layerAt: canvas.activeLayerIndex, canvas: canvas, history: history) {
            $0.maskEnabled = enabled
        }
    }

    /// Layer ▸ Layer Mask ▸ Invert (stage 28a): what showed is hidden and the reverse, as one step.
    @discardableResult
    public static func invertMask(canvas: Canvas, history: History, context: SelectionContext) -> Bool {
        guard let mask = canvas.activeLayer.mask, !canvas.isLocked(canvas.activeLayer) else { return false }
        SelectionActions.placeFloating(canvas: canvas, history: history, context: context)
        let edit = history.beginEdit("Invert Layer Mask", on: canvas)
        edit.willModify(canvas.bounds, in: mask)
        ParallelRows.forEach(0..<canvas.size.height) { rows in
            for y in rows {
                let row = mask.buffer.row(y)
                for x in 0..<canvas.size.width {
                    // What showed becomes how much ink there is.
                    let ink = UInt8((Compositing.reveal(row[x]) * 255).rounded())
                    row[x] = ink == 0 ? .clear : Pixel(r: 0, g: 0, b: 0, a: ink)
                }
            }
        }
        return history.commit(edit)
    }
}
