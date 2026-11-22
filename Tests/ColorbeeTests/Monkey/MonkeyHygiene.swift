import AppKit
import ColorbeeCore
import Darwin
import Foundation
@testable import Colorbee

/// Counts each time the document is told it was edited (monkey gaps, R9).
@MainActor
final class MarkCounter {
    private(set) var count = 0

    func watch(_ editor: Editor) {
        editor.onDocumentChange = { [weak self] _ in self?.count += 1 }
    }
}

/// Every editor an episode made, held weakly: once episodes are over, their editors must go away, or a long session
/// would keep every picture it ever had (monkey hardening, S6). Now and then one is still held for a while by the test
/// run itself (its own suspended work, AppKit's), which a real leak can't be told from in one episode; a real leak keeps
/// every episode's, so it's the pile that's reported.
@MainActor
enum MonkeyLeaks {
    private final class Weak {
        weak var editor: Editor?
        weak var page: Page?
        init(editor: Editor?, page: Page?) {
            self.editor = editor
            self.page = page
        }
        var isGone: Bool { editor == nil && page == nil }
    }

    private static var made: [Weak] = []

    static func note(_ editor: Editor) {
        made.append(Weak(editor: editor, page: nil))
        for page in editor.pages.pages { made.append(Weak(editor: nil, page: page)) }
    }

    /// Episodes checked, and how many left an editor held after them, for the report.
    private(set) static var checked = 0
    private(set) static var strays = 0

    /// After an episode, and a moment for background work to let go. About one episode in ten leaves its editor held
    /// by the test run's own suspended work (traced 2026-11-21: a closed window's canvas frees its editor); a real leak
    /// holds every episode's, so it's reported once most episodes leave one (`limit` episodes checked at least).
    static func check(limit: Int = 20) async -> MonkeyFailure? {
        for _ in 0..<80 where made.contains(where: { !$0.isGone }) {
            try? await Task.sleep(for: .milliseconds(25))
        }
        checked += 1
        if made.contains(where: { $0.editor != nil }) { strays += 1 }
        made = []
        guard checked >= limit, strays * 2 > checked else { return nil }
        defer { (checked, strays) = (0, 0) }
        return MonkeyFailure(rule: "Episodes' pictures stay in memory after they end",
                             detail: "\(strays) of the last \(checked) episodes left their editor held. A long session would keep every picture it had.")
    }

    static func forget() { made = [] }

    static func resetCounts() { (checked, strays) = (0, 0) }
}

/// What the monkey must never touch (monkey hardening, S3 and S4): Colorbee's preferences, the settings folders, the network.
/// Taken once before the run and compared after each episode.
@MainActor
struct MonkeyHygiene {
    private let defaults: [String: String]
    private let folders: [String: [String]]
    private let sockets: Int
    /// Open files once the system's own (fonts, image readers, Vision) are open: the most seen in the first episodes.
    private var files: Int
    private var episodes = 0

    static let watchedFolders = [SettingsFolder.everyday, SettingsFolder.testBuilds]

    static func take() -> MonkeyHygiene {
        MonkeyHygiene(defaults: preferences(), folders: Dictionary(uniqueKeysWithValues: watchedFolders.map { ($0.path, listing(of: $0)) }),
                      sockets: openDescriptors().sockets, files: openDescriptors().files)
    }

    /// Colorbee's saved preferences, each as text, so a change shows which one.
    private static func preferences() -> [String: String] {
        guard let id = Bundle.main.bundleIdentifier, let domain = UserDefaults.standard.persistentDomain(forName: id) else { return [:] }
        return domain.mapValues { "\($0)" }
    }

    /// Every file under `folder`, with its size and when it changed.
    private static func listing(of folder: URL) -> [String] {
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else { return [] }
        var lines: [String] = []
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            lines.append("\(url.path.dropFirst(folder.path.count)) \(values?.fileSize ?? -1) \(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)")
        }
        return lines.sorted()
    }

    /// This process's open internet sockets, and its open files (history's scratch files among them).
    static func openDescriptors() -> (sockets: Int, files: Int) {
        let pid = getpid()
        let size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard size > 0 else { return (0, 0) }
        let count = Int(size) / MemoryLayout<proc_fdinfo>.stride
        var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: count + 16)
        let used = descriptors.withUnsafeMutableBytes { proc_pidinfo(pid, PROC_PIDLISTFDS, 0, $0.baseAddress, Int32($0.count)) }
        guard used > 0 else { return (0, 0) }
        var sockets = 0, files = 0
        for descriptor in descriptors.prefix(Int(used) / MemoryLayout<proc_fdinfo>.stride) {
            switch Int32(descriptor.proc_fdtype) {
            case PROX_FDTYPE_VNODE:
                files += 1
            case PROX_FDTYPE_SOCKET:
                var info = socket_fdinfo()
                let read = proc_pidfdinfo(pid, descriptor.proc_fd, PROC_PIDFDSOCKETINFO, &info, Int32(MemoryLayout<socket_fdinfo>.size))
                if read > 0, [AF_INET, AF_INET6].contains(info.psi.soi_family) { sockets += 1 }
            default:
                break
            }
        }
        return (sockets, files)
    }

    /// After an episode: nothing above changed, and no files were left open. Another copy of Colorbee running (Leah's
    /// everyday one) shares the preferences and folders, so a change it made is said to be possible.
    mutating func check() -> MonkeyFailure? {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "").count > 1
        let maybe = others ? " Another copy of Colorbee was running and may have made this change." : ""
        let now = Self.preferences()
        if now != defaults {
            let changed = Set(now.keys).union(defaults.keys).filter { now[$0] != defaults[$0] }.sorted()
            return MonkeyFailure(rule: "The monkey changed Colorbee's preferences",
                                 detail: "Changed: \(changed.joined(separator: ", ")). Tests must never save a preference.\(maybe)")
        }
        for folder in Self.watchedFolders {
            let was = folders[folder.path] ?? [], listing = Self.listing(of: folder)
            guard listing == was else {
                let changed = Set(listing).symmetricDifference(was).map { $0.split(separator: " ").first.map(String.init) ?? $0 }
                return MonkeyFailure(rule: "The monkey wrote to a settings folder",
                                     detail: "In \(folder.lastPathComponent): \(Set(changed).sorted().joined(separator: ", ")).\(maybe)")
            }
        }
        let open = Self.openDescriptors()
        if open.sockets > sockets {
            return MonkeyFailure(rule: "Colorbee opened a network connection", detail: "\(open.sockets - sockets) internet socket\(open.sockets - sockets == 1 ? "" : "s") open. Colorbee does no networking at all.")
        }
        episodes += 1
        if episodes <= 5 {
            files = max(files, open.files)
            return nil
        }
        // Slack for the system opening more of its own; history scratch files left open by every episode soon pass it.
        if open.files > files + 40 {
            return MonkeyFailure(rule: "Files stayed open after an episode", detail: "\(open.files) files open, \(files) at the start.")
        }
        return nil
    }
}
