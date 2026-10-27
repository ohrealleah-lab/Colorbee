import AppKit

// Tooltips after half a second rather than macOS's usual second or so (Leah, 2026-10-27). In the registration domain,
// so nothing is written to Colorbee's settings.
UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 500])

let appDelegate: NSApplicationDelegate
if TestHost.isActive {
    // Set before launching, so Colorbee never shows in the Dock or becomes the active app while tests run.
    NSApplication.shared.setActivationPolicy(.prohibited)
    appDelegate = TestHost()
} else {
    appDelegate = AppDelegate()
}
NSApplication.shared.delegate = appDelegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
