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
        var destination = buffer.vImageBuffer
        let error = vImageBuffer_InitWithCGImage(&destination, &format, nil, image, vImage_Flags(kvImageNoAllocate))
        guard error == kvImageNoError else { throw ImageCodecError.conversionFailed(error) }
        return DecodedImage(buffer: buffer, colorSpace: colorSpace)
    }

    public static func makeCGImage(_ buffer: PixelBuffer, colorSpace: CGColorSpace) throws -> CGImage {
        var format = try storageFormat(for: colorSpace)
        var source = buffer.vImageBuffer
        var error = vImage_Error(kvImageNoError)
        guard let image = vImageCreateCGImageFromBuffer(&source, &format, nil, nil, vImage_Flags(kvImageNoFlags), &error)?
            .takeRetainedValue(), error == kvImageNoError else {
            throw ImageCodecError.conversionFailed(error)
        }
        return image
    }

    public static func encodePNG(_ buffer: PixelBuffer, colorSpace: CGColorSpace) throws -> Data {
        try encode(buffer, colorSpace: colorSpace, as: .png)
    }

    /// Encodes in `format`. Formats without transparency are composited over `matte` first (FR-11.1).
    /// `quality` (0...1) applies to lossy formats; `tiffLZW` compresses TIFF losslessly (FR-11.1).
    public static func encode(
        _ buffer: PixelBuffer,
        colorSpace: CGColorSpace,
        as format: ImageFileFormat,
        quality: Double = 0.9,
        matte: Pixel = .white,
        tiffLZW: Bool = false
    ) throws -> Data {
        guard format.canWrite else { throw ImageCodecError.encodingFailed }
        var pixels = buffer
        if !format.supportsTransparency {
            pixels = PixelBuffer(width: buffer.width, height: buffer.height, fill: Pixel(r: matte.r, g: matte.g, b: matte.b))
            for y in 0..<buffer.height {
                let source = buffer.row(y)
                let destination = pixels.row(y)
                for x in 0..<buffer.width {
                    destination[x] = Compositing.over(destination[x], source[x])
                }
            }
        }
        let image = try makeCGImage(pixels, colorSpace: colorSpace)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, format.type.identifier as CFString, 1, nil) else {
            throw ImageCodecError.encodingFailed
        }
        var options: [CFString: Any] = [:]
        if format.isLossy { options[kCGImageDestinationLossyCompressionQuality] = quality }
        if format == .tiff {
            // TIFF compression tags: 1 is none, 5 is LZW.
            options[kCGImagePropertyTIFFDictionary] = [kCGImagePropertyTIFFCompression: tiffLZW ? 5 : 1]
        }
        CGImageDestinationAddImage(destination, image, options.isEmpty ? nil : options as CFDictionary)
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
}

/// File formats Colorbee opens and saves (FR-11.1).
public enum ImageFileFormat: CaseIterable, Sendable {
    case png
    case jpeg
    case bmp
    case gif
    case tiff
    case webp
    case heic

    public var type: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        case .bmp: .bmp
        case .gif: .gif
        case .tiff: .tiff
        case .webp: .webP
        case .heic: .heic
        }
    }

    public init?(type: UTType) {
        guard let format = ImageFileFormat.allCases.first(where: { type.conforms(to: $0.type) }) else { return nil }
        self = format
    }

    public var name: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPEG"
        case .bmp: "BMP"
        case .gif: "GIF"
        case .tiff: "TIFF"
        case .webp: "WebP"
        case .heic: "HEIC"
        }
    }

    public var supportsTransparency: Bool { self != .jpeg }
    public var isLossy: Bool { self == .jpeg || self == .heic || self == .webp }

    /// Whether this Mac's ImageIO can write the format (it can read all of them).
    public var canWrite: Bool {
        let writable = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        return writable.contains(type.identifier)
    }
}
