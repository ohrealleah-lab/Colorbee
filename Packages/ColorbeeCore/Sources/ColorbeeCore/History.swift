import Foundation

public struct TileKey: Hashable, Sendable {
    public let layer: LayerID
    public let column: Int
    public let row: Int
}

/// The logical tile grid used for dirty tracking and undo. Storage stays contiguous.
public enum TileGrid {
    public static let tileSize = 256

    public static func rect(column: Int, row: Int, clippedTo bounds: IntRect) -> IntRect {
        IntRect(x: column * tileSize, y: row * tileSize, width: tileSize, height: tileSize).intersection(bounds)
    }

    /// Tile cells covering `rect`, which must not have negative coordinates.
    public static func cells(covering rect: IntRect) -> [(column: Int, row: Int)] {
        guard !rect.isEmpty else { return [] }
        var cells: [(column: Int, row: Int)] = []
        for row in (rect.minY / tileSize)...((rect.maxY - 1) / tileSize) {
            for column in (rect.minX / tileSize)...((rect.maxX - 1) / tileSize) {
                cells.append((column, row))
            }
        }
        return cells
    }
}

public final class TileSnapshot {
    public let rect: IntRect
    public let pixels: [Pixel]

    init(rect: IntRect, pixels: [Pixel]) {
        self.rect = rect
        self.pixels = pixels
    }
}

/// An in-progress change. Callers announce each region before writing to it, so the
/// original pixels of every touched tile are captured exactly once.
public final class Edit {
    public let name: String
    let canvas: Canvas
    let selectionBefore: SelectionState
    /// Record this edit even when only the selection changed (for example, moving a floating selection).
    public var recordsSelectionChange = false
    private(set) var geometryBefore: GeometryChange?
    private(set) var layersBefore: LayerStackState?
    private(set) var snapshots: [TileKey: TileSnapshot] = [:]
    public private(set) var dirtyRect: IntRect = .zero

    init(name: String, canvas: Canvas) {
        self.name = name
        self.canvas = canvas
        selectionBefore = canvas.selection
    }

    public func willModify(_ rect: IntRect, in layer: Layer) {
        precondition(layersBefore == nil, "Pixel edits can't be mixed with layer changes in one step")
        let bounds = layer.buffer.bounds
        let target = rect.intersection(bounds)
        guard !target.isEmpty else { return }
        dirtyRect = dirtyRect.union(target)
        for cell in TileGrid.cells(covering: target) {
            let key = TileKey(layer: layer.id, column: cell.column, row: cell.row)
            guard snapshots[key] == nil else { continue }
            let tileRect = TileGrid.rect(column: cell.column, row: cell.row, clippedTo: bounds)
            snapshots[key] = TileSnapshot(rect: tileRect, pixels: layer.buffer.pixels(in: tileRect))
        }
    }

    /// The tile's pixels as they were before this edit first touched it.
    public func originalTile(_ key: TileKey) -> TileSnapshot? {
        snapshots[key]
    }

    /// Call before replacing the canvas's size or layer buffers. The old buffers are kept, not copied,
    /// since geometry changes swap in new buffers rather than editing the old ones.
    public func willChangeGeometry() {
        precondition(snapshots.isEmpty, "Geometry changes can't be mixed with pixel edits in one step")
        if geometryBefore == nil { geometryBefore = canvas.currentGeometry }
    }

    /// Call before changing the layer stack: adding, removing, reordering or merging layers, or changing
    /// a layer's name, visibility, opacity, blend mode or lock. Merges swap in new buffers rather than
    /// editing pixels, so they can't be mixed with pixel edits in one step.
    public func willChangeLayers() {
        precondition(snapshots.isEmpty && geometryBefore == nil, "Layer changes can't be mixed with pixel or geometry edits in one step")
        if layersBefore == nil { layersBefore = canvas.layerStackState }
    }

    /// Puts back every pixel this edit has changed so far. Used for live previews that are recomputed.
    public func restoreOriginals() {
        for (key, snapshot) in snapshots {
            canvas.layer(withID: key.layer)?.buffer.setPixels(snapshot.pixels, in: snapshot.rect)
        }
    }
}

