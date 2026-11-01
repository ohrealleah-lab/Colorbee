import ColorbeeCore
import CoreGraphics
import Foundation
import Observation

extension Editor {
    // MARK: Layers

    /// ⌘L and the toolbar's Layers button: show the Layers panel (opening the sidebar), or hide it.
    /// Each panel shows or hides on its own; the sidebar closes only when none is left (FR-1.3; review J, finding 15).
    func toggleLayersPanel() {
        togglePanel(\.showsLayersPanel)
    }

    /// Shows a sidebar panel (opening the sidebar), or hides it if it's already showing.
    func togglePanel(_ panel: ReferenceWritableKeyPath<Editor, Bool>) {
        if isSidebarOpen && self[keyPath: panel] {
            self[keyPath: panel] = false
            // During Adjust Photo the sidebar holds its sliders, so it stays (review P, finding 4).
            if !showsAnyPanel, activeEffect != .adjustPhoto { isSidebarOpen = false }
        } else {
            self[keyPath: panel] = true
            isSidebarOpen = true
        }
    }

    func toggleAdjustmentsPanel() {
        togglePanel(\.showsAdjustmentsPanel)
    }

    private var showsAnyPanel: Bool { showsLayersPanel || showsAdjustmentsPanel || showsHistoryPanel || showsClipboardPanel || showsInfoPanel }

    /// Adjust Photo's sliders are in the sidebar, so it stays while they're open (review D, finding 5).
    var canToggleSidebar: Bool { activeEffect != .adjustPhoto }

    /// The toolbar's Sidebar button, View ▸ Sidebar and ⇧S. Opened with no panel chosen, it shows the Layers panel,
    /// so it's never an empty shell (Leah, 2026-10-10).
    func toggleSidebar() {
        guard canToggleSidebar else { return }
        if isSidebarOpen {
            isSidebarOpen = false
        } else {
            openSidebar()
        }
    }

    func openSidebar() {
        if !showsAnyPanel { showsLayersPanel = true }
        isSidebarOpen = true
    }

    /// After the panels are put back as a window was left: an open sidebar with no panel is closed.
    func settlePanels() {
        if isSidebarOpen, !showsAnyPanel { isSidebarOpen = false }
    }

    var layers: [Layer] {
        _ = layersRevision
        return canvas.layers
    }

    var activeLayerIndex: Int {
        _ = layersRevision
        return canvas.activeLayerIndex
    }

    /// Whether the active layer refuses pixel changes: it's locked (or its group is), or it's an adjustment layer or a
    /// group, with no pixels.
    var activeLayerIsLocked: Bool {
        _ = layersRevision
        return canvas.isLocked(canvas.activeLayer) || !canvas.paintLayer.isPixelLayer
    }

    /// Makes another layer active, and the only one chosen. Moved pixels are placed on their own layer first; the
    /// outline stays.
    func selectLayer(at index: Int) {
        guard canvas.layers.indices.contains(index) else { return }
        chooseAnchor = canvas.layers[index].id
        if !otherChosenLayerIDs.isEmpty {
            otherChosenLayerIDs = []
            layersRevision += 1
        }
        makeActive(index)
    }

    private func makeActive(_ index: Int) {
        guard index != canvas.activeLayerIndex else { return }
        finishInteractions()
        placeFloatingKeepingOutline()
        canvas.activeLayerIndex = index
        // Another layer: tools paint on it, not on a mask (stage 27).
        canvas.editsMask = false
        showsMaskAlone = false
        layersRevision += 1
        onRender()
    }

    // MARK: Choosing several layers (FR-8.6)

    /// Every chosen layer, the active one included.
    var chosenLayerIDs: Set<LayerID> {
        _ = layersRevision
        return otherChosenLayerIDs.intersection(canvas.layers.map(\.id)).union([canvas.activeLayer.id])
    }

    var hasSeveralChosenLayers: Bool { chosenLayerIDs.count > 1 }

