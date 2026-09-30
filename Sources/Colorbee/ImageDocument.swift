import AppKit
import ColorbeeCore
import UniformTypeIdentifiers

final class ImageDocument: NSDocument {
    private var editor: Editor?

    override init() {
        super.init()
        hasUndoManager = false
    }

    override class var autosavesInPlace: Bool {
        true
    }

    override func makeWindowControllers() {
        let editor = self.editor ?? Editor(canvas: Canvas(
            size: Benchmark.canvasSize ?? IntSize(width: 1920, height: 1080),
            colorSpace: Canvas.defaultColorSpace,
            background: .white
        ))
        self.editor = editor
        editor.onDocumentChange = { [weak self] change in
            switch change {
            case .done: self?.updateChangeCount(.changeDone)
            case .undone: self?.updateChangeCount(.changeUndone)
            case .redone: self?.updateChangeCount(.changeRedone)
            }
        }
        addWindowController(DocumentWindowController(editor: editor))
    }

    override func read(from data: Data, ofType typeName: String) throws {
        let decoded = try ImageCodec.decode(data)
        // AppKit reads on the main thread unless canConcurrentlyReadDocuments is overridden.
        MainActor.assumeIsolated {
            editor = Editor(canvas: Canvas(
                colorSpace: decoded.colorSpace,
                layers: [Layer(name: "Background", buffer: decoded.buffer)],
                hasTransparentBackground: decoded.buffer.hasTransparency
            ))
        }
    }

    override func data(ofType typeName: String) throws -> Data {
        guard let editor else { throw CocoaError(.fileWriteUnknown) }
        return try editor.flattenedPNG()
    }

    @IBAction func exportDocument(_ sender: Any?) {
        guard let editor, let window = windowForSheet else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = (displayName as NSString).deletingPathExtension + ".png"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try editor.flattenedPNG().write(to: url, options: .atomic)
            } catch {
                self?.presentError(error)
            }
        }
    }
}
