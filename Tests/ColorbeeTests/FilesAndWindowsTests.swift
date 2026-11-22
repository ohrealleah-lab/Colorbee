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
        settings.textStyle.curve = -40
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

    // MARK: Review round 13 (AI)

    /// Going back to the file removes the project's own autosave, so a relaunch can't bring it back under the file's
    /// name (review AI, finding 1).
    @Test func goingBackRemovesTheProjectsAutosave() throws {
        let (document, editor, url) = try openedPNG()
        defer { try? FileManager.default.removeItem(at: url) }
        editor.addLayer()
        document.followLayers()
        let autosave = FileManager.default.temporaryDirectory.appending(path: "Colorbee 34c autosave \(UUID().uuidString).colorproj")
        try Data([1, 2, 3]).write(to: autosave)
        defer { try? FileManager.default.removeItem(at: autosave) }
        document.autosavedContentsFileURL = autosave
        editor.undo()
        document.followLayers()
        #expect(document.fileURL == url && document.autosavedContentsFileURL == nil)
        #expect(!FileManager.default.fileExists(atPath: autosave.path))
    }

    /// A layered picture pointing at an image file, whatever its type says, becomes a project again rather than
    /// being written into the file (review AI, findings 1 and 4).
    @Test func aLayeredPicturePointingAtAnImageFileBecomesAProject() throws {
        let (document, editor, url) = try openedPNG()
        defer { try? FileManager.default.removeItem(at: url) }
        editor.addLayer()
        document.fileType = UTType.colorbeeProject.identifier
        document.followLayers()
        #expect(document.fileURL == nil && document.originalFile?.type == UTType.png.identifier)
    }

    /// A faded, hidden or blended layer is something only a project keeps (review AI, finding 2; Leah, 2026-11-21).
    @Test func aFadedHiddenOrBlendedLayerKeepsItAProject() throws {
        let (document, editor, url) = try openedPNG()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(!editor.isLayered)
        editor.canvas.layers[0].opacity = 0.5
        #expect(editor.isLayered)
        editor.canvas.layers[0].opacity = 1
        editor.canvas.layers[0].isVisible = false
        #expect(editor.isLayered)
        editor.canvas.layers[0].isVisible = true
        editor.canvas.layers[0].blendMode = BlendMode.allCases.first { $0 != .normal }!
        #expect(editor.isLayered)
        document.followLayers()
        #expect(document.fileURL == nil)
    }

    /// An unsaved redaction survives a relaunch, so going back to the file still warns about its earlier versions
    /// (review AI, finding 3).
    @Test func anUnsavedRedactionIsRememberedAcrossARelaunch() throws {
        let (document, editor, url) = try openedPNG()
        defer { try? FileManager.default.removeItem(at: url) }
        editor.addLayer()
        document.followLayers()
        editor.redactedSinceSave = true
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        document.encodeRestorableState(with: archiver)
        archiver.finishEncoding()
        editor.redactedSinceSave = false
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: archiver.encodedData)
        document.restoreState(with: unarchiver)
        #expect(editor.redactedSinceSave)
        editor.undo()
        document.followLayers()
        #expect(document.fileURL == url && document.wantsRedactionCheckBeforeClosing)
    }

    /// The disk is asked only when the picture could go back, and a file open in another window keeps it a project
    /// (review AI, findings 5 and 8).
    @Test func theDiskIsAskedOnlyWhenItCouldGoBack() {
        let original = OriginalFile(url: URL(filePath: "/tmp/a.png"), type: UTType.png.identifier, modified: nil)
        var asked = 0
        func exists() -> Bool { asked += 1; return true }
        // Worked out before #expect, which evaluates a call's arguments itself to show them.
        let layered = original.canReturn(isLayered: true, savedAsProject: false, exists: exists())
        let saved = original.canReturn(isLayered: false, savedAsProject: true, exists: exists())
        let elsewhere = original.canReturn(isLayered: false, savedAsProject: false, exists: exists(), openElsewhere: true)
        #expect(!layered && !saved && !elsewhere && asked == 0)
        let plain = original.canReturn(isLayered: false, savedAsProject: false, exists: exists())
        #expect(plain && asked == 1)
    }

    /// A damaged or hand-edited settings file is kept within what each control allows (review AI, finding 6), and a
    /// text style missing an option keeps the rest (finding 10).
    @Test func damagedSettingsAreKeptInRange() throws {
        let json = #"{"brushDiameter": 1e20, "eraserSize": 0, "badgeDiameter": 1000000, "fillTolerance": 7, "wandTolerance": -3, "#
            + #""eyedropperSampleSize": -5, "shapeLineWidth": -2, "redactBrushSize": 99999, "retouchStrength": 0, "#
            + #""retouchSizes": {"cloneStamp": -3, "blur": 40}, "#
            + #""textStyle": {"fontFamily": "Georgia", "fontSize": 0, "bold": true, "alignment": "sideways"}}"#
        let settings = try JSONDecoder().decode(ToolSettings.self, from: Data(json.utf8))
        let defaults = ToolSettings()
        #expect(settings.brushDiameter == 50 && settings.eraserSize == defaults.eraserSize && settings.badgeDiameter == 128)
        #expect(settings.fillTolerance == 1 && settings.wandTolerance == 0 && settings.eyedropperSampleSize == defaults.eyedropperSampleSize)
        #expect(settings.shapeLineWidth == 1 && settings.redactBrushSize == 300 && settings.retouchStrength == 0.01)
        #expect(settings.retouchSizes == [.blur: 40])
        #expect(settings.textStyle.fontFamily == "Georgia" && settings.textStyle.fontSize == 6 && settings.textStyle.bold)
        #expect(settings.textStyle.alignment == defaults.textStyle.alignment)
        // A window started with them can read every tool's size.
        let store = ToolSettingsStore(file: nil)
        let editor = makeEditor()
        editor.toolSettings = settings
        store.note(editor)
        for tool in Tool.allCases {
            editor.selectTool(tool)
            if let size = editor.toolSize { #expect(Editor.sizeRange(for: tool).contains(size)) }
        }
    }

    /// Colors picked after Undo of Add Mask aren't turned gray, and the real colors are carried after leaving a mask
    /// until a real color is picked (review AI, finding 7; Leah, 2026-11-21).
    @Test func realColorsAreCarriedAfterAMask() {
        let red = Pixel(r: 200, g: 30, b: 30), blue = Pixel(r: 20, g: 40, b: 220)
        let store = ToolSettingsStore(file: nil)
        let editor = makeEditor()
        editor.color1 = red
        editor.addMask()
        editor.paint(onMask: false, at: editor.canvas.activeLayerIndex)
        #expect(editor.color1 != red)
        store.note(editor)
        #expect(store.last?.color1 == red)

        editor.color1 = blue
        store.note(editor)
        #expect(store.last?.color1 == blue)

        let other = makeEditor()
        other.addMask()
        other.undo()
        other.color1 = blue
        #expect(other.color1 == blue)
    }
}
