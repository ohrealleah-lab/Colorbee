/// Settings that affect selection operations.
public struct SelectionContext: Sendable {
    public var color2: Pixel
    /// Transparent Selection mode: pixels matching Color 2 are treated as transparent when placed.
    public var transparentSelection: Bool
    public var resampling: Resampling

    public init(color2: Pixel, transparentSelection: Bool = false, resampling: Resampling = .nearestNeighbor) {
        self.color2 = color2
        self.transparentSelection = transparentSelection
        self.resampling = resampling
    }

    public var transparentKey: Pixel? { transparentSelection ? color2 : nil }
}

/// Selection operations on a canvas. Everything that changes pixels, or moves or removes
/// selected pixels, is recorded in the history; drawing a marquee on its own is not (as in Paint).
public enum SelectionActions {
    /// The marquee dragged from `start` to `end` (image coordinates), covering both end pixels.
    /// With `constrain`, the shape is a square or circle.
    public static func marquee(
        _ shape: SelectionShape,
        from start: Point2D,
        to end: Point2D,
        constrain: Bool,
        in canvasBounds: IntRect
    ) -> SelectionMask? {
        var end = end
        if constrain {
            let side = max(abs(end.x - start.x), abs(end.y - start.y))
            end = Point2D(
                x: start.x + (end.x < start.x ? -side : side),
                y: start.y + (end.y < start.y ? -side : side)
            )
        }
        let minX = Int(min(start.x, end.x).rounded(.down))
        let minY = Int(min(start.y, end.y).rounded(.down))
        let maxX = Int(max(start.x, end.x).rounded(.down)) + 1
        let maxY = Int(max(start.y, end.y).rounded(.down)) + 1
        let rect = IntRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        switch shape {
        case .rectangle: return .rectangle(rect, clippedTo: canvasBounds)
        case .ellipse: return .ellipse(in: rect, clippedTo: canvasBounds)
        }
    }

    /// Places any floating selection, then combines `mask` with what was selected.
    public static func select(_ mask: SelectionMask?, mode: SelectionCombineMode, canvas: Canvas, history: History, context: SelectionContext) {
        let existing = canvas.selection.outline
        placeFloating(canvas: canvas, history: history, context: context)
        canvas.selection = SelectionMask.combine(existing, with: mask, mode: mode).map(SelectionState.marquee) ?? .none
    }

    public static func selectAll(canvas: Canvas, history: History, context: SelectionContext) {
        select(.rectangle(canvas.bounds, clippedTo: canvas.bounds), mode: .replace, canvas: canvas, history: history, context: context)
    }

    public static func deselect(canvas: Canvas, history: History, context: SelectionContext) {
        placeFloating(canvas: canvas, history: history, context: context)
        canvas.selection = .none
    }

    public static func invert(canvas: Canvas, history: History, context: SelectionContext) {
        let existing = canvas.selection.outline
        placeFloating(canvas: canvas, history: history, context: context)
        let inverted = existing.map { $0.inverted(in: canvas.bounds) } ?? .rectangle(canvas.bounds, clippedTo: canvas.bounds)
        canvas.selection = inverted.map(SelectionState.marquee) ?? .none
    }

    /// Stamps the floating selection onto its layer and clears the selection. When the most recent step
    /// created or moved this floating selection, placing it joins that step, so one undo reverts both.
    @discardableResult
    public static func placeFloating(canvas: Canvas, history: History, context: SelectionContext) -> Bool {
        guard let floating = canvas.selection.floating else { return false }
        guard let layer = canvas.layer(withID: floating.layerID) else {
            canvas.selection = .none
            return false
        }
        let merge = history.lastStepLeftFloating(floating.id)
        let edit = history.beginEdit("Place Selection", on: canvas)
        edit.recordsSelectionChange = true
        floating.stamp(onto: layer, edit: edit, resampling: context.resampling, transparentKey: context.transparentKey)
        canvas.selection = .none
        history.commit(edit, mergingIntoPrevious: merge)
        return true
    }

