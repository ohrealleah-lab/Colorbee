import AppKit

/// Sends camera RAW files to the Develop window instead of opening them straight away (FR-11.8). Every way of
/// opening goes through here: File ▸ Open, Open Recent, drag and drop, and Finder.
@MainActor
final class DocumentController: NSDocumentController {
    override func openDocument(withContentsOf url: URL, display displayDocument: Bool,
                               completionHandler: @escaping (NSDocument?, Bool, (any Error)?) -> Void) {
        guard RawDeveloper.isRAW(url) else {
            return super.openDocument(withContentsOf: url, display: displayDocument, completionHandler: completionHandler)
        }
        DevelopWindowController.develop(url)
        completionHandler(nil, false, nil)
    }
}
