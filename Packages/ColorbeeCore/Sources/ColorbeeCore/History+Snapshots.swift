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
        // One layer at a time, its bands on all cores, so only one layer's compressed copy is held at once (review U,
        // finding 7).
        var layers: [HistorySnapshot.StoredLayer] = []
        for layer in canvas.layers {
            var written: [SpillStore.Location]?
            if !layer.holdsNoPixels {
                let compressed = ParallelRows.map(bands.count) { try? SpillStore.compress(layer.buffer.pixels(in: bands[$0])) }
                var locations: [SpillStore.Location] = []
                for data in compressed {
                    guard let data, let location = try? store.append(data) else { throw .unreadable }
                    locations.append(location)
                }
                written = locations
            }
            layers.append(HistorySnapshot.StoredLayer(layer: layer, id: layer.id, name: layer.name, isVisible: layer.isVisible,
                                                      opacity: layer.opacity, blendMode: layer.blendMode, isLocked: layer.isLocked,
                                                      locksTransparency: layer.locksTransparency, adjustment: layer.adjustment,
                                                      clipsToLayerBelow: layer.clipsToLayerBelow, pixels: written))
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
        // Layers with no pixels stay empty, which takes no memory. Each layer's bands are read and decoded together,
        // one layer at a time (review U, finding 7).
        var buffers: [PixelBuffer] = []
        for stored in snapshot.layers {
            let buffer = PixelBuffer(size: snapshot.size)
            buffers.append(buffer)
            guard let locations = stored.pixels else { continue }
            guard locations.count == bands.count else { throw .unreadable }
            var data: [Data] = []
            for location in locations {
                guard let compressed = try? snapshotStore?.readCompressed(location) else { throw .unreadable }
                data.append(compressed)
            }
            let decoded = ParallelRows.map(bands.count) { index -> Bool in
                guard let pixels = try? SpillStore.decompress(data[index], count: bands[index].area) else { return false }
                buffer.setPixels(pixels, in: bands[index])
                return true
            }
            guard decoded.allSatisfy({ $0 }) else { throw .unreadable }
        }
        let edit = beginEdit("Go to Snapshot", on: canvas)
        edit.willChangeLayers()
        edit.replacesPicture = true
        let records = zip(snapshot.layers, buffers).map { stored, buffer in
            LayerStackState.Record(layer: stored.layer ?? Layer(name: stored.name, buffer: buffer, id: stored.id), name: stored.name, isVisible: stored.isVisible, opacity: stored.opacity,
                                   blendMode: stored.blendMode, isLocked: stored.isLocked, locksTransparency: stored.locksTransparency, adjustment: stored.adjustment,
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
        // The scratch file only grows, so it goes once nothing needs it, and otherwise the snapshots left are copied to
        // a fresh one, still compressed (review U, finding 8).
        guard !snapshots.isEmpty, let old = snapshotStore else {
            snapshotStore = nil
            return
        }
        // All or nothing: if anything can't be copied, every snapshot keeps the old file.
        guard let fresh = try? SpillStore() else { return }
        var moved: [[HistorySnapshot.StoredLayer]] = []
        for snapshot in snapshots {
            var layers: [HistorySnapshot.StoredLayer] = []
            for var stored in snapshot.layers {
                if let locations = stored.pixels {
                    var copied: [SpillStore.Location] = []
                    for location in locations {
                        guard let data = try? old.readCompressed(location), let place = try? fresh.append(data) else { return }
                        copied.append(place)
                    }
                    stored.pixels = copied
                }
                layers.append(stored)
            }
            moved.append(layers)
        }
        for (snapshot, layers) in zip(snapshots, moved) { snapshot.layers = layers }
        snapshotStore = fresh
    }
}
