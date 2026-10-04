import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import ColorbeeCore

struct ImageCodecTests {
    @Test func pngRoundTripKeepsPixelsStraightAlphaAndProfile() throws {
        let buffer = PixelBuffer(width: 4, height: 1)
        buffer[0, 0] = Pixel(r: 255, g: 0, b: 0)
        buffer[1, 0] = Pixel(r: 255, g: 0, b: 0, a: 128)
        buffer[2, 0] = Pixel(r: 10, g: 200, b: 30, a: 200)
        buffer[3, 0] = .clear

        let data = try ImageCodec.encodePNG(buffer, colorSpace: Canvas.defaultColorSpace)
        let decoded = try ImageCodec.decode(data)

        for x in 0..<4 {
            #expect(decoded.buffer[x, 0] == buffer[x, 0], "pixel \(x)")
        }
        #expect(decoded.colorSpace.name == CGColorSpace.displayP3)
    }

    @Test func decodingCanConvertIntoAnotherColorSpace() throws {
        let srgbRed = PixelBuffer(width: 1, height: 1, fill: Pixel(r: 255, g: 0, b: 0))
        let data = try ImageCodec.encodePNG(srgbRed, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)

        let decoded = try ImageCodec.decode(data, convertingTo: Canvas.defaultColorSpace)

        let pixel = decoded.buffer[0, 0]
        #expect(pixel.r < 255)
        #expect(pixel.g > 0)
        #expect(pixel.a == 255)
    }

    @Test func unreadableDataThrows() {
        #expect(throws: ImageCodecError.self) {
            try ImageCodec.decode(Data([1, 2, 3]))
        }
    }
}

struct TIFFCompressionTests {
    @Test func tiffCanBeSavedPlainOrWithLZWAndReadsBackExactly() throws {
        let buffer = PixelBuffer(width: 64, height: 64, fill: Pixel(r: 10, g: 200, b: 90, a: 255))
        buffer.fill(Pixel(r: 250, g: 20, b: 20, a: 120), in: IntRect(x: 8, y: 8, width: 20, height: 30))
        let space = Canvas.defaultColorSpace
        for lzw in [false, true] {
            let data = try ImageCodec.encode(buffer, colorSpace: space, as: .tiff, tiffLZW: lzw)
            let source = CGImageSourceCreateWithData(data as CFData, nil)!
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as! [CFString: Any]
            let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
            #expect((tiff?[kCGImagePropertyTIFFCompression] as? Int) == (lzw ? 5 : 1))
            #expect(try ImageCodec.decode(data).buffer.pixels(in: buffer.bounds) == buffer.pixels(in: buffer.bounds))
        }
    }
}
