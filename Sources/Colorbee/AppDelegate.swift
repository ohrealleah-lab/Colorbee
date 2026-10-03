import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Strokes must see every input sample (NFR-2).
        NSEvent.isMouseCoalescingEnabled = false
        let menu = MainMenu.make()
        NSApp.mainMenu = menu
        // Every menu command and canvas key, with any changed shortcuts (FR-15.3).
        ShortcutStore.shared.register(menu)
    }

    private let services = ServicesProvider()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = services
        NSUpdateDynamicServices()
    }

    @objc func showSettings(_ sender: Any?) {
        SettingsWindowController.shared.showWindow(nil)
        SettingsWindowController.shared.window?.makeKeyAndOrderFront(nil)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
