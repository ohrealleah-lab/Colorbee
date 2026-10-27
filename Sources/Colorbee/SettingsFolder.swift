import Foundation

/// Where Colorbee keeps files a test build might write in a newer form than the everyday copy can read (stage 1a).
/// A signed beta, Leah's everyday copy, uses Application Support/Colorbee; every other build (Debug, `make run`)
/// uses a folder of its own, so a test build can't change the everyday copy's saved filters (Leah, 2026-10-27).
/// Clipboard History and desktop pictures stay in the everyday folder for every build.
@MainActor
enum SettingsFolder {
    static let everyday = URL.applicationSupportDirectory.appending(path: "Colorbee", directoryHint: .isDirectory)
    static let testBuilds = URL.applicationSupportDirectory.appending(path: "Colorbee Test Builds", directoryHint: .isDirectory)

    /// Nil while testing, so tests never write settings.
    static var current: URL? {
        if TestHost.isActive { return nil }
        #if COLORBEE_BETA
        return everyday
        #else
        return testBuilds
        #endif
    }
}
