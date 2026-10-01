import Testing
@testable import ColorbeeCore

struct ExportPresetTests {
    @Test func widthPresetKeepsTheAspectRatio() {
        let slack = ExportPreset.defaults[0]
        #expect(slack.targetSize(for: IntSize(width: 1520, height: 1000)) == IntSize(width: 760, height: 500))
    }

    @Test func neverEnlargesUnlessAllowed() {
        let preset = ExportPreset(name: "1920", size: .width(1920))
        #expect(preset.targetSize(for: IntSize(width: 800, height: 600)) == IntSize(width: 800, height: 600))
        #expect(preset.targetSize(for: IntSize(width: 800, height: 600), allowEnlarging: true) == IntSize(width: 1920, height: 1440))
    }

    @Test func squarePresetFitsTheLongerSide() {
        let square = ExportPreset(name: "Square", size: .fitSquare(1024))
        #expect(square.targetSize(for: IntSize(width: 2048, height: 1024)) == IntSize(width: 1024, height: 512))
        #expect(square.targetSize(for: IntSize(width: 1000, height: 4000)) == IntSize(width: 256, height: 1024))
    }

    @Test func pixelArtStaysSharp() {
        #expect(ExportPreset.resampling(for: IntSize(width: 32, height: 32)) == .nearestNeighbor)
        #expect(ExportPreset.resampling(for: IntSize(width: 1920, height: 1080)) == .smooth)
    }
}
