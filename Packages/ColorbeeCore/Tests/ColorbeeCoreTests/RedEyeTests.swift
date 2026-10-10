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
}
