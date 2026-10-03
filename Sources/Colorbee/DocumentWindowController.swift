import AppKit
import SwiftUI

final class DocumentWindowController: NSWindowController {
    private let editor: Editor
    private let canvasView: CanvasView

    init(editor: Editor) {
        self.editor = editor
        canvasView = CanvasView(editor: editor)

        let window = DocumentWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1512, height: 982),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 800, height: 600)
        window.editor = editor
        let hostingView = NSHostingView(rootView: DocumentView(editor: editor, canvasView: canvasView))
        // The SwiftUI toolbar becomes the window's own toolbar, so its groups get Liquid Glass.
        hostingView.sceneBridgingOptions = [.toolbars]
        window.contentView = hostingView
        window.toolbarStyle = .unified
        window.center()
        super.init(window: window)

        window.makeFirstResponder(canvasView)
        trackSubtitle()
        canvasView.onFirstFrame = { [weak window, weak canvasView, weak editor] in
            guard let window, let canvasView, let editor else { return }
            Benchmark.startIfRequested(window: window, canvasView: canvasView, editor: editor)
            Snapshot.startIfRequested(window: window, editor: editor)
        }
    }

    /// Shows the canvas size under the title, as in the mockups.
    private func trackSubtitle() {
        withObservationTracking {
            window?.subtitle = "\(editor.canvasSize.width) × \(editor.canvasSize.height)"
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackSubtitle() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}
