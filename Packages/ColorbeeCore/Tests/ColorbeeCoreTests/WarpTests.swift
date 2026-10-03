import Foundation
import Testing
@testable import ColorbeeCore

struct StraightenTests {
    private let context = SelectionContext(color2: .white)

    @Test func aLineDrawnAlongATiltTellsTheTurn() {
        // Rising to the right by 10°: turning 10° clockwise levels it.
        let rising = Warp.straighteningAngle(from: Point2D(x: 0, y: 0), to: Point2D(x: 100, y: -100 * tan(10 * .pi / 180)))
        #expect(abs(rising - 10) < 1e-9)
        let falling = Warp.straighteningAngle(from: Point2D(x: 0, y: 0), to: Point2D(x: 100, y: 100 * tan(5 * .pi / 180)))
        #expect(abs(falling + 5) < 1e-9)
        // Nearly upright: make it upright.
        let leaning = Warp.straighteningAngle(from: Point2D(x: 0, y: 0), to: Point2D(x: 100 * tan(3 * .pi / 180), y: 100))
        #expect(abs(leaning - 3) < 1e-9)
        #expect(Warp.straighteningAngle(from: Point2D(x: 5, y: 5), to: Point2D(x: 5, y: 5)) == 0)
    }

    @Test func cropToFitLeavesNoEmptyCorners() {
        let canvas = Canvas(size: IntSize(width: 200, height: 120), colorSpace: Canvas.defaultColorSpace, background: Pixel(r: 30, g: 90, b: 160))
        let history = History(byteBudget: .max)
        #expect(ImageActions.straighten(angle: 12, cropToFit: true, canvas: canvas, history: history, context: context))
        let size = canvas.size
        #expect(size.width < 200 && size.height < 120)
        #expect(abs(Double(size.width) / Double(size.height) - 200.0 / 120) < 0.03)
        let buffer = canvas.activeLayer.buffer
        for (x, y) in [(0, 0), (size.width - 1, 0), (0, size.height - 1), (size.width - 1, size.height - 1)] {
            #expect(buffer[x, y] == Pixel(r: 30, g: 90, b: 160))
        }
    }

    @Test func withoutCropTheCanvasGrowsAndTheCornersGetColor2() {
        let canvas = Canvas(size: IntSize(width: 100, height: 100), colorSpace: Canvas.defaultColorSpace, background: .black)
        let history = History(byteBudget: .max)
        let original = canvas.activeLayer.buffer.contentHash()
        #expect(ImageActions.straighten(angle: 30, cropToFit: false, canvas: canvas, history: history, context: context))
        #expect(canvas.size == IntSize(width: 137, height: 137))
        #expect(canvas.activeLayer.buffer[1, 1] == .white)
        #expect(canvas.activeLayer.buffer[68, 68] == .black)
        history.undo(on: canvas)
        #expect(canvas.size == IntSize(width: 100, height: 100) && canvas.activeLayer.buffer.contentHash() == original)
    }

    @Test func positiveAnglesTurnClockwise() {
        let canvas = Canvas(size: IntSize(width: 201, height: 201), colorSpace: Canvas.defaultColorSpace, background: .white)
        canvas.activeLayer.buffer.fill(.black, in: IntRect(x: 0, y: 99, width: 201, height: 3))
        #expect(ImageActions.straighten(angle: 20, cropToFit: false, canvas: canvas, history: History(byteBudget: .max), context: context))
        let center = Double(canvas.size.width) / 2
        // Clockwise on screen: right of center, the line has moved down.
        let x = Int(center + 60), y = Int((center + 60 * tan(20 * .pi / 180)).rounded())
        #expect(canvas.activeLayer.buffer[x, y].r < 100)
        #expect(canvas.activeLayer.buffer[x, Int(center)].r > 200)
    }

    @Test func aTransparentImageKeepsTransparentCornersAndTinyAnglesDoNothing() {
        let canvas = Canvas(size: IntSize(width: 50, height: 50), colorSpace: Canvas.defaultColorSpace, background: .clear)
        canvas.activeLayer.buffer.fill(.black)
        let history = History(byteBudget: .max)
        #expect(!ImageActions.straighten(angle: 0.01, cropToFit: false, canvas: canvas, history: history, context: context))
        #expect(ImageActions.straighten(angle: -20, cropToFit: false, canvas: canvas, history: history, context: context))
        #expect(canvas.activeLayer.buffer[0, 0].a == 0)
    }
}

struct PerspectiveTests {
    private let context = SelectionContext(color2: .white)

