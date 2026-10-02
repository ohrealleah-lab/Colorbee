import ColorbeeCore
import CoreGraphics
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
    case gradient
    case measure
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

/// Mirror drawing across the canvas's center lines (FR-7.3).
enum SymmetryMode: CaseIterable {
    case off
    case vertical
    case horizontal
    case both

    var title: String {
        switch self {
        case .off: "Off"
        case .vertical: "Vertical"
        case .horizontal: "Horizontal"
        case .both: "Both"
        }
    }
}

/// A measured distance (FR-7.1), between pixel centers.
struct Measurement: Equatable {
    var start: IntPoint
    var end: IntPoint

    var dx: Int { end.x - start.x }
    var dy: Int { end.y - start.y }
    var distance: Double { (Double(dx * dx + dy * dy)).squareRoot() }
    /// Degrees counter-clockwise from the positive x axis, as on a protractor.
    var angle: Double { atan2(Double(-dy), Double(dx)) * 180 / .pi }
}

/// An effect with a dialog, and the sliders it shows.
enum EffectKind {
    case gaussianBlur
    case pixelate
    case sharpen
    case brightnessContrast
    case hueSaturation

    struct Parameter {
        let label: String
        let range: ClosedRange<Double>
        let defaultValue: Double
        let unit: String
    }

    var title: String {
        switch self {
        case .gaussianBlur: "Gaussian Blur"
        case .pixelate: "Pixelate"
        case .sharpen: "Sharpen"
        case .brightnessContrast: "Brightness/Contrast"
        case .hueSaturation: "Hue/Saturation"
        }
    }

    var parameters: [Parameter] {
        switch self {
        case .gaussianBlur: [Parameter(label: "Radius", range: 1...100, defaultValue: 8, unit: "px")]
        case .pixelate: [Parameter(label: "Cell size", range: 2...100, defaultValue: 12, unit: "px")]
        case .sharpen: [Parameter(label: "Amount", range: 0...200, defaultValue: 60, unit: "%")]
        case .brightnessContrast: [
            Parameter(label: "Brightness", range: -100...100, defaultValue: 0, unit: ""),
            Parameter(label: "Contrast", range: -100...100, defaultValue: 0, unit: ""),
        ]
        case .hueSaturation: [
            Parameter(label: "Hue", range: -180...180, defaultValue: 0, unit: "°"),
            Parameter(label: "Saturation", range: -100...100, defaultValue: 0, unit: ""),
            Parameter(label: "Lightness", range: -100...100, defaultValue: 0, unit: ""),
        ]
        }
    }

    func effect(_ values: [Double]) -> Effect {
        switch self {
        case .gaussianBlur: .gaussianBlur(radius: values[0])
        case .pixelate: .pixelate(cellSize: Int(values[0].rounded()))
        case .sharpen: .sharpen(amount: values[0])
        case .brightnessContrast: .brightnessContrast(brightness: values[0], contrast: values[1])
        case .hueSaturation: .hueSaturation(hue: values[0], saturation: values[1], lightness: values[2])
        }
    }
}

enum RedactionTreatment: CaseIterable {
    case blur
    case pixelate
    case solidFill

    var title: String {
        switch self {
        case .blur: "Blur"
        case .pixelate: "Pixelate"
        case .solidFill: "Solid Fill"
        }
    }
}

/// An Auto-Redact review in progress (FR-9.3).
struct AutoRedactSession {
    /// The area searched: the selection, or nil for the whole image.
    let region: SelectionMask?
    var scan: TextScan?
    var failure: String?
    var matches: [RedactionMatch] = []
    /// Matches the person unchecked to keep visible.
    var keptVisible: Set<UUID> = []
    var treatment: RedactionTreatment = .solidFill

    var isReading: Bool { scan == nil && failure == nil }
    var selectedMatches: [RedactionMatch] { matches.filter { !keptVisible.contains($0.id) } }
}

/// The Before/After view's settings (FR-11.3).
struct Comparison: Equatable {
    enum Baseline { case asOpened, lastSaved }
    enum Layout { case split, sideBySide }

    var baseline: Baseline = .asOpened
    var layout: Layout = .split
    /// The split's divider, as a fraction of the view's width.
    var divider = 0.5
}

/// A shape still being edited, before it's placed into the layer (FR-5.1).
struct PendingShape: Equatable {
    var kind: ShapeKind
    var start: Point2D
    var end: Point2D
    /// Polygon vertices, or a curve's start, two control points and end.
    var points: [Point2D] = []
    var rotation = 0.0
    /// Right-dragged: outline uses Color 2 and fill uses Color 1.
    var swapped: Bool
    /// A polygon or curve still being placed point by point.
    var isBuilding = false
    /// Curve construction: 0 the line, 1 the first bend, 2 the second bend.
    var curveStage = 0

