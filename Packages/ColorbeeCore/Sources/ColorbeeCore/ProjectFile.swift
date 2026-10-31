import CoreGraphics
import Foundation

/// The .colorproj format (FR-8.5): one file holding every layer and its settings, so a project reopens
/// exactly as it was saved. After a magic line comes a 4-byte length, a JSON manifest, then each pixel
/// layer's rows as LZ4-compressed BGRA, exactly as stored in memory (straight alpha, no rounding), in pieces that
/// compress on all cores (`LayerPixels`).
public enum ProjectFile {
    public static let fileExtension = "colorproj"
    static let magic = Data("COLORBEE PROJECT 1\n".utf8)

    public enum Failure: Error, LocalizedError {
        case notAProject
        case damaged

        public var errorDescription: String? {
            switch self {
            case .notAProject: "This file isn't a Colorbee project."
            case .damaged: "This project is damaged and can't be opened."
            }
        }
    }

    struct Manifest: Codable {
        var width: Int
        var height: Int
        var iccProfile: Data?
        var colorSpaceName: String?
        var hasTransparentBackground: Bool
        var backgroundLayerID: UUID?
        var activeLayerIndex: Int
        var layers: [LayerEntry]
        /// Missing from projects saved before stage 12.
        var cameraDetails: CameraDetails?
        /// Missing from projects saved before the Info panel, and when false.
        var locationRemoved: Bool?
        /// A one-page project's resolution (a PDF page's), in pixels per inch. Several pages keep theirs in the page
        /// list; missing means the default (review K, finding 6).
        var resolution: Double?
        /// Layer groups (stage 25), kept apart from `layers` so beta 7, which doesn't know them, opens every layer in
        /// order, just not grouped (Q25.5). Missing when there are none.
        var groups: [GroupEntry]?
        /// With groups, the active layer's place counting them; `activeLayerIndex` counts only `layers`, for beta 7.
        var activeIndexWithGroups: Int?
        /// Layer masks (stage 27), apart from `layers` like groups, so beta 7 shows the layers whole (Q28.5).
        var masks: [MaskEntry]?
    }

    /// A layer's mask: its own id, name and pixels, the layer it's on, and whether it's turned on.
    struct MaskEntry: Codable {
        var owner: UUID
        var layer: LayerEntry
        /// Missing means on.
        var enabled: Bool?
    }

    /// A group's row and where it goes in the full list of layers.
    struct GroupEntry: Codable {
        var at: Int
        var layer: LayerEntry
        /// Missing means Pass Through.
        var passesThrough: Bool?
    }

    struct LayerEntry: Codable {
        var id: UUID
        var name: String
        var isVisible: Bool
        var opacity: Double
        var blendMode: Int
        var isLocked: Bool
        var adjustment: AdjustmentEntry?
        /// Where this layer's compressed pixels sit in the data after the manifest. Nil for adjustment layers.
        var pixels: Range<Int>?
        /// How the pixels are split into pieces compressed on their own (`LayerPixels`): rows per piece, and each
        /// piece's compressed size. Missing from projects saved before the pieces, which are one stream per layer.
        var pieceRows: Int?
        var pieces: [Int]?
        /// Lock Transparent Pixels (stage 23); missing means no, so older versions open such a layer unlocked.
        var locksTransparency: Bool?
        /// An adjustment that changes only the layer below; missing means no.
        var clipped: Bool?
        /// The group it's in (stage 25); missing at the top.
        var group: UUID?
    }

    /// An adjustment that reads back as none if it's of a kind this version doesn't know.
    struct AdjustmentEntry: Codable {
        var effect: Effect?

        init(_ effect: Effect) { self.effect = effect }
        init(from decoder: Decoder) throws { effect = try? Effect(from: decoder) }
        func encode(to encoder: Encoder) throws { try effect?.encode(to: encoder) }
    }

