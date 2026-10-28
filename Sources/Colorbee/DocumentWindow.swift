import AppKit
import ColorbeeCore

/// Handles document-level editing commands for whichever view in the window has focus.
final class DocumentWindow: NSWindow {
    weak var editor: Editor? {
        didSet { editor?.onViewStateChange = { [weak self] in self?.invalidateRestorableState() } }
    }
    weak var canvasView: CanvasView?
    /// While a key is handed to the canvas, which may pass it back up the responder chain to here.
    private var isForwardingKey = false

    /// A tool or canvas key that nothing else used, because a button or panel took the keyboard from the canvas,
    /// still reaches it. Text boxes use every letter themselves, so typing never gets here. A key the canvas passes
    /// back (with an effect's bar open) isn't handed to it again: that looped until Colorbee crashed (review T,
    /// finding 1).
    override func keyDown(with event: NSEvent) {
        if !isForwardingKey, let canvasView, firstResponder !== canvasView, !(firstResponder is NSText),
           ShortcutStore.shared.canvasCommand(for: event) != nil {
            isForwardingKey = true
            defer { isForwardingKey = false }
            canvasView.keyDown(with: event)
        } else {
            super.keyDown(with: event)
        }
    }

    /// ⌘W, File ▸ Close and the close button: an unsaved redaction is saved, and the earlier-versions warning
    /// shown, before the window goes (Leah, 2026-10-04).
    override func performClose(_ sender: Any?) {
        guard let document = windowController?.document as? ImageDocument, document.wantsRedactionCheckBeforeClosing else {
            return super.performClose(sender)
        }
        document.checkRedactionBeforeClosing { [weak self] in self?.closeAfterRedactionCheck(sender) }
    }

    private func closeAfterRedactionCheck(_ sender: Any?) {
        super.performClose(sender)
    }

    // MARK: Restoring (FR-12; review J, finding 28)

    private static let panelKeys = ["isSidebarOpen", "showsLayersPanel", "showsAdjustmentsPanel", "showsHistoryPanel",
                                    "showsClipboardPanel", "showsInfoPanel", "showsRulers", "showsStatusBar", "showsPageSidebar"]
    private static let panelPaths: [ReferenceWritableKeyPath<Editor, Bool>] = [\.isSidebarOpen, \.showsLayersPanel, \.showsAdjustmentsPanel,
                                                                             \.showsHistoryPanel, \.showsClipboardPanel, \.showsInfoPanel, \.showsRulers, \.showsStatusBar,
                                                                             \.showsPageSidebar]

    override func encodeRestorableState(with coder: NSCoder) {
        super.encodeRestorableState(with: coder)
        guard let editor else { return }
        coder.encode(editor.viewport.zoom, forKey: "ColorbeeZoom")
        coder.encode(editor.viewport.center.x, forKey: "ColorbeeCenterX")
        coder.encode(editor.viewport.center.y, forKey: "ColorbeeCenterY")
        for (key, path) in zip(Self.panelKeys, Self.panelPaths) { coder.encode(editor[keyPath: path], forKey: "Colorbee." + key) }
    }

