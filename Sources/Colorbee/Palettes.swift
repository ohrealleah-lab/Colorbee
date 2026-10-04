import AppKit
import ColorbeeCore
import Observation
import UniformTypeIdentifiers

extension UTType {
    static let colorbeePalette = UTType(exportedAs: "com.leah.colorbee.colorpalette")
}

/// A named set of colors (FR-15.1): the 28 swatches (sRGB, 0xRRGGBB) and the 12 custom slots.
struct Palette: Codable, Equatable {
    var name: String
    var swatches: [UInt32]
    /// Packed RGBA, -1 for an empty slot (see `CustomColors.packed`).
    var custom: [Int]

    static let classic = Palette(
        name: "Paint Classic",
        swatches: [
            0x000000, 0x808080, 0x800000, 0x808000, 0x008000, 0x008080, 0x000080, 0x800080, 0x808040, 0x004040, 0x0080FF, 0x004080, 0x8000FF, 0x804000,
            0xFFFFFF, 0xC0C0C0, 0xFF0000, 0xFFFF00, 0x00FF00, 0x00FFFF, 0x0000FF, 0xFF00FF, 0xFFFF80, 0x00FF80, 0x80FFFF, 0x8080FF, 0xFF0080, 0xFF8040,
        ],
        custom: Array(repeating: -1, count: 12)
    )
}

/// Saved palettes and the one in use, shared by every window and kept between launches.
@MainActor
@Observable
final class PaletteStore {
    static let shared = PaletteStore()
    private static let key = "Palettes"

    private struct Stored: Codable {
        var saved: [Palette]
        var activeName: String
        var swatches: [UInt32]
    }

    /// Palettes you saved or imported. Paint Classic is built in and always available.
    private(set) var saved: [Palette] = []
    private(set) var activeName = Palette.classic.name
    private(set) var swatches = Palette.classic.swatches

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key), let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            saved = stored.saved
            activeName = stored.activeName
            if stored.swatches.count == 28 { swatches = stored.swatches }
        }
    }

    var all: [Palette] { [Palette.classic] + saved }

    func load(_ palette: Palette) {
        swatches = palette.swatches.count == 28 ? palette.swatches : Palette.classic.swatches
        CustomColors.shared.replace(with: palette.custom)
        activeName = palette.name
        persist()
    }

    /// Saves the current swatches and custom colors under `name`, replacing a saved palette of that name.
    func saveCurrent(as name: String) {
        // A built-in palette's name gets a number, like an import, so it doesn't make a second one that can't be
        // renamed or deleted (review J, finding 23).
        var name = name
        if name == Palette.classic.name {
            let base = name
            var number = 2
            while all.contains(where: { $0.name == name }) {
                name = "\(base) \(number)"
                number += 1
            }
        }
        let palette = Palette(name: name, swatches: swatches, custom: CustomColors.shared.packed)
        if let index = saved.firstIndex(where: { $0.name == name }) { saved[index] = palette } else { saved.append(palette) }
        activeName = name
        persist()
    }

    func rename(_ name: String, to newName: String) {
        guard let index = saved.firstIndex(where: { $0.name == name }), !all.contains(where: { $0.name == newName }) else { return }
        saved[index].name = newName
        if activeName == name { activeName = newName }
        persist()
    }

    func delete(_ name: String) {
        saved.removeAll { $0.name == name }
        // The palette in use goes back to Paint Classic's colors too, not just its name (review J, finding 24).
        if activeName == name { load(Palette.classic) } else { persist() }
    }

    func resetToClassic() {
        load(Palette.classic)
    }

    func export(_ palette: Palette, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(palette).write(to: url, options: .atomic)
    }

    /// Adds a palette from a file (renamed if the name is taken) and switches to it.
    func importPalette(from url: URL) throws {
        var palette = try JSONDecoder().decode(Palette.self, from: Data(contentsOf: url))
        guard palette.swatches.count == 28 else { throw CocoaError(.fileReadCorruptFile) }
        let base = palette.name
        var number = 2
        while all.contains(where: { $0.name == palette.name }) {
            palette.name = "\(base) \(number)"
            number += 1
        }
        saved.append(palette)
        load(palette)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(Stored(saved: saved, activeName: activeName, swatches: swatches)) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

/// Asks for a name in a small dialog; nil if cancelled or left empty.
@MainActor
func askForName(_ title: String, message: String = "", defaultName: String = "", confirm: String = "Save") -> String? {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
    field.stringValue = defaultName
    alert.accessoryView = field
    alert.addButton(withTitle: confirm)
    alert.addButton(withTitle: "Cancel")
    alert.window.initialFirstResponder = field
    guard alert.runModal() == .alertFirstButtonReturn else { return nil }
    let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? nil : name
}