    /// Starts moving the selection. A marquee's pixels are lifted off the active layer, leaving the vacated
    /// fill behind unless `duplicate` is set. A duplicate of a floating selection leaves a copy where it was.
    /// Finish with `history.commit(_:)`.
    public static func beginMove(duplicate: Bool, canvas: Canvas, history: History, context: SelectionContext) -> Edit? {
        let edit = history.beginEdit(duplicate ? "Duplicate Selection" : "Move Selection", on: canvas)
        edit.recordsSelectionChange = true
        switch canvas.selection {
        case .none:
            return nil
        case .marquee(let mask):
            let layer = canvas.activeLayer
            let holeFill = duplicate ? nil : canvas.vacatedFill(for: layer, color2: context.color2)
            guard let floating = FloatingSelection.lift(from: layer, selection: mask, holeFill: holeFill, edit: edit) else {
                return nil
            }
            canvas.selection = .floating(floating)
        case .floating(let floating):
            if duplicate, let layer = canvas.layer(withID: floating.layerID) {
                floating.stamp(onto: layer, edit: edit, resampling: context.resampling, transparentKey: context.transparentKey)
            }
        }
        return edit
    }

    /// Moves the floating selection's top-left corner to `origin`. With `smear`, a copy is stamped
    /// where it currently is first, leaving a trail.
    public static func move(to origin: IntPoint, smear: Bool, edit: Edit, canvas: Canvas, context: SelectionContext) {
        guard var floating = canvas.selection.floating else { return }
        if smear, let layer = canvas.layer(withID: floating.layerID) {
            floating.stamp(onto: layer, edit: edit, resampling: context.resampling, transparentKey: context.transparentKey)
        }
        floating.destination = IntRect(x: origin.x, y: origin.y, width: floating.destination.width, height: floating.destination.height)
        canvas.selection = .floating(floating)
    }

    /// Moves the selected pixels by a few pixels as one step.
    public static func nudge(dx: Int, dy: Int, canvas: Canvas, history: History, context: SelectionContext) {
        guard let edit = beginMove(duplicate: false, canvas: canvas, history: history, context: context),
              let destination = canvas.selection.floating?.destination else { return }
        move(to: IntPoint(x: destination.minX + dx, y: destination.minY + dy), smear: false, edit: edit, canvas: canvas, context: context)
        history.commit(edit)
    }

    /// Removes the selected pixels. A marquee's area gets the vacated fill and stays selected;
    /// a floating selection is discarded.
    @discardableResult
    public static func deleteSelection(named name: String = "Delete", canvas: Canvas, history: History, context: SelectionContext) -> Bool {
        let edit = history.beginEdit(name, on: canvas)
        edit.recordsSelectionChange = true
        switch canvas.selection {
        case .none:
            return false
        case .marquee(let mask):
            let layer = canvas.activeLayer
            let fill = canvas.vacatedFill(for: layer, color2: context.color2)
            edit.willModify(mask.bounds, in: layer)
            for y in mask.bounds.minY..<mask.bounds.maxY {
                let row = layer.buffer.row(y)
                for x in mask.bounds.minX..<mask.bounds.maxX where mask[x, y] > 0 {
                    row[x] = fill
                }
            }
        case .floating:
            canvas.selection = .none
        }
        return history.commit(edit)
    }

    /// The selected pixels cropped to the selection, for Copy. Unselected pixels in the crop are transparent.
    public static func selectedPixels(canvas: Canvas, context: SelectionContext) -> PixelBuffer? {
        switch canvas.selection {
        case .none:
            return nil
        case .floating(let floating):
            return floating.rendered(using: context.resampling)
        case .marquee(let mask):
            let bounds = mask.bounds
            let result = PixelBuffer(width: bounds.width, height: bounds.height)
            let layer = canvas.activeLayer
            for y in bounds.minY..<bounds.maxY {
                let source = layer.buffer.row(y)
                let destination = result.row(y - bounds.minY)
                for x in bounds.minX..<bounds.maxX where mask[x, y] > 0 {
                    destination[x - bounds.minX] = source[x]
                }
            }
            return result
        }
    }

    /// Adds `image` as a floating selection on the active layer with its top-left at `origin`.
    /// Any existing floating selection is placed first.
    public static func paste(_ image: PixelBuffer, at origin: IntPoint, canvas: Canvas, history: History, context: SelectionContext) {
        placeFloating(canvas: canvas, history: history, context: context)
        let edit = history.beginEdit("Paste", on: canvas)
        edit.recordsSelectionChange = true
        canvas.selection = .floating(FloatingSelection(
            pixels: image,
            destination: IntRect(x: origin.x, y: origin.y, width: image.width, height: image.height),
            layerID: canvas.activeLayer.id
        ))
        history.commit(edit)
    }
}