    /// Shift-click chooses every layer from the anchor to this one; ⌘-click adds it or takes it away. The clicked layer
    /// becomes active, so drawing goes there.
    func chooseLayer(at index: Int, extending: Bool, toggling: Bool) {
        guard canvas.layers.indices.contains(index) else { return }
        let id = canvas.layers[index].id
        if extending {
            let anchor = chooseAnchor.flatMap { anchor in canvas.layers.firstIndex { $0.id == anchor } } ?? canvas.activeLayerIndex
            otherChosenLayerIDs = Set(canvas.layers[min(anchor, index)...max(anchor, index)].map(\.id))
            layersRevision += 1
            makeActive(index)
        } else if toggling {
            let chosen = chosenLayerIDs
            if chosen.contains(id) {
                // One layer always stays chosen.
                guard chosen.count > 1 else { return }
                otherChosenLayerIDs = chosen.subtracting([id])
                layersRevision += 1
                if id == canvas.activeLayer.id, let top = canvas.layers.lastIndex(where: { otherChosenLayerIDs.contains($0.id) }) {
                    makeActive(top)
                }
            } else {
                otherChosenLayerIDs = chosen
                chooseAnchor = id
                layersRevision += 1
                makeActive(index)
            }
        } else {
            selectLayer(at: index)
        }
    }

    /// A right-click on a layer that isn't chosen chooses it alone first, as in Finder and Photoshop.
    func chooseForMenu(layerAt index: Int) {
        guard canvas.layers.indices.contains(index), !chosenLayerIDs.contains(canvas.layers[index].id) else { return }
        selectLayer(at: index)
    }

    /// With several layers chosen, Merge Down is Merge Layers.
    var mergeCommandTitle: String {
        _ = layersRevision
        return hasSeveralChosenLayers ? "Merge Layers" : canvas.activeLayer.isGroup ? "Merge Group" : "Merge Down"
    }

    var canMerge: Bool {
        hasSeveralChosenLayers ? LayerActions.canMergeLayers(chosenLayerIDs, in: canvas) : LayerActions.canMergeDown(canvas)
    }

    var canDeleteLayers: Bool {
        hasSeveralChosenLayers ? LayerActions.canDeleteLayers(chosenLayerIDs, in: canvas) : LayerActions.canDelete(canvas)
    }

    /// Hide or show every chosen layer, following the active one: if it's shown, they're all hidden.
    func toggleChosenLayersVisible() {
        let visible = !canvas.activeLayer.isVisible
        chosenLayerSetting(visible ? "Show Layer" : "Hide Layer", includingLocked: true) { $0.isVisible = visible }
    }

    /// Lock Transparent Pixels on every chosen pixel layer (FR-8.2, stage 23), as one step.
    func toggleChosenLayersLockTransparency() {
        let locks = !canvas.activeLayer.locksTransparency
        chosenLayerSetting(locks ? "Lock Transparent Pixels" : "Unlock Transparent Pixels", includingLocked: true) { layer in
            if layer.adjustment == nil { layer.locksTransparency = locks }
        }
    }

    func setLayerLocksTransparency(_ locks: Bool, at index: Int) {
        guard canvas.layers.indices.contains(index), canvas.layers[index].adjustment == nil else { return }
        layerSetting(locks ? "Lock Transparent Pixels" : "Unlock Transparent Pixels", at: index) { $0.locksTransparency = locks }
    }

    func toggleChosenLayersLocked() {
        let locked = !canvas.activeLayer.isLocked
        chosenLayerSetting(locked ? "Lock Layer" : "Unlock Layer", includingLocked: true) { $0.isLocked = locked }
    }

    /// A settings change on every chosen layer as one step. Locked layers keep their opacity and blend mode.
    private func chosenLayerSetting(_ name: String, includingLocked: Bool = false, _ body: (Layer) -> Void) {
        let ids = Set(canvas.layers.filter { chosenLayerIDs.contains($0.id) && (includingLocked || !canvas.isLocked($0)) }.map(\.id))
        finishInteractions()
        recordingChanges { LayerActions.update(name, layersWithIDs: ids, canvas: canvas, history: history, body) }
        layersRevision += 1
        onRender()
    }

