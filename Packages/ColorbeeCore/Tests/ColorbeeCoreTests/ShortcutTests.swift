import Foundation
import Testing
@testable import ColorbeeCore

struct ShortcutTests {
    private func book() -> ShortcutBook {
        ShortcutBook(commands: [
            ShortcutCommand(id: "undo", title: "Undo", group: "Edit", kind: .menu, defaultShortcut: KeyShortcut("z", .command)),
            ShortcutCommand(id: "copy", title: "Copy", group: "Edit", kind: .menu, defaultShortcut: KeyShortcut("c", .command)),
            ShortcutCommand(id: "merge", title: "Merge Down", group: "Layer", kind: .menu, defaultShortcut: KeyShortcut("e", [.command, .shift])),
            ShortcutCommand(id: "flatten", title: "Flatten", group: "Layer", kind: .menu, defaultShortcut: nil),
            ShortcutCommand(id: "quit", title: "Quit", group: "Colorbee", kind: .menu, defaultShortcut: KeyShortcut("q", .command), isEditable: false),
            ShortcutCommand(id: "pencil", title: "Pencil", group: "Tools", kind: .canvas, defaultShortcut: KeyShortcut("p")),
            ShortcutCommand(id: "brush", title: "Brush", group: "Tools", kind: .canvas, defaultShortcut: KeyShortcut("b")),
        ])
    }

    @Test func displaysLikeMacOS() {
        #expect(KeyShortcut("e", [.command, .option, .shift]).display == "⌥⇧⌘E")
        #expect(KeyShortcut("delete", .command).display == "⌘⌫")
        #expect(KeyShortcut("[").display == "[")
    }

    @Test func menuCommandsNeedCommandOrControl() {
        let book = book()
        #expect(book.check(KeyShortcut("f"), for: "flatten") == .needsCommandOrControl)
        #expect(book.check(KeyShortcut("f", .shift), for: "flatten") == .needsCommandOrControl)
        #expect(book.check(KeyShortcut("f", [.control, .option]), for: "flatten") == .allowed)
    }

    @Test func canvasKeysAreOneKeyOrShiftPlusOne() {
        let book = book()
        #expect(book.check(KeyShortcut("k"), for: "pencil") == .allowed)
        #expect(book.check(KeyShortcut("k", .shift), for: "pencil") == .allowed)
        #expect(book.check(KeyShortcut("k", .command), for: "pencil") == .canvasKeysCantUseModifiers)
    }

    @Test func macOSShortcutsAreBlockedAndNamed() {
        let book = book()
        #expect(book.check(KeyShortcut("h", .command), for: "flatten") == .reserved(owner: "macOS to Hide Colorbee"))
        let system = [KeyShortcut("up", .control): "macOS for Mission Control"]
        #expect(book.check(KeyShortcut("up", .control), for: "flatten", system: system) == .reserved(owner: "macOS for Mission Control"))
        #expect(book.check(KeyShortcut("r", .command), for: "quit") == .cantBeChanged)
    }

    @Test func aShortcutInUseOffersToReassign() {
        var book = book()
        guard case .usedBy(let other) = book.check(KeyShortcut("e", [.command, .shift]), for: "flatten") else {
            Issue.record("Expected a conflict")
            return
        }
        #expect(other.id == "merge")
        book.assign(KeyShortcut("e", [.command, .shift]), to: "flatten")
        #expect(book.shortcut(for: "flatten") == KeyShortcut("e", [.command, .shift]))
        #expect(book.shortcut(for: "merge") == nil)
        #expect(book.command(for: KeyShortcut("e", [.command, .shift]), kind: .menu)?.id == "flatten")
    }

    @Test func standardShortcutsAskFirst() {
        let book = book()
        #expect(book.check(KeyShortcut("y", .command), for: "undo") == .givesUpStandard(name: "Undo", standard: KeyShortcut("z", .command), alsoTakenFrom: nil))
        #expect(book.check(KeyShortcut("c", .command), for: "flatten") == .takesStandard(name: "Copy"))
    }

