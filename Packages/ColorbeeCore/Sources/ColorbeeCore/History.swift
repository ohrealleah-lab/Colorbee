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
    private(set) var snapshots: [TileKey: TileSnapshot] = [:]
    public private(set) var dirtyRect: IntRect = .zero

    init(name: String, canvas: Canvas) {
        self.name = name
        self.canvas = canvas
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
    /// The pixels to write on the next undo or redo. Swapped with the buffer's contents each time.
    var pixels: [Pixel]

    init(key: TileKey, rect: IntRect, pixels: [Pixel]) {
        self.key = key
        self.rect = rect
        self.pixels = pixels
    }
}

public struct HistoryEntry {
    public let name: String
    let changes: [TileChange]
    let byteCount: Int
}

/// Linear undo/redo. Entries hold tile pre-images and are trimmed oldest-first to stay under a byte budget.
public final class History {
    public let byteBudget: Int
    public private(set) var byteCount = 0
    private var undoStack: [HistoryEntry] = []
    private var redoStack: [HistoryEntry] = []

    public init(byteBudget: Int) {
        self.byteBudget = byteBudget
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    public var undoCount: Int { undoStack.count }
    public var redoCount: Int { redoStack.count }
    public var undoActionName: String? { undoStack.last?.name }
    public var redoActionName: String? { redoStack.last?.name }

    public func beginEdit(_ name: String, on canvas: Canvas) -> Edit {
        Edit(name: name, canvas: canvas)
    }

    /// Records `edit` if it changed any pixels. Returns whether an entry was added.
    @discardableResult
    public func commit(_ edit: Edit) -> Bool {
        var changes: [TileChange] = []
        for (key, snapshot) in edit.snapshots {
            guard let layer = edit.canvas.layer(withID: key.layer) else { continue }
            if layer.buffer.pixels(in: snapshot.rect) != snapshot.pixels {
                changes.append(TileChange(key: key, rect: snapshot.rect, pixels: snapshot.pixels))
            }
        }
        guard !changes.isEmpty else { return false }

        for entry in redoStack {
            byteCount -= entry.byteCount
        }
        redoStack.removeAll()

        let entry = HistoryEntry(
            name: edit.name,
            changes: changes,
            byteCount: changes.reduce(0) { $0 + $1.pixels.count * MemoryLayout<Pixel>.stride }
        )
        undoStack.append(entry)
        byteCount += entry.byteCount
        trimToBudget()
        return true
    }

    /// Returns the region that changed, or nil if there was nothing to undo.
    @discardableResult
    public func undo(on canvas: Canvas) -> IntRect? {
        guard let entry = undoStack.popLast() else { return nil }
        let changed = apply(entry, to: canvas)
        redoStack.append(entry)
        return changed
    }

    @discardableResult
    public func redo(on canvas: Canvas) -> IntRect? {
        guard let entry = redoStack.popLast() else { return nil }
        let changed = apply(entry, to: canvas)
        undoStack.append(entry)
        return changed
    }

    private func apply(_ entry: HistoryEntry, to canvas: Canvas) -> IntRect {
        var changed = IntRect.zero
        for change in entry.changes {
            guard let layer = canvas.layer(withID: change.key.layer) else { continue }
            let current = layer.buffer.pixels(in: change.rect)
            layer.buffer.setPixels(change.pixels, in: change.rect)
            change.pixels = current
            changed = changed.union(change.rect)
        }
        return changed
    }

    private func trimToBudget() {
        while byteCount > byteBudget, undoStack.count > 1 {
            byteCount -= undoStack.removeFirst().byteCount
        }
    }
}
