import ColorbeeCore
import SwiftUI

/// Over an animated GIF or multi-page TIFF: which frame this copy shows, and a way to pick another
/// (Leah; review J, finding 2).
struct FrameBar: View {
    @Bindable var editor: Editor
    let frames: Editor.Frames

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: frames.kind == .pages ? "doc.on.doc" : "film.stack")
                .foregroundStyle(Theme.secondaryInk)
                .accessibilityHidden(true)
            Text("This \(frames.kind == .pages ? "TIFF" : "GIF") has \(frames.count) \(frames.word)s · Showing \(frames.word) \(frames.index + 1)")
                .font(.system(size: 12))
            Button("Choose \(frames.word.capitalized)…") { editor.isChoosingFrame = true }
                .controlSize(.small)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Theme.field)
        .sheet(isPresented: $editor.isChoosingFrame) {
            FrameChooser(editor: editor, frames: frames)
        }
    }
}

/// The frames as thumbnails; clicking one opens it in place of this copy.
private struct FrameChooser: View {
    let editor: Editor
    let frames: Editor.Frames
    @State private var thumbnails: [CGImage] = []
    @State private var pending: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose a \(frames.word)").font(.headline)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                    ForEach(Array(thumbnails.enumerated()), id: \.offset) { index, image in
                        Button {
                            if editor.hasChanges, index != frames.index { pending = index } else { editor.chooseFrame(index) }
                        } label: {
                            VStack(spacing: 3) {
                                Image(decorative: image, scale: 1)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(height: 72)
                                    .background(Checkerboard(square: 4))
                                    .overlay(RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(index == frames.index ? Color.accentColor : Theme.separator, lineWidth: index == frames.index ? 2 : 1))
                                Text("\(index + 1)").font(.system(size: 10.5)).monospacedDigit()
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(frames.word.capitalized) \(index + 1)")
                    }
                }
            }
            .frame(minHeight: 200, maxHeight: 420)
            if frames.count > thumbnails.count, !thumbnails.isEmpty {
                Text("Showing the first \(thumbnails.count) of \(frames.count).").font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { editor.isChoosingFrame = false }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 520)
        .task {
            let data = frames.data
            thumbnails = await Task.detached { ImageCodec.frameThumbnails(data, maxSide: 192) }.value
        }
        .alert("Show \(frames.word) \((pending ?? 0) + 1) instead?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button("Show \(frames.word.capitalized) \((pending ?? 0) + 1)") {
                if let pending { editor.chooseFrame(pending) }
            }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: {
            Text("Your changes to \(frames.word) \(frames.index + 1) will be lost.")
        }
    }
}
