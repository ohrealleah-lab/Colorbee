import AppKit
import ColorbeeCore
import SwiftUI
import UniformTypeIdentifiers

/// Settings ▸ Shortcuts (FR-15.3): every command, grouped by menu, with search. Click a shortcut and press
/// keys to change it; Esc cancels, Delete clears.
struct ShortcutSettings: View {
    let store: ShortcutStore
    @State private var search = ""
    @State private var recording: String?
    @State private var message: String?
    @State private var monitor: Any?

    private var groups: [(name: String, commands: [ShortcutCommand])] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        let matching = store.book.commands.filter { command in
            query.isEmpty || command.title.lowercased().contains(query) || command.group.lowercased().contains(query)
                || (store.book.shortcut(for: command.id)?.display.lowercased().contains(query) ?? false)
        }
        var order: [String] = []
        var byGroup: [String: [ShortcutCommand]] = [:]
        for command in matching {
            if byGroup[command.group] == nil { order.append(command.group) }
            byGroup[command.group, default: []].append(command)
        }
        return order.map { ($0, byGroup[$0]!) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Search commands or shortcuts", text: $search)
                .textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                    ForEach(groups, id: \.name) { group in
                        Section {
                            ForEach(group.commands, id: \.id) { command in
                                row(command)
                                    .padding(.horizontal, 10)
                                    .frame(height: 28)
                                Divider().padding(.leading, 10)
                            }
                        } header: {
                            Text(group.name)
                                .font(.headline)
                                .padding(.horizontal, 10)
                                .padding(.top, 12)
                                .padding(.bottom, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.background)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.25)))
            if let message {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }
            HStack {
                Button("Reset All") { store.resetAll() }
                    .help("Every shortcut back to its default")
                Spacer()
                Button("Import…") { importShortcuts() }
                Button("Export…") { exportShortcuts() }
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private func row(_ command: ShortcutCommand) -> some View {
        let shortcut = store.book.shortcut(for: command.id)
        let isRecording = recording == command.id
        return HStack {
            Text(command.title)
            if store.book.isChanged(command.id) {
                Circle().fill(Color.accentColor).frame(width: 6, height: 6).help("Changed from the default")
            }
            if command.isEditable, let owner = store.systemOwner(of: command.id) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("This Mac also uses \(store.book.shortcut(for: command.id)?.display ?? "it") (\(owner)), and macOS takes it first. Give this command another shortcut.")
            }
            Spacer()
            if command.isEditable {
                Button { isRecording ? stopRecording() : startRecording(command.id) } label: {
                    Text(isRecording ? "Type a shortcut…" : shortcut?.display ?? "—")
                        .monospaced()
                        .frame(minWidth: 110)
                        .foregroundStyle(isRecording ? Color.accentColor : .primary)
                }
                .help(isRecording ? "Press the new keys. Esc cancels; Delete clears." : "Click, then press the new shortcut")
                if store.book.isChanged(command.id) {
                    Button("Reset", systemImage: "arrow.uturn.backward") { store.reset(command.id) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Back to \(command.defaultShortcut?.display ?? "no shortcut")")
                } else {
                    Color.clear.frame(width: 16)
                }
            } else {
                Text(shortcut?.display ?? "—")
                    .monospaced()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 110)
                    .help("A standard macOS shortcut; it can't be changed")
                Image(systemName: "lock").foregroundStyle(.secondary).frame(width: 16)
            }
        }
    }

    // MARK: Recording

    private func startRecording(_ id: String) {
        stopRecording()
        message = nil
        recording = id
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { handle(event) }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = nil
    }

    private func handle(_ event: NSEvent) {
        guard let id = recording, let shortcut = ShortcutStore.shortcut(of: event) else { return }
        if shortcut == KeyShortcut("escape") {
            stopRecording()
            return
        }
        if shortcut == KeyShortcut("delete") {
            store.assign(nil, to: id)
            stopRecording()
            return
        }
        if event.modifierFlags.contains(.function), !shortcut.key.hasPrefix("f"), !["left", "right", "up", "down", "forwardDelete"].contains(shortcut.key) {
            message = "Fn and Globe shortcuts belong to macOS."
            return
        }
        stopRecording()
        switch store.check(shortcut, for: id) {
        case .allowed:
            store.assign(shortcut, to: id)
        case .needsCommandOrControl:
            message = "Menu commands need ⌘ or ⌃ in the shortcut."
        case .canvasKeysCantUseModifiers:
            message = "Tool and canvas keys are a single key, or ⇧ and a key."
        case .cantBeChanged:
            message = "This standard macOS shortcut can't be changed."
        case .reserved(let owner):
            message = "\(shortcut.display) is used by \(owner)."
        case .usedBy(let other):
            if confirm("\(shortcut.display) is used by \(other.title).", detail: "Reassign it? \(other.title) will have no shortcut.", action: "Reassign") {
                store.assign(shortcut, to: id)
            }
        case .standard(let name):
            if confirm("\(shortcut.display) is the standard shortcut for \(name).", detail: "Every Mac app expects it. Change it anyway?", action: "Change") {
                store.assign(shortcut, to: id)
            }
        }
    }

    private func confirm(_ title: String, detail: String, action: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: action)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: Files

    private func importShortcuts() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(exportedAs: "com.leah.colorbee.colorbeekeys")]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try store.importChanges(from: url) } catch { NSAlert(error: error).runModal() }
    }

    private func exportShortcuts() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(exportedAs: "com.leah.colorbee.colorbeekeys")]
        panel.nameFieldStringValue = "Colorbee Shortcuts"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try store.export(to: url) } catch { NSAlert(error: error).runModal() }
    }
}
