import AppKit
import ColorbeeCore
import Observation

/// Every shortcut in Colorbee: the menus' key equivalents and the canvas keys (FR-15.3). Changes apply
/// to the menus straight away and are kept between launches.
@MainActor
@Observable
final class ShortcutStore {
    static let shared = ShortcutStore()
    private static let key = "KeyboardShortcuts"

    private(set) var book = ShortcutBook(commands: [])
    /// Shortcuts set in System Settings on this Mac, with who owns them.
    private(set) var system: [KeyShortcut: String] = [:]
    @ObservationIgnored private weak var menu: NSMenu?

    /// The single-key canvas actions, in the order shown in Settings.
    static let canvasCommands: [ShortcutCommand] = [
        ("canvas.pencil", "Pencil", "p"), ("canvas.brush", "Brush", "b"), ("canvas.eraser", "Eraser", "e"),
        ("canvas.fill", "Fill", "g"), ("canvas.text", "Text", "t"), ("canvas.eyedropper", "Eyedropper", "i"),
        ("canvas.magnifier", "Magnifier", "z"), ("canvas.rectangleSelect", "Rectangle Select", "m"),
        ("canvas.lassoSelect", "Free-Form Select", "l"), ("canvas.magicWand", "Magic Wand", "w"),
        ("canvas.shape", "Shapes", "u"), ("canvas.measure", "Measure", "r"), ("canvas.stepBadge", "Step Badge", "n"),
        ("canvas.swapColors", "Swap Colors", "x"), ("canvas.resetColors", "Default Colors", "d"),
        ("canvas.smaller", "Smaller Size", "["), ("canvas.larger", "Larger Size", "]"),
    ].map { ShortcutCommand(id: $0.0, title: $0.1, group: "Tools and Canvas Keys", kind: .canvas, defaultShortcut: KeyShortcut($0.2)) }

    /// The Mac's own app and window commands: listed, but not changeable.
    private static let fixedActions: Set<String> = [
        "orderFrontStandardAboutPanel:", "showSettings:", "hide:", "hideOtherApplications:", "unhideAllApplications:",
        "terminate:", "performClose:", "performMiniaturize:", "performZoom:", "arrangeInFront:", "toggleFullScreen:",
    ]
    /// Commands told apart by their menu item's tag rather than their action.
    private static let taggedActions: Set<String> = ["applyOrientation:", "setSymmetry:", "newAdjustmentLayer:"]
    /// Menus filled in as they open, or owned by macOS.
    private static let skippedMenus: Set<String> = ["Export As", "Open Recent", "Services", "Help"]
    /// Menus whose own window commands are listed (with a padlock), without the window list macOS adds
    /// (§23, stage 7c; review J, finding 11).
    private static let fixedOnlyMenus: Set<String> = ["Window"]

    private init() {}

    /// Reads every command from the menu bar, then applies saved changes.
    func register(_ mainMenu: NSMenu) {
        menu = mainMenu
        var commands: [ShortcutCommand] = []
        var seen = Set<String>()
        func walk(_ menu: NSMenu, group: String, path: String) {
            for item in menu.items where !item.isSeparatorItem {
                if Self.fixedOnlyMenus.contains(menu.title), item.action.map({ !Self.fixedActions.contains(NSStringFromSelector($0)) }) ?? true { continue }
                if let submenu = item.submenu {
                    guard !Self.skippedMenus.contains(submenu.title) else { continue }
                    let nested = path.isEmpty ? "" : "\(path) ▸ "
                    walk(submenu, group: group.isEmpty ? submenu.title : group, path: group.isEmpty ? "" : nested + item.title)
                    continue
                }
                guard let id = Self.id(of: item), seen.insert(id).inserted else { continue }
                let action = NSStringFromSelector(item.action!)
                commands.append(ShortcutCommand(
                    id: id,
                    title: path.isEmpty ? item.title : "\(path) ▸ \(item.title)",
                    group: group,
                    kind: .menu,
                    defaultShortcut: Self.shortcut(of: item),
                    isEditable: !Self.fixedActions.contains(action)
                ))
            }
        }
        walk(mainMenu, group: "", path: "")
        book = ShortcutBook(commands: commands + Self.canvasCommands)
        system = SystemShortcuts.read()
        if let data = UserDefaults.standard.data(forKey: Self.key) {
            try? book.importChanges(from: data, system: system)
        }
        applyToMenus()
    }

