import CoreGraphics
import Testing
@testable import ColorbeeCore

/// Remove Red-Eye (FR-9.5), on a made-up eye: a red pupil with a white highlight, in a brown iris.
struct RedEyeTests {
    private let red = Pixel(r: 200, g: 30, b: 40)
    private let iris = Pixel(r: 110, g: 75, b: 50)

    private func eye() -> (Canvas, History) {
        let canvas = Canvas(size: IntSize(width: 80, height: 60), colorSpace: Canvas.defaultColorSpace, background: Pixel(r: 230, g: 190, b: 170))
        canvas.activeLayer.buffer.fill(iris, in: IntRect(x: 25, y: 15, width: 30, height: 30))
        canvas.activeLayer.buffer.fill(red, in: IntRect(x: 32, y: 22, width: 16, height: 16))
        canvas.activeLayer.buffer.fill(.white, in: IntRect(x: 36, y: 25, width: 3, height: 3))
        return (canvas, History(byteBudget: .max))
    }

    @Test func aRedPupilTurnsDarkAndKeepsItsHighlight() {
        let (canvas, history) = eye()
        let edit = history.beginEdit("Remove Red-Eye", on: canvas)
        #expect(RedEye.fix([RedEye.Eye(center: Point2D(x: 40, y: 30), radius: 15)], in: canvas.activeLayer, edit: edit))
        #expect(history.commit(edit))
        let pupil = canvas.activeLayer.buffer[44, 34]
        #expect(pupil == Pixel(r: 35, g: 30, b: 40))
        #expect(canvas.activeLayer.buffer[37, 26] == .white)
        // The brown iris isn't red enough to change, and nothing outside the eye does.
        #expect(canvas.activeLayer.buffer[27, 30] == iris)
        #expect(canvas.activeLayer.buffer[5, 5] == Pixel(r: 230, g: 190, b: 170))
        history.undo(on: canvas)
        #expect(canvas.activeLayer.buffer[44, 34] == red)
    }

    @Test func withASelectionOnlyRedPixelsInsideItChange() throws {
        let (canvas, history) = eye()
        let mask = try #require(SelectionMask.rectangle(IntRect(x: 30, y: 20, width: 10, height: 20), clippedTo: canvas.bounds))
        let edit = history.beginEdit("Remove Red-Eye", on: canvas)
        #expect(RedEye.fix(in: mask, layer: canvas.activeLayer, edit: edit))
        #expect(canvas.activeLayer.buffer[34, 34].r < 60)
        #expect(canvas.activeLayer.buffer[44, 34] == red)
    }

    @Test func anImageWithoutRedEyeDoesntChange() {
        let canvas = Canvas(size: IntSize(width: 40, height: 40), colorSpace: Canvas.defaultColorSpace, background: Pixel(r: 230, g: 190, b: 170))
        let history = History(byteBudget: .max)
        let edit = history.beginEdit("Remove Red-Eye", on: canvas)
        #expect(!RedEye.fix([RedEye.Eye(center: Point2D(x: 20, y: 20), radius: 15)], in: canvas.activeLayer, edit: edit))
        #expect(!history.commit(edit))
    }

    @Test func anEyeOffTheImageIsSkipped() {
        let (canvas, history) = eye()
        let before = canvas.activeLayer.buffer.contentHash()
        let edit = history.beginEdit("Remove Red-Eye", on: canvas)
        #expect(!RedEye.fix([RedEye.Eye(center: Point2D(x: -50, y: -50), radius: 10)], in: canvas.activeLayer, edit: edit))
        #expect(!history.commit(edit))
        #expect(canvas.activeLayer.buffer.contentHash() == before)
    }

    @Test func aSelectionWithNoRedInItChangesNothing() throws {
        let (canvas, history) = eye()
        let mask = try #require(SelectionMask.rectangle(IntRect(x: 0, y: 0, width: 10, height: 10), clippedTo: canvas.bounds))
        let edit = history.beginEdit("Remove Red-Eye", on: canvas)
        #expect(!RedEye.fix(in: mask, layer: canvas.activeLayer, edit: edit))
        #expect(!history.commit(edit))
    }

    @Test func onlyStronglyRedPixelsDarkenAndTheEdgeFadesIn() {
        // Very red: red comes all the way down to the average of green and blue.
        #expect(RedEye.darkened(Pixel(r: 200, g: 30, b: 40)) == Pixel(r: 35, g: 30, b: 40))
        // Just past the threshold: a quarter of the way there, so a pupil's edge stays soft.
        #expect(RedEye.darkened(Pixel(r: 100, g: 50, b: 40, a: 90)) == Pixel(r: 86, g: 50, b: 40, a: 90))
        // Too dark, not the reddest channel, or only reddish like skin: left alone.
        #expect(RedEye.darkened(Pixel(r: 50, g: 0, b: 0)) == nil)
        #expect(RedEye.darkened(Pixel(r: 100, g: 100, b: 0)) == nil)
        #expect(RedEye.darkened(Pixel(r: 100, g: 60, b: 60)) == nil)
        // So close to the threshold that the change rounds away.
        #expect(RedEye.darkened(Pixel(r: 251, g: 138, b: 138)) == nil)
    }

    // The circle drawn around each eye Vision finds (Vision itself only runs in the app).

    private func close(_ eye: RedEye.Eye?, _ x: Double, _ y: Double, _ radius: Double) -> Bool {
        guard let eye else { return false }
        return abs(eye.center.x - x) < 1e-9 && abs(eye.center.y - y) < 1e-9 && abs(eye.radius - radius) < 1e-9
    }

    @Test func anEyeCircleCentersOnThePupilWithYFlipped() {
        // A wide eye 25 across and 10 high: the radius follows the width.
        let outline = [CGPoint(x: 10, y: 60), CGPoint(x: 35, y: 60), CGPoint(x: 20, y: 65), CGPoint(x: 20, y: 55)]
        let eye = RedEye.eye(outline: outline, pupil: CGPoint(x: 21, y: 61), imageHeight: 100)
        #expect(close(eye, 21, 39, 8))
    }

    @Test func withoutAPupilTheEyeCircleCentersOnTheOutline() {
        // A tall eye 10 across and 20 high: the radius follows the height.
        let outline = [CGPoint(x: 10, y: 30), CGPoint(x: 20, y: 30), CGPoint(x: 15, y: 40), CGPoint(x: 15, y: 20)]
        #expect(close(RedEye.eye(outline: outline, pupil: nil, imageHeight: 50), 15, 20, 12))
    }

    @Test func aTinyEyeStillGetsACircleOfThreePixels() {
        let outline = [CGPoint(x: 5, y: 5), CGPoint(x: 6, y: 5)]
        #expect(close(RedEye.eye(outline: outline, pupil: nil, imageHeight: 10), 5.5, 5, 3))
        #expect(RedEye.eye(outline: [], pupil: CGPoint(x: 1, y: 1), imageHeight: 10) == nil)
    }
}
