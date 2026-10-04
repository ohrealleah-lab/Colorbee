import CoreGraphics
import Foundation

/// The .colorproj format (FR-8.5): one file holding every layer and its settings, so a project reopens
/// exactly as it was saved. After a magic line comes a 4-byte length, a JSON manifest, then each pixel
/// layer's rows as LZ4-compressed BGRA, exactly as stored in memory (straight alpha, no rounding).
public enum ProjectFile {
    public static let fileExtension = "colorproj"
    static let magic = Data("COLORBEE PROJECT 1\n".utf8)

    public enum Failure: Error {
        case notAProject
        case damaged
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
    }

    /// An adjustment that reads back as none if it's of a kind this version doesn't know.
    struct AdjustmentEntry: Codable {
        var effect: Effect?

        init(_ effect: Effect) { self.effect = effect }
        init(from decoder: Decoder) throws { effect = try? Effect(from: decoder) }
        func encode(to encoder: Encoder) throws { try effect?.encode(to: encoder) }
    }

    /// Encodes `canvas`. A floating selection is stamped into a copy of its layer, so what's saved is what's seen.
    public static func encode(_ canvas: Canvas, transparentKey: Pixel? = nil, resampling: Resampling = .nearestNeighbor) throws -> Data {
        var blobs = Data()
        var entries: [LayerEntry] = []
        let saved = canvas.layerBuffersAsSaved(transparentKey: transparentKey, resampling: resampling)
        for layer in canvas.layers {
            var range: Range<Int>?
            if layer.adjustment == nil, let buffer = saved[layer.id] {
                let compressed = try (rows(of: buffer) as NSData).compressed(using: .lz4) as Data
                range = blobs.count..<(blobs.count + compressed.count)
                blobs.append(compressed)
            }
            entries.append(LayerEntry(
                id: layer.id.rawValue, name: layer.name, isVisible: layer.isVisible, opacity: layer.opacity,
                blendMode: layer.blendMode.rawValue, isLocked: layer.isLocked,
                adjustment: layer.adjustment.map(AdjustmentEntry.init), pixels: range
            ))
        }
        let manifest = Manifest(
            width: canvas.size.width, height: canvas.size.height,
            iccProfile: canvas.colorSpace.copyICCData() as Data?, colorSpaceName: canvas.colorSpace.name as String?,
            hasTransparentBackground: canvas.hasTransparentBackground,
            backgroundLayerID: canvas.backgroundLayerID?.rawValue,
            activeLayerIndex: canvas.activeLayerIndex, layers: entries
        )
        let json = try JSONEncoder().encode(manifest)
        var data = magic
        var length = UInt32(json.count).littleEndian
        data.append(Data(bytes: &length, count: 4))
        data.append(json)
        data.append(blobs)
        return data
    }

    public static func decode(_ data: Data) throws -> Canvas {
        guard data.starts(with: magic), data.count >= magic.count + 4 else { throw Failure.notAProject }
        let lengthStart = data.startIndex + magic.count
        let length = data[lengthStart..<(lengthStart + 4)].withUnsafeBytes { Int(UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))) }
        let jsonStart = lengthStart + 4
        guard data.endIndex >= jsonStart + length else { throw Failure.damaged }
        let manifest = try JSONDecoder().decode(Manifest.self, from: data[jsonStart..<(jsonStart + length)])
        let blobs = data[(jsonStart + length)...]
        // Repeated layer ids would make two layers one (review J, finding 19).
        guard Set(manifest.layers.map(\.id)).count == manifest.layers.count else { throw Failure.damaged }
        guard manifest.width > 0, manifest.height > 0, manifest.width <= ResizeSkew.maxSide, manifest.height <= ResizeSkew.maxSide,
              manifest.width * manifest.height <= ResizeSkew.maxArea, !manifest.layers.isEmpty else { throw Failure.damaged }

        // Pixels are RGB, so a profile of another kind (gray or CMYK, from a damaged or edited file) is
        // ignored; drawing text or shapes in one would fail (local sweep after review round 1).
        let colorSpace = [manifest.iccProfile.flatMap { CGColorSpace(iccData: $0 as CFData) },
                          manifest.colorSpaceName.flatMap { CGColorSpace(name: $0 as CFString) }]
            .compactMap { $0 }.first { $0.model == .rgb } ?? Canvas.defaultColorSpace
        let layers = try manifest.layers.map { entry -> Layer in
            let buffer = PixelBuffer(width: manifest.width, height: manifest.height)
            if let range = entry.pixels {
                // Checked against the size before adding, so a huge offset can't overflow (review J, finding 20).
                guard range.lowerBound >= 0, range.upperBound <= blobs.count else { throw Failure.damaged }
                let start = blobs.startIndex + range.lowerBound, end = blobs.startIndex + range.upperBound
                let raw = try (blobs[start..<end] as NSData).decompressed(using: .lz4) as Data
                guard raw.count == manifest.width * manifest.height * 4 else { throw Failure.damaged }
                fill(buffer, from: raw)
            }
            let layer = Layer(name: entry.name, buffer: buffer, id: LayerID(rawValue: entry.id))
            layer.isVisible = entry.isVisible
            layer.opacity = min(1, max(0, entry.opacity))
            layer.blendMode = BlendMode(rawValue: entry.blendMode) ?? .normal
            layer.isLocked = entry.isLocked
            layer.adjustment = entry.adjustment?.effect
            return layer
        }
        return Canvas(
            colorSpace: colorSpace, layers: layers, hasTransparentBackground: manifest.hasTransparentBackground,
            backgroundLayerID: manifest.backgroundLayerID.map { LayerID(rawValue: $0) },
            activeLayerIndex: manifest.activeLayerIndex
        )
    }

    /// The pixels without row padding, so the file doesn't depend on in-memory alignment.
    private static func rows(of buffer: PixelBuffer) -> Data {
        var data = Data(count: buffer.width * buffer.height * 4)
        data.withUnsafeMutableBytes { bytes in
            for y in 0..<buffer.height {
                (bytes.baseAddress! + y * buffer.width * 4).copyMemory(from: buffer.row(y), byteCount: buffer.width * 4)
            }
        }
        return data
    }

    private static func fill(_ buffer: PixelBuffer, from data: Data) {
        data.withUnsafeBytes { bytes in
            for y in 0..<buffer.height {
                UnsafeMutableRawPointer(buffer.row(y)).copyMemory(from: bytes.baseAddress! + y * buffer.width * 4, byteCount: buffer.width * 4)
            }
        }
    }
}
