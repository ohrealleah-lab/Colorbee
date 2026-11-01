import ColorbeeCore
import CoreGraphics
import Foundation
import Observation

extension Editor {
    // MARK: Text

    /// Opens a text box with its top-left at `origin`. Any open box is placed first.
    func beginText(at origin: Point2D, wrapWidth: Double?, minimumHeight: Double = 0) {
        // Editable text goes on a new layer of its own, so the active layer's lock or kind doesn't matter.
        guard textIsEditable || !refusedBecauseLocked() else { return }
        finishInteractions()
        placeFloatingSelection()
        textDragFrame = nil
        pendingText = PendingText(origin: origin, wrapWidth: wrapWidth, minimumHeight: minimumHeight)
        onRender()
    }

    func updateTextDragFrame(from start: Point2D, to end: Point2D) {
        textDragFrame = (start, end)
        onRender()
    }

    /// The open text box's frame in image coordinates, for drawing its border.
    var pendingTextFrame: IntRect? {
        guard let text = pendingText else { return nil }
        var spec = textSpec(for: text)
        if spec.text.isEmpty { spec.text = " " }
        return TextRenderer.box(for: spec)
    }

    /// The text box's border, drawn a little outside the text so it doesn't touch the glyphs.
    var pendingTextBorder: (minX: Double, minY: Double, maxX: Double, maxY: Double)? {
        guard let box = pendingTextFrame else { return nil }
        let pad = 3 / viewport.zoom
        return (Double(box.minX) - pad, Double(box.minY) - pad, Double(box.maxX) + pad, Double(box.maxY) + pad)
    }

    /// The eight handles on the text box's border, in image coordinates.
    var pendingTextHandles: [(handle: SelectionHandle, point: Point2D)] {
        guard let border = pendingTextBorder else { return [] }
        let midX = (border.minX + border.maxX) / 2, midY = (border.minY + border.maxY) / 2
        return SelectionHandle.allCases.map { handle in
            let point: Point2D = switch handle {
            case .topLeft: Point2D(x: border.minX, y: border.minY)
            case .top: Point2D(x: midX, y: border.minY)
            case .topRight: Point2D(x: border.maxX, y: border.minY)
            case .right: Point2D(x: border.maxX, y: midY)
            case .bottomRight: Point2D(x: border.maxX, y: border.maxY)
            case .bottom: Point2D(x: midX, y: border.maxY)
            case .bottomLeft: Point2D(x: border.minX, y: border.maxY)
            case .left: Point2D(x: border.minX, y: midY)
            }
            return (handle, point)
        }
    }

    /// A handle or the border under a view point. Inside the box, clicks go to the text itself.
    func textBoxGrab(atView point: Point2D) -> TextBoxGrab? {
        guard let border = pendingTextBorder else { return nil }
        // An empty box is only a few pixels wide, so its handles overlap; take the closest one.
        if let handle = nearestHandle(pendingTextHandles, to: point) { return .handle(handle) }
        let topLeft = viewport.viewPoint(fromImage: Point2D(x: border.minX, y: border.minY))
        let bottomRight = viewport.viewPoint(fromImage: Point2D(x: border.maxX, y: border.maxY))
        let band = 5.0
        let nearOutside = point.x >= topLeft.x - band && point.x <= bottomRight.x + band
            && point.y >= topLeft.y - band && point.y <= bottomRight.y + band
        let wellInside = point.x > topLeft.x + band && point.x < bottomRight.x - band
            && point.y > topLeft.y + band && point.y < bottomRight.y - band
        return nearOutside && !wellInside ? .border : nil
    }

    func beginTextBoxDrag(_ grab: TextBoxGrab, at point: Point2D) {
        guard let text = pendingText, let frame = pendingTextFrame else { return }
        textBoxDrag = (grab, text, frame, point)
    }

    /// Moving keeps the size. Dragging a side handle sets the width the text wraps at; top and
    /// bottom handles set the box's height, which still grows if the text needs more room.
    func continueTextBoxDrag(to point: Point2D) {
        guard let drag = textBoxDrag, var text = pendingText else { return }
        let delta = Point2D(x: point.x - drag.start.x, y: point.y - drag.start.y)
        switch drag.grab {
        case .border:
            text.origin = Point2D(x: drag.text.origin.x + delta.x.rounded(), y: drag.text.origin.y + delta.y.rounded())
        case .handle(let handle):
            let rect = handle.resize(drag.frame, by: delta, keepProportions: false)
            text.origin = Point2D(
                x: drag.text.origin.x + Double(rect.minX - drag.frame.minX),
                y: drag.text.origin.y + Double(rect.minY - drag.frame.minY)
            )
            if rect.width != drag.frame.width { text.wrapWidth = Double(rect.width) }
            if rect.height != drag.frame.height { text.minimumHeight = Double(rect.height) }
        }
        pendingText = text
        onRender()
    }

    func endTextBoxDrag() {
        textBoxDrag = nil
    }

