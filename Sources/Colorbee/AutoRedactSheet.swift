import ColorbeeCore
import SwiftUI

/// Reviews what Auto-Redact found before anything is changed (FR-9.3).
struct AutoRedactSheet: View {
    @Bindable var editor: Editor

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            // Hiding a layer is how a part is kept out of redaction (Leah; review H, finding 4).
            if editor.autoRedact?.anyLayered == true {
                Label("Only visible layers were checked. Text on a hidden layer, or covered by another layer, isn't found.",
                      systemImage: "eye")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let session = editor.autoRedact {
                content(session)
                treatment(session)
            }
            DisclosureGroup("Patterns") {
                PatternEditor(patterns: $editor.redactionPatterns)
                    .padding(.top, 6)
            }
            Divider()
            footer
        }
        .padding(20)
        .frame(width: 560)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Auto-Redact").font(.headline)
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var status: String {
        guard let session = editor.autoRedact else { return "" }
        if let problem = session.problem { return problem }
        if let applying = session.applying {
            return session.isMultiPage ? "Redacting page \(min(applying.done + 1, applying.total)) of \(applying.total)…" : "Redacting…"
        }
        if session.isReading {
            return session.isMultiPage ? "Reading page \(session.pagesRead + 1) of \(session.pages.count)…" : "Reading text…"
        }
        if let failure = session.failure {
            guard session.isMultiPage, let page = session.failedPage.flatMap(editor.pageNumber(of:)) else {
                return "Couldn't read the text: \(failure)"
            }
            return "Couldn't read page \(page), so nothing can be redacted: \(failure) Cancel and try again."
        }
        // Says how much was read, so finding items on fewer pages doesn't look like pages were skipped (Leah).
        let read = session.isMultiPage ? "Read \(session.pages.count) pages. " : ""
        if session.matches.isEmpty { return read + "No sensitive text found." }
        let count = session.matches.count
        let items = "\(count) item\(count == 1 ? "" : "s")"
        guard session.isMultiPage else { return "Found \(items). Uncheck anything you want to keep visible." }
        let pagesWithItems = session.pages.filter { !$0.matches.isEmpty }
        let found = if pagesWithItems.count == 1, let only = pagesWithItems.first {
            "Found \(items), \(count == 1 ? "" : "all ")on page \(editor.pageNumber(of: only.pageID) ?? 0)."
        } else {
            "Found \(items) on \(pagesWithItems.count) pages."
        }
        return read + found + " Click one to see it; uncheck anything to keep visible."
    }

    @ViewBuilder
    private func content(_ session: AutoRedactSession) -> some View {
        if let applying = session.applying {
            ProgressView(value: Double(applying.done), total: Double(max(applying.total, 1)))
        } else if session.isReading && session.isMultiPage {
            ProgressView(value: Double(session.pagesRead), total: Double(session.pages.count))
        } else if session.isReading {
            ProgressView()
                .frame(maxWidth: .infinity)
        }
        if !session.matches.isEmpty {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(session.pages.filter { !$0.matches.isEmpty }, id: \.pageID) { result in
                        if session.isMultiPage {
                            let count = result.matches.count
                            Text("Page \(editor.pageNumber(of: result.pageID) ?? 0) · \(count) item\(count == 1 ? "" : "s")")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.top, 8)
                                .padding(.bottom, 2)
                        }
                        ForEach(Array(result.matches.enumerated()), id: \.element.id) { index, match in
                            MatchRow(
                                number: index + 1,
                                match: match,
                                isFocused: session.focused == match.id,
                                included: Binding(
                                    get: { !(editor.autoRedact?.keptVisible.contains(match.id) ?? false) },
                                    set: { editor.setRedactionMatch(match.id, included: $0) }
                                )
                            )
                            .onTapGesture { editor.focusRedactionMatch(match.id) }
                            if index < result.matches.count - 1 { Divider() }
                        }
                    }
                }
            }
            .frame(maxHeight: session.isMultiPage ? 300 : 240)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            .disabled(session.applying != nil)
        }
    }

    private func treatment(_ session: AutoRedactSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Treatment", selection: Binding(get: { session.treatment }, set: { editor.setRedactionTreatment($0) })) {
                ForEach(RedactionTreatment.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            if session.treatment != .solidFill {
                Text("Solid Fill is the most secure: blurred or pixelated text can sometimes be reconstructed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Fills each item with Color 1.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack {
            Label("Detection runs on-device. Nothing leaves this Mac.", systemImage: "lock")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            let busy = editor.autoRedact?.applying != nil
            Button("Cancel", role: .cancel) { editor.cancelAutoRedact() }
                .keyboardShortcut(.cancelAction)
                .disabled(busy)
            let count = editor.autoRedact?.selectedMatches.count ?? 0
            Button("Apply to \(count) Item\(count == 1 ? "" : "s")") { editor.applyAutoRedact() }
                .keyboardShortcut(.defaultAction)
                .disabled(count == 0 || busy || editor.autoRedact?.isReading != false || editor.autoRedact?.problem != nil
                          || editor.autoRedact?.failure != nil)
        }
    }
}

private struct MatchRow: View {
    let number: Int
    let match: RedactionMatch
    let isFocused: Bool
    @Binding var included: Bool

    var body: some View {
        HStack(spacing: 10) {
            Toggle("Redact", isOn: $included)
                .labelsHidden()
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(included ? Color.orange : Color.gray))
            Text(match.patternName)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(match.text)
                .font(.body.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if !included {
                Text("Keep visible")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isFocused ? Color.accentColor.opacity(0.15) : .clear)
        .contentShape(Rectangle())
    }
}

/// Turn built-in patterns on or off, and add or remove your own.
private struct PatternEditor: View {
    @Binding var patterns: [RedactionPattern]
    @State private var newName = ""
    @State private var newExpression = ""

    private var newPattern: RedactionPattern {
        RedactionPattern(name: newName.trimmingCharacters(in: .whitespaces), expression: newExpression)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach($patterns) { $pattern in
                HStack {
                    Toggle(pattern.name, isOn: $pattern.isEnabled)
                    if !pattern.isBuiltIn {
                        Text(pattern.expression)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button("Remove", systemImage: "minus.circle") {
                            patterns.removeAll { $0.id == pattern.id }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                    }
                }
            }
            HStack {
                TextField("Name", text: $newName)
                    .frame(width: 120)
                TextField("Pattern (regular expression)", text: $newExpression)
                    .font(.body.monospaced())
                Button("Add") {
                    patterns.append(newPattern)
                    newName = ""
                    newExpression = ""
                }
                .disabled(newPattern.name.isEmpty || newExpression.isEmpty || !newPattern.isValid)
            }
            if !newExpression.isEmpty && !newPattern.isValid {
                Text("That pattern isn't a valid regular expression.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}
