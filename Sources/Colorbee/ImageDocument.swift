import AppKit
import ColorbeeCore
import SwiftUI
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
        guard let editor, let format = UTType(typeName).flatMap(ImageFileFormat.init(type:)) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return try editor.encoded(as: format)
    }

    // MARK: Export

    @IBAction func exportPreset(_ sender: Any?) {
        guard let editor, let window = windowForSheet,
              let tag = (sender as? NSMenuItem)?.tag, ExportPreset.defaults.indices.contains(tag) else { return }
        let preset = ExportPreset.defaults[tag]
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        let base = (displayName as NSString).deletingPathExtension
        let size = preset.targetSize(for: editor.canvasSize)
        panel.nameFieldStringValue = "\(base) \(size.width)x\(size.height).png"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try editor.encoded(using: preset).write(to: url, options: .atomic)
            } catch {
                self?.presentError(error)
            }
        }
    }

    @IBAction func exportDocument(_ sender: Any?) {
        guard let editor, let window = windowForSheet else { return }
        let options = ExportOptions()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [options.format.type]
        panel.nameFieldStringValue = (displayName as NSString).deletingPathExtension
        panel.accessoryView = NSHostingView(rootView: ExportAccessory(options: options) { format in
            panel.allowedContentTypes = [format.type]
        })
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try editor.encoded(as: options.format, quality: options.quality).write(to: url, options: .atomic)
            } catch {
                self?.presentError(error)
            }
        }
    }
}

@MainActor
@Observable
private final class ExportOptions {
    var format: ImageFileFormat = .png
    var quality = 0.9
}

private struct ExportAccessory: View {
    @Bindable var options: ExportOptions
    let formatChanged: (ImageFileFormat) -> Void

    var body: some View {
        Form {
            Picker("Format", selection: $options.format) {
                ForEach(ImageFileFormat.allCases.filter(\.canWrite), id: \.self) { format in
                    Text(format.name).tag(format)
                }
            }
            if options.format.isLossy {
                LabeledContent("Quality") {
                    HStack {
                        Slider(value: $options.quality, in: 0.01...1)
                            .frame(width: 180)
                        Text("\(Int((options.quality * 100).rounded()))")
                            .monospacedDigit()
                            .frame(width: 30, alignment: .trailing)
                    }
                }
            }
            if !options.format.supportsTransparency {
                Text("Transparent areas are filled with Color 2.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 360)
        .onChange(of: options.format) { formatChanged(options.format) }
    }
}
