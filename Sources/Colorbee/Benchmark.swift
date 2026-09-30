import AppKit
import ColorbeeCore
import QuartzCore

/// Scripted performance run, enabled with `-ColorbeeBenchmark YES`.
/// Optional: `-BenchmarkCanvas <side px>` for a square canvas, `-BenchmarkBrush <diameter px>`.
@MainActor
enum Benchmark {
    private static var hasStarted = false
    private static let defaults = UserDefaults.standard

    static var isEnabled: Bool { defaults.bool(forKey: "ColorbeeBenchmark") }

    static var canvasSize: IntSize? {
        let side = defaults.integer(forKey: "BenchmarkCanvas")
        return isEnabled && side > 0 ? IntSize(width: side, height: side) : nil
    }

    private static var brushDiameter: Double {
        let diameter = defaults.double(forKey: "BenchmarkBrush")
        return diameter > 0 ? diameter : 5
    }

    static func startIfRequested(window: NSWindow, canvasView: CanvasView, editor: Editor) {
        guard isEnabled, !hasStarted else { return }
        hasStarted = true
        Task {
            await run(window: window, canvasView: canvasView, editor: editor)
            exit(0)
        }
    }

    private static func run(window: NSWindow, canvasView: CanvasView, editor: Editor) async {
        let size = editor.canvas.size
        Diagnostics.report("Benchmark: \(size.width)×\(size.height) canvas, \(Int(brushDiameter)) px brush, zoom \(Int(editor.viewport.zoom * 100))%")
        try? await Task.sleep(for: .milliseconds(500))
        Diagnostics.report("Memory at idle: \(Diagnostics.megabytes(Diagnostics.physicalFootprint()))")

        editor.brushDiameter = brushDiameter
        _ = canvasView.latency.drain()

        // Events go straight to the view: a terminal-launched app isn't frontmost, and the window
        // would swallow the first click as an activation click.
        let path = strokePath(in: canvasView, editor: editor, samples: 360)
        if let down = event(.leftMouseDown, at: path[0], window: window, view: canvasView) {
            canvasView.mouseDown(with: down)
        }
        for point in path.dropFirst() {
            try? await Task.sleep(for: .milliseconds(8))
            if let dragged = event(.leftMouseDragged, at: point, window: window, view: canvasView) {
                canvasView.mouseDragged(with: dragged)
            }
        }
        if let up = event(.leftMouseUp, at: path[path.count - 1], window: window, view: canvasView) {
            canvasView.mouseUp(with: up)
        }
        try? await Task.sleep(for: .milliseconds(300))
        Diagnostics.report("Stroke latency (input → on screen): \(LatencyStats.summary(canvasView.latency.drain()))")

        let clock = ContinuousClock()
        let undoTime = clock.measure { editor.undo() }
        let redoTime = clock.measure { editor.redo() }
        Diagnostics.report("Undo: \(format(undoTime)) · Redo: \(format(redoTime))")
        Diagnostics.report("Memory after stroke: \(Diagnostics.megabytes(Diagnostics.physicalFootprint()))")
    }

    /// A zigzag across the visible part of the canvas, in view coordinates.
    private static func strokePath(in view: NSView, editor: Editor, samples: Int) -> [NSPoint] {
        let viewport = editor.viewport
        let topLeft = viewport.viewPoint(fromImage: .zero)
        let bottomRight = viewport.viewPoint(fromImage: Point2D(x: Double(editor.canvas.size.width), y: Double(editor.canvas.size.height)))
        let canvasRect = NSRect(x: topLeft.x, y: topLeft.y, width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y)
        let area = canvasRect.intersection(view.bounds).insetBy(dx: 20, dy: 20)
        return (0..<samples).map { index in
            let t = Double(index) / Double(samples - 1)
            let sweep = (t * 3).truncatingRemainder(dividingBy: 1)
            return NSPoint(x: area.minX + area.width * sweep, y: area.midY + sin(t * 40) * area.height * 0.4)
        }
    }

    private static func event(_ type: NSEvent.EventType, at point: NSPoint, window: NSWindow, view: NSView) -> NSEvent? {
        NSEvent.mouseEvent(
            with: type,
            location: view.convert(point, to: nil),
            modifierFlags: [],
            timestamp: CACurrentMediaTime(),
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )
    }

    private static func format(_ duration: Duration) -> String {
        let (seconds, attoseconds) = duration.components
        return String(format: "%.2f ms", Double(seconds) * 1000 + Double(attoseconds) / 1e15)
    }
}