    // MARK: Changing

    /// Who in macOS takes a command's current shortcut first, if anyone (a default that clashes with this Mac's settings).
    func systemOwner(of id: String) -> String? {
        book.shortcut(for: id).flatMap { system[$0] ?? ShortcutBook.reservedByMac[$0] }
    }

    /// "Title (key)" with the command's current shortcut, or just the title if it has none, for tooltips that
    /// follow shortcut changes (review J, finding 14). `id` is a canvas key's id ("canvas.pencil") or a menu
    /// command's selector name ("toggleLayers:").
    func hint(_ title: String, command id: String) -> String {
        book.shortcut(for: id).map { "\(title) (\($0.display))" } ?? title
    }

    func check(_ shortcut: KeyShortcut, for id: String) -> ShortcutBook.Check {
        book.check(shortcut, for: id, system: system)
    }

    func assign(_ shortcut: KeyShortcut?, to id: String) {
        book.assign(shortcut, to: id)
        changed()
    }

    func reset(_ id: String) {
        book.reset(id)
        changed()
    }

    func resetAll() {
        book.resetAll()
        changed()
    }

    /// Returns what the file asked for that couldn't be kept.
    func importChanges(from url: URL) throws -> [String] {
        let problems = try book.importChanges(from: Data(contentsOf: url), system: system)
        changed()
        return problems
    }

    func export(to url: URL) throws {
        try book.exported().write(to: url, options: .atomic)
    }

    private func changed() {
        if let data = try? book.exported() { UserDefaults.standard.set(data, forKey: Self.key) }
        applyToMenus()
    }

    // MARK: Using

    /// The canvas command a key press triggers, if any. Only plain keys and Shift + a key count.
    func canvasCommand(for event: NSEvent) -> String? {
        guard let shortcut = Self.shortcut(of: event), shortcut.modifiers.subtracting(.shift).isEmpty else { return nil }
        return book.command(for: shortcut, kind: .canvas)?.id
    }

    private func applyToMenus() {
        guard let menu else { return }
        func walk(_ menu: NSMenu) {
            for item in menu.items {
                if let submenu = item.submenu {
                    if !Self.skippedMenus.contains(submenu.title), !Self.fixedOnlyMenus.contains(submenu.title) { walk(submenu) }
                    continue
                }
                guard let id = Self.id(of: item), let command = book.command(withID: id), command.isEditable else { continue }
                let (key, mask) = Self.keyEquivalent(for: book.shortcut(for: id))
                item.keyEquivalent = key
                item.keyEquivalentModifierMask = mask
            }
        }
        walk(menu)
    }

    // MARK: Converting

    private static func id(of item: NSMenuItem) -> String? {
        guard let action = item.action else { return nil }
        let name = NSStringFromSelector(action)
        return taggedActions.contains(name) ? "\(name)#\(item.tag)" : name
    }

    private static let functionKeys: [Int: String] = [
        NSLeftArrowFunctionKey: "left", NSRightArrowFunctionKey: "right", NSUpArrowFunctionKey: "up",
        NSDownArrowFunctionKey: "down", NSDeleteFunctionKey: "forwardDelete",
    ]

    static func shortcut(of item: NSMenuItem) -> KeyShortcut? {
        guard let scalar = item.keyEquivalent.unicodeScalars.first else { return nil }
        let key: String
        switch Int(scalar.value) {
        case 0x08, 0x7F: key = "delete"
        case 0x0D: key = "return"
        case 0x09: key = "tab"
        case 0x1B: key = "escape"
        case 0x20: key = "space"
        case NSF1FunctionKey...NSF20FunctionKey: key = "f\(Int(scalar.value) - NSF1FunctionKey + 1)"
        case let value where functionKeys[value] != nil: key = functionKeys[value]!
        default: key = item.keyEquivalent.lowercased()
        }
        var modifiers = modifiers(of: item.keyEquivalentModifierMask)
        // An uppercase key equivalent means Shift.
        if item.keyEquivalent != item.keyEquivalent.lowercased() { modifiers.insert(.shift) }
        return KeyShortcut(key, modifiers)
    }

