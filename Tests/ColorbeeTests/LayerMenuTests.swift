import AppKit
import Testing
@testable import Colorbee

/// The Layers panel's right-click menu (FR-8.6).
@MainActor
struct LayerMenuTests {
    /// A background and three layers, "Layer 1" to "Layer 3", with Layer 1 active.
    private func editor() -> Editor {
        let editor = makeEditor(width: 8, height: 8)
        for _ in 0..<3 { editor.addLayer() }
        editor.selectLayer(at: 1)
        return editor
    }

    private func item(_ menu: NSMenu, _ title: String) -> NSMenuItem? { menu.items.first { $0.title == title } }

    /// Chooses an item as the menu would.
    private func choose(_ item: NSMenuItem?) {
        guard let item, let action = item.action else { return }
        NSApp.sendAction(action, to: item.target, from: item)
    }

    @Test func oneLayerReadsInTheSingular() throws {
        let editor = editor()
        let menu = LayerMenu.make(for: editor, layerAt: 1) {}
        #expect(menu.items.map(\.title) == ["Merge Down", "Duplicate Layer", "Delete Layer", "", "Hide Layer", "Lock Layer", "",
                                            "Rename…", "Layer Properties…"])
        #expect(try #require(item(menu, "Rename…")).isEnabled)
        #expect(try #require(item(menu, "Merge Down")).isEnabled)
    }

    @Test func severalLayersReadInThePluralAndRenameIsGreyedOut() throws {
        let editor = editor()
        editor.chooseLayer(at: 3, extending: false, toggling: true)
        let menu = LayerMenu.make(for: editor, layerAt: 3) {}
        #expect(menu.items.map(\.title).filter { !$0.isEmpty } == ["Merge Layers", "Duplicate Layers", "Delete Layers", "Hide Layers",
                                                                    "Lock Layers", "Rename…", "Layer Properties…"])
        #expect(try !#require(item(menu, "Rename…")).isEnabled)
        #expect(try #require(item(menu, "Merge Layers")).isEnabled)
    }

    @Test func aLockedChosenLayerGreysOutMergeAndDelete() throws {
        let editor = editor()
        editor.canvas.layers[3].isLocked = true
        editor.chooseLayer(at: 3, extending: false, toggling: true)
        let menu = LayerMenu.make(for: editor, layerAt: 3) {}
        #expect(try !#require(item(menu, "Merge Layers")).isEnabled)
        #expect(try !#require(item(menu, "Delete Layers")).isEnabled)
        #expect(try #require(item(menu, "Unlock Layers")).isEnabled)
    }

    @Test func itemsRunTheirCommandsOnTheChosenLayers() {
        let editor = editor()
        editor.chooseLayer(at: 3, extending: false, toggling: true)
        choose(item(LayerMenu.make(for: editor, layerAt: 3) {}, "Hide Layers"))
        #expect(editor.canvas.layers.map(\.isVisible) == [true, false, true, false])
        choose(item(LayerMenu.make(for: editor, layerAt: 3) {}, "Delete Layers"))
        #expect(editor.canvas.layers.map(\.name) == ["Background", "Layer 2"])
    }

    @Test func renameAndLayerPropertiesActOnTheRightClickedLayer() {
        let editor = editor()
        var renamed = false
        let menu = LayerMenu.make(for: editor, layerAt: 2) { renamed = true }
        choose(item(menu, "Rename…"))
        #expect(renamed)
        choose(item(menu, "Layer Properties…"))
        #expect(editor.canvas.activeLayer.name == "Layer 2" && !editor.hasSeveralChosenLayers)
    }

    /// The right-clicked layer is chosen before the menu is built, so the menu speaks for it (Leah, 2026-10-27).
    @Test func rightClickingChoosesTheLayerBeforeTheMenuIsBuilt() throws {
        let editor = editor()
        let view = LayerMenuView()
        var builtFor: String?
        view.onOpen = { editor.chooseForMenu(layerAt: 3) }
        view.makeMenu = {
            builtFor = editor.canvas.activeLayer.name
            return LayerMenu.make(for: editor, layerAt: 3) {}
        }
        let click = try #require(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                    windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let menu = try #require(view.menu(for: click))
        #expect(builtFor == "Layer 3")
        #expect(item(menu, "Delete Layer") != nil)
    }
}