final class TileChange {
    let key: TileKey
    let rect: IntRect
    /// The pixels to write on the next undo or redo; swapped with the buffer's contents each time.
    /// Nil while the change is spilled to disk.
    var pixels: [Pixel]?
    var spillLocation: SpillStore.Location?

    init(key: TileKey, rect: IntRect, pixels: [Pixel]) {
        self.key = key
        self.rect = rect
        self.pixels = pixels
    }

    var byteCount: Int { rect.area * MemoryLayout<Pixel>.stride }
}

/// A whole-canvas state (size plus every layer's buffer), swapped in and out by undo and redo.
final class GeometryChange {
    let size: IntSize
    var buffers: [LayerID: PixelBuffer]?
    var spillLocations: [LayerID: SpillStore.Location]?

    init(size: IntSize, buffers: [LayerID: PixelBuffer]) {
        self.size = size
        self.buffers = buffers
    }

    var byteCount: Int {
        (buffers?.count ?? spillLocations?.count ?? 0) * size.width * size.height * MemoryLayout<Pixel>.stride
    }
}

final class HistoryEntry {
    let name: String
    var changes: [TileChange]
    var geometry: GeometryChange?
    var layers: LayerStackState?
    /// Memory held by buffers only this step keeps alive (a deleted or merged-away layer's pixels).
    var layerBytes = 0
    let selectionBefore: SelectionState
    var selectionAfter: SelectionState
    var isSpilled = false

    init(name: String, changes: [TileChange], selectionBefore: SelectionState, selectionAfter: SelectionState) {
        self.name = name
        self.changes = changes
        self.selectionBefore = selectionBefore
        self.selectionAfter = selectionAfter
    }

    var byteCount: Int { changes.reduce(0) { $0 + $1.byteCount } + (geometry?.byteCount ?? 0) + layerBytes }
    var hasSpillableData: Bool { !changes.isEmpty || geometry != nil }
}

/// Linear undo/redo with no step limit. Entries hold tile pre-images; once they use more memory
/// than `byteBudget`, the entries furthest from the present are compressed to a scratch file.
public final class History {
    public let byteBudget: Int
    /// Bytes of tile data currently held in memory.
    public private(set) var byteCount = 0
    /// Increases whenever a step is recorded, merged, undone or redone.
    public private(set) var revision = 0
    private var undoStack: [HistoryEntry] = []
    private var redoStack: [HistoryEntry] = []
    private var spillStore: SpillStore?

