import AppKit
import ColorbeeCore
import Observation
import SwiftUI

/// The Export As presets, editable in Settings and kept between launches (FR-11.2).
@MainActor
@Observable
final class ExportPresetStore {
    static let shared = ExportPresetStore()
    private static let key = "ExportPresets"

    struct Stored: Codable, Identifiable, Equatable {
        var id = UUID()
        var name: String
        /// Scale to this width, or (when `square`) fit inside a square of this side.
        var pixels: Int
        var square: Bool

        var preset: ExportPreset { ExportPreset(name: name, size: square ? .fitSquare(pixels) : .width(pixels)) }

        init(name: String, pixels: Int, square: Bool) {
            self.name = name
            self.pixels = pixels
            self.square = square
        }

        init(_ preset: ExportPreset) {
            switch preset.size {
            case .width(let width): self.init(name: preset.name, pixels: width, square: false)
            case .fitSquare(let side): self.init(name: preset.name, pixels: side, square: true)
            }
        }
    }

    var items: [Stored] {
        didSet { persist() }
    }

    var presets: [ExportPreset] { items.filter { $0.pixels > 0 && !$0.name.isEmpty }.map(\.preset) }

    /// How presets scale (FR-11.2): nil picks by size (sharp pixels for small pixel art, smooth otherwise).
    var scaling: Resampling? {
        didSet { UserDefaults.standard.set(scaling.map { $0 == .smooth ? "smooth" : "sharp" }, forKey: Self.scalingKey) }
    }
    private static let scalingKey = "ExportPresetScaling"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key), let stored = try? JSONDecoder().decode([Stored].self, from: data) {
            items = stored
        } else {
            items = ExportPreset.defaults.map(Stored.init)
        }
        scaling = switch UserDefaults.standard.string(forKey: Self.scalingKey) {
        case "smooth": .smooth
        case "sharp": .nearestNeighbor
        default: nil
        }
    }

    func resetToDefaults() {
        items = ExportPreset.defaults.map(Stored.init)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

/// Colorbee ▸ Settings… (⌘,).
@MainActor
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 560), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Colorbee Settings"
        window.contentView = NSHostingView(rootView: SettingsView())
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

private struct SettingsView: View {
    /// Settings reopens on the tab you last used.
    @AppStorage("SettingsTab") private var tab = "shortcuts"

    var body: some View {
        TabView(selection: $tab) {
            ShortcutSettings(store: ShortcutStore.shared)
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                .tag("shortcuts")
            ExportPresetSettings(store: ExportPresetStore.shared)
                .tabItem { Label("Export Presets", systemImage: "square.and.arrow.up") }
                .tag("exports")
            PDFSettings()
                .tabItem { Label("PDFs", systemImage: "doc.richtext") }
                .tag("pdfs")
        }
        .padding(20)
        .frame(width: 640, height: 560)
    }
}

/// The resolution PDFs open at (FR-11.6). It's read when a PDF opens, so it changes the next one.
private struct PDFSettings: View {
    @AppStorage("PDFResolution") private var resolution = 200.0

    var body: some View {
        Form {
            Picker("Open PDFs at", selection: $resolution) {
                Text("150 DPI · smaller, faster").tag(150.0)
                Text("200 DPI · recommended").tag(200.0)
                Text("300 DPI · sharpest, uses more memory").tag(300.0)
            }
            .pickerStyle(.radioGroup)
            Text("Each PDF page becomes an image at this resolution. A letter page is 1700 × 2200 pixels at 200 DPI. "
                 + "It applies to PDFs opened from now on; open ones keep their resolution, and Export as PDF keeps each page's.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .formStyle(.grouped)
    }
}

private struct ExportPresetSettings: View {
    @Bindable var store: ExportPresetStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("File ▸ Export As saves a PNG at each preset's size. Images are never enlarged.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Picker("Scaling", selection: $store.scaling) {
                Text("Automatic").tag(Resampling?.none)
                Text("Sharp pixels").tag(Resampling?.some(.nearestNeighbor))
                Text("Smooth").tag(Resampling?.some(.smooth))
            }
            .fixedSize()
            .help("Automatic keeps small pixel art sharp and scales everything else smoothly")
            List {
                ForEach($store.items) { $item in
                    HStack {
                        TextField("Name", text: $item.name)
                            .frame(width: 140)
                        Picker("Size", selection: $item.square) {
                            Text("Width").tag(false)
                            Text("Fits square").tag(true)
                        }
                        .labelsHidden()
                        .fixedSize()
                        TextField("Pixels", value: $item.pixels, format: .number)
                            .frame(width: 70)
                            .multilineTextAlignment(.trailing)
                        Text("px")
                        Spacer()
                        Button("Remove", systemImage: "minus.circle") { store.items.removeAll { $0.id == item.id } }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                    }
                }
            }
            HStack {
                Button("Add Preset") { store.items.append(.init(name: "New Preset", pixels: 1080, square: false)) }
                Spacer()
                Button("Reset to Defaults") { store.resetToDefaults() }
            }
        }
    }
}

/// The Services / Quick Actions item "Open in Colorbee" in Finder's right-click menu (FR-14.3).
@MainActor
final class ServicesProvider: NSObject {
    @objc func openInColorbee(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        NSApp.activate()
        for url in urls {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                // A file that can't be opened says why, rather than nothing happening (review J, finding 27).
                if let error { NSApp.presentError(error) }
            }
        }
    }
}
