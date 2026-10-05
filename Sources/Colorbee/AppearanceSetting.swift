import AppKit

/// Settings ▸ General ▸ Appearance: follow macOS, or always Light or Dark (FRD §17). It's set on the whole app,
/// so every window, sheet and panel follows at once; the image itself is never tinted.
enum AppearanceSetting: String, CaseIterable {
    case system, light, dark

    static let key = "Appearance"

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    static var current: AppearanceSetting {
        UserDefaults.standard.string(forKey: key).flatMap(AppearanceSetting.init) ?? .system
    }

    /// Applies the saved choice. Nil follows macOS, including when it switches on its own (Auto, at sunset).
    @MainActor
    static func apply() {
        NSApp.appearance = switch current {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}