    public init(byteBudget: Int) {
        self.byteBudget = byteBudget
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    public var undoCount: Int { undoStack.count }
    public var redoCount: Int { redoStack.count }
    public var undoActionName: String? { undoStack.last?.name }
    public var redoActionName: String? { redoStack.last?.name }
    var spilledEntryCount: Int { (undoStack + redoStack).filter(\.isSpilled).count }

    public func beginEdit(_ name: String, on canvas: Canvas) -> Edit {
        Edit(name: name, canvas: canvas)
    }

    /// Whether the most recent step left this floating selection on the canvas.
    public func lastStepLeftFloating(_ id: UUID) -> Bool {
        redoStack.isEmpty && undoStack.last?.selectionAfter.floating?.id == id
    }

    /// Records `edit` if it changed pixels (or, when it asks to, the selection).
    /// With `mergingIntoPrevious`, the change is folded into the most recent step instead of adding one.
    @discardableResult
    public func commit(_ edit: Edit, mergingIntoPrevious: Bool = false) -> Bool {
        let selectionAfter = edit.canvas.selection
        var changes: [TileChange] = []
        for (key, snapshot) in edit.snapshots {
            guard let layer = edit.canvas.layer(withID: key.layer) else { continue }
            if layer.buffer.pixels(in: snapshot.rect) != snapshot.pixels {
                changes.append(TileChange(key: key, rect: snapshot.rect, pixels: snapshot.pixels))
            }
        }
        let selectionChanged = edit.recordsSelectionChange && !edit.selectionBefore.isSame(as: selectionAfter)
        if let layers = edit.layersBefore {
            guard !layers.isSame(as: edit.canvas.layerStackState) else { return false }
            discardRedo()
            let entry = HistoryEntry(name: edit.name, changes: [], selectionBefore: edit.selectionBefore, selectionAfter: selectionAfter)
            entry.layers = layers
            entry.layerBytes = Self.bytesOnlyIn(layers, comparedWith: edit.canvas.layerStackState)
            undoStack.append(entry)
            byteCount += entry.byteCount
            revision += 1
            spillToBudget()
            return true
        }
        if let geometry = edit.geometryBefore {
            discardRedo()
            let entry = HistoryEntry(name: edit.name, changes: [], selectionBefore: edit.selectionBefore, selectionAfter: selectionAfter)
            entry.geometry = geometry
            undoStack.append(entry)
            byteCount += entry.byteCount
            revision += 1
            spillToBudget()
            return true
        }
        guard !changes.isEmpty || selectionChanged else { return false }

        if mergingIntoPrevious, redoStack.isEmpty, let previous = undoStack.last, load(previous) {
            // The previous step already holds the older pre-image for any tile it touched.
            let touched = Set(previous.changes.map(\.key))
            let added = changes.filter { !touched.contains($0.key) }
            previous.changes += added
            previous.selectionAfter = selectionAfter
            byteCount += added.reduce(0) { $0 + $1.byteCount }
            revision += 1
        } else {
            discardRedo()
            let entry = HistoryEntry(name: edit.name, changes: changes, selectionBefore: edit.selectionBefore, selectionAfter: selectionAfter)
            undoStack.append(entry)
            byteCount += entry.byteCount
            revision += 1
        }
        spillToBudget()
        return true
    }

    /// Returns the region that changed (possibly empty), or nil if there was nothing to undo.
    @discardableResult
    public func undo(on canvas: Canvas) -> IntRect? {
        guard let entry = undoStack.last else { return nil }
        guard load(entry) else {
            discardUndo(through: undoStack.count - 1)
            return nil
        }
        undoStack.removeLast()
        let changed = swapPixels(entry, on: canvas)
        canvas.selection = entry.selectionBefore
        redoStack.append(entry)
        revision += 1
        spillToBudget()
        return changed
    }

    @discardableResult
    public func redo(on canvas: Canvas) -> IntRect? {
        guard let entry = redoStack.last else { return nil }
        guard load(entry) else {
            discardRedo()
            return nil
        }
        redoStack.removeLast()
        let changed = swapPixels(entry, on: canvas)
        canvas.selection = entry.selectionAfter
        undoStack.append(entry)
        revision += 1
        spillToBudget()
        return changed
    }

    private func swapPixels(_ entry: HistoryEntry, on canvas: Canvas) -> IntRect {
        if let layers = entry.layers {
            let current = canvas.layerStackState
            canvas.restore(layers)
            entry.layers = current
            byteCount -= entry.layerBytes
            entry.layerBytes = Self.bytesOnlyIn(current, comparedWith: layers)
            byteCount += entry.layerBytes
            return canvas.bounds
        }
        if let geometry = entry.geometry, let buffers = geometry.buffers {
            entry.geometry = canvas.currentGeometry
            canvas.replaceContents(size: geometry.size, buffers: buffers)
            return canvas.bounds
        }
        var changed = IntRect.zero
        for change in entry.changes {
            guard let layer = canvas.layer(withID: change.key.layer), let pixels = change.pixels else { continue }
            change.pixels = layer.buffer.pixels(in: change.rect)
            layer.buffer.setPixels(pixels, in: change.rect)
            changed = changed.union(change.rect)
        }
        return changed
    }

    /// Bytes of buffers in `state` that `other` doesn't use.
    private static func bytesOnlyIn(_ state: LayerStackState, comparedWith other: LayerStackState) -> Int {
        let used = Set(other.records.map { ObjectIdentifier($0.buffer) })
        var seen = Set<ObjectIdentifier>()
        return state.records.reduce(0) { total, record in
            let id = ObjectIdentifier(record.buffer)
            guard !used.contains(id), seen.insert(id).inserted else { return total }
            return total + record.buffer.width * record.buffer.height * MemoryLayout<Pixel>.stride
        }
    }

    private func discardRedo() {
        for entry in redoStack where !entry.isSpilled {
            byteCount -= entry.byteCount
        }
        redoStack.removeAll()
    }

    /// Drops undo steps up to and including `index`, oldest first. Used when spilled data can't be read back.
    private func discardUndo(through index: Int) {
        for entry in undoStack[...index] where !entry.isSpilled {
            byteCount -= entry.byteCount
        }
        undoStack.removeFirst(index + 1)
    }

    // MARK: Undo on Active Layer (FR-8.3)

    /// The step Undo on Active Layer would take back for `layer`, or nil if it isn't available.
    public func undoOnLayerActionName(_ layer: LayerID, canvas: Canvas) -> String? {
        candidate(for: layer, canvas: canvas).map { undoStack[$0].name }
    }

    /// Takes back the most recent step that changed `layer`, leaving later steps on other layers in place.
    /// It becomes a new step itself, so ⌘Z can bring the change back.
    @discardableResult
    public func undoOnLayer(_ layer: LayerID, canvas: Canvas) -> Bool {
        guard let index = candidate(for: layer, canvas: canvas) else { return false }
        let entry = undoStack[index]
        guard load(entry) else { return false }
        let reversal = HistoryEntry(name: "Undo \(entry.name)", changes: [], selectionBefore: canvas.selection, selectionAfter: canvas.selection)
        if let state = entry.layers, let record = state.records.first(where: { $0.layer.id == layer }), let target = canvas.layer(withID: layer) {
            // Put back only this layer's settings and pixels; the step before keeps the rest of the stack as it is now.
            let current = canvas.layerStackState
            target.name = record.name
            target.isVisible = record.isVisible
            target.opacity = record.opacity
            target.blendMode = record.blendMode
            target.isLocked = record.isLocked
            target.adjustment = record.adjustment
            target.buffer = record.buffer
            reversal.layers = current
            reversal.layerBytes = Self.bytesOnlyIn(current, comparedWith: canvas.layerStackState)
        } else {
            // Swapping writes the old pixels back and leaves the newer ones in the entry: the reversal's undo.
            _ = swapPixels(entry, on: canvas)
            reversal.changes = entry.changes
        }
        byteCount -= entry.byteCount
        undoStack.remove(at: index)
        discardRedo()
        undoStack.append(reversal)
        byteCount += reversal.byteCount
        revision += 1
        spillToBudget()
        return true
    }

    /// The newest undo step that changed `layer`, if it changed nothing else.
    private func candidate(for layer: LayerID, canvas: Canvas) -> Int? {
        let now = canvas.layerStackState
        guard let currentRecord = now.records.first(where: { $0.layer.id == layer }) else { return nil }
        for index in undoStack.indices.reversed() {
            let entry = undoStack[index]
            // A whole-canvas change replaced every layer's pixels; nothing older can be pulled out alone.
            if entry.geometry != nil { return nil }
            if let before = entry.layers {
                // Nothing newer touched this layer, so its record now is what this step left it as.
                guard let record = before.records.first(where: { $0.layer.id == layer }) else { return nil }
                let changedThisLayer = !(record.name == currentRecord.name && record.isVisible == currentRecord.isVisible
                    && record.opacity == currentRecord.opacity && record.blendMode == currentRecord.blendMode
                    && record.isLocked == currentRecord.isLocked && record.adjustment == currentRecord.adjustment
                    && record.buffer === currentRecord.buffer)
                guard changedThisLayer else { continue }
                // Only a step that changed just this layer, and kept the same layers in the same order, stands alone.
                let others = zip(before.records, now.records).allSatisfy { a, b in
                    a.layer === b.layer && (a.layer.id == layer || (a.name == b.name && a.isVisible == b.isVisible
                        && a.opacity == b.opacity && a.blendMode == b.blendMode && a.isLocked == b.isLocked
                        && a.adjustment == b.adjustment && a.buffer === b.buffer))
                }
                return before.records.count == now.records.count && others ? index : nil
            }
            let touched = entry.changes.contains { $0.key.layer == layer }
            guard touched else { continue }
            return entry.changes.allSatisfy { $0.key.layer == layer } ? index : nil
        }
        return nil
    }

    // MARK: Spilling

    private func spillToBudget() {
        while byteCount > byteBudget, let entry = nextSpillCandidate() {
            guard spill(entry) else { return }
        }
    }

    /// The in-memory entry furthest from the present, never the newest undo or redo step.
    private func nextSpillCandidate() -> HistoryEntry? {
        if let entry = undoStack.dropLast().first(where: { !$0.isSpilled && $0.hasSpillableData }) {
            return entry
        }
        return redoStack.dropLast().first { !$0.isSpilled && $0.hasSpillableData }
    }

    private func spill(_ entry: HistoryEntry) -> Bool {
        if spillStore == nil { spillStore = try? SpillStore() }
        guard let store = spillStore else { return false }
        var locations: [SpillStore.Location] = []
        for change in entry.changes {
            guard let pixels = change.pixels, let location = try? store.write(pixels) else { return false }
            locations.append(location)
        }
        var geometryLocations: [LayerID: SpillStore.Location] = [:]
        if let geometry = entry.geometry, let buffers = geometry.buffers {
            for (id, buffer) in buffers {
                guard let location = try? store.write(buffer.pixels(in: buffer.bounds)) else { return false }
                geometryLocations[id] = location
            }
        }
        let bytes = entry.byteCount
        for (change, location) in zip(entry.changes, locations) {
            change.pixels = nil
            change.spillLocation = location
        }
        if let geometry = entry.geometry {
            geometry.buffers = nil
            geometry.spillLocations = geometryLocations
        }
        entry.isSpilled = true
        byteCount -= bytes
        return true
    }

    /// Brings a spilled entry back into memory. Returns false if its data can't be read.
    private func load(_ entry: HistoryEntry) -> Bool {
        guard entry.isSpilled else { return true }
        guard let store = spillStore else { return false }
        var loaded: [[Pixel]] = []
        for change in entry.changes {
            guard let location = change.spillLocation,
                  let pixels = try? store.read(location, count: change.rect.area) else { return false }
            loaded.append(pixels)
        }
        var buffers: [LayerID: PixelBuffer] = [:]
        if let geometry = entry.geometry, let locations = geometry.spillLocations {
            for (id, location) in locations {
                guard let pixels = try? store.read(location, count: geometry.size.width * geometry.size.height) else { return false }
                let buffer = PixelBuffer(width: geometry.size.width, height: geometry.size.height)
                buffer.setPixels(pixels, in: buffer.bounds)
                buffers[id] = buffer
            }
        }
        for (change, pixels) in zip(entry.changes, loaded) {
            change.pixels = pixels
            change.spillLocation = nil
        }
        if let geometry = entry.geometry, geometry.spillLocations != nil {
            geometry.buffers = buffers
            geometry.spillLocations = nil
        }
        entry.isSpilled = false
        byteCount += entry.byteCount
        return true
    }
}

/// An append-only scratch file of LZ4-compressed tile data, deleted when the history goes away.
final class SpillStore {
    struct Location {
        let offset: UInt64
        let length: Int
    }

