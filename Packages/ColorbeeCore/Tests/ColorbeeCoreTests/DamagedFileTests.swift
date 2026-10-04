import CoreGraphics
import Foundation
import Testing
@testable import ColorbeeCore

/// Local sweep after review round 1: settings read from files are kept in range, so a damaged or
/// hand-edited project or filter can't crash the app when it's drawn.
struct DamagedFileTests {
    private let probe: [Pixel] = (0..<256).map { (value: Int) -> Pixel in
        Pixel(r: UInt8(value), g: UInt8(255 - value), b: UInt8((value * 7) & 255))
    }

    private func decoded(_ json: String) throws -> Effect {
        try JSONDecoder().decode(Effect.self, from: Data(json.utf8))
    }

    @Test func curvesFromAFileStayOnTheGraph() throws {
        let effect = try decoded(#"{"kind": "curves", "curves": {"rgb": [{"x": 0, "y": -1e300}, {"x": 1e300, "y": 1e300}, {"x": 128, "y": 1e300}], "red": [{"x": 0, "y": 0}, {"x": 255, "y": 255}], "green": [{"x": 0, "y": 0}, {"x": 255, "y": 255}], "blue": [{"x": 0, "y": 0}, {"x": 255, "y": 255}]}}"#)
        guard case .curves(let curves) = effect else { Issue.record("Not curves"); return }
        #expect(curves.rgb.allSatisfy { (0...255).contains($0.x) && (0...255).contains($0.y) })
        let transform = try #require(effect.colorTransform)
        for pixel in probe { _ = transform(pixel) }
    }

    @Test func photoAdjustmentsFromAFileAreClamped() throws {
        let effect = try decoded(#"{"kind": "photo", "photo": {"adjustments": {"values": ["exposure", 1e300, "contrast", -1e300, "warmth", 1e300]}, "filterIntensity": 1e300}}"#)
        guard case .photo(let edit) = effect else { Issue.record("Not photo"); return }
        #expect(edit.adjustments[.exposure] == PhotoAdjustments.Slider.exposure.range.upperBound)
        #expect(edit.adjustments[.contrast] == PhotoAdjustments.Slider.contrast.range.lowerBound)
        #expect((0...100).contains(edit.filterIntensity))
        for pixel in probe { _ = edit.colorTransform(pixel) }
    }

    @Test func aFilterFileWithEffectsFiltersCantHoldIsRefused() {
        let json = Data(#"{"version": 1, "name": "Blurry", "steps": [{"kind": "gaussianBlur", "values": [500]}]}"#.utf8)
        #expect(throws: (any Error).self) { try PhotoFilter.imported(from: json) }
    }
}

struct OversizedImageTests {
    /// A real PNG whose header claims `width` × `height`, with its checksum fixed so the header is valid.
    private func png(claiming width: UInt32, by height: UInt32) throws -> Data {
        var data = try ImageCodec.encodePNG(PixelBuffer(width: 2, height: 2, fill: .black), colorSpace: Canvas.defaultColorSpace)
        // IHDR's data starts at byte 16: width, then height, big-endian; its CRC covers bytes 12..<29.
        for (offset, value) in [(16, width), (20, height)] {
            withUnsafeBytes(of: value.bigEndian) { data.replaceSubrange(offset..<(offset + 4), with: $0) }
        }
        let crc = Self.crc32(data[12..<29])
        withUnsafeBytes(of: crc.bigEndian) { data.replaceSubrange(29..<33, with: $0) }
        return data
    }

    private static func crc32(_ bytes: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        }
        return ~crc
    }

    @Test func anImageTooLargeToEditIsRefusedBeforeItsDecoded() throws {
        // ImageIO itself refuses PNGs claiming a large area, but not long thin ones; other formats may differ.
        #expect(throws: ImageCodecError.tooLarge) { try ImageCodec.decode(png(claiming: 60_000, by: 2)) }
        #expect(throws: ImageCodecError.tooLarge) { try ImageCodec.decode(png(claiming: 2, by: 30_001)) }
        #expect(!ImageCodec.fitsEditing(width: 20_000, height: 20_000))
        #expect(ImageCodec.fitsEditing(width: 16_000, height: 16_000))
    }

    @Test func aLargeButEditableSizeIsntRefusedForItsSize() throws {
        let decoded = try ImageCodec.decode(png(claiming: 30_000, by: 2))
        #expect(decoded.buffer.size == IntSize(width: 30_000, height: 2))
    }
}

struct TypedNumberTests {
    @Test func anEnormousPresetSizeDoesntOverflow() {
        let preset = ExportPreset(name: "Huge", size: .width(Int.max))
        let size = preset.targetSize(for: IntSize(width: 1, height: 1000), allowEnlarging: true)
        #expect(size.width <= ResizeSkew.maxSide && size.height <= ResizeSkew.maxSide)
        #expect(preset.targetSize(for: IntSize(width: 1, height: 1000)) == IntSize(width: 1, height: 1000))
    }
}

struct ProjectColorSpaceTests {
    @Test func aProjectWithANonRGBProfileOpensInRGB() throws {
        let gray = try #require(CGColorSpace(name: CGColorSpace.genericGrayGamma2_2))
        let canvas = Canvas(size: IntSize(width: 4, height: 4), colorSpace: gray, background: .white)
        let reopened = try ProjectFile.decode(ProjectFile.encode(canvas))
        #expect(reopened.colorSpace.model == .rgb)
    }
}
