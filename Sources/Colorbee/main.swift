import AppKit

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
