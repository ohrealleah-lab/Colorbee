import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ColorbeeCore

/// Scans from an iPhone or iPad arrive as a PDF with one JPEG on each Letter page (FR-11.7).
struct ScannedPageTests {
    private static let letter = CGRect(x: 0, y: 0, width: 612, height: 792)

    private func jpeg(width: Int, height: Int) throws -> Data {
        let buffer = PixelBuffer(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width { buffer[x, y] = Pixel(r: UInt8(x * 4), g: UInt8(y * 2), b: 90) }
        }
        let image = try ImageCodec.makeCGImage(buffer, colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!)
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    /// A Letter-page PDF; `draw` draws each page.
    private func pdf(pages: Int, _ draw: (CGContext, Int) throws -> Void) throws -> Data {
        let data = NSMutableData()
        var box = Self.letter
        let consumer = try #require(CGDataConsumer(data: data))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        for page in 0..<pages {
            context.beginPDFPage(nil)
            try draw(context, page)
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    /// Placed as the phone places it: as large as fits, centered.
    private func drawScan(_ jpeg: Data, in context: CGContext) throws {
        let provider = try #require(CGDataProvider(data: jpeg as CFData))
        let image = try #require(CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent))
        let scale = min(Self.letter.width / Double(image.width), Self.letter.height / Double(image.height))
        let size = CGSize(width: Double(image.width) * scale, height: Double(image.height) * scale)
        context.draw(image, in: CGRect(x: (Self.letter.width - size.width) / 2, y: 0, width: size.width, height: size.height))
    }

    @Test func aScanBecomesThePhonesOwnPixels() throws {
        let scan = try jpeg(width: 60, height: 100)
        let data = try pdf(pages: 1) { context, _ in try drawScan(scan, in: context) }
        let page = try PDFPages.scannedPage(data, page: 0, resolution: 200)
        let direct = try ImageCodec.decode(scan)
        #expect(page.canvas.size == IntSize(width: 60, height: 100))
        #expect(page.canvas.layers[0].buffer.contentHash() == direct.buffer.contentHash())
        #expect(page.canvas.colorSpace.name == CGColorSpace.displayP3)
        // As tall as the Letter page: 100 pixels over 11 inches.
        #expect(abs(page.resolution - 100 / 11) < 0.001)
    }

    @Test func eachPageOfAScanIsItsOwnScan() throws {
        let scans = try [jpeg(width: 60, height: 100), jpeg(width: 50, height: 90)]
        let data = try pdf(pages: 2) { context, index in try drawScan(scans[index], in: context) }
        #expect(try PDFPages.scannedPage(data, page: 0, resolution: 200).canvas.size == IntSize(width: 60, height: 100))
        #expect(try PDFPages.scannedPage(data, page: 1, resolution: 200).canvas.size == IntSize(width: 50, height: 90))
    }

    @Test func otherPagesAreDrawnLikeAnOpenedPDF() throws {
        let scan = try jpeg(width: 60, height: 100)
        let drawing = try pdf(pages: 1) { context, _ in
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 100, y: 100, width: 200, height: 200))
        }
        let twoScans = try pdf(pages: 1) { context, _ in
            try drawScan(scan, in: context)
            try drawScan(try jpeg(width: 40, height: 40), in: context)
        }
        for data in [drawing, twoScans] {
            let page = try PDFPages.scannedPage(data, page: 0, resolution: 72)
            #expect(page.canvas.size == IntSize(width: 612, height: 792))
            #expect(page.resolution == 72)
        }
    }
}