    /// The text being typed, drawn by the renderer exactly as placing will draw it, so it sits in its layer at
    /// the layer's blend mode and opacity (Leah; review F, finding 1). The text view shows only the caret
    /// and selection.
    func renderedPendingText() -> (pixels: PixelBuffer, origin: IntPoint)? {
        guard let text = pendingText else {
            textRenderCache = nil
            return nil
        }
        let spec = textSpec(for: text)
        if let cache = textRenderCache, cache.spec == spec { return (cache.pixels, cache.origin) }
        guard let rendered = TextRenderer.render(spec, colorSpace: canvas.colorSpace, clippedTo: canvas.bounds) else {
            textRenderCache = nil
            return nil
        }
        textRenderCache = (spec, rendered.pixels, rendered.origin)
        return rendered
    }

    func updatePendingText(_ string: String) {
        pendingText?.string = string
        onRender()
    }

    func textSpec(for text: PendingText) -> TextSpec {
        textStyle.spec(text.string, origin: text.origin, wrapWidth: text.wrapWidth, minimumHeight: text.minimumHeight, color: color1,
                       background: color2)
    }

    /// Places the open text box (FR-6.3): an edited text layer is drawn again; new text becomes a text layer with
    /// Editable on, or pixels on the active layer.
    func commitPendingText() {
        guard let text = pendingText else { return }
        pendingText = nil
        let spec = textSpec(for: text)
        if let id = text.layerID {
            if let index = canvas.layers.firstIndex(where: { $0.id == id }) {
                layerCommand { LayerActions.setText(spec, layerAt: index, canvas: canvas, history: history, context: selectionContext) }
                // The last layer can't go (review Y, finding 8).
                if spec.text.isEmpty, canvas.layers.contains(where: { $0.id == id }) {
                    showNotice("The last layer can't be deleted, so the text stays.")
                }
            }
            onRender()
            return
        }
        // Editable may have been turned off while the box was open on a layer that takes no pixels: the words go on a
        // layer of their own rather than into it (review Y, finding 5).
        if textIsEditable || !activeLayerTakesEdits {
            if !spec.text.isEmpty {
                layerCommand { LayerActions.addText(spec, canvas: canvas, history: history, context: selectionContext) }
            }
            onRender()
            return
        }
        if let rendered = TextRenderer.render(textSpec(for: text), colorSpace: canvas.colorSpace, clippedTo: canvas.bounds) {
            let edit = history.beginEdit("Text", on: canvas)
            Compositing.draw(rendered.pixels, at: rendered.origin, onto: canvas.paintLayer, edit: edit)
            recordingChanges { history.commit(edit) }
        }
        onRender()
    }

    /// Opens a text layer's box to change its words and settings (Q29.5): the Text tool, the layer's font and colors.
    /// Returns false if there's no text layer there.
    @discardableResult
    func editText(layerAt index: Int) -> Bool {
        guard canvas.layers.indices.contains(index), let text = canvas.layers[index].text else { return false }
        let layer = canvas.layers[index]
        guard text.isUpright else {
            showNotice("Turned text can't be edited. Turn the image back, or choose Layer ▸ Rasterize Text.")
            return true
        }
        guard !canvas.isLocked(layer) else {
            onRefused()
            return true
        }
        finishInteractions()
        placeFloatingSelection()
        selectLayer(at: index)
        paint(onMask: false, at: index)
        if tool != .text { selectTool(.text) }
        let spec = text.spec
        textStyle = TextStyle(spec)
        color1 = spec.color
        if let background = spec.background { color2 = background }
        textDragFrame = nil
        pendingText = PendingText(origin: spec.origin, wrapWidth: spec.wrapWidth, minimumHeight: spec.minimumHeight, string: spec.text,
                                  layerID: layer.id)
        if !text.hasFont {
            showNotice("Font missing: \(spec.fontFamily). The text keeps its look until you change it.")
        }
        onRender()
        return true
    }

    /// Double-click with the Text tool: the top text layer whose box is under `point`, if any.
    @discardableResult
    func editText(at point: Point2D) -> Bool {
        let hit = canvas.layers.indices.reversed().first { index in
            let layer = canvas.layers[index]
            guard let text = layer.text, canvas.isShown(layer) else { return false }
            let box = text.isUpright ? TextRenderer.box(for: text.spec) : canvas.bounds
            return box.contains(IntPoint(containing: point))
        }
        guard let hit else { return false }
        // The first click of the double-click opened an empty box, or said why it couldn't; both go without a trace.
        if pendingText?.string.isEmpty == true, pendingText?.layerID == nil { pendingText = nil }
        notice = nil
        return editText(layerAt: hit)
    }

    /// The text layer whose box is open: its own pixels are hidden while the box shows it as it's typed.
    var editedTextLayerID: LayerID? { pendingText?.layerID }

    /// New text that will be a layer of its own: shown on top while it's typed, not inside the active layer, so it looks
    /// as it will once placed (review Y, finding 7).
    var pendingTextMakesLayer: Bool {
        guard let pendingText, pendingText.layerID == nil else { return false }
        return textIsEditable || !activeLayerTakesEdits
    }
}
