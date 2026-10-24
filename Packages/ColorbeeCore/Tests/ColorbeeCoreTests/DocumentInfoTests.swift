import Testing
@testable import ColorbeeCore

/// The Info panel's rows (FR-1.3).
struct DocumentInfoTests {
    private func info(camera: CameraDetails? = nil, locationRemoved: Bool = false, resolution: Double = Page.defaultResolution,
                      pageCount: Int = 1) -> DocumentInfo {
        DocumentInfo(fileName: "Shot.png", kind: "PNG image", bytesOnDisk: 2_400_000, size: IntSize(width: 1920, height: 1080),
                     profileName: "Display P3", hasTransparentBackground: false, layerCount: 1, pageIndex: 2,
                     pageCount: pageCount, resolution: resolution, camera: camera, locationRemoved: locationRemoved)
    }

    private func rows(_ info: DocumentInfo, _ title: String) -> [String: String] {
        Dictionary(uniqueKeysWithValues: (info.sections.first { $0.title == title }?.rows ?? []).map { ($0.label, $0.value) })
    }

    @Test func aScreenshotHasFileAndImageOnly() {
        let info = info()
        #expect(info.sections.map(\.title) == ["File", "Image"])
        #expect(rows(info, "File") == ["Name": "Shot.png", "Kind": "PNG image", "Size": "2.4 MB"])
        #expect(rows(info, "Image") == ["Dimensions": "1920 × 1080 px", "Color profile": "Display P3", "Background": "Solid",
                                         "Layers": "1"])
    }

    @Test func anUnsavedDocumentSaysSo() {
        var info = info()
        info.kind = nil
        info.bytesOnDisk = nil
        #expect(rows(info, "File") == ["Name": "Shot.png", "Kind": "Not saved yet"])
    }

    @Test func pagesAndAPDFsResolutionShowOnlyWhenThereAreSome() {
        let pdf = info(resolution: 200, pageCount: 12)
        #expect(rows(pdf, "Image")["Page"] == "3 of 12")
        #expect(rows(pdf, "Image")["Resolution"] == "200 DPI")
        #expect(rows(info(), "Image")["Page"] == nil && rows(info(), "Image")["Resolution"] == nil)
    }

    @Test func aPhotoShowsHowItWasTaken() {
        let camera = CameraDetails(make: "Canon", model: "Canon EOS R5", lens: "RF 50mm F1.8", iso: 400, exposureTime: 0.008,
                                   fNumber: 1.8, focalLength: 50, dateTaken: "2026:10:05 10:30:00")
        let photo = rows(info(camera: camera, locationRemoved: true), "Photo")
        #expect(photo["Camera"] == "Canon EOS R5")
        #expect(photo["Lens"] == "RF 50mm F1.8" && photo["ISO"] == "400" && photo["Shutter"] == "1/125 s")
        #expect(photo["Aperture"] == "ƒ/1.8" && photo["Focal length"] == "50 mm" && photo["Location"] == "Removed")
        #expect(photo["Taken"]?.contains("2026") == true)
    }

    @Test func aRemovedLocationShowsEvenWithoutCameraDetails() {
        let info = info(locationRemoved: true)
        #expect(info.sections.last?.rows == [DocumentInfo.Row(label: "Location", value: "Removed")])
    }

    @Test func cameraNamesAreShownOnce() {
        #expect(DocumentInfo.cameraName(make: "Apple", model: "iPhone 17 Pro") == "Apple iPhone 17 Pro")
        #expect(DocumentInfo.cameraName(make: "NIKON CORPORATION", model: "NIKON Z 6") == "NIKON Z 6")
        #expect(DocumentInfo.cameraName(make: nil, model: "Test Camera") == "Test Camera")
        #expect(DocumentInfo.cameraName(make: nil, model: nil) == nil)
    }

    @Test func valuesReadNaturally() {
        #expect(DocumentInfo.shutter(1.0 / 60) == "1/60 s")
        #expect(DocumentInfo.shutter(2) == "2 s")
        #expect(DocumentInfo.shutter(0.5) == "0.5 s")
        #expect(DocumentInfo.number(2.8) == "2.8" && DocumentInfo.number(26.0) == "26")
        #expect(DocumentInfo.dateTaken("sometime") == "sometime")
    }
}
