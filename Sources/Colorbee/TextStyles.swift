import AppKit
import ColorbeeCore
import Observation
import SwiftUI

/// A saved look for text (FR-6.2): font, size, formatting, background, and the colors.
struct SavedTextStyle: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var style: TextStyle
    /// Color 1 (the text) and Color 2 (the opaque background), packed RGBA.
    var textColor: UInt32
    var backgroundColor: UInt32

    static func pack(_ pixel: Pixel) -> UInt32 { UInt32(pixel.r) << 24 | UInt32(pixel.g) << 16 | UInt32(pixel.b) << 8 | UInt32(pixel.a) }
    static func unpack(_ value: UInt32) -> Pixel { Pixel(r: UInt8(value >> 24 & 0xFF), g: UInt8(value >> 16 & 0xFF), b: UInt8(value >> 8 & 0xFF), a: UInt8(value & 0xFF)) }
}

/// Text styles, shared by every window and kept between launches.
@MainActor
@Observable
final class TextStyleStore {
    static let shared = TextStyleStore()
    private static let key = "TextStyles"

    private(set) var styles: [SavedTextStyle] = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key), let stored = try? JSONDecoder().decode([SavedTextStyle].self, from: data) {
            styles = stored
        }
    }

    /// Saves the editor's current text settings and colors; a style with the same name is replaced.
    func save(_ name: String, from editor: Editor) {
        let style = SavedTextStyle(name: name, style: editor.textStyle, textColor: SavedTextStyle.pack(editor.color1), backgroundColor: SavedTextStyle.pack(editor.color2))
        if let index = styles.firstIndex(where: { $0.name == name }) {
            styles[index] = SavedTextStyle(id: styles[index].id, name: name, style: style.style, textColor: style.textColor, backgroundColor: style.backgroundColor)
        } else {
            styles.append(style)
        }
        persist()
    }

    func rename(_ style: SavedTextStyle, to name: String) {
        guard let index = styles.firstIndex(of: style) else { return }
        styles[index].name = name
        persist()
    }

    func delete(_ style: SavedTextStyle) {
        styles.removeAll { $0.id == style.id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(styles) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

extension Editor {
    /// Applies a saved style: the text settings, Color 1, and Color 2 when the style has an opaque background.
    func apply(_ saved: SavedTextStyle) {
        textStyle = saved.style
        color1 = SavedTextStyle.unpack(saved.textColor)
        if saved.style.opaqueBackground { color2 = SavedTextStyle.unpack(saved.backgroundColor) }
    }
}

/// The Styles menu in the text tool's settings (FR-6.2).
struct TextStyleMenu: View {
    let editor: Editor
    let store: TextStyleStore

    var body: some View {
        Menu("Styles") {
            if store.styles.isEmpty {
                Text("No saved styles yet")
            }
            ForEach(store.styles) { style in
                Button(style.name) { editor.apply(style) }
            }
            Divider()
            Button("Save Current Style…") {
                if let name = askForName("Save Text Style", message: "Saves the font, size, formatting, background and colors.", defaultName: "Heading") {
                    store.save(name, from: editor)
                }
            }
            if !store.styles.isEmpty {
                Menu("Rename") {
                    ForEach(store.styles) { style in
                        Button(style.name) {
                            if let name = askForName("Rename Text Style", defaultName: style.name, confirm: "Rename") { store.rename(style, to: name) }
                        }
                    }
                }
                Menu("Delete") {
                    ForEach(store.styles) { style in
                        Button(style.name) { store.delete(style) }
                    }
                }
            }
        }
        .fixedSize()
        .help("Text styles: apply a saved look, or save the current one")
    }
}
