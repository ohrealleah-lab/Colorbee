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
        /// A one-page project's resolution (a PDF page's), in pixels per inch. Several pages keep theirs in the page
        /// list; missing means the default (review K, finding 6).
        var resolution: Double?
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
        let pixelLayers = canvas.layers.filter { $0.adjustment == nil && saved[$0.id] != nil }
        let compressed = Dictionary(uniqueKeysWithValues: zip(pixelLayers.map(\.id), try LayerPixels.compress(pixelLayers.map { saved[$0.id]! })))
        for layer in canvas.layers {
            var entry = LayerEntry(
                id: layer.id.rawValue, name: layer.name, isVisible: layer.isVisible, opacity: layer.opacity,
                blendMode: layer.blendMode.rawValue, isLocked: layer.isLocked,
                adjustment: layer.adjustment.map(AdjustmentEntry.init), pixels: nil
            )
            if let pixels = compressed[layer.id] {
                entry.pixels = blobs.count..<(blobs.count + pixels.data.count)
                entry.pieceRows = pixels.pieceRows
                entry.pieces = pixels.pieces
                blobs.append(pixels.data)
            }
            entries.append(entry)
        }
        let manifest = Manifest(
            width: canvas.size.width, height: canvas.size.height,
            iccProfile: canvas.colorSpace.copyICCData() as Data?, colorSpaceName: canvas.colorSpace.name as String?,
            hasTransparentBackground: canvas.hasTransparentBackground,
            backgroundLayerID: canvas.backgroundLayerID?.rawValue,
            activeLayerIndex: canvas.activeLayerIndex, layers: entries, cameraDetails: canvas.cameraDetails,
            resolution: resolution == Page.defaultResolution ? nil : resolution
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
        guard manifest.layers.map(\.id) == canvas.layers.map(\.id.rawValue) else { throw Failure.damaged }
        var stored: [LayerPixels.Stored] = []
        for (entry, layer) in zip(manifest.layers, canvas.layers) where layers.contains(layer.id) {
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
        guard Set(manifest.layers.map(\.id)).count == manifest.layers.count,
              manifest.width > 0, manifest.height > 0, manifest.width <= ResizeSkew.maxSide, manifest.height <= ResizeSkew.maxSide,
              manifest.width * manifest.height <= ResizeSkew.maxArea, !manifest.layers.isEmpty else { throw Failure.damaged }
        let colorSpace = [manifest.iccProfile.flatMap { CGColorSpace(iccData: $0 as CFData) },
                          manifest.colorSpaceName.flatMap { CGColorSpace(name: $0 as CFString) }]
            .compactMap { $0 }.first { $0.model == .rgb } ?? Canvas.defaultColorSpace
        let layers = manifest.layers.map { entry -> Layer in
            let layer = Layer(name: entry.name, buffer: PixelBuffer(width: manifest.width, height: manifest.height), id: LayerID(rawValue: entry.id))
            layer.isVisible = entry.isVisible
            layer.opacity = min(1, max(0, entry.opacity))
            layer.blendMode = BlendMode(rawValue: entry.blendMode) ?? .normal
            layer.isLocked = entry.isLocked
            layer.adjustment = entry.adjustment?.effect
            return layer
        }
        let canvas = Canvas(colorSpace: colorSpace, layers: layers, hasTransparentBackground: manifest.hasTransparentBackground,
                            backgroundLayerID: manifest.backgroundLayerID.map { LayerID(rawValue: $0) }, activeLayerIndex: manifest.activeLayerIndex)
        canvas.cameraDetails = manifest.cameraDetails
        let pixelLayers = Set(zip(manifest.layers, layers).filter { $0.0.pixels != nil && $0.1.adjustment == nil }.map(\.1.id))
        return (canvas, pixelLayers)
    }

    public static func decode(_ data: Data) throws -> Canvas {
        let (manifest, blobs) = try manifestAndBlobs(data)
        // Repeated layer ids would make two layers one (review J, finding 19).
        guard Set(manifest.layers.map(\.id)).count == manifest.layers.count else { throw Failure.damaged }
        guard manifest.width > 0, manifest.height > 0, manifest.width <= ResizeSkew.maxSide, manifest.height <= ResizeSkew.maxSide,
              manifest.width * manifest.height <= ResizeSkew.maxArea, !manifest.layers.isEmpty else { throw Failure.damaged }

        // Pixels are RGB, so a profile of another kind (gray or CMYK, from a damaged or edited file) is
        // ignored; drawing text or shapes in one would fail (local sweep after review round 1).
        let colorSpace = [manifest.iccProfile.flatMap { CGColorSpace(iccData: $0 as CFData) },
                          manifest.colorSpaceName.flatMap { CGColorSpace(name: $0 as CFString) }]
            .compactMap { $0 }.first { $0.model == .rgb } ?? Canvas.defaultColorSpace
        var stored: [LayerPixels.Stored] = []
        let layers = try manifest.layers.map { entry -> Layer in
            let buffer = PixelBuffer(width: manifest.width, height: manifest.height)
            if let range = entry.pixels {
                // Checked against the size before adding, so a huge offset can't overflow (review J, finding 20).
                guard range.lowerBound >= 0, range.upperBound <= blobs.count else { throw Failure.damaged }
                let start = blobs.startIndex + range.lowerBound, end = blobs.startIndex + range.upperBound
                stored.append(LayerPixels.Stored(data: blobs[start..<end], pieceRows: entry.pieceRows, pieces: entry.pieces, buffer: buffer))
            }
            let layer = Layer(name: entry.name, buffer: buffer, id: LayerID(rawValue: entry.id))
            layer.isVisible = entry.isVisible
            layer.opacity = min(1, max(0, entry.opacity))
            layer.blendMode = BlendMode(rawValue: entry.blendMode) ?? .normal
            layer.isLocked = entry.isLocked
            layer.adjustment = entry.adjustment?.effect
            return layer
        }
        try LayerPixels.decompress(stored)
        let canvas = Canvas(
            colorSpace: colorSpace, layers: layers, hasTransparentBackground: manifest.hasTransparentBackground,
            backgroundLayerID: manifest.backgroundLayerID.map { LayerID(rawValue: $0) },
            activeLayerIndex: manifest.activeLayerIndex
        )
        canvas.cameraDetails = manifest.cameraDetails
        return canvas
    }
}
