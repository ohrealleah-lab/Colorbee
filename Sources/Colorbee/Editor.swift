import ColorbeeCore
import Foundation
import Observation

enum DocumentChange {
    case done
    case undone
    case redone
}

enum Tool: CaseIterable {
    case pencil
    case brush
    case eraser
    case fill
    case eyedropper
    case rectangleSelect
    case ellipseSelect
    case lassoSelect

    var isSelectionTool: Bool {
        switch self {
        case .rectangleSelect, .ellipseSelect, .lassoSelect: true
        default: false
        }
    }

    /// Tools that paint while the pointer is dragged.
    var isStrokeTool: Bool {
        switch self {
        case .pencil, .brush, .eraser: true
        default: false
        }
    }
}

enum BrushKind: CaseIterable {
    case round
    case marker
}

enum EffectKind {
    case gaussianBlur
    case pixelate

    var title: String {
        switch self {
        case .gaussianBlur: "Gaussian Blur"
        case .pixelate: "Pixelate"
        }
    }

    var valueLabel: String {
        switch self {
        case .gaussianBlur: "Radius"
        case .pixelate: "Cell size"
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .gaussianBlur: 1...100
        case .pixelate: 2...100
        }
    }

    var defaultValue: Double {
        switch self {
        case .gaussianBlur: 8
        case .pixelate: 12
        }
    }

    func effect(_ value: Double) -> Effect {
        switch self {
        case .gaussianBlur: .gaussianBlur(radius: value)
        case .pixelate: .pixelate(cellSize: Int(value.rounded()))
        }
    }
}

/// Modifier keys that matter to canvas drags.
struct DragModifiers {
    var shift = false
    var option = false
}

/// Per-document editing state: the canvas, its history, tool settings and the view mapping.
@MainActor
@Observable
final class Editor {
    static let eraserSizes = [4, 6, 8, 10]
    /// The marker paints at half the chosen color's opacity.
    static let markerOpacity = 0.5

    let canvas: Canvas
    @ObservationIgnored let history: History

    private(set) var tool: Tool = .pencil
    var brushKind: BrushKind = .round
    var color1: Pixel = .black
    var color2: Pixel = .white {
        didSet { if transparentSelection { onRender() } }
    }
    var brushDiameter: Double = 5
    var eraserSize = 8
    /// Fill bucket tolerance, 0...1.
    var fillTolerance = 0.0
    var transparentSelection = false {
        didSet { onRender() }
    }
    var showsPixelGrid = true {
        didSet { onRender() }
    }
    private(set) var viewport = Viewport()
    var pointer: IntPoint?
    /// The selection being dragged, already combined with the existing selection.
    private(set) var marqueePreview: SelectionMask?
    /// Bounds of the selected area, for the status bar.
    private(set) var selectionBounds: IntRect?
    /// The canvas size, observable for the status bar (the canvas itself isn't observable).
    private(set) var canvasSize: IntSize
    /// The effect whose dialog is open, if any.
    private(set) var activeEffect: EffectKind?
    var effectValue = 8.0

    @ObservationIgnored var onRender: () -> Void = {}
    @ObservationIgnored var onDocumentChange: (DocumentChange) -> Void = { _ in }
    @ObservationIgnored private var activeStroke: ActiveStroke?
    @ObservationIgnored private var selectionDrag: SelectionDrag?
    @ObservationIgnored private var effectEdit: Edit?

    private struct ActiveStroke {
        let edit: Edit
        let stroke: Stroke
        let start: Point2D
    }

    private enum SelectionDrag {
        case marquee(shape: SelectionShape, start: Point2D, mode: SelectionCombineMode, shiftHeldAtStart: Bool, shiftReleased: Bool)
        case lasso(points: [Point2D], mode: SelectionCombineMode)
        case move(edit: Edit?, grab: Point2D, origin: IntPoint, smear: Bool, duplicate: Bool)
    }

    init(canvas: Canvas) {
        self.canvas = canvas
        canvasSize = canvas.size
        history = History(byteBudget: Editor.historyByteBudget)
    }

