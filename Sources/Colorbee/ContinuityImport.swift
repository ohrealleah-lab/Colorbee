import AppKit
import ColorbeeCore
import UniformTypeIdentifiers

/// File ▸ Import from iPhone or iPad (FR-11.7): macOS's Continuity Camera, which asks a nearby iPhone or iPad for a
/// photo, scanned pages or a sketch. AppKit builds the submenu; Colorbee says which kinds of data it takes and
/// receives them here. What arrives goes in as pages after the page shown, or, with no window open, as a new document.
///
/// A document window takes it two ways, because SwiftUI's views don't pass the request on: when a SwiftUI view has
/// focus, SwiftUI asks `DocumentView`'s `importsItemProviders`; when the canvas has, the canvas asks its window.
@MainActor
final class ContinuityImport: NSObject, NSServicesMenuRequestor {
    /// Scans come as a PDF, photos and sketches as a JPEG (with a TIFF copy of the same pixels, used only if it's
    /// the only kind offered).
    static let contentTypes: [UTType] = [.pdf, .jpeg, .heic, .png, .tiff]
    private static let types = contentTypes.map { NSPasteboard.PasteboardType($0.identifier) }

    /// The document that gets the pages; nil makes a new document.
    private let editor: () -> Editor?

    /// The owner keeps this for as long as it can import: AppKit doesn't keep the requestor it's given, and one
    /// made fresh for each check went away at once, greying out the menu (Leah, 2026-10-10).
    init(editor: @escaping () -> Editor?) {
        self.editor = editor
    }

    /// This, for a Continuity Camera request Colorbee can take: nothing sent, an image or PDF back.
    func requestor(sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?) -> ContinuityImport? {
        guard sendType == nil, let returnType, Self.types.contains(returnType) else { return nil }
        return self
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
        return Self.deliver(data, isPDF: type == .pdf, to: editor())
    }

    /// What SwiftUI hands on: the first item, in the first of `contentTypes` it comes in.
    static func receive(_ providers: [NSItemProvider], into editor: Editor) -> Bool {
        guard let provider = providers.first,
              let type = contentTypes.first(where: { type in provider.registeredContentTypes.contains { $0.conforms(to: type) } })
        else { return false }
        _ = provider.loadDataRepresentation(for: type) { [weak editor] data, error in
            Task { @MainActor in
                guard let editor else { return }
                guard let data else { return error.map { NSApp.presentError($0) } ?? () }
                _ = deliver(data, isPDF: type.conforms(to: .pdf), to: editor)
            }
        }
        return true
    }

    /// Adds the pages to `editor`'s document, or opens them as a new one.
    private static func deliver(_ data: Data, isPDF: Bool, to editor: Editor?) -> Bool {
        do {
            let stored = try pages(from: data, isPDF: isPDF)
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
