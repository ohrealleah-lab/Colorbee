import Foundation
import Testing
@testable import ColorbeeCore

/// Regression tests for the findings of cloud reviews H, I and J (Docs/Review/findings-H.md, -I.md, -J.md).
struct ReviewHIJTests {
    private let context = SelectionContext(color2: .white)

    /// H5: the spill file can't outlive Colorbee, even after a crash: it's unlinked as soon as it's open.
    @Test func theSpillFileHasNoNameOnDisk() throws {
        let store = try SpillStore()
        let location = try store.write([Pixel](repeating: Pixel(r: 1, g: 2, b: 3), count: 64))
        #expect(!FileManager.default.fileExists(atPath: store.path))
        #expect(try store.read(location, count: 64).first == Pixel(r: 1, g: 2, b: 3))
    }

    /// H7: pixels Remove Background makes fully transparent keep none of their old color.
    @Test func removeBackgroundLeavesNoHiddenColor() {
        let canvas = Canvas(size: IntSize(width: 2, height: 1), colorSpace: Canvas.defaultColorSpace, background: Pixel(r: 200, g: 100, b: 50))
        let history = History(byteBudget: 512 << 20)
        SubjectActions.removeBackground([0, 255], canvas: canvas, history: history, context: context)
        #expect(canvas.layers[0].buffer.row(0)[0] == .clear)
        #expect(canvas.layers[0].buffer.row(0)[1] == Pixel(r: 200, g: 100, b: 50))
    }

    /// I3: fully transparent pixels count as one color, whatever their hidden channels.
    @Test func transparentPixelsAreOneColorToFillAndTheWand() throws {
        let buffer = PixelBuffer(width: 3, height: 1)
        buffer.row(0)[0] = Pixel(r: 10, g: 20, b: 30, a: 0)
        buffer.row(0)[1] = Pixel(r: 200, g: 0, b: 0, a: 0)
        let wand = try #require(SelectionMask.magicWand(in: buffer, at: IntPoint(x: 0, y: 0), tolerance: 0, contiguous: true))
        #expect((0..<3).allSatisfy { wand[$0, 0] > 0 })
    }

    /// J19: a damaged project whose layers share an id is refused, not a crash.
    @Test func aProjectWithRepeatedLayerIDsIsDamaged() throws {
        let canvas = Canvas(size: IntSize(width: 4, height: 4), colorSpace: Canvas.defaultColorSpace, background: .white)
        LayerActions.add(canvas: canvas, history: History(byteBudget: 512 << 20), context: context)
        let data = try ProjectFile.encode(canvas)
        let first = canvas.layers[0].id.rawValue.uuidString, second = canvas.layers[1].id.rawValue.uuidString
        let damaged = try #require(String(data: data, encoding: .isoLatin1)?.replacingOccurrences(of: second, with: first).data(using: .isoLatin1))
        #expect(throws: ProjectFile.Failure.damaged) { try ProjectFile.decode(damaged) }
    }

    /// J20: a pixel range near Int.max is refused, not an overflow.
    @Test func aProjectWithAHugePixelOffsetIsDamaged() throws {
        let canvas = Canvas(size: IntSize(width: 4, height: 4), colorSpace: Canvas.defaultColorSpace, background: .white)
        let data = try ProjectFile.encode(canvas)
        let jsonStart = ProjectFile.magic.count + 4
        let length = Int(data[ProjectFile.magic.count..<jsonStart].withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) })
        var manifest = try JSONDecoder().decode(ProjectFile.Manifest.self, from: data[jsonStart..<(jsonStart + length)])
        manifest.layers[0].pixels = (Int.max - 1)..<Int.max
        let json = try JSONEncoder().encode(manifest)
        var damaged = Data(ProjectFile.magic)
        var newLength = UInt32(json.count).littleEndian
        damaged.append(Data(bytes: &newLength, count: 4))
        damaged.append(json)
        damaged.append(data[(jsonStart + length)...])
        #expect(throws: ProjectFile.Failure.damaged) { try ProjectFile.decode(damaged) }
    }
}

extension ReviewHIJTests {
    /// H3: Batch Redact covers every layer under the selection, like Auto-Redact.
    @Test func batchRedactCoversTheLayerBelowTheActiveOne() throws {
        let canvas = Canvas(size: IntSize(width: 16, height: 16), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: 512 << 20)
        LayerActions.add(canvas: canvas, history: history, context: context)
        let box = IntRect(x: 2, y: 2, width: 6, height: 6)
        let selection = try #require(SelectionMask.rectangle(box, clippedTo: canvas.bounds))
        let outcome = AutoRedact.apply(.solidFill(Pixel(r: 9, g: 9, b: 9)), in: selection, canvas: canvas, history: history)
        #expect(outcome == .redacted)
        #expect(canvas.layers[0].buffer.row(4)[4] == Pixel(r: 9, g: 9, b: 9))
        canvas.layers[0].isLocked = true
        #expect(AutoRedact.apply(.solidFill(.black), in: selection, canvas: canvas, history: history) == .locked(layerName: "Background"))
    }
}

