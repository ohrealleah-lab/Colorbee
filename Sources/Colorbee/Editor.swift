import ColorbeeCore
import Foundation
import Observation

enum DocumentChange {
    case done
    case undone
    case redone
}

enum Tool: CaseIterable {
    case brush
    case rectangleSelect
    case ellipseSelect

    var selectionShape: SelectionShape? {
        switch self {
        case .brush: nil
        case .rectangleSelect: .rectangle
        case .ellipseSelect: .ellipse
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
    let canvas: Canvas
    @ObservationIgnored let history: History

    private(set) var tool: Tool = .brush
    var color1: Pixel = .black
    var color2: Pixel = .white {
        didSet { if transparentSelection { onRender() } }
    }
    var brushDiameter: Double = 5
    var transparentSelection = false {
        didSet { onRender() }
    }
    var showsPixelGrid = true {
        didSet { onRender() }
    }
    private(set) var viewport = Viewport()
    var pointer: IntPoint?
    /// The marquee being dragged, already combined with the existing selection.
    private(set) var marqueePreview: SelectionMask?
    /// Bounds of the selected area, for the status bar.
    private(set) var selectionBounds: IntRect?

    @ObservationIgnored var onRender: () -> Void = {}
    @ObservationIgnored var onDocumentChange: (DocumentChange) -> Void = { _ in }
    @ObservationIgnored private var activeStroke: (edit: Edit, stroke: RoundBrushStroke)?
    @ObservationIgnored private var selectionDrag: SelectionDrag?

    private enum SelectionDrag {
        case marquee(shape: SelectionShape, start: Point2D, mode: SelectionCombineMode, shiftHeldAtStart: Bool, shiftReleased: Bool)
        case move(edit: Edit?, grab: Point2D, origin: IntPoint, smear: Bool, duplicate: Bool)
    }

    init(canvas: Canvas) {
        self.canvas = canvas
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
        if newTool.selectionShape == nil {
            recordingChanges { SelectionActions.deselect(canvas: canvas, history: history, context: selectionContext) }
            selectionDidChange()
        }
        tool = newTool
    }

    /// Ends any drag in progress so menu commands and undo see a settled document.
    private func finishInteractions() {
        endStroke()
        if selectionDrag != nil { endSelectionDrag(at: nil) }
    }

    // MARK: Brush

    func beginStroke(at point: Point2D, secondary: Bool) {
        finishInteractions()
        if canvas.selection.floating != nil {
            recordingChanges { SelectionActions.placeFloating(canvas: canvas, history: history, context: selectionContext) }
            selectionDidChange()
        }
        let edit = history.beginEdit("Brush Stroke", on: canvas)
        let stroke = RoundBrushStroke(
            diameter: brushDiameter,
            color: secondary ? color2 : color1,
            layer: canvas.activeLayer,
            edit: edit
        )
        activeStroke = (edit, stroke)
        if !stroke.move(to: point).isEmpty { onRender() }
    }

    func continueStroke(to point: Point2D) {
        guard let stroke = activeStroke?.stroke else { return }
        if !stroke.move(to: point).isEmpty { onRender() }
    }

    func endStroke() {
        guard let edit = activeStroke?.edit else { return }
        activeStroke = nil
        recordingChanges { history.commit(edit) }
    }

    // MARK: Selection dragging

    /// Whether a drag starting at `point` would move the selection rather than draw a new marquee.
    func selectionContains(_ point: Point2D) -> Bool {
        canvas.selection.contains(IntPoint(x: Int(point.x.rounded(.down)), y: Int(point.y.rounded(.down))))
    }

    func beginSelectionDrag(at point: Point2D, modifiers: DragModifiers) {
        guard let shape = tool.selectionShape else { return }
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
        selectionDrag = .marquee(shape: shape, start: point, mode: mode, shiftHeldAtStart: modifiers.shift, shiftReleased: false)
        updateMarqueePreview(to: point, shiftDown: modifiers.shift)
    }

    func continueSelectionDrag(to point: Point2D, shiftDown: Bool) {
        switch selectionDrag {
        case .marquee:
            updateMarqueePreview(to: point, shiftDown: shiftDown)
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
            if let edit, canvas.selection.floating?.destination.minX != target.x || canvas.selection.floating?.destination.minY != target.y {
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
            let preview = marqueePreview
            marqueePreview = nil
            let clicked = point.map { abs($0.x - start.x) < 1 && abs($0.y - start.y) < 1 } ?? false
            recordingChanges {
                if clicked, mode == .replace {
                    SelectionActions.deselect(canvas: canvas, history: history, context: selectionContext)
                } else {
                    SelectionActions.select(preview, mode: .replace, canvas: canvas, history: history, context: selectionContext)
                }
            }
        case .move(let edit, _, _, _, _):
            if let edit { recordingChanges { history.commit(edit) } }
        }
        selectionDidChange()
    }

    private func updateMarqueePreview(to point: Point2D, shiftDown: Bool) {
        guard case .marquee(let shape, let start, let mode, let shiftHeldAtStart, var shiftReleased) = selectionDrag else { return }
        if !shiftDown { shiftReleased = true }
        // Shift held from the start picks "add"; it only constrains once released and pressed again.
        let constrain = shiftDown && (!shiftHeldAtStart || shiftReleased)
        selectionDrag = .marquee(shape: shape, start: start, mode: mode, shiftHeldAtStart: shiftHeldAtStart, shiftReleased: shiftReleased)
        let shapeMask = SelectionActions.marquee(shape, from: start, to: point, constrain: constrain, in: canvas.bounds)
        marqueePreview = SelectionMask.combine(canvas.selection.outline, with: shapeMask, mode: mode)
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
        if tool.selectionShape == nil { tool = .rectangleSelect }
        performSelectionCommand { SelectionActions.selectAll(canvas: canvas, history: history, context: selectionContext) }
    }

    func deselect() {
        performSelectionCommand { SelectionActions.deselect(canvas: canvas, history: history, context: selectionContext) }
    }

    func invertSelection() {
        if tool.selectionShape == nil { tool = .rectangleSelect }
        performSelectionCommand { SelectionActions.invert(canvas: canvas, history: history, context: selectionContext) }
    }

    func placeSelection() {
        performSelectionCommand { SelectionActions.placeFloating(canvas: canvas, history: history, context: selectionContext) }
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
        if tool.selectionShape == nil { tool = .rectangleSelect }
        performSelectionCommand {
            SelectionActions.paste(image, at: origin, canvas: canvas, history: history, context: selectionContext)
        }
    }

    private func selectionDidChange() {
        selectionBounds = marqueePreview?.bounds ?? canvas.selection.bounds
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

    // MARK: Export

    /// The image as it looks, including any floating selection, as PNG.
    func flattenedPNG() throws -> Data {
        try ImageCodec.encodePNG(canvas.flattened(transparentKey: selectionContext.transparentKey), colorSpace: canvas.colorSpace)
    }
}
