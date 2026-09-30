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
    private(set) var snapshots: [TileKey: TileSnapshot] = [:]
    public private(set) var dirtyRect: IntRect = .zero

    init(name: String, canvas: Canvas) {
        self.name = name
        self.canvas = canvas
        selectionBefore = canvas.selection
    }

    public func willModify(_ rect: IntRect, in layer: Layer) {
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

final class HistoryEntry {
    let name: String
    var changes: [TileChange]
    let selectionBefore: SelectionState
    var selectionAfter: SelectionState
    var isSpilled = false

    init(name: String, changes: [TileChange], selectionBefore: SelectionState, selectionAfter: SelectionState) {
        self.name = name
        self.changes = changes
        self.selectionBefore = selectionBefore
        self.selectionAfter = selectionAfter
    }

    var byteCount: Int { changes.reduce(0) { $0 + $1.byteCount } }
}

/// Linear undo/redo with no step limit. Entries hold tile pre-images; once they use more memory
/// than `byteBudget`, the entries furthest from the present are compressed to a scratch file.
public final class History {
    public let byteBudget: Int
    /// Bytes of tile data currently held in memory.
    public private(set) var byteCount = 0
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
        guard !changes.isEmpty || selectionChanged else { return false }

        if mergingIntoPrevious, redoStack.isEmpty, let previous = undoStack.last, load(previous) {
            // The previous step already holds the older pre-image for any tile it touched.
            let touched = Set(previous.changes.map(\.key))
            let added = changes.filter { !touched.contains($0.key) }
            previous.changes += added
            previous.selectionAfter = selectionAfter
            byteCount += added.reduce(0) { $0 + $1.byteCount }
        } else {
            discardRedo()
            let entry = HistoryEntry(name: edit.name, changes: changes, selectionBefore: edit.selectionBefore, selectionAfter: selectionAfter)
            undoStack.append(entry)
            byteCount += entry.byteCount
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
        spillToBudget()
        return changed
    }

    private func swapPixels(_ entry: HistoryEntry, on canvas: Canvas) -> IntRect {
        var changed = IntRect.zero
        for change in entry.changes {
            guard let layer = canvas.layer(withID: change.key.layer), let pixels = change.pixels else { continue }
            change.pixels = layer.buffer.pixels(in: change.rect)
            layer.buffer.setPixels(pixels, in: change.rect)
            changed = changed.union(change.rect)
        }
        return changed
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

    // MARK: Spilling

    private func spillToBudget() {
        while byteCount > byteBudget, let entry = nextSpillCandidate() {
            guard spill(entry) else { return }
        }
    }

    /// The in-memory entry furthest from the present, never the newest undo or redo step.
    private func nextSpillCandidate() -> HistoryEntry? {
        if let entry = undoStack.dropLast().first(where: { !$0.isSpilled && !$0.changes.isEmpty }) {
            return entry
        }
        return redoStack.dropLast().first { !$0.isSpilled && !$0.changes.isEmpty }
    }

    private func spill(_ entry: HistoryEntry) -> Bool {
        if spillStore == nil { spillStore = try? SpillStore() }
        guard let store = spillStore else { return false }
        var locations: [SpillStore.Location] = []
        for change in entry.changes {
            guard let pixels = change.pixels, let location = try? store.write(pixels) else { return false }
            locations.append(location)
        }
        for (change, location) in zip(entry.changes, locations) {
            change.pixels = nil
            change.spillLocation = location
        }
        entry.isSpilled = true
        byteCount -= entry.byteCount
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
        for (change, pixels) in zip(entry.changes, loaded) {
            change.pixels = pixels
            change.spillLocation = nil
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
