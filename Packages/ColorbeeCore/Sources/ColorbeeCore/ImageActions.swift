/// Operations on the whole image's geometry.
public enum ImageActions {
    /// Crops every layer to `rect` (clipped to the canvas). Any floating selection is placed first,
    /// and the selection is cleared afterwards.
    @discardableResult
    public static func crop(to rect: IntRect, named name: String = "Crop", canvas: Canvas, history: History, context: SelectionContext) -> Bool {
        let target = rect.intersection(canvas.bounds)
        guard !target.isEmpty, target != canvas.bounds else { return false }
        return changeGeometry(name, to: target.size, fit: .moved(dx: -target.minX, dy: -target.minY), canvas: canvas, history: history,
                              context: context) { layer in
            let cropped = PixelBuffer(width: target.width, height: target.height)
            if !layer.holdsNoPixels {
                cropped.setPixels(layer.buffer.pixels(in: target), in: cropped.bounds)
            }
            return cropped
        }
    }

    /// What Crop, Resize and Skew, and Canvas Size share: the floating piece placed, one step that gives every layer
    /// and mask the buffer `buffer` makes, text layers following `fit`, and the selection `selection` leaves.
    private static func changeGeometry(_ name: String, to size: IntSize, fit: TextFit?, canvas: Canvas, history: History,
                                       context: SelectionContext, selection: (Canvas) -> SelectionState = { _ in .none },
                                       buffer: (Layer) -> PixelBuffer) -> Bool {
        SelectionActions.placeFloating(canvas: canvas, history: history, context: context)
        let edit = history.beginEdit(name, on: canvas)
        edit.willChangeGeometry()
        var buffers: [LayerID: PixelBuffer] = [:]
        for layer in canvas.allLayers { buffers[layer.id] = buffer(layer) }
        canvas.replaceContents(size: size, buffers: buffers)
        canvas.fitText(fit, edit: edit)
        canvas.selection = selection(canvas)
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
        let skewed = settings.horizontalSkew != 0 || settings.verticalSkew != 0
        let fit = skewed ? nil : TextFit.resized(from: canvas.size, to: settings.resultSize)
        return changeGeometry(settings.actionName(from: canvas.size), to: settings.resultSize, fit: fit, canvas: canvas, history: history,
                              context: context) { layer in
            guard layer.isPixelLayer else { return PixelBuffer(size: settings.resultSize) }
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
            return result
        }
    }

    /// Changes the canvas size (FR-1.4), keeping the image at the top-left. New area on a solid background
    /// gets Color 2; on other layers, or a transparent background, it's transparent. The selection is cleared.
    @discardableResult
    public static func resizeCanvas(to size: IntSize, anchor: CanvasAnchor = .topLeft, canvas: Canvas, history: History,
                                    context: SelectionContext) -> Bool {
        guard size.width > 0, size.height > 0, size != canvas.size,
              size.fitsEditing else { return false }
        let offset = anchor.offset(from: canvas.size, to: size)
        // The old picture's part that's still on the canvas, where it was and where it goes.
        let kept = IntRect(size: canvas.size).intersection(IntRect(x: -offset.x, y: -offset.y, width: size.width, height: size.height))
        let placed = IntRect(x: kept.minX + offset.x, y: kept.minY + offset.y, width: kept.width, height: kept.height)
        return changeGeometry("Resize Canvas", to: size, fit: .moved(dx: offset.x, dy: offset.y), canvas: canvas, history: history,
                              context: context, selection: { canvas in
            // The selection moves with the picture, losing any part that's cut off.
            let moved = canvas.selection.marquee.map { $0.translatedBy(dx: offset.x, dy: offset.y) }
            let onCanvas = SelectionMask.combine(moved, with: .rectangle(canvas.bounds, clippedTo: canvas.bounds), mode: .intersect)
            return moved == nil ? .none : onCanvas.map { .marquee($0) } ?? .none
        }) { layer in
            let fill = layer.isPixelLayer ? canvas.vacatedFill(for: layer, color2: context.color2) : .clear
            let buffer = PixelBuffer(width: size.width, height: size.height, fill: fill)
            // A layer with no pixels has nothing to copy, unless the new area's fill would cover where they go.
            if !(layer.holdsNoPixels && fill == .clear), !kept.isEmpty {
                buffer.setPixels(layer.buffer.pixels(in: kept), in: placed)
            }
            return buffer
        }
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
