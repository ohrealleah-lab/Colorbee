import Testing
@testable import ColorbeeCore

/// The overnight soak's failure: undo or redo across a geometry step that was spilled to disk, with layer
/// steps on either side holding the same layer buffers (Docs/STATUS.md, open problem 1).
struct GeometrySpillTests {
    private let context = SelectionContext(color2: .white)

    private func paint(_ canvas: Canvas, _ history: History, _ value: UInt8) {
        let edit = history.beginEdit("Paint", on: canvas)
        let rect = IntRect(x: 2, y: 2, width: 6, height: 6)
        edit.willModify(rect, in: canvas.activeLayer)
        canvas.activeLayer.buffer.fill(Pixel(r: value, g: 255 - value, b: 40), in: rect)
        history.commit(edit)
    }

    @Test(arguments: [false, true])
    func undoAndRedoAcrossASpilledCropAreExact(resize: Bool) {
        let canvas = Canvas(size: IntSize(width: 64, height: 64), colorSpace: Canvas.defaultColorSpace, background: Pixel(r: 90, g: 90, b: 90))
        let history = History(byteBudget: 1)
        let original = canvas.flattened().contentHash()
        LayerActions.update("Rename", layerAt: 0, canvas: canvas, history: history) { $0.name = "Before" }
        paint(canvas, history, 10)
        if resize {
            ImageActions.resizeCanvas(to: IntSize(width: 80, height: 70), canvas: canvas, history: history, context: context)
        } else {
            ImageActions.crop(to: IntRect(x: 0, y: 0, width: 40, height: 40), canvas: canvas, history: history, context: context)
        }
        paint(canvas, history, 60)
        LayerActions.update("Rename", layerAt: 0, canvas: canvas, history: history) { $0.name = "After" }
        paint(canvas, history, 120)
        paint(canvas, history, 180)
        let final = canvas.flattened().contentHash()

        var checkpoints: [Int: Int] = [:]
        while history.canUndo {
            checkpoints[history.undoCount] = canvas.flattened().contentHash()
            history.undo(on: canvas)
        }
        #expect(canvas.flattened().contentHash() == original)
        while history.canRedo {
            history.redo(on: canvas)
            #expect(canvas.flattened().contentHash() == checkpoints[history.undoCount])
        }
        #expect(canvas.flattened().contentHash() == final)
    }
}

struct FingerprintTests {
    @Test func bandHashesCombineToTheBuffersFingerprint() {
        let buffer = PixelBuffer(width: 37, height: 600)
        for y in 0..<buffer.height {
            for x in 0..<buffer.width { buffer.row(y)[x] = Pixel(r: UInt8(x), g: UInt8(y & 255), b: UInt8((x * y) & 255)) }
        }
        let bands = GeometryChange.bands(of: buffer.size)
        let hashes = bands.map { PixelBuffer.fingerprint(band: buffer.pixels(in: $0), width: buffer.width) }
        #expect(PixelBuffer.fingerprint(combining: hashes) == buffer.fingerprint())
        buffer.row(599)[36] = Pixel(r: 1, g: 2, b: 3)
        #expect(PixelBuffer.fingerprint(combining: hashes) != buffer.fingerprint())
    }
}

/// From the second 30-minute soak: a rotation or flip gave layers new buffers, so a layer-settings step made
/// before it put back a buffer that later edits had changed.
struct TransformIdentityTests {
    private let context = SelectionContext(color2: .white)

    @Test(arguments: Orientation.allCases)
    func undoAndRedoAroundATurnAreExact(orientation: Orientation) {
        let canvas = Canvas(size: IntSize(width: 24, height: 16), colorSpace: Canvas.defaultColorSpace, background: .white)
        canvas.layers[0].buffer.fill(Pixel(r: 10, g: 200, b: 90), in: IntRect(x: 0, y: 0, width: 6, height: 16))
        let history = History(byteBudget: 512 << 20)
        let original = canvas.flattened().contentHash()
        LayerActions.update("Blend Mode", layerAt: 0, canvas: canvas, history: history) { $0.blendMode = .multiply }
        let edit = history.beginEdit("Fill", on: canvas)
        edit.willModify(IntRect(x: 2, y: 2, width: 8, height: 8), in: canvas.activeLayer)
        canvas.activeLayer.buffer.fill(.black, in: IntRect(x: 2, y: 2, width: 8, height: 8))
        history.commit(edit)
        ImageActions.transform(orientation, canvas: canvas, history: history, context: context)
        let final = canvas.flattened().contentHash()
        while history.canUndo { history.undo(on: canvas) }
        #expect(canvas.flattened().contentHash() == original)
        while history.canRedo { history.redo(on: canvas) }
        #expect(canvas.flattened().contentHash() == final)
    }
}