    private static var historyByteBudget: Int {
        Int(min(UInt64(512 << 20), ProcessInfo.processInfo.physicalMemory / 10))
    }

    var selectionContext: SelectionContext {
        SelectionContext(color2: color2, transparentSelection: transparentSelection)
    }

    var hasSelection: Bool { !canvas.selection.isEmpty || marqueePreview != nil }

    // MARK: Tools

    func selectTool(_ newTool: Tool) {
        guard newTool != tool else { return }
        finishInteractions()
        if !newTool.isSelectionTool {
            recordingChanges { SelectionActions.deselect(canvas: canvas, history: history, context: selectionContext) }
            selectionDidChange()
        }
        tool = newTool
    }

    /// The `[` and `]` keys: resize whichever tool is active.
    func adjustToolSize(larger: Bool) {
        switch tool {
        case .eraser:
            eraserSize = max(1, min(100, eraserSize + (larger ? 2 : -2)))
        default:
            brushDiameter = max(1, min(50, brushDiameter + (larger ? 1 : -1)))
        }
    }

    /// Ends any drag in progress so menu commands and undo see a settled document.
    private func finishInteractions() {
        endStroke()
        if selectionDrag != nil { endSelectionDrag(at: nil) }
        if activeEffect != nil { cancelEffect() }
    }

    private func placeFloatingSelection() {
        guard canvas.selection.floating != nil else { return }
        recordingChanges { SelectionActions.placeFloating(canvas: canvas, history: history, context: selectionContext) }
        selectionDidChange()
    }

    // MARK: Painting

    func beginStroke(at point: Point2D, secondary: Bool) {
        finishInteractions()
        placeFloatingSelection()
        let layer = canvas.activeLayer
        let color = secondary ? color2 : color1
        let edit: Edit
        let stroke: Stroke
        switch tool {
        case .pencil:
            edit = history.beginEdit("Pencil", on: canvas)
            stroke = PencilStroke(color: color, layer: layer, edit: edit)
        case .brush where brushKind == .marker:
            edit = history.beginEdit("Marker", on: canvas)
            var translucent = color
            translucent.a = UInt8((Double(color.a) * Self.markerOpacity).rounded())
            stroke = RoundBrushStroke(diameter: brushDiameter, color: translucent, layer: layer, edit: edit)
        case .brush:
            edit = history.beginEdit("Brush Stroke", on: canvas)
            stroke = RoundBrushStroke(diameter: brushDiameter, color: color, layer: layer, edit: edit)
        case .eraser:
            // Right-drag is the Color Eraser: only Color 1 pixels become Color 2.
            let effect: StrokeEffect = secondary
                ? .replaceMatching(target: color1, tolerance: 0, with: color2)
                : .replace(canvas.vacatedFill(for: layer, color2: color2))
            edit = history.beginEdit(secondary ? "Color Erase" : "Erase", on: canvas)
            stroke = EraserStroke(size: eraserSize, effect: effect, layer: layer, edit: edit)
        default:
            return
        }
        activeStroke = ActiveStroke(edit: edit, stroke: stroke, start: point)
        if !stroke.move(to: point).isEmpty { onRender() }
    }

    /// With `constrain`, the pencil only draws horizontally or vertically from where it started.
    func continueStroke(to point: Point2D, constrain: Bool) {
        guard let active = activeStroke else { return }
        var target = point
        if constrain, tool == .pencil {
            if abs(point.x - active.start.x) >= abs(point.y - active.start.y) {
                target.y = active.start.y
            } else {
                target.x = active.start.x
            }
        }
        if !active.stroke.move(to: target).isEmpty { onRender() }
    }

    func endStroke() {
        guard let edit = activeStroke?.edit else { return }
        activeStroke = nil
        recordingChanges { history.commit(edit) }
    }

