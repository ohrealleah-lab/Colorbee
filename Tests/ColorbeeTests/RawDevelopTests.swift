import ColorbeeCore
import CoreGraphics
import Foundation
import Testing
@testable import Colorbee

/// RAW photos and the Develop window (FR-11.8), on the test camera's photo: what the camera's settings are, what
/// each control does, and what Open makes. Open itself opens a window, so it's left to Leah's hand tests.
@MainActor
struct RawDevelopTests {
    private static let photo = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appending(path: "../../TestImages/Stage 12/Test Camera.dng").standardized

    private let developer: RawDeveloper

    init() throws {
        developer = try RawDeveloper(url: Self.photo)
    }

    private func pixels(_ buffer: PixelBuffer) -> [Pixel] {
        (0..<buffer.height).flatMap { y in (0..<buffer.width).map { x in buffer[x, y] } }
    }

    private func luma(_ pixel: Pixel) -> Double {
        let r = 0.2126 * Double(pixel.r), g = 0.7152 * Double(pixel.g), b = 0.0722 * Double(pixel.b)
        return r + g + b
    }

    /// The average of each channel, 0...255.
    private func average(_ buffer: PixelBuffer) -> (r: Double, g: Double, b: Double) {
        var r = 0, g = 0, b = 0
        for pixel in pixels(buffer) { r += Int(pixel.r); g += Int(pixel.g); b += Int(pixel.b) }
        let count = Double(buffer.width * buffer.height)
        return (Double(r) / count, Double(g) / count, Double(b) / count)
    }

    private func brightness(_ buffer: PixelBuffer) -> Double {
        let (r, g, b) = average(buffer)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    /// How far the brightness spreads around its average: higher for more contrast.
    private func spread(_ buffer: PixelBuffer) -> Double {
        let mean = brightness(buffer)
        var total = 0.0
        for pixel in pixels(buffer) { total += (luma(pixel) - mean) * (luma(pixel) - mean) }
        return (total / Double(buffer.width * buffer.height)).squareRoot()
    }

    private func developed(_ change: (inout DevelopSettings) -> Void = { _ in }) throws -> PixelBuffer {
        var settings = developer.cameraDefaults
        change(&settings)
        return try developer.develop(settings).activeLayer.buffer
    }

    @Test func onlyRAWFilesGoThroughDevelop() {
        #expect(RawDeveloper.isRAW(Self.photo))
        let screenshot = Self.photo.deletingLastPathComponent().appending(path: "../Help/Sample Screenshot.png").standardized
        #expect(FileManager.default.fileExists(atPath: screenshot.path))
        #expect(!RawDeveloper.isRAW(screenshot))
    }

    @Test func itStartsFromTheCamerasOwnSettings() {
        #expect(developer.size == IntSize(width: 600, height: 400))
        let camera = developer.cameraDefaults
        // White balance comes from the file, not Develop's neutral 6500 K.
        #expect(camera.temperature != DevelopSettings().temperature && camera.temperature > 2000 && camera.temperature < 50000)
        #expect(camera.exposure == 0 && camera.highlights == 0 && camera.shadows == 0 && camera.contrast == 0)
        // A control the camera can't use stays off.
        if !developer.support.noiseReduction { #expect(camera.noiseReduction == 0) }
        if !developer.support.sharpness { #expect(camera.sharpness == 0) }
        if !developer.support.lensCorrection { #expect(!camera.lensCorrection) }
    }

    @Test func openMakesOneOpaqueDisplayP3LayerWithTheCameraDetails() throws {
        let canvas = try developer.develop(developer.cameraDefaults)
        #expect(canvas.size == developer.size)
        #expect(canvas.layers.count == 1 && canvas.activeLayer.name == "Background")
        #expect(canvas.colorSpace.name == Canvas.defaultColorSpace.name)
        #expect(!canvas.hasTransparentBackground)
        #expect(canvas.cameraDetails == developer.cameraDetails)
        let buffer = canvas.activeLayer.buffer
        #expect(pixels(buffer).allSatisfy { $0.a == 255 })
        let brightness = brightness(buffer)
        #expect(brightness > 10 && brightness < 245, "a picture, not a blank page")
    }

    @Test func exposureBrightensAndDarkens() throws {
        let plain = brightness(try developed())
        #expect(brightness(try developed { $0.exposure = 1 }) > plain + 10)
        #expect(brightness(try developed { $0.exposure = -1 }) < plain - 10)
    }

    @Test func aWarmerTemperatureMakesItYellowerAndTintMakesItMagenta() throws {
        let plain = average(try developed())
        let warmer = average(try developed { $0.temperature += 2000 })
        #expect(warmer.r - warmer.b > plain.r - plain.b + 5)
        let magenta = average(try developed { $0.tint = 60 })
        #expect((magenta.r + magenta.b) / 2 - magenta.g > (plain.r + plain.b) / 2 - plain.g + 3)
    }

    @Test func contrastSpreadsTheTonesAndLoweringItGathersThem() throws {
        let plain = spread(try developed())
        #expect(spread(try developed { $0.contrast = 100 }) > plain + 2)
        #expect(spread(try developed { $0.contrast = -100 }) < plain - 2)
    }

    @Test func shadowsLiftTheDarkAndHighlightsBringDownTheBright() throws {
        let plain = brightness(try developed())
        #expect(brightness(try developed { $0.shadows = 100 }) > plain + 2)
        #expect(brightness(try developed { $0.highlights = -100 }) < plain - 2)
    }

    @Test func thePreviewFitsItsSizeAndLooksLikeTheDevelopedPhoto() throws {
        let preview = try #require(developer.preview(developer.cameraDefaults, maxSide: 300))
        #expect(preview.width == 300 && preview.height == 200)
        let small = try ImageCodec.decode(preview).buffer
        let full = try developed()
        #expect(abs(brightness(small) - brightness(full)) < 3)
        // Never larger than the photo itself.
        let whole = try #require(developer.preview(developer.cameraDefaults, maxSide: 5000))
        #expect(whole.width == 600 && whole.height == 400)
    }

    @Test func theWindowsSessionPreviewsChangesAndResetsToTheCamera() async throws {
        let session = DevelopSession(developer: developer)
        #expect(session.settings == developer.cameraDefaults)
        session.refreshPreview()
        for _ in 0..<500 where session.preview == nil { try await Task.sleep(for: .milliseconds(10)) }
        let first = try #require(session.preview)
        #expect(max(first.width, first.height) <= 1600)
        session.settings.exposure = 1.5
        for _ in 0..<500 where session.preview === first { try await Task.sleep(for: .milliseconds(10)) }
        #expect(session.preview !== first, "changing a control redraws the preview")
        session.resetToCamera()
        #expect(session.settings == developer.cameraDefaults)
    }

    @Test func afterCancelThePreviewIsNoLongerReplaced() async throws {
        let session = DevelopSession(developer: developer)
        session.cancel()
        session.refreshPreview()
        try await Task.sleep(for: .milliseconds(400))
        #expect(session.preview == nil)
    }
}
