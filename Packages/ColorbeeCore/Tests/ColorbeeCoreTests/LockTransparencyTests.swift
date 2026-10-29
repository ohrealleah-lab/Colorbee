import Foundation
import Testing
@testable import ColorbeeCore

/// Lock Transparent Pixels (FR-8.2, stage 23): every tool recolors the layer's pixels but leaves its clear area
/// exactly as it was, mid-stroke too, and every pixel keeps its opacity.
struct LockTransparencyTests {
    private let context = SelectionContext(color2: Pixel(r: 0, g: 0, b: 255))
    private let red = Pixel(r: 255, g: 0, b: 0)
    /// A clear pixel holding a stray color, which must come back exactly.
    private let strayClear = Pixel(r: 7, g: 8, b: 9, a: 0)

    /// A clear layer with a white disc in the middle and a half-transparent edge pixel, above white paper; the
    /// disc's layer is active and locks its transparency.
    private func shape() -> (Canvas, History, Layer) {
        let canvas = Canvas(size: IntSize(width: 40, height: 40), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: .max)
        LayerActions.add(canvas: canvas, history: history, context: context)
        let layer = canvas.activeLayer
        for y in 0..<40 {
            for x in 0..<40 {
                let inside = (x - 20) * (x - 20) + (y - 20) * (y - 20) <= 64
                layer.buffer.row(y)[x] = inside ? .white : strayClear
            }
        }
        layer.buffer.row(20)[28] = Pixel(r: 255, g: 255, b: 255, a: 128)
        layer.locksTransparency = true
        return (canvas, history, layer)
    }