    static func keyEquivalent(for shortcut: KeyShortcut?) -> (String, NSEvent.ModifierFlags) {
        guard let shortcut else { return ("", []) }
        let key: String = switch shortcut.key {
        case "delete": "\u{8}"
        case "return": "\r"
        case "tab": "\t"
        case "escape": "\u{1b}"
        case "space": " "
        case "forwardDelete": String(Character(UnicodeScalar(NSDeleteFunctionKey)!))
        case "left": String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!))
        case "right": String(Character(UnicodeScalar(NSRightArrowFunctionKey)!))
        case "up": String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))
        case "down": String(Character(UnicodeScalar(NSDownArrowFunctionKey)!))
        // F1 to F20 only: a shortcuts file could hold any number (local sweep after review round 1).
        case let name where name.hasPrefix("f") && Int(name.dropFirst()).map((1...20).contains) == true:
            String(Character(UnicodeScalar(NSF1FunctionKey + Int(name.dropFirst())! - 1)!))
        default: shortcut.key
        }
        var mask: NSEvent.ModifierFlags = []
        if shortcut.modifiers.contains(.command) { mask.insert(.command) }
        if shortcut.modifiers.contains(.option) { mask.insert(.option) }
        if shortcut.modifiers.contains(.control) { mask.insert(.control) }
        if shortcut.modifiers.contains(.shift) { mask.insert(.shift) }
        return (key, mask)
    }

    static func modifiers(of flags: NSEvent.ModifierFlags) -> KeyShortcut.Modifiers {
        var modifiers: KeyShortcut.Modifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        return modifiers
    }

    /// A key press as a shortcut, using the unshifted character so ⇧[ is "Shift + [" rather than "{".
    static func shortcut(of event: NSEvent) -> KeyShortcut? {
        let modifiers = modifiers(of: event.modifierFlags)
        switch event.specialKey {
        case .leftArrow?: return KeyShortcut("left", modifiers)
        case .rightArrow?: return KeyShortcut("right", modifiers)
        case .upArrow?: return KeyShortcut("up", modifiers)
        case .downArrow?: return KeyShortcut("down", modifiers)
        case .delete?, .backspace?: return KeyShortcut("delete", modifiers)
        case .deleteForward?: return KeyShortcut("forwardDelete", modifiers)
        case .carriageReturn?, .enter?, .newline?: return KeyShortcut("return", modifiers)
        case .tab?, .backTab?: return KeyShortcut("tab", modifiers)
        default: break
        }
        if let special = event.specialKey?.rawValue, (NSF1FunctionKey...NSF20FunctionKey).contains(special) {
            return KeyShortcut("f\(special - NSF1FunctionKey + 1)", modifiers)
        }
        guard let characters = event.characters(byApplyingModifiers: []), let first = characters.first else { return nil }
        switch first {
        case " ": return KeyShortcut("space", modifiers)
        case "\u{1b}": return KeyShortcut("escape", modifiers)
        default: return KeyShortcut(String(first), modifiers)
        }
    }
}

/// The keyboard shortcuts macOS uses system-wide, as set on this Mac in System Settings ▸ Keyboard ▸
/// Keyboard Shortcuts (Mission Control, Spaces, Spotlight, screenshots, input sources…).
enum SystemShortcuts {
    /// macOS's defaults for the common ones, by their id in com.apple.symbolichotkeys: (name, key code, modifiers).
    private static let defaults: [Int: (String, Int, KeyShortcut.Modifiers)] = [
        28: ("macOS for screenshots", 20, [.command, .shift]),
        29: ("macOS to copy a picture of the screen", 20, [.command, .shift, .control]),
        30: ("macOS for screenshots", 21, [.command, .shift]),
        31: ("macOS to copy a picture of the selected area", 21, [.command, .shift, .control]),
        184: ("macOS for screenshot options", 23, [.command, .shift]),
        32: ("macOS for Mission Control", 126, [.control]),
        33: ("macOS for Application Windows", 125, [.control]),
        36: ("macOS to Show Desktop", 103, []),
        52: ("macOS to turn Dock hiding on or off", 2, [.command, .option]),
        59: ("macOS to turn VoiceOver on or off", 96, [.command]),
        60: ("macOS to select the previous input source", 49, [.control]),
        61: ("macOS to select the next input source", 49, [.control, .option]),
        64: ("macOS for Spotlight", 49, [.command]),
        65: ("macOS for a Finder search window", 49, [.command, .option]),
        79: ("macOS to move left a space", 123, [.control]),
        81: ("macOS to move right a space", 124, [.control]),
        98: ("macOS to search the Help menu", 44, [.command, .shift]),
        162: ("macOS for Accessibility Controls", 96, [.command, .option]),
    ]

