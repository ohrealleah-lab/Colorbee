import AppKit
import ColorbeeCore

/// Writes every menu command with its default shortcut and tooltip, and the canvas keys, as JSON, for the help
/// book's generated Menus and Keyboard Shortcuts pages (FR-14.6, `make help`): `-ColorbeeDumpMenus /path/to.json`.
/// Runs before any window opens and reads the menus as built, so changed shortcuts on this Mac don't leak in.
@MainActor
enum HelpDump {
    static var path: String? { UserDefaults.standard.string(forKey: "ColorbeeDumpMenus") }

    private struct Entry: Encodable {
        let menu: String
        let title: String
        let shortcut: String?
        let summary: String?
    }

    private struct Dump: Encodable {
        let menus: [Entry]
        let canvasKeys: [Entry]
    }

    /// Menus macOS fills in itself, listed as one line each.
    private static let filledByMacOS: Set<String> = ["Services", "Export As"]

    static func write(_ mainMenu: NSMenu, to path: String) throws {
        var entries: [Entry] = []
        func walk(_ menu: NSMenu, top: String, path: String) {
            for item in menu.items where !item.isSeparatorItem && !item.isSectionHeader && !item.isHidden {
                let title = path.isEmpty ? item.title : "\(path) ▸ \(item.title)"
                if let submenu = item.submenu, !filledByMacOS.contains(item.title), !submenu.items.isEmpty {
                    walk(submenu, top: top, path: title)
                } else {
                    entries.append(Entry(menu: top, title: title, shortcut: ShortcutStore.shortcut(of: item)?.display,
                                         summary: item.toolTip))
                }
            }
        }
        for top in mainMenu.items {
            guard let submenu = top.submenu else { continue }
            walk(submenu, top: submenu.title, path: "")
        }
        let keys = ShortcutStore.canvasCommands.map {
            Entry(menu: $0.group, title: $0.title, shortcut: $0.defaultShortcut?.display, summary: nil)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        try encoder.encode(Dump(menus: entries, canvasKeys: keys)).write(to: URL(fileURLWithPath: path))
    }
}