    func addLayer() {
        layerCommand { LayerActions.add(canvas: canvas, history: history, context: selectionContext) }
        // New Layer shows the Layers panel (FR-8.1), never an empty sidebar (review P, finding 3).
        showsLayersPanel = true
        isSidebarOpen = true
    }

    /// Duplicates the chosen layers; the copies are then the chosen ones.
    func duplicateLayer() {
        guard hasSeveralChosenLayers else {
            return layerCommand { LayerActions.duplicate(canvas: canvas, history: history, context: selectionContext) }
        }
        var copies: [LayerID]?
        layerCommand { copies = LayerActions.duplicateLayers(chosenLayerIDs, canvas: canvas, history: history, context: selectionContext); return copies != nil }
        otherChosenLayerIDs = Set(copies ?? [])
    }

    func deleteLayer() {
        let several = hasSeveralChosenLayers, ids = chosenLayerIDs
        layerCommand {
            several ? LayerActions.deleteLayers(ids, canvas: canvas, history: history, context: selectionContext)
                : LayerActions.delete(canvas: canvas, history: history, context: selectionContext)
        }
    }

    /// Merge Down, or Merge Layers with several layers chosen (FR-8.6).
    func mergeDown() {
        let several = hasSeveralChosenLayers, ids = chosenLayerIDs
        layerCommand {
            several ? LayerActions.mergeLayers(ids, canvas: canvas, history: history, context: selectionContext)
                : LayerActions.mergeDown(canvas: canvas, history: history, context: selectionContext)
        }
    }

    // MARK: Layer masks (stages 27 to 28b)

    /// Whether tools paint on the active layer's mask: true after Add Mask or a click on the mask's thumbnail.
    var editsMask: Bool {
        _ = layersRevision
        return canvas.editsMask && canvas.activeLayer.mask != nil
    }

    /// A click on a layer's thumbnail (`mask` false) or its mask's: that layer becomes active, and tools paint there.
    func paint(onMask mask: Bool, at index: Int) {
        guard canvas.layers.indices.contains(index) else { return }
        selectLayer(at: index)
        let editsMask = mask && canvas.activeLayer.mask != nil
        guard editsMask != canvas.editsMask else { return }
        finishInteractions()
        placeFloatingKeepingOutline()
        canvas.editsMask = editsMask
        if editsMask {
            color1 = color1.maskGray
            color2 = color2.maskGray
        } else {
            showsMaskAlone = false
        }
        layersRevision += 1
        onRender()
    }

    /// Layer ▸ Layer Mask ▸ Add Mask: from the selection if there is one (Q28.6), otherwise showing everything.
    func addMask(hidingAll: Bool = false) {
        let start: MaskStart = hidingAll ? .hideAll : canvas.selection.marquee != nil ? .selection : .revealAll
        layerCommand(keepingChoice: true) { LayerActions.addMask(start, canvas: canvas, history: history, context: selectionContext) }
        color1 = color1.maskGray
        color2 = color2.maskGray
    }

    func deleteMask() {
        layerCommand(keepingChoice: true) { LayerActions.deleteMask(canvas: canvas, history: history, context: selectionContext) }
        showsMaskAlone = false
    }

    func applyMask() {
        layerCommand(keepingChoice: true) { LayerActions.applyMask(canvas: canvas, history: history, context: selectionContext) }
        showsMaskAlone = false
    }

    func invertMask() {
        // The mask is what changes, so an adjustment, group or text layer with its own picture chosen is fine (review Z,
        // finding 4).
        guard canvas.activeLayer.mask != nil, !canvas.isLocked(canvas.activeLayer) else { return onRefused() }
        layerCommand(keepingChoice: true) { LayerActions.invertMask(canvas: canvas, history: history, context: selectionContext) }
    }

    /// Shift-click on the mask, or Layer ▸ Layer Mask ▸ Turn Off Mask: the layer shows everywhere until it's turned on.
    func toggleMaskEnabled() {
        let enabled = !canvas.activeLayer.maskEnabled
        layerCommand(keepingChoice: true) { LayerActions.setMaskEnabled(enabled, canvas: canvas, history: history) }
    }

