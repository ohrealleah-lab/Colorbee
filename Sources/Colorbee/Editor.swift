import ColorbeeCore
import Foundation
import Observation

enum DocumentChange {
    case done
    case undone
    case redone
}

/// Per-document editing state: the canvas, its history, tool settings and the view mapping.
@MainActor
@Observable
final class Editor {
    let canvas: Canvas
    @ObservationIgnored let history: History

    var color1: Pixel = .black
    var color2: Pixel = .white
    var brushDiameter: Double = 5
    private(set) var viewport = Viewport()
    var pointer: IntPoint?

    @ObservationIgnored var onRender: () -> Void = {}
    @ObservationIgnored var onDocumentChange: (DocumentChange) -> Void = { _ in }
    @ObservationIgnored private var activeStroke: (edit: Edit, stroke: RoundBrushStroke)?

    init(canvas: Canvas) {
        self.canvas = canvas
        history = History(byteBudget: Editor.historyByteBudget)
    }

    private static var historyByteBudget: Int {
        Int(min(UInt64(512 << 20), ProcessInfo.processInfo.physicalMemory / 10))
    }

    // MARK: Drawing

    func beginStroke(at point: Point2D, secondary: Bool) {
        endStroke()
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
        if history.commit(edit) { onDocumentChange(.done) }
    }

    /// Pastes at the top-left of the visible part of the canvas.
    func paste(_ image: PixelBuffer) {
        endStroke()
        let visibleTopLeft = viewport.imagePoint(fromView: .zero)
        let origin = IntPoint(
            x: min(max(0, Int(visibleTopLeft.x.rounded(.down))), canvas.size.width - 1),
            y: min(max(0, Int(visibleTopLeft.y.rounded(.down))), canvas.size.height - 1)
        )
        let edit = history.beginEdit("Paste", on: canvas)
        Compositing.draw(image, at: origin, onto: canvas.activeLayer, edit: edit)
        if history.commit(edit) {
            onDocumentChange(.done)
            onRender()
        }
    }

    // MARK: Undo

    var undoActionName: String? { history.undoActionName }
    var redoActionName: String? { history.redoActionName }

    func undo() {
        endStroke()
        guard history.undo(on: canvas) != nil else { return }
        onDocumentChange(.undone)
        onRender()
    }

    func redo() {
        endStroke()
        guard history.redo(on: canvas) != nil else { return }
        onDocumentChange(.redone)
        onRender()
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

    func flattenedPNG() throws -> Data {
        try ImageCodec.encodePNG(canvas.flattened(), colorSpace: canvas.colorSpace)
    }
}
