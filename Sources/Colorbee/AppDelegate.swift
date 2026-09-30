import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Strokes must see every input sample (NFR-2).
        NSEvent.isMouseCoalescingEnabled = false
        NSApp.mainMenu = MainMenu.make()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
