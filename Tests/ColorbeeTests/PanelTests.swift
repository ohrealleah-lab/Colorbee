import ColorbeeCore
import Testing
@testable import Colorbee

/// The sidebar and its panels (§23, 2026-10-10): it's never an empty shell.
@MainActor
struct PanelTests {
    private let panels: [ReferenceWritableKeyPath<Editor, Bool>] = [\.showsLayersPanel, \.showsAdjustmentsPanel, \.showsHistoryPanel, \.showsClipboardPanel]

    /// The sidebar open with every panel switched off but the one given, or none.
    private func editor(keeping kept: ReferenceWritableKeyPath<Editor, Bool>? = nil) -> Editor {
        let editor = makeEditor()
        editor.isSidebarOpen = true
        for panel in panels { editor[keyPath: panel] = panel == kept }
        return editor
    }

    @Test func turningOffTheLastPanelClosesTheSidebar() {
        let editor = editor(keeping: \.showsHistoryPanel)
        editor.togglePanel(\.showsHistoryPanel)
        #expect(!editor.isSidebarOpen)
    }

    @Test func openingWithNoPanelShowsLayers() {
        let editor = editor()
        editor.isSidebarOpen = false
        editor.toggleSidebar()
        #expect(editor.isSidebarOpen && editor.showsLayersPanel)
    }

    /// Review P, finding 3.
    @Test func newLayerShowsTheLayersPanel() {
        let editor = editor()
        editor.isSidebarOpen = false
        editor.addLayer()
        #expect(editor.isSidebarOpen && editor.showsLayersPanel)
    }

    /// Review P, finding 4: the sidebar holds Adjust Photo's sliders, so it stays.
    @Test func adjustPhotoKeepsTheSidebarWithNoPanels() {
        let editor = editor(keeping: \.showsLayersPanel)
        editor.beginEffect(.adjustPhoto)
        editor.togglePanel(\.showsLayersPanel)
        #expect(editor.isSidebarOpen)
        editor.cancelEffect()
    }

    @Test func aRestoredSidebarWithNoPanelCloses() {
        let editor = editor()
        editor.settlePanels()
        #expect(!editor.isSidebarOpen)
    }
}
