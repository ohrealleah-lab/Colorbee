import ColorbeeCore
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The Develop window's controls (FR-11.8). Exposure is in stops; Temperature in kelvin; Tint, Shadows and
/// Contrast from −100 to 100; Highlights from −100 to 0 (macOS's highlight control only brings bright areas
/// down); Noise Reduction and Sharpness from 0 to 100.
struct DevelopSettings: Equatable, Sendable {
    var exposure = 0.0
    var temperature = 6500.0
    var tint = 0.0
    var highlights = 0.0
    var shadows = 0.0
    var contrast = 0.0
    var noiseReduction = 0.0
    var sharpness = 0.0
    var lensCorrection = false
}

/// What a RAW file's camera can be developed with, besides the controls every file has.
struct DevelopSupport: Equatable, Sendable {
    var noiseReduction = false
    var sharpness = false
    var lensCorrection = false
}

enum RawDevelopError: LocalizedError {
    case unreadable
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .unreadable:
            "This RAW file can't be read. The camera may be newer than this version of macOS knows; a macOS update usually adds it."
        case .tooLarge:
            "This photo is too large to open. Colorbee edits images up to \(ResizeSkew.maxSide.formatted()) pixels on a side and \(ResizeSkew.maxArea / 1_000_000) megapixels, and the photo must fit in memory."
        }
    }
}

/// Develops a camera RAW file with macOS's own RAW engine (the one Photos and Preview use), at RAW precision,
/// into Colorbee's 8-bit Display P3 pixels (FR-11.8). Each render makes its own filter, so previews and the final
/// render can run on other threads.
final class RawDeveloper: Sendable {
    let url: URL
    let cameraDefaults: DevelopSettings
    let support: DevelopSupport
    /// Upright size, in pixels.
    let size: IntSize
    let cameraDetails: CameraDetails?

    // CIContext is safe to share between threads.
    nonisolated(unsafe) private static let context = CIContext(options: [.cacheIntermediates: false, .workingFormat: CIFormat.RGBAh])
    private static let colorSpace = Canvas.defaultColorSpace

    static func isRAW(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.conforms(to: .rawImage) == true
    }

    init(url: URL) throws {
        guard let filter = CIRAWFilter(imageURL: url) else { throw RawDevelopError.unreadable }
        self.url = url
        let native = filter.nativeSize
        // Turned photos (portrait) are shown upright: the output's size, not the sensor's.
        let upright = filter.outputImage?.extent.size ?? native
        size = IntSize(width: Int(upright.width.rounded()), height: Int(upright.height.rounded()))
        guard size.width > 0, size.height > 0 else { throw RawDevelopError.unreadable }
        support = DevelopSupport(noiseReduction: filter.isLuminanceNoiseReductionSupported, sharpness: filter.isSharpnessSupported,
                                 lensCorrection: filter.isLensCorrectionSupported)
        cameraDefaults = DevelopSettings(
            temperature: Double(filter.neutralTemperature), tint: Double(filter.neutralTint),
            noiseReduction: support.noiseReduction ? Double(filter.luminanceNoiseReductionAmount) * 100 : 0,
            sharpness: support.sharpness ? Double(filter.sharpnessAmount) * 100 : 0,
            lensCorrection: support.lensCorrection && filter.isLensCorrectionEnabled
        )
        let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        let properties = source.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] } ?? [:]
        cameraDetails = CameraDetails(properties: properties)
    }

    /// The developed photo, scaled by `scale` (1 for full size), still at RAW precision.
    private func image(_ settings: DevelopSettings, scale: Double) -> CIImage? {
        guard let filter = CIRAWFilter(imageURL: url) else { return nil }
        filter.scaleFactor = Float(scale)
        filter.exposure = Float(settings.exposure)
        filter.neutralTemperature = Float(settings.temperature)
        filter.neutralTint = Float(settings.tint)
        if support.noiseReduction { filter.luminanceNoiseReductionAmount = Float(settings.noiseReduction / 100) }
        if support.sharpness { filter.sharpnessAmount = Float(settings.sharpness / 100) }
        if support.lensCorrection { filter.isLensCorrectionEnabled = settings.lensCorrection }
        guard var image = filter.outputImage else { return nil }
        // Highlights and Shadows work on the unclipped image, so detail above white can still be brought back.
        if settings.highlights != 0 || settings.shadows != 0 {
            image = image.applyingFilter("CIHighlightShadowAdjust", parameters: [
                "inputHighlightAmount": 1 + max(-1, min(0, settings.highlights / 100)),
                "inputShadowAmount": settings.shadows / 100,
                "inputRadius": 0,
            ])
        }
        if settings.contrast != 0 {
            image = image.applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1 + settings.contrast / 100 * 0.5])
        }
        return image
    }

    /// A small picture for the Develop window, at most `maxSide` pixels on its longer side.
    func preview(_ settings: DevelopSettings, maxSide: Int) -> CGImage? {
        let scale = min(1, Double(maxSide) / Double(max(size.width, size.height)))
        guard let image = image(settings, scale: scale) else { return nil }
        return Self.context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: Self.colorSpace)
    }

    /// The full-size photo as a one-layer canvas in Display P3, with its camera details.
    func develop(_ settings: DevelopSettings) throws -> Canvas {
        guard ImageCodec.fitsEditing(width: size.width, height: size.height) else { throw RawDevelopError.tooLarge }
        // The pixels, plus room for the engine to work, must fit comfortably in memory.
        guard size.width * size.height * 4 * 3 < ProcessInfo.processInfo.physicalMemory / 2 else { throw RawDevelopError.tooLarge }
        guard let image = image(settings, scale: 1) else { throw RawDevelopError.unreadable }
        let buffer = PixelBuffer(width: size.width, height: size.height)
        let bounds = CGRect(x: image.extent.minX, y: image.extent.minY, width: CGFloat(size.width), height: CGFloat(size.height))
        Self.context.render(image, toBitmap: buffer.baseAddress, rowBytes: buffer.bytesPerRow, bounds: bounds,
                            format: .BGRA8, colorSpace: Self.colorSpace)
        let canvas = Canvas(colorSpace: Self.colorSpace, layers: [Layer(name: "Background", buffer: buffer)], hasTransparentBackground: false)
        canvas.cameraDetails = cameraDetails
        return canvas
    }
}
