import AppKit
import ColorbeeCore
import SwiftUI

/// The Develop window that every RAW photo opens through (FR-11.8): a live preview and the controls, at RAW
/// precision. Open makes the developed photo a new untitled document; Cancel opens nothing.
@MainActor
final class DevelopWindowController: NSWindowController, NSWindowDelegate {
    /// Open Develop windows, kept until they close.
    private static var open: Set<DevelopWindowController> = []
    private let session: DevelopSession

    /// Shows the Develop window for `url`, or a message if macOS can't read it.
    static func develop(_ url: URL) {
        do {
            let developer = try RawDeveloper(url: url)
            let controller = DevelopWindowController(session: DevelopSession(developer: developer))
            open.insert(controller)
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "“\(url.lastPathComponent)” can't be opened."
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private init(session: DevelopSession) {
        self.session = session
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 720),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Develop — \(session.developer.url.lastPathComponent)"
        window.minSize = NSSize(width: 820, height: 560)
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: DevelopView(session: session) { [weak self] in self?.close() })
        window.center()
        session.onOpened = { [weak self] in self?.close() }
        session.refreshPreview()
        Snapshot.developIfRequested(window: window, session: session)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func windowWillClose(_ notification: Notification) {
        session.cancel()
        Self.open.remove(self)
    }
}

/// One Develop window's state: the settings, the preview, and the final develop.
@MainActor
@Observable
final class DevelopSession {
    let developer: RawDeveloper
    var settings: DevelopSettings {
        didSet { if settings != oldValue { refreshPreview() } }
    }
    private(set) var preview: CGImage?
    private(set) var isDeveloping = false
    var problem: String?
    @ObservationIgnored var onOpened: () -> Void = {}

    @ObservationIgnored private var previewRunning = false
    @ObservationIgnored private var previewWanted = false
    @ObservationIgnored private var cancelled = false
    /// The preview's longer side, in pixels: enough for a large window on a Retina screen, quick to render.
    nonisolated private static let previewSide = 1600

    init(developer: RawDeveloper) {
        self.developer = developer
        settings = developer.cameraDefaults
    }

    func resetToCamera() {
        settings = developer.cameraDefaults
    }

    /// Renders the preview in the background. While one render runs, changes wait and the newest is drawn next.
    func refreshPreview() {
        guard !previewRunning else {
            previewWanted = true
            return
        }
        previewRunning = true
        previewWanted = false
        let developer = developer, settings = settings
        Task {
            let image = await Task.detached(priority: .userInitiated) {
                developer.preview(settings, maxSide: Self.previewSide).map(UncheckedImage.init)
            }.value
            previewRunning = false
            guard !cancelled else { return }
            if let image { preview = image.value }
            if previewWanted { refreshPreview() }
        }
    }

    /// Develops at full size and opens the photo as a new untitled document.
    func open() {
        guard !isDeveloping else { return }
        isDeveloping = true
        problem = nil
        let developer = developer, settings = settings
        Task {
            do {
                let canvas = try await Task.detached(priority: .userInitiated) {
                    UncheckedCanvas(value: try developer.develop(settings))
                }.value
                guard !cancelled else { return }
                ImageDocument.open(canvas.value, name: developer.url.deletingPathExtension().lastPathComponent)
                NSDocumentController.shared.noteNewRecentDocumentURL(developer.url)
                onOpened()
            } catch {
                isDeveloping = false
                problem = error.localizedDescription
            }
        }
    }