    /// Option-click on the mask: see it alone in grays, or the picture again.
    func toggleMaskAlone(at index: Int) {
        guard canvas.layers.indices.contains(index), canvas.layers[index].mask != nil else { return }
        if index != canvas.activeLayerIndex { selectLayer(at: index) }
        showsMaskAlone.toggle()
    }

    var canAddMask: Bool {
        _ = layersRevision
        return LayerActions.canAddMask(canvas)
    }

    var activeLayerHasMask: Bool {
        _ = layersRevision
        return canvas.activeLayer.mask != nil
    }

    var canApplyMask: Bool {
        _ = layersRevision
        return LayerActions.canApplyMask(canvas)
    }

    // MARK: Layer groups (stages 25 and 26)

    /// Layer ▸ Group (⌘G): the chosen layers into a new group, which becomes active.
    func groupLayers() {
        let ids = chosenLayerIDs
        layerCommand { LayerActions.group(ids, canvas: canvas, history: history, context: selectionContext) }
    }

    /// Layer ▸ Ungroup (⇧⌘G).
    func ungroupLayers() {
        layerCommand { LayerActions.ungroup(canvas: canvas, history: history, context: selectionContext) }
    }

    var canGroupLayers: Bool {
        _ = layersRevision
        return LayerActions.canGroup(chosenLayerIDs, in: canvas)
    }

    var canUngroupLayers: Bool {
        _ = layersRevision
        return LayerActions.canUngroup(canvas)
    }

    /// Moves the layer `id`, with the other chosen layers if it's one of them, to `drop` (stage 26).
    func moveLayer(_ id: LayerID, to drop: LayerDrop) {
        let ids: Set<LayerID> = chosenLayerIDs.count > 1 && chosenLayerIDs.contains(id) ? chosenLayerIDs : [id]
        layerCommand(keepingChoice: true) { LayerActions.moveLayers(ids, to: drop, canvas: canvas, history: history, context: selectionContext) }
    }

    func toggleFold(_ group: LayerID) {
        if foldedGroups.contains(group) { foldedGroups.remove(group) } else { foldedGroups.insert(group) }
    }

    func mergeVisible() {
        layerCommand { LayerActions.mergeVisible(canvas: canvas, history: history, context: selectionContext) }
    }

    /// Layer ▸ Stamp Visible: a merged copy of everything visible, as a new layer above the active one.
    func stampVisible() {
        layerCommand { LayerActions.stampVisible(canvas: canvas, history: history, context: selectionContext) }
    }

    // MARK: Align and Distribute (stage 24)

    /// The chosen layers with pixels to line up: adjustment layers have none.
    /// The chosen pixel layers, and each chosen group's, a group's moving together (stage 26).
    private var chosenAlignUnits: [LayerAlign.Unit] {
        LayerAlign.units(chosenLayerIDs, in: canvas)
    }

    var canAlignChosenLayers: Bool {
        let units = chosenAlignUnits
        return !units.isEmpty && !units.contains { $0.layers.contains(where: canvas.isLocked) }
    }

    var canDistributeChosenLayers: Bool { canAlignChosenLayers && chosenAlignUnits.count >= 3 }

    /// Layer ▸ Align: the chosen layers' visible pixels lined up, as one step. They line up with the selection if
    /// there is one; otherwise one layer lines up with the canvas, and several with the box around them all (Q24.3).
    func alignChosenLayers(_ alignment: LayerAlignment) {
        guard canAlignChosenLayers else { return onRefused() }
        finishInteractions()
        placeFloatingKeepingOutline()
        let units = chosenAlignUnits
        let boxes = units.compactMap(\.box)
        let reference = canvas.selection.marquee.map { $0.bounds.intersection(canvas.bounds) }
            ?? (units.count == 1 ? canvas.bounds : boxes.dropFirst().reduce(boxes.first ?? canvas.bounds) { $0.union($1) })
        moveChosenLayers(LayerAlign.offsets(aligning: units, to: alignment, reference: reference), named: "Align \(alignment.title)")
    }

