import Foundation

/// Maps between view points and image pixels. `center` is the image position shown at the middle of the view.
public struct Viewport: Equatable, Sendable {
    public static let minZoom = 0.125
    public static let maxZoom = 32.0
    public static let zoomSteps: [Double] = [0.125, 0.25, 1.0 / 3, 0.5, 2.0 / 3, 1, 1.5, 2, 3, 4, 6, 8, 12, 16, 24, 32]

    public var zoom: Double
    public var center: Point2D
    public var viewSize: Size2D

    public init(zoom: Double = 1, center: Point2D = .zero, viewSize: Size2D = .zero) {
        self.zoom = zoom
        self.center = center
        self.viewSize = viewSize
    }

    public func imagePoint(fromView point: Point2D) -> Point2D {
        Point2D(
            x: (point.x - viewSize.width / 2) / zoom + center.x,
            y: (point.y - viewSize.height / 2) / zoom + center.y
        )
    }

    public func viewPoint(fromImage point: Point2D) -> Point2D {
        Point2D(
            x: (point.x - center.x) * zoom + viewSize.width / 2,
            y: (point.y - center.y) * zoom + viewSize.height / 2
        )
    }

    /// Changes the zoom while keeping the image point under `anchor` (a view point) fixed.
    public mutating func setZoom(_ newZoom: Double, anchor: Point2D) {
        let fixed = imagePoint(fromView: anchor)
        zoom = min(max(newZoom, Self.minZoom), Self.maxZoom)
        center = Point2D(
            x: fixed.x - (anchor.x - viewSize.width / 2) / zoom,
            y: fixed.y - (anchor.y - viewSize.height / 2) / zoom
        )
    }

    /// Moves the image by a distance in view points.
    public mutating func pan(byViewDeltaX dx: Double, y dy: Double) {
        center.x -= dx / zoom
        center.y -= dy / zoom
    }

    /// Centers the image and zooms out until it fits inside the view, never enlarging past 100%.
    public mutating func fit(_ imageSize: IntSize, margin: Double) {
        let availableWidth = max(1, viewSize.width - 2 * margin)
        let availableHeight = max(1, viewSize.height - 2 * margin)
        let fitZoom = min(1, availableWidth / Double(imageSize.width), availableHeight / Double(imageSize.height))
        zoom = min(max(fitZoom, Self.minZoom), Self.maxZoom)
        center = Point2D(x: Double(imageSize.width) / 2, y: Double(imageSize.height) / 2)
    }

    /// Where `zoom` sits on the status-bar slider, 0...1. The slider is logarithmic, so doubling
    /// the zoom always moves it the same distance.
    public static func sliderPosition(forZoom zoom: Double) -> Double {
        let clamped = min(max(zoom, minZoom), maxZoom)
        return log(clamped / minZoom) / log(maxZoom / minZoom)
    }

    public static func zoom(forSliderPosition position: Double) -> Double {
        minZoom * pow(maxZoom / minZoom, min(1, max(0, position)))
    }

    public func nextZoomStep(zoomingIn: Bool) -> Double {
        if zoomingIn {
            return Self.zoomSteps.first { $0 > zoom * 1.0001 } ?? Self.maxZoom
        }
        return Self.zoomSteps.last { $0 < zoom / 1.0001 } ?? Self.minZoom
    }
}
