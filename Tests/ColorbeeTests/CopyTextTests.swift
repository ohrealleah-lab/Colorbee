import ColorbeeCore
import Testing
@testable import Colorbee

/// Copy Text (FR-10.4). The clipboard is a stand-in here, so the tests never touch the real one.
@MainActor
struct CopyTextTests {
    /// A change while the text is read (a redaction, say) means the old text isn't copied after it (review N, finding 3).
    @Test func aChangeWhileReadingCopiesNothing() async throws {
        let editor = makeEditor()
        var copied: [String] = []
        editor.copyText { text in
            copied.append(text)
            return 0
        }
        // Reading runs after this, so the stroke lands first, as a redaction made while "Reading text…" shows.
        editor.selectTool(.pencil)
        editor.stroke(wobblyPath)
        for _ in 0..<400 where editor.isReadingText { try await Task.sleep(for: .milliseconds(5)) }
        #expect(!editor.isReadingText)
        #expect(copied.isEmpty)
        #expect(editor.notice?.text == "The image changed while reading, so nothing was copied")
    }
}