    func fill(at point: Point2D, secondary: Bool) {
        finishInteractions()
        placeFloatingSelection()
        let seed = IntPoint(x: Int(point.x.rounded(.down)), y: Int(point.y.rounded(.down)))
        let edit = history.beginEdit("Fill", on: canvas)
        FloodFill.fill(
            layer: canvas.activeLayer,
            at: seed,
            with: secondary ? color2 : color1,
            tolerance: fillTolerance,
            selection: canvas.selection.marquee,
            edit: edit
        )
        recordingChanges { history.commit(edit) }
        onRender()
    }

    /// Picks a color. With `allLayers`, samples what's visible rather than only the active layer.
    func pickColor(at point: Point2D, secondary: Bool, allLayers: Bool) {
        let pixel = IntPoint(x: Int(point.x.rounded(.down)), y: Int(point.y.rounded(.down)))
        guard canvas.bounds.contains(pixel) else { return }
        var picked: Pixel
        if allLayers {
            picked = .clear
            for layer in canvas.layers where layer.isVisible {
                picked = Compositing.over(picked, layer.buffer[pixel.x, pixel.y], coverage: Float(layer.opacity))
            }
        } else {
            picked = canvas.activeLayer.buffer[pixel.x, pixel.y]
        }
        if secondary { color2 = picked } else { color1 = picked }
    }

    // MARK: Selection dragging

    /// Whether a drag starting at `point` would move the selection rather than start a new one.
    func selectionContains(_ point: Point2D) -> Bool {
        canvas.selection.contains(IntPoint(x: Int(point.x.rounded(.down)), y: Int(point.y.rounded(.down))))
    }

    func beginSelectionDrag(at point: Point2D, modifiers: DragModifiers) {
        guard tool.isSelectionTool else { return }
        finishInteractions()
        if selectionContains(point), let origin = canvas.selection.bounds.map({ IntPoint(x: $0.minX, y: $0.minY) }) {
            selectionDrag = .move(edit: nil, grab: point, origin: origin, smear: modifiers.shift, duplicate: modifiers.option)
            return
        }
        let mode: SelectionCombineMode = switch (modifiers.shift, modifiers.option) {
        case (true, true): .intersect
        case (true, false): .add
        case (false, true): .subtract
        case (false, false): .replace
        }
        switch tool {
        case .lassoSelect:
            selectionDrag = .lasso(points: [point], mode: mode)
        case .ellipseSelect:
            selectionDrag = .marquee(shape: .ellipse, start: point, mode: mode, shiftHeldAtStart: modifiers.shift, shiftReleased: false)
        default:
            selectionDrag = .marquee(shape: .rectangle, start: point, mode: mode, shiftHeldAtStart: modifiers.shift, shiftReleased: false)
        }
        updateSelectionPreview(to: point, shiftDown: modifiers.shift)
    }

    func continueSelectionDrag(to point: Point2D, shiftDown: Bool) {
        switch selectionDrag {
        case .marquee, .lasso:
            updateSelectionPreview(to: point, shiftDown: shiftDown)
        case .move(var edit, let grab, let origin, let smear, let duplicate):
            if edit == nil {
                edit = SelectionActions.beginMove(duplicate: duplicate, canvas: canvas, history: history, context: selectionContext)
                guard edit != nil else {
                    selectionDrag = nil
                    return
                }
            }
            let target = IntPoint(
                x: origin.x + Int((point.x - grab.x).rounded()),
                y: origin.y + Int((point.y - grab.y).rounded())
            )
            if let edit, let destination = canvas.selection.floating?.destination,
               destination.minX != target.x || destination.minY != target.y {
                SelectionActions.move(to: target, smear: smear, edit: edit, canvas: canvas, context: selectionContext)
                selectionDidChange()
            }
            selectionDrag = .move(edit: edit, grab: grab, origin: origin, smear: smear, duplicate: duplicate)
        case nil:
            break
        }
    }

