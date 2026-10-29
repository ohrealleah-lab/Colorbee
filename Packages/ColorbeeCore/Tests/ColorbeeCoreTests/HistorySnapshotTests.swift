import Testing
@testable import ColorbeeCore

/// History Snapshots (FR-9.7 item 4): named copies of the image that survive any later edit.
struct HistorySnapshotTests {
    private let red = Pixel(r: 255, g: 0, b: 0)
    private let context = SelectionContext(color2: .white)

    private func canvas(_ side: Int = 300) -> Canvas {
        Canvas(size: IntSize(width: side, height: side), colorSpace: Canvas.defaultColorSpace, background: .white)
    }

    private func fill(_ rect: IntRect, with color: Pixel, on canvas: Canvas, history: History) {
        let edit = history.beginEdit("Fill", on: canvas)
        edit.willModify(rect, in: canvas.activeLayer)
        canvas.activeLayer.buffer.fill(color, in: rect)
        history.commit(edit)
    }

    /// The whole image, layers and settings included.
    private func look(_ canvas: Canvas) -> [Int] {
        [canvas.flattened().contentHash(), canvas.layers.count, canvas.size.width, canvas.size.height]
            + canvas.layers.map { $0.name.hashValue ^ Int($0.opacity * 1000) }
    }

    @Test func goingToASnapshotPutsTheImageBackAsOneStep() throws {
        let canvas = canvas(), history = History(byteBudget: .max)
        fill(IntRect(x: 0, y: 0, width: 50, height: 50), with: .black, on: canvas, history: history)
        let start = look(canvas)
        let snapshot = try history.takeSnapshot(named: "Start", of: canvas)
        #expect(history.snapshots.map(\.name) == ["Start"] && history.undoCount == 1)
        fill(IntRect(x: 100, y: 100, width: 90, height: 90), with: red, on: canvas, history: history)
        let edited = look(canvas)
        try history.goToSnapshot(snapshot.id, on: canvas)
        #expect(look(canvas) == start)
        #expect(history.undoActionName == "Go to Snapshot" && history.undoCount == 3)
        // ⌘Z comes back to where you were.
        history.undo(on: canvas)
        #expect(look(canvas) == edited)
        history.redo(on: canvas)
        #expect(look(canvas) == start)
    }

    @Test func aSnapshotSurvivesUndoingPastItAndNewEdits() throws {
        let canvas = canvas(), history = History(byteBudget: .max)
        fill(IntRect(x: 0, y: 0, width: 50, height: 50), with: .black, on: canvas, history: history)
        let start = look(canvas)
        let snapshot = try history.takeSnapshot(named: "Start", of: canvas)
        // Undoing the step it was taken after, then a new edit, throws that step away for good; the snapshot stays.
        history.undo(on: canvas)
        fill(IntRect(x: 10, y: 10, width: 20, height: 20), with: red, on: canvas, history: history)
        try history.goToSnapshot(snapshot.id, on: canvas)
        #expect(look(canvas) == start)
        // Editing after going there doesn't change the snapshot.
        fill(canvas.bounds, with: red, on: canvas, history: history)
        try history.goToSnapshot(snapshot.id, on: canvas)
        #expect(look(canvas) == start)
    }

