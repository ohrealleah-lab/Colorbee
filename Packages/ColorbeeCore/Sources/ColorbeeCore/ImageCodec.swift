import Accelerate
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageCodecError: Error {
    case unreadableData
    case unsupportedColorSpace
    case conversionFailed(Int)
    case encodingFailed
}

public struct DecodedImage {
    public let buffer: PixelBuffer
    public let colorSpace: CGColorSpace
}

/// Converts between image files and straight-alpha BGRA8 buffers, preserving color profiles.
public enum ImageCodec {
    /// Decodes the first image in `data`. With no target, the image keeps its own RGB color space.
    public static func decode(_ data: Data, convertingTo target: CGColorSpace? = nil) throws -> DecodedImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ImageCodecError.unreadableData
        }
        return try decode(image, convertingTo: target)
    }

    public static func decode(_ image: CGImage, convertingTo target: CGColorSpace? = nil) throws -> DecodedImage {
        let colorSpace = target ?? rgbColorSpace(of: image)
        var format = try storageFormat(for: colorSpace)
        let buffer = PixelBuffer(width: image.width, height: image.height)
        var destination = vImageBuffer(wrapping: buffer)
        let error = vImageBuffer_InitWithCGImage(&destination, &format, nil, image, vImage_Flags(kvImageNoAllocate))
        guard error == kvImageNoError else { throw ImageCodecError.conversionFailed(error) }
        return DecodedImage(buffer: buffer, colorSpace: colorSpace)
    }

    public static func makeCGImage(_ buffer: PixelBuffer, colorSpace: CGColorSpace) throws -> CGImage {
        var format = try storageFormat(for: colorSpace)
        var source = vImageBuffer(wrapping: buffer)
        var error = vImage_Error(kvImageNoError)
        guard let image = vImageCreateCGImageFromBuffer(&source, &format, nil, nil, vImage_Flags(kvImageNoFlags), &error)?
            .takeRetainedValue(), error == kvImageNoError else {
            throw ImageCodecError.conversionFailed(error)
        }
        return image
    }

    public static func encodePNG(_ buffer: PixelBuffer, colorSpace: CGColorSpace) throws -> Data {
        let image = try makeCGImage(buffer, colorSpace: colorSpace)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
            throw ImageCodecError.encodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ImageCodecError.encodingFailed }
        return data as Data
    }

    private static func storageFormat(for colorSpace: CGColorSpace) throws -> vImage_CGImageFormat {
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.first.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        guard colorSpace.model == .rgb,
              let format = vImage_CGImageFormat(bitsPerComponent: 8, bitsPerPixel: 32, colorSpace: colorSpace, bitmapInfo: bitmapInfo) else {
            throw ImageCodecError.unsupportedColorSpace
        }
        return format
    }

    private static func rgbColorSpace(of image: CGImage) -> CGColorSpace {
        if let colorSpace = image.colorSpace, colorSpace.model == .rgb {
            return colorSpace
        }
        return CGColorSpace(name: CGColorSpace.sRGB)!
    }

    private static func vImageBuffer(wrapping buffer: PixelBuffer) -> vImage_Buffer {
        vImage_Buffer(
            data: buffer.baseAddress,
            height: vImagePixelCount(buffer.height),
            width: vImagePixelCount(buffer.width),
            rowBytes: buffer.bytesPerRow
        )
    }
}
