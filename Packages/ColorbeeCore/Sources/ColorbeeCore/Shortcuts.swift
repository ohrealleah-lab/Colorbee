import Foundation

/// A key and its modifiers (FR-15.3). `key` is the unshifted character, lowercased ("z", "[", "1"),
/// or a named key ("space", "tab", "escape", "delete", "forwardDelete", "return", "left", "right",
/// "up", "down", "f1"…"f20").
public struct KeyShortcut: Hashable, Codable, Sendable {
    public struct Modifiers: OptionSet, Hashable, Codable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    public var key: String
    public var modifiers: Modifiers

    public init(_ key: String, _ modifiers: Modifiers = []) {
        self.key = key.count == 1 ? key.lowercased() : key
        self.modifiers = modifiers
    }

    private enum CodingKeys: String, CodingKey { case key, modifiers }

    /// Through `init`, so a hand-edited "Z" is the same key as "z" (review J, finding 13).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(try container.decode(String.self, forKey: .key), try container.decode(Modifiers.self, forKey: .modifiers))
    }

    /// As macOS writes shortcuts: ⌃⌥⇧⌘ then the key.
    public var display: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        let names = ["space": "Space", "tab": "⇥", "escape": "⎋", "delete": "⌫", "forwardDelete": "⌦", "return": "↩",
                     "left": "←", "right": "→", "up": "↑", "down": "↓"]
        return text + (names[key] ?? key.uppercased())
    }
}

/// Something a shortcut can trigger: a menu command, or a key that works on the canvas (a tool, X, D, [ ]).
public struct ShortcutCommand: Hashable, Sendable {
    public enum Kind: Sendable {
        /// Needs ⌘ or ⌃.
        case menu
        /// A single key or Shift + a key; never active while typing text.
        case canvas
    }

    public let id: String
    public let title: String
    /// The menu it's in, for grouping ("Edit", "Tools"…).
    public let group: String
    public let kind: Kind
    public let defaultShortcut: KeyShortcut?
    /// The Mac's own app and window commands (Quit, Hide, Close…) are shown but can't be changed.
    public let isEditable: Bool

    public init(id: String, title: String, group: String, kind: Kind, defaultShortcut: KeyShortcut?, isEditable: Bool = true) {
        self.id = id
        self.title = title
        self.group = group
        self.kind = kind
        self.defaultShortcut = defaultShortcut
        self.isEditable = isEditable
    }
}

/// Every command's shortcut: the defaults, with your changes on top (FR-15.3).
public struct ShortcutBook: Sendable {
    public private(set) var commands: [ShortcutCommand]
    /// Changed shortcuts by command id. A nil value means the shortcut was cleared.
    public private(set) var overrides: [String: KeyShortcut?] = [:]

    /// Shortcuts every Mac app is expected to keep; changing them asks first.
    public static let standard: [KeyShortcut: String] = [
        KeyShortcut("z", .command): "Undo", KeyShortcut("x", .command): "Cut", KeyShortcut("c", .command): "Copy",
        KeyShortcut("v", .command): "Paste", KeyShortcut("a", .command): "Select All", KeyShortcut("s", .command): "Save",
    ]

