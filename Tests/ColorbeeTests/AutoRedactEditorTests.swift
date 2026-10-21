import ColorbeeCore
import Foundation
import Testing
@testable import Colorbee

/// Auto-Redact through the Editor (FR-9.3), on the made-up sample screenshot: reading, the review, Apply on every
/// layer and page as one step, and refusing when the image changed or a layer under a box is locked. Text is read on
/// this Mac, as in the app.
@MainActor
@Suite(.serialized)
struct AutoRedactEditorTests {
    private static let sample = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appending(path: "../../TestImages/Help/Sample Screenshot.png").standardized

    private func sampleEditor() throws -> Editor {
        let decoded = try ImageCodec.decode(Data(contentsOf: Self.sample))
        return Editor(canvas: Canvas(colorSpace: decoded.colorSpace, layers: [Layer(name: "Background", buffer: decoded.buffer)],
                                     hasTransparentBackground: false))
    }

    /// Starts Auto-Redact and waits until every page is read.
    private func read(_ editor: Editor) async throws -> AutoRedactSession {
        editor.beginAutoRedact()
        for _ in 0..<2000 where editor.autoRedact?.isReading == true { try await Task.sleep(for: .milliseconds(5)) }
        let session = try #require(editor.autoRedact)
        #expect(!session.isReading)
        #expect(session.failure == nil)
        return session
    }

    private func apply(_ editor: Editor) async throws {
        editor.applyAutoRedact()
        for _ in 0..<2000 where editor.autoRedact?.applying != nil { try await Task.sleep(for: .milliseconds(5)) }
    }

    private func everyPixel(of rect: IntRect, in buffer: PixelBuffer, is pixel: Pixel) -> Bool {
        (rect.minY..<rect.maxY).allSatisfy { y in (rect.minX..<rect.maxX).allSatisfy { x in buffer[x, y] == pixel } }
    }

    @Test func applyCoversEveryMatchOnEveryLayerAsOneStep() async throws {
        let editor = try sampleEditor()
        // A see-through layer with a mark over each found item: it must be covered there too.
        let overlay = Layer(name: "Notes", buffer: PixelBuffer(width: editor.canvas.size.width, height: editor.canvas.size.height))
        editor.canvas.insertLayer(overlay, at: 1)
        let session = try await read(editor)
        #expect(session.matches.count >= 2, "\(session.matches.map(\.text))")
        for match in session.matches { overlay.buffer.fill(Pixel(r: 255, g: 0, b: 0), in: IntRect(x: match.rect.minX, y: match.rect.minY, width: 2, height: 2)) }
        // Re-read, so the marks are part of what was read.
        editor.cancelAutoRedact()
        let fresh = try await read(editor)
        let before = editor.canvas.layers.map { $0.buffer.contentHash() }
        try await apply(editor)
        #expect(editor.autoRedact == nil)
        #expect(editor.stepNames.last == "Auto-Redact")
        #expect(editor.redactedSinceSave)
        let ink = editor.color1
        for match in fresh.selectedMatches {
            #expect(everyPixel(of: match.rect, in: editor.canvas.layers[0].buffer, is: ink), "\(match.text)")
            #expect(everyPixel(of: match.rect, in: overlay.buffer, is: ink), "\(match.text)")
        }
        editor.undo()
        #expect(editor.canvas.layers.map { $0.buffer.contentHash() } == before)
    }

    @Test func anItemKeptVisibleIsLeftAlone() async throws {
        let editor = try sampleEditor()
        let session = try await read(editor)
        let kept = try #require(session.matches.first)
        editor.setRedactionMatch(kept.id, included: false)
        let original = editor.canvas.activeLayer.buffer.pixels(in: kept.rect)
        try await apply(editor)
        #expect(editor.canvas.activeLayer.buffer.pixels(in: kept.rect) == original)
    }

    @Test func nothingIsRedactedIfTheImageChangedAfterReading() async throws {
        let editor = try sampleEditor()
        _ = try await read(editor)
        // A change made while the review is open (as another window's script or an undo could).
        let edit = editor.history.beginEdit("Change", on: editor.canvas)
        edit.willModify(IntRect(x: 0, y: 0, width: 4, height: 4), in: editor.canvas.activeLayer)
        editor.canvas.activeLayer.buffer.fill(.black, in: IntRect(x: 0, y: 0, width: 4, height: 4))
        editor.history.commit(edit)
        let before = editor.canvas.activeLayer.buffer.contentHash()
        try await apply(editor)
        #expect(editor.autoRedact?.problem?.contains("changed after it was read") == true)
        #expect(editor.canvas.activeLayer.buffer.contentHash() == before)
        editor.cancelAutoRedact()
    }

    @Test func nothingIsRedactedWithALockedLayerUnderABox() async throws {
        let editor = try sampleEditor()
        editor.setLayerLocked(true, at: 0)
        _ = try await read(editor)
        let before = editor.canvas.activeLayer.buffer.contentHash()
        try await apply(editor)
        #expect(editor.autoRedact?.problem?.contains("is locked") == true)
        #expect(editor.canvas.activeLayer.buffer.contentHash() == before)
        editor.cancelAutoRedact()
    }

    @Test func everyPageIsRedactedAndOneUndoBringsAllBack() async throws {
        let editor = try sampleEditor()
        editor.duplicatePage()
        #expect(editor.pageCount == 2)
        let session = try await read(editor)
        #expect(session.isMultiPage)
        let pageHashes = { (0..<2).map { index -> Int in
            editor.showPage(at: index)
            return editor.canvas.activeLayer.buffer.contentHash()
        } }
        let before = pageHashes()
        editor.showPage(at: 1)
        try await apply(editor)
        let after = pageHashes()
        #expect(after[0] != before[0] && after[1] != before[1])
        editor.undo()
        #expect(pageHashes() == before)
    }
}
