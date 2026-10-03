import AppKit
import ColorbeeCore
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// The native format with layers (FR-8.5).
    static let colorbeeProject = UTType(exportedAs: "com.leah.colorbee.colorproj")
}

final class ImageDocument: NSDocument {
    private var editor: Editor?
    /// An image that gained layers becomes an unsaved project so the original file is never flattened;
    /// this keeps its name in the title until the project is saved somewhere.
    private var projectName: String?

    override init() {
        super.init()
        hasUndoManager = false
    }

    override class var autosavesInPlace: Bool {
        true
    }

    var canvasSize: IntSize? { editor?.canvasSize }

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
            self?.becomeProjectIfLayered()
        }
        if editor.canvas.layers.count > 1 { editor.isSidebarOpen = true }
        addWindowController(DocumentWindowController(editor: editor))
    }

    override func read(from data: Data, ofType typeName: String) throws {
        if UTType(typeName)?.conforms(to: .colorbeeProject) == true {
            let canvas = try ProjectFile.decode(data)
            MainActor.assumeIsolated { editor = Editor(canvas: canvas) }
            return
        }
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

    override func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
                       completionHandler: @escaping (Error?) -> Void) {
        let explicit = saveOperation == .saveOperation || saveOperation == .saveAsOperation
        super.save(to: url, ofType: typeName, for: saveOperation) { [weak self] error in
            if error == nil, explicit {
                Task { @MainActor in self?.editor?.markSaved() }
            }
            completionHandler(error)
        }
    }

    /// Saving and exporting wait until an open effect is applied or cancelled.
    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if editor?.activeEffect != nil { return false }
        return super.validateUserInterfaceItem(item)
    }

    /// Once an image has layers (or an adjustment layer), saving keeps it as a .colorproj: an image file
    /// would flatten the layers. A file that was opened is left untouched; the next save asks where to put
    /// the project (decided by Leah, FRD §23).
    private func becomeProjectIfLayered() {
        guard let editor, editor.isLayered, let fileType, UTType(fileType)?.conforms(to: .colorbeeProject) != true else { return }
        if let fileURL {
            projectName = fileURL.deletingPathExtension().lastPathComponent
            self.fileURL = nil
        }
        self.fileType = UTType.colorbeeProject.identifier
        windowControllers.forEach { $0.synchronizeWindowTitleWithDocumentName() }
    }

    override var displayName: String! {
        get { fileURL == nil ? projectName ?? super.displayName : super.displayName }
        set { super.displayName = newValue }
    }

    /// A layered image can only be saved as a project; flat copies come from Export.
    override func writableTypes(for saveOperation: NSDocument.SaveOperationType) -> [String] {
        // AppKit asks on the main thread while setting up a save panel.
        let layered = MainActor.assumeIsolated { editor?.isLayered == true }
        if layered { return [UTType.colorbeeProject.identifier] }
        return super.writableTypes(for: saveOperation)
    }

    override func data(ofType typeName: String) throws -> Data {
        if UTType(typeName)?.conforms(to: .colorbeeProject) == true {
            guard let editor else { throw CocoaError(.fileWriteUnknown) }
            return try editor.encodedProject()
        }
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
