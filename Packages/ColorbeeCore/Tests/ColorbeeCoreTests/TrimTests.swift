import Foundation
import Testing
@testable import ColorbeeCore

/// Image ▸ Trim (§23, 2026-10-28): finding the picture's border.
struct TrimTests {
    private func picture(_ width: Int, _ height: Int, _ fill: Pixel) -> PixelBuffer {
        PixelBuffer(width: width, height: height, fill: fill)
    }

    @Test func aTransparentBorderGoesAndASoftEdgeStays() {
        let buffer = picture(20, 12, .clear)
        buffer.fill(Pixel(r: 200, g: 0, b: 0), in: IntRect(x: 6, y: 4, width: 5, height: 3))
        // A barely-there soft edge still counts as picture.
        buffer.row(9)[13] = Pixel(r: 0, g: 0, b: 255, a: 1)
        #expect(Trim.keptBounds(of: buffer) == IntRect(x: 6, y: 4, width: 8, height: 6))
    }

    @Test func aOnePixelLineIsKept() {
        let buffer = picture(30, 10, .clear)
        for x in 3..<27 { buffer.row(5)[x] = .black }
        #expect(Trim.keptBounds(of: buffer) == IntRect(x: 3, y: 5, width: 24, height: 1))
    }

    @Test func aSolidBorderGoesWithinTwoPercent() {
        let buffer = picture(16, 16, .white)
        // A JPEG's edge: off-white by a few levels.
        buffer.row(0)[5] = Pixel(r: 251, g: 252, b: 250)
        buffer.row(15)[15] = Pixel(r: 250, g: 250, b: 250)
        buffer.fill(Pixel(r: 40, g: 90, b: 40), in: IntRect(x: 4, y: 5, width: 6, height: 7))
        #expect(Trim.keptBounds(of: buffer) == IntRect(x: 4, y: 5, width: 6, height: 7))
        // Further off than 2% is picture.
        buffer.row(0)[15] = Pixel(r: 240, g: 255, b: 255)
        #expect(Trim.keptBounds(of: buffer) == IntRect(x: 4, y: 0, width: 12, height: 12))
    }

    @Test func nothingToTrimOrNothingButBorderIsNil() {
        let full = picture(8, 8, .white)
        full.row(0)[0] = .black
        full.row(7)[7] = .black
        #expect(Trim.keptBounds(of: full) == nil)
        #expect(Trim.keptBounds(of: picture(8, 8, .white)) == nil)
        #expect(Trim.keptBounds(of: picture(8, 8, .clear)) == nil)
    }

    @Test func thePracticePicturesTrimExactly() throws {
        let folder = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../../../TestImages")
        let clear = try ImageCodec.decode(Data(contentsOf: folder.appending(path: "Trim Practice.png"))).buffer
        #expect(Trim.keptBounds(of: clear) == IntRect(x: 150, y: 140, width: 491, height: 331))
        let solid = try ImageCodec.decode(Data(contentsOf: folder.appending(path: "Trim Practice Solid.png"))).buffer
        #expect(Trim.keptBounds(of: solid) == IntRect(x: 120, y: 90, width: 561, height: 411))
    }
}
