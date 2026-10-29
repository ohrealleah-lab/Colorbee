import Foundation

/// A named copy of a page's image in the History panel (FR-9.7 item 4), such as "Before dramatic". It keeps its own
/// copy, so it survives any later edit, undo or crop (Q12.1). The copy is compressed to a scratch file straight away,
/// so it takes almost no memory; it isn't saved in the project (Q12.2).
public final class HistorySnapshot: Identifiable {
    public let id = UUID()
    public internal(set) var name: String
    /// How the image looked, for the History panel.
    public let thumbnail: Thumbnail?
    let size: IntSize
    let layers: [StoredLayer]
    let activeIndex: Int
    let hasTransparentBackground: Bool
    let selection: SelectionState

    /// A layer as it was: its settings, and where its pixels are in `History.snapshotStore`.
    struct StoredLayer {
        /// The layer object itself, as undo steps keep it, so going to the snapshot gives back the same layer.
        let layer: Layer
        let name: String
        let isVisible: Bool
        let opacity: Double
        let blendMode: BlendMode
        let isLocked: Bool
        let locksTransparency: Bool
        let adjustment: Effect?
        let clipsToLayerBelow: Bool
        /// One band of rows each (`GeometryChange.bands`); nil for a layer with no pixels (empty or an adjustment).
        let pixels: [SpillStore.Location]?
    }

    init(name: String, thumbnail: Thumbnail?, size: IntSize, layers: [StoredLayer], activeIndex: Int,
         hasTransparentBackground: Bool, selection: SelectionState) {
        self.name = name
        self.thumbnail = thumbnail
        self.size = size
        self.layers = layers
        self.activeIndex = activeIndex
        self.hasTransparentBackground = hasTransparentBackground
        self.selection = selection
    }

    public enum Failure: Error, Equatable {
        /// `History.snapshotLimit` snapshots already (Q12.1).
        case full
        /// The scratch file couldn't be written or read back.
        case unreadable
    }
}
