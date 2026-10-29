import AppKit
import ColorbeeCore
import Observation
import UniformTypeIdentifiers

extension UTType {
    static let colorbeeFilter = UTType(exportedAs: "com.leah.colorbee.colorbeefilter")
    /// A color look (FR-9.7 item 4). Colorbee doesn't claim .cube files, so they're imported only from the filter
    /// menu (Q11.1).
    static let cubeLook = UTType(filenameExtension: "cube") ?? .data
}

/// The photo filters (FR-9.5): the nine built in, then yours, kept in Application Support and shared by every window.
@MainActor
@Observable
final class FilterStore {
    static let shared = FilterStore()

    /// Filters you saved or imported, in the order you made them.
    private(set) var custom: [PhotoFilter] = []

    private static let fileName = "Photo Filters.json"
    /// Where beta 7 and earlier keep their filters. They can't read newer filters, and saving would write an empty
    /// list over them, so filters moved to `fileName` (stage 1a). This one is read once, never written.
    private static let olderFile = SettingsFolder.everyday.appending(path: "Filters.json")

    /// Nil while testing: filters then live only in memory.
    private let file = SettingsFolder.current?.appending(path: FilterStore.fileName)

    private init() {
        guard let file else { return }
        Self.copyOnce(to: file)
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([Readable].self, from: data) {
            custom = saved.compactMap(\.filter).map { PhotoFilter(name: $0.name, steps: $0.steps) }
        }
    }

    /// The first time `file` is needed, it starts as a copy of the newest filters there are: the everyday copy's, or
    /// an older version's.
    private static func copyOnce(to file: URL) {
        let manager = FileManager.default
        guard !manager.fileExists(atPath: file.path) else { return }
        let everyday = SettingsFolder.everyday.appending(path: fileName)
        guard let source = [everyday, olderFile].first(where: { $0 != file && manager.fileExists(atPath: $0.path) }) else { return }
        try? manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? manager.copyItem(at: source, to: file)
    }

    /// One filter, or none if this version can't read it, so the others are still kept.
    private struct Readable: Decodable {
        let filter: PhotoFilter?
        init(from decoder: Decoder) throws { filter = try? PhotoFilter(from: decoder) }
    }

    var all: [PhotoFilter] { PhotoFilter.builtIn + custom }

    func filter(named name: String) -> PhotoFilter? {
        all.first { $0.name == name }
    }

    /// Adds `filter`, numbering its name if it's taken. Returns the name it was saved under.
    @discardableResult
    func add(_ filter: PhotoFilter) -> String {
        var filter = PhotoFilter(name: filter.name, steps: filter.steps)
        let base = filter.name
        var number = 2
        while all.contains(where: { $0.name == filter.name }) {
            filter.name = "\(base) \(number)"
            number += 1
        }
        custom.append(filter)
        persist()
        return filter.name
    }

    @discardableResult
    func rename(_ name: String, to newName: String) -> Bool {
        guard let index = custom.firstIndex(where: { $0.name == name }), !all.contains(where: { $0.name == newName }) else { return false }
        custom[index].name = newName
        persist()
        return true
    }

    func delete(_ name: String) {
        custom.removeAll { $0.name == name }
        persist()
    }

    func export(_ filter: PhotoFilter, to url: URL) throws {
        try filter.exported().write(to: url, options: .atomic)
    }

    /// Adds the filter in a .colorbeefilter, or a .cube look as a filter of its own. Returns the name it was saved under.
    /// The file is read in the background: a big look is tens of megabytes (review V, finding 3).
    @discardableResult
    func importFilter(from url: URL) async throws -> String {
        add(try await Task.detached(priority: .userInitiated) { try Self.read(url) }.value)
    }

    private nonisolated static func read(_ url: URL) throws -> PhotoFilter {
        let data = try Data(contentsOf: url)
        guard url.pathExtension.lowercased() == "cube" else { return try PhotoFilter.imported(from: data) }
        let (name, look) = try CubeFile.read(data, fallbackName: url.deletingPathExtension().lastPathComponent)
        return PhotoFilter(name: name, steps: [.look(look)])
    }

    /// Writes in order, in the background: with looks the list can be many megabytes.
    private static let writer = DispatchQueue(label: "com.leah.Colorbee.filters", qos: .utility)

    private func persist() {
        guard let file else { return }
        let filters = custom
        Self.writer.async {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try? encoder.encode(filters).write(to: file, options: .atomic)
        }
    }
}
