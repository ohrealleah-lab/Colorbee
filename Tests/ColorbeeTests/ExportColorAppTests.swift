import ColorbeeCore
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Colorbee

/// Export's Color and Limit file size, and each Export As preset's Color (FR-9.7 item 8), through the snapshot the
/// panel encodes. Nothing here touches the remembered export settings.
@MainActor
struct ExportColorAppTests {
    private func profile(_ data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return image.colorSpace?.name as String?
    }

    private func photo() -> Editor {
        let editor = makeEditor(width: 200, height: 150)
        let buffer = editor.canvas.activeLayer.buffer
        for y in 0..<150 { for x in 0..<200 { buffer.row(y)[x] = Pixel(r: UInt8(x), g: UInt8((x * y) % 256), b: UInt8(y)) } }
        return editor
    }

    @Test func exportWritesTheChosenColors() throws {
        let snapshot = photo().saveSnapshot()
        #expect(profile(try snapshot.encoded(as: .jpeg)) == CGColorSpace.displayP3 as String)
        #expect(profile(try snapshot.encoded(as: .jpeg, color: .sRGB)) == CGColorSpace.sRGB as String)
        #expect(profile(try snapshot.encoded(using: ExportPreset(name: "Web", size: .width(100), color: .sRGB))) == CGColorSpace.sRGB as String)
        #expect(profile(try snapshot.encoded(using: ExportPreset(name: "Keep", size: .width(100)))) == CGColorSpace.displayP3 as String)
    }

    @Test func exportStaysUnderTheLimit() throws {
        let snapshot = photo().saveSnapshot()
        let full = try snapshot.encoded(as: .jpeg, quality: 1)
        let fitted = try snapshot.encoded(as: .jpeg, limit: full.count / 2)
        #expect(fitted.count <= full.count / 2)
        // A PNG has no quality to lower, so the limit doesn't apply.
        #expect(try snapshot.encoded(as: .png, limit: 10).count > 10)
    }
}
