import AppKit
import ColorbeeCore

/// Saves a picture of the first document window and quits, for checking the interface without
/// taking over the screen: `-ColorbeeSnapshot /path/to.png`, optionally with `-ColorbeeSnapshotDark YES`
/// `-ColorbeeSnapshotTool brush` (any tool's name), `-ColorbeeSnapshotLayers 3` (adds layers, opens the panel),
/// `-ColorbeeSnapshotEffect levels` and `-ColorbeeSnapshotAdjustment curves`. The Metal canvas and Liquid Glass aren't drawn,
/// so it checks layout, not the glass.
@MainActor
enum Snapshot {
    private static let defaults = UserDefaults.standard

    static func startIfRequested(window: NSWindow, editor: Editor) {
        guard let path = defaults.string(forKey: "ColorbeeSnapshot") else { return }
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
        // `-ColorbeeSnapshotEffect levels` opens an effect's bar; `-ColorbeeSnapshotAdjustment curves` adds that
        // adjustment layer and shows its settings.
        if let name = defaults.string(forKey: "ColorbeeSnapshotEffect"), let kind = EffectKind.allCases.first(where: { "\($0)" == name }) {
            editor.beginEffect(kind)
        }
        if let name = defaults.string(forKey: "ColorbeeSnapshotAdjustment"), let choice = AdjustmentChoice.allCases.first(where: { "\($0)" == name }) {
            editor.addAdjustmentLayer(choice)
            editor.showsLayersPanel = true
        }
        // `-ColorbeeSnapshotSettings YES` photographs the Settings window instead.
        let settings = defaults.bool(forKey: "ColorbeeSnapshotSettings")
        if settings { SettingsWindowController.shared.showWindow(nil) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let window = settings ? SettingsWindowController.shared.window! : window
            guard let frame = window.contentView?.superview,
                  let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { return }
            frame.cacheDisplay(in: frame.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            NSApp.terminate(nil)
        }
    }
}
