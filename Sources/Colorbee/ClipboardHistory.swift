import AppKit
import ColorbeeCore
import CryptoKit
import ImageIO
import Observation

/// The last 10 images copied or pasted (FR-10.2), shared by every window and kept between launches in
/// Application Support. Pasting from here never touches the system clipboard.
@MainActor
@Observable
final class ClipboardHistory {
    static let shared = ClipboardHistory()
    static let capacity = 10

    struct Item: Identifiable, Codable {
        let id: UUID
        let date: Date
        let width: Int
        let height: Int
        /// Spots the same image copied twice, so it moves to the top instead of appearing again.
        let fingerprint: Int
    }

    private(set) var items: [Item] = []
    @ObservationIgnored private var thumbnails: [UUID: NSImage] = [:]
    @ObservationIgnored private let folder: URL

    private init() {
        folder = URL.applicationSupportDirectory.appending(path: "Colorbee/Clipboard History", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL), let stored = try? JSONDecoder().decode([Item].self, from: data) {
            items = stored.filter { FileManager.default.fileExists(atPath: imageURL($0).path) }
        }
    }

    private var indexURL: URL { folder.appending(path: "index.json") }
    private func imageURL(_ item: Item) -> URL { folder.appending(path: "\(item.id.uuidString).image") }

    /// Remembers an image (PNG, TIFF or any format macOS reads) that was just copied or pasted.
    func add(_ data: Data) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return }
        // A hash that's the same on every launch (Swift's own hashValue isn't).
        let fingerprint = SHA256.hash(data: data).withUnsafeBytes { $0.loadUnaligned(as: Int.self) }
        if let existing = items.firstIndex(where: { $0.fingerprint == fingerprint }) {
            let item = items.remove(at: existing)
            items.insert(Item(id: item.id, date: .now, width: item.width, height: item.height, fingerprint: fingerprint), at: 0)
        } else {
            let item = Item(id: UUID(), date: .now, width: width, height: height, fingerprint: fingerprint)
            guard (try? data.write(to: imageURL(item), options: .atomic)) != nil else { return }
            items.insert(item, at: 0)
            while items.count > Self.capacity { forget(items.removeLast()) }
        }
        save()
    }

    func data(for item: Item) -> Data? {
        try? Data(contentsOf: imageURL(item))
    }

    /// A small version for the panel; full-size screenshots would cost far more memory than ten tiles need.
    func thumbnail(for item: Item) -> NSImage? {
        if let cached = thumbnails[item.id] { return cached }
        guard let source = CGImageSourceCreateWithURL(imageURL(item) as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 480,
                  kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary) else { return nil }
        let thumbnail = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        thumbnails[item.id] = thumbnail
        return thumbnail
    }

    func clear() {
        items.forEach(forget)
        items = []
        save()
    }

    private func forget(_ item: Item) {
        thumbnails[item.id] = nil
        try? FileManager.default.removeItem(at: imageURL(item))
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) { try? data.write(to: indexURL, options: .atomic) }
    }
}