    @Test func theCornersLandOnTheSquaresCorners() {
        let corners = [Point2D(x: 10, y: 20), Point2D(x: 210, y: 5), Point2D(x: 190, y: 160), Point2D(x: 30, y: 140)]
        let map = Homography(square: corners)
        for (index, (u, v)) in [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)].enumerated() {
            let point = map.apply(u, v)
            #expect(abs(point.x - corners[index].x) < 1e-9 && abs(point.y - corners[index].y) < 1e-9)
        }
    }

    @Test func anUprightRectangleIsTheSameAsCroppingToIt() {
        let canvas = Canvas(size: IntSize(width: 40, height: 30), colorSpace: Canvas.defaultColorSpace, background: .white)
        let buffer = canvas.activeLayer.buffer
        for y in 0..<30 { for x in 0..<40 { buffer[x, y] = Pixel(r: UInt8(x * 6), g: UInt8(y * 8), b: 77) } }
        let expected = buffer.pixels(in: IntRect(x: 5, y: 4, width: 20, height: 15))
        let corners = [Point2D(x: 5, y: 4), Point2D(x: 25, y: 4), Point2D(x: 25, y: 19), Point2D(x: 5, y: 19)]
        #expect(ImageActions.correctPerspective(corners: corners, canvas: canvas, history: History(byteBudget: .max), context: context))
        #expect(canvas.size == IntSize(width: 20, height: 15))
        #expect(canvas.activeLayer.buffer.pixels(in: canvas.bounds) == expected)
    }

    @Test func aTrapezoidBecomesARectangle() {
        // A dark trapezoid whose top edge is shorter, like a whiteboard seen from below.
        let canvas = Canvas(size: IntSize(width: 120, height: 100), colorSpace: Canvas.defaultColorSpace, background: .white)
        let corners = [Point2D(x: 40, y: 10), Point2D(x: 80, y: 10), Point2D(x: 110, y: 90), Point2D(x: 10, y: 90)]
        let trapezoid = SelectionMask.polygon(corners, clippedTo: canvas.bounds)!
        Effects.apply(.solidFill(.black), to: canvas.activeLayer, selection: trapezoid, edit: Edit(name: "Fill", canvas: canvas))
        #expect(ImageActions.correctPerspective(corners: corners, canvas: canvas, history: History(byteBudget: .max), context: context))
        #expect(canvas.size == Warp.perspectiveSize(corners))
        let size = canvas.size
        // Well inside every edge, it's all trapezoid now.
        for (x, y) in [(3, 3), (size.width - 4, 3), (3, size.height - 4), (size.width / 2, size.height / 2)] {
            #expect(canvas.activeLayer.buffer[x, y].r < 40)
        }
    }
}

struct CropBoxTests {
    private let context = SelectionContext(color2: .white)

    @Test func fittingAShapeInsideTheImage() {
        let bounds = IntRect(x: 0, y: 0, width: 400, height: 300)
        #expect(CropBox.fitted(aspect: 1, in: bounds) == IntRect(x: 50, y: 0, width: 300, height: 300))
        #expect(CropBox.fitted(aspect: 16.0 / 9, in: bounds) == IntRect(x: 0, y: 37, width: 400, height: 225))
        #expect(CropBox.fitted(aspect: 9.0 / 16, in: bounds).height == 300)
    }

    @Test func theBoxStaysInsideAndKeepsItsShape() {
        let bounds = IntRect(x: 0, y: 0, width: 100, height: 80)
        let tooBig = CropBox.clamped(IntRect(x: -20, y: 10, width: 160, height: 90), to: bounds, aspect: 16.0 / 9)
        #expect(bounds.intersection(tooBig) == tooBig)
        #expect(abs(Double(tooBig.width) / Double(tooBig.height) - 16.0 / 9) < 0.05)
        #expect(CropBox.moved(IntRect(x: 70, y: 10, width: 20, height: 20), by: IntPoint(x: 50, y: -30), within: bounds) == IntRect(x: 80, y: 0, width: 20, height: 20))
    }

    @Test func aPixelSizePresetGivesExactlyThatSizeInOneStep() {
        let canvas = Canvas(size: IntSize(width: 300, height: 200), colorSpace: Canvas.defaultColorSpace, background: .black)
        let history = History(byteBudget: .max)
        let original = canvas.activeLayer.buffer.contentHash()
        #expect(ImageActions.crop(to: IntRect(x: 10, y: 10, width: 240, height: 126), resizingTo: IntSize(width: 1200, height: 630),
                                  canvas: canvas, history: history, context: context))
        #expect(canvas.size == IntSize(width: 1200, height: 630))
        #expect(history.undoCount == 1)
        history.undo(on: canvas)
        #expect(canvas.size == IntSize(width: 300, height: 200) && canvas.activeLayer.buffer.contentHash() == original)
    }
}
