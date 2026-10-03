import Testing
@testable import ColorbeeCore

struct ViewportTests {
    @Test func zoomSliderIsLogarithmic() {
        #expect(Viewport.sliderPosition(forZoom: Viewport.minZoom) == 0)
        #expect(Viewport.sliderPosition(forZoom: Viewport.maxZoom) == 1)
        // 12.5% to 3200% is 8 doublings, so 100% (3 doublings up) sits at 3/8.
        #expect(abs(Viewport.sliderPosition(forZoom: 1) - 0.375) < 1e-9)
        #expect(abs(Viewport.zoom(forSliderPosition: 0.375) - 1) < 1e-9)
        #expect(Viewport.zoom(forSliderPosition: 2) == Viewport.maxZoom)
    }

    private func isClose(_ a: Point2D, _ b: Point2D) -> Bool {
        abs(a.x - b.x) < 1e-9 && abs(a.y - b.y) < 1e-9
    }

    @Test func viewAndImagePointsRoundTrip() {
        let viewport = Viewport(zoom: 2.5, center: Point2D(x: 300, y: 200), viewSize: Size2D(width: 800, height: 600))
        let point = Point2D(x: 123.25, y: 456.5)
        #expect(isClose(viewport.imagePoint(fromView: viewport.viewPoint(fromImage: point)), point))
        #expect(isClose(viewport.viewPoint(fromImage: viewport.center), Point2D(x: 400, y: 300)))
    }

    @Test func zoomKeepsTheAnchorFixed() {
        var viewport = Viewport(zoom: 1, center: Point2D(x: 100, y: 100), viewSize: Size2D(width: 400, height: 300))
        let anchor = Point2D(x: 50, y: 60)
        let before = viewport.imagePoint(fromView: anchor)
        viewport.setZoom(4, anchor: anchor)
        #expect(viewport.zoom == 4)
        #expect(isClose(viewport.imagePoint(fromView: anchor), before))
    }

    @Test func zoomIsClamped() {
        var viewport = Viewport(viewSize: Size2D(width: 100, height: 100))
        viewport.setZoom(1000, anchor: .zero)
        #expect(viewport.zoom == Viewport.maxZoom)
        viewport.setZoom(0.001, anchor: .zero)
        #expect(viewport.zoom == Viewport.minZoom)
    }

    @Test func fitShrinksLargeImagesButNeverEnlarges() {
        var viewport = Viewport(viewSize: Size2D(width: 1000, height: 800))
        viewport.fit(IntSize(width: 1920, height: 1080), margin: 40)
        #expect(abs(viewport.zoom - 920.0 / 1920.0) < 1e-9)
        #expect(viewport.center == Point2D(x: 960, y: 540))

        viewport.fit(IntSize(width: 100, height: 100), margin: 40)
        #expect(viewport.zoom == 1)
    }

    @Test func zoomStepsMoveToTheNextPreset() {
        let viewport = Viewport(zoom: 1)
        #expect(viewport.nextZoomStep(zoomingIn: true) == 1.5)
        #expect(viewport.nextZoomStep(zoomingIn: false) == 2.0 / 3)
    }
}
