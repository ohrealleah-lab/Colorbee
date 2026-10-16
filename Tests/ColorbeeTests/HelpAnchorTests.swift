import Foundation
import Testing
@testable import Colorbee

/// The contextual ? buttons (FR-14.6, AC-42) open these anchors, so each must be in the shipped help book exactly once.
struct HelpAnchorTests {
    @Test(arguments: HelpAnchor.allCases)
    func eachAnchorIsInTheHelpBookOnce(_ anchor: HelpAnchor) throws {
        let pages = try #require(Bundle.main.url(forResource: "Colorbee", withExtension: "help")?
            .appending(path: "Contents/Resources/en.lproj"))
        let files = try FileManager.default.contentsOfDirectory(at: pages, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "html" }
        let count = try files.reduce(0) { total, file in
            total + (try String(contentsOf: file, encoding: .utf8)).components(separatedBy: "<a name=\"\(anchor.rawValue)\">").count - 1
        }
        #expect(count == 1)
    }
}
