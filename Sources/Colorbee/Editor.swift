import ColorbeeCore
import CoreGraphics
import Foundation
import Observation

enum DocumentChange {
    case done
    case undone
    case redone
}

/// Which color well a swatch click (and the Alpha slider and the color picker) changes (FR-1.1).
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

/// The Before/After view's settings (FR-11.3).
struct Comparison: Equatable {
    enum Baseline { case asOpened, lastSaved }
    enum Layout { case split, sideBySide }

    var baseline: Baseline = .asOpened
    var layout: Layout = .split
    /// The split's divider, as a fraction of the view's width.
    var divider = 0.5
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

    /// The document's pages (FR-11.6); the canvas and history are the shown page's.
    @ObservationIgnored let pages: PageStack
    /// The page shown. Setting it (through `pageDidChange`) refreshes everything that shows the canvas.
    var page: Page
    var canvas: Canvas { page.canvas }
    var history: History { page.history }

    // A first click on a new document selects rather than draws (Leah, 2026-10-04).
    var tool: Tool = .rectangleSelect
    var brush: Brush = .round
    /// Brushes respond to trackpad and pen pressure (FR-4.2). Off, every brush draws at full size.
    var usesPressure = true
    // Colors show live in pending shapes and transparent selections.
    /// While a mask is chosen, colors are grays (Q28.3): a mask holds how much shows, not a color.
    var color1: Pixel = .black {
        didSet {
            if canvas.editsMask, color1 != color1.maskGray { color1 = color1.maskGray }
            renderSoon()
        }
    }
    var color2: Pixel = .white {
        didSet {
            if canvas.editsMask, color2 != color2.maskGray { color2 = color2.maskGray }
            renderSoon()
        }
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
    /// Fill and the wand find their area in all visible layers together, not just the active one (Leah, 2026-10-04).
    var fillSamplesAllLayers = false
    var wandSamplesAllLayers = false
    /// The Color Eraser's tolerance, 0...1; 0 replaces only exact Color 1 (FR-4.3; review I, finding 6).
    var colorEraserTolerance = 0.0
    /// The Eraser color-erases with a plain drag too, not only a right-drag, which is awkward on a trackpad (Leah, 2026-10-04).
    var colorEraserMode = false
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
    var viewport = Viewport()
    var pointer: IntPoint?
    /// The selection being dragged, already combined with the existing selection.
    var marqueePreview: SelectionMask?
    /// Bounds of the selected area, for the status bar.
    var selectionBounds: IntRect?
    /// The canvas size, observable for the status bar (the canvas itself isn't observable).
    var canvasSize: IntSize
    /// A stretched floating selection's width as a percentage of its original, for the status bar.
    var selectionScalePercent: Int?
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
    var pendingShape: PendingShape?
    // Step badges (FR-5.3).
    var badgeStyle: BadgeStyle = .numbers {
        didSet { renderSoon() }
    }
    /// What the next badge of each style shows: numbers and letters count separately (Leah, 2026-10-10). Each starts
    /// at the beginning in each document and steps back when one of its badges is undone.
    var nextBadges: [BadgeStyle: Int] = [:]
    /// The next badge in the style chosen now.
    var nextBadge: Int {
        get { nextBadges[badgeStyle] ?? 1 }
        set { nextBadges[badgeStyle] = max(1, newValue) }
    }
    var badgeDiameter = 32.0 {
        didSet { renderSoon() }
    }
    var pendingBadge: PendingBadge?
    // The Redact Brush (FR-9.6). Solid Fill is the safest, so it's the default, as in Auto-Redact.
    var redactTreatment: RedactionTreatment = .solidFill
    var redactBrushSize = 24.0 {
        didSet { renderSoon() }
    }
    /// A Redact Brush or Remove and Spot Heal stroke: the area painted so far, its smoothed path, and what it's for.
    @ObservationIgnored var areaStroke: (area: RedactBrushArea, path: StrokePath, purpose: AreaPurpose)?
    enum AreaPurpose {
        case redact(secondary: Bool)
        case retouch(RetouchKind)
    }
    // Retouching (FR-4.6).
    var retouchKind: RetouchKind = .remove {
        didSet { renderSoon() }
    }
    /// Each retouching tool keeps its own size.
    private var retouchSizes: [RetouchKind: Double] = [:] {
        didSet { renderSoon() }
    }
    var retouchSize: Double {
        get { retouchSizes[retouchKind] ?? retouchKind.defaultSize }
        set { retouchSizes[retouchKind] = newValue }
    }
    /// Remove and Spot Heal read what all visible layers show and write into the active one, so retouching can go
    /// on an empty layer above a photo and leave the photo as it was.
    var retouchSamplesAllLayers = false
    /// The local brushes' Strength, and how hard the retouching brushes' edge is (FR-4.6).
    var retouchStrength = 0.5
    var retouchHardness = 0.5
    var toneRange: ToneRange = .midtones
    /// The Clone Stamp: where it copies from (Option-click), whether the offset stays from stroke to stroke, and
    /// whether the copied pixels' tone is evened out with their surroundings.
    var cloneSource: Point2D?
    var cloneAligned = true
    var cloneMatchesTone = false
    /// From where you paint to where it copies from, once the first stroke after picking the source started.
    @ObservationIgnored var cloneOffset: IntPoint?
    @ObservationIgnored var retouchBrush: (stroke: Stroke, edit: Edit, kind: RetouchKind, path: StrokePath, offset: IntPoint?, pressure: Double)?
    /// Where the Clone Stamp is copying from now, for the crosshair.
    var cloneCrosshair: Point2D?
    /// The area being filled, shown until the fill is done.
    @ObservationIgnored var fillingArea: RedactBrushArea?
    /// How far the fill has got, while one runs.
    var fillProgress: Double?
    @ObservationIgnored var fillCancel: CancelFlag?
    enum BadgeDrag {
        case create
        case move(grab: Point2D, original: PendingBadge)
    }
    @ObservationIgnored var badgeDrag: BadgeDrag?
    /// What each placed badge's step showed, so undoing it steps its style's next value back.
    @ObservationIgnored var badgeSteps: [UUID: (style: BadgeStyle, value: Int)] = [:]
    var gradientMode: GradientMode = .linear
    var symmetry: SymmetryMode = .off {
        didSet { renderSoon() }
    }
    /// The last measurement; it stays on screen until the next one or a tool change.
    var measurement: Measurement?
    var textStyle = TextStyle() {
        didSet { renderSoon() }
    }
    /// The Text options' Editable switch (Q29.1): placed text becomes a text layer. Off by default; the switch remembers
    /// it (`editableTextKey`), so tests never save it.
    var textIsEditable = UserDefaults.standard.bool(forKey: Editor.editableTextKey)
    static let editableTextKey = "EditableText"
    /// Smoothing (stage 31), 0 (off) to 1, shared by the Brushes, Eraser, Redact Brush and Retouch tools (Q31.2). The
    /// palette bar's slider remembers it (`smoothingKey`), so tests never save it.
    var smoothing = min(1, max(0, UserDefaults.standard.double(forKey: Editor.smoothingKey)))
    static let smoothingKey = "Smoothing"
    /// How far the pointer pulls ahead before a smoothed line follows, in image pixels: up to 36 points on screen at full
    /// Smoothing, so it feels the same at any zoom.
    var smoothingReach: Double { smoothing * 36 / viewport.zoom }
    var pendingText: PendingText?
    /// Non-nil while Before/After is showing. The view is read-only while it's on.
    var comparison: Comparison? {
        didSet { if oldValue?.layout != comparison?.layout { fitComparison() } else { renderSoon() } }
    }
    /// The page shown, as opened or created (FR-11.3). Other pages keep theirs in `pageMemory`.
    @ObservationIgnored var opened: PageBaseline
    var asOpened: PixelBuffer? { opened.flattened }
    /// The document at the last explicit save, as it was written.
    var lastSavedSnapshot: SaveSnapshot?
    @ObservationIgnored var lastSavedImage: PixelBuffer?
    /// "Last Saved" is for the page shown at the last save (FR-11.6).
    var hasLastSaved: Bool { lastSavedSnapshot?.pageID == page.id }
    /// The image at the last explicit save, flattened the first time Before/After needs it.
    var lastSaved: PixelBuffer? {
        guard hasLastSaved else { return nil }
        if lastSavedImage == nil, let snapshot = lastSavedSnapshot {
            lastSavedImage = snapshot.flattened
        }
        return lastSavedImage
    }
    var autoRedact: AutoRedactSession?
    var redactionPatterns = Editor.loadRedactionPatterns() {
        didSet {
            Editor.saveRedactionPatterns(redactionPatterns)
            refreshAutoRedactMatches()
        }
    }
    /// The gap between the two images in side-by-side Before/After, in image pixels.
    static let comparisonGap = 40
    /// The effect whose dialog is open, if any.
    var activeEffect: EffectKind?
    /// Batch Redact's Blur and Pixelate: the preview and Apply cover every layer under the selection
    /// (review H, finding 3; Leah, 2026-10-04).
    var effectCoversAllLayers = false
    /// The layers a Batch Redact bar previews and changes.
    @ObservationIgnored var effectLayers: [Layer] = []
    var effectValues: [Double] = []

    @ObservationIgnored var onRender: () -> Void = {}
    @ObservationIgnored var renderScheduled = false
    @ObservationIgnored var onDocumentChange: (DocumentChange) -> Void = { _ in }
    @ObservationIgnored var activeStroke: ActiveStroke?
    @ObservationIgnored var selectionDrag: SelectionDrag?
    @ObservationIgnored var effectEdit: Edit?
    /// Curves' points while its dialog is open.
    var effectCurves = Curves.identity
    /// The Adjust Photo panel's settings while it's open, and which sliders Auto last set.
    var photoEdit = PhotoEdit()
    var photoAutoMoved: Set<PhotoAdjustments.Slider> = []
    /// An eyedropper waiting for a click on the picture (FR-9.7). See `picturePickPurpose`.
    var picturePick: PicturePick?
    /// What Levels shows behind its sliders: the pixels it applies to, before any change.
    var effectHistogram: Histogram?
    /// The selection's separate regions, worked out once per dialog; nil applies to the whole layer.
    @ObservationIgnored var effectRegions: [SelectionMask]?
    @ObservationIgnored var effectPreviewScheduled = false
    /// The active layer's pixels as they were when the effect opened. Previews are worked out from this
    /// copy in the background, so large images don't hold up the sliders (NFR-6).
    @ObservationIgnored var effectSource: PixelBuffer?
    /// What the canvas shows now, so Apply knows whether the newest settings still need working out.
    @ObservationIgnored var shownEffect: Effect?
    /// Bumped when the effect closes, so a background preview finishing late is ignored.
    @ObservationIgnored var previewGeneration = 0
    @ObservationIgnored var previewRunning = false
    @ObservationIgnored var previewWanted = false
    @ObservationIgnored var shapeDrag: ShapeDrag?
    @ObservationIgnored var gradientDrag: GradientDrag?
    @ObservationIgnored var gradientRenderScheduled = false

    struct GradientDrag {
        let edit: Edit
        let start: Point2D
        var end: Point2D
        /// Right-drag runs from Color 2 to Color 1.
        let reversed: Bool
        let selection: SelectionMask?
    }
    @ObservationIgnored var shapeRenderCache: (spec: ShapeSpec, pixels: PixelBuffer, origin: IntPoint)?
    @ObservationIgnored var textRenderCache: (spec: TextSpec, pixels: PixelBuffer, origin: IntPoint)?
    /// Textured shapes take too long to draw on every drag event, so they're drawn in the background;
    /// these track the drawing under way and the newest spec waiting for it.
    @ObservationIgnored var shapeRenderInFlight = false
    @ObservationIgnored var shapeRenderWanted: ShapeSpec?
    /// Bumped when a shape is placed or cancelled, so a late background result for it is dropped.
    @ObservationIgnored var shapeRenderGeneration = 0

    enum ShapeDrag {
        case draw
        case curveLine
        case move(grab: Point2D, original: PendingShape)
        case handle(ShapeHandle, grab: Point2D, original: PendingShape)
    }

    private func family(_ kind: ShapeKind) -> Int {
        kind.isLinear ? 0 : kind.isPointBased ? (kind == .polygon ? 1 : 2) : 3
    }

    struct ActiveStroke {
        let edit: Edit
        /// One stroke per mirror image when Symmetry is on.
        let strokes: [Stroke]
        var path: StrokePath
        /// The lightest and firmest pressure seen, logged when the stroke ends to tune pressure response.
        var pressureRange: ClosedRange<Double>
        /// The latest pressure, for the line catching up on release.
        var pressure: Double
    }

    enum SelectionDrag {
        case marquee(shape: SelectionShape, start: Point2D, mode: SelectionCombineMode, shiftHeldAtStart: Bool, shiftReleased: Bool)
        case lasso(points: [Point2D], mode: SelectionCombineMode)
        case move(edit: Edit?, grab: Point2D, origin: IntPoint, smear: Bool, duplicate: Bool)
        case resize(edit: Edit?, handle: SelectionHandle, original: IntRect, grab: Point2D)
    }

    convenience init(canvas: Canvas) {
        self.init(pages: PageStack(pages: [Page(canvas: canvas, history: Editor.makeHistory())]))
    }

    /// Every page but the current one should be parked.
    init(pages: PageStack) {
        self.pages = pages
        page = pages.current
        canvasSize = pages.current.canvas.size
        opened = PageBaseline(canvas: pages.current.canvas.copy())
        saved = opened
        // Every other page as opened is the bytes it's parked in: nothing to copy, and right even if the page is
        // redacted before it's ever shown (review K, finding 4).
        for other in pages.pages where other !== pages.current {
            guard let parked = other.parked else { continue }
            let baseline = PageBaseline(data: parked, describing: other.canvas)
            pageMemory[other.id] = PageMemory(viewport: nil, opened: baseline, saved: baseline, savedGeometrySteps: [])
        }
    }

    /// A page's undo history, as the app keeps it.
    nonisolated static func makeHistory() -> History {
        let history = History(byteBudget: Editor.historyByteBudget)
        history.makeThumbnail = { $0.thumbnail(maxSide: 64) }
        // Flatten and Merge don't wait for replaced layers to be written out (AC-27).
        history.evictsInBackground = true
        return history
    }

    // MARK: Pages (FR-11.6)

    /// What a hidden page goes back to when it's shown: compressed until then.
    struct PageMemory {
        /// Nil until the page has been shown.
        var viewport: Viewport?
        var opened: PageBaseline
        var saved: PageBaseline
        var savedGeometrySteps: [ObjectIdentifier]
    }

    @ObservationIgnored var pageMemory: [UUID: PageMemory] = [:]
    /// The newest undos, oldest first: page changes and page edits redo in the order they were undone.
    enum Undone { case pageChange, pageEdit }
    @ObservationIgnored var undone: [Undone] = []
    /// Auto-Redacts that changed more than one page, as each page's step: undone and redone together while they're
    /// the newest change on every page (Leah, 2026-10-04).
    @ObservationIgnored var redactionGroups: [[(page: UUID, step: UUID)]] = []
    var showsPageSidebar = true {
        didSet { onViewStateChange() }
    }

    // MARK: Canvas (FR-1.4)

    var isCanvasPropertiesOpen = false
    var showsRulers = false {
        didSet { onViewStateChange() }
    }
    var showsStatusBar = true {
        didSet { onViewStateChange() }
    }
    var showsHistoryPanel = false {
        didSet { onViewStateChange() }
    }
    var showsClipboardPanel = false {
        didSet { onViewStateChange() }
    }
    var showsInfoPanel = false {
        didSet { onViewStateChange() }
    }

    /// The document's file, for the Info panel (FR-1.3). `ImageDocument` keeps these current.
    var fileName = "Untitled"
    /// The format's name, or nil while it has never been saved.
    var fileKind: String?
    var fileBytes: Int64?

    /// While a canvas edge handle is dragged: the size it would become, outlined on the canvas.
    var canvasResizePreview: IntSize? {
        didSet { renderSoon() }
    }

    /// The page shown's layers as of the last explicit save (or as opened), for Revert Layer (FR-8.3).
    @ObservationIgnored var saved: PageBaseline
    /// The crop, resize, rotation and flip steps in effect at the last save; Revert Layer needs the same ones.
    @ObservationIgnored var savedGeometrySteps: [ObjectIdentifier] = []

    nonisolated private static var historyByteBudget: Int {
        Int(min(UInt64(512 << 20), ProcessInfo.processInfo.physicalMemory / 10))
    }

    // MARK: Painting

    /// The Eyedropper's Sample Size (FR-9.7 item 9): 1 (one pixel), 3 or 5 pixels square, averaged.
    var eyedropperSampleSize = 1

    /// The status bar's eyedropper is on: the next click on the picture copies that color's hex, whatever the tool
    /// (Leah, 2026-10-28). Esc turns it off.
    var picksHexToCopy = false

    /// A drag is going on over the picture: drawing, moving or panning.
    var isPointerDragging = false
    @ObservationIgnored var lastPointerColor: Pixel?

    // MARK: Retouching: brushes (FR-4.6)

    /// Strokes whose Match Tone reads more pixels than this have it worked out in the background. Tests lower it.
    static var backgroundToneArea = 250_000

    // MARK: Text

    /// The box being dragged out with the Text tool, shown as a frame until the mouse is released.
    var textDragFrame: (start: Point2D, end: Point2D)?

    @ObservationIgnored var textBoxDrag: (grab: TextBoxGrab, text: PendingText, frame: IntRect, start: Point2D)?

    // MARK: Selection dragging

    /// The selection tools' Feather (FR-3.4): how soft each new rectangle, ellipse or free-form selection's edge is,
    /// in pixels. It's applied when the drag ends, so dragging stays quick; the outline shows where pixels are half
    /// selected, which feathering doesn't move.
    var selectionFeather = 0.0
    /// The shape being drawn and how it combines, for feathering it when the drag ends.
    @ObservationIgnored var drawnSelection: (shape: SelectionMask?, mode: SelectionCombineMode)?

    // MARK: Edit ▸ Feather… and Modify Selection (FR-3.4, FR-9.7 item 3)

    /// Which change the selection sheet is trying, if it's open; the canvas tints what isn't selected meanwhile.
    var selectionChange: SelectionModification?
    /// The radius being tried, in whole pixels.
    var selectionChangeRadius = 10.0
    /// Whether the radius being tried would leave nothing selected, so OK can't be chosen.
    var selectionChangeLeavesNothing = false
    /// Whether the preview for the radius being tried is still being worked out.
    var isWorkingOnSelectionChange = false
    @ObservationIgnored var selectionChangeOriginal: SelectionMask?
    /// Whether the last Clone Stamp stroke's Match Tone is still being worked out.
    var isMatchingTone = false
    @ObservationIgnored var pendingTone: PendingTone?

    /// The radius the preview shows, whether one is being worked out, a count that drops a stale one, and whether
    /// OK is waiting for it.
    @ObservationIgnored var selectionChangeShown: Double?
    @ObservationIgnored var selectionChangeRunning = false
    @ObservationIgnored var selectionChangeSession = 0
    @ObservationIgnored var appliesSelectionChangeWhenShown = false

    // MARK: Edit ▸ Color Range… and Luminance Range… (FR-9.7 item 3)

    /// The colors clicked for Color Range; Shift-click adds more.
    var rangeColors: [Pixel] = []
    /// What the range reads: the active layer, or everything shown with Sample All Layers (shared with the Magic Wand).
    @ObservationIgnored var rangeSource: PixelBuffer?
    /// The settings the preview shows, whether one is being worked out, and a count that drops a stale one.
    @ObservationIgnored var rangeShown: RangeSettings?
    @ObservationIgnored var rangeRunning = false
    @ObservationIgnored var rangeSession = 0
    /// The range's own selection for the settings shown, before it's combined with the one there already.
    @ObservationIgnored var rangeMask: SelectionMask?

    enum RangeSettings: Equatable {
        case color(ColorRange)
        case luminance(LuminanceRange)
        case graduated(GraduatedSelection)

        func selection(in source: PixelBuffer) -> SelectionMask? {
            switch self {
            case .color(let range): range.selection(in: source)
            case .luminance(let range): range.selection(in: source)
            case .graduated(let line): line.selection(in: source.bounds)
            }
        }
    }

    /// Graduated Selection's line, once one is drawn; its ends can be dragged until Return.
    var graduatedLine: GraduatedSelection?
    /// Which end a drag is moving, or nil when it draws a new line.
    @ObservationIgnored var graduatedMoving: GraduatedEnd?

    enum GraduatedEnd { case start, end }

    /// Luminance Range's presets, in the order the bar shows them.
    static let luminancePresets: [(title: String, range: LuminanceRange)] =
        [("Shadows", .shadows), ("Midtones", .midtones), ("Highlights", .highlights)]

    // MARK: Effects

    /// Whether a Drop Shadow, Border or Straighten preview step is in the history right now.
    @ObservationIgnored var decorationPreviewed = false
    /// Straighten's preview: whether a turn is being worked out in the background, whether newer settings wait for
    /// it, which angle and Crop to fit the preview step shows, and a count that makes a stale turn be dropped.
    @ObservationIgnored var straightenRunning = false
    @ObservationIgnored var straightenWanted = false
    @ObservationIgnored var straightenShown: (angle: Double, cropToFit: Bool)?
    @ObservationIgnored var straightenToken = 0
    /// The running turn's stop flag, and a signal it gives once it no longer reads the original layers.
    @ObservationIgnored var straightenWork: (stop: CancelFlag, done: DispatchSemaphore)?

    // MARK: Straighten, Perspective Correction and Crop (FR-9.5)

    /// Straighten: a line being drawn along something that should be level.
    var straightenLine: (start: Point2D, end: Point2D)?
    /// Perspective Correction: top left, top right, bottom right, bottom left, in image coordinates.
    var perspectiveCorners: [Point2D] = []
    /// Where the corners started: on the rectangle Vision found, or inset from the edges. Reset puts them back.
    var perspectiveStartCorners: [Point2D] = []
    var isFindingCorners = false
    /// Counts searches, so one from a Perspective Correction that was closed can't move a later one's corners.
    @ObservationIgnored var cornerSearch = 0

    /// Crop: the box, its shape and an exact output size from a pixel-size preset.
    var cropRect = IntRect.zero
    var cropShape = CropShape.free { didSet { renderSoon() } }
    var cropPixelSize: IntSize? { didSet { renderSoon() } }
    var isDraggingCrop = false
    /// Crop…'s guides (FR-9.7 item 7): the last chosen, in every window, while Colorbee is open.
    var cropOverlay = Editor.lastCropOverlay {
        didSet {
            Editor.lastCropOverlay = cropOverlay
            renderSoon()
        }
    }
    @ObservationIgnored private static var lastCropOverlay = CropOverlay.thirds
    /// After O, the guides show for a moment though the box isn't being dragged, so you see what you chose.
    @ObservationIgnored var cropOverlayShownUntil: ContinuousClock.Instant?

    @ObservationIgnored var toolDrag: (start: Point2D, handle: SelectionHandle?, rect: IntRect, corner: Int?)?

    // MARK: Messages and Copy Text (FR-10.4)

    /// A short message at the bottom of the canvas that fades by itself, such as "Copied 42 words" (Leah, 2026-10-10).
    struct Notice: Equatable {
        let id = UUID()
        let text: String
    }

    var notice: Notice?

    /// Whether Copy Text is reading now.
    var isReadingText = false

    // MARK: Remove Red-Eye (FR-9.5)

    /// Whether Vision is looking for eyes now.
    var isFindingEyes = false

    // MARK: Subjects (FR-9.5)

    enum SubjectAction {
        case removeBackground, liftToNewLayer, select
    }

    /// Whether Vision is looking for the subject now.
    var isFindingSubject = false
    /// A message to show, such as "No subject found".
    var subjectMessage: String?
    /// With several subjects, or none: what was found, the image it was found in and what to do with the one you click.
    @ObservationIgnored var subjectPick: (scan: SubjectScan, image: CGImage, action: SubjectAction, layer: LayerID)?
    /// How many subjects the pick found, for Return to take. With none, a click looks closer.
    var pickSubjectCount = 0
    /// Counts closer looks, so one that was cancelled can't touch a later search when it finishes.
    @ObservationIgnored var closerLook = 0

    // MARK: Picking from the picture (FR-9.7): the white-balance eyedropper and Point Color

    enum PicturePickPurpose: Equatable {
        /// Warmth and Tint set so the clicked spot comes out gray.
        case whiteBalance
        /// The clicked color added to Point Color.
        case pointColor
        /// The hand (FR-9.7 item 6): dragging up or down changes the Tone Curve region under the pointer.
        case toneCurve
        /// The hand in the Color Mixer: dragging changes this setting for the color under the pointer.
        case colorMixer(ColorMixer.Setting)

        /// The hand stays on, and drags; an eyedropper takes one click.
        var drags: Bool {
            switch self {
            case .toneCurve, .colorMixer: true
            case .whiteBalance, .pointColor: false
            }
        }
    }

    struct PicturePick: Equatable {
        enum Target: Equatable {
            /// For the Adjust Photo panel.
            case panel
            /// For this Adjust Photo layer, from the Adjustments panel.
            case layer(LayerID)
        }

        var purpose: PicturePickPurpose
        var target: Target
    }

    // MARK: Dragging on the picture to adjust (FR-9.7 item 6)

    /// A drag with the hand: what it changes, and where it started.
    struct PictureDrag {
        let target: PicturePick.Target
        /// The Tone Curve region, or the Color Mixer setting and range, under the pointer when the drag began.
        let region: ToneCurve.Region?
        let mixer: (setting: ColorMixer.Setting, range: ColorMixer.Range)?
        let startY: Double
        let startValue: Double
    }

    @ObservationIgnored var pictureDrag: PictureDrag?

    /// How many slider steps a drag of one view point makes: 200 points is the whole of one side.
    static let pictureDragRate = 0.5

    // MARK: Using Adjust Photo settings again (FR-9.7 item 4)

    /// Same as Last is being worked out.
    @ObservationIgnored var sameAsLastRunning = false

    // MARK: Adjust Photo's histogram and clipping warnings (FR-9.7 item 6)

    /// The picture as it looks now, for Adjust Photo's histogram: worked out from a small copy after each change.
    var photoHistogram: Histogram?
    @ObservationIgnored var photoHistogramScheduled = false
    @ObservationIgnored var lastPhotoHistogram: ContinuousClock.Instant?
    /// While a slider is dragged, the histogram follows about ten times a second: worked out on every step, it made
    /// Exposure stutter, taking up to two frames on an Adjust Photo layer (Leah, 2026-10-28).
    static let photoHistogramInterval = Duration.milliseconds(100)
    /// The copy it's worked out from: plenty for its shape, and a quarter of the work of 320.
    static let photoHistogramSide = 160
    /// Blown highlights shown red, and crushed shadows blue, on the picture only (Q15.2).
    var clipsHighlights = false {
        didSet { renderSoon() }
    }
    var clipsShadows = false {
        didSet { renderSoon() }
    }

    /// Whether the Resize and Skew dialog (⌘E) is open.
    var isResizeSkewOpen = false

    // MARK: After a redaction (review H, findings 1 and 2)

    /// A redaction step to report: why one couldn't be done.
    var redactionMessage: String?
    /// After a redaction, the Clipboard History items to offer to remove (Remove is the default).
    var clipboardCleanup: ClipboardCleanup?
    /// The clipboard's change count right after Copy Text put this document's text there; while it's unchanged, the
    /// clipboard still holds that text.
    @ObservationIgnored var copiedTextClipboardCount: Int?
    /// A redaction was applied since the last explicit save, so the save warns about earlier versions.
    @ObservationIgnored var redactedSinceSave = false

    // MARK: Layers

    /// Bumped whenever the layers or their pixels may have changed, so the Layers panel refreshes.
    var layersRevision = 0
    /// Whether the right sidebar is showing (FR-1.3, FR-8.1), and which of its panels.
    var isSidebarOpen = false {
        didSet { onViewStateChange() }
    }
    var showsLayersPanel = true {
        didSet { onViewStateChange() }
    }
    var showsAdjustmentsPanel = true {
        didSet { onViewStateChange() }
    }
    /// Called when a command can't be carried out, such as painting on a locked layer; the view beeps.
    @ObservationIgnored var onRefused: () -> Void = {}
    /// Gives the canvas the keyboard, so tool keys work after a toolbar click or a paste (review I, finding 2).
    @ObservationIgnored var onFocusCanvas: () -> Void = {}
    @ObservationIgnored var layerSettingsEdit: Edit?

    // MARK: Choosing several layers (FR-8.6)

    /// The layers chosen besides the active one, with Shift- or ⌘-click (Leah, 2026-10-27). Choosing isn't an undo step
    /// and isn't saved.
    var otherChosenLayerIDs: Set<LayerID> = []
    /// Where a Shift-click range starts: the layer last clicked without Shift.
    @ObservationIgnored var chooseAnchor: LayerID?

    // MARK: Layer masks (stages 27 to 28b)

    /// Option-click on a mask's thumbnail (stage 28a): the picture shows the mask alone, in grays. Only a view.
    var showsMaskAlone = false {
        didSet { renderSoon() }
    }

    // MARK: Layer groups (stages 25 and 26)

    /// Groups folded shut in the Layers panel. Only a view: not saved, and not an undo step.
    var foldedGroups: Set<LayerID> = []

    // MARK: Align and Distribute (stage 24)

    /// What Option-clicking an eye last did: which layer it left showing alone, how every layer was before, how they
    /// were right after, and the step, which must still be done for any of it to count (review U, finding 6).
    struct Isolation {
        let layer: LayerID
        let before: [LayerID: Bool]
        let after: [LayerID: Bool]
        weak var step: AnyObject?
    }

    @ObservationIgnored var isolation: Isolation?

    /// Undo and redo can change pixels below the active layer without changing any layer's settings.
    var undoRedoCount = 0

    // MARK: Colors

    /// The well a left-click on a swatch sets. Right-clicks always set Color 2.
    var activeWell: ColorWell = .color1

    // MARK: Viewport

    /// Zoom and scroll position to show instead of fitting the window, after a relaunch (review J, finding 28).
    @ObservationIgnored var restoredView: (zoom: Double, center: Point2D)?
    /// Tells the window its restorable state (zoom, scroll, panels) changed.
    @ObservationIgnored var onViewStateChange: () -> Void = {}

    // MARK: Auto-Redact

    /// Where a page's pixels come from for reading: the page shown, copied, or a parked page's bytes.
    enum PageSource: Sendable {
        case canvas(UnsafeTransfer<Canvas>)
        case parked(Data)

        func canvas() throws -> Canvas {
            switch self {
            case .canvas(let copy): copy.value
            case .parked(let data): try ProjectFile.decode(data)
            }
        }
    }

    static let patternsKey = "AutoRedactPatterns"
}

/// A finished shape drawing handed back from the background. The buffer is new and nothing else holds it.
struct RenderedShape: @unchecked Sendable {
    let pixels: PixelBuffer
    let origin: IntPoint
}

/// What the after-redaction offer removes: Clipboard History images this document came from or was copied to, and
/// whether the clipboard still holds text Copy Text read from it before the redaction.
struct ClipboardCleanup: Equatable {
    var images: [ClipboardHistory.Item.ID]
    var text: Bool
}
