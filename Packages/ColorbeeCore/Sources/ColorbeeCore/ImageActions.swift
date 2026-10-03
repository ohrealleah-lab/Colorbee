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
            if !layer.holdsNoPixels {
                cropped.setPixels(layer.buffer.pixels(in: target), in: cropped.bounds)
            }
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
        edit.willTransform(orientation)
        canvas.transform(orientation)
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
            guard layer.adjustment == nil else {
                buffers[layer.id] = PixelBuffer(size: settings.resultSize)
                continue
            }
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

    /// Changes the canvas size (FR-1.4), keeping the image at the top-left. New area on a solid background
    /// gets Color 2; on other layers, or a transparent background, it's transparent. The selection is cleared.
    @discardableResult
    public static func resizeCanvas(to size: IntSize, canvas: Canvas, history: History, context: SelectionContext) -> Bool {
        guard size.width > 0, size.height > 0, size != canvas.size,
              size.width <= ResizeSkew.maxSide, size.height <= ResizeSkew.maxSide, size.width * size.height <= ResizeSkew.maxArea else { return false }
        SelectionActions.placeFloating(canvas: canvas, history: history, context: context)
        let edit = history.beginEdit("Resize Canvas", on: canvas)
        edit.willChangeGeometry()
        var buffers: [LayerID: PixelBuffer] = [:]
        let kept = IntRect(size: canvas.size).intersection(IntRect(size: size))
        for layer in canvas.layers {
            let fill = layer.adjustment == nil ? canvas.vacatedFill(for: layer, color2: context.color2) : .clear
            let buffer = PixelBuffer(width: size.width, height: size.height, fill: fill)
            // A layer with no pixels has nothing to copy, unless the new area's fill would cover where they go.
            if !(layer.holdsNoPixels && fill == .clear), !kept.isEmpty {
                buffer.setPixels(layer.buffer.pixels(in: kept), in: kept)
            }
            buffers[layer.id] = buffer
        }
        canvas.replaceContents(size: size, buffers: buffers)
        canvas.selection = .none
        return history.commit(edit)
    }

    /// Canvas Properties' transparent background switch (FR-2.2): what erasing and new canvas area leave
    /// behind on the background. Existing pixels don't change.
    @discardableResult
    public static func setTransparentBackground(_ transparent: Bool, canvas: Canvas, history: History) -> Bool {
        guard transparent != canvas.hasTransparentBackground else { return false }
        let edit = history.beginEdit(transparent ? "Transparent Background" : "Solid Background", on: canvas)
        edit.willChangeLayers()
        canvas.hasTransparentBackground = transparent
        return history.commit(edit)
    }

    /// Crops to the selection's bounding box.
    @discardableResult
    public static func cropToSelection(canvas: Canvas, history: History, context: SelectionContext) -> Bool {
        guard let bounds = canvas.selection.bounds else { return false }
        return crop(to: bounds, canvas: canvas, history: history, context: context)
    }
}
