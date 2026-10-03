import AppKit

/// Saves a picture of the first document window and quits, for checking the interface without
/// taking over the screen: `-ColorbeeSnapshot /path/to.png`, optionally with `-ColorbeeSnapshotDark YES`
/// and `-ColorbeeSnapshotTool brush` (any tool's name). The Metal canvas and Liquid Glass aren't drawn,
/// so it checks layout, not the glass.
@MainActor
enum Snapshot {
    private static let defaults = UserDefaults.standard

    static func startIfRequested(window: NSWindow, editor: Editor) {
        guard let path = defaults.string(forKey: "ColorbeeSnapshot") else { return }
        if defaults.bool(forKey: "ColorbeeSnapshotDark") { NSApp.appearance = NSAppearance(named: .darkAqua) }
        if let name = defaults.string(forKey: "ColorbeeSnapshotTool"), let tool = Tool.allCases.first(where: { "\($0)" == name }) {
            editor.selectTool(tool)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard let frame = window.contentView?.superview,
                  let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { return }
            frame.cacheDisplay(in: frame.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            NSApp.terminate(nil)
        }
    }
}
