import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import ColorbeeCore

/// Stage 12: camera details (FR-11.8).
struct CameraDetailsTests {
    /// `TestImages/Stage 12/Test Camera.dng`: made-up camera details, a serial number, an owner and a GPS location.
    private var testRAW: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "../../../../TestImages/Stage 12/Test Camera.dng")
    }

    private func properties(of data: Data) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    }

    @Test func detailsAreReadFromARAWFile() throws {
        let details = try #require(CameraDetails(properties: try properties(of: Data(contentsOf: testRAW))))
        #expect(details == CameraDetails(make: "Colorbee", model: "Test Camera", lens: "Test Lens 50mm F2.8", iso: 400,
                                         exposureTime: 0.008, fNumber: 2.8, focalLength: 50, dateTaken: "2026:10:05 10:30:00"))
    }

    @Test func anImageWithoutDetailsHasNone() throws {
        let png = try ImageCodec.encodePNG(PixelBuffer(width: 4, height: 4, fill: .white), colorSpace: Canvas.defaultColorSpace)
        #expect(CameraDetails(properties: try properties(of: png)) == nil)
        #expect(try ImageCodec.decode(png).cameraDetails == nil)
    }

    @Test(arguments: [ImageFileFormat.png, .jpeg, .tiff, .heic])
    func exportsCarryOnlyTheDetailsAsked(format: ImageFileFormat) throws {
        let source = try #require(CameraDetails(properties: try properties(of: Data(contentsOf: testRAW))))
        let image = PixelBuffer(width: 8, height: 8, fill: Pixel(r: 200, g: 100, b: 50))
        let with = try ImageCodec.encode(image, colorSpace: Canvas.defaultColorSpace, as: format, cameraDetails: source)
        let read = try properties(of: with)
        #expect(CameraDetails(properties: read) == source)
        #expect(read[kCGImagePropertyGPSDictionary] == nil)
        let exif = read[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        #expect(exif[kCGImagePropertyExifBodySerialNumber] == nil && exif[kCGImagePropertyExifCameraOwnerName] == nil)

        let without = try ImageCodec.encode(image, colorSpace: Canvas.defaultColorSpace, as: format)
        #expect(CameraDetails(properties: try properties(of: without)) == nil)
    }

    @Test func formatsWithoutEXIFDontClaimToHoldThem() {
        #expect(!ImageFileFormat.bmp.holdsCameraDetails && !ImageFileFormat.gif.holdsCameraDetails)
    }

    @Test func projectsKeepTheDetails() throws {
        let canvas = Canvas(size: IntSize(width: 16, height: 16), colorSpace: Canvas.defaultColorSpace, background: .white)
        canvas.cameraDetails = CameraDetails(model: "Test Camera", iso: 800)
        #expect(try ProjectFile.decode(ProjectFile.encode(canvas)).cameraDetails == canvas.cameraDetails)
        #expect(canvas.copy().cameraDetails == canvas.cameraDetails)
        let plain = Canvas(size: IntSize(width: 16, height: 16), colorSpace: Canvas.defaultColorSpace, background: .white)
        #expect(try ProjectFile.decode(ProjectFile.encode(plain)).cameraDetails == nil)
    }
}
