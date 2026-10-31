import Foundation

/// How Colorbee's settings stores read their saved lists and write their settings (review round 11, AC 1). A list is
/// read entry by entry, so one entry this version can't read (from a newer test build, say) is skipped and the rest
/// are kept, rather than the whole list coming back empty and the next change saving the empty list over it. Nothing
/// is written while testing, so a test can never change Leah's settings.
@MainActor
enum StoredSettings {
    static var canWrite: Bool { !TestHost.isActive }

    /// The entries of the list in `data` that this version can read; nil without data, or if it isn't a list.
    static func list<Element: Decodable>(of type: Element.Type, from data: Data?) -> [Element]? {
        guard let data, let entries = try? JSONDecoder().decode([Readable<Element>].self, from: data) else { return nil }
        return entries.compactMap(\.value)
    }

    static func data(forKey key: String) -> Data? {
        UserDefaults.standard.data(forKey: key)
    }

    static func set(_ value: Any?, forKey key: String) {
        guard canWrite else { return }
        UserDefaults.standard.set(value, forKey: key)
    }

    /// Encodes `value` and saves it under `key`, unless it can't be encoded.
    static func save(_ value: some Encodable, forKey key: String) {
        guard canWrite, let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

/// One entry of a saved list, or nil if this version can't read it.
struct Readable<Element: Decodable>: Decodable {
    let value: Element?
    init(from decoder: Decoder) throws { value = try? Element(from: decoder) }
}
