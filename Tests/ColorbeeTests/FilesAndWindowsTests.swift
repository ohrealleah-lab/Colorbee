import ColorbeeCore
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Colorbee

/// Stage 34c (§23, 2026-11-20): a picture goes back to its file once it's one plain layer again, and new windows start
/// with the tool settings last used. Nothing here saves a preference: the store has no file.
@MainActor
@Suite(.serialized)
struct FilesAndWindowsTests {
    // MARK: Back to its file

    /// A PNG on disk, opened as a document, without a window.
    private func openedPNG() throws -> (ImageDocument, Editor, URL) {
        let url = FileManager.default.temporaryDirectory.appending(path: "Colorbee 34c \(UUID().uuidString).png")
        let picture = PixelBuffer(width: 12, height: 8, fill: Pixel(r: 40, g: 120, b: 200))
        try ImageCodec.encodePNG(picture, colorSpace: Canvas.defaultColorSpace).write(to: url)
        let document = ImageDocument()
        try document.read(from: Data(contentsOf: url), ofType: UTType.png.identifier)
        document.fileURL = url
        document.fileType = UTType.png.identifier
        return (document, try #require(document.editor), url)
    }

    @Test func undoingTheNewLayerGoesBackToTheFile() throws {
        let (document, editor, url) = try openedPNG()
        defer { try? FileManager.default.removeItem(at: url) }
        editor.addLayer()
        document.followLayers()
        #expect(document.fileURL == nil && document.fileType == UTType.colorbeeProject.identifier)
        #expect(document.originalFile?.url == url)

        editor.undo()
        document.followLayers()
        #expect(document.fileURL == url && document.fileType == UTType.png.identifier)

        // Flatten does it too.
        editor.addLayer()
        document.followLayers()
        editor.flatten()
        document.followLayers()
        #expect(document.fileURL == url && document.fileType == UTType.png.identifier)
    }

    @Test func aFileThatWentAwayLeavesItAProject() throws {
        let (document, editor, url) = try openedPNG()
        editor.addLayer()
        document.followLayers()
        try FileManager.default.removeItem(at: url)
        editor.undo()
        document.followLayers()
        #expect(document.fileURL == nil && document.fileType == UTType.colorbeeProject.identifier)
    }

    @Test func onlyAnUnsavedPlainPictureWithItsFileGoesBack() {
        let original = OriginalFile(url: URL(filePath: "/tmp/a.png"), type: UTType.png.identifier, modified: nil)
        #expect(original.canReturn(isLayered: false, savedAsProject: false, exists: true))
        #expect(!original.canReturn(isLayered: true, savedAsProject: false, exists: true))
        #expect(!original.canReturn(isLayered: false, savedAsProject: true, exists: true))
        #expect(!original.canReturn(isLayered: false, savedAsProject: false, exists: false))
    }

    // MARK: Tool settings carry over

    private func changedSettings() -> ToolSettings {
        var settings = ToolSettings()
        settings.color1 = Pixel(r: 220, g: 20, b: 30, a: 200)
        settings.color2 = Pixel(r: 1, g: 2, b: 3)
        settings.brush = .airbrush
        settings.brushDiameter = 20
        settings.eraserSize = 30
        settings.shapeKind = .ellipse
        settings.shapeOutline = nil
        settings.shapeFill = .solid
        settings.textStyle.fontSize = 36
        settings.textStyle.bold = true
        settings.redactTreatment = .pixelate
        settings.retouchKind = .cloneStamp
        settings.retouchSizes = [.cloneStamp: 70, .blur: 12]
        settings.toneRange = .highlights
        settings.wandMode = .object
        settings.gradientMode = GradientMode.allCases.last!
        settings.eyedropperSampleSize = 5
        return settings
    }

    @Test func settingsKeepEveryValueThroughTheFile() throws {
        let settings = changedSettings()
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(ToolSettings.self, from: data) == settings)
        // A file from another version: what's missing or unknown keeps its default, the rest is kept.
        let partial = Data(#"{"brushDiameter": 14, "brush": "no such brush", "shapeKind": 7}"#.utf8)
        let decoded = try JSONDecoder().decode(ToolSettings.self, from: partial)
        #expect(decoded.brushDiameter == 14 && decoded.brush == ToolSettings().brush && decoded.shapeKind == ToolSettings().shapeKind)
    }

    @Test func aNewWindowTakesTheSettingsButNotTheToolOrSymmetry() async throws {
        let store = ToolSettingsStore(file: nil)
        let first = makeEditor()
        store.start(first)
        first.selectTool(.brush)
        first.symmetry = SymmetryMode.allCases.last!
        first.toolSettings = changedSettings()
        // The store hears of changes a moment later, as the window changes them.
        for _ in 0..<50 where store.last != changedSettings() { try await Task.sleep(for: .milliseconds(10)) }
        #expect(store.last == changedSettings())

        let second = makeEditor()
        store.start(second)
        #expect(second.toolSettings == changedSettings())
        #expect(second.tool == .rectangleSelect && second.symmetry == .off)
    }

    @Test func maskGraysAreNotCarried() throws {
        let store = ToolSettingsStore(file: nil)
        let editor = makeEditor()
        editor.color1 = Pixel(r: 200, g: 30, b: 30)
        store.note(editor)
        editor.addMask()
        #expect(editor.canvas.editsMask && editor.color1 != Pixel(r: 200, g: 30, b: 30))
        store.note(editor)
        #expect(store.last?.color1 == Pixel(r: 200, g: 30, b: 30))
    }
}
