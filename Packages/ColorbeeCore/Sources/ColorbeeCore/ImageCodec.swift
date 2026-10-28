import Accelerate
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageCodecError: Error, Equatable {
    case unreadableData
    /// Over the largest size Colorbee edits (`ResizeSkew.maxSide`, `maxArea`).
    case tooLarge
    case unsupportedColorSpace
    case conversionFailed(Int)
    case encodingFailed
    /// Export's Limit file size (FR-9.7 item 8): even the lowest quality is over the limit; this is the smallest it
    /// can be, in bytes.
    case overSizeLimit(limit: Int, smallest: Int)
}

extension ImageCodecError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .tooLarge:
            "This image is too large to edit. Colorbee edits images up to \(ResizeSkew.maxSide.formatted()) pixels on a side and \(ResizeSkew.maxArea / 1_000_000) megapixels."
        // Plain words instead of an error code (review J, finding 27).
        case .unreadableData: "This file isn't an image Colorbee can read, or it's damaged."
        case .unsupportedColorSpace: "This image uses colors Colorbee can't read."
        case .conversionFailed: "This image couldn't be read."
        case .encodingFailed: "The image couldn't be written in this format."
        case .overSizeLimit(let limit, let smallest):
            "This picture can't be made as small as \(ByteCountFormatter.string(fromByteCount: Int64(limit), countStyle: .file)). The smallest it can be at this size is \(ByteCountFormatter.string(fromByteCount: Int64(smallest), countStyle: .file))."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .overSizeLimit: "Nothing was saved. Raise the limit, or use File ▸ Export As to make the picture smaller in pixels first."
        default: nil
        }
    }
}

public struct DecodedImage {
    public let buffer: PixelBuffer
    public let colorSpace: CGColorSpace
    /// Frames (an animated GIF) or pages (a multi-page TIFF) in the file; only one is decoded.
    public var frameCount = 1
    /// More than 8 bits per channel in the file; Colorbee keeps 8.
    public var isDeep = false
    /// How the photo was taken, if the file says (FR-11.8).
    public var cameraDetails: CameraDetails?
    /// The file had a GPS location, which isn't kept.
    public var locationRemoved = false

    /// Saving back over the file would lose frames or precision, so it opens as an untitled copy
    /// (Leah; review J, finding 2).
    public var opensAsCopy: Bool { frameCount > 1 || isDeep }
}

