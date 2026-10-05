import AppKit
import ColorbeeCore

/// Saves a picture of the first document window and quits, for checking the interface without
/// taking over the screen: `-ColorbeeSnapshot /path/to.png`, optionally with `-ColorbeeSnapshotDark YES`
/// `-ColorbeeSnapshotTool brush` (any tool's name), `-ColorbeeSnapshotLayers 3` (adds layers, opens the panel),
/// `-ColorbeeSnapshotEffect levels`, `-ColorbeeSnapshotAdjustment curves`, `-ColorbeeSnapshotShapeFill YES`,
/// `-ColorbeeSnapshotPDF /path/to.pdf`, `-ColorbeeSnapshotAutoRedact YES` and `-ColorbeeSnapshotAutoRedactApply YES`. The Metal canvas and Liquid Glass aren't drawn,
/// so it checks layout, not the glass.
@MainActor
enum Snapshot {
    private static let defaults = UserDefaults.standard

    static func startIfRequested(window: NSWindow, editor: Editor) {
        guard let path = defaults.string(forKey: "ColorbeeSnapshot") else { return }
        // Overrides Settings ▸ General ▸ Appearance for this run only, without saving. `-Appearance light` (or dark,
        // or system) picks the setting itself for a run, since snapshots otherwise use Leah's saved choice.
        if defaults.bool(forKey: "ColorbeeSnapshotDark") { NSApp.appearance = NSAppearance(named: .darkAqua) }
        if defaults.bool(forKey: "ColorbeeSnapshotEdited") {
            (window.windowController?.document as? NSDocument)?.updateChangeCount(.changeDone)
        }
        let extraLayers = defaults.integer(forKey: "ColorbeeSnapshotLayers")
        if extraLayers > 0 {
            for _ in 0..<extraLayers { editor.addLayer() }
            editor.setBlendMode(.multiply)
            editor.setLayerLocked(true, at: 0)
            editor.addAdjustmentLayer(.levels(Levels(black: 12, white: 240, gamma: 1.1)), named: "Levels")
            editor.showsAdjustmentsPanel = false
            editor.showsHistoryPanel = true
            editor.showsClipboardPanel = true
            editor.showsRulers = true
        }
        if let name = defaults.string(forKey: "ColorbeeSnapshotTool"), let tool = Tool.allCases.first(where: { "\($0)" == name }) {
            editor.selectTool(tool)
        }
        // `-ColorbeeSnapshotShapeFill YES`: a solid shape fill in an orange Color 2, to see the Fill swatch.
        if defaults.bool(forKey: "ColorbeeSnapshotShapeFill") {
            editor.shapeFill = .solid
            editor.color2 = Pixel(r: 255, g: 140, b: 0)
        }
        // `-ColorbeeSnapshotEffect levels` opens an effect's bar; `-ColorbeeSnapshotAdjustment curves` adds that
        // adjustment layer and shows its settings.
        if let name = defaults.string(forKey: "ColorbeeSnapshotEffect"), let kind = EffectKind.allCases.first(where: { "\($0)" == name }) {
            editor.beginEffect(kind)
        }
        if let name = defaults.string(forKey: "ColorbeeSnapshotAdjustment"), let choice = AdjustmentChoice.allCases.first(where: { "\($0)" == name }) {
            editor.addAdjustmentLayer(choice)
            editor.showsLayersPanel = true
        }
        // `-ColorbeeSnapshotExportPNG /path/to.png` also exports the page shown as a PNG with its camera details (stage 12).
        if let png = defaults.string(forKey: "ColorbeeSnapshotExportPNG") {
            try? editor.saveSnapshot().encoded(as: .png, includingCameraDetails: true).write(to: URL(fileURLWithPath: png))
        }
        // `-ColorbeeSnapshotPDF /path/to.pdf` also exports every page as a PDF (stage 10b).
        let pdf = defaults.string(forKey: "ColorbeeSnapshotPDF")
        func exportPDF() {
            if let pdf { try? editor.saveSnapshot().encodedPDF().write(to: URL(fileURLWithPath: pdf)) }
        }
        // `-ColorbeeSnapshotAutoRedact YES` runs Auto-Redact; its review is saved next to the picture as "-sheet.png".
        // `-ColorbeeSnapshotAutoRedactApply YES` then applies it, before any PDF is exported.
        let autoRedact = defaults.bool(forKey: "ColorbeeSnapshotAutoRedact")
        let applyRedaction = defaults.bool(forKey: "ColorbeeSnapshotAutoRedactApply")
        if autoRedact { editor.beginAutoRedact() }
        if applyRedaction {
            Task { @MainActor in
                while let session = editor.autoRedact {
                    if !session.isReading && session.applying == nil && session.problem == nil { editor.applyAutoRedact() }
                    try? await Task.sleep(for: .milliseconds(200))
                }
                exportPDF()
            }
        } else {
            exportPDF()
        }
        // `-ColorbeeSnapshotSettings YES` photographs the Settings window instead.
        let settings = defaults.bool(forKey: "ColorbeeSnapshotSettings")
        if settings { SettingsWindowController.shared.showWindow(nil) }
        DispatchQueue.main.asyncAfter(deadline: .now() + (applyRedaction ? 25 : autoRedact ? 8 : 1.5)) {
            let shown = settings ? SettingsWindowController.shared.window! : window
            photograph(shown, to: path)
            if let sheet = shown.attachedSheet {
                photograph(sheet, to: (path as NSString).deletingPathExtension + "-sheet.png")
            }
            // Quits outright: a snapshot of an edited or redacted document mustn't stop to ask about saving.
            exit(0)
        }
    }

    /// `-ColorbeeSnapshotDevelop /path/to.png` photographs a RAW file's Develop window once its preview shows, after
    /// `-ColorbeeSnapshotDevelopSettings "exposure=1,highlights=-100"` (any of the settings' names). With
    /// `-ColorbeeSnapshotDevelopOpen YES` it then opens the photo, and the document window's options take over.
    static func developIfRequested(window: NSWindow, session: DevelopSession) {
        guard let path = defaults.string(forKey: "ColorbeeSnapshotDevelop") else { return }
        if defaults.bool(forKey: "ColorbeeSnapshotDark") { NSApp.appearance = NSAppearance(named: .darkAqua) }
        let paths: [String: WritableKeyPath<DevelopSettings, Double>] = [
            "exposure": \.exposure, "temperature": \.temperature, "tint": \.tint, "highlights": \.highlights,
            "shadows": \.shadows, "contrast": \.contrast, "noiseReduction": \.noiseReduction, "sharpness": \.sharpness,
        ]
        for pair in (defaults.string(forKey: "ColorbeeSnapshotDevelopSettings") ?? "").split(separator: ",") {
            let parts = pair.split(separator: "=").map(String.init)
            if parts.count == 2, let path = paths[parts[0]], let value = Double(parts[1]) { session.settings[keyPath: path] = value }
        }
        Task { @MainActor in
            while session.preview == nil { try? await Task.sleep(for: .milliseconds(100)) }
            try? await Task.sleep(for: .milliseconds(1500))
            photograph(window, to: path)
            if defaults.bool(forKey: "ColorbeeSnapshotDevelopOpen") { session.open() } else { exit(0) }
        }
    }

    private static func photograph(_ window: NSWindow, to path: String) {
        guard let frame = window.contentView?.superview,
              let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { return }
        frame.cacheDisplay(in: frame.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
