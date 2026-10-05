import Foundation

/// One page of a document (FR-11.6): an image of its own, with its own size, layers, selection and undo history.
///
/// A page that isn't being looked at is parked: its layers are compressed in memory, in exactly the form a
/// one-page project file stores them, and their memory is freed. Parking keeps every buffer object, so the
/// page's history still points at the right buffers when it comes back (see `History`'s eviction). Saving
/// reuses a parked page's bytes as they are.
public final class Page {
    public let id = UUID()
    public let canvas: Canvas
    public let history: History
    /// Pixels per inch, for Export as PDF: a PDF's pages keep the resolution they were opened at.
    public var resolution: Double
    /// The page as a one-page project, while it's parked.
    public private(set) var parked: Data?
    /// The layers whose memory was freed when parking (empty and adjustment layers have none).
    private var freedLayers: Set<LayerID> = []
    /// A small picture for the page sidebar, kept while parked.
    public private(set) var parkedThumbnail: Thumbnail?
    /// The bytes the page was last brought back from, with what they hold. If nothing has changed when the page is
    /// parked again, they're used as they are: no new copy is made, so visiting pages doesn't add up in memory, and
    /// switching is quicker (Leah's memory test, 2026-10-05).
    private var unparkedFrom: (data: Data, thumbnail: Thumbnail?, revision: Int, activeLayer: Int)?
    private let activeBudget: Int

    /// What a parked page's history may keep in memory.
    public static let parkedHistoryBudget = 16 << 20
    /// Resolution for pages that didn't come from a PDF (Retina screenshots).
    public static let defaultResolution = 144.0

    public init(canvas: Canvas, history: History, resolution: Double = Page.defaultResolution) {
        self.canvas = canvas
        self.history = history
        self.resolution = resolution
        activeBudget = history.byteBudget
    }

    /// A page read from a project, parked from the start: its pixels stay compressed until it's shown.
    public init(stored: ProjectFile.StoredPage, history: History) throws {
        let (canvas, pixelLayers) = try ProjectFile.decodeParked(stored.project)
        self.canvas = canvas
        self.history = history
        resolution = stored.resolution
        activeBudget = history.byteBudget
        parked = stored.project
        freedLayers = pixelLayers
        parkedThumbnail = stored.thumbnail
        history.byteBudget = min(activeBudget, Self.parkedHistoryBudget)
    }

    /// The page's small picture: kept while parked (worked out from the parked bytes if there's none yet), or
    /// made from the canvas.
    public func thumbnail(maxSide: Int = 160) -> Thumbnail? {
        if let parkedThumbnail { return parkedThumbnail }
        guard let parked else { return canvas.thumbnail(maxSide: maxSide) }
        parkedThumbnail = (try? ProjectFile.decode(parked))?.thumbnail(maxSide: maxSide)
        return parkedThumbnail
    }

    public var isParked: Bool { parked != nil }

    /// Compresses the page and frees its layers' memory. Any floating selection should be placed first.
    public func park(thumbnailSide: Int = 160) throws {
        guard parked == nil else { return }
        history.finishBackgroundWork()
        // Every change to a page goes through its history, so an unchanged revision means unchanged pixels and layers.
        let data: Data
        if let last = unparkedFrom, last.revision == history.revision, last.activeLayer == canvas.activeLayerIndex,
           canvas.selection.floating == nil {
            data = last.data
            parkedThumbnail = last.thumbnail ?? canvas.thumbnail(maxSide: thumbnailSide)
        } else {
            // The layers exactly as they are: these bytes go straight back into them.
            data = try ProjectFile.encode(canvas, stampingFloating: false)
            parkedThumbnail = canvas.thumbnail(maxSide: thumbnailSide)
        }
        unparkedFrom = nil
        freedLayers = []
        for layer in canvas.layers where layer.adjustment == nil && !layer.buffer.isUntouched {
            layer.buffer.discardContents()
            freedLayers.insert(layer.id)
        }
        parked = data
        history.byteBudget = min(activeBudget, Self.parkedHistoryBudget)
        history.keepWithinBudget(canvas: canvas)
    }

    /// Brings the parked pixels back into the page's own buffers.
    public func unpark() throws {
        guard let data = parked else { return }
        try ProjectFile.restore(data, into: canvas, layers: freedLayers)
        unparkedFrom = (data, parkedThumbnail, history.revision, canvas.activeLayerIndex)
        parked = nil
        parkedThumbnail = nil
        freedLayers = []
        history.byteBudget = activeBudget
    }

    /// The page as a one-page project: the parked bytes as they are, or encoded now.
    public func projectData(transparentKey: Pixel? = nil, resampling: Resampling = .nearestNeighbor) throws -> Data {
        if let parked { return parked }
        return try ProjectFile.encode(canvas, transparentKey: transparentKey, resampling: resampling)
    }
}