    /// Names for the other entries macOS may have, when they're switched on.
    private static let names: [Int: String] = [
        7: "macOS to move focus to the menu bar", 8: "macOS to move focus to the Dock", 9: "macOS to move focus to the active window",
        10: "macOS to move focus to the window toolbar", 11: "macOS to move focus to the floating window",
        27: "macOS to move focus to the next window", 57: "macOS to move focus to the status menus",
        118: "macOS to switch to Desktop 1", 119: "macOS to switch to Desktop 2", 120: "macOS to switch to Desktop 3",
        121: "macOS to switch to Desktop 4", 160: "macOS for Launchpad", 163: "macOS for Notification Center",
        175: "macOS to turn Do Not Disturb on or off", 190: "macOS for Quick Note",
    ]

    /// US keyboard key codes to characters, for entries that only record a key code.
    private static let keyCodes: [Int: String] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e",
        15: "r", 16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-",
        28: "8", 29: "0", 30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p", 37: "l", 38: "j", 39: "'", 40: "k", 41: ";",
        42: "\\", 43: ",", 44: "/", 45: "n", 46: "m", 47: ".", 50: "`", 49: "space", 48: "tab", 53: "escape", 51: "delete",
        36: "return", 123: "left", 124: "right", 125: "down", 126: "up",
        122: "f1", 120: "f2", 99: "f3", 118: "f4", 96: "f5", 97: "f6", 98: "f7", 100: "f8", 101: "f9", 109: "f10", 103: "f11", 111: "f12",
    ]

    static func read() -> [KeyShortcut: String] {
        var entries: [Int: (name: String, shortcut: KeyShortcut?, enabled: Bool)] = [:]
        for (id, value) in defaults {
            entries[id] = (value.0, keyCodes[value.1].map { KeyShortcut($0, value.2) }, true)
        }
        let stored = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys") ?? [:]
        for (key, raw) in stored {
            guard let id = Int(key), let entry = raw as? [String: Any] else { continue }
            let enabled = (entry["enabled"] as? Bool) ?? ((entry["enabled"] as? Int) == 1)
            let name = defaults[id]?.0 ?? names[id] ?? "a macOS shortcut (System Settings ▸ Keyboard ▸ Keyboard Shortcuts)"
            var shortcut: KeyShortcut?
            if let value = entry["value"] as? [String: Any], let parameters = value["parameters"] as? [Int], parameters.count >= 3 {
                let character = parameters[0], code = parameters[1], flags = parameters[2]
                // Globe (Fn) shortcuts like Quick Note can't clash with Colorbee's. Arrows and F-keys carry
                // the same flag without involving the Globe key.
                let isArrowOrFunctionKey = [123, 124, 125, 126, 122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111].contains(code)
                if flags & (1 << 23) != 0, !isArrowOrFunctionKey { continue }
                var modifiers: KeyShortcut.Modifiers = []
                if flags & (1 << 17) != 0 { modifiers.insert(.shift) }
                if flags & (1 << 18) != 0 { modifiers.insert(.control) }
                if flags & (1 << 19) != 0 { modifiers.insert(.option) }
                if flags & (1 << 20) != 0 { modifiers.insert(.command) }
                let key: String? = if let mapped = keyCodes[code] {
                    mapped
                } else if character > 0, character < 65535, let scalar = UnicodeScalar(character) {
                    String(Character(scalar)).lowercased()
                } else {
                    nil
                }
                shortcut = key.map { KeyShortcut($0, modifiers) }
            }
            entries[id] = (name, shortcut, enabled)
        }
        var result: [KeyShortcut: String] = [:]
        for entry in entries.values where entry.enabled {
            if let shortcut = entry.shortcut, result[shortcut] == nil { result[shortcut] = entry.name }
        }
        return result
    }
}
