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
    case magnifier

    var isSelectionTool: Bool {
        switch self {
        case .rectangleSelect, .ellipseSelect, .lassoSelect, .magicWand: true
        default: false
        }
    }

    /// Tools that change the active layer's pixels.
    var changesPixels: Bool {
        switch self {
        case .pencil, .brush, .eraser, .fill, .gradient, .shape, .text: true
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

/// Which color well a swatch click (and the Alpha slider and Edit Colors…) changes (FR-1.1).
enum ColorWell {
    case color1
    case color2
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
enum EffectKind: CaseIterable {
    case gaussianBlur
    case pixelate
    case sharpen
    case hueSaturation
    case levels
    case curves
    case sepia
    case posterize
    case addNoise
    case motionBlur
    case emboss
    case vignette
    case adjustPhoto
    case dropShadow
    case border
    case spotlight
    case straighten
    case perspective
    case crop
    /// Waiting for a click on one of several subjects (Remove Background, Select Subject).
    case pickSubject

    /// Drop Shadow, Border and Straighten change the canvas's size, so their preview is a real step, redone as
    /// settings change.
    var previewsAsStep: Bool { self == .dropShadow || self == .border || self == .straighten }

    /// Straighten, Perspective Correction and Crop: dragging on the canvas sets them, rather than panning.
    var isCanvasTool: Bool { self == .straighten || self == .perspective || self == .crop || self == .pickSubject }

    /// Changes every layer, not just the active one.
    var appliesToWholeImage: Bool { self == .straighten || self == .perspective || self == .crop }

    struct Parameter {
        let label: String
        let range: ClosedRange<Double>
        let defaultValue: Double
        let unit: String
        /// The slider moves in steps of this size.
        var step: Double = 1
        /// A picker instead of a slider: the value is the chosen option's index.
        var options: [String]? = nil
    }

    var title: String {
        switch self {
        case .gaussianBlur: "Gaussian Blur"
        case .pixelate: "Pixelate"
        case .sharpen: "Sharpen"
        case .hueSaturation: "Hue/Saturation"
        case .levels: "Levels"
        case .curves: "Curves"
        case .sepia: "Sepia"
        case .posterize: "Posterize"
        case .addNoise: "Add Noise"
        case .motionBlur: "Motion Blur"
        case .emboss: "Emboss"
        case .vignette: "Vignette"
        case .adjustPhoto: "Adjust Photo"
        case .dropShadow: "Drop Shadow"
        case .border: "Border"
        case .spotlight: "Spotlight"
        case .straighten: "Straighten"
        case .perspective: "Perspective Correction"
        case .crop: "Crop"
        case .pickSubject: "Pick a Subject"
        }
    }

    var parameters: [Parameter] {
        switch self {
        case .gaussianBlur: [Parameter(label: "Radius", range: 1...100, defaultValue: 8, unit: "px")]
        case .pixelate: [Parameter(label: "Cell size", range: 2...100, defaultValue: 12, unit: "px")]
        case .sharpen: [Parameter(label: "Amount", range: 0...200, defaultValue: 60, unit: "%")]
        case .hueSaturation: [
            Parameter(label: "Hue", range: -180...180, defaultValue: 0, unit: "°"),
            Parameter(label: "Saturation", range: -100...100, defaultValue: 0, unit: ""),
            Parameter(label: "Lightness", range: -100...100, defaultValue: 0, unit: ""),
        ]
        case .levels: [
            Parameter(label: "Black", range: 0...254, defaultValue: 0, unit: ""),
            Parameter(label: "Midtones", range: 0.1...9.99, defaultValue: 1, unit: "", step: 0.01),
            Parameter(label: "White", range: 1...255, defaultValue: 255, unit: ""),
        ]
        case .curves, .adjustPhoto, .perspective, .crop, .pickSubject: []
        case .straighten: [
            Parameter(label: "Angle", range: -45...45, defaultValue: 0, unit: "°", step: 0.1),
            Parameter(label: "Corners", range: 0...1, defaultValue: 0, unit: "", options: ["Crop to Fit", "Grow Canvas"]),
        ]
        case .dropShadow: [
            Parameter(label: "Across", range: -200...200, defaultValue: 12, unit: "px"),
            Parameter(label: "Down", range: -200...200, defaultValue: 12, unit: "px"),
            Parameter(label: "Blur", range: 0...100, defaultValue: 10, unit: "px"),
            Parameter(label: "Opacity", range: 0...100, defaultValue: 50, unit: "%"),
            Parameter(label: "Color", range: 0...1, defaultValue: 0, unit: "", options: ["Black", "Color 1"]),
        ]
        case .border: [
            Parameter(label: "Width", range: 1...200, defaultValue: 8, unit: "px"),
            Parameter(label: "Color", range: 0...3, defaultValue: 0, unit: "", options: ["Color 1", "Color 2", "Black", "White"]),
        ]
        case .spotlight: [
            Parameter(label: "Outside", range: 0...2, defaultValue: 0, unit: "", options: ["Dim", "Blur", "Desaturate"]),
            Parameter(label: "Amount", range: 0...100, defaultValue: 60, unit: "%"),
        ]
        case .sepia: [Parameter(label: "Amount", range: 0...100, defaultValue: 100, unit: "%")]
        case .posterize: [Parameter(label: "Levels", range: 2...32, defaultValue: 4, unit: "")]
        case .addNoise: [
            Parameter(label: "Amount", range: 0...100, defaultValue: 20, unit: "%"),
            Parameter(label: "Noise", range: 0...1, defaultValue: 0, unit: "", options: ["Color", "Monochrome"]),
        ]
        case .motionBlur: [
            Parameter(label: "Angle", range: -180...180, defaultValue: 0, unit: "°"),
            Parameter(label: "Distance", range: 1...200, defaultValue: 20, unit: "px"),
        ]
        case .emboss: [
            Parameter(label: "Angle", range: -180...180, defaultValue: 135, unit: "°"),
            Parameter(label: "Depth", range: 1...10, defaultValue: 3, unit: ""),
        ]
        case .vignette: [
            Parameter(label: "Amount", range: -100...100, defaultValue: 50, unit: ""),
            Parameter(label: "Size", range: 0...100, defaultValue: 50, unit: ""),
        ]
        }
    }

    func effect(_ values: [Double], curves: Curves = .identity, photo: PhotoEdit = PhotoEdit()) -> Effect {
        func value(_ index: Int) -> Double { values.indices.contains(index) ? values[index] : parameters[index].defaultValue }
        return switch self {
        case .gaussianBlur: .gaussianBlur(radius: value(0))
        case .pixelate: .pixelate(cellSize: Int(value(0).rounded()))
        case .sharpen: .sharpen(amount: value(0))
        case .hueSaturation: .hueSaturation(hue: value(0), saturation: value(1), lightness: value(2))
        case .levels: .levels(Levels(black: value(0), white: max(value(2), value(0) + 1), gamma: value(1)))
        case .curves: .curves(curves)
        case .sepia: .sepia(amount: value(0))
        case .posterize: .posterize(levels: Int(value(0).rounded()))
        case .addNoise: .addNoise(amount: value(0), monochrome: value(1) >= 0.5)
        case .motionBlur: .motionBlur(angle: value(0), distance: value(1))
        case .emboss: .emboss(angle: value(0), depth: value(1))
        case .vignette: .vignette(amount: value(0), size: value(1))
        case .adjustPhoto: .photo(photo)
        case .spotlight:
            switch Int(value(0).rounded()) {
            case 1: .gaussianBlur(radius: max(1, value(1) / 2))
            case 2: .hueSaturation(hue: 0, saturation: -value(1), lightness: 0)
            default: .brightnessContrast(brightness: -value(1) * 0.8, contrast: 0)
            }
        // Done by Decorations and ImageActions, not as an effect (see Editor.renderEffectPreview).
        case .dropShadow, .border, .straighten, .perspective, .crop, .pickSubject: .invert
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
struct TextStyle: Equatable, Codable {
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

/// What a press on the open text box grabbed: a handle resizes it, the border moves it (FR-6.1).
enum TextBoxGrab: Equatable {
    case handle(SelectionHandle)
    case border
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

    let canvas: Canvas
    @ObservationIgnored let history: History

    private(set) var tool: Tool = .pencil
    var brush: Brush = .round
    /// Brushes respond to trackpad and pen pressure (FR-4.2). Off, every brush draws at full size.
    var usesPressure = true
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
    /// Nil is no outline. Open shapes (lines, arrows, curves) always have one.
    var shapeOutline: PaintStyle? = .solid {
        didSet { renderSoon() }
    }
    /// Nil is no fill.
    var shapeFill: PaintStyle? {
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
    /// The document at the last explicit save, as it was written.
    private(set) var lastSavedSnapshot: SaveSnapshot?
    @ObservationIgnored private var lastSavedImage: PixelBuffer?
    var hasLastSaved: Bool { lastSavedSnapshot != nil }
    /// The image at the last explicit save, flattened the first time Before/After needs it.
    var lastSaved: PixelBuffer? {
        if lastSavedImage == nil, let snapshot = lastSavedSnapshot {
            lastSavedImage = snapshot.canvas.flattened(transparentKey: snapshot.transparentKey)
        }
        return lastSavedImage
    }
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
    /// Curves' points while its dialog is open.
    var effectCurves = Curves.identity
    /// The Adjust Photo panel's settings while it's open, and which sliders Auto last set.
    private(set) var photoEdit = PhotoEdit()
    private(set) var photoAutoMoved: Set<PhotoAdjustments.Slider> = []
    /// What Levels shows behind its sliders: the pixels it applies to, before any change.
    private(set) var effectHistogram: Histogram?
    /// The selection's separate regions, worked out once per dialog; nil applies to the whole layer.
    @ObservationIgnored private var effectRegions: [SelectionMask]?
    @ObservationIgnored private var effectPreviewScheduled = false
    /// The active layer's pixels as they were when the effect opened. Previews are worked out from this
    /// copy in the background, so large images don't hold up the sliders (NFR-6).
    @ObservationIgnored private var effectSource: PixelBuffer?
    /// What the canvas shows now, so Apply knows whether the newest settings still need working out.
    @ObservationIgnored private var shownEffect: Effect?
    /// Bumped when the effect closes, so a background preview finishing late is ignored.
    @ObservationIgnored private var previewGeneration = 0
    @ObservationIgnored private var previewRunning = false
    @ObservationIgnored private var previewWanted = false
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
    /// Textured shapes take too long to draw on every drag event, so they're drawn in the background;
    /// these track the drawing under way and the newest spec waiting for it.
    @ObservationIgnored private var shapeRenderInFlight = false
    @ObservationIgnored private var shapeRenderWanted: ShapeSpec?
    /// Bumped when a shape is placed or cancelled, so a late background result for it is dropped.
    @ObservationIgnored private var shapeRenderGeneration = 0

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
        /// The lightest and firmest pressure seen, logged when the stroke ends to tune pressure response.
        var pressureRange: ClosedRange<Double>
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
        history.makeThumbnail = { $0.thumbnail(maxSide: 64) }
        rememberLayersAsSaved(sharingSingleLayerWith: asOpened)
    }

    // MARK: History panel (FR-13.2)

    var historySteps: [(name: String, thumbnail: Thumbnail?, isUndone: Bool)] {
        _ = layersRevision
        return history.steps
    }

    /// Undoes or redoes until exactly `count` steps are done, for a click in the History panel.
    func jump(toStep count: Int) {
        finishInteractions()
        while history.undoCount > count, history.canUndo { undo() }
        while history.undoCount < count, history.canRedo { redo() }
    }

    // MARK: Canvas (FR-1.4)

    var isCanvasPropertiesOpen = false
    var showsRulers = false
    var showsStatusBar = true
    var showsHistoryPanel = false
    var showsClipboardPanel = false

    var hasTransparentBackground: Bool {
        _ = layersRevision
        return canvas.hasTransparentBackground
    }

    /// Canvas Properties: the new size and the transparent-background setting, each its own step.
    func applyCanvasProperties(size: IntSize, transparentBackground: Bool) {
        isCanvasPropertiesOpen = false
        finishInteractions()
        recordingChanges {
            ImageActions.setTransparentBackground(transparentBackground, canvas: canvas, history: history)
            ImageActions.resizeCanvas(to: size, canvas: canvas, history: history, context: selectionContext)
        }
        selectionDidChange()
    }

    /// The canvas's edge handles: new area on the right and bottom (FR-1.4).
    func resizeCanvas(to size: IntSize) {
        finishInteractions()
        recordingChanges { ImageActions.resizeCanvas(to: size, canvas: canvas, history: history, context: selectionContext) }
        selectionDidChange()
    }

    /// While a canvas edge handle is dragged: the size it would become, outlined on the canvas.
    var canvasResizePreview: IntSize? {
        didSet { renderSoon() }
    }

    /// Each pixel layer as of the last explicit save (or as opened), for Revert Layer (FR-8.3).
    @ObservationIgnored private var savedLayers: [LayerID: PixelBuffer] = [:]
    @ObservationIgnored private var savedSize: IntSize = .init(width: 0, height: 0)

    /// A lone opaque layer looks exactly like the flattened image, so it can share that copy.
    private func rememberLayersAsSaved(sharingSingleLayerWith flattened: PixelBuffer? = nil) {
        savedSize = canvas.size
        let pixelLayers = canvas.layers.filter { $0.adjustment == nil }
        if let flattened, canvas.layers.count == 1, let only = pixelLayers.first, only.opacity >= 1, only.isVisible {
            savedLayers = [only.id: flattened]
        } else {
            savedLayers = Dictionary(uniqueKeysWithValues: pixelLayers.map { ($0.id, $0.buffer.copy()) })
        }
    }

    var canRevertLayer: Bool {
        let layer = canvas.activeLayer
        return layer.adjustment == nil && !layer.isLocked && canvas.size == savedSize && savedLayers[layer.id] != nil
    }

    /// Revert Layer: the active layer's pixels go back to how they were at the last save, as one step.
    func revertLayer() {
        guard canRevertLayer, let saved = savedLayers[canvas.activeLayer.id] else {
            onRefused()
            return
        }
        finishInteractions()
        placeFloatingKeepingOutline()
        let layer = canvas.activeLayer
        let edit = history.beginEdit("Revert Layer", on: canvas)
        edit.willModify(layer.buffer.bounds, in: layer)
        layer.buffer.setPixels(saved.pixels(in: saved.bounds), in: layer.buffer.bounds)
        recordingChanges { history.commit(edit) }
        onRender()
    }

    /// The step Undo on Active Layer would take back, for the menu; nil when it isn't available.
    var undoOnActiveLayerName: String? {
        history.undoOnLayerActionName(canvas.activeLayer.id, canvas: canvas)
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

    /// What the toolbar's Size control edits (FR-1.1); nil for tools without a size.
    var toolSize: Int? {
        get {
            switch tool {
            case .brush: Int(brushDiameter.rounded())
            case .shape: Int(shapeLineWidth.rounded())
            case .eraser: eraserSize
            default: nil
            }
        }
        set {
            guard let size = newValue else { return }
            switch tool {
            case .brush: brushDiameter = Double(min(50, max(1, size)))
            case .shape: shapeLineWidth = Double(min(50, max(1, size)))
            case .eraser: eraserSize = min(100, max(1, size))
            default: break
            }
        }
    }

    /// The five sizes the Size control offers for the tool in use.
    var toolSizePresets: [Int] {
        tool == .eraser ? [4, 6, 8, 10, 20] : [1, 2, 3, 4, 5]
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
        cancelOrEndSelectionDrag()
        if activeEffect != nil { cancelEffect() }
        finishLayerSettings()
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

    func beginStroke(at point: Point2D, secondary: Bool, pressure: Double = 1) {
        guard !refusedBecauseLocked() else { return }
        finishInteractions()
        placeFloatingSelection()
        let layer = canvas.activeLayer
        let color = secondary ? color2 : color1
        let name: String
        // The flag says whether this copy is mirrored across one axis only, which turns a `/` nib into `\`.
        let makeStroke: (Edit, Bool) -> Stroke
        switch tool {
        case .pencil:
            name = "Pencil"
            makeStroke = { edit, _ in PencilStroke(color: color, layer: layer, edit: edit) }
        case .brush:
            name = brush == .round ? "Brush Stroke" : brush.name
            makeStroke = { [brush, brushDiameter] edit, mirrored in
                (mirrored ? brush.mirrored : brush).makeStroke(diameter: brushDiameter, color: color, layer: layer, edit: edit)
            }
        case .eraser:
            // Right-drag is the Color Eraser: only Color 1 pixels become Color 2.
            let effect: StrokeEffect = secondary
                ? .replaceMatching(target: color1, tolerance: 0, with: color2)
                : .replace(canvas.vacatedFill(for: layer, color2: color2))
            name = secondary ? "Color Erase" : "Erase"
            makeStroke = { [eraserSize] edit, _ in EraserStroke(size: eraserSize, effect: effect, layer: layer, edit: edit) }
        default:
            return
        }
        let edit = history.beginEdit(name, on: canvas)
        let mirroredOnce: [Bool] = switch symmetry {
        case .off: [false]
        case .vertical, .horizontal: [false, true]
        case .both: [false, true, true, false]
        }
        let strokes = mirroredOnce.map { makeStroke(edit, $0) }
        activeStroke = ActiveStroke(edit: edit, strokes: strokes, axisLock: AxisLock(start: point), pressureRange: pressure...pressure)
        moveStrokes(strokes, to: point, pressure: pressure)
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

    private func moveStrokes(_ strokes: [Stroke], to point: Point2D, pressure: Double) {
        var changed = false
        for (stroke, mirror) in zip(strokes, mirrors) where !stroke.move(to: mirror(point), pressure: pressure).isEmpty {
            changed = true
        }
        if changed { onRender() }
    }

    /// Whether the stroke under way should keep being fed `holdStroke()` while the pointer is still (the airbrush).
    var strokeSpraysWhileHeld: Bool {
        activeStroke != nil && tool == .brush && brush == .airbrush
    }

    func holdStroke() {
        guard let strokes = activeStroke?.strokes else { return }
        var changed = false
        for stroke in strokes where !stroke.hold().isEmpty { changed = true }
        if changed { onRender() }
    }

    /// With `constrain`, the pencil stays on one horizontal or vertical line from where it started (`AxisLock`).
    func continueStroke(to point: Point2D, constrain: Bool, pressure: Double = 1) {
        guard var active = activeStroke else { return }
        var target = point
        if constrain, tool == .pencil {
            target = active.axisLock.constrain(point)
        }
        active.pressureRange = min(active.pressureRange.lowerBound, pressure)...max(active.pressureRange.upperBound, pressure)
        activeStroke = active
        moveStrokes(active.strokes, to: target, pressure: pressure)
    }

    /// The size of the eraser stroke under way. Size changes apply from the next stroke, so the outline shows this one.
    var strokeEraserSize: Int? {
        (activeStroke?.strokes.first as? EraserStroke)?.size
    }

    func endStroke() {
        guard let active = activeStroke else { return }
        activeStroke = nil
        if active.strokes.contains(where: { !$0.finish().isEmpty }) { onRender() }
        if tool == .brush {
            let range = active.pressureRange
            Diagnostics.logger.notice("Brush pressure \(range.lowerBound, format: .fixed(precision: 2))–\(range.upperBound, format: .fixed(precision: 2))")
        }
        recordingChanges { history.commit(active.edit) }
    }

    func fill(at point: Point2D, secondary: Bool) {
        guard !refusedBecauseLocked() else { return }
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
        guard !refusedBecauseLocked() else { return }
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
            outline: shapeOutline != nil || pendingShape.kind.isOpen ? outlineColor : nil,
            fill: shapeFill != nil ? fillColor : nil,
            outlineStyle: shapeOutline ?? .solid,
            fillStyle: shapeFill ?? .solid
        )
    }

    /// The pending shape drawn into pixels, cached until it changes.
    /// For display. A textured shape may briefly show its previous frame while the new one draws in the background.
    func renderedPendingShape() -> (pixels: PixelBuffer, origin: IntPoint)? {
        guard let spec = pendingShapeSpec else { return nil }
        if let cache = shapeRenderCache, cache.spec == spec { return (cache.pixels, cache.origin) }
        if spec.outlineStyle == .solid, spec.fillStyle == .solid {
            return renderShapeNow(spec)
        }
        renderShapeInBackground(spec)
        return shapeRenderCache.map { ($0.pixels, $0.origin) }
    }

    private func renderShapeNow(_ spec: ShapeSpec) -> (pixels: PixelBuffer, origin: IntPoint)? {
        guard let rendered = ShapeRenderer.render(spec, colorSpace: canvas.colorSpace, clippedTo: canvas.bounds) else {
            shapeRenderCache = nil
            return nil
        }
        shapeRenderCache = (spec, rendered.pixels, rendered.origin)
        return rendered
    }

    private func renderShapeInBackground(_ spec: ShapeSpec) {
        guard !shapeRenderInFlight else {
            shapeRenderWanted = spec
            return
        }
        shapeRenderInFlight = true
        let generation = shapeRenderGeneration
        let colorSpace = canvas.colorSpace, bounds = canvas.bounds
        Task { [weak self] in
            let rendered = await Task.detached(priority: .userInitiated) {
                ShapeRenderer.render(spec, colorSpace: colorSpace, clippedTo: bounds).map { RenderedShape(pixels: $0.pixels, origin: $0.origin) }
            }.value
            guard let self else { return }
            self.shapeRenderInFlight = false
            guard generation == self.shapeRenderGeneration else { return }
            self.shapeRenderCache = rendered.map { (spec, $0.pixels, $0.origin) }
            if let wanted = self.shapeRenderWanted {
                self.shapeRenderWanted = nil
                if wanted != spec { self.renderShapeInBackground(wanted) }
            }
            self.renderSoon()
        }
    }

    private func forgetShapeRender() {
        shapeRenderCache = nil
        shapeRenderWanted = nil
        shapeRenderGeneration += 1
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
        if pendingShape == nil, refusedBecauseLocked() { return }
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
        // Placing always uses the finished drawing, never a frame still catching up.
        let rendered = shapeRenderCache.flatMap { $0.spec == spec ? ($0.pixels, $0.origin) : nil } ?? renderShapeNow(spec)
        pendingShape = nil
        forgetShapeRender()
        if let rendered {
            let edit = history.beginEdit(spec.kind.name, on: canvas)
            Compositing.draw(rendered.pixels, at: rendered.origin, onto: canvas.activeLayer, edit: edit)
            recordingChanges { history.commit(edit) }
        }
        onRender()
    }

    func cancelPendingShape() {
        pendingShape = nil
        forgetShapeRender()
        shapeDrag = nil
        onRender()
    }

    // MARK: Text

    /// Opens a text box with its top-left at `origin`. Any open box is placed first.
    func beginText(at origin: Point2D, wrapWidth: Double?, minimumHeight: Double = 0) {
        guard !refusedBecauseLocked() else { return }
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

    @ObservationIgnored private var textBoxDrag: (grab: TextBoxGrab, text: PendingText, frame: IntRect, start: Point2D)?

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
        return nearestHandle(SelectionHandle.allCases.map { ($0, $0.point(on: rect)) }, to: point)
    }

    /// The handle closest to a view point, if one is within reach. On a tiny box the handles overlap,
    /// and taking the first one in range would always pick a left or top one.
    private func nearestHandle(_ handles: [(handle: SelectionHandle, point: Point2D)], to point: Point2D) -> SelectionHandle? {
        handles
            .map { handle, center -> (SelectionHandle, Double) in
                let view = viewport.viewPoint(fromImage: center)
                return (handle, max(abs(view.x - point.x), abs(view.y - point.y)))
            }
            .filter { $0.1 <= 6 }
            .min { $0.1 < $1.1 }?
            .0
    }

    func beginResize(_ handle: SelectionHandle, at point: Point2D) {
        guard !refusedBecauseLocked() else { return }
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
            // Moving selected pixels changes the layer; drawing a new outline doesn't.
            guard !refusedBecauseLocked() else { return }
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

    /// Interrupted mid-drag (say, by a tool key): a marquee or lasso still being drawn is dropped and the
    /// earlier selection stays, while a move or resize keeps what's already been done.
    private func cancelOrEndSelectionDrag() {
        switch selectionDrag {
        case .marquee, .lasso:
            selectionDrag = nil
            marqueePreview = nil
            selectionDidChange()
        case .move, .resize:
            endSelectionDrag(at: nil)
        case nil:
            break
        }
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
        if history.revision != revision {
            onDocumentChange(.done)
            layersRevision += 1
        }
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
        guard !refusedBecauseLocked() else { return }
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
        guard !refusedBecauseLocked() else { return }
        performSelectionCommand {
            SelectionActions.nudge(dx: dx, dy: dy, canvas: canvas, history: history, context: selectionContext)
        }
    }

    /// The selected pixels, or nil when nothing is selected.
    /// Copy Merged: the selection as all visible layers show it together.
    func selectedMergedPixels() -> PixelBuffer? {
        finishInteractions()
        return SelectionActions.selectedPixels(canvas: canvas, context: selectionContext, merged: true)
    }

    func selectedPixels() -> PixelBuffer? {
        finishInteractions()
        return SelectionActions.selectedPixels(canvas: canvas, context: selectionContext)
    }

    /// Pastes as a floating selection at the top-left of the visible part of the canvas.
    /// Pastes as a floating selection at the top-left of the visible area (FR-10.1), or at `origin`.
    func paste(_ image: PixelBuffer, at origin: IntPoint? = nil) {
        guard !refusedBecauseLocked() else { return }
        let visibleTopLeft = viewport.imagePoint(fromView: .zero)
        let origin = origin ?? IntPoint(
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
        // Whole-image tools apply to every layer, locked or not (§23), and picking a subject was already
        // checked by findSubject, since selecting one doesn't change pixels (review B, findings 4 and 5).
        guard kind.appliesToWholeImage || kind == .pickSubject || !refusedBecauseLocked() else { return }
        finishInteractions()
        placeFloatingKeepingOutline()
        // Spotlight changes what's around the selection, so it needs one.
        if kind == .spotlight, canvas.selection.marquee == nil { return onRefused() }
        effectValues = kind.parameters.map(\.defaultValue)
        effectCurves = .identity
        photoEdit = PhotoEdit()
        photoAutoMoved = []
        if kind == .adjustPhoto { isSidebarOpen = true }
        effectHistogram = kind == .levels ? Histogram(canvas.activeLayer.buffer, selection: canvas.selection.marquee) : nil
        decorationPreviewed = false
        if kind == .crop {
            cropShape = .free
            cropPixelSize = nil
            cropRect = canvas.selection.bounds?.intersection(canvas.bounds) ?? canvas.bounds
            if cropRect.isEmpty { cropRect = canvas.bounds }
        }
        if kind == .perspective {
            // Inset a little, so the corners are easy to find and grab.
            let w = Double(canvas.size.width), h = Double(canvas.size.height), inset = 0.06
            perspectiveCorners = [Point2D(x: w * inset, y: h * inset), Point2D(x: w * (1 - inset), y: h * inset),
                                  Point2D(x: w * (1 - inset), y: h * (1 - inset)), Point2D(x: w * inset, y: h * (1 - inset))]
        }
        effectEdit = kind.previewsAsStep || kind.isCanvasTool ? nil : history.beginEdit(kind.title, on: canvas)
        if kind == .spotlight {
            effectRegions = canvas.selection.marquee?.inverted(in: canvas.bounds).map { [$0] } ?? []
        } else {
            effectRegions = canvas.selection.marquee?.connectedRegions()
        }
        activeEffect = kind
        shownEffect = nil
        effectSource = effectEdit == nil ? nil : canvas.activeLayer.buffer.copy()
        if effectSource != nil { previewEffect() } else { renderEffectPreview() }
    }

    /// Whether a Drop Shadow, Border or Straighten preview step is in the history right now.
    @ObservationIgnored private var decorationPreviewed = false

    // MARK: Straighten, Perspective Correction and Crop (FR-9.5)

    /// Straighten: a line being drawn along something that should be level.
    private(set) var straightenLine: (start: Point2D, end: Point2D)?
    /// Perspective Correction: top left, top right, bottom right, bottom left, in image coordinates.
    private(set) var perspectiveCorners: [Point2D] = []
    /// Crop: the box, its shape and an exact output size from a pixel-size preset.
    var cropRect = IntRect.zero
    var cropShape = CropShape.free { didSet { renderSoon() } }
    var cropPixelSize: IntSize? { didSet { renderSoon() } }
    private(set) var isDraggingCrop = false
    @ObservationIgnored private var toolDrag: (start: Point2D, handle: SelectionHandle?, rect: IntRect, corner: Int?)?

    /// Width ÷ height the crop box keeps, or nil for any shape.
    var cropAspect: Double? {
        if let size = cropPixelSize { return Double(size.width) / Double(size.height) }
        return cropShape.aspect(original: canvas.size)
    }

    /// Changing the shape or size preset fits the largest box of that shape in the image.
    func setCrop(shape: CropShape, pixelSize: IntSize?) {
        cropShape = shape
        cropPixelSize = pixelSize
        if let aspect = cropAspect {
            cropRect = CropBox.fitted(aspect: aspect, in: canvas.bounds)
        }
        renderSoon()
    }

    /// The handles to draw for the open canvas tool, in image coordinates.
    var canvasToolHandles: [Point2D] {
        switch activeEffect {
        case .crop: SelectionHandle.allCases.map { $0.point(on: cropRect) }
        case .perspective: perspectiveCorners
        default: []
        }
    }

    /// Guide lines for the open canvas tool: the crop frame and its thirds while dragging, the perspective
    /// outline, Straighten's grid and the line being drawn.
    var canvasToolLines: [(from: Point2D, to: Point2D, color: SIMD4<Float>)] {
        var lines: [(from: Point2D, to: Point2D, color: SIMD4<Float>)] = []
        let white = SIMD4<Float>(1, 1, 1, 0.95), faint = SIMD4<Float>(1, 1, 1, 0.55), accent = SIMD4<Float>(1, 0.35, 0.2, 1)
        switch activeEffect {
        case .crop:
            let r = cropRect
            let corners = [Point2D(x: Double(r.minX), y: Double(r.minY)), Point2D(x: Double(r.maxX), y: Double(r.minY)),
                           Point2D(x: Double(r.maxX), y: Double(r.maxY)), Point2D(x: Double(r.minX), y: Double(r.maxY))]
            for index in 0..<4 { lines.append((corners[index], corners[(index + 1) % 4], white)) }
            if isDraggingCrop {
                for third in [1.0, 2.0] {
                    let x = Double(r.minX) + Double(r.width) * third / 3, y = Double(r.minY) + Double(r.height) * third / 3
                    lines.append((Point2D(x: x, y: Double(r.minY)), Point2D(x: x, y: Double(r.maxY)), faint))
                    lines.append((Point2D(x: Double(r.minX), y: y), Point2D(x: Double(r.maxX), y: y), faint))
                }
            }
        case .perspective where perspectiveCorners.count == 4:
            for index in 0..<4 { lines.append((perspectiveCorners[index], perspectiveCorners[(index + 1) % 4], accent)) }
        case .straighten:
            let width = Double(canvas.size.width), height = Double(canvas.size.height)
            for step in 1..<8 {
                let x = width * Double(step) / 8, y = height * Double(step) / 8
                lines.append((Point2D(x: x, y: 0), Point2D(x: x, y: height), faint))
                lines.append((Point2D(x: 0, y: y), Point2D(x: width, y: y), faint))
            }
            if let line = straightenLine { lines.append((line.start, line.end, accent)) }
        default:
            break
        }
        return lines
    }

    /// A drag on the canvas while Straighten, Perspective Correction or Crop is open.
    func beginCanvasToolDrag(at point: Point2D, viewPoint: Point2D) {
        switch activeEffect {
        case .pickSubject:
            pickSubject(at: point)
            return
        case .straighten:
            straightenLine = (point, point)
        case .perspective:
            let nearest = perspectiveCorners.indices.min { a, b in
                distance(viewport.viewPoint(fromImage: perspectiveCorners[a]), viewPoint) < distance(viewport.viewPoint(fromImage: perspectiveCorners[b]), viewPoint)
            }
            guard let nearest, distance(viewport.viewPoint(fromImage: perspectiveCorners[nearest]), viewPoint) <= 16 else { return }
            toolDrag = (point, nil, .zero, nearest)
        case .crop:
            let handle = nearestHandle(SelectionHandle.allCases.map { ($0, $0.point(on: cropRect)) }, to: viewPoint)
            let inside = point.x >= Double(cropRect.minX) && point.x < Double(cropRect.maxX) && point.y >= Double(cropRect.minY) && point.y < Double(cropRect.maxY)
            if handle == nil && !inside {
                // Outside the box: draw a new one from here.
                let start = IntPoint(x: Int(point.x.rounded()), y: Int(point.y.rounded()))
                cropRect = CropBox.clamped(IntRect(x: start.x, y: start.y, width: 1, height: 1), to: canvas.bounds, aspect: nil)
                toolDrag = (point, .bottomRight, cropRect, nil)
            } else {
                toolDrag = (point, handle, cropRect, nil)
            }
            isDraggingCrop = true
        default:
            break
        }
        renderSoon()
    }

    func continueCanvasToolDrag(to point: Point2D) {
        switch activeEffect {
        case .straighten:
            if let line = straightenLine { straightenLine = (line.start, point) }
        case .perspective:
            guard let drag = toolDrag, let corner = drag.corner else { return }
            perspectiveCorners[corner] = Point2D(x: min(max(point.x, 0), Double(canvas.size.width)), y: min(max(point.y, 0), Double(canvas.size.height)))
        case .crop:
            guard let drag = toolDrag else { return }
            let delta = Point2D(x: point.x - drag.start.x, y: point.y - drag.start.y)
            if let handle = drag.handle {
                var start = drag.rect
                // A new box drawn with a preset shape starts at that shape so it keeps it.
                if let aspect = cropAspect, start.width <= 1 || start.height <= 1 {
                    start = IntRect(x: start.minX, y: start.minY, width: max(1, Int(aspect.rounded())), height: max(1, Int((1 / aspect).rounded())))
                }
                let resized = handle.resize(start, by: delta, keepProportions: cropAspect != nil)
                cropRect = CropBox.clamped(resized, to: canvas.bounds, aspect: cropAspect)
            } else {
                cropRect = CropBox.moved(drag.rect, by: IntPoint(x: Int(delta.x.rounded()), y: Int(delta.y.rounded())), within: canvas.bounds)
            }
        default:
            break
        }
        renderSoon()
    }

    func endCanvasToolDrag() {
        if activeEffect == .straighten, let line = straightenLine {
            straightenLine = nil
            // The line was drawn on the turned preview, so its tilt adds to the turn already there.
            if distance(viewport.viewPoint(fromImage: line.start), viewport.viewPoint(fromImage: line.end)) > 8,
               effectValues.indices.contains(0) {
                let turned = effectValues[0] + Warp.straighteningAngle(from: line.start, to: line.end)
                effectValues[0] = (min(max(turned, -45), 45) * 10).rounded() / 10
            }
        }
        toolDrag = nil
        isDraggingCrop = false
        renderSoon()
    }

    private func distance(_ a: Point2D, _ b: Point2D) -> Double { hypot(a.x - b.x, a.y - b.y) }

    // MARK: Subjects (FR-9.5)

    enum SubjectAction {
        case removeBackground, liftToNewLayer, select
    }

    /// Whether Vision is looking for the subject now.
    private(set) var isFindingSubject = false
    /// A message to show, such as "No subject found".
    var subjectMessage: String?
    /// With several subjects: what was found and what to do with the one you click.
    @ObservationIgnored private var subjectPick: (scan: SubjectScan, action: SubjectAction, layer: LayerID)?

    /// Finds the subject in the active layer with Vision, on this Mac, then acts on it. With several
    /// subjects it waits for a click on one (Return takes them all).
    func findSubject(_ action: SubjectAction) {
        guard !isFindingSubject, activeEffect == nil else { return }
        if action != .select, refusedBecauseLocked() { return }
        finishInteractions()
        placeFloatingKeepingOutline()
        let layer = canvas.activeLayer
        guard layer.adjustment == nil, let image = try? ImageCodec.makeCGImage(layer.buffer, colorSpace: canvas.colorSpace) else { return onRefused() }
        let revision = history.revision
        isFindingSubject = true
        Task { @MainActor [weak self] in
            let scan = try? await SubjectScan.find(in: image)
            guard let self else { return }
            self.isFindingSubject = false
            // Something changed the image meanwhile (a step, an undo, or a stroke still being drawn), so the
            // masks may no longer fit it (review B, finding 2).
            guard self.history.revision == revision, self.activeStroke == nil, self.gradientDrag == nil,
                  self.canvas.activeLayer.id == layer.id, self.activeEffect == nil else {
                self.subjectMessage = "The image changed while Colorbee was looking for the subject. Try again."
                return
            }
            guard let scan, !scan.isEmpty else {
                self.subjectMessage = "No subject found. Remove Background and Select Subject work on photos of people, pets and objects, not on screenshots or text."
                return
            }
            if scan.masks.count == 1 {
                self.perform(action, mask: scan.mask())
            } else {
                self.subjectPick = (scan, action, layer.id)
                self.beginEffect(.pickSubject)
            }
        }
    }

    private func perform(_ action: SubjectAction, mask: [UInt8]) {
        recordingChanges {
            switch action {
            case .removeBackground: SubjectActions.removeBackground(mask, canvas: canvas, history: history, context: selectionContext)
            case .liftToNewLayer: SubjectActions.liftToNewLayer(mask, canvas: canvas, history: history, context: selectionContext)
            case .select: SubjectActions.select(mask, canvas: canvas, history: history, context: selectionContext)
            }
        }
        selectionDidChange()
        onRender()
    }

    /// A click while picking: that subject, or a beep on the background.
    private func pickSubject(at point: Point2D) {
        guard let pick = subjectPick, let index = pick.scan.subject(at: IntPoint(x: Int(point.x), y: Int(point.y))) else { return onRefused() }
        subjectPick = nil
        activeEffect = nil
        perform(pick.action, mask: pick.scan.mask(for: [index]))
    }

    /// Drop Shadow and Border: takes back the last preview step and draws the new one.
    private func renderDecorationPreview(_ kind: EffectKind) {
        if decorationPreviewed {
            history.undo(on: canvas)
            // The undone preview was never applied, so it mustn't be redoable, even if this tick draws nothing
            // (review A, finding 5).
            history.forgetRedo()
            decorationPreviewed = false
        }
        let colors = [color1, color2, .black, .white]
        let values = effectValues
        func value(_ index: Int) -> Double { values.indices.contains(index) ? values[index] : kind.parameters[index].defaultValue }
        let drawn = switch kind {
        case .straighten:
            ImageActions.straighten(angle: value(0), cropToFit: value(1) < 0.5, canvas: canvas, history: history, context: selectionContext)
        case .dropShadow:
            Decorations.dropShadow(DropShadow(offsetX: value(0), offsetY: value(1), blur: value(2),
                                              color: value(4) >= 0.5 ? color1 : .black, opacity: value(3)),
                                   canvas: canvas, history: history, context: selectionContext)
        default:
            Decorations.border(Border(width: value(0), color: colors[min(max(Int(value(1).rounded()), 0), 3)]),
                               canvas: canvas, history: history, context: selectionContext)
        }
        decorationPreviewed = drawn
        if canvas.size != canvasSize { canvasDidResize() }
        selectionDidChange()
        onRender()
    }

    /// Called as the slider moves. Updates are merged, so only the latest value is ever computed
    /// and the slider never waits on a backlog.
    func previewEffect() {
        if effectSource != nil, effectEdit != nil {
            // One background render at a time; settings that change meanwhile are rendered next.
            if previewRunning { previewWanted = true } else { startBackgroundPreview() }
            return
        }
        guard !effectPreviewScheduled else { return }
        effectPreviewScheduled = true
        Task { @MainActor [weak self] in self?.renderEffectPreview() }
    }

    /// Works out the current settings from the original pixels off the main thread, then shows them.
    private func startBackgroundPreview() {
        guard let kind = activeEffect, let source = effectSource else { return }
        let effect = kind.effect(effectValues, curves: effectCurves, photo: photoEdit)
        guard effect != shownEffect else { return }
        let regions = effectRegions, generation = previewGeneration
        let original = UnsafeTransfer(source)
        previewRunning = true
        Task.detached(priority: .userInitiated) { [weak self] in
            let preview = EffectPreview.render(effect, from: original.value, regions: regions)
            await MainActor.run { [weak self] in self?.showBackgroundPreview(preview, of: effect, generation: generation) }
        }
    }

    private func showBackgroundPreview(_ preview: EffectPreview?, of effect: Effect, generation: Int) {
        // A render from a closed session mustn't clear the flag for the current one's (review B, finding 6).
        guard generation == previewGeneration else { return }
        previewRunning = false
        guard let edit = effectEdit else { return }
        edit.restoreOriginals()
        preview?.write(into: canvas.activeLayer, edit: edit)
        shownEffect = effect
        onRender()
        if previewWanted {
            previewWanted = false
            startBackgroundPreview()
        }
    }

    private func renderEffectPreview() {
        effectPreviewScheduled = false
        guard let kind = activeEffect else { return }
        if kind.previewsAsStep { return renderDecorationPreview(kind) }
        if kind.isCanvasTool { return onRender() }
        guard let edit = effectEdit else { return }
        edit.restoreOriginals()
        let effect = kind.effect(effectValues, curves: effectCurves, photo: photoEdit)
        if let regions = effectRegions {
            Effects.apply(effect, to: canvas.activeLayer, regions: regions, edit: edit)
        } else {
            Effects.apply(effect, to: canvas.activeLayer, selection: nil, edit: edit)
        }
        shownEffect = effect
        onRender()
    }

    /// Levels' Auto button: black and white points at the darkest and lightest values (FR-9.5).
    func autoLevels() {
        guard activeEffect == .levels, let histogram = effectHistogram else { return }
        let levels = Levels.auto(from: histogram)
        effectValues = [levels.black, levels.gamma, levels.white]
        previewEffect()
    }

    func setPhotoEdit(_ edit: PhotoEdit) {
        guard activeEffect == .adjustPhoto else { return }
        photoEdit = edit
        photoAutoMoved = photoAutoMoved.filter { edit.adjustments[$0] != 0 }
        previewEffect()
    }

    /// Adjust Photo's Auto: sets the sliders it balances from the original pixels and marks them (FR-9.5).
    func autoPhoto() {
        guard activeEffect == .adjustPhoto, let source = effectSource else { return }
        // From the original pixels, not the preview on screen.
        let auto = PhotoAdjustments.auto(for: source, selection: canvas.selection.marquee)
        var changed = photoEdit
        for slider in [PhotoAdjustments.Slider.exposure, .brilliance, .highlights, .shadows, .contrast, .warmth, .tint, .vibrance] {
            changed.adjustments[slider] = auto[slider]
        }
        photoEdit = changed
        photoAutoMoved = Set(auto.values.keys)
        previewEffect()
    }

    /// Adjust Photo's "As Adjustment Layer": the settings become an adjustment layer instead of pixels.
    func photoAsAdjustmentLayer() {
        guard activeEffect == .adjustPhoto else { return }
        let settings = photoEdit
        cancelEffect()
        addAdjustmentLayer(.photo(settings), named: settings.filter?.name ?? "Adjust Photo")
    }

    /// Save as Filter…: the filter at its intensity, then the color and tone sliders, as one filter.
    /// Returns the settings that now look the same: the new filter at 100%, with the color and tone
    /// sliders it absorbed back at zero (only the detail sliders stay). Nil if there was nothing to save.
    func saveFilter(from edit: PhotoEdit, named name: String) -> PhotoEdit? {
        var steps = edit.filter?.steps(atIntensity: edit.filterIntensity / 100) ?? []
        let own = edit.adjustments.colorAndTone
        if !own.isNeutral { steps.append(.photo(PhotoEdit(adjustments: own))) }
        guard !steps.isEmpty else {
            onRefused()
            return nil
        }
        let savedName = FilterStore.shared.add(PhotoFilter(name: name, steps: steps))
        let detail = PhotoAdjustments(edit.adjustments.values.filter { !$0.key.isColorOrTone })
        return PhotoEdit(adjustments: detail, filter: FilterStore.shared.filter(named: savedName), filterIntensity: 100)
    }

    /// Save Filter from Layers: the visible color and tone adjustment layers, bottom to top.
    /// False when there are none to save.
    func saveFilterFromLayers(named name: String) -> Bool {
        guard let filter = PhotoFilter.fromLayers(canvas.layers, name: name) else { return false }
        FilterStore.shared.add(filter)
        return true
    }

    /// Adjustments ▸ Auto Contrast: one step, no settings (FR-9.5, AC-31).
    func autoContrast() {
        guard !refusedBecauseLocked() else { return }
        finishInteractions()
        placeFloatingKeepingOutline()
        let selection = canvas.selection.marquee
        let levels = Levels.auto(from: Histogram(canvas.activeLayer.buffer, selection: selection))
        guard levels != .identity else { return }
        let edit = history.beginEdit("Auto Contrast", on: canvas)
        Effects.apply(.levels(levels), to: canvas.activeLayer, selection: selection, edit: edit)
        recordingChanges { history.commit(edit) }
        onRender()
    }

    /// An Auto Contrast adjustment layer: a Levels layer with its points set from what's beneath it now.
    func addAutoContrastLayer() {
        let below = canvas.composited(through: canvas.activeLayerIndex)
        addAdjustmentLayer(.levels(Levels.auto(from: Histogram(below))), named: "Auto Contrast")
    }

    /// An adjustment with no settings (Invert, Desaturate), applied to the selection or the whole layer.
    func applyAdjustment(_ effect: Effect) {
        guard !refusedBecauseLocked() else { return }
        finishInteractions()
        placeFloatingKeepingOutline()
        let edit = history.beginEdit(effect.name, on: canvas)
        Effects.apply(effect, to: canvas.activeLayer, selection: canvas.selection.marquee, edit: edit)
        recordingChanges { history.commit(edit) }
        onRender()
    }

    /// Whether the Resize and Skew dialog (⌘E) is open.
    var isResizeSkewOpen = false

    /// What Resize and Skew starts from: the selection as it appears now, or the whole image.
    var resizeSkewBaseSize: IntSize {
        canvas.selection.bounds?.size ?? canvas.size
    }

    func showResizeSkew() {
        finishInteractions()
        isResizeSkewOpen = true
    }

    /// Resizes and skews the selection, or the whole image when nothing is selected (FR-7.2).
    func apply(_ settings: ResizeSkew) {
        isResizeSkewOpen = false
        if !canvas.selection.isEmpty, refusedBecauseLocked() { return }
        finishInteractions()
        recordingChanges {
            if canvas.selection.isEmpty {
                ImageActions.resizeAndSkew(settings, canvas: canvas, history: history, context: selectionContext)
            } else {
                SelectionActions.resizeAndSkewSelection(settings, canvas: canvas, history: history, context: selectionContext)
            }
        }
        selectionDidChange()
    }

    /// Rotates or flips the selection, or the whole image when nothing is selected.
    func apply(_ orientation: Orientation) {
        // The whole image turns every layer, locked or not; a selection is pixels on the active layer.
        if !canvas.selection.isEmpty, refusedBecauseLocked() { return }
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
        guard !refusedBecauseLocked() else { return }
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
        if activeEffect == .pickSubject {
            activeEffect = nil
            if let pick = subjectPick { perform(pick.action, mask: pick.scan.mask()) }
            subjectPick = nil
            return
        }
        if activeEffect == .crop || activeEffect == .perspective {
            // Crossed or folded corners can't be straightened; the tool stays open to fix them (review C, finding 1).
            if activeEffect == .perspective, !Warp.isConvex(perspectiveCorners) { return onRefused() }
            let kind = activeEffect
            activeEffect = nil
            recordingChanges {
                if kind == .crop {
                    ImageActions.crop(to: cropRect, resizingTo: cropPixelSize, canvas: canvas, history: history, context: selectionContext)
                } else {
                    ImageActions.correctPerspective(corners: perspectiveCorners, canvas: canvas, history: history, context: selectionContext)
                }
            }
            if canvas.size != canvasSize { canvasDidResize() }
            // The new image can be a very different size; show all of it.
            zoomToFit()
            selectionDidChange()
            onRender()
            return
        }
        if activeEffect?.previewsAsStep == true {
            if activeEffect == .straighten { zoomToFit() }
            activeEffect = nil
            // The preview already is the step; it counts as a change only now.
            if decorationPreviewed {
                onDocumentChange(.done)
                layersRevision += 1
            } else {
                onRefused()
            }
            decorationPreviewed = false
            return
        }
        // Apply commits exactly the settings on screen: if the newest ones are still being worked out, do it now.
        if let kind = activeEffect, effectEdit != nil, kind.effect(effectValues, curves: effectCurves, photo: photoEdit) != shownEffect {
            renderEffectPreview()
        }
        guard let edit = effectEdit else { return }
        endEffectSession()
        activeEffect = nil
        recordingChanges { history.commit(edit) }
    }

    /// Drops the background preview state; a render still running finds a newer generation and is ignored.
    private func endEffectSession() {
        effectEdit = nil
        effectSource = nil
        shownEffect = nil
        previewGeneration += 1
        previewRunning = false
        previewWanted = false
    }

    func cancelEffect() {
        if activeEffect?.previewsAsStep == true, decorationPreviewed {
            history.undo(on: canvas)
            history.forgetRedo()
            if canvas.size != canvasSize { canvasDidResize() }
            selectionDidChange()
        }
        decorationPreviewed = false
        subjectPick = nil
        effectEdit?.restoreOriginals()
        endEffectSession()
        activeEffect = nil
        onRender()
    }

    // MARK: Layers

    /// Bumped whenever the layers or their pixels may have changed, so the Layers panel refreshes.
    private(set) var layersRevision = 0
    /// Whether the right sidebar is showing (FR-1.3, FR-8.1), and which of its panels.
    var isSidebarOpen = false
    var showsLayersPanel = true
    var showsAdjustmentsPanel = true
    /// Called when a command can't be carried out, such as painting on a locked layer; the view beeps.
    @ObservationIgnored var onRefused: () -> Void = {}
    @ObservationIgnored private var layerSettingsEdit: Edit?

    /// ⌘L and the toolbar's Layers button: show the Layers panel (opening the sidebar), or hide it.
    func toggleLayersPanel() {
        if isSidebarOpen && showsLayersPanel {
            showsLayersPanel = false
            if !showsAdjustmentsPanel { isSidebarOpen = false }
        } else {
            showsLayersPanel = true
            isSidebarOpen = true
        }
    }

    /// Shows a sidebar panel (opening the sidebar), or hides it if it's already showing.
    func togglePanel(_ panel: ReferenceWritableKeyPath<Editor, Bool>) {
        if isSidebarOpen && self[keyPath: panel] {
            self[keyPath: panel] = false
            if !showsLayersPanel && !showsAdjustmentsPanel && !showsHistoryPanel && !showsClipboardPanel { isSidebarOpen = false }
        } else {
            self[keyPath: panel] = true
            isSidebarOpen = true
        }
    }

    func toggleAdjustmentsPanel() {
        if isSidebarOpen && showsAdjustmentsPanel {
            showsAdjustmentsPanel = false
            if !showsLayersPanel { isSidebarOpen = false }
        } else {
            showsAdjustmentsPanel = true
            isSidebarOpen = true
        }
    }

    var layers: [Layer] {
        _ = layersRevision
        return canvas.layers
    }

    var activeLayerIndex: Int {
        _ = layersRevision
        return canvas.activeLayerIndex
    }

    /// Whether the active layer refuses pixel changes: it's locked, or it's an adjustment layer with no pixels.
    var activeLayerIsLocked: Bool {
        _ = layersRevision
        return canvas.activeLayer.isLocked || canvas.activeLayer.adjustment != nil
    }

    /// Makes another layer active. Moved pixels are placed on their own layer first; the outline stays.
    func selectLayer(at index: Int) {
        guard canvas.layers.indices.contains(index), index != canvas.activeLayerIndex else { return }
        finishInteractions()
        placeFloatingKeepingOutline()
        canvas.activeLayerIndex = index
        layersRevision += 1
        onRender()
    }

    func addLayer() {
        layerCommand { LayerActions.add(canvas: canvas, history: history, context: selectionContext) }
        isSidebarOpen = true
    }

    func duplicateLayer() {
        layerCommand { LayerActions.duplicate(canvas: canvas, history: history, context: selectionContext) }
    }

    func deleteLayer() {
        layerCommand { LayerActions.delete(canvas: canvas, history: history, context: selectionContext) }
    }

    func mergeDown() {
        layerCommand { LayerActions.mergeDown(canvas: canvas, history: history, context: selectionContext) }
    }

    func mergeVisible() {
        layerCommand { LayerActions.mergeVisible(canvas: canvas, history: history, context: selectionContext) }
    }

    func flatten() {
        layerCommand { LayerActions.flatten(canvas: canvas, history: history, context: selectionContext) }
    }

    /// Moves the layer at `source` so it sits at `destination` (stack indices; 0 is the bottom).
    func moveLayer(from source: Int, to destination: Int) {
        layerCommand { LayerActions.move(from: source, to: destination, canvas: canvas, history: history, context: selectionContext) }
    }

    func setLayerVisible(_ visible: Bool, at index: Int) {
        layerSetting(visible ? "Show Layer" : "Hide Layer", at: index) { $0.isVisible = visible }
    }

    func setLayerLocked(_ locked: Bool, at index: Int) {
        layerSetting(locked ? "Lock Layer" : "Unlock Layer", at: index) { $0.isLocked = locked }
    }

    func renameLayer(at index: Int, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        layerSetting("Rename Layer", at: index) { $0.name = trimmed }
    }

    func setBlendMode(_ mode: BlendMode) {
        layerSetting("Blend Mode", at: canvas.activeLayerIndex) { $0.blendMode = mode }
    }

    /// Opacity while its slider is dragged: shown live, recorded as one step by `finishLayerSettings()`.
    func previewOpacity(_ opacity: Double) {
        previewLayerSettings("Layer Opacity") { $0.opacity = min(1, max(0, opacity)) }
    }

    /// An adjustment layer's settings while a slider is dragged (FR-8.4), likewise one step.
    func previewAdjustment(_ adjustment: Effect) {
        guard canvas.activeLayer.adjustment != nil else { return }
        previewLayerSettings("Adjustment Settings") { $0.adjustment = adjustment }
    }

    func finishLayerSettings() {
        guard let edit = layerSettingsEdit else { return }
        layerSettingsEdit = nil
        recordingChanges { history.commit(edit) }
    }

    private func previewLayerSettings(_ name: String, _ change: (Layer) -> Void) {
        if layerSettingsEdit == nil {
            finishInteractions()
            let edit = history.beginEdit(name, on: canvas)
            edit.willChangeLayers()
            layerSettingsEdit = edit
        }
        change(canvas.activeLayer)
        layersRevision += 1
        onRender()
    }

    /// Adds an adjustment layer above the active layer and shows its settings.
    func addAdjustmentLayer(_ adjustment: Effect, named name: String) {
        layerCommand { LayerActions.addAdjustment(adjustment, named: name, canvas: canvas, history: history, context: selectionContext) }
        isSidebarOpen = true
        showsAdjustmentsPanel = true
    }

    /// Adds an adjustment layer of this kind above the active layer.
    func addAdjustmentLayer(_ choice: AdjustmentChoice) {
        if choice == .autoContrast {
            addAutoContrastLayer()
        } else {
            addAdjustmentLayer(choice.startingAdjustment, named: choice.title)
        }
    }

    /// Changes whenever the layers beneath the active one may look different, so a Levels layer's histogram
    /// is worked out again then, and not on every tick of its own sliders (review D, finding 2).
    var belowActiveLayerKey: Int {
        // Read so SwiftUI looks at the key again when layers change; layers themselves aren't observed.
        _ = layersRevision
        var hasher = Hasher()
        hasher.combine(undoRedoCount)
        hasher.combine(canvas.activeLayer.id)
        for layer in canvas.layers.prefix(canvas.activeLayerIndex) {
            hasher.combine(layer.id)
            hasher.combine(ObjectIdentifier(layer.buffer))
            hasher.combine(layer.isVisible)
            hasher.combine(layer.opacity)
            hasher.combine(layer.blendMode)
            hasher.combine(layer.adjustment)
        }
        return hasher.finalize()
    }

    /// Undo and redo can change pixels below the active layer without changing any layer's settings.
    private var undoRedoCount = 0

    /// The layers beneath the active one as they look together, by brightness, for a Levels layer.
    func histogramBelowActiveLayer() -> Histogram {
        let index = canvas.activeLayerIndex
        guard index > 0 else { return Histogram(PixelBuffer(width: 1, height: 1)) }
        return Histogram(canvas.composited(through: index - 1))
    }

    func applyAdjustmentLayer() {
        layerCommand { LayerActions.applyAdjustment(canvas: canvas, history: history, context: selectionContext) }
    }

    /// Sets an adjustment layer's settings in one step (Reset).
    func setAdjustment(_ adjustment: Effect) {
        layerSetting("Adjustment Settings", at: canvas.activeLayerIndex) { $0.adjustment = adjustment }
    }

    var activeAdjustment: Effect? {
        _ = layersRevision
        return canvas.activeLayer.adjustment
    }

    private func layerSetting(_ name: String, at index: Int, _ body: (Layer) -> Void) {
        finishInteractions()
        recordingChanges { LayerActions.update(name, layerAt: index, canvas: canvas, history: history, body) }
        onRender()
    }

    private func layerCommand(_ body: () -> Bool) {
        finishInteractions()
        var done = false
        recordingChanges { done = body() }
        if !done { onRefused() }
        layersRevision += 1
        selectionDidChange()
    }

    /// Whether pixel-changing commands work on the active layer (see `refusedBecauseLocked`).
    var activeLayerTakesEdits: Bool { !canvas.activeLayer.isLocked && canvas.activeLayer.adjustment == nil }

    /// Pixel-changing commands call this first. A locked layer refuses them (FR-8.2), and so does an
    /// adjustment layer, which has no pixels to change.
    private func refusedBecauseLocked() -> Bool {
        guard canvas.activeLayer.isLocked || canvas.activeLayer.adjustment != nil else { return false }
        onRefused()
        return true
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
        undoRedoCount += 1
        layersRevision += 1
        onDocumentChange(.undone)
        selectionDidChange()
    }

    func redo() {
        finishInteractions()
        guard history.redo(on: canvas) != nil else { return }
        undoRedoCount += 1
        layersRevision += 1
        onDocumentChange(.redone)
        selectionDidChange()
    }

    // MARK: Colors

    /// The well a left-click on a swatch sets. Right-clicks always set Color 2.
    var activeWell: ColorWell = .color1

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

    // MARK: Auto-Redact

    /// Reads the text in the selection (or the whole image) on this Mac and opens the review.
    func beginAutoRedact() {
        guard !refusedBecauseLocked() else { return }
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
    /// `snapshot` is the copy that was written; nothing else changes it, so its buffers are kept as they are.
    func markSaved(_ snapshot: SaveSnapshot) {
        lastSavedSnapshot = snapshot
        lastSavedImage = nil
        savedSize = snapshot.canvas.size
        savedLayers = Dictionary(uniqueKeysWithValues: snapshot.canvas.layers.filter { $0.adjustment == nil }.map { ($0.id, $0.buffer) })
    }

    // MARK: Files

    /// The image as it looks, including any floating selection, encoded in `format`.
    /// Formats without transparency are flattened over Color 2.
    func encoded(as format: ImageFileFormat, quality: Double = 0.9) throws -> Data {
        try withoutEffectPreview { try snapshot(of: canvas).encoded(as: format, quality: quality) }
    }

    /// The whole document as a .colorproj (FR-8.5), without any live effect preview.
    func encodedProject() throws -> Data {
        try withoutEffectPreview { try snapshot(of: canvas).encodedProject() }
    }

    /// A copy of the document to save or export in the background, without any live effect preview.
    func saveSnapshot() -> SaveSnapshot {
        withoutEffectPreview { snapshot(of: canvas.copy()) }
    }

    private func snapshot(of canvas: ColorbeeCore.Canvas) -> SaveSnapshot {
        SaveSnapshot(canvas: canvas, transparentKey: selectionContext.transparentKey, matte: color2)
    }

    /// More than one layer, or an adjustment layer: something only a project file can keep.
    var isLayered: Bool {
        canvas.layers.count > 1 || canvas.layers.contains { $0.adjustment != nil }
    }

    /// An effect's live preview is drawn into the layer before it's applied; an autosave in the
    /// meantime must write the image without it, in case the effect is cancelled.
    private func withoutEffectPreview<T>(_ body: () throws -> T) rethrows -> T {
        // Drop Shadow, Border and Straighten preview as a real step, so it's taken back for the copy
        // (review B, finding 1).
        if activeEffect?.previewsAsStep == true, decorationPreviewed {
            history.undo(on: canvas)
            defer { history.redo(on: canvas) }
            return try body()
        }
        guard let edit = effectEdit else { return try body() }
        // The preview's pixels are put back as they were, not worked out again on the main thread
        // (review B, finding 3).
        let shown = edit.dirtyRect, layer = canvas.activeLayer
        let pixels = layer.buffer.pixels(in: shown)
        edit.restoreOriginals()
        defer { layer.buffer.setPixels(pixels, in: shown) }
        return try body()
    }

    func flattenedPNG() throws -> Data {
        try encoded(as: .png)
    }
}

/// A finished shape drawing handed back from the background. The buffer is new and nothing else holds it.
private struct RenderedShape: @unchecked Sendable {
    let pixels: PixelBuffer
    let origin: IntPoint
}

/// Hands a pixel buffer to a background task that only reads it while nothing else writes to it.
private struct UnsafeTransfer<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
