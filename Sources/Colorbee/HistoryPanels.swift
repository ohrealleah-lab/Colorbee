import AppKit
import ColorbeeCore
import SwiftUI

/// The History panel (FR-13.2): every step with a small picture. Clicking one jumps there; steps after
/// it are dimmed and can be redone until the next change.
struct HistoryPanel: View {
    @Bindable var editor: Editor

    var body: some View {
        let steps = editor.historySteps
        let done = steps.filter { !$0.isUndone }.count
        ScrollViewReader { scroller in
            ScrollView {
                VStack(spacing: 2) {
                    row(name: "Opened", thumbnail: nil, isCurrent: done == 0, isUndone: false) { editor.jump(toStep: 0) }
                        .id(0)
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        row(name: step.name, thumbnail: step.thumbnail, isCurrent: index + 1 == done, isUndone: step.isUndone) {
                            editor.jump(toStep: index + 1)
                        }
                        .id(index + 1)
                    }
                }
                .padding(.horizontal, 6)
            }
            .onChange(of: steps.count) { scroller.scrollTo(done, anchor: .bottom) }
        }
        .frame(minHeight: 100, maxHeight: .infinity)
    }

    private func row(name: String, thumbnail: Thumbnail?, isCurrent: Bool, isUndone: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Group {
                    if let image = thumbnail.flatMap(image(for:)) {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "doc").font(.system(size: 11)).foregroundStyle(Theme.secondaryInk)
                    }
                }
                .frame(width: 32, height: 22)
                .background(Theme.field)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                Text(name).font(.system(size: 12)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(height: 30)
            .foregroundStyle(isCurrent ? Color.white : Color.primary)
            .background(isCurrent ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 7))
            .opacity(isUndone ? 0.45 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isUndone ? "Undone: click to redo up to here" : "Click to go back to this point")
    }

    private func image(for thumbnail: Thumbnail) -> NSImage? {
        let buffer = PixelBuffer(width: thumbnail.width, height: thumbnail.height)
        buffer.setPixels(thumbnail.pixels, in: buffer.bounds)
        guard let cgImage = try? ImageCodec.makeCGImage(buffer, colorSpace: editor.canvas.colorSpace) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: thumbnail.width, height: thumbnail.height))
    }
}

/// The Clipboard History panel (FR-10.2): the last 10 images copied or pasted. Clicking one pastes it
/// as a floating selection without changing the system clipboard.
struct ClipboardPanel: View {
    let editor: Editor
    private let history = ClipboardHistory.shared

    var body: some View {
        VStack(spacing: 6) {
            if history.items.isEmpty {
                Text("Images you copy or paste appear here.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondaryInk)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                        ForEach(history.items) { item in
                            Button { paste(item) } label: {
                                Group {
                                    if let image = history.thumbnail(for: item) {
                                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                                    } else {
                                        Image(systemName: "photo")
                                    }
                                }
                                .frame(height: 70)
                                .frame(maxWidth: .infinity)
                                .background(Checkerboard(square: 5))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.separator))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("\(item.date.formatted(date: .abbreviated, time: .shortened)) · \(item.width) × \(item.height) px")
                        }
                    }
                    .padding(.horizontal, 10)
                }
                HStack {
                    Spacer()
                    Button("Clear") { history.clear() }
                        .controlSize(.small)
                        .help("Forget all of these images")
                }
                .padding(.horizontal, 10)
            }
        }
        .padding(.bottom, 8)
        .frame(minHeight: 100, maxHeight: .infinity)
    }

    private func paste(_ item: ClipboardHistory.Item) {
        guard let data = history.data(for: item),
              let decoded = try? ImageCodec.decode(data, convertingTo: editor.canvas.colorSpace) else { return }
        editor.paste(decoded.buffer)
    }
}
