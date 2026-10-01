import AppKit
import ColorbeeCore

/// Handles document-level editing commands for whichever view in the window has focus.
final class DocumentWindow: NSWindow {
    weak var editor: Editor?

    private static let pasteboardImageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff]

    /// While text is being typed, undo belongs to the text box.
    private var textUndoManager: UndoManager? {
        firstResponder is NSTextView ? undoManager : nil
    }

    @objc func undo(_ sender: Any?) {
        if let textUndoManager { textUndoManager.undo() } else { editor?.undo() }
    }

    @objc func redo(_ sender: Any?) {
        if let textUndoManager { textUndoManager.redo() } else { editor?.redo() }
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

    @objc func showSharpen(_ sender: Any?) { editor?.beginEffect(.sharpen) }
    @objc func showBrightnessContrast(_ sender: Any?) { editor?.beginEffect(.brightnessContrast) }
    @objc func showHueSaturation(_ sender: Any?) { editor?.beginEffect(.hueSaturation) }
    @objc func invertColors(_ sender: Any?) { editor?.applyAdjustment(.invert) }
    @objc func desaturate(_ sender: Any?) { editor?.applyAdjustment(.desaturate) }

    @objc func setSymmetry(_ sender: Any?) {
        guard let tag = (sender as? NSMenuItem)?.tag, SymmetryMode.allCases.indices.contains(tag) else { return }
        editor?.symmetry = SymmetryMode.allCases[tag]
    }

    @objc func applyOrientation(_ sender: Any?) {
        guard let tag = (sender as? NSMenuItem)?.tag, Orientation.allCases.indices.contains(tag) else { return }
        editor?.apply(Orientation.allCases[tag])
    }

    @objc func showAutoRedact(_ sender: Any?) {
        editor?.beginAutoRedact()
    }

    @objc func applySolidFill(_ sender: Any?) {
        editor?.applySolidFill()
    }

    @objc func toggleBeforeAfter(_ sender: Any?) {
        editor?.toggleComparison()
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
        case #selector(undo(_:)) where textUndoManager != nil:
            menuItem.title = textUndoManager!.undoMenuItemTitle
            return textUndoManager!.canUndo
        case #selector(redo(_:)) where textUndoManager != nil:
            menuItem.title = textUndoManager!.redoMenuItemTitle
            return textUndoManager!.canRedo
        case #selector(undo(_:)):
            menuItem.title = editor.undoActionName.map { "Undo \($0)" } ?? "Undo"
            return editor.undoActionName != nil
        case #selector(redo(_:)):
            menuItem.title = editor.redoActionName.map { "Redo \($0)" } ?? "Redo"
            return editor.redoActionName != nil
        case #selector(paste(_:)):
            return Self.imageDataOnPasteboard() != nil
        case #selector(cut(_:)), #selector(delete(_:)), #selector(deselect(_:)), #selector(cropToSelection(_:)),
             #selector(applySolidFill(_:)):
            return editor.hasSelection
        case #selector(selectAll(_:)), #selector(invertSelection(_:)),
             #selector(showGaussianBlur(_:)), #selector(showPixelate(_:)), #selector(showAutoRedact(_:)),
             #selector(showSharpen(_:)), #selector(showBrightnessContrast(_:)), #selector(showHueSaturation(_:)),
             #selector(invertColors(_:)), #selector(desaturate(_:)), #selector(applyOrientation(_:)):
            return true
        case #selector(setSymmetry(_:)):
            menuItem.state = SymmetryMode.allCases.indices.contains(menuItem.tag) && SymmetryMode.allCases[menuItem.tag] == editor.symmetry ? .on : .off
            return true
        case #selector(toggleBeforeAfter(_:)):
            menuItem.state = editor.comparison != nil ? .on : .off
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
