import Foundation
import Testing
@testable import Colorbee

/// Hardening (Leah, 2026-10-19): the app's own readers with damaged files. The core's readers are covered by
/// `FileFuzzTests`. Files are written to a temporary folder; nothing is saved to Colorbee's settings.
@MainActor
struct DamagedFileAppTests {
    private static let camera = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appending(path: "../../TestImages/Stage 12/Test Camera.dng").standardized

    @Test func aDamagedRAWFileIsRefused() throws {
        let original = try Data(contentsOf: Self.camera)
        let folder = FileManager.default.temporaryDirectory.appending(path: "DamagedRAW-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var random = SystemRandomNumberGenerator()
        var files = [Data(), Data("not a photo".utf8), Data((0..<4096).map { _ in UInt8.random(in: 0...255, using: &random) })]
        files += stride(from: 0, to: original.count, by: max(1, original.count / 12)).map { original.prefix($0) }
        for (number, data) in files.enumerated() {
            let url = folder.appending(path: "Damaged \(number).dng")
            try data.write(to: url)
            // Refused, or read at a size Colorbee can edit; never a crash.
            if let developer = try? RawDeveloper(url: url) {
                #expect(developer.size.width > 0 && developer.size.height > 0)
            }
        }
    }

    @Test func aPaletteFilesCustomColorsAreAlwaysFourSlots() {
        for packed in [[], [-1], [Int.max, Int.min, -5, 0xFFFF_FFFF + 1], Array(repeating: 0x1122_33FF, count: 10_000), [0x00FF_00FF]] {
            #expect(CustomColors.unpacked(packed).count == CustomColors.slotCount)
        }
    }
}