    /// Finishes the drag. Pass nil to finish without a final pointer position.
    func endSelectionDrag(at point: Point2D?) {
        guard let drag = selectionDrag else { return }
        selectionDrag = nil
        switch drag {
        case .marquee(_, let start, let mode, _, _):
            let clicked = point.map { abs($0.x - start.x) < 1 && abs($0.y - start.y) < 1 } ?? false
            commitSelectionPreview(deselecting: clicked && mode == .replace)
        case .lasso(let points, let mode):
            commitSelectionPreview(deselecting: points.count < 3 && mode == .replace)
        case .move(let edit, _, _, _, _):
            if let edit { recordingChanges { history.commit(edit) } }
        }
        selectionDidChange()
    }

    private func commitSelectionPreview(deselecting: Bool) {
        let preview = marqueePreview
        marqueePreview = nil
        recordingChanges {
            if deselecting {
                SelectionActions.deselect(canvas: canvas, history: history, context: selectionContext)
            } else {
                SelectionActions.select(preview, mode: .replace, canvas: canvas, history: history, context: selectionContext)
            }
        }
    }

    private func updateSelectionPreview(to point: Point2D, shiftDown: Bool) {
        let shape: SelectionMask?
        let mode: SelectionCombineMode
        switch selectionDrag {
        case .marquee(let kind, let start, let combine, let shiftHeldAtStart, var shiftReleased):
            if !shiftDown { shiftReleased = true }
            // Shift held from the start picks "add"; it only constrains once released and pressed again.
            let constrain = shiftDown && (!shiftHeldAtStart || shiftReleased)
            selectionDrag = .marquee(shape: kind, start: start, mode: combine, shiftHeldAtStart: shiftHeldAtStart, shiftReleased: shiftReleased)
            shape = SelectionActions.marquee(kind, from: start, to: point, constrain: constrain, in: canvas.bounds)
            mode = combine
        case .lasso(var points, let combine):
            if let last = points.last, abs(last.x - point.x) + abs(last.y - point.y) >= 1 {
                points.append(point)
            }
            selectionDrag = .lasso(points: points, mode: combine)
            shape = SelectionMask.polygon(points, clippedTo: canvas.bounds)
            mode = combine
        default:
            return
        }
        marqueePreview = SelectionMask.combine(canvas.selection.outline, with: shape, mode: mode)
        selectionBounds = marqueePreview?.bounds
        onRender()
    }

    // MARK: Selection commands

    private func performSelectionCommand(_ command: () -> Void) {
        finishInteractions()
        recordingChanges(command)
        selectionDidChange()
    }

    /// Runs `body` and tells the document it changed if a history step was recorded.
    private func recordingChanges(_ body: () -> Void) {
        let revision = history.revision
        body()
        if history.revision != revision { onDocumentChange(.done) }
    }

    func selectAll() {
        if !tool.isSelectionTool { tool = .rectangleSelect }
        performSelectionCommand { SelectionActions.selectAll(canvas: canvas, history: history, context: selectionContext) }
    }

    func deselect() {
        performSelectionCommand { SelectionActions.deselect(canvas: canvas, history: history, context: selectionContext) }
    }

    func invertSelection() {
        if !tool.isSelectionTool { tool = .rectangleSelect }
        performSelectionCommand { SelectionActions.invert(canvas: canvas, history: history, context: selectionContext) }
    }

    func deleteSelection(named name: String = "Delete") {
        performSelectionCommand {
            SelectionActions.deleteSelection(named: name, canvas: canvas, history: history, context: selectionContext)
        }
    }

    func nudgeSelection(dx: Int, dy: Int) {
        performSelectionCommand {
            SelectionActions.nudge(dx: dx, dy: dy, canvas: canvas, history: history, context: selectionContext)
        }
    }

    /// The selected pixels, or nil when nothing is selected.
    func selectedPixels() -> PixelBuffer? {
        finishInteractions()
        return SelectionActions.selectedPixels(canvas: canvas, context: selectionContext)
    }

