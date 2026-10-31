import Foundation
import Testing
@testable import ColorbeeCore

/// The History panel's thumbnails composite each sampled pixel on their own, and must show what an export shows
/// (review round 11, AE 2 and AE B). At full size they sample every pixel, so they can be compared pixel by pixel.
struct ThumbnailTests {
    private let context = SelectionContext(color2: .white)

    private func largestDifference(_ canvas: Canvas) -> Int {
        let flat = canvas.flattened().pixels(in: canvas.bounds), thumbnail = canvas.thumbnail(maxSide: max(canvas.size.width, canvas.size.height)).pixels
        return zip(flat, thumbnail).map { a, b in
            max(abs(Int(a.r) - Int(b.r)), abs(Int(a.g) - Int(b.g)), abs(Int(a.b) - Int(b.b)), abs(Int(a.a) - Int(b.a)))
        }.max()!
    }

    /// Masks, a clipped adjustment and a clipped pixel layer, a group drawn on its own, and adjustments blended in
    /// other modes: every rule the thumbnail shares with the export.
    private func busyStack() -> (Canvas, History) {
        let canvas = Canvas(size: IntSize(width: 16, height: 12), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: .max)
        for y in 0..<12 { for x in 0..<16 { canvas.layers[0].buffer[x, y] = Pixel(r: UInt8(x * 15), g: UInt8(y * 20), b: 90) } }
        LayerActions.add(canvas: canvas, history: history, context: context)
        let shapes = canvas.activeLayer
        shapes.buffer.fill(Pixel(r: 220, g: 60, b: 30, a: 200), in: IntRect(x: 2, y: 2, width: 10, height: 7))
        shapes.blendMode = .multiply
        shapes.mask = Layer(name: "Mask", buffer: PixelBuffer(width: 16, height: 12))
        shapes.mask!.buffer.fill(Pixel(r: 0, g: 0, b: 0, a: 255), in: IntRect(x: 0, y: 0, width: 5, height: 12))
        LayerActions.addAdjustment(.hueSaturation(hue: 40, saturation: 30, lightness: 0), named: "Clipped", canvas: canvas, history: history, context: context)
        canvas.activeLayer.clipsToLayerBelow = true
        canvas.activeLayer.blendMode = .softLight
        canvas.activeLayer.opacity = 0.7
        LayerActions.add(canvas: canvas, history: history, context: context)
        canvas.activeLayer.buffer.fill(Pixel(r: 20, g: 200, b: 220), in: IntRect(x: 6, y: 0, width: 4, height: 12))
        canvas.activeLayer.clipsToLayerBelow = true
        canvas.activeLayer.opacity = 0.5
        LayerActions.add(canvas: canvas, history: history, context: context)
        let grouped = canvas.activeLayer
        grouped.buffer.fill(Pixel(r: 250, g: 230, b: 60), in: IntRect(x: 8, y: 5, width: 7, height: 6))
        LayerActions.addAdjustment(.invert, named: "Inside", canvas: canvas, history: history, context: context)
        LayerActions.group([grouped.id, canvas.activeLayer.id], canvas: canvas, history: history, context: context)
        let group = canvas.layers.first { $0.isGroup }!
        group.passesThrough = false
        group.opacity = 0.8
        LayerActions.addAdjustment(.brightnessContrast(brightness: 20, contrast: 30), named: "On Top", canvas: canvas, history: history, context: context)
        canvas.activeLayer.blendMode = .luminosity
        canvas.activeLayer.opacity = 0.6
        return (canvas, history)
    }

    @Test func aThumbnailShowsWhatTheExportShows() {
        let (canvas, _) = busyStack()
        #expect(largestDifference(canvas) <= 2)
    }

    /// AE B: a pasted piece not yet placed was left out of the History panel's pictures.
    @Test func aFloatingPieceShowsInTheThumbnail() {
        let (canvas, history) = busyStack()
        canvas.activeLayerIndex = 0
        SelectionActions.paste(PixelBuffer(width: 4, height: 3, fill: Pixel(r: 10, g: 10, b: 240)), at: IntPoint(x: 1, y: 8),
                               canvas: canvas, history: history, context: context)
        #expect(canvas.selection.floating != nil)
        #expect(largestDifference(canvas) <= 2)
    }
}
