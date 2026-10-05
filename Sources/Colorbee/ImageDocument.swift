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
    private var projectName: String? {
        didSet { invalidateRestorableState() }
    }
    /// The file can't be saved back without losing frames or precision, so it opens as an untitled copy
    /// (Leah; review J, finding 2).
    private var opensAsCopy = false

    override init() {
        super.init()
        hasUndoManager = false
    }

    /// Opens `canvas` as a new untitled document in its own window (Paste into New Image, a drop, or a developed RAW
    /// photo, titled `name`).
    static func open(_ canvas: ColorbeeCore.Canvas, clipboardSource: ClipboardHistory.Item.ID? = nil, name: String? = nil) {
        let document = ImageDocument()
        document.projectName = name
        let editor = Editor(canvas: canvas)
        editor.noteClipboardSource(clipboardSource)
        document.editor = editor
        document.fileType = UTType.png.identifier
        NSDocumentController.shared.addDocument(document)
        document.makeWindowControllers()
        // Unsaved from the start, so closing asks and autosave keeps it safe (FR-12; review J, finding 6).
        document.updateChangeCount(.changeDone)
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
        if opensAsCopy, let fileURL {
            opensAsCopy = false
            projectName = fileURL.deletingPathExtension().lastPathComponent
            self.fileURL = nil
            fileType = editor.isLayered ? UTType.colorbeeProject.identifier : UTType.png.identifier
            updateChangeCount(.changeDone)
        }
    }

    /// Puts a new window in place of the old ones (same frame and tab), for a new editor.
    private func replaceWindows() {
        let old = windowControllers
        let oldWindow = old.first?.window
        makeWindowControllers()
        if let oldWindow, let newWindow = windowControllers.last?.window {
            newWindow.setFrame(oldWindow.frame, display: false)
            if oldWindow.tabbedWindows != nil { oldWindow.addTabbedWindow(newWindow, ordered: .above) }
        }
        for controller in old {
            removeWindowController(controller)
            controller.close()
        }
        showWindows()
    }

    override func read(from data: Data, ofType typeName: String) throws {
        let type = UTType(typeName)
        if type?.conforms(to: .colorbeeProject) == true {
            // Every page but the shown one stays parked: its pixels are decoded when it's shown (FR-11.6).
            let (stored, current) = try ProjectFile.storedPages(data)
            try open(stored, showing: current)
            return
        }
        if type?.conforms(to: .pdf) == true {
            // Every page, as pixels, at the resolution in Settings (FR-11.6). A PDF can't be saved back.
            let resolution = Self.pdfResolution
            let stored = try ProjectFile.storedPages(count: try PDFPages.pageCount(data)) { index in
                try PDFPages.render(data, page: index, resolution: resolution)
            }
            opensAsCopy = true
            try open(stored, showing: 0)
            return
        }
        let decoded = try ImageCodec.decode(data)
        // A format Colorbee can't write (WebP, or a RAW file reaching here without the Develop window) opens as a copy
        // too, so saving asks where (review J, WebP check).
        let writable = type.flatMap(ImageFileFormat.init(type:))?.canWrite ?? (type?.conforms(to: .rawImage) != true)
        opensAsCopy = decoded.opensAsCopy || !writable
        if decoded.frameCount > 1 {
            // Animated GIFs and multi-page TIFFs: every frame as a page (FR-11.6).
            let stored = try ProjectFile.storedPages(count: decoded.frameCount) { index in
                let frame = try ImageCodec.decode(data, frame: index)
                return (Canvas(colorSpace: frame.colorSpace, layers: [Layer(name: "Background", buffer: frame.buffer)],
                               hasTransparentBackground: frame.buffer.hasTransparency), Page.defaultResolution)
            }
            try open(stored, showing: 0)
            return
        }
        // AppKit reads on the main thread unless canConcurrentlyReadDocuments is overridden.
        MainActor.assumeIsolated {
            let canvas = Canvas(
                colorSpace: decoded.colorSpace,
                layers: [Layer(name: "Background", buffer: decoded.buffer)],
                hasTransparentBackground: decoded.buffer.hasTransparency
            )
            canvas.cameraDetails = decoded.cameraDetails
            editor = Editor(canvas: canvas)
        }
    }

    /// The PDF resolution set in Settings, in pixels per inch.
    nonisolated static var pdfResolution: Double {
        let stored = UserDefaults.standard.double(forKey: "PDFResolution")
        return [150, 200, 300].contains(stored) ? stored : 200
    }

    /// Makes the document's pages from stored ones, all parked but the one shown.
    private func open(_ stored: [ProjectFile.StoredPage], showing current: Int) throws {
        let pages = try stored.map { try Page(stored: $0, history: Editor.makeHistory()) }
        try pages[current].unpark()
        MainActor.assumeIsolated { editor = Editor(pages: PageStack(pages: pages, currentIndex: current)) }
    }

    override func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
                       completionHandler: @escaping (Error?) -> Void) {
        let explicit = saveOperation == .saveOperation || saveOperation == .saveAsOperation
        // A format chosen in the Save panel for an image without layers is remembered for the next new image.
        if saveOperation == .saveAsOperation || (saveOperation == .saveOperation && fileURL == nil),
           MainActor.assumeIsolated({ editor?.isLayered != true }) {
            UserDefaults.standard.set(typeName, forKey: Self.lastSaveFormatKey)
        }
        // The copy is taken here, on the main thread, so the encoding can run in the background (NFR-6).
        let snapshot = MainActor.assumeIsolated { editor?.saveSnapshot() }
        snapshotLock.withLock { pendingSnapshot = snapshot }
        super.save(to: url, ofType: typeName, for: saveOperation) { [weak self] error in
            // Let the copy go once its save is done, unless a newer save has replaced it. Writes don't overlap,
            // so the copy this save encoded is the one in the file; a newer save's copy may have replaced
            // this save's own before it was written (review B, finding 8).
            let written = self?.snapshotLock.withLock {
                if self?.pendingSnapshot?.canvas === snapshot?.canvas { self?.pendingSnapshot = nil }
                defer { self?.encodedSnapshot = nil }
                return self?.encodedSnapshot ?? snapshot
            } ?? nil
            if error == nil, explicit, let written {
                Task { @MainActor in
                    self?.editor?.markSaved(written)
                    self?.warnAboutEarlierVersions(of: url) {}
                }
            }
            completionHandler(error)
        }
    }

    /// After a redaction is saved, the file's earlier versions (File ▸ Revert To) still show what was redacted.
    /// Colorbee says so and offers to remove them; nothing is removed without asking (Leah; review H, finding 1).
    /// `then` runs once the person has answered, or at once if there's nothing to say.
    private func warnAboutEarlierVersions(of url: URL, then done: @escaping () -> Void) {
        guard let editor, editor.redactedSinceSave else { return done() }
        editor.redactedSinceSave = false
        guard let versions = NSFileVersion.otherVersionsOfItem(at: url), !versions.isEmpty, let window = windowForSheet else { return done() }
        let alert = NSAlert()
        alert.messageText = "Earlier versions of this file still show what you redacted."
        alert.informativeText = "File ▸ Revert To can bring them back on this Mac, and Undo can take the redaction back. "
            + "They don't travel with the file if you send it. Removing them also clears this window's undo history."
        alert.addButton(withTitle: "Keep Earlier Versions")
        alert.addButton(withTitle: "Remove Earlier Versions and Undo History")
        alert.beginSheetModal(for: window) { response in
            defer { done() }
            guard response == .alertSecondButtonReturn else { return }
            do {
                try NSFileVersion.removeOtherVersionsOfItem(at: url)
                // Undoing the redaction would let autosave write the original back (Leah, 2026-10-04).
                editor.forgetHistory()
            } catch { self.presentError(error) }
        }
    }

    /// A redaction not yet saved with ⌘S: closing saves it first, then gives the earlier-versions warning
    /// (Leah, 2026-10-04).
    var wantsRedactionCheckBeforeClosing: Bool {
        editor?.redactedSinceSave == true && fileURL != nil
    }

    func checkRedactionBeforeClosing(then close: @escaping () -> Void) {
        autosave(withImplicitCancellability: false) { [weak self] error in
            DispatchQueue.main.async {
                // If saving failed, closing as usual reports it.
                guard let self, error == nil, let url = self.fileURL else { return close() }
                self.warnAboutEarlierVersions(of: url, then: close)
            }
        }
    }

    /// Revert To (Saved, Last Opened, or a version) reads the file into a new editor; the window is rebuilt
    /// around it, so what's on screen is what's saved (review J, finding 1).
    override func revert(toContentsOf url: URL, ofType typeName: String) throws {
        try super.revert(toContentsOf: url, ofType: typeName)
        replaceWindows()
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

    /// The name of an image that became a project, so the title survives a relaunch (review J, finding 28).
    override func encodeRestorableState(with coder: NSCoder) {
        super.encodeRestorableState(with: coder)
        coder.encode(projectName, forKey: "ColorbeeProjectName")
    }

    override func restoreState(with coder: NSCoder) {
        super.restoreState(with: coder)
        if let name = coder.decodeObject(of: NSString.self, forKey: "ColorbeeProjectName") as String? {
            projectName = name
            windowControllers.forEach { $0.synchronizeWindowTitleWithDocumentName() }
        }
    }

    override var displayName: String! {
        get { fileURL == nil ? projectName ?? super.displayName : super.displayName }
        set { super.displayName = newValue }
    }

    /// A layered image can only be saved as a project; flat copies come from Export.
    /// The format last chosen when saving an image without layers (Leah, 2026-10-05). It's where the Save panel
    /// starts for a new or untitled image; a file keeps its own format, and a layered image saves as a project.
    private static let lastSaveFormatKey = "LastSaveFormat"

    override func runModalSavePanel(for saveOperation: NSDocument.SaveOperationType, delegate: Any?, didSave didSaveSelector: Selector?,
                                    contextInfo: UnsafeMutableRawPointer?) {
        if fileURL == nil, editor?.isLayered != true, let remembered = UserDefaults.standard.string(forKey: Self.lastSaveFormatKey),
           writableTypes(for: saveOperation).contains(remembered) {
            fileType = remembered
        }
        super.runModalSavePanel(for: saveOperation, delegate: delegate, didSave: didSaveSelector, contextInfo: contextInfo)
    }

    override func writableTypes(for saveOperation: NSDocument.SaveOperationType) -> [String] {
        // AppKit asks on the main thread while setting up a save panel.
        let layered = MainActor.assumeIsolated { editor?.isLayered == true }
        if layered { return [UTType.colorbeeProject.identifier] }
        return super.writableTypes(for: saveOperation)
    }

    /// The copy being saved. A newer save replaces it, which is fine since it's newer content.
    nonisolated private let snapshotLock = NSLock()
    nonisolated(unsafe) private var pendingSnapshot: SaveSnapshot?
    /// The copy the running save is writing, which a newer save may have put in place of its own.
    nonisolated(unsafe) private var encodedSnapshot: SaveSnapshot?

    nonisolated override func canAsynchronouslyWrite(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType) -> Bool {
        true
    }

    /// Called on a background thread for saves (see `canAsynchronouslyWrite`), so it touches only the snapshot.
    nonisolated override func data(ofType typeName: String) throws -> Data {
        var snapshot = snapshotLock.withLock {
            encodedSnapshot = pendingSnapshot
            return pendingSnapshot
        }
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
        // Earlier shares' copies go first; each can show what's since been redacted (review H, finding 6).
        Self.removeShareFolders()
        let folder = FileManager.default.temporaryDirectory.appending(path: "Colorbee Share \(UUID().uuidString)", directoryHint: .isDirectory)
        let url = folder.appending(path: "\((displayName as NSString).deletingPathExtension).png")
        writePNGInBackground(of: editor, to: url) { [weak view] in
            guard let view else { return }
            let picker = NSSharingServicePicker(items: [url])
            picker.show(relativeTo: NSRect(x: view.bounds.midX, y: view.bounds.maxY - 1, width: 1, height: 1), of: view, preferredEdge: .minY)
        }
    }

    /// Removes the copies earlier shares left in the temporary folder. Also run at launch.
    static func removeShareFolders() {
        let temporary = FileManager.default.temporaryDirectory
        let folders = (try? FileManager.default.contentsOfDirectory(at: temporary, includingPropertiesForKeys: nil)) ?? []
        for folder in folders where folder.lastPathComponent.hasPrefix("Colorbee Share ") { try? FileManager.default.removeItem(at: folder) }
    }

    /// Writes the image as a PNG from a copy, encoded off the main thread like saving (review E, finding 6),
    /// then calls `done` on the main thread.
    private func writePNGInBackground(of editor: Editor, to url: URL, then done: @escaping @MainActor () throws -> Void) {
        let snapshot = editor.saveSnapshot()
        Task { [weak self] in
            do {
                try await Task.detached(priority: .userInitiated) {
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try snapshot.encoded(as: .png).write(to: url)
                }.value
                try done()
            } catch {
                self?.presentError(error)
            }
        }
    }

    /// Saves a PNG copy in Application Support (the desktop needs a file that stays put) and shows it on every screen.
    @IBAction func setDesktopPicture(_ sender: Any?) {
        guard let editor else { return }
        let folder = URL.applicationSupportDirectory.appending(path: "Colorbee/Desktop Pictures", directoryHint: .isDirectory)
        let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).replacingOccurrences(of: ":", with: ".")
        let url = folder.appending(path: "\((displayName as NSString).deletingPathExtension) \(stamp).png")
        writePNGInBackground(of: editor, to: url) {
            for screen in NSScreen.screens {
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
            }
            // Only the picture in use is kept (review H, finding 6).
            let others = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for other in others where other.lastPathComponent != url.lastPathComponent { try? FileManager.default.removeItem(at: other) }
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
            let scaling = ExportPresetStore.shared.scaling
            self?.export(editor.saveSnapshot(), to: url) { try $0.encoded(using: preset, scaling: scaling) }
        }
    }

    @IBAction func exportDocument(_ sender: Any?) {
        guard let editor, let window = windowForSheet else { return }
        let options = ExportOptions()
        options.hasCameraDetails = editor.canvas.cameraDetails != nil
        let panel = NSSavePanel()
        panel.allowedContentTypes = [options.format.type]
        panel.nameFieldStringValue = (displayName as NSString).deletingPathExtension
        panel.accessoryView = NSHostingView(rootView: ExportAccessory(options: options) { format in
            panel.allowedContentTypes = [format.type]
        })
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            let format = options.format, quality = options.quality, lzw = options.tiffLZW
            let details = options.writesCameraDetails
            self?.export(editor.saveSnapshot(), to: url) {
                try $0.encoded(as: format, quality: quality, tiffLZW: lzw, includingCameraDetails: details)
            }
        }
    }

    /// Every page, in order, as a PDF (FR-11.6).
    @IBAction func exportPDF(_ sender: Any?) {
        guard let editor, let window = windowForSheet else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = (displayName as NSString).deletingPathExtension
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.export(editor.saveSnapshot(), to: url) { try $0.encodedPDF() }
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
    private static let defaults = UserDefaults.standard

    /// Export… starts with the format, quality and compression last used (Leah, 2026-10-05).
    var format: ImageFileFormat = ExportOptions.rememberedFormat {
        didSet { Self.defaults.set(format.type.identifier, forKey: "ExportFormat") }
    }
    var quality = ExportOptions.defaults.object(forKey: "ExportQuality") as? Double ?? 0.9 {
        didSet { Self.defaults.set(quality, forKey: "ExportQuality") }
    }
    /// Lossless and usually much smaller, so it's the default.
    var tiffLZW = ExportOptions.defaults.object(forKey: "ExportTIFFLZW") as? Bool ?? true {
        didSet { Self.defaults.set(tiffLZW, forKey: "ExportTIFFLZW") }
    }

    private static var rememberedFormat: ImageFileFormat {
        let format = defaults.string(forKey: "ExportFormat").flatMap(UTType.init).flatMap(ImageFileFormat.init(type:))
        return format.flatMap { $0.canWrite ? $0 : nil } ?? .png
    }
    /// The image came from a camera or phone that recorded how it was taken (FR-11.8).
    var hasCameraDetails = false
    /// Off at first; remembered after that.
    var includeCameraDetails = UserDefaults.standard.bool(forKey: "ExportCameraDetails") {
        didSet { UserDefaults.standard.set(includeCameraDetails, forKey: "ExportCameraDetails") }
    }

    var writesCameraDetails: Bool { hasCameraDetails && includeCameraDetails && format.holdsCameraDetails }
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
            if options.format == .tiff {
                Picker("Compression", selection: $options.tiffLZW) {
                    Text("LZW").tag(true)
                    Text("None").tag(false)
                }
                .help("LZW is lossless and smaller; some older apps only read uncompressed TIFF")
            }
            if options.hasCameraDetails && options.format.holdsCameraDetails {
                Toggle("Include camera details", isOn: $options.includeCameraDetails)
                    .help("Camera, lens, ISO, shutter speed, aperture, focal length and date taken. Never location, serial numbers or the owner's name.")
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
