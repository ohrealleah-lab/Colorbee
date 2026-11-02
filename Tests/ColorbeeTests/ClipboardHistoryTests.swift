import AppKit
import Foundation
import Testing
@testable import Colorbee

/// Review AF, finding 3: a test that copies or pastes must leave Leah's real Clipboard History folder alone.
@MainActor
struct ClipboardHistoryTests {
    private func png(_ shade: Int) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4 + shade, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    @Test func addingAndForgettingImagesWritesAndDeletesNothingOnDisk() {
        let folder = SettingsFolder.everyday.appending(path: "Clipboard History", directoryHint: .isDirectory)
        func files() -> Set<String> { Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []) }
        let before = files()
        let history = ClipboardHistory.shared
        for shade in 0..<(ClipboardHistory.capacity + 2) { #expect(history.add(png(shade)) != nil) }
        #expect(history.items.count == ClipboardHistory.capacity)
        #expect(files() == before)
        history.clear()
        #expect(files() == before)
    }
}
