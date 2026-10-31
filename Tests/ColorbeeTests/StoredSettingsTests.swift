import ColorbeeCore
import Foundation
import Testing
@testable import Colorbee

/// The settings stores' shared reading and writing (review round 11, AC 1).
@MainActor
struct StoredSettingsTests {
    private struct Entry: Codable, Equatable {
        var name: String
        var size: Int
    }

    @Test func anEntryThisVersionCantReadIsSkippedAndTheRestKept() {
        let data = Data(#"[{"name":"A","size":1},{"name":"B","size":"big"},{"name":"C","size":3},{"other":true}]"#.utf8)
        #expect(StoredSettings.list(of: Entry.self, from: data) == [Entry(name: "A", size: 1), Entry(name: "C", size: 3)])
    }

    @Test func noDataOrNoListReadsAsNothingSaved() {
        #expect(StoredSettings.list(of: Entry.self, from: nil) == nil)
        #expect(StoredSettings.list(of: Entry.self, from: Data(#"{"name":"A","size":1}"#.utf8)) == nil)
        #expect(StoredSettings.list(of: Entry.self, from: Data("not JSON".utf8)) == nil)
        #expect(StoredSettings.list(of: Entry.self, from: Data("[]".utf8)) == [])
    }

    /// Tests share Colorbee's settings, so nothing a test does may write them.
    @Test func nothingIsWrittenWhileTesting() {
        #expect(!StoredSettings.canWrite)
        let key = "StoredSettingsTests.neverWritten"
        StoredSettings.set(42, forKey: key)
        StoredSettings.save([Entry(name: "A", size: 1)], forKey: key)
        #expect(UserDefaults.standard.object(forKey: key) == nil)
    }

    /// A saved filter list with one damaged entry keeps the others.
    @Test func savedPhotoFiltersReadLeniently() throws {
        let filters = [PhotoFilter(name: "Mine", adjustments: PhotoAdjustments([.exposure: 10]))]
        var json = try #require(String(data: JSONEncoder().encode(filters), encoding: .utf8))
        json.insert(contentsOf: #"{"name":5},"#, at: json.index(after: json.startIndex))
        #expect(StoredSettings.list(of: PhotoFilter.self, from: Data(json.utf8))?.map(\.name) == ["Mine"])
    }
}
