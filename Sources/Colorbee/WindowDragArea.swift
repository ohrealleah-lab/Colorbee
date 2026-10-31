import AppKit
import SwiftUI

/// Toolbar space that acts like the title bar: dragging moves the window, and a double-click does what System
/// Settings says a title bar's double-click does. It covers a toolbar control while it's hidden (Leah, 2026-10-31),
/// since the toolbar item would otherwise take the click.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        private func fill(_ window: NSWindow) {
            guard let item = NSApp.windowsMenu?.items.first(where: { $0.title == "Fill" }), let action = item.action else { return window.zoom(nil) }
            NSApp.sendAction(action, to: item.target, from: item)
        }

        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            if event.clickCount == 2 {
                switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
                case "Minimize": window.miniaturize(nil)
                case "None": break
                // Newer macOS can fill the screen instead (review Z, finding 8): the Window menu's own Fill does it.
                case "Fill": fill(window)
                default: window.zoom(nil)
                }
            } else {
                window.performDrag(with: event)
            }
        }
    }
}