    /// Pastes as a floating selection at the top-left of the visible part of the canvas.
    func paste(_ image: PixelBuffer) {
        let visibleTopLeft = viewport.imagePoint(fromView: .zero)
        let origin = IntPoint(
            x: min(max(0, Int(visibleTopLeft.x.rounded(.down))), canvas.size.width - 1),
            y: min(max(0, Int(visibleTopLeft.y.rounded(.down))), canvas.size.height - 1)
        )
        if !tool.isSelectionTool { tool = .rectangleSelect }
        performSelectionCommand {
            SelectionActions.paste(image, at: origin, canvas: canvas, history: history, context: selectionContext)
        }
    }

    private func selectionDidChange() {
        selectionBounds = marqueePreview?.bounds ?? canvas.selection.bounds
        if canvasSize != canvas.size { canvasDidResize() }
        onRender()
    }

    // MARK: Image

    func cropToSelection() {
        performSelectionCommand { ImageActions.cropToSelection(canvas: canvas, history: history, context: selectionContext) }
    }

    /// Keeps the zoom and recenters on the new canvas.
    private func canvasDidResize() {
        canvasSize = canvas.size
        let center = Point2D(x: Double(canvas.size.width) / 2, y: Double(canvas.size.height) / 2)
        updateViewport { $0.center = center }
    }

    // MARK: Effects

    /// Opens an effect's dialog and shows its preview. It applies to the selection, or the whole layer.
    func beginEffect(_ kind: EffectKind) {
        finishInteractions()
        placeFloatingSelection()
        effectValue = kind.defaultValue
        effectEdit = history.beginEdit(kind.title, on: canvas)
        activeEffect = kind
        previewEffect()
    }

    func previewEffect() {
        guard let kind = activeEffect, let edit = effectEdit else { return }
        edit.restoreOriginals()
        Effects.apply(kind.effect(effectValue), to: canvas.activeLayer, selection: canvas.selection.marquee, edit: edit)
        onRender()
    }

    func applyEffect() {
        guard let edit = effectEdit else { return }
        effectEdit = nil
        activeEffect = nil
        recordingChanges { history.commit(edit) }
    }

    func cancelEffect() {
        effectEdit?.restoreOriginals()
        effectEdit = nil
        activeEffect = nil
        onRender()
    }

    // MARK: Undo

    var undoActionName: String? { history.undoActionName }
    var redoActionName: String? { history.redoActionName }

    func undo() {
        finishInteractions()
        guard history.undo(on: canvas) != nil else { return }
        onDocumentChange(.undone)
        selectionDidChange()
    }

    func redo() {
        finishInteractions()
        guard history.redo(on: canvas) != nil else { return }
        onDocumentChange(.redone)
        selectionDidChange()
    }

    // MARK: Colors

    func swapColors() {
        swap(&color1, &color2)
    }

    // MARK: Viewport

    func updateViewport(_ change: (inout Viewport) -> Void) {
        var updated = viewport
        change(&updated)
        guard updated != viewport else { return }
        viewport = updated
        onRender()
    }

    private var viewCenter: Point2D {
        Point2D(x: viewport.viewSize.width / 2, y: viewport.viewSize.height / 2)
    }

    func zoomIn() {
        updateViewport { $0.setZoom($0.nextZoomStep(zoomingIn: true), anchor: viewCenter) }
    }

    func zoomOut() {
        updateViewport { $0.setZoom($0.nextZoomStep(zoomingIn: false), anchor: viewCenter) }
    }

    func zoomToActualSize() {
        updateViewport { $0.setZoom(1, anchor: viewCenter) }
    }

    func zoomToFit() {
        updateViewport { $0.fit(canvas.size, margin: 40) }
    }

    // MARK: Files

    /// The image as it looks, including any floating selection, encoded in `format`.
    /// Formats without transparency are flattened over Color 2.
    func encoded(as format: ImageFileFormat, quality: Double = 0.9) throws -> Data {
        try ImageCodec.encode(
            canvas.flattened(transparentKey: selectionContext.transparentKey),
            colorSpace: canvas.colorSpace,
            as: format,
            quality: quality,
            matte: color2
        )
    }

    func flattenedPNG() throws -> Data {
        try encoded(as: .png)
    }
}