    /// Shortcuts that belong to macOS or to standard Mac app behavior, with who owns them.
    /// The shortcuts set in System Settings are added by the app, which reads them from this Mac.
    public static let reservedByMac: [KeyShortcut: String] = [
        KeyShortcut("q", .command): "macOS to Quit Colorbee",
        KeyShortcut("h", .command): "macOS to Hide Colorbee",
        KeyShortcut("h", [.command, .option]): "macOS to Hide Others",
        KeyShortcut(",", .command): "macOS to open Settings",
        KeyShortcut("escape", [.command, .option]): "macOS to Force Quit",
        KeyShortcut("w", .command): "macOS to Close the window",
        KeyShortcut("m", .command): "macOS to Minimize the window",
        KeyShortcut("m", [.command, .option]): "macOS to Minimize all windows",
        KeyShortcut("`", .command): "macOS to cycle through windows",
        KeyShortcut("f", [.command, .control]): "macOS to enter Full Screen",
        KeyShortcut("/", [.command, .shift]): "macOS to search the Help menu",
        KeyShortcut("space", [.command, .control]): "macOS for Emoji & Symbols",
        KeyShortcut("tab", .command): "macOS to switch apps",
        KeyShortcut("space", .command): "macOS for Spotlight",
        KeyShortcut("3", [.command, .shift]): "macOS for screenshots",
        KeyShortcut("4", [.command, .shift]): "macOS for screenshots",
        KeyShortcut("5", [.command, .shift]): "macOS for screenshots",
        KeyShortcut("q", [.command, .control]): "macOS to Lock Screen",
        // Window tabs (review J, finding 10).
        KeyShortcut("\\", [.command, .shift]): "macOS to show all tabs",
        KeyShortcut("tab", .control): "macOS to show the next tab",
        KeyShortcut("tab", [.control, .shift]): "macOS to show the previous tab",
    ]

    /// Keys the canvas handles itself, before any shortcut (§23, stage 7c; review J, finding 9): Space pans, the
    /// arrows nudge, Return and Esc place, Delete deletes, and ⌘- or ⇧⌘-arrows resize a selection (FR-3.3).
    static func isKeptByCanvas(_ shortcut: KeyShortcut, kind: ShortcutCommand.Kind) -> Bool {
        let arrows = ["left", "right", "up", "down"]
        switch kind {
        case .canvas: return arrows.contains(shortcut.key) || ["space", "return", "escape", "delete", "forwardDelete"].contains(shortcut.key)
        case .menu: return arrows.contains(shortcut.key) && shortcut.modifiers.isSubset(of: [.command, .shift])
        }
    }

    public init(commands: [ShortcutCommand]) {
        self.commands = commands
    }

    public func command(withID id: String) -> ShortcutCommand? {
        commands.first { $0.id == id }
    }

    public func shortcut(for id: String) -> KeyShortcut? {
        if let override = overrides[id] { return override }
        return command(withID: id)?.defaultShortcut
    }

    public func isChanged(_ id: String) -> Bool {
        overrides[id] != nil
    }

    /// The command a shortcut triggers, among commands of one kind.
    public func command(for shortcut: KeyShortcut, kind: ShortcutCommand.Kind) -> ShortcutCommand? {
        commands.first { $0.kind == kind && self.shortcut(for: $0.id) == shortcut }
    }

    public enum Check: Equatable, Sendable {
        case allowed
        /// Menu commands need ⌘ or ⌃.
        case needsCommandOrControl
        /// Canvas keys are one key, or Shift + one key.
        case canvasKeysCantUseModifiers
        case cantBeChanged
        /// Belongs to macOS; the text names the owner ("macOS to Hide Colorbee").
        case reserved(owner: String)
        /// Already another Colorbee command's; can be reassigned.
        case usedBy(ShortcutCommand)
        /// The canvas uses this key itself, so the command would never get it.
        case keptByCanvas
        /// The command gives up its standard key (⌘Z/X/C/V/A/S) for this one, which `alsoTakenFrom` loses if
        /// set. Asks first (review J, finding 5).
        case givesUpStandard(name: String, standard: KeyShortcut, alsoTakenFrom: ShortcutCommand?)
        /// The key is the standard one for `name`, which would lose it. Asks first.
        case takesStandard(name: String)
    }

