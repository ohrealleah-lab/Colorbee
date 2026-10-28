import ColorbeeCore
import Foundation
import Observation

/// Adjust Photo settings to use again (FR-9.7 item 4): the last ones applied, kept across a relaunch, and the ones
/// copied with Copy Photo Settings, kept until Colorbee quits. Neither touches the Mac's clipboard, so a copied image
/// stays there.
@MainActor
@Observable
final class PhotoSettingsStore {
    static let shared = PhotoSettingsStore()

    /// The settings last applied anywhere: Apply, As Adjustment Layer or Paste as Adjustment Layer (Leah, 2026-10-27).
    var last: PhotoEdit? {
        didSet { persist() }
    }
    var copied: PhotoEdit?

    /// Nil while testing: the last settings then live only in memory.
    private let file = SettingsFolder.current?.appending(path: "Last Photo Settings.json")

    private init() {
        if let file, let data = try? Data(contentsOf: file) {
            last = try? JSONDecoder().decode(PhotoEdit.self, from: data)
        }
    }

    private func persist() {
        guard let file else { return }
        guard let last, let data = try? JSONEncoder().encode(last) else {
            try? FileManager.default.removeItem(at: file)
            return
        }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
