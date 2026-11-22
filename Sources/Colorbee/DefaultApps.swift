import AppKit
import Observation
import UniformTypeIdentifiers

/// One row of Settings ▸ General ▸ Make Colorbee the default for (FR-14.3, stage 36).
enum DefaultAppKind: String, CaseIterable, Identifiable {
    case jpeg, png, heic, tiff, gif, bmp, webp, pdf

    var id: Self { self }

    var title: String {
        switch self {
        case .jpeg: "JPEG"
        case .png: "PNG"
        case .heic: "HEIC and HEIF"
        case .tiff: "TIFF"
        case .gif: "GIF"
        case .bmp: "BMP"
        case .webp: "WebP"
        case .pdf: "PDF"
        }
    }

    var types: [UTType] {
        switch self {
        case .jpeg: [.jpeg]
        case .png: [.png]
        case .heic: [.heic, .heif]
        case .tiff: [.tiff]
        case .gif: [.gif]
        case .bmp: [.bmp]
        case .webp: [.webP]
        case .pdf: [.pdf]
        }
    }
}

/// The Mac's choice of app for each file type. Tests use a stand-in, so they never change Leah's defaults.
@MainActor
protocol DefaultAppSystem {
    func appBundleID(toOpen type: UTType) -> String?
    func isInstalled(_ bundleID: String) -> Bool
    func setApp(_ bundleID: String, toOpen type: UTType) async throws
}

@MainActor
struct WorkspaceDefaultApps: DefaultAppSystem {
    func appBundleID(toOpen type: UTType) -> String? {
        NSWorkspace.shared.urlForApplication(toOpen: type).flatMap { Bundle(url: $0)?.bundleIdentifier }
    }

    func isInstalled(_ bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    func setApp(_ bundleID: String, toOpen type: UTType) async throws {
        // This copy of Colorbee, not whichever copy Launch Services would pick (there can be build copies).
        let url = bundleID == Bundle.main.bundleIdentifier ? Bundle.main.bundleURL : NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        guard let url else { throw CocoaError(.fileNoSuchFile) }
        try await NSWorkspace.shared.setDefaultApplication(at: url, toOpen: type)
    }
}

/// Which file types open in Colorbee when double-clicked in Finder (FR-14.3, stage 36). Unchecking a type gives it
/// back to the app it opened with before Colorbee took it, or to Preview.
@MainActor
@Observable
final class DefaultApps {
    static let shared = DefaultApps(
        system: WorkspaceDefaultApps(),
        colorbee: Bundle.main.bundleIdentifier ?? "com.leah.Colorbee",
        before: UserDefaults.standard.dictionary(forKey: beforeKey) as? [String: String] ?? [:]
    )
    static let preview = "com.apple.Preview"
    private static let beforeKey = "DefaultAppsBefore"

    private(set) var checked: Set<DefaultAppKind> = []
    private(set) var isChanging = false
    /// The app each type opened with before Colorbee took it, by type identifier.
    private(set) var before: [String: String]

    private let system: DefaultAppSystem
    private let colorbee: String

    init(system: DefaultAppSystem, colorbee: String, before: [String: String]) {
        self.system = system
        self.colorbee = colorbee
        self.before = before
        refresh()
    }

    /// Reads the Mac's choices again, since they can change in Finder's Get Info while Settings is open.
    func refresh() {
        checked = Set(DefaultAppKind.allCases.filter { kind in kind.types.allSatisfy { opensInColorbee($0) } })
    }

    /// macOS asks before each type changes. If Leah keeps the app it has, the rest of the row is left alone and this
    /// returns false, without an error.
    @discardableResult
    func set(_ kind: DefaultAppKind, on: Bool) async throws -> Bool {
        isChanging = true
        defer {
            isChanging = false
            StoredSettings.set(before, forKey: Self.beforeKey)
        }
        for type in kind.types where opensInColorbee(type) != on {
            let current = system.appBundleID(toOpen: type)
            let app = on ? colorbee : before[type.identifier].flatMap { system.isInstalled($0) ? $0 : nil } ?? Self.preview
            do {
                try await system.setApp(app, toOpen: type)
            } catch {
                // macOS reports a "Keep" answer as a failure (FRD §23, 2026-11-21). Nothing changed, so it's no error.
                guard system.appBundleID(toOpen: type) == current else { throw error }
                refresh()
                return false
            }
            before[type.identifier] = on ? current : nil
        }
        // Launch Services can take a moment to report a change, so reading it back here could undo the checkbox.
        if on { checked.insert(kind) } else { checked.remove(kind) }
        return true
    }

    /// Stops at the first type Leah keeps, rather than asking about every other row.
    func checkAll() async throws {
        for kind in DefaultAppKind.allCases where !checked.contains(kind) {
            guard try await set(kind, on: true) else { return }
        }
    }

    private func opensInColorbee(_ type: UTType) -> Bool {
        system.appBundleID(toOpen: type)?.caseInsensitiveCompare(colorbee) == .orderedSame
    }
}