    /// Layer ▸ Align ▸ Distribute: equal gaps between three or more chosen layers, as one step.
    func distributeChosenLayers(_ distribution: LayerDistribution) {
        guard canDistributeChosenLayers else { return onRefused() }
        finishInteractions()
        placeFloatingKeepingOutline()
        moveChosenLayers(LayerAlign.offsets(distributing: chosenAlignUnits, distribution), named: distribution.title)
    }

    private func moveChosenLayers(_ offsets: [LayerID: IntPoint], named name: String) {
        var refusal: LayerAlign.Refusal?
        recordingChanges { refusal = LayerAlign.move(offsets, named: name, canvas: canvas, history: history, context: selectionContext) }
        // Pixels past the canvas's edge would be lost, so nothing moves (Q24.1).
        if case .offCanvas(let layer) = refusal {
            onRefused()
            showNotice("That would push part of “\(layer)” off the canvas, so nothing moved.")
        }
        layersRevision += 1
        onRender()
    }

    /// Layer ▸ Select All Layers (⌥⌘A): every layer is chosen, hidden and adjustment layers too (Q22.2).
    func selectAllLayers() {
        finishInteractions()
        otherChosenLayerIDs = Set(canvas.layers.map(\.id)).subtracting([canvas.activeLayer.id])
        layersRevision += 1
    }

    /// Option-click on a layer's eye (FR-8.6): only that layer shows. Option-clicking it again brings back what was
    /// showing; if anything was shown or hidden meanwhile, everything shows (Q22.4). Each is one step (Q22.3).
    func toggleIsolation(at index: Int) {
        guard canvas.layers.indices.contains(index) else { return }
        finishInteractions()
        let layer = canvas.layers[index]
        let now = Dictionary(uniqueKeysWithValues: canvas.layers.map { ($0.id, $0.isVisible) })
        if let isolation, isolation.layer == layer.id, let step = isolation.step, history.isDone(step), now != isolation.before {
            let restored = now == isolation.after ? isolation.before : now.mapValues { _ in true }
            self.isolation = nil
            recordingChanges { LayerActions.setVisibility(restored, named: "Show Layers", canvas: canvas, history: history) }
        } else {
            // Its groups show too, or it couldn't; inside a group, its own layers keep theirs (stage 25).
            let inside = layer.isGroup ? canvas.layers[canvas.memberRange(ofGroupAt: index)].map(\.id) : []
            let alone = now.mapValues { _ in false }
                .merging(Dictionary(uniqueKeysWithValues: ([layer] + canvas.ancestors(of: layer)).map { ($0.id, true) })) { $1 }
                .merging(Dictionary(uniqueKeysWithValues: inside.map { ($0, now[$0] ?? true) })) { $1 }
            // Already showing alone, with nothing to go back to: everything shows, as in Photoshop.
            if now == alone {
                isolation = nil
                recordingChanges { LayerActions.setVisibility(now.mapValues { _ in true }, named: "Show Layers", canvas: canvas, history: history) }
                return onRender()
            }
            recordingChanges { LayerActions.setVisibility(alone, named: "Show Only “\(layer.name)”", canvas: canvas, history: history) }
            isolation = Isolation(layer: layer.id, before: now, after: alone, step: history.lastStep)
        }
        onRender()
    }

    func flatten() {
        layerCommand { LayerActions.flatten(canvas: canvas, history: history, context: selectionContext) }
    }

    /// Moves the layer at `source` so it sits at `destination` (stack indices; 0 is the bottom). A chosen layer brings
    /// the other chosen layers with it (FR-8.6).
    func moveLayer(from source: Int, to destination: Int) {
        let ids = chosenLayerIDs
        let together = ids.count > 1 && canvas.layers.indices.contains(source) && ids.contains(canvas.layers[source].id)
        layerCommand(keepingChoice: true) {
            together ? LayerActions.moveLayers(ids, dragging: source, to: destination, canvas: canvas, history: history, context: selectionContext)
                : LayerActions.move(from: source, to: destination, canvas: canvas, history: history, context: selectionContext)
        }
    }