    /// Encodes `canvas`. A floating selection is stamped into a copy of its layer, so what's saved is what's seen.
    /// `stampingFloating` off writes the layers exactly as they are, for parking a page (FR-11.6).
    /// `resolution` is a one-page project's (a PDF page's); several pages keep theirs in the page list.
    public static func encode(_ canvas: Canvas, transparentKey: Pixel? = nil, resampling: Resampling = .nearestNeighbor,
                              stampingFloating: Bool = true, resolution: Double = Page.defaultResolution) throws -> Data {
        var blobs = Data()
        var entries: [LayerEntry] = []
        let saved = stampingFloating ? canvas.layerBuffersAsSaved(transparentKey: transparentKey, resampling: resampling)
            : Dictionary(uniqueKeysWithValues: canvas.layers.filter { $0.adjustment == nil }.map { ($0.id, $0.buffer) })
        let pixelLayers = canvas.layers.filter { $0.isPixelLayer && saved[$0.id] != nil }
        let masked = canvas.layers.compactMap { layer in layer.mask.map { (owner: layer, mask: $0) } }
        let buffers = pixelLayers.map { saved[$0.id]! } + masked.map(\.mask.buffer)
        let compressed = Dictionary(uniqueKeysWithValues: zip(pixelLayers.map(\.id) + masked.map(\.mask.id), try LayerPixels.compress(buffers)))
        var groups: [GroupEntry] = []
        for (index, layer) in canvas.layers.enumerated() {
            var entry = LayerEntry(
                id: layer.id.rawValue, name: layer.name, isVisible: layer.isVisible, opacity: layer.opacity,
                blendMode: layer.blendMode.rawValue, isLocked: layer.isLocked,
                adjustment: layer.adjustment.map(AdjustmentEntry.init), pixels: nil
            )
            if layer.adjustment != nil, layer.clipsToLayerBelow { entry.clipped = true }
            if layer.locksTransparency { entry.locksTransparency = true }
            entry.group = layer.groupID?.rawValue
            if layer.isGroup {
                groups.append(GroupEntry(at: index, layer: entry, passesThrough: layer.passesThrough ? nil : false))
                continue
            }
            if let pixels = compressed[layer.id] {
                entry.pixels = blobs.count..<(blobs.count + pixels.data.count)
                entry.pieceRows = pixels.pieceRows
                entry.pieces = pixels.pieces
                blobs.append(pixels.data)
            }
            entries.append(entry)
        }
        var masks: [MaskEntry] = []
        for (owner, mask) in masked {
            var entry = LayerEntry(id: mask.id.rawValue, name: mask.name, isVisible: true, opacity: 1, blendMode: 0, isLocked: false,
                                   adjustment: nil, pixels: nil)
            if let pixels = compressed[mask.id], !mask.buffer.isUntouched {
                entry.pixels = blobs.count..<(blobs.count + pixels.data.count)
                entry.pieceRows = pixels.pieceRows
                entry.pieces = pixels.pieces
                blobs.append(pixels.data)
            }
            masks.append(MaskEntry(owner: owner.id.rawValue, layer: entry, enabled: owner.maskEnabled ? nil : false))
        }
        let active = canvas.activeLayerIndex
        let manifest = Manifest(
            width: canvas.size.width, height: canvas.size.height,
            iccProfile: canvas.colorSpace.copyICCData() as Data?, colorSpaceName: canvas.colorSpace.name as String?,
            hasTransparentBackground: canvas.hasTransparentBackground,
            backgroundLayerID: canvas.backgroundLayerID?.rawValue,
            activeLayerIndex: max(0, canvas.layers[..<active].filter { !$0.isGroup }.count - (canvas.activeLayer.isGroup ? 1 : 0)),
            layers: entries, cameraDetails: canvas.cameraDetails,
            locationRemoved: canvas.locationRemoved ? true : nil,
            resolution: resolution == Page.defaultResolution ? nil : resolution,
            groups: groups.isEmpty ? nil : groups, activeIndexWithGroups: groups.isEmpty ? nil : active,
            masks: masks.isEmpty ? nil : masks
        )
        let json = try JSONEncoder().encode(manifest)
        var data = magic
        var length = UInt32(json.count).littleEndian
        data.append(Data(bytes: &length, count: 4))
        data.append(json)
        data.append(blobs)
        return data
    }

