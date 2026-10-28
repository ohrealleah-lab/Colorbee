import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import ColorbeeCore

/// Export's Color and Limit file size (FR-9.7 item 8).
struct ExportColorTests {
    private let p3 = CGColorSpace(name: CGColorSpace.displayP3)!, srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    /// A photo-like picture: varied color everywhere, so it doesn't compress to almost nothing.
    private func photo(_ side: Int = 256) -> PixelBuffer {
        let buffer = PixelBuffer(width: side, height: side)
        var random = SplitMix64(seed: 42)
        for y in 0..<side { for x in 0..<side { buffer.row(y)[x] = Pixel(r: UInt8(x % 256), g: random.byte(), b: UInt8((x + y) % 256)) } }
        return buffer
    }

    private func profileName(_ data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return image.colorSpace?.name as String?
    }

    @Test func convertingToSRGBDullsP3sVividRedAndKeepsGray() throws {
        let colors = PixelBuffer(width: 2, height: 1)
        colors.row(0)[0] = Pixel(r: 255, g: 0, b: 0)
        colors.row(0)[1] = Pixel(r: 128, g: 128, b: 128, a: 77)
        let converted = try ImageCodec.converted(colors, from: p3, to: srgb)
        #expect(converted[0, 0].r == 255 && converted[0, 0].g == 0)
        let gray = converted[1, 0]
        #expect(abs(Int(gray.r) - 128) <= 1 && gray.r == gray.g && gray.g == gray.b && gray.a == 77)
        // Keeping the same space changes nothing.
        #expect(try ImageCodec.converted(colors, from: p3, to: p3) === colors)
        // An sRGB red, written in P3, is less than full red there.
        let srgbRed = PixelBuffer(width: 1, height: 1, fill: Pixel(r: 255, g: 0, b: 0))
        #expect(try ImageCodec.converted(srgbRed, from: srgb, to: p3)[0, 0].r < 240)
    }

    @Test func theFileCarriesTheChosenProfile() throws {
        let data = try ImageCodec.encode(photo(32), colorSpace: srgb, as: .jpeg)
        #expect(profileName(data) == CGColorSpace.sRGB as String)
        #expect(profileName(try ImageCodec.encode(photo(32), colorSpace: p3, as: .png)) == CGColorSpace.displayP3 as String)
        #expect(ExportColor.keep.space(for: p3) === p3 && ExportColor.sRGB.space(for: p3).name == CGColorSpace.sRGB)
    }

    @Test func aSizeLimitIsKeptWithTheBestQualityThatFits() throws {
        let picture = photo()
        let full = try ImageCodec.encode(picture, colorSpace: p3, as: .jpeg, quality: 1)
        let limit = full.count / 3
        let fitted = try ImageCodec.encode(picture, colorSpace: p3, as: .jpeg, limit: limit)
        #expect(fitted.count <= limit && fitted.count > limit * 2 / 3)
        // Already small enough: full quality.
        #expect(try ImageCodec.encode(picture, colorSpace: p3, as: .jpeg, limit: full.count + 10) == full)
        #expect(throws: ImageCodecError.encodingFailed) { try ImageCodec.encode(picture, colorSpace: p3, as: .png, limit: 1000) }
    }

    @Test func tooSmallALimitSaysTheSmallestPossible() {
        do {
            _ = try ImageCodec.encode(photo(), colorSpace: p3, as: .jpeg, limit: 500)
            Issue.record("It fitted")
        } catch let ImageCodecError.overSizeLimit(limit, smallest) {
            #expect(limit == 500 && smallest > 500)
            #expect(ImageCodecError.overSizeLimit(limit: 5000, smallest: 38000).localizedDescription.contains("5 KB"))
        } catch {
            Issue.record("\(error)")
        }
    }
}