    func setLayerVisible(_ visible: Bool, at index: Int) {
        layerSetting(visible ? "Show Layer" : "Hide Layer", at: index) { $0.isVisible = visible }
    }

    func setLayerLocked(_ locked: Bool, at index: Int) {
        layerSetting(locked ? "Lock Layer" : "Unlock Layer", at: index) { $0.isLocked = locked }
    }

    func renameLayer(at index: Int, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        layerSetting("Rename Layer", at: index) { $0.name = trimmed }
    }

    /// An adjustment layer: change only the layer below it, or everything below (Leah, 2026-10-10).
    /// An adjustment layer, or since stage 28b a pixel layer: only on the layer below it, or everything below.
    func setClipsToLayerBelow(_ clips: Bool) {
        guard !canvas.activeLayer.isGroup, !canvas.isLocked(canvas.activeLayer) else { return }
        layerSetting(clips ? "Only the Layer Below" : "All Layers Below", at: canvas.activeLayerIndex) { $0.clipsToLayerBelow = clips }
    }

    /// On every chosen layer (FR-8.6).
    /// On a group, a blend mode means it's no longer Pass Through (Q25.2).
    func setBlendMode(_ mode: BlendMode) {
        chosenLayerSetting("Blend Mode") { layer in
            layer.blendMode = mode
            if layer.isGroup { layer.passesThrough = false }
        }
    }

    /// A group's Pass Through (Q25.2): its layers blend with everything below.
    func setPassesThrough() {
        chosenLayerSetting("Blend Mode") { layer in
            if layer.isGroup { layer.passesThrough = true }
        }
    }

    /// Opacity while its slider is dragged, on every chosen layer: shown live, recorded as one step by
    /// `finishLayerSettings()`.
    func previewOpacity(_ opacity: Double) {
        previewLayerSettings("Layer Opacity", onChosen: true) { $0.opacity = min(1, max(0, opacity)) }
    }

    /// An adjustment layer's settings while a slider is dragged (FR-8.4), likewise one step.
    func previewAdjustment(_ adjustment: Effect) {
        guard canvas.activeLayer.adjustment != nil else { return }
        previewLayerSettings("Adjustment Settings") { $0.adjustment = adjustment }
    }

    func finishLayerSettings() {
        guard let edit = layerSettingsEdit else { return }
        layerSettingsEdit = nil
        // A view shown while a slider was held never stays in the layer, however the slider let go (review V, finding 1).
        for layer in canvas.layers {
            if case .photo(let photo) = layer.adjustment, photo != photo.withoutViews { layer.adjustment = .photo(photo.withoutViews) }
        }
        recordingChanges { history.commit(edit) }
    }

    private func previewLayerSettings(_ name: String, onChosen: Bool = false, _ change: (Layer) -> Void) {
        if layerSettingsEdit == nil {
            finishInteractions()
            let edit = history.beginEdit(name, on: canvas)
            edit.willChangeLayers()
            layerSettingsEdit = edit
        }
        if onChosen {
            let ids = chosenLayerIDs
            canvas.layers.filter { ids.contains($0.id) && ($0 === canvas.activeLayer || !canvas.isLocked($0)) }.forEach(change)
        } else {
            change(canvas.activeLayer)
        }
        layersRevision += 1
        onRender()
        if activePhotoLayerEdit != nil { refreshPhotoHistogram() }
    }

    /// Adds an adjustment layer above the active layer and shows its settings.
    func addAdjustmentLayer(_ adjustment: Effect, named name: String) {
        layerCommand { LayerActions.addAdjustment(adjustment, named: name, canvas: canvas, history: history, context: selectionContext) }
        isSidebarOpen = true
        showsAdjustmentsPanel = true
    }

    /// Adds an adjustment layer of this kind above the active layer.
    func addAdjustmentLayer(_ choice: AdjustmentChoice) {
        if choice == .autoContrast {
            addAutoContrastLayer()
        } else {
            addAdjustmentLayer(choice.startingAdjustment, named: choice.title)
        }
    }

