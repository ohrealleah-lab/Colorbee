import AppKit
import ColorbeeCore

/// An image put on the clipboard before its PNG exists (FR-10.3): the PNG is made in the background, so
/// copying a very large image doesn't pause the window (NFR-6). An app that pastes before it's ready
/// waits only for the rest of the encoding.
final class ClipboardImage: NSObject, NSPasteboardItemDataProvider, @unchecked Sendable {
    /// The pasteboard doesn't keep its data providers alive, so the one on the clipboard is kept here.
    @MainActor private static var current: ClipboardImage?

    private let condition = NSCondition()
    private var png: Data?
    private var finished = false

    /// Puts an image on the clipboard. `pixels` is called in the background and must only read things
    /// nothing else changes (a snapshot or a fresh buffer). The PNG joins Clipboard History when it's ready, and
    /// `added` gets its item.
    @MainActor
    static func copy(colorSpace: CGColorSpace, pixels: @escaping @Sendable () -> PixelBuffer?,
                     added: @escaping @MainActor @Sendable (ClipboardHistory.Item.ID) -> Void = { _ in }) {
        let image = ClipboardImage()
        let item = NSPasteboardItem()
        item.setDataProvider(image, forTypes: [.png])
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
        current = image
        let space = UnsafeColorSpace(colorSpace)
        DispatchQueue.global(qos: .userInitiated).async {
            let png = pixels().flatMap { try? ImageCodec.encodePNG($0, colorSpace: space.value) }
            image.finish(with: png)
            if let png {
                // A later copy may have finished first; only what's still on the clipboard joins the history
                // (review B, finding 7).
                DispatchQueue.main.async {
                    if current === image, let id = ClipboardHistory.shared.add(png) { added(id) }
                }
            }
        }
    }

    private func finish(with data: Data?) {
        condition.lock()
        png = data
        finished = true
        condition.broadcast()
        condition.unlock()
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        condition.lock()
        while !finished { condition.wait() }
        let data = png
        condition.unlock()
        if let data { item.setData(data, forType: type) }
    }
}

/// Core Graphics color spaces are immutable, so handing one to the encoder's thread is safe.
private struct UnsafeColorSpace: @unchecked Sendable {
    let value: CGColorSpace
    init(_ value: CGColorSpace) { self.value = value }
}
