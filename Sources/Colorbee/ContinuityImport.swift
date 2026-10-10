import AppKit
import ColorbeeCore
import UniformTypeIdentifiers

/// File ▸ Import from iPhone or iPad (FR-11.7): macOS's Continuity Camera, which asks a nearby iPhone or iPad for a
/// photo, scanned pages or a sketch. AppKit builds the submenu; Colorbee says which kinds of data it takes and
/// receives them here. What arrives goes in as pages after the page shown, or, with no window open, as a new document.
@MainActor
final class ContinuityImport: NSObject, NSServicesMenuRequestor {
    /// Scans come as a PDF, photos and sketches as a JPEG (with a TIFF copy of the same pixels, used only if it's
    /// the only kind offered).
    private static let types: [NSPasteboard.PasteboardType] = [
        .pdf, NSPasteboard.PasteboardType(UTType.jpeg.identifier), NSPasteboard.PasteboardType(UTType.heic.identifier), .png, .tiff,
    ]

    private weak var editor: Editor?

    private init(editor: Editor?) {
        self.editor = editor
    }

    /// The requestor for a Continuity Camera request, when it's one Colorbee can take: nothing sent, an image or PDF
    /// back. `editor` gets the pages; nil makes a new document.
    static func requestor(for editor: Editor?, sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?) -> ContinuityImport? {
        guard sendType == nil, let returnType, types.contains(returnType) else { return nil }
        return ContinuityImport(editor: editor)
    }

    nonisolated func writeSelection(to pasteboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        false
    }

    /// AppKit calls this on the main thread.
    nonisolated func readSelection(from pasteboard: NSPasteboard) -> Bool {
        nonisolated(unsafe) let pasteboard = pasteboard
        return MainActor.assumeIsolated { receive(from: pasteboard) }
    }

    private func receive(from pasteboard: NSPasteboard) -> Bool {
        let offered = pasteboard.types ?? []
        guard let type = Self.types.first(where: { offered.contains($0) }), let data = pasteboard.data(forType: type) else { return false }
        do {
            let stored = try Self.pages(from: data, isPDF: type == .pdf)
            if let editor {
                editor.importPages(stored)
            } else {
                try ImageDocument.open(stored)
            }
            return true
        } catch {
            NSApp.presentError(error)
            return false
        }
    }

    /// Each scanned page as the phone's own picture; a photo or sketch as one page at the usual resolution.
    private static func pages(from data: Data, isPDF: Bool) throws -> [ProjectFile.StoredPage] {
        if isPDF {
            let resolution = ImageDocument.pdfResolution
            return try ProjectFile.storedPages(count: try PDFPages.pageCount(data)) { index in
                try PDFPages.scannedPage(data, page: index, resolution: resolution)
            }
        }
        let decoded = try ImageCodec.decode(data)
        return try ProjectFile.storedPages(count: 1) { _ in
            (Canvas(colorSpace: decoded.colorSpace, layers: [Layer(name: "Background", buffer: decoded.buffer)],
                    hasTransparentBackground: decoded.buffer.hasTransparency), Page.defaultResolution)
        }
    }
}
