import AppKit
import ColorbeeCore
import Metal
import QuartzCore

/// The drawing surface: renders the canvas with Metal and turns mouse, trackpad and keys into edits.
final class CanvasView: NSView {
    private enum Drag {
        case primary
        case secondary
        case pan(last: NSPoint)
    }

    var onFirstFrame: (() -> Void)?
    let latency = LatencyStats()

    private let editor: Editor
    private let renderer = Renderer.shared
    private var displayLink: CADisplayLink?
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
        editor.onRender = { [weak self] in self?.setNeedsRender() }
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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            displayLink?.invalidate()
            displayLink = nil
            return
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
        if inLiveResize { render() } else { setNeedsRender() }
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

    @objc private func displayLinkFired(_ link: CADisplayLink) {
        if needsRender {
            render()
        } else {
            link.isPaused = true
        }
    }

    private func render() {
        needsRender = false
        let inputTime = pendingInputTime
        pendingInputTime = nil
        let latency = latency
        let signpostState = Diagnostics.signposter.beginInterval("Render")
        renderer.render(
            editor.canvas,
            viewport: editor.viewport,
            into: metalLayer,
            scale: backingScale,
            surround: surroundColor
        ) { [weak self] presentedTime in
            // A zero time means the frame never reached the screen, e.g. the window was still ordering in.
            guard presentedTime > 0 else {
                Task { @MainActor in self?.frameFinished(shown: false) }
                return
            }
            if let inputTime {
                latency.record(presentedTime - inputTime)
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
    }

    private func beginDrag(_ event: NSEvent, secondary: Bool) {
        window?.makeFirstResponder(self)
        if spaceHeld {
            drag = .pan(last: convert(event.locationInWindow, from: nil))
            NSCursor.closedHand.set()
            return
        }
        drag = secondary ? .secondary : .primary
        noteInput(event)
        editor.beginStroke(at: imagePoint(event), secondary: secondary)
        updatePointer(event)
    }

    private func continueDrag(_ event: NSEvent) {
        switch drag {
        case .pan(let last):
            let point = convert(event.locationInWindow, from: nil)
            editor.updateViewport { $0.pan(byViewDeltaX: point.x - last.x, y: point.y - last.y) }
            drag = .pan(last: point)
        case .primary, .secondary:
            noteInput(event)
            editor.continueStroke(to: imagePoint(event))
                updatePointer(event)
        case nil:
            break
        }
    }

    private func endDrag() {
        if case .pan = drag {
            (spaceHeld ? NSCursor.openHand : NSCursor.crosshair).set()
        } else {
            editor.endStroke()
        }
        drag = nil
    }

    override func mouseDown(with event: NSEvent) { beginDrag(event, secondary: false) }
    override func mouseDragged(with event: NSEvent) { continueDrag(event) }
    override func mouseUp(with event: NSEvent) { endDrag() }

    override func rightMouseDown(with event: NSEvent) { beginDrag(event, secondary: true) }
    override func rightMouseDragged(with event: NSEvent) { continueDrag(event) }
    override func rightMouseUp(with event: NSEvent) { endDrag() }

    override func mouseMoved(with event: NSEvent) { updatePointer(event) }
    override func mouseExited(with event: NSEvent) { editor.pointer = nil }

    override func cursorUpdate(with event: NSEvent) {
        (spaceHeld ? NSCursor.openHand : NSCursor.crosshair).set()
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
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
        switch (event.charactersIgnoringModifiers, modifiers.isEmpty) {
        case (" ", true):
            spaceHeld = true
            if drag == nil { NSCursor.openHand.set() }
        case ("x", true):
            editor.swapColors()
        default:
            super.keyDown(with: event)
        }
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
