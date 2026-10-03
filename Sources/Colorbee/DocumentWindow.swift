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
            ClipboardHistory.shared.add(png)
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
    @objc func showLevels(_ sender: Any?) { editor?.beginEffect(.levels) }
    @objc func showAdjustPhoto(_ sender: Any?) { editor?.beginEffect(.adjustPhoto) }
    @objc func showCurves(_ sender: Any?) { editor?.beginEffect(.curves) }
    @objc func showSepia(_ sender: Any?) { editor?.beginEffect(.sepia) }
    @objc func showPosterize(_ sender: Any?) { editor?.beginEffect(.posterize) }
    @objc func autoContrast(_ sender: Any?) { editor?.autoContrast() }
    @objc func showAddNoise(_ sender: Any?) { editor?.beginEffect(.addNoise) }
    @objc func showMotionBlur(_ sender: Any?) { editor?.beginEffect(.motionBlur) }
    @objc func showEmboss(_ sender: Any?) { editor?.beginEffect(.emboss) }
    @objc func showVignette(_ sender: Any?) { editor?.beginEffect(.vignette) }
    @objc func showBrightnessContrast(_ sender: Any?) { editor?.beginEffect(.brightnessContrast) }
    @objc func showHueSaturation(_ sender: Any?) { editor?.beginEffect(.hueSaturation) }
    @objc func invertColors(_ sender: Any?) { editor?.applyAdjustment(.invert) }
    @objc func desaturate(_ sender: Any?) { editor?.applyAdjustment(.desaturate) }

    @objc func setSymmetry(_ sender: Any?) {
        guard let tag = (sender as? NSMenuItem)?.tag, SymmetryMode.allCases.indices.contains(tag) else { return }
        editor?.symmetry = SymmetryMode.allCases[tag]
    }

    @objc func showResizeSkew(_ sender: Any?) {
        editor?.showResizeSkew()
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

    @objc func copyMerged(_ sender: Any?) {
        guard let editor else { return }
        do {
            let png = try editor.selectedMergedPixels().map {
                try ImageCodec.encodePNG($0, colorSpace: editor.canvas.colorSpace)
            } ?? editor.flattenedPNG()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setData(png, forType: .png)
        } catch {
            presentError(error)
        }
    }

    @objc func toggleLayers(_ sender: Any?) { editor?.toggleLayersPanel() }
    @objc func toggleAdjustmentsPanel(_ sender: Any?) { editor?.toggleAdjustmentsPanel() }
    @objc func applyAdjustment(_ sender: Any?) { editor?.applyAdjustmentLayer() }
    @objc func undoOnActiveLayer(_ sender: Any?) { editor?.undoOnActiveLayer() }
    @objc func revertLayer(_ sender: Any?) { editor?.revertLayer() }

    @objc func newAdjustmentLayer(_ sender: Any?) {
        guard let tag = (sender as? NSMenuItem)?.tag, AdjustmentChoice.allCases.indices.contains(tag) else { return }
        editor?.addAdjustmentLayer(AdjustmentChoice.allCases[tag])
    }
    @objc func newLayer(_ sender: Any?) { editor?.addLayer() }
    @objc func duplicateLayer(_ sender: Any?) { editor?.duplicateLayer() }
    @objc func deleteLayer(_ sender: Any?) { editor?.deleteLayer() }
    @objc func mergeDown(_ sender: Any?) { editor?.mergeDown() }
    @objc func mergeVisible(_ sender: Any?) { editor?.mergeVisible() }
    @objc func flattenImage(_ sender: Any?) { editor?.flatten() }

    @objc func toggleLayerVisibility(_ sender: Any?) {
        guard let editor else { return }
        editor.setLayerVisible(!editor.canvas.activeLayer.isVisible, at: editor.activeLayerIndex)
    }

    @objc func toggleLayerLock(_ sender: Any?) {
        guard let editor else { return }
        editor.setLayerLocked(!editor.canvas.activeLayer.isLocked, at: editor.activeLayerIndex)
    }

    /// The Layers panel holds the active layer's name, blend mode and opacity, so this opens it.
    @objc func showLayerProperties(_ sender: Any?) { editor?.isSidebarOpen = true }

    @objc func togglePixelGrid(_ sender: Any?) {
        editor?.showsPixelGrid.toggle()
    }

    @objc func paste(_ sender: Any?) {
        guard let editor, let data = Self.imageDataOnPasteboard() else { return }
        do {
            let decoded = try ImageCodec.decode(data, convertingTo: editor.canvas.colorSpace)
            ClipboardHistory.shared.add(data)
            let image = decoded.buffer, canvas = editor.canvasSize
            guard image.width > canvas.width || image.height > canvas.height else {
                editor.paste(image)
                return
            }
            // Like Paint: a paste bigger than the canvas offers to enlarge the canvas to fit (FR-10.1).
            let alert = NSAlert()
            alert.messageText = "The pasted image is larger than the canvas."
            alert.informativeText = "It's \(image.width) × \(image.height) px; the canvas is \(canvas.width) × \(canvas.height) px. Enlarge the canvas to fit it?"
            alert.addButton(withTitle: "Enlarge Canvas")
            alert.addButton(withTitle: "Keep Canvas Size")
            alert.beginSheetModal(for: self) { response in
                if response == .alertFirstButtonReturn {
                    editor.resizeCanvas(to: IntSize(width: max(image.width, canvas.width), height: max(image.height, canvas.height)))
                    editor.paste(image, at: IntPoint(x: 0, y: 0))
                } else {
                    // At the top-left, shown only where it falls on the canvas; drag it to choose what shows.
                    editor.paste(image, at: IntPoint(x: 0, y: 0))
                }
            }
        } catch {
            presentError(error)
        }
    }

    /// Paste into New Image (⇧⌘V): the clipboard image becomes a document of its own, at its own size.
    @objc func pasteIntoNewImage(_ sender: Any?) {
        guard let data = Self.imageDataOnPasteboard() else { return }
        do {
            let decoded = try ImageCodec.decode(data)
            ClipboardHistory.shared.add(data)
            ImageDocument.open(Canvas(colorSpace: decoded.colorSpace, layers: [Layer(name: "Background", buffer: decoded.buffer)],
                                      hasTransparentBackground: decoded.buffer.hasTransparency))
        } catch {
            presentError(error)
        }
    }

    @objc func showCanvasProperties(_ sender: Any?) { editor?.isCanvasPropertiesOpen = true }
    @objc func toggleHistoryPanel(_ sender: Any?) { editor?.togglePanel(\.showsHistoryPanel) }
    @objc func toggleClipboardPanel(_ sender: Any?) { editor?.togglePanel(\.showsClipboardPanel) }
    @objc func toggleRulers(_ sender: Any?) { editor?.showsRulers.toggle() }
    @objc func toggleStatusBar(_ sender: Any?) { editor?.showsStatusBar.toggle() }

    @objc func zoomIn(_ sender: Any?) { editor?.zoomIn() }
    @objc func zoomOut(_ sender: Any?) { editor?.zoomOut() }
    @objc func actualSize(_ sender: Any?) { editor?.zoomToActualSize() }
    @objc func zoomToFit(_ sender: Any?) { editor?.zoomToFit() }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let editor else { return super.validateMenuItem(menuItem) }
        // While an effect's bar is open, only viewing commands work; Apply or Cancel comes first.
        if editor.activeEffect != nil {
            return [#selector(zoomIn(_:)), #selector(zoomOut(_:)), #selector(actualSize(_:)),
                    #selector(zoomToFit(_:)), #selector(togglePixelGrid(_:))].contains(menuItem.action)
        }
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
             #selector(invertColors(_:)), #selector(desaturate(_:)), #selector(applyOrientation(_:)), #selector(showResizeSkew(_:)):
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
        case #selector(toggleLayers(_:)):
            menuItem.state = editor.isSidebarOpen && editor.showsLayersPanel ? .on : .off
            return true
        case #selector(pasteIntoNewImage(_:)):
            return Self.imageDataOnPasteboard() != nil
        case #selector(showCanvasProperties(_:)):
            return true
        case #selector(toggleHistoryPanel(_:)):
            menuItem.state = editor.isSidebarOpen && editor.showsHistoryPanel ? .on : .off
            return true
        case #selector(toggleClipboardPanel(_:)):
            menuItem.state = editor.isSidebarOpen && editor.showsClipboardPanel ? .on : .off
            return true
        case #selector(toggleRulers(_:)):
            menuItem.title = editor.showsRulers ? "Hide Rulers" : "Show Rulers"
            return true
        case #selector(toggleStatusBar(_:)):
            menuItem.title = editor.showsStatusBar ? "Hide Status Bar" : "Show Status Bar"
            return true
        case #selector(toggleAdjustmentsPanel(_:)):
            menuItem.state = editor.isSidebarOpen && editor.showsAdjustmentsPanel ? .on : .off
            return true
        case #selector(applyAdjustment(_:)):
            return LayerActions.canApplyAdjustment(editor.canvas)
        case #selector(undoOnActiveLayer(_:)):
            let name = editor.undoOnActiveLayerName
            menuItem.title = name.map { "Undo \($0) on Active Layer" } ?? "Undo on Active Layer"
            return name != nil
        case #selector(revertLayer(_:)):
            return editor.canRevertLayer
        case #selector(newAdjustmentLayer(_:)):
            return true
        case #selector(deleteLayer(_:)):
            return LayerActions.canDelete(editor.canvas)
        case #selector(mergeDown(_:)):
            return LayerActions.canMergeDown(editor.canvas)
        case #selector(mergeVisible(_:)):
            return LayerActions.canMergeVisible(editor.canvas)
        case #selector(flattenImage(_:)):
            return LayerActions.canFlatten(editor.canvas)
        case #selector(toggleLayerVisibility(_:)):
            menuItem.title = editor.canvas.activeLayer.isVisible ? "Hide Layer" : "Show Layer"
            return true
        case #selector(toggleLayerLock(_:)):
            menuItem.title = editor.canvas.activeLayer.isLocked ? "Unlock Layer" : "Lock Layer"
            return true
        case #selector(newLayer(_:)), #selector(duplicateLayer(_:)), #selector(showLayerProperties(_:)), #selector(copyMerged(_:)):
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
