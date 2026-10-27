import AppKit
import Testing
@testable import Colorbee

/// Canvas keys that reach the window are handed to the canvas (Leah, 2026-10-27). The window is made but never shown.
@MainActor
struct KeyForwardingTests {
    /// The canvas keys come from the shortcut store, which the test host doesn't fill (it builds no menus). Reading
    /// the shortcuts saves nothing.
    init() {
        if ShortcutStore.shared.book.shortcut(for: "canvas.brush") == nil { ShortcutStore.shared.register(MainMenu.make()) }
    }

    private var brushKey: String { ShortcutStore.shared.book.shortcut(for: "canvas.brush")!.key }

    private func window(for editor: Editor) -> (DocumentWindow, CanvasView) {
        let window = DocumentWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.titled],
                                    backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let canvas = CanvasView(editor: editor)
        window.contentView = canvas
        window.canvasView = canvas
        window.editor = editor
        window.makeFirstResponder(nil)
        return (window, canvas)
    }

    private func key(_ characters: String) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 11)!
    }

    @Test func aToolKeyReachesTheCanvasWhenTheWindowHasTheKeyboard() {
        let editor = makeEditor()
        let (window, _) = window(for: editor)
        #expect(window.firstResponder === window)
        #expect(editor.tool != .brush)
        window.keyDown(with: key(brushKey))
        #expect(editor.tool == .brush)
    }

    /// Review T, finding 1: with an effect's bar open the canvas passes keys back up, and the window mustn't hand them
    /// over again. Before the fix this test never returned.
    @Test func aKeyTheCanvasPassesBackDoesntLoop() {
        let editor = makeEditor()
        let (window, _) = window(for: editor)
        editor.beginEffect(.gaussianBlur)
        window.keyDown(with: key(brushKey))
        #expect(editor.activeEffect == .gaussianBlur && editor.tool != .brush)
        editor.cancelEffect()
    }
}
