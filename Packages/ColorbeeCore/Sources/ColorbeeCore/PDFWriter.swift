import CoreGraphics
import Foundation

/// Writes a PDF of pixel pages (FR-11.6, Export as PDF): one image per page, losslessly compressed, with each
/// page's color profile, and no metadata at all: no title, author, app name or dates (Leah, 2026-10-04).
/// Written by hand because Core Graphics always adds its own producer and dates.
public enum PDFWriter {
    /// One page, compressed and ready to be written. Making these is the slow part, so it can run in parallel.
    public struct EncodedPage: Sendable {
        let width: Int
        let height: Int
        /// The page's size in points (1/72 inch).
        let mediaSize: (width: Double, height: Double)
        /// RGB, 8 bits a channel, zlib-compressed. Emptied once written, so a long document isn't held twice.
        var pixels: Data
        let profile: Data?
    }

    /// Compresses `image` (a flattened page) for the PDF, over white where it's transparent, as a PDF viewer
    /// would show it. `resolution` is in pixels per inch and sets the page's printed size.
    public static func encodePage(_ image: PixelBuffer, colorSpace: CGColorSpace, resolution: Double) throws -> EncodedPage {
        // A custom profile (a calibrated display's, a camera's) can name a device or a person's calibration, so such
        // pages are converted to Display P3; Display P3 and sRGB are kept as they are (Leah, 2026-10-05; review K, finding 8).
        var image = image, colorSpace = colorSpace
        let standard = [CGColorSpace.displayP3, CGColorSpace.sRGB].contains { $0 == colorSpace.name }
        if !standard, let displayP3 = CGColorSpace(name: CGColorSpace.displayP3) {
            image = try ImageCodec.decode(ImageCodec.makeCGImage(image, colorSpace: colorSpace), convertingTo: displayP3).buffer
            colorSpace = displayP3
        }
        let width = image.width, height = image.height
        var rgb = Data(count: width * height * 3)
        rgb.withUnsafeMutableBytes { raw in
            let out = raw.bindMemory(to: UInt8.self).baseAddress!
            ParallelRows.forEach(0..<height) { rows in
                for y in rows {
                    let row = image.row(y)
                    var index = y * width * 3
                    for x in 0..<width {
                        let pixel = row[x]
                        let alpha = Int(pixel.a), white = 255 * (255 - alpha) + 127
                        out[index] = UInt8((Int(pixel.r) * alpha + white) / 255)
                        out[index + 1] = UInt8((Int(pixel.g) * alpha + white) / 255)
                        out[index + 2] = UInt8((Int(pixel.b) * alpha + white) / 255)
                        index += 3
                    }
                }
            }
        }
        let points = 72 / max(resolution, 1)
        return EncodedPage(width: width, height: height,
                           mediaSize: (Double(width) * points, Double(height) * points),
                           pixels: try zlib(rgb), profile: colorSpace.copyICCData() as Data?)
    }

    /// The PDF file, its pages in order.
    public static func document(_ pages: [EncodedPage]) throws -> Data {
        var pages = pages
        var file = Data()
        var offsets: [Int] = [0]
        func object(_ body: String, stream: Data? = nil) -> Int {
            offsets.append(file.count)
            let number = offsets.count - 1
            file.append(Data("\(number) 0 obj\n\(body)\n".utf8))
            if let stream {
                file.append(Data("stream\n".utf8))
                file.append(stream)
                file.append(Data("\nendstream\n".utf8))
            }
            file.append(Data("endobj\n".utf8))
            return number
        }
        file.append(Data("%PDF-1.7\n%".utf8))
        file.append(Data([0xE2, 0xE3, 0xCF, 0xD3, 0x0A]))

        // Object 1 is the catalog and 2 the page list, written last once the pages' numbers are known.
        var profiles: [Data: Int] = [:]
        var pageNumbers: [Int] = []
        _ = object("<< /Type /Catalog /Pages 2 0 R >>")
        offsets.append(0)
        for index in pages.indices {
            let page = pages[index]
            var colorSpace = "/DeviceRGB"
            if let profile = page.profile {
                let compressed = try zlib(profile)
                let number = profiles[profile]
                    ?? object("<< /N 3 /Alternate /DeviceRGB /Filter /FlateDecode /Length \(compressed.count) >>", stream: compressed)
                profiles[profile] = number
                colorSpace = "[/ICCBased \(number) 0 R]"
            }
            let image = object("<< /Type /XObject /Subtype /Image /Width \(page.width) /Height \(page.height) /ColorSpace \(colorSpace) "
                               + "/BitsPerComponent 8 /Filter /FlateDecode /Length \(page.pixels.count) >>", stream: page.pixels)
            let w = number(page.mediaSize.width), h = number(page.mediaSize.height)
            let drawing = Data("q \(w) 0 0 \(h) 0 0 cm /Im0 Do Q".utf8)
            let contents = object("<< /Length \(drawing.count) >>", stream: drawing)
            pageNumbers.append(object("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 \(w) \(h)] "
                                      + "/Resources << /XObject << /Im0 \(image) 0 R >> >> /Contents \(contents) 0 R >>"))
            pages[index].pixels = Data()
        }
        offsets[2] = file.count
        let kids = pageNumbers.map { "\($0) 0 R" }.joined(separator: " ")
        file.append(Data("2 0 obj\n<< /Type /Pages /Kids [\(kids)] /Count \(pages.count) >>\nendobj\n".utf8))

        let table = file.count
        var xref = "xref\n0 \(offsets.count)\n0000000000 65535 f \n"
        // Padded by hand: "%d" reads 32 bits, so offsets past 2 GB would come out wrong (review K, finding 10).
        for offset in offsets.dropFirst() {
            let digits = String(offset)
            xref += String(repeating: "0", count: max(0, 10 - digits.count)) + digits + " 00000 n \n"
        }
        // No /Info and no /ID: nothing that says who made the file or when.
        xref += "trailer\n<< /Size \(offsets.count) /Root 1 0 R >>\nstartxref\n\(table)\n%%EOF\n"
        file.append(Data(xref.utf8))
        return file
    }

    /// A PDF number: up to 3 decimals, never in exponent form.
    private static func number(_ value: Double) -> String {
        var text = String(format: "%.3f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// zlib format (RFC 1950), as PDF's FlateDecode wants: Foundation's `.zlib` gives raw deflate, so the header
    /// and Adler-32 checksum are added here.
    static func zlib(_ data: Data) throws -> Data {
        // A failure is reported rather than written as an empty page (review K, finding 10).
        let deflated = try (data as NSData).compressed(using: .zlib) as Data
        var a: UInt32 = 1, b: UInt32 = 0
        data.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            var index = 0
            // 5552 bytes is the most that can be summed before the 32-bit sums must be reduced.
            while index < bytes.count {
                let end = min(index + 5552, bytes.count)
                for i in index..<end {
                    a &+= UInt32(bytes[i])
                    b &+= a
                }
                a %= 65521
                b %= 65521
                index = end
            }
        }
        var result = Data([0x78, 0x9C])
        result.append(deflated)
        withUnsafeBytes(of: ((b << 16) | a).bigEndian) { result.append(contentsOf: $0) }
        return result
    }
}
