import Foundation

/// History Snapshots (FR-9.7 item 4): named copies of the image, separate from the undo steps.
extension History {
    /// The most a page keeps (Q12.1): each is a copy of every layer, compressed on disk.
    public static let snapshotLimit = 10

    /// Copies the image as it is now under `name`. The floating selection should be placed first: only a marquee is
    /// kept.
    @discardableResult
    public func takeSnapshot(named name: String, of canvas: Canvas) throws(HistorySnapshot.Failure) -> HistorySnapshot {
        guard snapshots.count < Self.snapshotLimit else { throw .full }
        if snapshotStore == nil { snapshotStore = try? SpillStore() }
        guard let store = snapshotStore else { throw .unreadable }
        let bands = GeometryChange.bands(of: canvas.size)
        let pixelLayers = canvas.layers.filter { !$0.holdsNoPixels }
        // Every band of every layer compresses on all cores, then they're written in order.
        let compressed = ParallelRows.map(pixelLayers.count * bands.count) { index in
            try? SpillStore.compress(pixelLayers[index / bands.count].buffer.pixels(in: bands[index % bands.count]))
        }
        var locations: [ObjectIdentifier: [SpillStore.Location]] = [:]
        for (index, layer) in pixelLayers.enumerated() {
            var written: [SpillStore.Location] = []
            for data in compressed[(index * bands.count)..<((index + 1) * bands.count)] {
                guard let data, let location = try? store.append(data) else { throw .unreadable }
                written.append(location)
            }
            locations[ObjectIdentifier(layer)] = written
        }
        let layers = canvas.layers.map { layer in
            HistorySnapshot.StoredLayer(layer: layer, name: layer.name, isVisible: layer.isVisible, opacity: layer.opacity,
                                        blendMode: layer.blendMode, isLocked: layer.isLocked, adjustment: layer.adjustment,
                                        clipsToLayerBelow: layer.clipsToLayerBelow, pixels: locations[ObjectIdentifier(layer)])
        }
        let selection: SelectionState = canvas.selection.marquee.map { .marquee($0) } ?? .none
        let snapshot = HistorySnapshot(name: name, thumbnail: makeThumbnail?(canvas), size: canvas.size, layers: layers,
                                       activeIndex: canvas.activeLayerIndex, hasTransparentBackground: canvas.hasTransparentBackground,
                                       selection: selection)
        snapshots.append(snapshot)
        return snapshot
    }

    /// Puts the image back as the snapshot has it, as one step ("Go to Snapshot", Q12.5) that ⌘Z takes back. The
    /// canvas gets fresh copies, so later edits never change the snapshot.
    public func goToSnapshot(_ id: HistorySnapshot.ID, on canvas: Canvas) throws(HistorySnapshot.Failure) {
        guard let snapshot = snapshots.first(where: { $0.id == id }) else { throw .unreadable }
        let bands = GeometryChange.bands(of: snapshot.size)
        var data: [Data] = []
        for location in snapshot.layers.compactMap(\.pixels).joined() {
            guard let compressed = try? snapshotStore?.readCompressed(location) else { throw .unreadable }
            data.append(compressed)
        }
        // Layers with no pixels stay empty, which takes no memory.
        let buffers = snapshot.layers.map { _ in PixelBuffer(size: snapshot.size) }
        let pixelIndices = snapshot.layers.indices.filter { snapshot.layers[$0].pixels != nil }
        guard pixelIndices.count * bands.count == data.count else { throw .unreadable }
        let decoded = ParallelRows.map(data.count) { index -> Bool in
            let buffer = buffers[pixelIndices[index / bands.count]], band = bands[index % bands.count]
            guard let pixels = try? SpillStore.decompress(data[index], count: band.area) else { return false }
            buffer.setPixels(pixels, in: band)
            return true
        }
        guard decoded.allSatisfy({ $0 }) else { throw .unreadable }
        let edit = beginEdit("Go to Snapshot", on: canvas)
        edit.willChangeLayers()
        let records = zip(snapshot.layers, buffers).map { stored, buffer in
            LayerStackState.Record(layer: stored.layer, name: stored.name, isVisible: stored.isVisible, opacity: stored.opacity,
                                   blendMode: stored.blendMode, isLocked: stored.isLocked, adjustment: stored.adjustment,
                                   clipsToLayerBelow: stored.clipsToLayerBelow, buffer: buffer)
        }
        canvas.restore(LayerStackState(records: records, activeIndex: snapshot.activeIndex,
                                       hasTransparentBackground: snapshot.hasTransparentBackground, size: snapshot.size))
        canvas.selection = snapshot.selection
        commit(edit)
    }

    /// False if the name is empty.
    @discardableResult
    public func renameSnapshot(_ id: HistorySnapshot.ID, to name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let snapshot = snapshots.first(where: { $0.id == id }) else { return false }
        snapshot.name = name
        return true
    }

    public func deleteSnapshot(_ id: HistorySnapshot.ID) {
        snapshots.removeAll { $0.id == id }
        // The scratch file only grows, so it goes once nothing needs it.
        if snapshots.isEmpty { snapshotStore = nil }
    }
}
