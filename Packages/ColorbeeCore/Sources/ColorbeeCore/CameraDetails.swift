import Foundation
import ImageIO

/// How a photo was taken (FR-11.8): kept with the image, and written into an export only when asked. Only these
/// fields are ever read from a file, so location, serial numbers and the owner's name are never kept or written.
public struct CameraDetails: Codable, Equatable, Sendable {
    public var make: String?
    public var model: String?
    public var lens: String?
    public var iso: Int?
    /// In seconds.
    public var exposureTime: Double?
    public var fNumber: Double?
    /// In millimeters.
    public var focalLength: Double?
    /// As EXIF writes it: "2026:10:05 10:30:00".
    public var dateTaken: String?

    public init(make: String? = nil, model: String? = nil, lens: String? = nil, iso: Int? = nil, exposureTime: Double? = nil,
                fNumber: Double? = nil, focalLength: Double? = nil, dateTaken: String? = nil) {
        self.make = make
        self.model = model
        self.lens = lens
        self.iso = iso
        self.exposureTime = exposureTime
        self.fNumber = fNumber
        self.focalLength = focalLength
        self.dateTaken = dateTaken
    }

    /// The details in an image file's properties (from `CGImageSourceCopyPropertiesAtIndex`), or nil if it has none.
    public init?(properties: [CFString: Any]) {
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let aux = properties[kCGImagePropertyExifAuxDictionary] as? [CFString: Any] ?? [:]
        func text(_ value: Any?) -> String? {
            (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        func number(_ value: Any?) -> Double? {
            (value as? NSNumber)?.doubleValue ?? (value as? [NSNumber])?.first?.doubleValue
        }
        make = text(tiff[kCGImagePropertyTIFFMake])
        model = text(tiff[kCGImagePropertyTIFFModel])
        lens = text(exif[kCGImagePropertyExifLensModel]) ?? text(aux[kCGImagePropertyExifAuxLensModel])
        iso = number(exif[kCGImagePropertyExifISOSpeedRatings]).map { Int($0.rounded()) }
        exposureTime = number(exif[kCGImagePropertyExifExposureTime])
        fNumber = number(exif[kCGImagePropertyExifFNumber])
        focalLength = number(exif[kCGImagePropertyExifFocalLength])
        dateTaken = text(exif[kCGImagePropertyExifDateTimeOriginal])
        if self == CameraDetails() { return nil }
    }

    /// Properties for `CGImageDestinationAddImage`: these fields and nothing else.
    public var properties: [CFString: Any] {
        var tiff: [CFString: Any] = [:], exif: [CFString: Any] = [:]
        tiff[kCGImagePropertyTIFFMake] = make
        tiff[kCGImagePropertyTIFFModel] = model
        exif[kCGImagePropertyExifLensModel] = lens
        exif[kCGImagePropertyExifISOSpeedRatings] = iso.map { [$0] }
        exif[kCGImagePropertyExifExposureTime] = exposureTime
        exif[kCGImagePropertyExifFNumber] = fNumber
        exif[kCGImagePropertyExifFocalLength] = focalLength
        exif[kCGImagePropertyExifDateTimeOriginal] = dateTaken
        var result: [CFString: Any] = [:]
        if !tiff.isEmpty { result[kCGImagePropertyTIFFDictionary] = tiff }
        if !exif.isEmpty { result[kCGImagePropertyExifDictionary] = exif }
        return result
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