    /// Changes whenever the layers beneath the active one may look different, so a Levels layer's histogram
    /// is worked out again then, and not on every tick of its own sliders (review D, finding 2).
    var belowActiveLayerKey: Int {
        // Read so SwiftUI looks at the key again when layers change; layers themselves aren't observed.
        _ = layersRevision
        var hasher = Hasher()
        hasher.combine(undoRedoCount)
        hasher.combine(canvas.activeLayer.id)
        for layer in canvas.layers.prefix(canvas.activeLayerIndex) {
            hasher.combine(layer.id)
            hasher.combine(ObjectIdentifier(layer.buffer))
            hasher.combine(layer.isVisible)
            hasher.combine(layer.opacity)
            hasher.combine(layer.blendMode)
            hasher.combine(layer.adjustment)
            hasher.combine(layer.groupID?.rawValue)
            hasher.combine(layer.passesThrough)
        }
        return hasher.finalize()
    }

    /// The layers beneath the active one as they look together, by brightness, for a Levels layer.
    func histogramBelowActiveLayer() -> Histogram {
        let index = canvas.activeLayerIndex
        guard index > 0 else { return Histogram(PixelBuffer(width: 1, height: 1)) }
        return Histogram(canvas.composited(through: index - 1))
    }

    func applyAdjustmentLayer() {
        layerCommand { LayerActions.applyAdjustment(canvas: canvas, history: history, context: selectionContext) }
    }

    /// Sets an adjustment layer's settings in one step (Reset).
    func setAdjustment(_ adjustment: Effect) {
        layerSetting("Adjustment Settings", at: canvas.activeLayerIndex) { $0.adjustment = adjustment }
    }

    var activeAdjustment: Effect? {
        _ = layersRevision
        return canvas.activeLayer.adjustment
    }

    private func layerSetting(_ name: String, at index: Int, _ body: (Layer) -> Void) {
        finishInteractions()
        recordingChanges { LayerActions.update(name, layerAt: index, canvas: canvas, history: history, body) }
        onRender()
    }

    /// A command that changes the layer stack. Afterwards only the active layer is chosen, unless `keepingChoice`.
    func layerCommand(keepingChoice: Bool = false, _ body: () -> Bool) {
        finishInteractions()
        var done = false
        recordingChanges { done = body() }
        if !done { onRefused() }
        if done, !keepingChoice { otherChosenLayerIDs = [] }
        layersRevision += 1
        selectionDidChange()
    }

    /// Whether pixel-changing commands work on the active layer (see `refusedBecauseLocked`).
    /// Its pixels can change: it isn't locked, and it has pixels, or its mask is chosen (stage 27).
    /// A text layer takes none until it's rasterized (Q29.2).
    var activeLayerTakesEdits: Bool {
        !canvas.isLocked(canvas.activeLayer) && canvas.paintLayer.isPixelLayer && canvas.paintLayer.text == nil
    }

    /// Pixel-changing commands call this first. A locked layer refuses them (FR-8.2), and so does an
    /// adjustment layer, which has no pixels to change, and a text layer, which says how to paint on it (Q29.2).
    /// Redaction never asks: it turns a text layer into pixels itself (`Edit.willModify`).
    func refusedBecauseLocked() -> Bool {
        if canvas.paintLayer.text != nil, !canvas.isLocked(canvas.activeLayer) {
            showNotice("This is a text layer. To paint on it, choose Layer ▸ Rasterize Text first.")
            return true
        }
        guard canvas.isLocked(canvas.activeLayer) || !canvas.paintLayer.isPixelLayer else { return false }
        onRefused()
        return true
    }

    /// Layer ▸ Rasterize Text (stage 30).
    func rasterizeText() {
        layerCommand { LayerActions.rasterizeText(canvas: canvas, history: history, context: selectionContext) }
    }

    var canRasterizeText: Bool {
        _ = layersRevision
        return canvas.activeLayer.text != nil && !canvas.isLocked(canvas.activeLayer)
    }
}
