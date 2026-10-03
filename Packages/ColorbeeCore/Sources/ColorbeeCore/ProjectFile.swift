import CoreGraphics
import Foundation

/// The .colorproj format (FR-8.5): one file holding every layer and its settings, so a project reopens
/// exactly as it was saved. After a magic line comes a 4-byte length, a JSON manifest, then each pixel
/// layer's rows as LZ4-compressed BGRA, exactly as stored in memory (straight alpha, no rounding).
public enum ProjectFile {
    public static let fileExtension = "colorproj"
    private static let magic = Data("COLORBEE PROJECT 1\n".utf8)

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
    public static func encode(_ canvas: Canvas, transparentKey: Pixel? = nil) throws -> Data {
        var blobs = Data()
        var entries: [LayerEntry] = []
        for layer in canvas.layers {
            var range: Range<Int>?
            if layer.adjustment == nil {
                var buffer = layer.buffer
                if let floating = canvas.selection.floating, floating.layerID == layer.id {
                    buffer = buffer.copy()
                    let pixels = floating.rendered(using: .nearestNeighbor, transparentKey: transparentKey)
                    let origin = IntPoint(x: floating.destination.minX, y: floating.destination.minY)
                    let area = IntRect(x: origin.x, y: origin.y, width: pixels.width, height: pixels.height).intersection(buffer.bounds)
                    for y in area.minY..<area.maxY {
                        let source = pixels.row(y - origin.y), target = buffer.row(y)
                        for x in area.minX..<area.maxX { target[x] = Compositing.over(target[x], source[x - origin.x]) }
                    }
                }
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
        guard manifest.width > 0, manifest.height > 0, !manifest.layers.isEmpty else { throw Failure.damaged }

        let colorSpace = manifest.iccProfile.flatMap { CGColorSpace(iccData: $0 as CFData) }
            ?? manifest.colorSpaceName.flatMap { CGColorSpace(name: $0 as CFString) }
            ?? Canvas.defaultColorSpace
        let layers = try manifest.layers.map { entry -> Layer in
            let buffer = PixelBuffer(width: manifest.width, height: manifest.height)
            if let range = entry.pixels {
                let start = blobs.startIndex + range.lowerBound, end = blobs.startIndex + range.upperBound
                guard range.lowerBound >= 0, end <= blobs.endIndex else { throw Failure.damaged }
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
