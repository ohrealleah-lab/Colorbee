import AppKit
import ColorbeeCore
import Observation
import UniformTypeIdentifiers

extension UTType {
    static let colorbeeFilter = UTType(exportedAs: "com.leah.colorbee.colorbeefilter")
}

/// The photo filters (FR-9.5): the nine built in, then yours, kept in Application Support and shared by every window.
@MainActor
@Observable
final class FilterStore {
    static let shared = FilterStore()

    /// Filters you saved or imported, in the order you made them.
    private(set) var custom: [PhotoFilter] = []

    private let file = URL.applicationSupportDirectory.appending(path: "Colorbee/Filters.json")

    private init() {
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([PhotoFilter].self, from: data) {
            custom = saved.map { PhotoFilter(name: $0.name, steps: $0.steps) }
        }
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

    @discardableResult
    func importFilter(from url: URL) throws -> String {
        add(try PhotoFilter.imported(from: Data(contentsOf: url)))
    }

    private func persist() {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(custom).write(to: file, options: .atomic)
    }
}
