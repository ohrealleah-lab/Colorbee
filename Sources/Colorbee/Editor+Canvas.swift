import ColorbeeCore
import CoreGraphics
import Foundation
import Observation

extension Editor {
    // MARK: Canvas (FR-1.4)

    /// The Info panel's facts, except the color profile's name, which takes AppKit to read.
    var documentInfo: DocumentInfo {
        DocumentInfo(fileName: fileName, kind: fileKind, bytesOnDisk: fileBytes, size: canvasSize, profileName: nil,
                     hasTransparentBackground: hasTransparentBackground, layerCount: layers.count,
                     pageIndex: currentPageIndex, pageCount: pageCount, resolution: page.resolution,
                     camera: canvas.cameraDetails, locationRemoved: canvas.locationRemoved)
    }

    var hasTransparentBackground: Bool {
        _ = layersRevision
        return canvas.hasTransparentBackground
    }

    /// Canvas Properties: the new size, with the picture at `anchor`, and the transparent-background setting, each its
    /// own step.
    func applyCanvasProperties(size: IntSize, anchor: CanvasAnchor = .center, transparentBackground: Bool) {
        isCanvasPropertiesOpen = false
        finishInteractions()
        recordingChanges {
            ImageActions.setTransparentBackground(transparentBackground, canvas: canvas, history: history)
            ImageActions.resizeCanvas(to: size, anchor: anchor, canvas: canvas, history: history, context: selectionContext)
        }
        selectionDidChange()
    }

    /// The canvas's edge handles: new area on the right and bottom (FR-1.4).
    func resizeCanvas(to size: IntSize) {
        finishInteractions()
        recordingChanges { ImageActions.resizeCanvas(to: size, canvas: canvas, history: history, context: selectionContext) }
        selectionDidChange()
    }

    var canRevertLayer: Bool {
        let layer = canvas.activeLayer
        // After a flip or rotation since the save, the saved pixels would come back unturned (review G, finding 4).
        return layer.isPixelLayer && !canvas.isLocked(layer) && canvas.size == saved.size && history.geometrySteps == savedGeometrySteps
            && saved.layerIDs.contains(layer.id)
    }

    /// Revert Layer: the active layer's pixels go back to how they were at the last save, as one step, and its mask's too
    /// if it had that mask then (Q28.8).
    func revertLayer() {
        guard canRevertLayer, let saved = saved.layer(canvas.activeLayer.id) else {
            onRefused()
            return
        }
        finishInteractions()
        placeFloatingKeepingOutline()
        let layer = canvas.activeLayer
        let edit = history.beginEdit("Revert Layer", on: canvas)
        edit.willModify(layer.buffer.bounds, in: layer)
        layer.buffer.setPixels(saved.pixels(in: saved.bounds), in: layer.buffer.bounds)
        if let mask = layer.mask, let savedMask = self.saved.mask(mask.id), savedMask.size == mask.buffer.size {
            edit.willModify(mask.buffer.bounds, in: mask)
            mask.buffer.setPixels(savedMask.pixels(in: savedMask.bounds), in: mask.buffer.bounds)
        }
        recordingChanges { history.commit(edit) }
        onRender()
    }

    /// The step Undo on Active Layer would take back, for the menu; nil when it isn't available.
    var undoOnActiveLayerName: String? {
        // Placing a pending shape or text makes a newer step, so the step isn't known yet (review G, finding 1).
        guard pendingShape == nil, pendingText == nil, pendingBadge == nil else { return nil }
        return history.undoOnLayerActionName(canvas.activeLayer.id, canvas: canvas)
    }

    /// Undo on Active Layer (⌘⌥Z, FR-8.3): takes back the active layer's last change only.
    func undoOnActiveLayer() {
        finishInteractions()
        placeFloatingKeepingOutline()
        var done = false
        recordingChanges { done = history.undoOnLayer(canvas.activeLayer.id, canvas: canvas) }
        if !done { onRefused() }
        selectionDidChange()
    }

    var selectionContext: SelectionContext {
        SelectionContext(color2: color2, transparentSelection: transparentSelection, resampling: smoothResize ? .smooth : .nearestNeighbor)
    }

    var hasSelection: Bool { !canvas.selection.isEmpty || marqueePreview != nil }

    // MARK: Tools

    func selectTool(_ newTool: Tool) {
        onFocusCanvas()
        guard newTool != tool else { return }
        finishInteractions()
        measurement = nil
        // Moved or pasted pixels are placed, but the outline stays selected so tools like
        // Fill and Gradient (and the Effects) still work inside it.
        if !newTool.isSelectionTool {
            placeFloatingKeepingOutline()
        }
        tool = newTool
    }

    /// What the toolbar's Size control edits (FR-1.1); nil for tools without a size.
    var toolSize: Int? {
        get {
            switch tool {
            case .brush: Int(brushDiameter.rounded())
            case .shape: Int(shapeLineWidth.rounded())
            case .eraser: eraserSize
            case .stepBadge: Int(badgeDiameter.rounded())
            case .redactBrush: Int(redactBrushSize.rounded())
            case .retouch: Int(retouchSize.rounded())
            default: nil
            }
        }
        set {
            guard let size = newValue else { return }
            let range = toolSizeRange
            let clamped = min(range.upperBound, max(range.lowerBound, size))
            switch tool {
            case .brush: brushDiameter = Double(clamped)
            case .shape: shapeLineWidth = Double(clamped)
            case .eraser: eraserSize = clamped
            case .stepBadge: badgeDiameter = Double(clamped)
            case .redactBrush: redactBrushSize = Double(clamped)
            case .retouch: retouchSize = Double(clamped)
            default: break
            }
        }
    }