    @Test func itBringsBackTheSizeLayersAndSelection() throws {
        let canvas = canvas(), history = History(byteBudget: .max)
        LayerActions.add(canvas: canvas, history: history, context: context)
        canvas.activeLayer.buffer.fill(red, in: IntRect(x: 20, y: 20, width: 40, height: 40))
        canvas.activeLayer.opacity = 0.5
        LayerActions.addAdjustment(.invert, named: "Invert", canvas: canvas, history: history, context: context)
        let mask = try #require(SelectionMask.rectangle(IntRect(x: 5, y: 5, width: 10, height: 10), clippedTo: canvas.bounds))
        canvas.selection = .marquee(mask)
        let start = look(canvas)
        let snapshot = try history.takeSnapshot(named: "Layers", of: canvas)
        // Merge everything, then crop.
        LayerActions.mergeVisible(canvas: canvas, history: history, context: context)
        canvas.selection = .marquee(try #require(SelectionMask.rectangle(IntRect(x: 0, y: 0, width: 100, height: 80), clippedTo: canvas.bounds)))
        ImageActions.cropToSelection(canvas: canvas, history: history, context: context)
        let cropped = look(canvas)
        #expect(canvas.size == IntSize(width: 100, height: 80) && canvas.layers.count == 1)
        try history.goToSnapshot(snapshot.id, on: canvas)
        #expect(look(canvas) == start)
        #expect(canvas.selection.marquee?.bounds == mask.bounds)
        #expect(canvas.layers.last?.adjustment == .invert && canvas.activeLayerIndex == 2)
        history.undo(on: canvas)
        #expect(look(canvas) == cropped)
        // And every step still undoes, back to the start.
        while history.canUndo { history.undo(on: canvas) }
        #expect(canvas.layers.count == 1 && canvas.size == IntSize(width: 300, height: 300))
    }

    @Test func itWorksWhenHistoryIsMovedOutOfMemory() throws {
        let canvas = canvas(64), history = History(byteBudget: 64 * 64 * 4)
        let snapshot = try history.takeSnapshot(named: "White", of: canvas)
        let white = look(canvas)
        var looks: [[Int]] = []
        for index in 0..<4 {
            fill(canvas.bounds, with: Pixel(r: UInt8(index * 50), g: 0, b: 0), on: canvas, history: history)
            try history.goToSnapshot(snapshot.id, on: canvas)
            #expect(look(canvas) == white)
            history.undo(on: canvas)
            looks.append(look(canvas))
            history.redo(on: canvas)
        }
        while history.canUndo { history.undo(on: canvas) }
        #expect(look(canvas) == white)
        while history.canRedo { history.redo(on: canvas) }
        #expect(look(canvas) == white)
        #expect(history.byteCount <= history.byteBudget)
    }

    @Test func thereAreAtMostTenAndTheyCanBeRenamedAndDeleted() throws {
        let canvas = canvas(16), history = History(byteBudget: .max)
        for index in 1...10 { try history.takeSnapshot(named: "Snapshot \(index)", of: canvas) }
        #expect(throws: HistorySnapshot.Failure.full) { try history.takeSnapshot(named: "One more", of: canvas) }
        let first = history.snapshots[0].id
        #expect(history.renameSnapshot(first, to: "  Start "))
        #expect(!history.renameSnapshot(first, to: " "))
        #expect(history.snapshots[0].name == "Start")
        history.deleteSnapshot(first)
        #expect(history.snapshots.count == 9 && history.snapshots[0].name == "Snapshot 2")
        try history.takeSnapshot(named: "One more", of: canvas)
        #expect(history.snapshots.count == 10)
    }

    @Test func removingUndoHistoryRemovesSnapshotsToo() throws {
        let canvas = canvas(16), history = History(byteBudget: .max)
        try history.takeSnapshot(named: "Before redacting", of: canvas)
        history.removeAll()
        #expect(history.snapshots.isEmpty && history.snapshotStore == nil)
    }

    @Test func aSnapshotOfEmptyAndAdjustmentLayersKeepsThemEmpty() throws {
        let canvas = canvas(32), history = History(byteBudget: .max)
        LayerActions.add(canvas: canvas, history: history, context: context)
        let snapshot = try history.takeSnapshot(named: "Empty layer", of: canvas)
        fill(canvas.bounds, with: red, on: canvas, history: history)
        try history.goToSnapshot(snapshot.id, on: canvas)
        #expect(canvas.activeLayer.buffer.isUntouched)
    }

    /// Review U, finding 1: going to a snapshot of another size can't be taken back on one layer alone, which would
    /// leave that layer a different size from the canvas.
    @Test func goingToASnapshotOfAnotherSizeIsNotUndoneOnOneLayer() throws {
        let canvas = canvas(), history = History(byteBudget: .max)
        let snapshot = try history.takeSnapshot(named: "Start", of: canvas)
        #expect(ImageActions.crop(to: IntRect(x: 0, y: 0, width: 120, height: 80), canvas: canvas, history: history, context: context))
        try history.goToSnapshot(snapshot.id, on: canvas)
        #expect(history.undoOnLayerActionName(canvas.activeLayer.id, canvas: canvas) == nil)
        #expect(!history.undoOnLayer(canvas.activeLayer.id, canvas: canvas))
        #expect(canvas.layers.allSatisfy { $0.buffer.size == canvas.size })
    }

    /// Review U, finding 4: going to a snapshot counts as a change to the whole picture, so Revert Layer (which needs
    /// the same geometry steps as when saved) isn't offered after it.
    @Test func goingToASnapshotCountsAsAGeometryStep() throws {
        let canvas = canvas(), history = History(byteBudget: .max)
        let snapshot = try history.takeSnapshot(named: "Start", of: canvas)
        let before = history.geometrySteps
        try history.goToSnapshot(snapshot.id, on: canvas)
        #expect(history.geometrySteps != before)
        history.undo(on: canvas)
        #expect(history.geometrySteps == before)
    }

    /// Review U, finding 8: deleting a snapshot moves the rest to a fresh scratch file, and they still go back exactly;
    /// a snapshot doesn't keep a removed layer alive.
    @Test func deletingASnapshotKeepsTheOthersAndFreesRemovedLayers() throws {
        let canvas = canvas(), history = History(byteBudget: .max)
        weak var added: Layer?
        do {
            let layer = Layer(name: "Added", buffer: PixelBuffer(width: 300, height: 300, fill: red))
            canvas.insertLayer(layer, at: 1)
            added = layer
        }
        let first = try history.takeSnapshot(named: "First", of: canvas)
        fill(IntRect(x: 0, y: 0, width: 40, height: 40), with: .black, on: canvas, history: history)
        let second = try history.takeSnapshot(named: "Second", of: canvas)
        let kept = look(canvas)
        let oldStore = history.snapshotStore
        history.deleteSnapshot(first.id)
        #expect(history.snapshotStore != nil && history.snapshotStore !== oldStore)
        canvas.removeLayer(at: 1)
        #expect(added == nil)
        try history.goToSnapshot(second.id, on: canvas)
        #expect(look(canvas) == kept)
        #expect(canvas.layers[1].buffer[200, 200] == red)
    }
}
