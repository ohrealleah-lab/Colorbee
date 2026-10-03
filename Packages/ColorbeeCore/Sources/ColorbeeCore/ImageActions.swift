/// Operations on the whole image's geometry.
public enum ImageActions {
    /// Crops every layer to `rect` (clipped to the canvas). Any floating selection is placed first,
    /// and the selection is cleared afterwards.
    @discardableResult
    public static func crop(to rect: IntRect, canvas: Canvas, history: History, context: SelectionContext) -> Bool {
        let target = rect.intersection(canvas.bounds)
        guard !target.isEmpty, target != canvas.bounds else { return false }
        SelectionActions.placeFloating(canvas: canvas, history: history, context: context)
        let edit = history.beginEdit("Crop", on: canvas)
        edit.willChangeGeometry()
        var buffers: [LayerID: PixelBuffer] = [:]
        for layer in canvas.layers {
            let cropped = PixelBuffer(width: target.width, height: target.height)
            cropped.setPixels(layer.buffer.pixels(in: target), in: cropped.bounds)
            buffers[layer.id] = cropped
        }
        canvas.replaceContents(size: target.size, buffers: buffers)
        canvas.selection = .none
        return history.commit(edit)
    }

    /// Rotates or flips every layer. Any floating selection is placed first and the selection is cleared.
    @discardableResult
    public static func transform(_ orientation: Orientation, canvas: Canvas, history: History, context: SelectionContext) -> Bool {
        SelectionActions.placeFloating(canvas: canvas, history: history, context: context)
        let edit = history.beginEdit(orientation.name, on: canvas)
        edit.willChangeGeometry()
        var buffers: [LayerID: PixelBuffer] = [:]
        for layer in canvas.layers {
            buffers[layer.id] = layer.buffer.transformed(orientation)
        }
        canvas.replaceContents(size: orientation.transformedSize(canvas.size), buffers: buffers)
        canvas.selection = .none
        return history.commit(edit)
    }

    /// Resizes and skews every layer (FR-7.2). Corners the skew exposes get the same fill as erased
    /// pixels: Color 2 on a solid background, transparent otherwise.
    @discardableResult
    public static func resizeAndSkew(_ settings: ResizeSkew, canvas: Canvas, history: History, context: SelectionContext) -> Bool {
        guard settings.fits, settings.changes(canvas.size) else { return false }
        SelectionActions.placeFloating(canvas: canvas, history: history, context: context)
        let edit = history.beginEdit(settings.actionName(from: canvas.size), on: canvas)
        edit.willChangeGeometry()
        var buffers: [LayerID: PixelBuffer] = [:]
        for layer in canvas.layers {
            let result = layer.buffer.resizedAndSkewed(settings)
            let fill = canvas.vacatedFill(for: layer, color2: context.color2)
            if fill.a > 0, settings.horizontalSkew != 0 || settings.verticalSkew != 0 {
                for y in 0..<result.height {
                    let row = result.row(y)
                    for x in 0..<result.width where row[x].a < 255 {
                        row[x] = Compositing.over(fill, row[x])
                    }
                }
            }
            buffers[layer.id] = result
        }
        canvas.replaceContents(size: settings.resultSize, buffers: buffers)
        canvas.selection = .none
        return history.commit(edit)
    }

    /// Crops to the selection's bounding box.
    @discardableResult
    public static func cropToSelection(canvas: Canvas, history: History, context: SelectionContext) -> Bool {
        guard let bounds = canvas.selection.bounds else { return false }
        return crop(to: bounds, canvas: canvas, history: history, context: context)
    }
}
