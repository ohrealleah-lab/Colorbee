import AppKit

/// The app tests (`make test`) run inside Colorbee. Their scheme sets `COLORBEE_TESTING`, and Colorbee then starts with
/// this delegate instead of `AppDelegate`: no Dock icon, menus or windows, and it never takes focus from what Leah is
/// doing on the Mac.
@MainActor
final class TestHost: NSObject, NSApplicationDelegate {
    static let isActive = ProcessInfo.processInfo.environment["COLORBEE_TESTING"] == "1"

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    /// A file double-clicked while the tests run can come here (it's Colorbee too). It's left unopened rather than
    /// opened out of sight, so it can be opened normally once the tests end (review P, finding 10).
    func application(_ application: NSApplication, open urls: [URL]) {}
}
