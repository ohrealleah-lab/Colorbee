import AppKit
import UniformTypeIdentifiers

/// Finding an image on the clipboard or in a drag (FR-10), whatever form another app put it in.
@MainActor
enum PasteboardImages {
    /// PNG and TIFF keep exact pixels, so they're preferred when an app offers several forms.
    private static let preferred: [NSPasteboard.PasteboardType] = [.png, .tiff]
    private static let imageFiles: [NSPasteboard.ReadingOptionKey: Any] = [
        .urlReadingFileURLsOnly: true,
        .urlReadingContentsConformToTypes: [UTType.image.identifier],
    ]

    /// Whether there's an image to paste. Only looks at what's offered, without fetching it, so it's
    /// quick enough for menus and works before an app has finished providing a large image.
    static func hasImage(_ pasteboard: NSPasteboard = .general) -> Bool {
        if pasteboard.availableType(from: preferred) != nil { return true }
        if imageTypes(pasteboard).first != nil { return true }
        if pasteboard.canReadObject(forClasses: [NSURL.self], options: imageFiles) { return true }
        return NSImage.canInit(with: pasteboard)
    }

    /// The image's data, in a form ImageCodec can read: PNG or TIFF if offered, then any other image type
    /// macOS can decode (HEIC, JPEG…), then an image file, then whatever AppKit itself can turn into an image.
    static func imageData(_ pasteboard: NSPasteboard = .general) -> Data? {
        for type in preferred + imageTypes(pasteboard) {
            if let data = pasteboard.data(forType: type), CGImageSourceCreateWithData(data as CFData, nil).flatMap({ CGImageSourceGetCount($0) > 0 }) == true {
                return data
            }
        }
        if let url = pasteboard.readObjects(forClasses: [NSURL.self], options: imageFiles)?.first as? URL,
           let data = try? Data(contentsOf: url) {
            return data
        }
        return (pasteboard.readObjects(forClasses: [NSImage.self])?.first as? NSImage)?.tiffRepresentation
    }

    /// Image types on the pasteboard other than PNG and TIFF, in the order the app offered them.
    private static func imageTypes(_ pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        (pasteboard.types ?? []).filter { type in
            !preferred.contains(type) && (UTType(type.rawValue)?.conforms(to: .image) ?? false)
        }
    }
}
