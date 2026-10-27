import AppKit

/// The Layers panel's right-click menu (FR-8.6), built once the right-clicked layer is chosen, so it speaks for what's
/// chosen now.
@MainActor
enum LayerMenu {
    /// `rename` starts renaming the layer in place; the panel owns that.
    static func make(for editor: Editor, layerAt index: Int, rename: @escaping () -> Void) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let layers = editor.hasSeveralChosenLayers ? "Layers" : "Layer"
        let active = editor.canvas.activeLayer
        // Adding first, as in Photoshop's layer menu; each goes just above the right-clicked layer (Leah, 2026-10-27).
        menu.addItem(ClosureMenuItem("New Layer") { editor.addLayer() })
        let adjustments = NSMenuItem(title: "New Adjustment Layer", action: nil, keyEquivalent: "")
        adjustments.submenu = NSMenu(title: "New Adjustment Layer")
        for choice in AdjustmentChoice.allCases {
            let item = ClosureMenuItem(choice.title) { editor.addAdjustmentLayer(choice) }
            item.image = NSImage(systemSymbolName: choice.symbol, accessibilityDescription: nil)
            adjustments.submenu?.addItem(item)
        }
        menu.addItem(adjustments)
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(editor.mergeCommandTitle, enabled: editor.canMerge) { editor.mergeDown() })
        menu.addItem(ClosureMenuItem("Duplicate \(layers)") { editor.duplicateLayer() })
        menu.addItem(ClosureMenuItem("Delete \(layers)", enabled: editor.canDeleteLayers) { editor.deleteLayer() })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem((active.isVisible ? "Hide " : "Show ") + layers) { editor.toggleChosenLayersVisible() })
        menu.addItem(ClosureMenuItem((active.isLocked ? "Unlock " : "Lock ") + layers) { editor.toggleChosenLayersLocked() })
        menu.addItem(.separator())
        // A name belongs to one layer (Leah, 2026-10-27).
        menu.addItem(ClosureMenuItem("Rename…", enabled: !editor.hasSeveralChosenLayers, rename))
        // Its name, blend mode and opacity are at the top of the Layers panel once it's the active layer.
        menu.addItem(ClosureMenuItem("Layer Properties…") { editor.selectLayer(at: index) })
        return menu
    }
}