import ImageIO
import UniformTypeIdentifiers

/// J2 and J3: what decoding a file says about it, and photos the right way up.
struct DecodingTests {
    private func file(_ type: UTType, frames: [PixelBuffer], orientation: Int? = nil) throws -> Data {
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, type.identifier as CFString, frames.count, nil))
        for frame in frames {
            let image = try ImageCodec.makeCGImage(frame, colorSpace: Canvas.defaultColorSpace)
            let properties = orientation.map { [kCGImagePropertyOrientation: $0] as CFDictionary }
            CGImageDestinationAddImage(destination, image, properties)
        }
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test func aPhotoTaggedAsTurnedOpensUpright() throws {
        let stored = PixelBuffer(width: 2, height: 1)
        stored.row(0)[0] = Pixel(r: 255, g: 0, b: 0)
        stored.row(0)[1] = Pixel(r: 0, g: 0, b: 255)
        let decoded = try ImageCodec.decode(file(.tiff, frames: [stored], orientation: 6))
        #expect(decoded.buffer.size == IntSize(width: 1, height: 2))
        #expect(decoded.buffer.row(0)[0] == Pixel(r: 255, g: 0, b: 0))
        #expect(decoded.buffer.row(1)[0] == Pixel(r: 0, g: 0, b: 255))
        #expect(!decoded.opensAsCopy)
    }

    @Test func everyOrientationTagIsUndone() {
        let stored = PixelBuffer(width: 3, height: 2)
        for y in 0..<2 { for x in 0..<3 { stored.row(y)[x] = Pixel(r: UInt8(x * 40), g: UInt8(y * 90), b: 0) } }
        // Each tag's turns, applied to the image as it should look, give what's stored; uprighting undoes them.
        for tag in 1...8 {
            var buffer = stored
            for turn in ImageCodec.uprightingTurns(forOrientationTag: tag) { buffer = buffer.transformed(turn) }
            #expect(tag < 5 ? buffer.size == stored.size : buffer.size == IntSize(width: 2, height: 3), "tag \(tag)")
        }
    }

    @Test func aFileWithSeveralFramesOpensAsACopy() throws {
        let frames = [PixelBuffer(width: 4, height: 4, fill: .black), PixelBuffer(width: 4, height: 4, fill: .white)]
        let data = try file(.tiff, frames: frames)
        let first = try ImageCodec.decode(data)
        #expect(first.frameCount == 2)
        #expect(first.opensAsCopy)
        let second = try ImageCodec.decode(data, frame: 1)
        #expect(second.buffer.row(0)[0] == .white)
        #expect(ImageCodec.frameThumbnails(data, maxSide: 32).count == 2)
    }
}

/// I4 and I5: Symmetry's mirrored strokes.
struct SymmetryStrokeTests {
    private func whiteLayer() -> (Canvas, Edit) {
        let canvas = Canvas(size: IntSize(width: 20, height: 20), colorSpace: Canvas.defaultColorSpace, background: .white)
        return (canvas, History(byteBudget: .max).beginEdit("Stroke", on: canvas))
    }

