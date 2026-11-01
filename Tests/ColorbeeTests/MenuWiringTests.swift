import AppKit
import Testing
@testable import Colorbee

/// Menu items name their commands by text (`MainMenu.item`), so a typo or a renamed command would leave an item
/// silently greyed out, and its tooltip missing (review round 11, AC 3). This walks the real menu bar instead.
@MainActor
struct MenuWiringTests {
    /// Where Colorbee's commands are handled, and the AppKit classes that handle the standard ones.
    private let handlers: [AnyClass] = [
        DocumentWindow.self, DocumentWindowController.self, ImageDocument.self, AppDelegate.self, DocumentController.self,
        CanvasView.self, NSApplication.self, NSWindow.self, NSDocument.self, NSDocumentController.self, NSTextView.self,
    ]

    private func items(_ menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { [$0] + ($0.submenu.map(items) ?? []) }
    }

    private var commands: [NSMenuItem] {
        let menu = NSApp.mainMenu ?? MainMenu.make()
        // The Services and Window lists are filled in by macOS.
        return items(menu).filter { $0.action != nil && $0.submenu == nil && $0.menu !== NSApp.servicesMenu && $0.menu !== NSApp.windowsMenu }
    }

    @Test func everyCommandHasSomethingToHandleIt() {
        #expect(commands.count > 100)
        for item in commands {
            let action = item.action!
            let handled = item.target.map { ($0 as AnyObject).responds(to: action) } ?? handlers.contains { $0.instancesRespond(to: action) }
            #expect(handled, "\(item.title): \(action)")
        }
    }

    @Test func everyCommandHasATooltip() {
        for item in commands where item.target == nil {
            #expect(!(item.toolTip ?? "").isEmpty, "\(item.title): \(item.action!)")
        }
    }

    /// The canvas keys are named in ShortcutStore and acted on in CanvasView; a key in one and not the other would show
    /// in Settings and do nothing, or never show (review round 11, AC 5).
    @Test func everyCanvasKeyHasAnActionAndEveryActionAKey() {
        #expect(Set(ShortcutStore.canvasCommands.map(\.id)) == Set(CanvasView.canvasActions.keys))
    }
}
