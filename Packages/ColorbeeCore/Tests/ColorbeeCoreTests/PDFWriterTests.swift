import CoreGraphics
import Foundation
import Testing
@testable import ColorbeeCore

/// Stage 10b: Export as PDF (FR-11.6).
struct PDFWriterTests {
    private let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    private func twoPages() throws -> Data {
        let red = PixelBuffer(width: 30, height: 20, fill: Pixel(r: 255, g: 0, b: 0))
        red.fill(Pixel(r: 0, g: 0, b: 255), in: IntRect(x: 0, y: 0, width: 10, height: 10))
        let clear = PixelBuffer(width: 40, height: 10, fill: .clear)
        clear.fill(.black, in: IntRect(x: 20, y: 0, width: 20, height: 10))
        return try PDFWriter.document([
            PDFWriter.encodePage(red, colorSpace: sRGB, resolution: 72),
            PDFWriter.encodePage(clear, colorSpace: sRGB, resolution: 144),
        ])
    }

    @Test func pagesComeOutInOrderAtTheirResolution() throws {
        let data = try twoPages()
        let document = try #require(CGPDFDocument(CGDataProvider(data: data as CFData)!))
        #expect(document.numberOfPages == 2)
        #expect(document.page(at: 1)?.getBoxRect(.mediaBox).size == CGSize(width: 30, height: 20))
        #expect(document.page(at: 2)?.getBoxRect(.mediaBox).size == CGSize(width: 20, height: 5))
    }

    @Test func pixelsSurviveAndTransparencyIsWhite() throws {
        let data = try twoPages()
        let first = try PDFPages.render(data, page: 0, resolution: 72).canvas.layers[0].buffer
        let blue = first.row(5)[5], red = first.row(15)[25]
        #expect(blue.b > 245 && blue.r < 10 && blue.g < 10)
        #expect(red.r > 245 && red.g < 10 && red.b < 10)
        let second = try PDFPages.render(data, page: 1, resolution: 144).canvas.layers[0].buffer
        let white = second.row(5)[5], black = second.row(5)[30]
        #expect(white.r > 245 && white.g > 245 && white.b > 245 && white.a == 255)
        #expect(black.r < 10 && black.g < 10 && black.b < 10)
    }

    @Test func nothingSaysWhoMadeItOrWhen() throws {
        let text = String(decoding: try twoPages(), as: UTF8.self)
        for key in ["/Info", "/Producer", "/Creator", "/CreationDate", "/ModDate", "/Author", "/Title", "/ID", "/Metadata"] {
            #expect(!text.contains(key), "\(key)")
        }
    }

    @Test func oneProfileIsSharedByPagesThatUseIt() throws {
        let page = try PDFWriter.encodePage(PixelBuffer(width: 4, height: 4, fill: .white), colorSpace: sRGB, resolution: 72)
        let text = String(decoding: try PDFWriter.document([page, page, page]), as: UTF8.self)
        #expect(text.components(separatedBy: "/ICCBased").count == 4)
        #expect(text.components(separatedBy: "/Alternate /DeviceRGB").count == 2)
    }

    @Test func zlibHasTheRightChecksum() throws {
        let wrapped = try PDFWriter.zlib(Data("Wikipedia".utf8))
        #expect(wrapped.prefix(2) == Data([0x78, 0x9C]))
        #expect(wrapped.suffix(4) == Data([0x11, 0xE6, 0x03, 0x98]))
    }

    /// Review K, finding 8 (Leah): a custom profile isn't embedded; the page is converted to Display P3.
    @Test func aCustomProfileBecomesDisplayP3() throws {
        let custom = try #require(CGColorSpace(name: CGColorSpace.adobeRGB1998))
        let page = try PDFWriter.encodePage(PixelBuffer(width: 4, height: 4, fill: Pixel(r: 200, g: 40, b: 40)), colorSpace: custom, resolution: 72)
        #expect(page.profile == CGColorSpace(name: CGColorSpace.displayP3)?.copyICCData() as Data?)
        let kept = try PDFWriter.encodePage(PixelBuffer(width: 4, height: 4, fill: .white), colorSpace: sRGB, resolution: 72)
        #expect(kept.profile == sRGB.copyICCData() as Data?)
    }
}
