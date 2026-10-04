import Foundation
import Testing
@testable import ColorbeeCore

/// Regression tests for the findings of cloud review F (Docs/Review/findings-F.md), which Leah confirmed by hand.
struct ReviewFTests {
    private func canvasWithBlueBelow() -> (Canvas, History) {
        let canvas = Canvas(size: IntSize(width: 16, height: 16), colorSpace: Canvas.defaultColorSpace, background: Pixel(r: 30, g: 60, b: 220))
        let history = History(byteBudget: 512 << 20)
        LayerActions.add(canvas: canvas, history: history, context: SelectionContext(color2: .white))
        canvas.layers[1].buffer.fill(Pixel(r: 200, g: 200, b: 200), in: IntRect(x: 0, y: 0, width: 16, height: 8))
        return (canvas, history)
    }

    /// Finding 1 (Leah: preview the placed look): a floating selection on a layer that isn't Normal at 100%
    /// looks the same before and after it's placed.
    @Test(arguments: [(BlendMode.multiply, 1.0), (.normal, 0.5), (.screen, 0.6)])
    func placingAFloatingSelectionDoesntChangeHowItLooks(mode: BlendMode, opacity: Double) {
        let (canvas, history) = canvasWithBlueBelow()
        canvas.layers[1].blendMode = mode
        canvas.layers[1].opacity = opacity
        let context = SelectionContext(color2: .white, resampling: .smooth)
        SelectionActions.paste(PixelBuffer(width: 6, height: 6, fill: Pixel(r: 250, g: 220, b: 0)), at: IntPoint(x: 4, y: 4),
                               canvas: canvas, history: history, context: context)
        let before = canvas.flattened(resampling: .smooth).contentHash()
        SelectionActions.placeFloating(canvas: canvas, history: history, context: context)
        #expect(canvas.flattened().contentHash() == before)
    }

    /// Finding 2: a stretched floating selection is saved with the resampling it's shown and placed with.
    @Test(arguments: [Resampling.smooth, .nearestNeighbor])
    func aStretchedFloatingSelectionFlattensAsItWillBePlaced(resampling: Resampling) {
        let canvas = Canvas(size: IntSize(width: 16, height: 16), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: 512 << 20)
        let context = SelectionContext(color2: .white, resampling: resampling)
        let checker = PixelBuffer(width: 2, height: 2, fill: .black)
        checker.row(0)[1] = .white
        checker.row(1)[0] = .white
        SelectionActions.paste(checker, at: IntPoint(x: 2, y: 2), canvas: canvas, history: history, context: context)
        SelectionActions.resize(to: IntRect(x: 2, y: 2, width: 8, height: 8), canvas: canvas)
        let before = canvas.flattened(resampling: resampling).contentHash()
        let project = try? ProjectFile.decode(ProjectFile.encode(canvas, resampling: resampling))
        SelectionActions.placeFloating(canvas: canvas, history: history, context: context)
        #expect(before == canvas.flattened().contentHash())
        #expect(project?.flattened().contentHash() == canvas.flattened().contentHash())
    }
}
