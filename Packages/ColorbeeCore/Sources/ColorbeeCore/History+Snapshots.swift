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
        // One layer at a time, its bands on all cores, so only one layer's compressed copy is held at once (review U,
        // finding 7).
        var layers: [HistorySnapshot.StoredLayer] = []
        func stored(_ layer: Layer) throws(HistorySnapshot.Failure) -> [SpillStore.Location]? {
            guard !layer.holdsNoPixels else { return nil }
            guard let compressed = SpillStore.compressedBands(of: layer.buffer), let locations = store.appendAll(compressed) else {
                throw .unreadable
            }
            return locations
        }
        for layer in canvas.layers {
            let written = try stored(layer)
            layers.append(HistorySnapshot.StoredLayer(layer: layer, id: layer.id, isGroup: layer.isGroup, settings: layer.settings,
                                                      maskID: layer.mask?.id, maskName: layer.mask?.name ?? "",
                                                      maskPixels: try layer.mask.flatMap { mask throws(HistorySnapshot.Failure) in try stored(mask) },
                                                      pixels: written))
        }
        let selection: SelectionState = canvas.selection.marquee.map { .marquee($0) } ?? .none
        let snapshot = HistorySnapshot(name: name, thumbnail: makeThumbnail?(canvas, thumbnailKey), size: canvas.size, layers: layers,
                                       activeIndex: canvas.activeLayerIndex, hasTransparentBackground: canvas.hasTransparentBackground,
                                       selection: selection)
        snapshots.append(snapshot)
        return snapshot
    }

    /// Puts the image back as the snapshot has it, as one step ("Go to Snapshot", Q12.5) that ⌘Z takes back. The
    /// canvas gets fresh copies, so later edits never change the snapshot.
    public func goToSnapshot(_ id: HistorySnapshot.ID, on canvas: Canvas) throws(HistorySnapshot.Failure) {
        guard let snapshot = snapshots.first(where: { $0.id == id }) else { throw .unreadable }
        // Layers with no pixels stay empty, which takes no memory. Each layer's bands are read and decoded together,
        // one layer at a time (review U, finding 7).
        func read(_ locations: [SpillStore.Location]?) throws(HistorySnapshot.Failure) -> PixelBuffer {
            let buffer = PixelBuffer(size: snapshot.size)
            guard let locations else { return buffer }
            guard snapshotStore?.readBands(locations, into: buffer) != nil else { throw .unreadable }
            return buffer
        }
        var buffers: [PixelBuffer] = []
        var masks: [Layer?] = []
        for stored in snapshot.layers {
            buffers.append(try read(stored.pixels))
            if stored.maskID != nil {
                // A new mask, so undoing this step brings back the mask object as it was, pixels and all, and older
                // strokes on it never land on this one.
                masks.append(Layer(name: stored.maskName, buffer: try read(stored.maskPixels)))
            } else {
                masks.append(nil)
            }
        }
        let edit = beginEdit("Go to Snapshot", on: canvas)
        edit.willChangeLayers()
        edit.replacesPicture = true
        let records = zip(zip(snapshot.layers, buffers), masks).map { pair, mask in
            let (stored, buffer) = pair
            let layer = stored.layer ?? Layer(name: stored.settings.name, buffer: buffer, id: stored.id, isGroup: stored.isGroup)
            return LayerStackState.Record(layer: layer, settings: stored.settings, mask: mask, buffer: buffer)
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

    /// After a redaction (Leah, 2026-11-01): the snapshots would still show what was redacted, so they go, scratch file
    /// and all. It isn't a step, so undoing the redaction doesn't bring them back.
    public func deleteAllSnapshots() {
        snapshots = []
        snapshotStore = nil
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
            func copied(_ locations: [SpillStore.Location]?) -> [SpillStore.Location]?? {
                guard let locations else { return .some(nil) }
                var copies: [SpillStore.Location] = []
                for location in locations {
                    guard let data = try? old.readCompressed(location), let place = try? fresh.append(data) else { return nil }
                    copies.append(place)
                }
                return copies
            }
            for var stored in snapshot.layers {
                guard let pixels = copied(stored.pixels), let maskPixels = copied(stored.maskPixels) else { return }
                stored.pixels = pixels
                stored.maskPixels = maskPixels
                layers.append(stored)
            }
            moved.append(layers)
        }
        for (snapshot, layers) in zip(snapshots, moved) { snapshot.layers = layers }
        snapshotStore = fresh
    }
}