    /// Review J, finding 5: moving a standard command onto a key in use names both the standard key given up and
    /// the command losing its key.
    @Test func movingAStandardCommandOntoAUsedKeyNamesBoth() throws {
        let book = book()
        let merge = try #require(book.command(withID: "merge"))
        #expect(book.check(KeyShortcut("e", [.command, .shift]), for: "undo")
                == .givesUpStandard(name: "Undo", standard: KeyShortcut("z", .command), alsoTakenFrom: merge))
        #expect(book.check(KeyShortcut("c", .command), for: "undo") == .takesStandard(name: "Copy"))
    }

    /// Review J, findings 9 and 10: keys the canvas keeps, and macOS's tab shortcuts, can't be assigned.
    @Test func canvasKeysAndTabShortcutsAreRefused() {
        let book = book()
        for key in ["space", "left", "right", "up", "down", "return", "escape", "delete"] {
            #expect(book.check(KeyShortcut(key), for: "pencil") == .keptByCanvas, "\(key)")
        }
        #expect(book.check(KeyShortcut("left", .command), for: "flatten") == .keptByCanvas)
        #expect(book.check(KeyShortcut("tab", .control), for: "flatten") == .reserved(owner: "macOS to show the next tab"))
        #expect(book.check(KeyShortcut("\\", [.command, .shift]), for: "flatten") == .reserved(owner: "macOS to show all tabs"))
    }

    /// Review J, finding 13: an imported file can't set up a clash quietly, and keys are normalized.
    @Test func importingReportsWhatItCouldntKeep() throws {
        var book = book()
        let file = Data(#"{"version":1,"shortcuts":{"copy":{"key":"K","modifiers":8},"flatten":{"key":"k","modifiers":8},"pencil":{"key":"space","modifiers":0}}}"#.utf8)
        let problems = try book.importChanges(from: file)
        #expect(book.shortcut(for: "flatten") == KeyShortcut("k", .command) || book.shortcut(for: "copy") == KeyShortcut("k", .command))
        #expect(problems.count == 2, "\(problems)")
    }

    @Test func resettingAndClearing() {
        var book = book()
        book.assign(KeyShortcut("k"), to: "pencil")
        book.assign(nil, to: "brush")
        #expect(book.isChanged("pencil") && book.isChanged("brush"))
        #expect(book.shortcut(for: "brush") == nil)
        book.reset("pencil")
        #expect(book.shortcut(for: "pencil") == KeyShortcut("p"))
        #expect(!book.isChanged("pencil"))
        book.resetAll()
        #expect(book.shortcut(for: "brush") == KeyShortcut("b"))
    }

    @Test func resettingDoesntStealADefaultAnotherCommandTook() {
        var book = book()
        book.assign(KeyShortcut("p"), to: "brush")
        #expect(book.shortcut(for: "pencil") == nil)
        book.reset("pencil")
        #expect(book.shortcut(for: "brush") == KeyShortcut("p"))
        #expect(book.shortcut(for: "pencil") == nil)
    }

    @Test func exportAndImportRoundTrip() throws {
        var book = book()
        book.assign(KeyShortcut("k"), to: "pencil")
        book.assign(nil, to: "brush")
        book.assign(KeyShortcut("f", [.command, .option]), to: "flatten")
        let data = try book.exported()
        var other = self.book()
        try other.importChanges(from: data)
        #expect(other.shortcut(for: "pencil") == KeyShortcut("k"))
        #expect(other.shortcut(for: "brush") == nil)
        #expect(other.shortcut(for: "flatten") == KeyShortcut("f", [.command, .option]))
        // A shortcut that's reserved on this Mac is skipped on import.
        var strict = self.book()
        try strict.importChanges(from: data, system: [KeyShortcut("f", [.command, .option]): "macOS for something"])
        #expect(strict.shortcut(for: "flatten") == nil)
    }
}