/// Converts between image files and straight-alpha BGRA8 buffers, preserving color profiles.
public enum ImageCodec {
    /// Decodes one frame (the first, by default) of `data`, upright. With no target, the image keeps its own
    /// RGB color space.
    public static func decode(_ data: Data, convertingTo target: CGColorSpace? = nil, frame: Int = 0) throws -> DecodedImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw ImageCodecError.unreadableData }
        let frameCount = CGImageSourceGetCount(source)
        guard frame >= 0, frame < max(frameCount, 1) else { throw ImageCodecError.unreadableData }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, frame, nil) as? [CFString: Any] ?? [:]
        // The header's size is checked before anything is decoded, so a file claiming a huge size can't use up
        // memory (local sweep after review round 1).
        if let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
           !fitsEditing(width: width, height: height) {
            throw ImageCodecError.tooLarge
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, frame, nil) else { throw ImageCodecError.unreadableData }
        var decoded = try decode(image, convertingTo: target)
        // Photos are often stored turned, with a tag saying how to show them (review J, finding 3).
        let tag = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let turns = uprightingTurns(forOrientationTag: tag)
        if !turns.isEmpty {
            var buffer = decoded.buffer
            for turn in turns { buffer = buffer.transformed(turn) }
            decoded = DecodedImage(buffer: buffer, colorSpace: decoded.colorSpace)
        }
        decoded.frameCount = frameCount
        decoded.isDeep = image.bitsPerComponent > 8
        decoded.cameraDetails = CameraDetails(properties: properties)
        decoded.locationRemoved = CameraDetails.hasLocation(properties: properties)
        return decoded
    }

    /// The turns that show an image stored with EXIF orientation `tag` (1–8) the right way up.
    static func uprightingTurns(forOrientationTag tag: Int) -> [Orientation] {
        switch tag {
        case 2: [.flipHorizontal]
        case 3: [.rotate180]
        case 4: [.flipVertical]
        case 5: [.rotate90Clockwise, .flipHorizontal]
        case 6: [.rotate90Clockwise]
        case 7: [.rotate90Clockwise, .flipVertical]
        case 8: [.rotate90CounterClockwise]
        default: []
        }
    }

    /// A small picture of each frame, for Choose Frame… (review J, finding 2).
    public static func frameThumbnails(_ data: Data, maxSide: Int, limit: Int = 300) -> [CGImage] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return [] }
        return (0..<min(CGImageSourceGetCount(source), limit)).compactMap { index in
            CGImageSourceCreateThumbnailAtIndex(source, index, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxSide,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ] as CFDictionary)
        }
    }

    public static func fitsEditing(width: Int, height: Int) -> Bool {
        width <= ResizeSkew.maxSide && height <= ResizeSkew.maxSide && width * height <= ResizeSkew.maxArea
    }

    public static func decode(_ image: CGImage, convertingTo target: CGColorSpace? = nil) throws -> DecodedImage {
        guard fitsEditing(width: image.width, height: image.height) else { throw ImageCodecError.tooLarge }
        let colorSpace = target ?? rgbColorSpace(of: image)
        var format = try storageFormat(for: colorSpace)
        let buffer = PixelBuffer(width: image.width, height: image.height)
        var destination = buffer.vImageBuffer
        let error = vImageBuffer_InitWithCGImage(&destination, &format, nil, image, vImage_Flags(kvImageNoAllocate))
        guard error == kvImageNoError else { throw ImageCodecError.conversionFailed(error) }
        return DecodedImage(buffer: buffer, colorSpace: colorSpace)
    }

    /// `buffer`'s colors, in `source`, as `target` shows them, for Export's Color (FR-9.7 item 8). Colors `target`
    /// can't show are brought just inside it, so vivid ones get a little duller going from Display P3 to sRGB.
    public static func converted(_ buffer: PixelBuffer, from source: CGColorSpace, to target: CGColorSpace) throws -> PixelBuffer {
        guard source != target, source.name != target.name || source.name == nil else { return buffer }
        return try decode(makeCGImage(buffer, colorSpace: source), convertingTo: target).buffer
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
        tiffLZW: Bool = false,
        cameraDetails: CameraDetails? = nil
    ) throws -> Data {
        guard format.canWrite else { throw ImageCodecError.encodingFailed }
        let image = try prepared(buffer, colorSpace: colorSpace, as: format, matte: matte)
        return try write(image, as: format, quality: quality, tiffLZW: tiffLZW, cameraDetails: cameraDetails)
    }

    /// A JPEG or HEIC no bigger than `limit` bytes (FR-9.7 item 8): the highest quality that fits, found by halving
    /// the range eight times. Camera details count toward the size. Throws `overSizeLimit` if even the lowest
    /// quality is too big.
    public static func encode(
        _ buffer: PixelBuffer,
        colorSpace: CGColorSpace,
        as format: ImageFileFormat,
        limit: Int,
        matte: Pixel = .white,
        cameraDetails: CameraDetails? = nil
    ) throws -> Data {
        guard format.canWrite, format.isLossy else { throw ImageCodecError.encodingFailed }
        let image = try prepared(buffer, colorSpace: colorSpace, as: format, matte: matte)
        func at(_ quality: Double) throws -> Data { try write(image, as: format, quality: quality, cameraDetails: cameraDetails) }
        let best = try at(1)
        if best.count <= limit { return best }
        var fits = try at(0.01)
        guard fits.count <= limit else { throw ImageCodecError.overSizeLimit(limit: limit, smallest: fits.count) }
        var low = 0.01, high = 1.0
        for _ in 0..<8 {
            let middle = (low + high) / 2
            let data = try at(middle)
            if data.count <= limit {
                low = middle
                fits = data
            } else {
                high = middle
            }
        }
        return fits
    }

    /// The picture as `format` takes it: flattened over `matte` when the format has no transparency (FR-11.1).
    private static func prepared(_ buffer: PixelBuffer, colorSpace: CGColorSpace, as format: ImageFileFormat, matte: Pixel) throws -> CGImage {
        var pixels = buffer
        if !format.supportsTransparency {
            pixels = PixelBuffer(width: buffer.width, height: buffer.height, fill: Pixel(r: matte.r, g: matte.g, b: matte.b))
            ParallelRows.forEach(0..<buffer.height) { rows in
                for y in rows {
                    let source = buffer.row(y)
                    let destination = pixels.row(y)
                    for x in 0..<buffer.width {
                        destination[x] = Compositing.over(destination[x], source[x])
                    }
                }
            }
        }
        return try makeCGImage(pixels, colorSpace: colorSpace)
    }

    private static func write(_ image: CGImage, as format: ImageFileFormat, quality: Double, tiffLZW: Bool = false,
                              cameraDetails: CameraDetails?) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, format.type.identifier as CFString, 1, nil) else {
            throw ImageCodecError.encodingFailed
        }
        var options: [CFString: Any] = [:]
        if format.isLossy { options[kCGImageDestinationLossyCompressionQuality] = quality }
        if let cameraDetails, format.holdsCameraDetails {
            options.merge(cameraDetails.properties) { $1 }
        }
        if format == .tiff {
            // TIFF compression tags: 1 is none, 5 is LZW.
            var tiff = options[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
            tiff[kCGImagePropertyTIFFCompression] = tiffLZW ? 5 : 1
            options[kCGImagePropertyTIFFDictionary] = tiff
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
    /// Whether the format can carry camera details (EXIF).
    public var holdsCameraDetails: Bool { self == .png || self == .jpeg || self == .tiff || self == .heic }
    public var isLossy: Bool { self == .jpeg || self == .heic || self == .webp }

    /// Whether this Mac's ImageIO can write the format (it can read all of them).
    public var canWrite: Bool {
        let writable = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        return writable.contains(type.identifier)
    }
}
