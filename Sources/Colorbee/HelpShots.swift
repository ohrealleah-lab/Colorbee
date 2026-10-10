import AppKit
import ColorbeeCore

/// Sets up one of the help book's screenshots (FR-14.6), for `make help-shots`: `-ColorbeeHelpShot N` arranges scene
/// N in a fixed-size window, in front, and Leah takes the picture (⇧⌘4, Space, Option-click). The script launches
/// Colorbee once per scene, in light mode, with the made-up sample image, and files each picture.
@MainActor
enum HelpShots {
    static var scene: Int { UserDefaults.standard.integer(forKey: "ColorbeeHelpShot") }

    static func startIfRequested(window: NSWindow, editor: Editor) {
        guard scene > 0 else { return }
        window.setContentSize(NSSize(width: 1280, height: 820))
        window.center()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        switch scene {
        case 4:
            editor.beginAutoRedact()
        case 5:
            Task { await redactThenCompare(editor) }
        case 6:
            editor.addLayer()
            editor.addAdjustmentLayer(.levels(Levels(black: 12, white: 240, gamma: 1.1)), named: "Levels")
            editor.isSidebarOpen = true
            editor.showsLayersPanel = true
        case 7, 8:
            UserDefaults.standard.set(scene == 7 ? "exports" : "shortcuts", forKey: "SettingsTab")
            SettingsWindowController.shared.showWindow(nil)
            SettingsWindowController.shared.window?.makeKeyAndOrderFront(nil)
        default:
            break
        }
    }

    /// Before/After: the sample redacted with Solid Fill, compared with how it opened.
    private static func redactThenCompare(_ editor: Editor) async {
        editor.beginAutoRedact()
        while editor.autoRedact?.isReading == true { try? await Task.sleep(for: .milliseconds(100)) }
        editor.applyAutoRedact()
        while editor.autoRedact != nil { try? await Task.sleep(for: .milliseconds(100)) }
        editor.toggleComparison()
    }
}
