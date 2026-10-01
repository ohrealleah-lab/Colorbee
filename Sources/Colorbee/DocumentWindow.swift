import AppKit
import ColorbeeCore

/// Handles document-level editing commands for whichever view in the window has focus.
final class DocumentWindow: NSWindow {
    weak var editor: Editor?

    private static let pasteboardImageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff]

    @objc func undo(_ sender: Any?) {
        editor?.undo()
    }

    @objc func redo(_ sender: Any?) {
        editor?.redo()
    }

    /// Copies the selection, or the whole image when nothing is selected (FR-10.3).
    @objc func copy(_ sender: Any?) {
        guard let editor else { return }
        do {
            let png = try editor.selectedPixels().map {
                try ImageCodec.encodePNG($0, colorSpace: editor.canvas.colorSpace)
            } ?? editor.flattenedPNG()
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setData(png, forType: .png)
        } catch {
            presentError(error)
        }
    }

    @objc func cut(_ sender: Any?) {
        guard let editor, editor.hasSelection else { return }
        copy(sender)
        editor.deleteSelection(named: "Cut")
    }

    @objc func delete(_ sender: Any?) {
        editor?.deleteSelection()
    }

    @objc override func selectAll(_ sender: Any?) {
        editor?.selectAll()
    }

    @objc func deselect(_ sender: Any?) {
        editor?.deselect()
    }

    @objc func invertSelection(_ sender: Any?) {
        editor?.invertSelection()
    }

    @objc func cropToSelection(_ sender: Any?) {
        editor?.cropToSelection()
    }

    @objc func showGaussianBlur(_ sender: Any?) {
        editor?.beginEffect(.gaussianBlur)
    }

    @objc func showPixelate(_ sender: Any?) {
        editor?.beginEffect(.pixelate)
    }

    @objc func togglePixelGrid(_ sender: Any?) {
        editor?.showsPixelGrid.toggle()
    }

    @objc func paste(_ sender: Any?) {
        guard let editor, let data = Self.imageDataOnPasteboard() else { return }
        do {
            let decoded = try ImageCodec.decode(data, convertingTo: editor.canvas.colorSpace)
            editor.paste(decoded.buffer)
        } catch {
            presentError(error)
        }
    }

    @objc func zoomIn(_ sender: Any?) { editor?.zoomIn() }
    @objc func zoomOut(_ sender: Any?) { editor?.zoomOut() }
    @objc func actualSize(_ sender: Any?) { editor?.zoomToActualSize() }
    @objc func zoomToFit(_ sender: Any?) { editor?.zoomToFit() }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let editor else { return super.validateMenuItem(menuItem) }
        switch menuItem.action {
        case #selector(undo(_:)):
            menuItem.title = editor.undoActionName.map { "Undo \($0)" } ?? "Undo"
            return editor.undoActionName != nil
        case #selector(redo(_:)):
            menuItem.title = editor.redoActionName.map { "Redo \($0)" } ?? "Redo"
            return editor.redoActionName != nil
        case #selector(paste(_:)):
            return Self.imageDataOnPasteboard() != nil
        case #selector(cut(_:)), #selector(delete(_:)), #selector(deselect(_:)), #selector(cropToSelection(_:)):
            return editor.hasSelection
        case #selector(selectAll(_:)), #selector(invertSelection(_:)),
             #selector(showGaussianBlur(_:)), #selector(showPixelate(_:)):
            return true
        case #selector(togglePixelGrid(_:)):
            menuItem.state = editor.showsPixelGrid ? .on : .off
            return true
        case #selector(copy(_:)), #selector(zoomIn(_:)), #selector(zoomOut(_:)),
             #selector(actualSize(_:)), #selector(zoomToFit(_:)):
            return true
        default:
            return super.validateMenuItem(menuItem)
        }
    }

    private static func imageDataOnPasteboard() -> Data? {
        let pasteboard = NSPasteboard.general
        if let type = pasteboard.availableType(from: pasteboardImageTypes) {
            return pasteboard.data(forType: type)
        }
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: ["public.image"],
        ]
        guard let url = pasteboard.readObjects(forClasses: [NSURL.self], options: options)?.first as? URL else {
            return nil
        }
        return try? Data(contentsOf: url)
    }
}
