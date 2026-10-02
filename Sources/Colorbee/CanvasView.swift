import AppKit
import ColorbeeCore
import Metal
import QuartzCore

/// The drawing surface: renders the canvas with Metal and turns mouse, trackpad and keys into edits.
final class CanvasView: NSView {
    private enum Drag {
        case primary
        case secondary
        case select(last: Point2D)
        case measure(start: Point2D)
        case gradient
        case divider
        case shape
        case text(start: Point2D)
        case pan(last: NSPoint)
    }

    var onFirstFrame: (() -> Void)?
    /// Input event → GPU finished the frame: Colorbee's own share (NFR-2).
    let processingLatency = LatencyStats()
    /// Input event → frame on screen, including macOS compositing.
    let screenLatency = LatencyStats()

    private let editor: Editor
    private let renderer = Renderer.shared
    private var displayLink: CADisplayLink?
    private var antsTimer: Timer?
    private var textView: CanvasTextView?
    private var appliedTextStyle: (spec: TextSpec, zoom: Double)?
    private var needsRender = true
    private var pendingInputTime: TimeInterval?
    private var hasFitted = false
    private var hasPresented = false
    private var drag: Drag?
    private var spaceHeld = false
    /// Where the pointer is over the view, in image coordinates, for the eraser's outline.
    private var hoverPoint: Point2D?
    private var surroundColor = MTLClearColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)

    private var metalLayer: CAMetalLayer {
        guard let metalLayer = layer as? CAMetalLayer else { fatalError("CanvasView must be backed by a CAMetalLayer") }
        return metalLayer
    }

    init(editor: Editor) {
        self.editor = editor
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
        editor.onRender = { [weak self] in
            self?.setNeedsRender()
            self?.syncTextEditor()
        }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect, .cursorUpdate],
            owner: self
        ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func makeBackingLayer() -> CALayer {
        let layer = CAMetalLayer()
        layer.device = renderer.device
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = true
        layer.maximumDrawableCount = 2
        // The window server composites before scanout anyway; skipping our own vsync wait saves ~8 ms.
        layer.displaySyncEnabled = false
        layer.isOpaque = true
        layer.colorspace = editor.canvas.colorSpace
        return layer
    }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    // MARK: Rendering

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if let window {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: window)
        }
        if let newWindow {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowOcclusionChanged(_:)),
                name: NSWindow.didChangeOcclusionStateNotification,
                object: newWindow
            )
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            displayLink?.invalidate()
            displayLink = nil
            antsTimer?.invalidate()
            antsTimer = nil
            return
        }
        if antsTimer == nil {
            let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.animateAnts() }
            }
            RunLoop.main.add(timer, forMode: .common)
            antsTimer = timer
        }
        updateSurroundColor()
        updateDrawableSize()
        if displayLink == nil {
            let link = displayLink(target: self, selector: #selector(displayLinkFired(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateDrawableSize()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateSurroundColor()
        setNeedsRender()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateDrawableSize()
    }

    private var backingScale: Double { Double(window?.backingScaleFactor ?? 2) }

    private func updateDrawableSize() {
        guard window != nil, bounds.width > 0, bounds.height > 0 else { return }
        metalLayer.contentsScale = backingScale
        metalLayer.drawableSize = CGSize(width: bounds.width * backingScale, height: bounds.height * backingScale)
        let size = Size2D(width: bounds.width, height: bounds.height)
        let canvasSize = editor.canvas.size
        let shouldFit = !hasFitted
        hasFitted = true
        editor.updateViewport { viewport in
            viewport.viewSize = size
            if shouldFit { viewport.fit(canvasSize, margin: 40) }
        }
        if inLiveResize, isWindowVisible { render() } else { setNeedsRender() }
    }

    private func updateSurroundColor() {
        var color = NSColor.gray
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let space = NSColorSpace(cgColorSpace: editor.canvas.colorSpace)
            color = space.flatMap { NSColor.underPageBackgroundColor.usingColorSpace($0) } ?? .gray
        }
        surroundColor = MTLClearColor(
            red: color.redComponent, green: color.greenComponent, blue: color.blueComponent, alpha: 1
        )
    }

    func setNeedsRender() {
        needsRender = true
        displayLink?.isPaused = false
    }

    /// Hidden windows never get their frames composited, so waiting on a drawable would stall.
    private var isWindowVisible: Bool {
        window?.occlusionState.contains(.visible) ?? false
    }

    @objc private func windowOcclusionChanged(_ notification: Notification) {
        if isWindowVisible, needsRender {
            displayLink?.isPaused = false
        }
    }

    @objc private func displayLinkFired(_ link: CADisplayLink) {
        if needsRender, isWindowVisible {
            render()
        } else {
            link.isPaused = true
        }
    }

    private func animateAnts() {
        if editor.hasSelection { setNeedsRender() }
    }

    private var renderScene: RenderScene {
        let selection = editor.canvas.selection
        let comparing = editor.comparison != nil
        let outline: (mask: SelectionMask, rect: IntRect)? =
            if comparing {
                nil
            } else if let preview = editor.marqueePreview {
                (preview, preview.bounds)
            } else if case .marquee(let mask) = selection {
                (mask, mask.bounds)
            } else if let floating = selection.floating {
                (floating.mask, floating.destination)
            } else {
                nil
            }
        return RenderScene(
            canvas: editor.canvas,
            viewport: editor.viewport,
            outline: outline,
            transparentKey: editor.selectionContext.transparentKey,
            smoothFloating: editor.smoothResize,
            overlay: comparing ? nil : editor.renderedPendingShape(),
            handlePoints: comparing ? [] : handlePoints(selection),
            roundHandlePoints: comparing ? [] : [editor.pendingShapeRotateHandle].compactMap { $0 },
            showsPixelGrid: editor.showsPixelGrid,
            antsPhase: Float((CACurrentMediaTime() * 4).truncatingRemainder(dividingBy: 2)),
            lines: comparing ? [] : overlayLines,
            highlights: redactionHighlights,
            comparison: comparisonScene
        )
    }

    /// The symmetry axes (faint) and the current measurement (accent color).
    private var overlayLines: [(from: Point2D, to: Point2D, color: SIMD4<Float>)] {
        var lines: [(from: Point2D, to: Point2D, color: SIMD4<Float>)] = []
        let width = Double(editor.canvas.size.width), height = Double(editor.canvas.size.height)
        let guide = SIMD4<Float>(0.1, 0.6, 0.9, 0.6)
        if editor.symmetry == .vertical || editor.symmetry == .both {
            lines.append((Point2D(x: width / 2, y: 0), Point2D(x: width / 2, y: height), guide))
        }
        if editor.symmetry == .horizontal || editor.symmetry == .both {
            lines.append((Point2D(x: 0, y: height / 2), Point2D(x: width, y: height / 2), guide))
        }
        let frameColor = SIMD4<Float>(0.2, 0.45, 0.95, 0.9)
        func frame(_ minX: Double, _ minY: Double, _ maxX: Double, _ maxY: Double, color: SIMD4<Float>? = nil) {
            let corners = [Point2D(x: minX, y: minY), Point2D(x: maxX, y: minY), Point2D(x: maxX, y: maxY), Point2D(x: minX, y: maxY)]
            for index in 0..<4 { lines.append((corners[index], corners[(index + 1) % 4], color ?? frameColor)) }
        }
        if let drag = editor.textDragFrame {
            frame(min(drag.start.x, drag.end.x), min(drag.start.y, drag.end.y), max(drag.start.x, drag.end.x), max(drag.start.y, drag.end.y))
        }
        if let box = editor.pendingTextFrame {
            // A little outside the text so the border doesn't touch the glyphs.
            let pad = 3 / editor.viewport.zoom
            frame(Double(box.minX) - pad, Double(box.minY) - pad, Double(box.maxX) + pad, Double(box.maxY) + pad)
        }
        for guide in editor.pendingShapeGuides {
            lines.append((guide.0, guide.1, SIMD4(0.2, 0.45, 0.95, 0.9)))
        }
        if showsEraserOutline, let hoverPoint {
            // Black on the eraser's edge and white just inside it, so it shows on any colors.
            // Zoomed out, a small eraser is drawn at least 8 points wide so it can still be seen.
            let square = EraserStroke.footprint(at: hoverPoint, size: editor.eraserSize)
            let zoom = editor.viewport.zoom
            let grow = max(0, 8 / zoom - Double(square.width)) / 2
            let minX = Double(square.minX) - grow, minY = Double(square.minY) - grow
            let maxX = Double(square.maxX) + grow, maxY = Double(square.maxY) + grow
            let inset = 1.5 / zoom
            frame(minX, minY, maxX, maxY, color: SIMD4(0, 0, 0, 1))
            frame(minX + inset, minY + inset, maxX - inset, maxY - inset, color: SIMD4(1, 1, 1, 1))
        }
        if let measurement = editor.measurement {
            let center = { (p: IntPoint) in Point2D(x: Double(p.x) + 0.5, y: Double(p.y) + 0.5) }
            lines.append((center(measurement.start), center(measurement.end), SIMD4(1, 0.25, 0.45, 1)))
        }
        return lines
    }

    private var redactionHighlights: [(rect: IntRect, active: Bool)] {
        guard let session = editor.autoRedact else { return [] }
        return session.matches.map { ($0.rect, !session.keptVisible.contains($0.id)) }
    }

    private var comparisonScene: (before: PixelBuffer, layout: Comparison.Layout, dividerX: Double)? {
        guard let comparison = editor.comparison, let before = editor.comparisonBaseline else { return nil }
        return (before, comparison.layout, comparison.divider * bounds.width)
    }

    // MARK: Text editing

    /// Shows, positions and styles the text box to match the editor's pending text, or removes it.
    private func syncTextEditor() {
        guard let pending = editor.pendingText else {
            if let textView {
                textView.removeFromSuperview()
                self.textView = nil
                appliedTextStyle = nil
                window?.makeFirstResponder(self)
            }
            return
        }
        let view: CanvasTextView
        if let textView {
            view = textView
        } else {
            view = CanvasTextView.make()
            view.delegate = self
            view.onCommit = { [weak self] in self?.editor.commitPendingText() }
            addSubview(view)
            textView = view
            window?.makeFirstResponder(view)
        }
        var style = editor.textSpec(for: pending)
        style.text = ""
        let zoom = editor.viewport.zoom
        if appliedTextStyle?.spec != style || appliedTextStyle?.zoom != zoom {
            view.apply(style, zoom: zoom, colorSpace: editor.canvas.colorSpace)
            appliedTextStyle = (style, zoom)
        }
        let origin = editor.viewport.viewPoint(fromImage: pending.origin)
        view.fit(at: NSPoint(x: origin.x, y: origin.y), wrapWidth: pending.wrapWidth.map { $0 * zoom }, minimumHeight: pending.minimumHeight * zoom)
    }

    private func handlePoints(_ selection: SelectionState) -> [Point2D] {
        if editor.pendingShape != nil { return editor.pendingShapeHandlePoints }
        guard editor.tool.isSelectionTool, editor.marqueePreview == nil, let rect = selection.bounds else { return [] }
        return SelectionHandle.allCases.map { $0.point(on: rect) }
    }

    private func render() {
        needsRender = false
        let inputTime = pendingInputTime
        pendingInputTime = nil
        let processingLatency = processingLatency
        let screenLatency = screenLatency
        let signpostState = Diagnostics.signposter.beginInterval("Render")
        renderer.render(
            renderScene,
            into: metalLayer,
            scale: backingScale,
            surround: surroundColor,
            onRendered: { renderedTime in
                if let inputTime { processingLatency.record(renderedTime - inputTime) }
            }
        ) { [weak self] presentedTime in
            // A zero time means the frame never reached the screen, e.g. the window was still ordering in.
            guard presentedTime > 0 else {
                Task { @MainActor in self?.frameFinished(shown: false) }
                return
            }
            if let inputTime {
                screenLatency.record(presentedTime - inputTime)
            }
            Task { @MainActor in self?.frameFinished(shown: true) }
        }
        Diagnostics.signposter.endInterval("Render", signpostState)
    }

    private func frameFinished(shown: Bool) {
        guard !hasPresented else { return }
        guard shown else {
            setNeedsRender()
            return
        }
        hasPresented = true
        Diagnostics.reportColdStartIfNeeded()
        onFirstFrame?()
    }

    // MARK: Input

    private func viewPoint(_ event: NSEvent) -> Point2D {
        let point = convert(event.locationInWindow, from: nil)
        return Point2D(x: point.x, y: point.y)
    }

    private func imagePoint(_ event: NSEvent) -> Point2D {
        editor.viewport.imagePoint(fromView: viewPoint(event))
    }

    private func noteInput(_ event: NSEvent) {
        pendingInputTime = min(pendingInputTime ?? event.timestamp, event.timestamp)
    }

    private func updatePointer(_ event: NSEvent) {
        let point = imagePoint(event)
        let pixel = IntPoint(x: Int(point.x.rounded(.down)), y: Int(point.y.rounded(.down)))
        editor.pointer = editor.canvas.bounds.contains(pixel) ? pixel : nil
        hoverPoint = point
        if editor.tool == .eraser { setNeedsRender() }
        if drag == nil { currentCursor(at: point).set() }
    }

    /// A circular-arrow pointer for the rotate handle (macOS has no built-in one).
    private static let rotateCursor: NSCursor = {
        let configuration = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        guard let symbol = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Rotate")?
            .withSymbolConfiguration(configuration) else { return .crosshair }
        let size = NSSize(width: 22, height: 22)
        let image = NSImage(size: size, flipped: false) { rect in
            // A white halo keeps the arrow visible on dark pixels.
            NSColor.white.setFill()
            NSBezierPath(ovalIn: rect).fill()
            symbol.draw(in: rect.insetBy(dx: 3, dy: 3))
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: size.width / 2, y: size.height / 2))
    }()

    /// Stands in for the pointer while the eraser's square outline shows where it is.
    private static let hiddenCursor = NSCursor(image: NSImage(size: NSSize(width: 1, height: 1)), hotSpot: .zero)

    private var showsEraserOutline: Bool {
        editor.tool == .eraser && !spaceHeld && editor.comparison == nil
    }

    private func currentCursor(at point: Point2D?) -> NSCursor {
        if spaceHeld { return .openHand }
        if let point {
            let view = editor.viewport.viewPoint(fromImage: point)
            if let handle = editor.selectionHandle(atView: view) {
                return NSCursor.frameResize(position: handle.cursorPosition, directions: .all)
            }
            switch editor.shapeHandle(atView: view) {
            case .box(let handle): return NSCursor.frameResize(position: handle.cursorPosition, directions: .all)
            case .rotate: return Self.rotateCursor
            case .start, .end, .vertex: return .crosshair
            case nil: if editor.pendingShapeContains(point) { return .openHand }
            }
        }
        if editor.tool.isSelectionTool, let point, editor.selectionContains(point) { return .openHand }
        if editor.tool == .text { return .iBeam }
        if showsEraserOutline { return Self.hiddenCursor }
        return .crosshair
    }

    private func dragModifiers(_ event: NSEvent) -> DragModifiers {
        DragModifiers(shift: event.modifierFlags.contains(.shift), option: event.modifierFlags.contains(.option))
    }

    private func beginDrag(_ event: NSEvent, secondary: Bool) {
        window?.makeFirstResponder(self)
        // Before/After is view-only: a drag moves the split's divider.
        if editor.comparison != nil {
            drag = .divider
            moveDivider(event)
            return
        }
        if spaceHeld {
            drag = .pan(last: convert(event.locationInWindow, from: nil))
            NSCursor.closedHand.set()
            return
        }
        let point = imagePoint(event)
        switch editor.tool {
        case let tool where tool.isSelectionTool:
            guard !secondary else { return }
            drag = .select(last: point)
            if let handle = editor.selectionHandle(atView: viewPoint(event)) {
                editor.beginResize(handle, at: point)
                return
            }
            editor.beginSelectionDrag(at: point, modifiers: dragModifiers(event))
            if editor.selectionContains(point) { NSCursor.closedHand.set() }
        case .measure:
            drag = .measure(start: point)
            editor.measure(from: point, to: point)
        case .gradient:
            drag = .gradient
            editor.beginGradient(at: point, secondary: secondary)
        case .shape:
            drag = .shape
            editor.beginShapeDrag(at: point, viewPoint: viewPoint(event), secondary: secondary, clickCount: event.clickCount)
        case .text:
            // A click away from an open text box places it; the next click starts a new one.
            if editor.pendingText != nil {
                editor.commitPendingText()
            } else if !secondary {
                drag = .text(start: point)
            }
        case .fill:
            editor.fill(at: point, secondary: secondary)
        case .eyedropper:
            editor.pickColor(at: point, secondary: secondary, allLayers: event.modifierFlags.contains(.option))
        default:
            drag = secondary ? .secondary : .primary
            noteInput(event)
            editor.beginStroke(at: point, secondary: secondary)
        }
        updatePointer(event)
    }

    private func continueDrag(_ event: NSEvent) {
        switch drag {
        case .pan(let last):
            let point = convert(event.locationInWindow, from: nil)
            editor.updateViewport { $0.pan(byViewDeltaX: point.x - last.x, y: point.y - last.y) }
            drag = .pan(last: point)
        case .divider:
            moveDivider(event)
        case .measure(let start):
            editor.measure(from: start, to: imagePoint(event))
            updatePointer(event)
        case .gradient:
            editor.continueGradient(to: imagePoint(event))
            updatePointer(event)
        case .shape:
            editor.continueShapeDrag(to: imagePoint(event), shiftDown: event.modifierFlags.contains(.shift))
            updatePointer(event)
        case .text(let start):
            editor.updateTextDragFrame(from: start, to: imagePoint(event))
            updatePointer(event)
        case .select:
            let point = imagePoint(event)
            drag = .select(last: point)
            editor.continueSelectionDrag(to: point, shiftDown: event.modifierFlags.contains(.shift))
            updatePointer(event)
        case .primary, .secondary:
            noteInput(event)
            editor.continueStroke(to: imagePoint(event), constrain: event.modifierFlags.contains(.shift))
            updatePointer(event)
        case nil:
            break
        }
    }

    private func endDrag(_ event: NSEvent) {
        switch drag {
        case .pan:
            break
        case .divider, .measure:
            break
        case .gradient:
            editor.endGradient()
        case .shape:
            editor.endShapeDrag()
        case .text(let start):
            let end = imagePoint(event)
            // Dragging out a box sets its width (lines wrap) and height; a plain click lets the text run on.
            let width = abs(end.x - start.x)
            let dragged = width * editor.viewport.zoom > 8
            drag = nil
            editor.beginText(
                at: Point2D(x: min(start.x, end.x), y: dragged ? min(start.y, end.y) : start.y),
                wrapWidth: dragged ? width : nil,
                minimumHeight: dragged ? abs(end.y - start.y) : 0
            )
            return
        case .select:
            editor.endSelectionDrag(at: imagePoint(event))
        case .primary, .secondary:
            editor.endStroke()
        case nil:
            return
        }
        drag = nil
        currentCursor(at: imagePoint(event)).set()
    }

    private func moveDivider(_ event: NSEvent) {
        guard editor.comparison?.layout == .split, bounds.width > 0 else { return }
        editor.comparison?.divider = min(1, max(0, viewPoint(event).x / bounds.width))
    }

    override func mouseDown(with event: NSEvent) { beginDrag(event, secondary: false) }
    override func mouseDragged(with event: NSEvent) { continueDrag(event) }
    override func mouseUp(with event: NSEvent) { endDrag(event) }

    override func rightMouseDown(with event: NSEvent) { beginDrag(event, secondary: true) }
    override func rightMouseDragged(with event: NSEvent) { continueDrag(event) }
    override func rightMouseUp(with event: NSEvent) { endDrag(event) }

    override func mouseMoved(with event: NSEvent) { updatePointer(event) }
    override func mouseExited(with event: NSEvent) {
        editor.pointer = nil
        hoverPoint = nil
        setNeedsRender()
    }

    override func cursorUpdate(with event: NSEvent) {
        currentCursor(at: imagePoint(event)).set()
    }

    /// Pressing or releasing Shift mid-drag changes the marquee's constraint without moving the mouse.
    override func flagsChanged(with event: NSEvent) {
        if case .select(let last) = drag {
            editor.continueSelectionDrag(to: last, shiftDown: event.modifierFlags.contains(.shift))
        }
        super.flagsChanged(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        let multiplier = event.hasPreciseScrollingDeltas ? 1.0 : 10.0
        editor.updateViewport {
            $0.pan(byViewDeltaX: event.scrollingDeltaX * multiplier, y: event.scrollingDeltaY * multiplier)
        }
    }

    override func magnify(with event: NSEvent) {
        let anchor = viewPoint(event)
        editor.updateViewport { $0.setZoom($0.zoom * (1 + event.magnification), anchor: anchor) }
    }

    override func keyDown(with event: NSEvent) {
        handleKey(event)
        // Tool and size keys change the pointer and the eraser outline without the mouse moving.
        if drag == nil, let hoverPoint {
            currentCursor(at: hoverPoint).set()
            setNeedsRender()
        }
    }

    private func handleKey(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        let plain = modifiers.isEmpty
        let step = modifiers == .shift ? 10 : 1

        let resizeStep = modifiers == [.command, .shift] ? 10 : 1
        let resizing = modifiers == .command || modifiers == [.command, .shift]

        switch event.specialKey {
        case .leftArrow where resizing:
            editor.resizeMarquee(byWidth: -resizeStep, height: 0)
        case .rightArrow where resizing:
            editor.resizeMarquee(byWidth: resizeStep, height: 0)
        case .upArrow where resizing:
            editor.resizeMarquee(byWidth: 0, height: -resizeStep)
        case .downArrow where resizing:
            editor.resizeMarquee(byWidth: 0, height: resizeStep)
        case .leftArrow where plain || modifiers == .shift:
            nudge(dx: -step, dy: 0, event)
        case .rightArrow where plain || modifiers == .shift:
            nudge(dx: step, dy: 0, event)
        case .upArrow where plain || modifiers == .shift:
            nudge(dx: 0, dy: -step, event)
        case .downArrow where plain || modifiers == .shift:
            nudge(dx: 0, dy: step, event)
        case .carriageReturn where plain, .enter where plain:
            if editor.pendingShape?.isBuilding == true {
                editor.finishBuilding()
            } else if editor.pendingShape != nil {
                editor.commitPendingShape()
            } else {
                editor.deselect()
            }
        case .delete where plain, .deleteForward where plain, .backspace where plain:
            if editor.hasSelection { editor.deleteSelection() } else { super.keyDown(with: event) }
        default:
            switch (event.charactersIgnoringModifiers, plain) {
            case ("\u{1b}", true):
                if editor.pendingShape != nil { editor.cancelPendingShape() } else { editor.deselect() }
            case (" ", true):
                spaceHeld = true
                if drag == nil { NSCursor.openHand.set() }
            case ("x", true):
                editor.swapColors()
            case ("d", true):
                editor.resetColors()
            case ("p", true): editor.selectTool(.pencil)
            case ("b", true): editor.selectTool(.brush)
            case ("e", true): editor.selectTool(.eraser)
            case ("g", true): editor.selectTool(.fill)
            case ("i", true): editor.selectTool(.eyedropper)
            case ("m", true): editor.selectTool(.rectangleSelect)
            case ("l", true): editor.selectTool(.lassoSelect)
            case ("u", true): editor.selectTool(.shape)
            case ("t", true): editor.selectTool(.text)
            case ("w", true): editor.selectTool(.magicWand)
            case ("r", true): editor.selectTool(.measure)
            case ("[", true): editor.adjustToolSize(larger: false)
            case ("]", true): editor.adjustToolSize(larger: true)
            default:
                super.keyDown(with: event)
            }
        }
    }

    private func nudge(dx: Int, dy: Int, _ event: NSEvent) {
        guard editor.hasSelection else {
            super.keyDown(with: event)
            return
        }
        editor.nudgeSelection(dx: dx, dy: dy)
    }

    override func keyUp(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " {
            spaceHeld = false
            if drag == nil { currentCursor(at: hoverPoint).set() }
            setNeedsRender()
        } else {
            super.keyUp(with: event)
        }
    }
}

private extension SelectionHandle {
    var cursorPosition: NSCursor.FrameResizePosition {
        switch self {
        case .topLeft: .topLeft
        case .top: .top
        case .topRight: .topRight
        case .right: .right
        case .bottomRight: .bottomRight
        case .bottom: .bottom
        case .bottomLeft: .bottomLeft
        case .left: .left
        }
    }
}

extension CanvasView: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        guard let textView else { return }
        editor.updatePendingText(textView.string)
        syncTextEditor()
    }
}
