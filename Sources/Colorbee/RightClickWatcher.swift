import AppKit
import SwiftUI

/// Calls `action` when its window is right-clicked (or Control-clicked), just before SwiftUI opens a context menu,
/// so the menu can act on what was clicked. The action decides what was clicked; this never takes the click itself.
struct RightClickWatcher: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> WatcherView {
        let view = WatcherView()
        view.action = action
        return view
    }

    func updateNSView(_ view: WatcherView, context: Context) {
        view.action = action
    }

    final class WatcherView: NSView {
        var action: () -> Void = {}
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            // A local monitor sees the click before SwiftUI does, so the page changes before the menu appears.
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
                MainActor.assumeIsolated { self?.watch(event) }
                return event
            }
        }

        private func watch(_ event: NSEvent) {
            let isMenuClick = event.type == .rightMouseDown
                || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
            guard isMenuClick, event.window === window else { return }
            action()
        }
    }
}
