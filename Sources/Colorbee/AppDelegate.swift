import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // The first document controller made becomes the shared one, so RAW files go to the Develop window.
        _ = DocumentController()
        // Before any window exists, so none shows in the wrong appearance first.
        AppearanceSetting.apply()
        // Strokes must see every input sample (NFR-2).
        NSEvent.isMouseCoalescingEnabled = false
        // Help ▸ Colorbee Help and the ? buttons use this copy's help book. Left to find it alone, macOS can keep
        // an older copy's cached book (from another build or version), whose new sections then can't be found.
        NSHelpManager.shared.registerBooks(in: .main)
        let menu = MainMenu.make()
        // `make help`: the menus as built, before this Mac's changed shortcuts are applied; then quit.
        if let path = HelpDump.path {
            do { try HelpDump.write(menu, to: path) } catch { fputs("\(error)\n", stderr); exit(1) }
            exit(0)
        }
        NSApp.mainMenu = menu
        // Every menu command and canvas key, with any changed shortcuts (FR-15.3).
        ShortcutStore.shared.register(menu)
    }

    private let services = ServicesProvider()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A help screenshot (`make help-shots`) needs Colorbee in front, also for the Develop window's scene.
        if HelpShots.scene > 0 { NSApp.activate() }
        NSApp.servicesProvider = services
        NSUpdateDynamicServices()
        ImageDocument.removeShareFolders()
    }

    private let continuityImport = ContinuityImport { nil }

    /// Import from iPhone or iPad with no window open (FR-11.7).
    @objc func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?) -> Any? {
        continuityImport.requestor(sendType: sendType, returnType: returnType)
    }

    /// Paste into New Image with no window open, the usual way to start on a screenshot (review M, finding 1).
    @objc func pasteIntoNewImage(_ sender: Any?) {
        do { try DocumentWindow.openClipboardImage() } catch { NSApp.presentError(error) }
    }

    @objc func showSettings(_ sender: Any?) {
        SettingsWindowController.shared.showWindow(nil)
        SettingsWindowController.shared.window?.makeKeyAndOrderFront(nil)
    }

    /// Quitting: each window with a redaction not yet saved with ⌘S is saved and gives the earlier-versions
    /// warning first, one at a time, then Colorbee quits (Leah, 2026-10-04).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let waiting = NSDocumentController.shared.documents.compactMap { $0 as? ImageDocument }.filter(\.wantsRedactionCheckBeforeClosing)
        guard !waiting.isEmpty else { return .terminateNow }
        func check(_ remaining: ArraySlice<ImageDocument>) {
            guard let document = remaining.first else { return sender.reply(toApplicationShouldTerminate: true) }
            document.showWindows()
            document.checkRedactionBeforeClosing { check(remaining.dropFirst()) }
        }
        check(waiting[...])
        return .terminateLater
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.action == #selector(pasteIntoNewImage(_:)) ? PasteboardImages.hasImage() : true
    }
}
