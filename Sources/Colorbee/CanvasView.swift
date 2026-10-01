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
        let outline: (mask: SelectionMask, rect: IntRect)? =
            if let preview = editor.marqueePreview {
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
            overlay: editor.renderedPendingShape(),
            handlePoints: handlePoints(selection),
            showsPixelGrid: editor.showsPixelGrid,
            antsPhase: Float((CACurrentMediaTime() * 4).truncatingRemainder(dividingBy: 2))
        )
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
        view.fit(at: NSPoint(x: origin.x, y: origin.y), wrapWidth: pending.wrapWidth.map { $0 * zoom })
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
        if drag == nil { currentCursor(at: point).set() }
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
            case .start, .end: return .pointingHand
            case nil: if editor.pendingShapeContains(point) { return .openHand }
            }
        }
        if editor.tool.isSelectionTool, let point, editor.selectionContains(point) { return .openHand }
        if editor.tool == .text { return .iBeam }
        return .crosshair
    }

    private func dragModifiers(_ event: NSEvent) -> DragModifiers {
        DragModifiers(shift: event.modifierFlags.contains(.shift), option: event.modifierFlags.contains(.option))
    }

    private func beginDrag(_ event: NSEvent, secondary: Bool) {
        window?.makeFirstResponder(self)
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
        case .shape:
            drag = .shape
            editor.beginShapeDrag(at: point, viewPoint: viewPoint(event), secondary: secondary)
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
        case .shape:
            editor.continueShapeDrag(to: imagePoint(event), shiftDown: event.modifierFlags.contains(.shift))
            updatePointer(event)
        case .text:
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
        case .shape:
            editor.endShapeDrag()
        case .text(let start):
            let end = imagePoint(event)
            // Dragging sets the wrap width; a plain click lets the text run on.
            let width = abs(end.x - start.x)
            let wrapWidth = width * editor.viewport.zoom > 8 ? width : nil
            drag = nil
            editor.beginText(at: Point2D(x: min(start.x, end.x), y: start.y), wrapWidth: wrapWidth)
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

    override func mouseDown(with event: NSEvent) { beginDrag(event, secondary: false) }
    override func mouseDragged(with event: NSEvent) { continueDrag(event) }
    override func mouseUp(with event: NSEvent) { endDrag(event) }

    override func rightMouseDown(with event: NSEvent) { beginDrag(event, secondary: true) }
    override func rightMouseDragged(with event: NSEvent) { continueDrag(event) }
    override func rightMouseUp(with event: NSEvent) { endDrag(event) }

    override func mouseMoved(with event: NSEvent) { updatePointer(event) }
    override func mouseExited(with event: NSEvent) { editor.pointer = nil }

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
            if editor.pendingShape != nil { editor.commitPendingShape() } else { editor.deselect() }
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
            if drag == nil { NSCursor.crosshair.set() }
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
