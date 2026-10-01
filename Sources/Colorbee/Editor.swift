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
    case shape
    case text
    case rectangleSelect
    case ellipseSelect
    case lassoSelect
    case magicWand

    var isSelectionTool: Bool {
        switch self {
        case .rectangleSelect, .ellipseSelect, .lassoSelect, .magicWand: true
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

/// A shape still being edited, before it's placed into the layer (FR-5.1).
struct PendingShape: Equatable {
    var start: Point2D
    var end: Point2D
    /// Right-dragged: outline uses Color 2 and fill uses Color 1.
    var swapped: Bool
}

/// Text formatting for the text tool (FR-6.1).
struct TextStyle: Equatable {
    var fontFamily = "Helvetica Neue"
    /// In image pixels at 100% zoom.
    var fontSize = 24.0
    var bold = false
    var italic = false
    var underline = false
    var strikethrough = false
    var alignment: TextAlignment = .left
    /// Opaque draws a Color 2 rectangle behind the text.
    var opaqueBackground = false
}

/// A text box still being typed into.
struct PendingText: Equatable {
    var origin: Point2D
    /// Set when the box was dragged out; otherwise lines run as long as they need.
    var wrapWidth: Double?
    var string = ""
}

/// What a press on a pending shape grabbed.
enum ShapeHandle: Equatable {
    case box(SelectionHandle)
    case start
    case end
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
    // Colors show live in pending shapes and transparent selections.
    var color1: Pixel = .black {
        didSet { onRender() }
    }
    var color2: Pixel = .white {
        didSet { onRender() }
    }
    var brushDiameter: Double = 5
    var eraserSize = 8
    /// Fill bucket tolerance, 0...1.
    var fillTolerance = 0.0
    /// Magic Wand tolerance, 0...1.
    var wandTolerance = 0.1
    var wandContiguous = true
    var transparentSelection = false {
        didSet { onRender() }
    }
    /// How stretched selections are resampled: smooth for photos and screenshots, sharp for pixel art.
    var smoothResize = true {
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
    /// A stretched floating selection's width as a percentage of its original, for the status bar.
    private(set) var selectionScalePercent: Int?
    var shapeKind: ShapeKind = .rectangle {
        didSet { onRender() }
    }
    var shapeLineWidth = 3.0 {
        didSet { onRender() }
    }
    var shapeHasOutline = true {
        didSet { onRender() }
    }
    var shapeHasFill = false {
        didSet { onRender() }
    }
    private(set) var pendingShape: PendingShape?
    var textStyle = TextStyle() {
        didSet { onRender() }
    }
    private(set) var pendingText: PendingText?
    /// The effect whose dialog is open, if any.
    private(set) var activeEffect: EffectKind?
    var effectValue = 8.0

    @ObservationIgnored var onRender: () -> Void = {}
    @ObservationIgnored var onDocumentChange: (DocumentChange) -> Void = { _ in }
    @ObservationIgnored private var activeStroke: ActiveStroke?
    @ObservationIgnored private var selectionDrag: SelectionDrag?
    @ObservationIgnored private var effectEdit: Edit?
    @ObservationIgnored private var shapeDrag: ShapeDrag?
    @ObservationIgnored private var shapeRenderCache: (spec: ShapeSpec, pixels: PixelBuffer, origin: IntPoint)?

    private enum ShapeDrag {
        case draw
        case move(grab: Point2D, original: PendingShape)
        case handle(ShapeHandle, grab: Point2D, original: PendingShape)
    }

    private struct ActiveStroke {
        let edit: Edit
        let stroke: Stroke
        let start: Point2D
    }

    private enum SelectionDrag {
        case marquee(shape: SelectionShape, start: Point2D, mode: SelectionCombineMode, shiftHeldAtStart: Bool, shiftReleased: Bool)
        case lasso(points: [Point2D], mode: SelectionCombineMode)
        case move(edit: Edit?, grab: Point2D, origin: IntPoint, smear: Bool, duplicate: Bool)
        case resize(edit: Edit?, handle: SelectionHandle, original: IntRect, grab: Point2D)
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
        SelectionContext(color2: color2, transparentSelection: transparentSelection, resampling: smoothResize ? .smooth : .nearestNeighbor)
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
    /// A pending shape is placed.
    private func finishInteractions() {
        shapeDrag = nil
        commitPendingShape()
        commitPendingText()
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

    // MARK: Shapes

    /// The pending shape with the current toolbar settings applied.
    var pendingShapeSpec: ShapeSpec? {
        guard let pendingShape else { return nil }
        let outlineColor = pendingShape.swapped ? color2 : color1
        let fillColor = pendingShape.swapped ? color1 : color2
        return ShapeSpec(
            kind: shapeKind,
            start: pendingShape.start,
            end: pendingShape.end,
            lineWidth: shapeLineWidth,
            outline: shapeHasOutline || shapeKind.isLinear ? outlineColor : nil,
            fill: shapeHasFill ? fillColor : nil
        )
    }

    /// The pending shape drawn into pixels, cached until it changes.
    func renderedPendingShape() -> (pixels: PixelBuffer, origin: IntPoint)? {
        guard let spec = pendingShapeSpec else { return nil }
        if let cache = shapeRenderCache, cache.spec == spec { return (cache.pixels, cache.origin) }
        guard let rendered = ShapeRenderer.render(spec, colorSpace: canvas.colorSpace, clippedTo: canvas.bounds) else {
            shapeRenderCache = nil
            return nil
        }
        shapeRenderCache = (spec, rendered.pixels, rendered.origin)
        return rendered
    }

    /// Where the pending shape's handles are, in image coordinates.
    var pendingShapeHandlePoints: [Point2D] {
        guard let spec = pendingShapeSpec else { return [] }
        if spec.kind.isLinear { return [spec.start, spec.end] }
        return SelectionHandle.allCases.map { $0.point(on: spec.box) }
    }

    func shapeHandle(atView point: Point2D) -> ShapeHandle? {
        guard let spec = pendingShapeSpec else { return nil }
        func near(_ imagePoint: Point2D) -> Bool {
            let center = viewport.viewPoint(fromImage: imagePoint)
            return abs(center.x - point.x) <= 6 && abs(center.y - point.y) <= 6
        }
        if spec.kind.isLinear {
            if near(spec.end) { return .end }
            if near(spec.start) { return .start }
            return nil
        }
        return SelectionHandle.allCases.first { near($0.point(on: spec.box)) }.map(ShapeHandle.box)
    }

    /// Whether `point` is on the pending shape, so a drag there moves it.
    func pendingShapeContains(_ point: Point2D) -> Bool {
        guard let spec = pendingShapeSpec else { return false }
        if !spec.kind.isLinear {
            return spec.box.contains(IntPoint(x: Int(point.x.rounded(.down)), y: Int(point.y.rounded(.down))))
        }
        let dx = spec.end.x - spec.start.x, dy = spec.end.y - spec.start.y
        let lengthSquared = max(dx * dx + dy * dy, 1e-9)
        let t = min(1, max(0, ((point.x - spec.start.x) * dx + (point.y - spec.start.y) * dy) / lengthSquared))
        let nearestX = spec.start.x + t * dx, nearestY = spec.start.y + t * dy
        let distance = ((point.x - nearestX) * (point.x - nearestX) + (point.y - nearestY) * (point.y - nearestY)).squareRoot()
        return distance <= spec.lineWidth / 2 + 4 / viewport.zoom
    }

    func beginShapeDrag(at point: Point2D, viewPoint: Point2D, secondary: Bool) {
        if let pendingShape {
            if let handle = shapeHandle(atView: viewPoint) {
                shapeDrag = .handle(handle, grab: point, original: pendingShape)
                return
            }
            if pendingShapeContains(point) {
                shapeDrag = .move(grab: point, original: pendingShape)
                return
            }
        }
        finishInteractions()
        placeFloatingSelection()
        pendingShape = PendingShape(start: point, end: point, swapped: secondary)
        shapeDrag = .draw
        onRender()
    }

    func continueShapeDrag(to point: Point2D, shiftDown: Bool) {
        guard var shape = pendingShape, let drag = shapeDrag else { return }
        switch drag {
        case .draw:
            shape.end = point
            if shiftDown, let spec = pendingShapeSpec {
                var constrained = spec
                constrained.end = point
                shape.end = constrained.constrained().end
            }
        case .move(let grab, let original):
            let dx = point.x - grab.x, dy = point.y - grab.y
            shape.start = Point2D(x: original.start.x + dx, y: original.start.y + dy)
            shape.end = Point2D(x: original.end.x + dx, y: original.end.y + dy)
        case .handle(let handle, let grab, let original):
            let delta = Point2D(x: point.x - grab.x, y: point.y - grab.y)
            switch handle {
            case .start:
                shape.start = Point2D(x: original.start.x + delta.x, y: original.start.y + delta.y)
            case .end:
                shape.end = Point2D(x: original.end.x + delta.x, y: original.end.y + delta.y)
            case .box(let boxHandle):
                let originalBox = IntRect(
                    enclosingMinX: min(original.start.x, original.end.x), minY: min(original.start.y, original.end.y),
                    maxX: max(original.start.x, original.end.x), maxY: max(original.start.y, original.end.y)
                )
                let box = boxHandle.resize(originalBox, by: delta, keepProportions: shiftDown)
                shape.start = Point2D(x: Double(box.minX), y: Double(box.minY))
                shape.end = Point2D(x: Double(box.maxX), y: Double(box.maxY))
            }
        }
        pendingShape = shape
        onRender()
    }

    func endShapeDrag() {
        defer { shapeDrag = nil }
        if case .draw = shapeDrag, let shape = pendingShape,
           abs(shape.end.x - shape.start.x) < 1, abs(shape.end.y - shape.start.y) < 1 {
            pendingShape = nil
            onRender()
        }
    }

    /// Draws the pending shape into the active layer as one step.
    func commitPendingShape() {
        guard let spec = pendingShapeSpec else { return }
        let rendered = renderedPendingShape()
        pendingShape = nil
        shapeRenderCache = nil
        if let rendered {
            let edit = history.beginEdit(spec.kind.name, on: canvas)
            Compositing.draw(rendered.pixels, at: rendered.origin, onto: canvas.activeLayer, edit: edit)
            recordingChanges { history.commit(edit) }
        }
        onRender()
    }

    func cancelPendingShape() {
        pendingShape = nil
        shapeRenderCache = nil
        shapeDrag = nil
        onRender()
    }

    // MARK: Text

    /// Opens a text box with its top-left at `origin`. Any open box is placed first.
    func beginText(at origin: Point2D, wrapWidth: Double?) {
        finishInteractions()
        placeFloatingSelection()
        pendingText = PendingText(origin: origin, wrapWidth: wrapWidth)
        onRender()
    }

    func updatePendingText(_ string: String) {
        pendingText?.string = string
    }

    func textSpec(for text: PendingText) -> TextSpec {
        var spec = TextSpec(
            text: text.string,
            origin: text.origin,
            wrapWidth: text.wrapWidth,
            fontFamily: textStyle.fontFamily,
            fontSize: textStyle.fontSize,
            color: color1,
            background: textStyle.opaqueBackground ? color2 : nil
        )
        spec.bold = textStyle.bold
        spec.italic = textStyle.italic
        spec.underline = textStyle.underline
        spec.strikethrough = textStyle.strikethrough
        spec.alignment = textStyle.alignment
        return spec
    }

    /// Turns the open text box into pixels on the active layer (FR-6.3).
    func commitPendingText() {
        guard let text = pendingText else { return }
        pendingText = nil
        if let rendered = TextRenderer.render(textSpec(for: text), colorSpace: canvas.colorSpace, clippedTo: canvas.bounds) {
            let edit = history.beginEdit("Text", on: canvas)
            Compositing.draw(rendered.pixels, at: rendered.origin, onto: canvas.activeLayer, edit: edit)
            recordingChanges { history.commit(edit) }
        }
        onRender()
    }

    // MARK: Selection dragging

    /// Whether a drag starting at `point` would move the selection rather than start a new one.
    func selectionContains(_ point: Point2D) -> Bool {
        canvas.selection.contains(IntPoint(x: Int(point.x.rounded(.down)), y: Int(point.y.rounded(.down))))
    }

    /// The handle under a view point, if the selection's handles are showing there.
    func selectionHandle(atView point: Point2D) -> SelectionHandle? {
        guard tool.isSelectionTool, marqueePreview == nil, let rect = canvas.selection.bounds else { return nil }
        return SelectionHandle.allCases.first { handle in
            let center = viewport.viewPoint(fromImage: handle.point(on: rect))
            return abs(center.x - point.x) <= 6 && abs(center.y - point.y) <= 6
        }
    }

    func beginResize(_ handle: SelectionHandle, at point: Point2D) {
        finishInteractions()
        guard let rect = canvas.selection.bounds else { return }
        selectionDrag = .resize(edit: nil, handle: handle, original: rect, grab: point)
    }

    func beginSelectionDrag(at point: Point2D, modifiers: DragModifiers) {
        guard tool.isSelectionTool else { return }
        finishInteractions()
        // The wand always selects when a modifier is held, so it can add to or subtract from a selection.
        let wandCombining = tool == .magicWand && (modifiers.shift || modifiers.option)
        if !wandCombining, selectionContains(point), let origin = canvas.selection.bounds.map({ IntPoint(x: $0.minX, y: $0.minY) }) {
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
        case .magicWand:
            let seed = IntPoint(x: Int(point.x.rounded(.down)), y: Int(point.y.rounded(.down)))
            let mask = SelectionMask.magicWand(in: canvas.activeLayer.buffer, at: seed, tolerance: wandTolerance, contiguous: wandContiguous)
            recordingChanges {
                SelectionActions.select(mask, mode: mode, canvas: canvas, history: history, context: selectionContext)
            }
            selectionDidChange()
            return
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
        case .resize(var edit, let handle, let original, let grab):
            if edit == nil {
                // Resizing a marquee lifts its pixels first.
                edit = SelectionActions.beginMove(duplicate: false, named: "Resize Selection", canvas: canvas, history: history, context: selectionContext)
                guard edit != nil else {
                    selectionDrag = nil
                    return
                }
            }
            let delta = Point2D(x: point.x - grab.x, y: point.y - grab.y)
            SelectionActions.resize(to: handle.resize(original, by: delta, keepProportions: shiftDown), canvas: canvas)
            selectionDrag = .resize(edit: edit, handle: handle, original: original, grab: grab)
            selectionDidChange()
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
        case .move(let edit, _, _, _, _), .resize(let edit, _, _, _):
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

    /// ⌘-arrows: grow or shrink the marquee's outline without touching the pixels.
    func resizeMarquee(byWidth dx: Int, height dy: Int) {
        finishInteractions()
        SelectionActions.resizeMarquee(byWidth: dx, height: dy, canvas: canvas)
        selectionDidChange()
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
        if let floating = canvas.selection.floating, floating.destination.size != floating.pixels.size {
            selectionScalePercent = Int((Double(floating.destination.width) / Double(floating.pixels.width) * 100).rounded())
        } else {
            selectionScalePercent = nil
        }
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

    /// Batch redaction with a solid color: every selected region becomes Color 1 in one step (FR-9.4).
    func applySolidFill() {
        finishInteractions()
        placeFloatingSelection()
        guard let selection = canvas.selection.marquee else { return }
        let edit = history.beginEdit("Solid Fill", on: canvas)
        Effects.apply(.solidFill(color1), to: canvas.activeLayer, selection: selection, edit: edit)
        recordingChanges { history.commit(edit) }
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
        // Undo first discards a shape that hasn't been placed yet.
        if pendingShape != nil {
            cancelPendingShape()
            return
        }
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

    /// A PNG scaled by an export preset, using the sharpness that suits the image's size.
    func encoded(using preset: ExportPreset) throws -> Data {
        let image = canvas.flattened(transparentKey: selectionContext.transparentKey)
        let scaled = image.resampled(to: preset.targetSize(for: image.size), using: ExportPreset.resampling(for: image.size))
        return try ImageCodec.encode(scaled, colorSpace: canvas.colorSpace, as: .png)
    }

    func flattenedPNG() throws -> Data {
        try encoded(as: .png)
    }
}
