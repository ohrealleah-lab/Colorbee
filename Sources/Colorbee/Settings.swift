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

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key), let stored = try? JSONDecoder().decode([Stored].self, from: data) {
            items = stored
        } else {
            items = ExportPreset.defaults.map(Stored.init)
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
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 380), styleMask: [.titled, .closable], backing: .buffered, defer: false)
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
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            ExportPresetSettings(store: ExportPresetStore.shared)
                .tabItem { Label("Export Presets", systemImage: "square.and.arrow.up") }
        }
        .padding(20)
        .frame(width: 520, height: 380)
    }
}

private struct GeneralSettings: View {
    @State private var watcher = ScreenshotWatcher.shared

    var body: some View {
        Form {
            Toggle("Open new screenshots in Colorbee", isOn: Binding(get: { watcher.isEnabled }, set: { watcher.isEnabled = $0 }))
            Text("Colorbee watches \(watcher.folder.path(percentEncoded: false)), where macOS saves screenshots, and opens each new one. The first time, macOS asks to let Colorbee see that folder.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Screenshots copied straight to the clipboard (⌃⇧⌘4) can't be caught; paste them with ⌘V and they appear in Clipboard History.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ExportPresetSettings: View {
    @Bindable var store: ExportPresetStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("File ▸ Export As saves a PNG at each preset's size. Images are never enlarged.")
                .font(.callout)
                .foregroundStyle(.secondary)
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

/// Opens new screenshots as they appear (FR-14.4). Off by default.
@MainActor
@Observable
final class ScreenshotWatcher {
    static let shared = ScreenshotWatcher()
    private static let key = "OpenNewScreenshots"

    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.key)
            isEnabled ? start() : stop()
        }
    }

    /// Where macOS saves screenshots: the location set in the Screenshot app, or the Desktop.
    var folder: URL {
        if let location = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") {
            return URL(fileURLWithPath: (location as NSString).expandingTildeInPath, isDirectory: true)
        }
        return URL.desktopDirectory
    }

    @ObservationIgnored private var source: DispatchSourceFileSystemObject?
    @ObservationIgnored private var seen: Set<String> = []
    @ObservationIgnored private var since = Date.now

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.key)
    }

    /// Starts watching if the setting is on; called at launch.
    func resume() {
        if isEnabled { start() }
    }

    private func start() {
        stop()
        since = .now
        seen = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.folderChanged() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    private func stop() {
        source?.cancel()
        source = nil
    }

    /// macOS writes a hidden temporary file first, then renames it; only new, visible images count.
    private func folderChanged() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in names where !seen.contains(name) && !name.hasPrefix(".") {
            seen.insert(name)
            let url = folder.appending(path: name)
            guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType, type.conforms(to: .image),
                  let created = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate, created >= since else { continue }
            // Give macOS a moment to finish writing the file.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
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
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
        }
    }
}