    /// What happens if `shortcut` is given to the command `id`. `system` holds the shortcuts set in
    /// System Settings on this Mac, with who owns them. Standard-shortcut and reassign checks come last,
    /// since those can be confirmed.
    public func check(_ shortcut: KeyShortcut, for id: String, system: [KeyShortcut: String] = [:]) -> Check {
        guard let command = command(withID: id), command.isEditable else { return .cantBeChanged }
        switch command.kind {
        case .menu:
            guard shortcut.modifiers.contains(.command) || shortcut.modifiers.contains(.control) else { return .needsCommandOrControl }
        case .canvas:
            guard shortcut.modifiers.subtracting(.shift).isEmpty else { return .canvasKeysCantUseModifiers }
        }
        if let owner = Self.reservedByMac[shortcut] ?? system[shortcut] { return .reserved(owner: owner) }
        if Self.isKeptByCanvas(shortcut, kind: command.kind) { return .keptByCanvas }
        if let current = self.shortcut(for: id), current == shortcut { return .allowed }
        let other = commands.first { $0.id != id && self.shortcut(for: $0.id) == shortcut }
        // Taking ⌘C (say) from Copy asks with the stronger warning.
        if let other, let name = Self.standard[shortcut], other.defaultShortcut == shortcut { return .takesStandard(name: name) }
        if let current = self.shortcut(for: id), let name = Self.standard[current], command.defaultShortcut == current {
            return .givesUpStandard(name: name, standard: current, alsoTakenFrom: other)
        }
        if let other { return .usedBy(other) }
        return .allowed
    }

    /// Gives `shortcut` to the command `id` (nil clears it). Any other command using it loses it.
    public mutating func assign(_ shortcut: KeyShortcut?, to id: String) {
        if let shortcut {
            for other in commands where other.id != id && self.shortcut(for: other.id) == shortcut {
                setOverride(nil, for: other.id)
            }
        }
        setOverride(shortcut, for: id)
    }

    public mutating func reset(_ id: String) {
        overrides[id] = nil
        // A reset can bring back a default another command took over; that command keeps it and this one goes without.
        if let restored = command(withID: id)?.defaultShortcut,
           commands.contains(where: { $0.id != id && shortcut(for: $0.id) == restored }) {
            overrides[id] = .some(nil)
        }
    }

    public mutating func resetAll() {
        overrides = [:]
    }

    private mutating func setOverride(_ shortcut: KeyShortcut?, for id: String) {
        if shortcut == command(withID: id)?.defaultShortcut {
            overrides[id] = nil
        } else {
            overrides[id] = .some(shortcut)
        }
    }

    // MARK: Saving (.colorbeekeys)

    private struct Stored: Codable {
        var version = 1
        /// Command id to shortcut; a missing shortcut means cleared.
        var shortcuts: [String: KeyShortcut?]
    }

    public func exported() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Stored(shortcuts: overrides))
    }

    /// Replaces your changes with those in `data`. Unknown commands, and shortcuts that are now reserved
    /// or break the rules, are skipped. Returns what couldn't be kept, to tell the person (review J, finding 13).
    @discardableResult
    public mutating func importChanges(from data: Data, system: [KeyShortcut: String] = [:]) throws -> [String] {
        let stored = try JSONDecoder().decode(Stored.self, from: data)
        overrides = [:]
        var problems: [String] = []
        var givenByFile: [KeyShortcut: String] = [:]
        for (id, shortcut) in stored.shortcuts.sorted(by: { $0.key < $1.key }) {
            guard let command = command(withID: id), command.isEditable else { continue }
            guard let shortcut else {
                assign(nil, to: id)
                continue
            }
            switch check(shortcut, for: id, system: system) {
            case .allowed, .usedBy, .givesUpStandard, .takesStandard:
                if let earlier = givenByFile[shortcut], let earlierCommand = self.command(withID: earlier) {
                    problems.append("\(earlierCommand.title) lost \(shortcut.display), which the file also gives \(command.title).")
                }
                givenByFile[shortcut] = id
                assign(shortcut, to: id)
            default:
                problems.append("\(command.title) kept its shortcut: \(shortcut.display) can't be used.")
            }
        }
        return problems
    }
}
