import AppKit
import SwiftUI

final class DocumentWindowController: NSWindowController {
    private let editor: Editor
    private let canvasView: CanvasView

    init(editor: Editor) {
        self.editor = editor
        canvasView = CanvasView(editor: editor)

        let window = DocumentWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 800, height: 600)
        window.editor = editor
        window.contentView = NSHostingView(rootView: DocumentView(editor: editor, canvasView: canvasView))
        window.center()
        super.init(window: window)

        window.makeFirstResponder(canvasView)
        canvasView.onFirstFrame = { [weak window, weak canvasView, weak editor] in
            guard let window, let canvasView, let editor else { return }
            Benchmark.startIfRequested(window: window, canvasView: canvasView, editor: editor)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}
