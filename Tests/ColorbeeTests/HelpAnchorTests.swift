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

    /// The Help menu's quick links (Leah, 2026-10-22): every page opens at its own anchor, and every page is listed.
    @Test(arguments: HelpPage.allCases)
    func eachPagesAnchorIsInTheHelpBookOnce(_ page: HelpPage) throws {
        let pages = try #require(Bundle.main.url(forResource: "Colorbee", withExtension: "help")?
            .appending(path: "Contents/Resources/en.lproj"))
        let file = pages.appending(path: "\(page.rawValue).html")
        #expect((try String(contentsOf: file, encoding: .utf8)).contains("<a name=\"\(page.anchor)\">"))
        let files = try FileManager.default.contentsOfDirectory(at: pages, includingPropertiesForKeys: nil).filter { $0.pathExtension == "html" }
        let count = try files.reduce(0) { total, file in
            total + (try String(contentsOf: file, encoding: .utf8)).components(separatedBy: "<a name=\"\(page.anchor)\">").count - 1
        }
        #expect(count == 1)
        // Every page but the contents page has a quick link.
        let listed = Set(HelpPage.allCases.map { "\($0.rawValue).html" })
        #expect(Set(files.map(\.lastPathComponent)).subtracting(listed) == ["index.html"])
    }
}
