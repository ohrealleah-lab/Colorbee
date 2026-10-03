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

    /// Opens `canvas` as a new untitled document in its own window (Paste into New Image).
    static func open(_ canvas: ColorbeeCore.Canvas) {
        let document = ImageDocument()
        document.editor = Editor(canvas: canvas)
        document.fileType = UTType.png.identifier
        NSDocumentController.shared.addDocument(document)
        document.makeWindowControllers()
        document.showWindows()
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
        // The copy is taken here, on the main thread, so the encoding can run in the background (NFR-6).
        let snapshot = MainActor.assumeIsolated { editor?.saveSnapshot() }
        snapshotLock.withLock { pendingSnapshot = snapshot }
        super.save(to: url, ofType: typeName, for: saveOperation) { [weak self] error in
            // Let the copy go once its save is done, unless a newer save has replaced it.
            self?.snapshotLock.withLock {
                if self?.pendingSnapshot?.canvas === snapshot?.canvas { self?.pendingSnapshot = nil }
            }
            if error == nil, explicit, let snapshot {
                Task { @MainActor in self?.editor?.markSaved(snapshot) }
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

    /// The copy being saved. A newer save replaces it, which is fine since it's newer content.
    nonisolated private let snapshotLock = NSLock()
    nonisolated(unsafe) private var pendingSnapshot: SaveSnapshot?

    nonisolated override func canAsynchronouslyWrite(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType) -> Bool {
        true
    }

    /// Called on a background thread for saves (see `canAsynchronouslyWrite`), so it touches only the snapshot.
    nonisolated override func data(ofType typeName: String) throws -> Data {
        var snapshot = snapshotLock.withLock { pendingSnapshot }
        if snapshot == nil, Thread.isMainThread {
            snapshot = MainActor.assumeIsolated { editor?.saveSnapshot() }
        }
        guard let snapshot else { throw CocoaError(.fileWriteUnknown) }
        unblockUserInteraction()
        if UTType(typeName)?.conforms(to: .colorbeeProject) == true {
            return try snapshot.encodedProject()
        }
        guard let format = UTType(typeName).flatMap(ImageFileFormat.init(type:)) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return try snapshot.encoded(as: format)
    }

    // MARK: Share, desktop picture, print (FR-11.5)

    @IBAction func shareDocument(_ sender: Any?) {
        guard let editor, let view = windowForSheet?.contentView else { return }
        do {
            let folder = FileManager.default.temporaryDirectory.appending(path: "Colorbee Share \(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appending(path: "\((displayName as NSString).deletingPathExtension).png")
            try editor.flattenedPNG().write(to: url)
            let picker = NSSharingServicePicker(items: [url])
            picker.show(relativeTo: NSRect(x: view.bounds.midX, y: view.bounds.maxY - 1, width: 1, height: 1), of: view, preferredEdge: .minY)
        } catch {
            presentError(error)
        }
    }

    /// Saves a PNG copy in Application Support (the desktop needs a file that stays put) and shows it on every screen.
    @IBAction func setDesktopPicture(_ sender: Any?) {
        guard let editor else { return }
        do {
            let folder = URL.applicationSupportDirectory.appending(path: "Colorbee/Desktop Pictures", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).replacingOccurrences(of: ":", with: ".")
            let url = folder.appending(path: "\((displayName as NSString).deletingPathExtension) \(stamp).png")
            try editor.flattenedPNG().write(to: url)
            for screen in NSScreen.screens {
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
            }
        } catch {
            presentError(error)
        }
    }

    /// Prints the combined image, scaled down to fit the page and centered.
    override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
        guard let editor, let image = NSImage(data: try editor.flattenedPNG()) else { throw CocoaError(.fileReadUnknown) }
        let view = NSImageView(frame: NSRect(origin: .zero, size: image.size))
        view.image = image
        view.imageScaling = .scaleProportionallyUpOrDown
        let info = printInfo.copy() as! NSPrintInfo
        info.dictionary().addEntries(from: printSettings)
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = true
        return NSPrintOperation(view: view, printInfo: info)
    }

    // MARK: Export

    @IBAction func exportPreset(_ sender: Any?) {
        guard let editor, let window = windowForSheet,
              let tag = (sender as? NSMenuItem)?.tag, ExportPresetStore.shared.presets.indices.contains(tag) else { return }
        let preset = ExportPresetStore.shared.presets[tag]
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        let base = (displayName as NSString).deletingPathExtension
        let size = preset.targetSize(for: editor.canvasSize)
        panel.nameFieldStringValue = "\(base) \(size.width)x\(size.height).png"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.export(editor.saveSnapshot(), to: url) { try $0.encoded(using: preset) }
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
            let format = options.format, quality = options.quality
            self?.export(editor.saveSnapshot(), to: url) { try $0.encoded(as: format, quality: quality) }
        }
    }

    /// Encodes and writes in the background, so a large image doesn't stall the window (NFR-6).
    private func export(_ snapshot: SaveSnapshot, to url: URL, encode: @escaping @Sendable (SaveSnapshot) throws -> Data) {
        Task.detached(priority: .userInitiated) {
            do {
                try encode(snapshot).write(to: url, options: .atomic)
            } catch {
                await MainActor.run { [weak self] in _ = self?.presentError(error) }
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
