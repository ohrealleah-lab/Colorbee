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

/// AC-27: layers moved out of memory in the background come back exactly, whether or not the background
/// work has finished when they're needed.
struct BackgroundEvictionTests {
    private let context = SelectionContext(color2: .white)

    @Test(arguments: [false, true])
    func layerStepsUndoAndRedoExactlyWithBackgroundEviction(waitBetweenSteps: Bool) {
        let canvas = Canvas(size: IntSize(width: 300, height: 300), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: 1)
        history.evictsInBackground = true
        let original = canvas.flattened().contentHash()
        for round in 0..<6 {
            LayerActions.add(canvas: canvas, history: history, context: context)
            let edit = history.beginEdit("Paint", on: canvas)
            let rect = IntRect(x: round * 20, y: round * 30, width: 120, height: 90)
            edit.willModify(rect, in: canvas.activeLayer)
            canvas.activeLayer.buffer.fill(Pixel(r: UInt8(round * 40), g: 100, b: 200, a: 200), in: rect)
            history.commit(edit)
            if round % 2 == 1 { LayerActions.mergeDown(canvas: canvas, history: history, context: context) }
            if waitBetweenSteps { history.finishBackgroundWork() }
        }
        LayerActions.flatten(canvas: canvas, history: history, context: context)
        let final = canvas.flattened().contentHash()
        while history.canUndo { history.undo(on: canvas) }
        #expect(canvas.flattened().contentHash() == original)
        while history.canRedo { history.redo(on: canvas) }
        #expect(canvas.flattened().contentHash() == final)
        history.finishBackgroundWork()
        while history.canUndo { history.undo(on: canvas) }
        #expect(canvas.flattened().contentHash() == original)
    }
}

/// Leah, 2026-10-04: after removing a redacted file's earlier versions, its undo history goes too.
struct ForgettingHistoryTests {
    @Test func forgettingTheHistoryLeavesNothingToUndoOrRedo() {
        let canvas = Canvas(size: IntSize(width: 64, height: 64), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: 1)
        history.evictsInBackground = true
        for value in [UInt8(10), 90, 170] {
            LayerActions.add(canvas: canvas, history: history, context: SelectionContext(color2: .white))
            let edit = history.beginEdit("Paint", on: canvas)
            edit.willModify(IntRect(x: 0, y: 0, width: 30, height: 30), in: canvas.activeLayer)
            canvas.activeLayer.buffer.fill(Pixel(r: value, g: 0, b: 0), in: IntRect(x: 0, y: 0, width: 30, height: 30))
            history.commit(edit)
        }
        history.undo(on: canvas)
        let shown = canvas.flattened().contentHash()
        let revision = history.revision
        history.removeAll()
        #expect(!history.canUndo && !history.canRedo)
        #expect(history.byteCount == 0 && history.spillFileSize == 0)
        #expect(history.revision != revision)
        #expect(canvas.flattened().contentHash() == shown)
    }
}