    /// Puts a parked page's pixels back into the very layers they came from (FR-11.6), so the page's history
    /// still points at the right buffers. Only `layers` are filled; the canvas's layers mustn't have changed.
    /// Returns whether every layer was stored in pieces, as this version writes them.
    @discardableResult
    static func restore(_ data: Data, into canvas: Canvas, layers: Set<LayerID>) throws -> Bool {
        let (manifest, blobs) = try manifestAndBlobs(data)
        guard allEntries(manifest).map(\.entry.id) == canvas.layers.map(\.id.rawValue) else { throw Failure.damaged }
        var stored: [LayerPixels.Stored] = []
        let pairs = zip(allEntries(manifest).map(\.entry), canvas.layers).map { ($0, $1) }
            + (manifest.masks ?? []).compactMap { mask in canvas.layer(withID: LayerID(rawValue: mask.layer.id)).map { (mask.layer, $0) } }
        for (entry, layer) in pairs where layers.contains(layer.id) {
            guard let range = entry.pixels, range.lowerBound >= 0, range.upperBound <= blobs.count else { throw Failure.damaged }
            stored.append(LayerPixels.Stored(data: blobs[(blobs.startIndex + range.lowerBound)..<(blobs.startIndex + range.upperBound)],
                                             pieceRows: entry.pieceRows, pieces: entry.pieces, buffer: layer.buffer))
        }
        for layer in stored { layer.buffer.reuseContents() }
        try LayerPixels.decompress(stored)
        return stored.allSatisfy { $0.pieces != nil }
    }