    /// The sizes the tool in use allows.
    var toolSizeRange: ClosedRange<Int> {
        switch tool {
        case .eraser: 1...100
        case .stepBadge: 16...128
        case .redactBrush, .retouch: 1...300
        default: 1...50
        }
    }

    /// The five sizes the Size control offers for the tool in use.
    var toolSizePresets: [Int] {
        switch tool {
        case .eraser: [4, 6, 8, 10, 20]
        case .stepBadge: [24, 32, 48, 64, 96]
        case .redactBrush: [8, 16, 24, 40, 64]
        case .retouch: retouchKind.sizePresets
        default: [1, 2, 3, 4, 5]
        }
    }

    /// The `[` and `]` keys: resize whichever tool is active.
    func adjustToolSize(larger: Bool) {
        switch tool {
        case .eraser:
            eraserSize = max(1, min(100, eraserSize + (larger ? 2 : -2)))
        case .shape:
            // The Shapes tool's size is its line width (review I, finding 10).
            shapeLineWidth = max(1, min(50, shapeLineWidth + (larger ? 1 : -1)))
        case .stepBadge:
            badgeDiameter = max(16, min(128, badgeDiameter + (larger ? 4 : -4)))
        case .redactBrush:
            redactBrushSize = max(1, min(300, redactBrushSize + (larger ? 4 : -4)))
        case .retouch:
            retouchSize = max(1, min(300, retouchSize + (larger ? 4 : -4)))
        default:
            brushDiameter = max(1, min(50, brushDiameter + (larger ? 1 : -1)))
        }
    }

    /// Redraws on the next turn of the run loop. Property observers use this instead of `onRender()`:
    /// drawing reads other settings, and reading one while another is mid-change crashes (Swift exclusivity).
    func renderSoon() {
        guard !renderScheduled else { return }
        renderScheduled = true
        Task { @MainActor [weak self] in
            self?.renderScheduled = false
            self?.onRender()
        }
    }

    /// Ends any drag in progress so menu commands and undo see a settled document.
    /// A pending shape is placed.
    func finishInteractions() {
        finishPendingTone()
        endGradient()
        shapeDrag = nil
        commitPendingShape()
        commitPendingText()
        commitPendingBadge()
        endRedactStroke()
        endRetouchStroke()
        endRetouchBrush()
        endStroke()
        cancelOrEndSelectionDrag()
        if activeEffect != nil { cancelEffect() }
        finishLayerSettings()
    }

    func placeFloatingSelection() {
        guard canvas.selection.floating != nil else { return }
        recordingChanges { SelectionActions.placeFloating(canvas: canvas, history: history, context: selectionContext) }
        selectionDidChange()
    }

    /// Places a floating selection but keeps its outline selected, so effects still apply to just that area.
    func placeFloatingKeepingOutline() {
        guard let outline = canvas.selection.outline, canvas.selection.floating != nil else { return }
        placeFloatingSelection()
        // The paste may hang past the canvas; the outline kept is only the part on it (Leah's crash, 2026-10-04).
        if let clipped = SelectionMask.combine(outline, with: .rectangle(canvas.bounds, clippedTo: canvas.bounds), mode: .intersect) {
            canvas.selection = .marquee(clipped)
        } else {
            canvas.selection = .none
        }
        selectionDidChange()
    }

    // MARK: Colors

    var activeColor: Pixel {
        get { activeWell == .color1 ? color1 : color2 }
        set { if activeWell == .color1 { color1 = newValue } else { color2 = newValue } }
    }

    /// A swatch click. Swatches carry no alpha, so the well keeps its Alpha setting.
    func applySwatch(_ swatch: Pixel, secondary: Bool) {
        var color = swatch
        color.a = secondary ? color2.a : activeColor.a
        if secondary { color2 = color } else { activeColor = color }
    }

    func swapColors() {
        // One at a time: swapping both in place holds both open while their observers run.
        let first = color1
        color1 = color2
        color2 = first
    }

    // MARK: Viewport

    func updateViewport(_ change: (inout Viewport) -> Void) {
        var updated = viewport
        change(&updated)
        guard updated != viewport else { return }
        viewport = updated
        onRender()
        onViewStateChange()
    }

    private var viewCenter: Point2D {
        Point2D(x: viewport.viewSize.width / 2, y: viewport.viewSize.height / 2)
    }

    /// The Magnifier: one zoom step in or out, keeping the clicked point under the pointer (FR-7.1).
    func magnify(in zoomingIn: Bool, atView anchor: Point2D) {
        updateViewport { $0.setZoom($0.nextZoomStep(zoomingIn: zoomingIn), anchor: anchor) }
    }

    func zoomIn() {
        updateViewport { $0.setZoom($0.nextZoomStep(zoomingIn: true), anchor: viewCenter) }
    }

    func zoomOut() {
        updateViewport { $0.setZoom($0.nextZoomStep(zoomingIn: false), anchor: viewCenter) }
    }

    func zoomToActualSize() {
        zoom(to: 1)
    }

    func zoom(to scale: Double) {
        updateViewport { $0.setZoom(scale, anchor: viewCenter) }
    }

    func zoomToFit() {
        updateViewport { $0.fit(canvas.size, margin: 40) }
    }
}