    func cancel() {
        cancelled = true
    }
}

private struct UncheckedImage: @unchecked Sendable {
    let value: CGImage
}

/// A canvas made in the background and handed to the main thread, which then owns it alone.
private struct UncheckedCanvas: @unchecked Sendable {
    let value: ColorbeeCore.Canvas
}

private struct DevelopView: View {
    @Bindable var session: DevelopSession
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                preview
                Divider()
                controls
                    .frame(width: 300)
            }
            Divider()
            footer
        }
        .disabled(session.isDeveloping)
    }

    private var preview: some View {
        ZStack {
            Color.black.opacity(0.85)
            if let image = session.preview {
                Image(decorative: image, scale: 2)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(16)
            } else {
                ProgressView().controlSize(.large)
            }
            if session.isDeveloping {
                VStack(spacing: 10) {
                    ProgressView().controlSize(.large)
                    Text("Developing…").foregroundStyle(.white)
                }
                .padding(24)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var controls: some View {
        let support = session.developer.support
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                section("Light") {
                    slider("Exposure", value: $session.settings.exposure, in: -3...3, format: { String(format: "%+.2f", $0) })
                    slider("Highlights", value: $session.settings.highlights, in: -100...0,
                           help: "Drag left to bring back detail in bright areas, such as a sky")
                    slider("Shadows", value: $session.settings.shadows, in: -100...100)
                    slider("Contrast", value: $session.settings.contrast, in: -100...100)
                }
                section("Color") {
                    slider("Temperature", value: $session.settings.temperature, in: 2000...12000, format: { "\(Int($0.rounded())) K" })
                    slider("Tint", value: $session.settings.tint, in: -150...150)
                }
                section("Detail") {
                    slider("Noise Reduction", value: $session.settings.noiseReduction, in: 0...100, enabled: support.noiseReduction)
                    slider("Sharpness", value: $session.settings.sharpness, in: 0...100, enabled: support.sharpness)
                    Toggle("Lens Correction", isOn: $session.settings.lensCorrection)
                        .disabled(!support.lensCorrection)
                        .help(support.lensCorrection ? "Corrects this lens's distortion and vignetting"
                                                     : "macOS has no correction for this lens")
                    if !support.noiseReduction || !support.sharpness || !support.lensCorrection {
                        Text("Greyed-out controls aren't available for this photo.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(cameraSummary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if let problem = session.problem {
                Text(problem).font(.callout).foregroundStyle(.red).lineLimit(2)
            }
            Button("Reset to Camera") { session.resetToCamera() }
                .disabled(session.settings == session.developer.cameraDefaults)
            Button("Cancel", role: .cancel, action: close)
                .keyboardShortcut(.cancelAction)
            Button("Open") { session.open() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// "Test Camera · Test Lens 50mm F2.8 · ISO 400 · 1/125 s · f/2.8 · 50 mm · 6000 × 4000"
    private var cameraSummary: String {
        let details = session.developer.cameraDetails
        var parts: [String] = []
        if let model = details?.model { parts.append(model) }
        if let lens = details?.lens { parts.append(lens) }
        if let iso = details?.iso { parts.append("ISO \(iso)") }
        if let time = details?.exposureTime, time > 0 {
            parts.append(time < 1 ? "1/\(Int((1 / time).rounded())) s" : "\(time.formatted()) s")
        }
        if let f = details?.fNumber { parts.append("f/\(f.formatted(.number.precision(.fractionLength(0...1))))") }
        if let focal = details?.focalLength { parts.append("\(Int(focal.rounded())) mm") }
        let size = session.developer.size
        parts.append("\(size.width) × \(size.height)")
        return parts.joined(separator: " · ")
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
    }

    private func slider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, enabled: Bool = true,
                        help: String? = nil, format: @escaping (Double) -> String = { "\(Int($0.rounded()))" }) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // Text doesn't grey out by itself when disabled; without this an unavailable slider looked usable (Leah).
            HStack {
                Text(title).foregroundStyle(enabled ? .primary : .tertiary)
                Spacer()
                Text(format(value.wrappedValue)).monospacedDigit().foregroundStyle(enabled ? .secondary : .tertiary)
            }
            .font(.callout)
            Slider(value: Binding(get: { min(max(value.wrappedValue, range.lowerBound), range.upperBound) },
                                  set: { value.wrappedValue = $0 }), in: range)
                .controlSize(.small)
                .accessibilityLabel(title)
        }
        .disabled(!enabled)
        .help(enabled ? (help ?? "") : "Not available for this camera")
    }
}