    private static func manifestAndBlobs(_ data: Data) throws -> (Manifest, Data) {
        guard data.starts(with: magic), data.count >= magic.count + 4 else { throw Failure.notAProject }
        let lengthStart = data.startIndex + magic.count
        let length = data[lengthStart..<(lengthStart + 4)].withUnsafeBytes { Int(UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))) }
        let jsonStart = lengthStart + 4
        guard data.endIndex >= jsonStart + length else { throw Failure.damaged }
        let manifest = try JSONDecoder().decode(Manifest.self, from: data[jsonStart..<(jsonStart + length)])
        return (manifest, data[(jsonStart + length)...])
    }

    // MARK: Pages (FR-11.6)

    /// Several pages: a magic line, a 4-byte length, a JSON list of pages, then each page as a one-page project.
    static let pagesMagic = Data("COLORBEE PROJECT 2\n".utf8)

    struct PagesManifest: Codable {
        var currentIndex: Int
        var pages: [PageEntry]
    }

    struct PageEntry: Codable {
        var resolution: Double
        var project: Range<Int>
        var thumbnail: ThumbnailEntry?
    }

    struct ThumbnailEntry: Codable {
        var width: Int
        var height: Int
        /// BGRA, row after row.
        var pixels: Data
    }

    /// A page read from a project, its pixels still compressed: `Page(parked:)` makes it without decoding them.
    public struct StoredPage: Sendable {
        public let project: Data
        public let resolution: Double
        public let thumbnail: Thumbnail?

        public init(project: Data, resolution: Double, thumbnail: Thumbnail?) {
            self.project = project
            self.resolution = resolution
            self.thumbnail = thumbnail
        }
    }

    /// Writes `pages`; one page is written as a one-page project, which older versions read too. A parked page's
    /// bytes are used as they are.
    public static func encode(pages: [Page], currentIndex: Int, transparentKey: Pixel? = nil, resampling: Resampling = .nearestNeighbor) throws -> Data {
        try encode(stored: pages.map { page in
            StoredPage(project: try page.projectData(transparentKey: transparentKey, resampling: resampling), resolution: page.resolution,
                       thumbnail: page.thumbnail())
        }, currentIndex: currentIndex)
    }

    /// Writes pages already in one-page project form (a save copy holds them like this).
    public static func encode(stored pages: [StoredPage], currentIndex: Int) throws -> Data {
        if pages.count == 1 { return try settingResolution(pages[0].resolution, of: pages[0].project) }
        var projects = Data()
        var entries: [PageEntry] = []
        for page in pages {
            let project = page.project
            let thumbnail = page.thumbnail.map { thumbnail in
                ThumbnailEntry(width: thumbnail.width, height: thumbnail.height,
                               pixels: thumbnail.pixels.withUnsafeBytes { Data($0) })
            }
            entries.append(PageEntry(resolution: page.resolution, project: projects.count..<(projects.count + project.count), thumbnail: thumbnail))
            projects.append(project)
        }
        let json = try JSONEncoder().encode(PagesManifest(currentIndex: currentIndex, pages: entries))
        var data = pagesMagic
        var length = UInt32(json.count).littleEndian
        data.append(Data(bytes: &length, count: 4))
        data.append(json)
        data.append(projects)
        return data
    }

    /// Makes `count` pages (PDF pages, image frames), four at a time, and stores each at once as a one-page project
    /// with its thumbnail, so a long document never holds more than a few pages' pixels at a time. Each page in work
    /// holds about three full-size copies, so four keeps a long PDF at 300 DPI well within memory (review L, finding 7).
    public static func storedPages(count: Int, make: (Int) throws -> (canvas: Canvas, resolution: Double)) throws -> [StoredPage] {
        let lanes = min(4, count)
        let made = ParallelRows.map(lanes) { lane -> [(Int, Result<StoredPage, Error>)] in
            stride(from: lane, to: count, by: lanes).map { index in
                (index, Result {
                    let (canvas, resolution) = try make(index)
                    return StoredPage(project: try encode(canvas), resolution: resolution, thumbnail: canvas.thumbnail(maxSide: 160))
                })
            }
        }
        return try made.joined().sorted { $0.0 < $1.0 }.map { try $0.1.get() }
    }

    /// `project` (a one-page project) with `resolution` recorded in its manifest. The pixels are left as they are.
    static func settingResolution(_ resolution: Double, of project: Data) throws -> Data {
        var (manifest, blobs) = try manifestAndBlobs(project)
        guard manifest.resolution != resolution else { return project }
        manifest.resolution = resolution == Page.defaultResolution ? nil : resolution
        let json = try JSONEncoder().encode(manifest)
        var data = magic
        var length = UInt32(json.count).littleEndian
        data.append(Data(bytes: &length, count: 4))
        data.append(json)
        data.append(blobs)
        return data
    }

    /// The pages of a project, one-page or several, without decoding their pixels.
    public static func storedPages(_ data: Data) throws -> (pages: [StoredPage], currentIndex: Int) {
        guard data.starts(with: pagesMagic) else {
            let (manifest, _) = try manifestAndBlobs(data)
            let resolution = manifest.resolution.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? Page.defaultResolution
            return ([StoredPage(project: data, resolution: resolution, thumbnail: nil)], 0)
        }
        guard data.count >= pagesMagic.count + 4 else { throw Failure.damaged }
        let lengthStart = data.startIndex + pagesMagic.count
        let length = data[lengthStart..<(lengthStart + 4)].withUnsafeBytes { Int(UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))) }
        let jsonStart = lengthStart + 4
        guard data.endIndex >= jsonStart + length else { throw Failure.damaged }
        let manifest = try JSONDecoder().decode(PagesManifest.self, from: data[jsonStart..<(jsonStart + length)])
        let projects = data[(jsonStart + length)...]
        guard !manifest.pages.isEmpty else { throw Failure.damaged }
        let pages = try manifest.pages.map { entry -> StoredPage in
            guard entry.project.lowerBound >= 0, entry.project.upperBound <= projects.count,
                  entry.resolution.isFinite, entry.resolution > 0 else { throw Failure.damaged }
            let project = Data(projects[(projects.startIndex + entry.project.lowerBound)..<(projects.startIndex + entry.project.upperBound)])
            let thumbnail = entry.thumbnail.flatMap { stored -> Thumbnail? in
                // Sizes from the file are bounded before multiplying, so a damaged file can't overflow (review K, finding 9).
                guard stored.width > 0, stored.height > 0, stored.width <= 4096, stored.height <= 4096,
                      stored.width * stored.height * 4 == stored.pixels.count else { return nil }
                return Thumbnail(width: stored.width, height: stored.height, pixels: stored.pixels.withUnsafeBytes { Array($0.bindMemory(to: Pixel.self)) })
            }
            return StoredPage(project: project, resolution: entry.resolution, thumbnail: thumbnail)
        }
        return (pages, min(max(0, manifest.currentIndex), pages.count - 1))
    }

    /// A one-page project's layers and settings with empty buffers, and which layers hold pixels: a parked page.
    static func decodeParked(_ data: Data) throws -> (canvas: Canvas, pixelLayers: Set<LayerID>) {
        let (manifest, _) = try manifestAndBlobs(data)
        let entries = try checkedEntries(manifest)
        let layers = entries.map { layer(from: $0.entry, group: $0.group, buffer: PixelBuffer(width: manifest.width, height: manifest.height)) }
        let canvas = makeCanvas(manifest, layers: layers)
        var pixelLayers = Set(zip(entries, layers).filter { $0.0.entry.pixels != nil && $0.1.isPixelLayer }.map(\.1.id))
        for mask in attachMasks(manifest, to: canvas, buffer: { _ in PixelBuffer(width: manifest.width, height: manifest.height) }) where mask.entry.pixels != nil {
            pixelLayers.insert(mask.layer.id)
        }
        return (canvas, pixelLayers)
    }

    public static func decode(_ data: Data) throws -> Canvas {
        let (manifest, blobs) = try manifestAndBlobs(data)
        var stored: [LayerPixels.Stored] = []
        let layers = try checkedEntries(manifest).map { entry, group -> Layer in
            let buffer = PixelBuffer(width: manifest.width, height: manifest.height)
            if let range = entry.pixels, group == nil {
                // Checked against the size before adding, so a huge offset can't overflow (review J, finding 20).
                guard range.lowerBound >= 0, range.upperBound <= blobs.count else { throw Failure.damaged }
                let start = blobs.startIndex + range.lowerBound, end = blobs.startIndex + range.upperBound
                stored.append(LayerPixels.Stored(data: blobs[start..<end], pieceRows: entry.pieceRows, pieces: entry.pieces, buffer: buffer))
            }
            return layer(from: entry, group: group, buffer: buffer)
        }
        let canvas = makeCanvas(manifest, layers: layers)
        _ = try attachMasks(manifest, to: canvas) { entry in
            let buffer = PixelBuffer(width: manifest.width, height: manifest.height)
            if let range = entry.pixels {
                guard range.lowerBound >= 0, range.upperBound <= blobs.count else { throw Failure.damaged }
                let start = blobs.startIndex + range.lowerBound, end = blobs.startIndex + range.upperBound
                stored.append(LayerPixels.Stored(data: blobs[start..<end], pieceRows: entry.pieceRows, pieces: entry.pieces, buffer: buffer))
            }
            return buffer
        }
        try LayerPixels.decompress(stored)
        return canvas
    }

    /// Puts each mask in the manifest on its layer, its pixels in the buffer `buffer` gives. Masks of layers that aren't
    /// there are left out.
    private static func attachMasks(_ manifest: Manifest, to canvas: Canvas,
                                    buffer: (LayerEntry) throws -> PixelBuffer) rethrows -> [(entry: LayerEntry, layer: Layer)] {
        var attached: [(entry: LayerEntry, layer: Layer)] = []
        for entry in manifest.masks ?? [] {
            guard let owner = canvas.layers.first(where: { $0.id.rawValue == entry.owner }), owner.mask == nil,
                  canvas.layer(withID: LayerID(rawValue: entry.layer.id)) == nil else { continue }
            let mask = Layer(name: entry.layer.name, buffer: try buffer(entry.layer), id: LayerID(rawValue: entry.layer.id))
            owner.mask = mask
            owner.maskEnabled = entry.enabled ?? true
            attached.append((entry.layer, mask))
        }
        return attached
    }

    /// Every layer and group, in order: the groups put back at their places among the layers (stage 25).
    static func allEntries(_ manifest: Manifest) -> [(entry: LayerEntry, group: GroupEntry?)] {
        var result: [(entry: LayerEntry, group: GroupEntry?)] = manifest.layers.map { ($0, nil) }
        for group in (manifest.groups ?? []).sorted(by: { $0.at < $1.at }) {
            result.insert((group.layer, group), at: min(max(0, group.at), result.count))
        }
        return result
    }

    /// `allEntries`, refusing a damaged manifest.
    private static func checkedEntries(_ manifest: Manifest) throws -> [(entry: LayerEntry, group: GroupEntry?)] {
        let entries = allEntries(manifest)
        // Repeated layer ids would make two layers one (review J, finding 19).
        guard Set(entries.map(\.entry.id)).count == entries.count,
              manifest.width > 0, manifest.height > 0, manifest.width <= ResizeSkew.maxSide, manifest.height <= ResizeSkew.maxSide,
              manifest.width * manifest.height <= ResizeSkew.maxArea, !entries.isEmpty else { throw Failure.damaged }
        return entries
    }

    private static func layer(from entry: LayerEntry, group: GroupEntry?, buffer: PixelBuffer) -> Layer {
        let layer = Layer(name: entry.name, buffer: buffer, id: LayerID(rawValue: entry.id), isGroup: group != nil)
        layer.isVisible = entry.isVisible
        layer.opacity = min(1, max(0, entry.opacity))
        layer.blendMode = BlendMode(rawValue: entry.blendMode) ?? .normal
        layer.isLocked = entry.isLocked
        layer.adjustment = group == nil ? entry.adjustment?.effect : nil
        layer.locksTransparency = entry.locksTransparency == true && layer.adjustment == nil
        layer.clipsToLayerBelow = entry.clipped == true && layer.adjustment != nil
        layer.groupID = entry.group.map { LayerID(rawValue: $0) }
        layer.passesThrough = group?.passesThrough ?? true
        return layer
    }

    private static func makeCanvas(_ manifest: Manifest, layers: [Layer]) -> Canvas {
        // Pixels are RGB, so a profile of another kind (gray or CMYK, from a damaged or edited file) is
        // ignored; drawing text or shapes in one would fail (local sweep after review round 1).
        let colorSpace = [manifest.iccProfile.flatMap { CGColorSpace(iccData: $0 as CFData) },
                          manifest.colorSpaceName.flatMap { CGColorSpace(name: $0 as CFString) }]
            .compactMap { $0 }.first { $0.model == .rgb } ?? Canvas.defaultColorSpace
        let canvas = Canvas(
            colorSpace: colorSpace, layers: layers, hasTransparentBackground: manifest.hasTransparentBackground,
            backgroundLayerID: manifest.backgroundLayerID.map { LayerID(rawValue: $0) },
            activeLayerIndex: manifest.activeIndexWithGroups ?? manifest.activeLayerIndex
        )
        canvas.cameraDetails = manifest.cameraDetails
        canvas.locationRemoved = manifest.locationRemoved == true
        // A damaged or hand-edited file can't leave a group torn apart.
        canvas.keepGroupsTogether()
        return canvas
    }
}
