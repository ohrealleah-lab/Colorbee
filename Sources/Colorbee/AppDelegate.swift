import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Strokes must see every input sample (NFR-2).
        NSEvent.isMouseCoalescingEnabled = false
        NSApp.mainMenu = MainMenu.make()
    }

    private let services = ServicesProvider()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = services
        NSUpdateDynamicServices()
        ScreenshotWatcher.shared.resume()
    }

    @objc func showSettings(_ sender: Any?) {
        SettingsWindowController.shared.showWindow(nil)
        SettingsWindowController.shared.window?.makeKeyAndOrderFront(nil)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