    enum Failure: Error {
        case corrupt
    }

    private let url: URL
    private let handle: FileHandle
    private var end: UInt64 = 0

    init() throws {
        url = FileManager.default.temporaryDirectory.appending(path: "colorbee-history-\(UUID().uuidString).bin")
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        handle = try FileHandle(forUpdating: url)
    }

    deinit {
        try? handle.close()
        try? FileManager.default.removeItem(at: url)
    }

    func write(_ pixels: [Pixel]) throws -> Location {
        let raw = pixels.withUnsafeBytes { Data($0) }
        let compressed = try (raw as NSData).compressed(using: .lz4) as Data
        try handle.seek(toOffset: end)
        try handle.write(contentsOf: compressed)
        let location = Location(offset: end, length: compressed.count)
        end += UInt64(compressed.count)
        return location
    }

    func read(_ location: Location, count: Int) throws -> [Pixel] {
        try handle.seek(toOffset: location.offset)
        guard let compressed = try handle.read(upToCount: location.length), compressed.count == location.length else {
            throw Failure.corrupt
        }
        let raw = try (compressed as NSData).decompressed(using: .lz4) as Data
        guard raw.count == count * MemoryLayout<Pixel>.stride else { throw Failure.corrupt }
        return raw.withUnsafeBytes { Array($0.bindMemory(to: Pixel.self)) }
    }
}