    /// The clear area is untouched, every opaque pixel is still opaque, and the soft one is still half.
    private func expectOutlineKept(_ layer: Layer) {
        for y in 0..<40 {
            for x in 0..<40 {
                let inside = (x - 20) * (x - 20) + (y - 20) * (y - 20) <= 64
                let pixel = layer.buffer[x, y]
                if x == 28, y == 20 { #expect(pixel.a == 128) } else if inside { #expect(pixel.a == 255) } else { #expect(pixel == strayClear, "at \(x), \(y)") }
            }
        }
    }

    @Test func aBrushRecolorsTheShapeAndNeverTheClearAreaEvenMidStroke() {
        let (canvas, history, layer) = shape()
        let edit = history.beginEdit("Brush", on: canvas)
        let stroke = Brush.round.makeStroke(diameter: 30, color: red, layer: layer, edit: edit, seed: 1)
        stroke.move(to: Point2D(x: 5, y: 20), pressure: 1)
        stroke.move(to: Point2D(x: 20, y: 20), pressure: 1)
        // What the display does before showing each part of the stroke.
        canvas.keepLockedTransparency()
        expectOutlineKept(layer)
        #expect(layer.buffer[20, 20] == red)
        stroke.move(to: Point2D(x: 35, y: 20), pressure: 1)
        _ = stroke.finish()
        history.commit(edit)
        expectOutlineKept(layer)
        #expect(layer.buffer[28, 20] == Pixel(r: 255, g: 0, b: 0, a: 128))
    }

    @Test func fillsAndEffectsKeepTheOutline() {
        let (canvas, history, layer) = shape()
        // A fill from the clear area would spread everywhere it's clear.
        let fill = history.beginEdit("Fill", on: canvas)
        FloodFill.fill(layer: layer, at: IntPoint(x: 1, y: 1), with: red, tolerance: 0.2, selection: nil, edit: fill)
        history.commit(fill)
        expectOutlineKept(layer)
        let blur = history.beginEdit("Blur", on: canvas)
        Effects.apply(.gaussianBlur(radius: 4), to: layer, selection: nil, edit: blur)
        history.commit(blur)
        expectOutlineKept(layer)
    }

    @Test func erasingAndDeletingPaintColor2InsideTheShape() throws {
        let (canvas, history, layer) = shape()
        #expect(canvas.erasedFill(for: layer, color2: context.color2) == Pixel(r: 0, g: 0, b: 255))
        #expect(canvas.vacatedFill(for: layer, color2: context.color2) == .clear)
        canvas.selection = .marquee(try #require(SelectionMask.rectangle(IntRect(x: 0, y: 0, width: 20, height: 40), clippedTo: canvas.bounds)))
        SelectionActions.deleteSelection(canvas: canvas, history: history, context: context)
        expectOutlineKept(layer)
        #expect(layer.buffer[15, 20] == Pixel(r: 0, g: 0, b: 255))
    }

    @Test func turningAndCroppingMoveTheOutlineAndUndoIsExact() {
        let (canvas, history, layer) = shape()
        let original = layer.buffer.contentHash()
        ImageActions.transform(.flipHorizontal, canvas: canvas, history: history, context: context)
        #expect(layer.buffer[11, 20] == Pixel(r: 255, g: 255, b: 255, a: 128) && layer.locksTransparency)
        ImageActions.resizeCanvas(to: IntSize(width: 50, height: 40), canvas: canvas, history: history, context: context)
        #expect(canvas.activeLayer.buffer[45, 5] == .clear)
        history.undo(on: canvas)
        history.undo(on: canvas)
        #expect(canvas.layers[1].buffer.contentHash() == original)
    }

    @Test func theLockIsSavedInProjectsAndIsAnUndoStep() throws {
        let (canvas, history, layer) = shape()
        let reopened = try ProjectFile.decode(ProjectFile.encode(canvas))
        #expect(reopened.layers[1].locksTransparency && !reopened.layers[0].locksTransparency)
        layer.locksTransparency = false
        LayerActions.update("Lock Transparent Pixels", layerAt: 1, canvas: canvas, history: history) { $0.locksTransparency = true }
        #expect(history.undoActionName == "Lock Transparent Pixels")
        history.undo(on: canvas)
        #expect(!canvas.layers[1].locksTransparency)
    }

    /// Review U, finding 3: a soft edge lifted, moved and put back comes back exactly, and while it floats a save
    /// shows what placing it will leave.
    @Test func aSoftEdgeMovedAndPutBackIsExact() throws {
        let (canvas, history, layer) = shape()
        let original = layer.buffer.contentHash()
        canvas.selection = .marquee(try #require(SelectionMask.rectangle(IntRect(x: 22, y: 14, width: 10, height: 12), clippedTo: canvas.bounds)))
        SelectionActions.nudge(dx: 3, dy: 0, canvas: canvas, history: history, context: context)
        let floating = try #require(canvas.selection.floating)
        let saved = try #require(canvas.layerBuffersAsSaved(transparentKey: nil, resampling: .nearestNeighbor)[layer.id])
        let patch = try #require(floating.placedPatch(on: layer, resampling: .nearestNeighbor, transparentKey: nil))
        for y in 0..<patch.area.height {
            for x in 0..<patch.area.width {
                #expect(saved[patch.area.minX + x, patch.area.minY + y] == patch.pixels[x, y])
            }
        }
        // Past the shape, the piece doesn't show at all.
        #expect(saved[34, 20] == strayClear)
        SelectionActions.nudge(dx: -3, dy: 0, canvas: canvas, history: history, context: context)
        #expect(SelectionActions.placeFloating(canvas: canvas, history: history, context: context))
        #expect(layer.buffer.contentHash() == original)
    }

    @Test func aPasteOverTheClearAreaLeavesItClear() {
        let (canvas, history, layer) = shape()
        let image = PixelBuffer(width: 40, height: 4, fill: Pixel(r: 0, g: 255, b: 0, a: 200))
        SelectionActions.paste(image, at: IntPoint(x: 0, y: 18), canvas: canvas, history: history, context: context)
        let flat = canvas.flattened()
        #expect(flat[2, 19] == .white)
        #expect(SelectionActions.placeFloating(canvas: canvas, history: history, context: context))
        expectOutlineKept(layer)
        #expect(canvas.flattened().contentHash() == flat.contentHash())
        #expect(layer.buffer[20, 19] == Pixel(r: 55, g: 255, b: 55))
    }

    /// Review U, finding 2: a shadow big enough to grow the canvas still leaves the clear area as it was.
    @Test func aShadowThatGrowsTheCanvasKeepsTheClearArea() {
        let (canvas, history, layer) = shape()
        let original = layer.buffer.contentHash()
        #expect(Decorations.dropShadow(DropShadow(offsetX: 30, offsetY: 0, blur: 0, color: .black, opacity: 100), canvas: canvas, history: history, context: context))
        #expect(canvas.size.width > 40)
        let grown = canvas.layers[1]
        for y in 0..<40 {
            for x in 0..<canvas.size.width {
                let inside = (x - 20) * (x - 20) + (y - 20) * (y - 20) <= 64
                if x >= 40 { #expect(grown.buffer[x, y] == .clear) } else if !inside, x != 28 || y != 20 { #expect(grown.buffer[x, y] == strayClear, "at \(x), \(y)") }
            }
        }
        history.undo(on: canvas)
        #expect(canvas.layers[1].buffer.contentHash() == original)
    }
}
