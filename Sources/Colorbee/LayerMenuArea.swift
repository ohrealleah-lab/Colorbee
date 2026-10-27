import AppKit
import SwiftUI

/// A layer row's right-click menu, in AppKit so the row can be chosen the moment it's right-clicked, before the menu
/// opens (Leah, 2026-10-27): the highlight then shows which layer the menu is for. Other clicks pass straight through.
struct LayerMenuArea: NSViewRepresentable {
    let onOpen: () -> Void
    let menu: () -> NSMenu

    func makeNSView(context: Context) -> LayerMenuView {
        let view = LayerMenuView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: LayerMenuView, context: Context) {
        view.onOpen = onOpen
        view.makeMenu = menu
    }
}

final class LayerMenuView: NSView {
    var onOpen: () -> Void = {}
    var makeMenu: () -> NSMenu = { NSMenu() }

    /// Only a right-click or Control-click lands here; the row's own clicks, drags and buttons work as before.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let event = NSApp.currentEvent,
              event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control)) else { return nil }
        return super.hitTest(point)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        onOpen()
        return makeMenu()
    }
}

/// A menu item that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let run: () -> Void

    init(_ title: String, enabled: Bool = true, _ run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(runAction), keyEquivalent: "")
        target = self
        isEnabled = enabled
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func runAction() { run() }
}