    /// I4: where a stroke and its mirror overlap, neither overwrites the other's paint.
    @Test func mirroredBrushDabsOverlapCleanly() {
        let (canvas, edit) = whiteLayer()
        let layer = canvas.layers[0]
        let first = Brush.round.makeStroke(diameter: 9, color: .black, layer: layer, edit: edit)
        let mirror = Brush.round.makeStroke(diameter: 9, color: .black, layer: layer, edit: edit, sharingPainterWith: first)
        first.move(to: Point2D(x: 8.5, y: 10.5))
        mirror.move(to: Point2D(x: 11.5, y: 10.5))
        for y in 0..<20 {
            for x in 0..<10 { #expect(layer.buffer.row(y)[x] == layer.buffer.row(y)[19 - x], "(\(x), \(y))") }
        }
        #expect(layer.buffer.row(13)[8] == .black)
    }

    /// I5: an even-sized eraser square is mirrored as a square of pixels, not by its pointer.
    @Test(arguments: [4, 5, 8])
    func mirroredEraserSquaresAreExactReflections(size: Int) {
        let (canvas, edit) = whiteLayer()
        let layer = canvas.layers[0]
        let mirror = StrokeMirror(canvasSize: canvas.size, flipsX: true, flipsY: false)
        let first = EraserStroke(size: size, effect: .replace(.black), layer: layer, edit: edit)
        let second = EraserStroke(size: size, effect: .replace(.black), layer: layer, edit: edit, mirror: mirror, sharingPainterWith: first)
        for stroke in [first, second] { stroke.move(to: Point2D(x: 5.5, y: 10.5)) }
        for x in 0..<10 { #expect(layer.buffer.row(10)[x] == layer.buffer.row(10)[19 - x], "size \(size), x \(x)") }
    }
}

/// Leah's decision on review I's question: Fill and the wand can look at all layers together.
struct SampleAllLayersTests {
    @Test func fillCanFindItsAreaInTheLayersBelow() throws {
        let canvas = Canvas(size: IntSize(width: 10, height: 10), colorSpace: Canvas.defaultColorSpace, background: .white)
        canvas.layers[0].buffer.fill(Pixel(r: 255, g: 0, b: 0), in: IntRect(x: 2, y: 2, width: 4, height: 4))
        let history = History(byteBudget: 512 << 20)
        LayerActions.add(canvas: canvas, history: history, context: SelectionContext(color2: .white))
        let edit = history.beginEdit("Fill", on: canvas)
        let flattened = canvas.flattened()
        FloodFill.fill(layer: canvas.activeLayer, at: IntPoint(x: 3, y: 3), with: .black, tolerance: 0, selection: nil, edit: edit, sampling: flattened)
        #expect(canvas.activeLayer.buffer.row(3)[3] == .black)
        #expect(canvas.activeLayer.buffer.row(0)[0] == .clear)
        let wand = try #require(SelectionMask.magicWand(in: flattened, at: IntPoint(x: 3, y: 3), tolerance: 0, contiguous: true))
        #expect(wand.bounds == IntRect(x: 2, y: 2, width: 4, height: 4))
    }
}

/// I8: Option-click with the Eyedropper picks the color shown, blend modes and adjustment layers included.
struct ShownPixelTests {
    @Test func anInvertLayerOverWhiteShowsBlack() {
        let canvas = Canvas(size: IntSize(width: 4, height: 4), colorSpace: Canvas.defaultColorSpace, background: .white)
        LayerActions.addAdjustment(.invert, named: "Invert", canvas: canvas, history: History(byteBudget: .max), context: SelectionContext(color2: .white))
        #expect(canvas.pixelAsShown(at: IntPoint(x: 1, y: 1)) == .black)
    }

    @Test func aMultiplyLayerIsBlended() {
        let canvas = Canvas(size: IntSize(width: 4, height: 4), colorSpace: Canvas.defaultColorSpace, background: Pixel(r: 0, g: 0, b: 255))
        LayerActions.add(canvas: canvas, history: History(byteBudget: .max), context: SelectionContext(color2: .white))
        canvas.activeLayer.buffer.fill(Pixel(r: 255, g: 0, b: 0), in: canvas.bounds)
        canvas.activeLayer.blendMode = .multiply
        let flattened = canvas.flattened()
        #expect(canvas.pixelAsShown(at: IntPoint(x: 2, y: 2)) == flattened.row(2)[2])
    }
}

/// I7, I11 and I13: selection and shape geometry.
struct SelectionGeometryTests {
    /// I13: a Shift-constrained marquee is square in pixels, wherever the drag starts within a pixel.
    @Test func aConstrainedMarqueeIsSquareInPixels() throws {
        let bounds = IntRect(x: 0, y: 0, width: 100, height: 100)
        for (start, end) in [((0.9, 0.1), (3.0, 2.0)), ((5.2, 5.9), (9.7, 7.1)), ((10.0, 10.0), (4.4, 2.2))] {
            let mask = try #require(SelectionActions.marquee(.rectangle, from: Point2D(x: start.0, y: start.1), to: Point2D(x: end.0, y: end.1),
                                                             constrain: true, in: bounds))
            #expect(mask.bounds.width == mask.bounds.height, "\(start) → \(end): \(mask.bounds)")
        }
    }

    /// I7: dragging a handle can't make a selection bigger than Colorbee edits.
    @Test func aHandleDragIsLimitedToAnEditableSize() {
        let rect = SelectionHandle.bottomRight.resize(IntRect(x: 0, y: 0, width: 200, height: 200), by: Point2D(x: 90_000, y: 90_000), keepProportions: false)
        #expect(rect.width <= ResizeSkew.maxSide && rect.height <= ResizeSkew.maxSide && rect.width * rect.height <= ResizeSkew.maxArea)
    }

    /// I11: every shape's painted area holds all of its outline.
    @Test(arguments: ShapeKind.allCases.filter(\.isBoxShape))
    func paintedBoundsHoldTheWholeShape(kind: ShapeKind) {
        let spec = ShapeSpec(kind: kind, start: Point2D(x: 100, y: 100), end: Point2D(x: 700, y: 700), lineWidth: 4, outline: .black, fill: nil)
        let path = ShapePaths.path(kind, in: CGRect(x: 100, y: 100, width: 600, height: 600)).boundingBoxOfPath.insetBy(dx: -2, dy: -2)
        let painted = spec.paintedBounds
        #expect(Double(painted.minX) <= path.minX && Double(painted.maxX) >= path.maxX && Double(painted.minY) <= path.minY && Double(painted.maxY) >= path.maxY, "\(kind)")
    }
}