    mutating func translate(by dx: Double, _ dy: Double) {
        start = Point2D(x: start.x + dx, y: start.y + dy)
        end = Point2D(x: end.x + dx, y: end.y + dy)
        points = points.map { Point2D(x: $0.x + dx, y: $0.y + dy) }
    }
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
    /// A dragged-out box keeps at least its dragged height.
    var minimumHeight: Double = 0
    var string = ""
}

/// What a press on a pending shape grabbed.
enum ShapeHandle: Equatable {
    case box(SelectionHandle)
    case start
    case end
    case vertex(Int)
    case rotate
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
    static let eraserSizes = Array(stride(from: 2, through: 20, by: 2)) + [30, 40]
    /// The marker paints at half the chosen color's opacity.
    static let markerOpacity = 0.5

    let canvas: Canvas
    @ObservationIgnored let history: History

    private(set) var tool: Tool = .pencil
    var brushKind: BrushKind = .round
    // Colors show live in pending shapes and transparent selections.
    var color1: Pixel = .black {
        didSet { renderSoon() }
    }
    var color2: Pixel = .white {
        didSet { renderSoon() }
    }
    var brushDiameter: Double = 5
    /// The eraser's square outline follows the pointer, so it redraws when the size changes.
    var eraserSize = 8 {
        didSet { renderSoon() }
    }
    /// Fill bucket tolerance, 0...1.
    var fillTolerance = 0.0
    /// Magic Wand tolerance, 0...1.
    var wandTolerance = 0.1
    var wandContiguous = true
    var transparentSelection = false {
        didSet { renderSoon() }
    }
    /// How stretched selections are resampled: smooth for photos and screenshots, sharp for pixel art.
    var smoothResize = true {
        didSet { renderSoon() }
    }
    var showsPixelGrid = true {
        didSet { renderSoon() }
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
    /// Changing the kind restyles a pending shape of the same family; otherwise the pending one is placed first.
    var shapeKind: ShapeKind = .rectangle {
        didSet {
            if let pending = pendingShape, pending.kind != shapeKind {
                if family(pending.kind) == family(shapeKind), !pending.isBuilding {
                    pendingShape?.kind = shapeKind
                } else {
                    commitPendingShape()
                }
            }
            renderSoon()
        }
    }
    var shapeLineWidth = 3.0 {
        didSet { renderSoon() }
    }
    var shapeHasOutline = true {
        didSet { renderSoon() }
    }
    var shapeHasFill = false {
        didSet { renderSoon() }
    }
    private(set) var pendingShape: PendingShape?
    var gradientMode: GradientMode = .linear
    var symmetry: SymmetryMode = .off {
        didSet { renderSoon() }
    }
    /// The last measurement; it stays on screen until the next one or a tool change.
    private(set) var measurement: Measurement?
    var textStyle = TextStyle() {
        didSet { renderSoon() }
    }
    private(set) var pendingText: PendingText?
    /// Non-nil while Before/After is showing. The view is read-only while it's on.
    var comparison: Comparison? {
        didSet { if oldValue?.layout != comparison?.layout { fitComparison() } else { renderSoon() } }
    }
    /// The image when the document was opened or created.
    @ObservationIgnored let asOpened: PixelBuffer
    /// The image at the last explicit save.
    private(set) var lastSaved: PixelBuffer?
    private(set) var autoRedact: AutoRedactSession?
    var redactionPatterns = Editor.loadRedactionPatterns() {
        didSet {
            Editor.saveRedactionPatterns(redactionPatterns)
            refreshAutoRedactMatches()
        }
    }
    /// The gap between the two images in side-by-side Before/After, in image pixels.
    static let comparisonGap = 40
    /// The effect whose dialog is open, if any.
    private(set) var activeEffect: EffectKind?
    var effectValues: [Double] = []

    @ObservationIgnored var onRender: () -> Void = {}
    @ObservationIgnored private var renderScheduled = false
    @ObservationIgnored var onDocumentChange: (DocumentChange) -> Void = { _ in }
    @ObservationIgnored private var activeStroke: ActiveStroke?
    @ObservationIgnored private var selectionDrag: SelectionDrag?
    @ObservationIgnored private var effectEdit: Edit?
    /// The selection's separate regions, worked out once per dialog; nil applies to the whole layer.
    @ObservationIgnored private var effectRegions: [SelectionMask]?
    @ObservationIgnored private var effectPreviewScheduled = false
    @ObservationIgnored private var shapeDrag: ShapeDrag?
    @ObservationIgnored private var gradientDrag: GradientDrag?
    @ObservationIgnored private var gradientRenderScheduled = false

    private struct GradientDrag {
        let edit: Edit
        let start: Point2D
        var end: Point2D
        /// Right-drag runs from Color 2 to Color 1.
        let reversed: Bool
        let selection: SelectionMask?
    }
    @ObservationIgnored private var shapeRenderCache: (spec: ShapeSpec, pixels: PixelBuffer, origin: IntPoint)?

    private enum ShapeDrag {
        case draw
        case curveLine
        case move(grab: Point2D, original: PendingShape)
        case handle(ShapeHandle, grab: Point2D, original: PendingShape)
    }

    private func family(_ kind: ShapeKind) -> Int {
        kind.isLinear ? 0 : kind.isPointBased ? (kind == .polygon ? 1 : 2) : 3
    }

    private struct ActiveStroke {
        let edit: Edit
        /// One stroke per mirror image when Symmetry is on.
        let strokes: [Stroke]
        var axisLock: AxisLock
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
        asOpened = canvas.flattened()
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
        measurement = nil
        // Moved or pasted pixels are placed, but the outline stays selected so tools like
        // Fill and Gradient (and the Effects) still work inside it.
        if !newTool.isSelectionTool {
            placeFloatingKeepingOutline()
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

    /// Redraws on the next turn of the run loop. Property observers use this instead of `onRender()`:
    /// drawing reads other settings, and reading one while another is mid-change crashes (Swift exclusivity).
    private func renderSoon() {
        guard !renderScheduled else { return }
        renderScheduled = true
        Task { @MainActor [weak self] in
            self?.renderScheduled = false
            self?.onRender()
        }
    }

    /// Ends any drag in progress so menu commands and undo see a settled document.
    /// A pending shape is placed.
    private func finishInteractions() {
        endGradient()
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

    /// Places a floating selection but keeps its outline selected, so effects still apply to just that area.
    private func placeFloatingKeepingOutline() {
        guard let outline = canvas.selection.outline, canvas.selection.floating != nil else { return }
        placeFloatingSelection()
        canvas.selection = .marquee(outline)
        selectionDidChange()
    }

    // MARK: Painting

    func beginStroke(at point: Point2D, secondary: Bool) {
        finishInteractions()
        placeFloatingSelection()
        let layer = canvas.activeLayer
        let color = secondary ? color2 : color1
        let name: String
        let makeStroke: (Edit) -> Stroke
        switch tool {
        case .pencil:
            name = "Pencil"
            makeStroke = { PencilStroke(color: color, layer: layer, edit: $0) }
        case .brush where brushKind == .marker:
            name = "Marker"
            var translucent = color
            translucent.a = UInt8((Double(color.a) * Self.markerOpacity).rounded())
            makeStroke = { [brushDiameter] in RoundBrushStroke(diameter: brushDiameter, color: translucent, layer: layer, edit: $0) }
        case .brush:
            name = "Brush Stroke"
            makeStroke = { [brushDiameter] in RoundBrushStroke(diameter: brushDiameter, color: color, layer: layer, edit: $0) }
        case .eraser:
            // Right-drag is the Color Eraser: only Color 1 pixels become Color 2.
            let effect: StrokeEffect = secondary
                ? .replaceMatching(target: color1, tolerance: 0, with: color2)
                : .replace(canvas.vacatedFill(for: layer, color2: color2))
            name = secondary ? "Color Erase" : "Erase"
            makeStroke = { [eraserSize] in EraserStroke(size: eraserSize, effect: effect, layer: layer, edit: $0) }
        default:
            return
        }
        let edit = history.beginEdit(name, on: canvas)
        let strokes = mirrors.map { _ in makeStroke(edit) }
        activeStroke = ActiveStroke(edit: edit, strokes: strokes, axisLock: AxisLock(start: point))
        moveStrokes(strokes, to: point)
    }

    /// How a point is reflected for each active mirror; the first is always the point itself.
    private var mirrors: [(Point2D) -> Point2D] {
        let width = Double(canvas.size.width), height = Double(canvas.size.height)
        let flipX: (Point2D) -> Point2D = { Point2D(x: width - $0.x, y: $0.y) }
        let flipY: (Point2D) -> Point2D = { Point2D(x: $0.x, y: height - $0.y) }
        switch symmetry {
        case .off: return [{ $0 }]
        case .vertical: return [{ $0 }, flipX]
        case .horizontal: return [{ $0 }, flipY]
        case .both: return [{ $0 }, flipX, flipY, { flipY(flipX($0)) }]
        }
    }

    private func moveStrokes(_ strokes: [Stroke], to point: Point2D) {
        var changed = false
        for (stroke, mirror) in zip(strokes, mirrors) where !stroke.move(to: mirror(point)).isEmpty {
            changed = true
        }
        if changed { onRender() }
    }

    /// With `constrain`, the pencil stays on one horizontal or vertical line from where it started (`AxisLock`).
    func continueStroke(to point: Point2D, constrain: Bool) {
        guard var active = activeStroke else { return }
        var target = point
        if constrain, tool == .pencil {
            target = active.axisLock.constrain(point)
            activeStroke = active
        }
        moveStrokes(active.strokes, to: target)
    }

    func endStroke() {
        guard let edit = activeStroke?.edit else { return }
        activeStroke = nil
        recordingChanges { history.commit(edit) }
    }

    func fill(at point: Point2D, secondary: Bool) {
        finishInteractions()
        placeFloatingKeepingOutline()
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

    // MARK: Gradient

    func beginGradient(at point: Point2D, secondary: Bool) {
        finishInteractions()
        placeFloatingKeepingOutline()
        gradientDrag = GradientDrag(
            edit: history.beginEdit("Gradient", on: canvas),
            start: point,
            end: point,
            reversed: secondary,
            selection: canvas.selection.marquee
        )
    }

    func continueGradient(to point: Point2D) {
        gradientDrag?.end = point
        guard !gradientRenderScheduled else { return }
        gradientRenderScheduled = true
        Task { @MainActor [weak self] in self?.renderGradient() }
    }

    private func renderGradient() {
        gradientRenderScheduled = false
        guard let drag = gradientDrag else { return }
        drag.edit.restoreOriginals()
        Gradients.draw(
            gradientMode,
            from: drag.start,
            to: drag.end,
            startColor: drag.reversed ? color2 : color1,
            endColor: drag.reversed ? color1 : color2,
            onto: canvas.activeLayer,
            selection: drag.selection,
            edit: drag.edit
        )
        onRender()
    }

    func endGradient() {
        guard let drag = gradientDrag else { return }
        if gradientRenderScheduled { renderGradient() }
        gradientDrag = nil
        recordingChanges { history.commit(drag.edit) }
    }

    // MARK: Measure

    func measure(from start: Point2D, to end: Point2D) {
        func pixel(_ point: Point2D) -> IntPoint { IntPoint(x: Int(point.x.rounded(.down)), y: Int(point.y.rounded(.down))) }
        measurement = Measurement(start: pixel(start), end: pixel(end))
        onRender()
    }

    // MARK: Shapes

    /// The pending shape with the current toolbar settings applied.
    var pendingShapeSpec: ShapeSpec? {
        guard let pendingShape else { return nil }
        let outlineColor = pendingShape.swapped ? color2 : color1
        let fillColor = pendingShape.swapped ? color1 : color2
        return ShapeSpec(
            kind: pendingShape.kind,
            start: pendingShape.start,
            end: pendingShape.end,
            points: pendingShape.points,
            rotation: pendingShape.rotation,
            lineWidth: shapeLineWidth,
            outline: shapeHasOutline || pendingShape.kind.isOpen ? outlineColor : nil,
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

    /// The rotate handle sits a fixed on-screen distance above the box's top edge.
    private func rotateHandlePoint(for spec: ShapeSpec) -> Point2D {
        let center = spec.boxCenter
        let top = min(spec.start.y, spec.end.y)
        return spec.rotated(Point2D(x: center.x, y: top - 24 / viewport.zoom))
    }

    /// Where the pending shape's handles are, in image coordinates.
    var pendingShapeHandlePoints: [Point2D] {
        guard let spec = pendingShapeSpec else { return [] }
        if spec.kind.isLinear { return [spec.start, spec.end] }
        if spec.kind.isPointBased { return spec.points }
        return SelectionHandle.allCases.map { spec.rotated($0.point(on: spec.box)) }
    }

    /// The round rotate handle above a box shape.
    var pendingShapeRotateHandle: Point2D? {
        guard let spec = pendingShapeSpec, spec.kind.isBoxShape, pendingShape?.isBuilding == false else { return nil }
        return rotateHandlePoint(for: spec)
    }

    /// Guide lines for the pending shape: the rotate handle's stem, and a curve's control arms.
    var pendingShapeGuides: [(Point2D, Point2D)] {
        guard let spec = pendingShapeSpec else { return [] }
        if spec.kind.isBoxShape {
            return [(spec.rotated(SelectionHandle.top.point(on: spec.box)), rotateHandlePoint(for: spec))]
        }
        if spec.kind == .curve, spec.points.count == 4 {
            return [(spec.points[0], spec.points[1]), (spec.points[3], spec.points[2])]
        }
        return []
    }

    func shapeHandle(atView point: Point2D) -> ShapeHandle? {
        guard let spec = pendingShapeSpec, pendingShape?.isBuilding == false else { return nil }
        func near(_ imagePoint: Point2D) -> Bool {
            let center = viewport.viewPoint(fromImage: imagePoint)
            return abs(center.x - point.x) <= 6 && abs(center.y - point.y) <= 6
        }
        if spec.kind.isLinear {
            if near(spec.end) { return .end }
            if near(spec.start) { return .start }
            return nil
        }
        if spec.kind.isPointBased {
            return spec.points.indices.last { near(spec.points[$0]) }.map(ShapeHandle.vertex)
        }
        if near(rotateHandlePoint(for: spec)) { return .rotate }
        return SelectionHandle.allCases.first { near(spec.rotated($0.point(on: spec.box))) }.map(ShapeHandle.box)
    }

    /// Whether `point` is on the pending shape, so a drag there moves it.
    func pendingShapeContains(_ point: Point2D) -> Bool {
        guard let spec = pendingShapeSpec, pendingShape?.isBuilding == false else { return false }
        if spec.kind.isBoxShape {
            let local = spec.unrotated(point)
            return spec.box.contains(IntPoint(x: Int(local.x.rounded(.down)), y: Int(local.y.rounded(.down))))
        }
        let tolerance = spec.lineWidth / 2 + 4 / viewport.zoom
        if let path = spec.path {
            let cgPoint = CGPoint(x: point.x, y: point.y)
            if spec.kind == .polygon, path.contains(cgPoint) { return true }
            return path.copy(strokingWithWidth: tolerance * 2, lineCap: .round, lineJoin: .round, miterLimit: 10).contains(cgPoint)
        }
        let dx = spec.end.x - spec.start.x, dy = spec.end.y - spec.start.y
        let lengthSquared = max(dx * dx + dy * dy, 1e-9)
        let t = min(1, max(0, ((point.x - spec.start.x) * dx + (point.y - spec.start.y) * dy) / lengthSquared))
        let nearestX = spec.start.x + t * dx, nearestY = spec.start.y + t * dy
        return ((point.x - nearestX) * (point.x - nearestX) + (point.y - nearestY) * (point.y - nearestY)).squareRoot() <= tolerance
    }

    func beginShapeDrag(at point: Point2D, viewPoint: Point2D, secondary: Bool, clickCount: Int) {
        if var pending = pendingShape {
            if pending.isBuilding {
                continueBuilding(&pending, at: point, viewPoint: viewPoint, clickCount: clickCount)
                return
            }
            if let handle = shapeHandle(atView: viewPoint) {
                shapeDrag = .handle(handle, grab: point, original: pending)
                return
            }
            if pendingShapeContains(point) {
                shapeDrag = .move(grab: point, original: pending)
                return
            }
        }
        finishInteractions()
        placeFloatingSelection()
        var shape = PendingShape(kind: shapeKind, start: point, end: point, swapped: secondary)
        switch shapeKind {
        case .polygon:
            shape.points = [point, point]
            shape.isBuilding = true
            shapeDrag = .handle(.vertex(1), grab: point, original: shape)
        case .curve:
            shape.points = [point, point, point, point]
            shape.isBuilding = true
            shapeDrag = .curveLine
        default:
            shapeDrag = .draw
        }
        pendingShape = shape
        onRender()
    }

    /// Polygons: each click adds a corner; clicking the first corner or double-clicking closes it.
    /// Curves: after the line, two more drags bend it.
    private func continueBuilding(_ pending: inout PendingShape, at point: Point2D, viewPoint: Point2D, clickCount: Int) {
        if pending.kind == .polygon {
            let first = viewport.viewPoint(fromImage: pending.points[0])
            let closesOnFirst = abs(first.x - viewPoint.x) <= 8 && abs(first.y - viewPoint.y) <= 8 && pending.points.count >= 3
            if clickCount >= 2 || closesOnFirst {
                finishBuilding()
                return
            }
            pending.points.append(point)
            pendingShape = pending
            shapeDrag = .handle(.vertex(pending.points.count - 1), grab: point, original: pending)
        } else {
            let control = pending.curveStage == 1 ? 1 : 2
            pending.points[control] = point
            pendingShape = pending
            shapeDrag = .handle(.vertex(control), grab: point, original: pending)
        }
        onRender()
    }

    /// Ends point-by-point placement; the shape stays editable until placed.
    func finishBuilding() {
        guard var pending = pendingShape, pending.isBuilding else { return }
        if pending.kind == .polygon, pending.points.count > 2,
           let last = pending.points.last, let previous = pending.points.dropLast().last,
           abs(last.x - previous.x) < 0.5, abs(last.y - previous.y) < 0.5 {
            pending.points.removeLast()
        }
        pending.isBuilding = false
        pendingShape = pending
        onRender()
    }

    func continueShapeDrag(to point: Point2D, shiftDown: Bool) {
        guard var shape = pendingShape, let drag = shapeDrag else { return }
        switch drag {
        case .draw:
            shape.end = point
            if shiftDown, var spec = pendingShapeSpec {
                spec.end = point
                shape.end = spec.constrained().end
            }
        case .curveLine:
            let start = shape.points[0]
            shape.points[3] = point
            shape.points[1] = Point2D(x: start.x + (point.x - start.x) / 3, y: start.y + (point.y - start.y) / 3)
            shape.points[2] = Point2D(x: start.x + (point.x - start.x) * 2 / 3, y: start.y + (point.y - start.y) * 2 / 3)
            shape.start = start
            shape.end = point
        case .move(let grab, let original):
            shape = original
            shape.translate(by: point.x - grab.x, point.y - grab.y)
        case .handle(let handle, let grab, let original):
            let delta = Point2D(x: point.x - grab.x, y: point.y - grab.y)
            switch handle {
            case .start:
                shape.start = Point2D(x: original.start.x + delta.x, y: original.start.y + delta.y)
            case .end:
                shape.end = Point2D(x: original.end.x + delta.x, y: original.end.y + delta.y)
            case .vertex(let index):
                guard original.points.indices.contains(index) else { break }
                shape.points[index] = Point2D(x: original.points[index].x + delta.x, y: original.points[index].y + delta.y)
                if shape.kind == .curve {
                    shape.start = shape.points[0]
                    shape.end = shape.points[3]
                }
            case .rotate:
                let center = Point2D(x: (original.start.x + original.end.x) / 2, y: (original.start.y + original.end.y) / 2)
                let turned = atan2(point.y - center.y, point.x - center.x) - atan2(grab.y - center.y, grab.x - center.x)
                var rotation = original.rotation + turned
                if shiftDown {
                    let step = Double.pi / 12
                    rotation = (rotation / step).rounded() * step
                }
                shape.rotation = rotation
            case .box(let boxHandle):
                resizeBox(&shape, original: original, handle: boxHandle, delta: delta, keepProportions: shiftDown)
            }
        }
        pendingShape = shape
        onRender()
    }

    /// Resizes in the shape's own (rotated) frame, keeping the opposite side fixed on the canvas.
    private func resizeBox(_ shape: inout PendingShape, original: PendingShape, handle: SelectionHandle, delta: Point2D, keepProportions: Bool) {
        let cosine = cos(original.rotation), sine = sin(original.rotation)
        let localDelta = Point2D(x: delta.x * cosine + delta.y * sine, y: -delta.x * sine + delta.y * cosine)
        let box = IntRect(
            enclosingMinX: min(original.start.x, original.end.x), minY: min(original.start.y, original.end.y),
            maxX: max(original.start.x, original.end.x), maxY: max(original.start.y, original.end.y)
        )
        let resized = handle.resize(box, by: localDelta, keepProportions: keepProportions)
        let oldCenter = Point2D(x: Double(box.minX) + Double(box.width) / 2, y: Double(box.minY) + Double(box.height) / 2)
        let shift = Point2D(
            x: Double(resized.minX) + Double(resized.width) / 2 - oldCenter.x,
            y: Double(resized.minY) + Double(resized.height) / 2 - oldCenter.y
        )
        // The box rotates around its own center, so move that center by the rotated shift.
        let newCenter = Point2D(x: oldCenter.x + shift.x * cosine - shift.y * sine, y: oldCenter.y + shift.x * sine + shift.y * cosine)
        shape.start = Point2D(x: newCenter.x - Double(resized.width) / 2, y: newCenter.y - Double(resized.height) / 2)
        shape.end = Point2D(x: newCenter.x + Double(resized.width) / 2, y: newCenter.y + Double(resized.height) / 2)
    }

    func endShapeDrag() {
        defer { shapeDrag = nil }
        guard var shape = pendingShape else { return }
        switch shapeDrag {
        case .draw where abs(shape.end.x - shape.start.x) < 1 && abs(shape.end.y - shape.start.y) < 1:
            pendingShape = nil
            onRender()
        case .curveLine:
            shape.curveStage = 1
            pendingShape = shape
        case .handle(.vertex, _, _) where shape.isBuilding && shape.kind == .curve:
            shape.curveStage += 1
            if shape.curveStage > 2 { shape.isBuilding = false }
            pendingShape = shape
            onRender()
        default:
            break
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
    func beginText(at origin: Point2D, wrapWidth: Double?, minimumHeight: Double = 0) {
        finishInteractions()
        placeFloatingSelection()
        textDragFrame = nil
        pendingText = PendingText(origin: origin, wrapWidth: wrapWidth, minimumHeight: minimumHeight)
        onRender()
    }

    /// The box being dragged out with the Text tool, shown as a frame until the mouse is released.
    private(set) var textDragFrame: (start: Point2D, end: Point2D)?

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

    func updatePendingText(_ string: String) {
        pendingText?.string = string
        onRender()
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
        spec.minimumHeight = text.minimumHeight
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
        placeFloatingKeepingOutline()
        effectValues = kind.parameters.map(\.defaultValue)
        effectEdit = history.beginEdit(kind.title, on: canvas)
        effectRegions = canvas.selection.marquee?.connectedRegions()
        activeEffect = kind
        renderEffectPreview()
    }

    /// Called as the slider moves. Updates are merged, so only the latest value is ever computed
    /// and the slider never waits on a backlog.
    func previewEffect() {
        guard !effectPreviewScheduled else { return }
        effectPreviewScheduled = true
        Task { @MainActor [weak self] in self?.renderEffectPreview() }
    }

    private func renderEffectPreview() {
        effectPreviewScheduled = false
        guard let kind = activeEffect, let edit = effectEdit else { return }
        edit.restoreOriginals()
        let effect = kind.effect(effectValues)
        if let regions = effectRegions {
            Effects.apply(effect, to: canvas.activeLayer, regions: regions, edit: edit)
        } else {
            Effects.apply(effect, to: canvas.activeLayer, selection: nil, edit: edit)
        }
        onRender()
    }

    /// An adjustment with no settings (Invert, Desaturate), applied to the selection or the whole layer.
    func applyAdjustment(_ effect: Effect) {
        finishInteractions()
        placeFloatingKeepingOutline()
        let edit = history.beginEdit(effect.name, on: canvas)
        Effects.apply(effect, to: canvas.activeLayer, selection: canvas.selection.marquee, edit: edit)
        recordingChanges { history.commit(edit) }
        onRender()
    }

    /// Rotates or flips the selection, or the whole image when nothing is selected.
    func apply(_ orientation: Orientation) {
        finishInteractions()
        recordingChanges {
            if canvas.selection.isEmpty {
                ImageActions.transform(orientation, canvas: canvas, history: history, context: selectionContext)
            } else {
                SelectionActions.transformSelection(orientation, canvas: canvas, history: history, context: selectionContext)
            }
        }
        selectionDidChange()
    }

    /// The D key: Color 1 black, Color 2 white.
    func resetColors() {
        color1 = .black
        color2 = .white
    }

    /// Batch redaction with a solid color: every selected region becomes Color 1 in one step (FR-9.4).
    func applySolidFill() {
        finishInteractions()
        placeFloatingKeepingOutline()
        guard let selection = canvas.selection.marquee else { return }
        let edit = history.beginEdit("Solid Fill", on: canvas)
        Effects.apply(.solidFill(color1), to: canvas.activeLayer, selection: selection, edit: edit)
        recordingChanges { history.commit(edit) }
        onRender()
    }

    func applyEffect() {
        if effectPreviewScheduled { renderEffectPreview() }
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

    // MARK: Auto-Redact

    /// Reads the text in the selection (or the whole image) on this Mac and opens the review.
    func beginAutoRedact() {
        finishInteractions()
        placeFloatingKeepingOutline()
        let region = canvas.selection.marquee
        let area = region?.bounds ?? canvas.bounds
        let image = canvas.flattened()
        let cropped = PixelBuffer(width: area.width, height: area.height)
        cropped.setPixels(image.pixels(in: area), in: cropped.bounds)
        autoRedact = AutoRedactSession(region: region)
        onRender()
        do {
            let cgImage = try ImageCodec.makeCGImage(cropped, colorSpace: canvas.colorSpace)
            Task { [weak self] in
                do {
                    let scan = try await TextScan.read(cgImage, offset: IntPoint(x: area.minX, y: area.minY))
                    guard let self, self.autoRedact != nil else { return }
                    self.autoRedact?.scan = scan
                    self.refreshAutoRedactMatches()
                } catch {
                    self?.autoRedact?.failure = error.localizedDescription
                }
            }
        } catch {
            autoRedact?.failure = error.localizedDescription
        }
    }

    private func refreshAutoRedactMatches() {
        guard let session = autoRedact, let scan = session.scan else { return }
        var matches = scan.matches(for: redactionPatterns)
        if let region = session.region {
            matches = matches.filter { match in
                let center = IntPoint(x: match.rect.minX + match.rect.width / 2, y: match.rect.minY + match.rect.height / 2)
                return region.contains(center)
            }
        }
        autoRedact?.matches = matches
        autoRedact?.keptVisible.formIntersection(matches.map(\.id))
        onRender()
    }

    func setRedactionMatch(_ id: UUID, included: Bool) {
        if included { autoRedact?.keptVisible.remove(id) } else { autoRedact?.keptVisible.insert(id) }
        onRender()
    }

    func setRedactionTreatment(_ treatment: RedactionTreatment) {
        autoRedact?.treatment = treatment
    }

    /// Redacts every checked match in one step. Each match is treated on its own, scaled to its text size.
    func applyAutoRedact() {
        guard let session = autoRedact else { return }
        autoRedact = nil
        let selected = session.selectedMatches
        guard var mask = AutoRedact.mask(covering: selected.map(\.rect), in: canvas.bounds) else {
            onRender()
            return
        }
        if let region = session.region, let clipped = SelectionMask.combine(mask, with: region, mode: .intersect) {
            mask = clipped
        }
        let heights = selected.map(\.rect.height).sorted()
        let textHeight = Double(heights[heights.count / 2])
        let strength = max(6, textHeight / 3)
        let effect: Effect = switch session.treatment {
        case .blur: .gaussianBlur(radius: strength)
        case .pixelate: .pixelate(cellSize: Int(strength.rounded()))
        case .solidFill: .solidFill(color1)
        }
        let edit = history.beginEdit("Auto-Redact", on: canvas)
        Effects.apply(effect, to: canvas.activeLayer, selection: mask, edit: edit)
        recordingChanges { history.commit(edit) }
        onRender()
    }

    func cancelAutoRedact() {
        autoRedact = nil
        onRender()
    }

    private static let patternsKey = "AutoRedactPatterns"

    /// Saved patterns, with every built-in present (new built-ins are added, their expressions kept current).
    private static func loadRedactionPatterns() -> [RedactionPattern] {
        let saved = UserDefaults.standard.data(forKey: patternsKey)
            .flatMap { try? JSONDecoder().decode([RedactionPattern].self, from: $0) } ?? []
        let builtIns = RedactionPattern.builtIns.map { builtIn in
            var pattern = builtIn
            pattern.isEnabled = saved.first { $0.id == builtIn.id }?.isEnabled ?? true
            return pattern
        }
        return builtIns + saved.filter { !$0.isBuiltIn }
    }

    private static func saveRedactionPatterns(_ patterns: [RedactionPattern]) {
        if let data = try? JSONEncoder().encode(patterns) {
            UserDefaults.standard.set(data, forKey: patternsKey)
        }
    }

    // MARK: Before/After

    var comparisonBaseline: PixelBuffer? {
        switch comparison?.baseline {
        case .asOpened: asOpened
        case .lastSaved: lastSaved
        case nil: nil
        }
    }

    func toggleComparison() {
        if comparison == nil {
            finishInteractions()
            comparison = Comparison()
        } else {
            comparison = nil
        }
    }

    /// Fits the view to what's being compared: both images side by side, or just the canvas.
    private func fitComparison() {
        if comparison?.layout == .sideBySide {
            let width = asOpened.width + canvas.size.width + Self.comparisonGap
            let height = max(asOpened.height, canvas.size.height)
            updateViewport { $0.fit(IntSize(width: width, height: height), margin: 40) }
        } else {
            zoomToFit()
        }
    }

    /// Records the image as of an explicit save, for "Last Saved".
    func markSaved() {
        lastSaved = canvas.flattened(transparentKey: selectionContext.transparentKey)
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