    override func restoreState(with coder: NSCoder) {
        super.restoreState(with: coder)
        guard let editor else { return }
        for (key, path) in zip(Self.panelKeys, Self.panelPaths) where coder.containsValue(forKey: "Colorbee." + key) {
            editor[keyPath: path] = coder.decodeBool(forKey: "Colorbee." + key)
        }
        editor.settlePanels()
        guard coder.containsValue(forKey: "ColorbeeZoom") else { return }
        let zoom = coder.decodeDouble(forKey: "ColorbeeZoom")
        let center = Point2D(x: coder.decodeDouble(forKey: "ColorbeeCenterX"), y: coder.decodeDouble(forKey: "ColorbeeCenterY"))
        if editor.viewport.viewSize.width > 0 {
            editor.updateViewport { viewport in
                viewport.setZoom(zoom, anchor: Point2D(x: viewport.viewSize.width / 2, y: viewport.viewSize.height / 2))
                viewport.center = center
            }
        } else {
            editor.restoredView = (zoom, center)
        }
    }


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
        // An adjustment layer has no pixels of its own, so copying it alone pasted as nothing. It copies what you see
        // instead, like Copy Merged (Leah, 2026-10-09).
        let isAdjustment = editor.canvas.activeLayer.adjustment != nil
        copyToClipboard(selected: isAdjustment ? editor.selectedMergedPixels() : editor.selectedPixels(), merged: isAdjustment, editor: editor)
    }

    /// The selected pixels (made now, so they're the selection as it is), or the whole image from a
    /// snapshot flattened in the background. Where they came from goes with them, for Paste in Place.
    private func copyToClipboard(selected: PixelBuffer?, merged: Bool, editor: Editor) {
        let colorSpace = editor.canvas.colorSpace
        let place = editor.copiedPlace(merged: merged)
        // A copy made from the document is offered for removal after a redaction too, like the image it came from
        // (Leah, 2026-10-05; review K, finding 11).
        let added: @MainActor @Sendable (ClipboardHistory.Item.ID) -> Void = { [weak editor] id in editor?.noteClipboardSource(id) }
        if let selected {
            let pixels = UnsafePixels(selected)
            ClipboardImage.copy(colorSpace: colorSpace, place: place, pixels: { pixels.value }, added: added)
        } else {
            let snapshot = editor.saveSnapshot()
            ClipboardImage.copy(colorSpace: colorSpace, place: place, pixels: {
                snapshot.canvas.flattened(transparentKey: snapshot.transparentKey, resampling: snapshot.resampling)
            }, added: added)
        }
    }

    @objc func cut(_ sender: Any?) {
        guard let editor, editor.hasSelection else { return }
        // A locked layer refuses the cut before anything is copied, so the clipboard isn't changed either.
        guard editor.activeLayerTakesEdits else { return editor.onRefused() }
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

    @objc func batchRedactBlur(_ sender: Any?) { editor?.beginBatchRedact(.gaussianBlur) }
    @objc func batchRedactPixelate(_ sender: Any?) { editor?.beginBatchRedact(.pixelate) }
    @objc func showPixelate(_ sender: Any?) {
        editor?.beginEffect(.pixelate)
    }

    @objc func showSharpen(_ sender: Any?) { editor?.beginEffect(.sharpen) }
    @objc func showLevels(_ sender: Any?) { editor?.beginEffect(.levels) }
    @objc func showAdjustPhoto(_ sender: Any?) { editor?.beginEffect(.adjustPhoto) }
    @objc func applySameAsLastPhoto(_ sender: Any?) { editor?.applySameAsLastPhoto() }
    @objc func copyPhotoSettings(_ sender: Any?) { editor?.copyPhotoSettings() }
    @objc func pastePhotoSettings(_ sender: Any?) { editor?.pastePhotoSettings() }
    @objc func pastePhotoSettingsAsLayer(_ sender: Any?) { editor?.pastePhotoSettingsAsLayer() }
    @objc func showCurves(_ sender: Any?) { editor?.beginEffect(.curves) }
    @objc func showSepia(_ sender: Any?) { editor?.beginEffect(.sepia) }
    @objc func showPosterize(_ sender: Any?) { editor?.beginEffect(.posterize) }
    @objc func removeRedEye(_ sender: Any?) { editor?.removeRedEye() }
    @objc func showFeather(_ sender: Any?) { editor?.beginSelectionChange(.feather) }
    @objc func showExpandSelection(_ sender: Any?) { editor?.beginSelectionChange(.expand) }
    @objc func showContractSelection(_ sender: Any?) { editor?.beginSelectionChange(.contract) }
    @objc func showSmoothSelection(_ sender: Any?) { editor?.beginSelectionChange(.smooth) }
    @objc func autoContrast(_ sender: Any?) { editor?.autoContrast() }
    @objc func showAddNoise(_ sender: Any?) { editor?.beginEffect(.addNoise) }
    @objc func showMotionBlur(_ sender: Any?) { editor?.beginEffect(.motionBlur) }
    @objc func showEmboss(_ sender: Any?) { editor?.beginEffect(.emboss) }
    @objc func showVignette(_ sender: Any?) { editor?.beginEffect(.vignette) }
    @objc func showDropShadow(_ sender: Any?) { editor?.beginEffect(.dropShadow) }
    @objc func showBorder(_ sender: Any?) { editor?.beginEffect(.border) }
    @objc func showSpotlight(_ sender: Any?) { editor?.beginEffect(.spotlight) }
    @objc func showCrop(_ sender: Any?) { editor?.beginEffect(.crop) }
    @objc func selectSubject(_ sender: Any?) { editor?.findSubject(.select) }
    @objc func showColorRange(_ sender: Any?) { editor?.beginEffect(.colorRange) }
    @objc func showLuminanceRange(_ sender: Any?) { editor?.beginEffect(.luminanceRange) }
    @objc func showGraduatedSelection(_ sender: Any?) { editor?.beginEffect(.graduatedSelection) }
    @objc func removeBackground(_ sender: Any?) { editor?.findSubject(.removeBackground) }
    @objc func liftSubject(_ sender: Any?) { editor?.findSubject(.liftToNewLayer) }
    @objc func showStraighten(_ sender: Any?) { editor?.beginEffect(.straighten) }
    @objc func showPerspective(_ sender: Any?) { editor?.beginEffect(.perspective) }
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

    @objc func copyText(_ sender: Any?) {
        editor?.copyText { text in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            return NSPasteboard.general.changeCount
        }
    }

    @objc func copyMerged(_ sender: Any?) {
        guard let editor else { return }
        copyToClipboard(selected: editor.selectedMergedPixels(), merged: true, editor: editor)
    }

    @objc func toggleSidebar(_ sender: Any?) { editor?.toggleSidebar() }
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
    /// With hidden layers, asks first: flattening keeps only what's visible (Leah, 2026-10-04).
    @objc func flattenImage(_ sender: Any?) {
        guard let editor else { return }
        let hidden = editor.canvas.layers.filter { !$0.isVisible }.count
        guard hidden > 0 else { return editor.flatten() }
        let alert = NSAlert()
        alert.messageText = "Discard hidden layers?"
        alert.informativeText = hidden == 1 ? "1 layer is hidden. Flattening keeps only what's visible, so it will be discarded."
            : "\(hidden) layers are hidden. Flattening keeps only what's visible, so they will be discarded."
        alert.addButton(withTitle: "Flatten")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: self) { response in
            if response == .alertFirstButtonReturn { editor.flatten() }
        }
    }

    // MARK: Pages (FR-11.6)

    @objc func newPage(_ sender: Any?) { editor?.newPage() }
    @objc func duplicatePage(_ sender: Any?) { editor?.duplicatePage() }
    @objc func deletePage(_ sender: Any?) { editor?.deletePage() }
    @objc func movePageUp(_ sender: Any?) {
        guard let editor else { return }
        editor.movePage(from: editor.currentPageIndex, to: editor.currentPageIndex - 1)
    }
    @objc func movePageDown(_ sender: Any?) {
        guard let editor else { return }
        editor.movePage(from: editor.currentPageIndex, to: editor.currentPageIndex + 1)
    }
    @objc func previousPage(_ sender: Any?) {
        guard let editor else { return }
        editor.showPage(at: editor.currentPageIndex - 1)
    }
    @objc func nextPage(_ sender: Any?) {
        guard let editor else { return }
        editor.showPage(at: editor.currentPageIndex + 1)
    }
    @objc func togglePageSidebar(_ sender: Any?) { editor?.showsPageSidebar.toggle() }

    @objc func toggleLayerVisibility(_ sender: Any?) { editor?.toggleChosenLayersVisible() }
    @objc func toggleLayerLock(_ sender: Any?) { editor?.toggleChosenLayersLocked() }

    /// The Layers panel holds the active layer's name, blend mode and opacity, so this opens it.
    @objc func showLayerProperties(_ sender: Any?) {
        editor?.showsLayersPanel = true
        editor?.openSidebar()
    }

    @objc func togglePixelGrid(_ sender: Any?) {
        editor?.showsPixelGrid.toggle()
    }

    @objc func paste(_ sender: Any?) { paste(inPlace: false) }

    /// Paste in Place (⌥⇧⌘V): where Colorbee copied the pixels from, when any of them land on this canvas (FR-10.1).
    @objc func pasteInPlace(_ sender: Any?) { paste(inPlace: true) }

    private func paste(inPlace: Bool) {
        guard let editor, let data = Self.imageDataOnPasteboard() else { return }
        let place = inPlace ? ClipboardImage.place() : nil
        do {
            let decoded = try ImageCodec.decode(data, convertingTo: editor.canvas.colorSpace)
            let source = ClipboardHistory.shared.add(data)
            let image = decoded.buffer, canvas = editor.canvasSize
            guard image.width > canvas.width || image.height > canvas.height else {
                editor.paste(image, inPlaceAt: place)
                editor.noteClipboardSource(source)
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
                } else if let place {
                    editor.paste(image, inPlaceAt: place)
                } else {
                    // At the top-left, shown only where it falls on the canvas; drag it to choose what shows.
                    editor.paste(image, at: IntPoint(x: 0, y: 0))
                }
                editor.noteClipboardSource(source)
            }
        } catch {
            presentError(error)
        }
    }

    /// Paste into New Image (⇧⌘V): the clipboard image becomes a document of its own, at its own size.
    @objc func pasteIntoNewImage(_ sender: Any?) {
        do { try Self.openClipboardImage() } catch { presentError(error) }
    }

    /// Also `AppDelegate`'s, so it works with no window open (review M, finding 1).
    static func openClipboardImage() throws {
        guard let data = imageDataOnPasteboard() else { return }
        let decoded = try ImageCodec.decode(data)
        let source = ClipboardHistory.shared.add(data)
        ImageDocument.open(Canvas(colorSpace: decoded.colorSpace, layers: [Layer(name: "Background", buffer: decoded.buffer)],
                                  hasTransparentBackground: decoded.buffer.hasTransparency), clipboardSource: source)
    }

    @objc func showCanvasProperties(_ sender: Any?) { editor?.isCanvasPropertiesOpen = true }
    @objc func toggleHistoryPanel(_ sender: Any?) { editor?.togglePanel(\.showsHistoryPanel) }
    @objc func toggleClipboardPanel(_ sender: Any?) { editor?.togglePanel(\.showsClipboardPanel) }
    @objc func toggleInfoPanel(_ sender: Any?) { editor?.togglePanel(\.showsInfoPanel) }
    @objc func toggleRulers(_ sender: Any?) { editor?.showsRulers.toggle() }
    @objc func toggleStatusBar(_ sender: Any?) { editor?.showsStatusBar.toggle() }

    @objc func zoomIn(_ sender: Any?) { editor?.zoomIn() }
    @objc func zoomOut(_ sender: Any?) { editor?.zoomOut() }
    @objc func actualSize(_ sender: Any?) { editor?.zoomToActualSize() }
    @objc func zoomToFit(_ sender: Any?) { editor?.zoomToFit() }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let editor else { return super.validateMenuItem(menuItem) }
        // Before the early returns below: these still work while an effect's bar or the text box is open, so their
        // checkmarks must still follow (review R, finding 3).
        if let isOn = Self.isOn(menuItem, in: editor) { menuItem.state = isOn ? .on : .off }
        // Adjust Photo's sliders are in the sidebar, as for the toolbar's Sidebar button (review D, finding 5).
        if menuItem.action == #selector(toggleSidebar(_:)) { return editor.canToggleSidebar }
        // While an effect's bar, Auto-Redact, Resize and Skew, Canvas Properties or Feather is open, only viewing and window
        // commands work; Apply or Cancel comes first. Sheets don't stop menu commands reaching the window (review E,
        // finding 2; review J, findings 7 and 18).
        if editor.blocksDocumentCommands {
            return Self.viewingCommands.contains(menuItem.action)
                || [#selector(performClose(_:)), #selector(performMiniaturize(_:)), #selector(performZoom(_:)),
                    #selector(toggleFullScreen(_:))].contains(menuItem.action)
        }
        // While text is typed, menu shortcuts give way to the text box, so ⌘⌫ deletes text rather than the layer
        // (review J, finding 4). The text box handles Cut, Copy, Paste, Select All, Undo and Redo itself.
        if firstResponder is CanvasTextView {
            return Self.viewingCommands.contains(menuItem.action)
        }
        // Commands that change the active layer's pixels are greyed out on a locked or adjustment layer, rather
        // than beeping when chosen (Leah, §23). Whole-image commands work on every layer, so they stay.
        if !editor.activeLayerTakesEdits, let action = menuItem.action {
            if Self.pixelCommands.contains(action) { return false }
            if editor.hasSelection, [#selector(applyOrientation(_:)), #selector(showResizeSkew(_:))].contains(action) { return false }
        }
        switch menuItem.action {
        case #selector(applySameAsLastPhoto(_:)):
            return PhotoSettingsStore.shared.last != nil
        case #selector(copyPhotoSettings(_:)):
            return editor.activePhotoLayerEdit != nil
        case #selector(pastePhotoSettings(_:)):
            return PhotoSettingsStore.shared.copied != nil && (editor.activeLayerTakesEdits || editor.activePhotoLayerEdit != nil)
        case #selector(pastePhotoSettingsAsLayer(_:)):
            return PhotoSettingsStore.shared.copied != nil
        case #selector(showSpotlight(_:)):
            // Spotlight changes what's around a selection, so it waits for one.
            return editor.hasSelection
        case #selector(showColorRange(_:)), #selector(showLuminanceRange(_:)), #selector(showGraduatedSelection(_:)):
            return true
        case #selector(showFeather(_:)), #selector(showExpandSelection(_:)), #selector(showContractSelection(_:)),
             #selector(showSmoothSelection(_:)):
            return editor.hasSelection
        case #selector(removeRedEye(_:)):
            return !editor.isFindingEyes && editor.activeLayerTakesEdits
        case #selector(selectSubject(_:)), #selector(removeBackground(_:)), #selector(liftSubject(_:)):
            // One search at a time, and an adjustment layer has no picture to search (review D, finding 6).
            return !editor.isFindingSubject && editor.canvas.activeLayer.adjustment == nil
        case #selector(undo(_:)) where textUndoManager != nil:
            menuItem.title = textUndoManager!.undoMenuItemTitle
            return textUndoManager!.canUndo
        case #selector(redo(_:)) where textUndoManager != nil:
            menuItem.title = textUndoManager!.redoMenuItemTitle
            return textUndoManager!.canRedo
        case #selector(undo(_:)) where editor.pendingShape != nil:
            // ⌘Z discards a shape that isn't placed yet (§23, stage 3b; review J, finding 16).
            menuItem.title = "Undo Shape"
            return true
        case #selector(undo(_:)) where editor.pendingBadge != nil:
            menuItem.title = "Undo Step Badge"
            return true
        case #selector(undo(_:)):
            menuItem.title = editor.undoActionName.map { "Undo \($0)" } ?? "Undo"
            return editor.undoActionName != nil
        case #selector(redo(_:)):
            menuItem.title = editor.redoActionName.map { "Redo \($0)" } ?? "Redo"
            return editor.redoActionName != nil
        case #selector(paste(_:)), #selector(pasteInPlace(_:)):
            return PasteboardImages.hasImage()
        case #selector(cut(_:)), #selector(delete(_:)), #selector(deselect(_:)), #selector(cropToSelection(_:)),
             #selector(applySolidFill(_:)):
            return editor.hasSelection
        case #selector(selectAll(_:)), #selector(invertSelection(_:)),
             #selector(showGaussianBlur(_:)), #selector(showPixelate(_:)), #selector(showAutoRedact(_:)),
             #selector(showSharpen(_:)), #selector(showHueSaturation(_:)),
             #selector(invertColors(_:)), #selector(desaturate(_:)), #selector(applyOrientation(_:)), #selector(showResizeSkew(_:)):
            return true
        case #selector(setSymmetry(_:)):
            return true
        case #selector(toggleBeforeAfter(_:)):
            return true
        case #selector(togglePixelGrid(_:)):
            return true
        case #selector(toggleLayers(_:)):
            return true
        case #selector(pasteIntoNewImage(_:)):
            return PasteboardImages.hasImage()
        case #selector(showCanvasProperties(_:)):
            return true
        case #selector(toggleHistoryPanel(_:)):
            return true
        case #selector(toggleClipboardPanel(_:)), #selector(toggleInfoPanel(_:)):
            return true
        case #selector(toggleRulers(_:)):
            return true
        case #selector(toggleStatusBar(_:)):
            return true
        case #selector(toggleAdjustmentsPanel(_:)):
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
        // With several layers chosen, these act on all of them (FR-8.6).
        case #selector(deleteLayer(_:)):
            menuItem.title = editor.hasSeveralChosenLayers ? "Delete Layers" : "Delete Layer"
            return editor.canDeleteLayers
        case #selector(mergeDown(_:)):
            menuItem.title = editor.mergeCommandTitle
            return editor.canMerge
        case #selector(duplicateLayer(_:)):
            menuItem.title = editor.hasSeveralChosenLayers ? "Duplicate Layers" : "Duplicate Layer"
            return true
        case #selector(mergeVisible(_:)):
            return LayerActions.canMergeVisible(editor.canvas)
        case #selector(flattenImage(_:)):
            return LayerActions.canFlatten(editor.canvas)
        case #selector(deletePage(_:)):
            return editor.pageCount > 1
        case #selector(movePageUp(_:)), #selector(previousPage(_:)):
            return editor.currentPageIndex > 0
        case #selector(movePageDown(_:)), #selector(nextPage(_:)):
            return editor.currentPageIndex < editor.pageCount - 1
        case #selector(newPage(_:)), #selector(duplicatePage(_:)):
            return true
        case #selector(togglePageSidebar(_:)):
            return editor.pageCount > 1
        case #selector(toggleLayerVisibility(_:)):
            let layers = editor.hasSeveralChosenLayers ? "Layers" : "Layer"
            menuItem.title = (editor.canvas.activeLayer.isVisible ? "Hide " : "Show ") + layers
            return true
        case #selector(toggleLayerLock(_:)):
            let layers = editor.hasSeveralChosenLayers ? "Layers" : "Layer"
            menuItem.title = (editor.canvas.activeLayer.isLocked ? "Unlock " : "Lock ") + layers
            return true
        case #selector(newLayer(_:)), #selector(showLayerProperties(_:)), #selector(copyMerged(_:)):
            return true
        case #selector(copy(_:)), #selector(zoomIn(_:)), #selector(zoomOut(_:)),
             #selector(actualSize(_:)), #selector(zoomToFit(_:)):
            return true
        default:
            return super.validateMenuItem(menuItem)
        }
    }

    /// Commands that only change the view.
    /// Whether a toggle in the menus is on, or nil for a command that isn't one.
    static func isOn(_ menuItem: NSMenuItem, in editor: Editor) -> Bool? {
        switch menuItem.action {
        case #selector(setSymmetry(_:)):
            SymmetryMode.allCases.indices.contains(menuItem.tag) && SymmetryMode.allCases[menuItem.tag] == editor.symmetry
        case #selector(toggleBeforeAfter(_:)): editor.comparison != nil
        case #selector(togglePixelGrid(_:)): editor.showsPixelGrid
        case #selector(toggleRulers(_:)): editor.showsRulers
        case #selector(toggleStatusBar(_:)): editor.showsStatusBar
        case #selector(toggleSidebar(_:)): editor.isSidebarOpen
        case #selector(toggleLayers(_:)): editor.isSidebarOpen && editor.showsLayersPanel
        case #selector(toggleAdjustmentsPanel(_:)): editor.isSidebarOpen && editor.showsAdjustmentsPanel
        case #selector(toggleHistoryPanel(_:)): editor.isSidebarOpen && editor.showsHistoryPanel
        case #selector(toggleClipboardPanel(_:)): editor.isSidebarOpen && editor.showsClipboardPanel
        case #selector(toggleInfoPanel(_:)): editor.isSidebarOpen && editor.showsInfoPanel
        case #selector(togglePageSidebar(_:)): editor.showsPageSidebar && editor.pageCount > 1
        default: nil
        }
    }

    private static let viewingCommands: Set<Selector?> = [
        #selector(zoomIn(_:)), #selector(zoomOut(_:)), #selector(actualSize(_:)), #selector(zoomToFit(_:)),
        #selector(togglePixelGrid(_:)), #selector(toggleRulers(_:)), #selector(toggleStatusBar(_:)), #selector(toggleLayers(_:)),
        #selector(toggleAdjustmentsPanel(_:)), #selector(toggleHistoryPanel(_:)), #selector(toggleClipboardPanel(_:)), #selector(toggleInfoPanel(_:)),
        #selector(togglePageSidebar(_:)), #selector(toggleSidebar(_:)),
    ]

    private static let pixelCommands: Set<Selector> = [
        // Not Batch Redact ▸ Solid Fill: like Blur… and Pixelate…, it redacts every layer under the selection (review P,
        // finding 6).
        #selector(cut(_:)), #selector(delete(_:)), #selector(paste(_:)), #selector(pasteInPlace(_:)),
        #selector(showGaussianBlur(_:)), #selector(showPixelate(_:)), #selector(showSharpen(_:)), #selector(showLevels(_:)),
        #selector(showAdjustPhoto(_:)), #selector(showCurves(_:)), #selector(showSepia(_:)), #selector(showPosterize(_:)),
        #selector(applySameAsLastPhoto(_:)), #selector(autoContrast(_:)), #selector(showAddNoise(_:)), #selector(showMotionBlur(_:)), #selector(showEmboss(_:)),
        #selector(showVignette(_:)), #selector(showDropShadow(_:)), #selector(showBorder(_:)), #selector(showSpotlight(_:)),
        #selector(showHueSaturation(_:)), #selector(invertColors(_:)), #selector(desaturate(_:)),
        #selector(removeBackground(_:)), #selector(liftSubject(_:)),
    ]

    private static func imageDataOnPasteboard() -> Data? {
        PasteboardImages.imageData()
    }
}

/// A buffer made for the clipboard and handed to the encoder's thread; nothing else holds it.
private struct UnsafePixels: @unchecked Sendable {
    let value: PixelBuffer
    init(_ value: PixelBuffer) { self.value = value }
}
