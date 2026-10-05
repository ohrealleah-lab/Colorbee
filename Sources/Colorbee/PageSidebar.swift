import ColorbeeCore
import SwiftUI

/// The pages, down the left side (FR-11.6): a thumbnail each, in order. Clicking one shows it; dragging one moves it.
struct PageSidebar: View {
    @Bindable var editor: Editor
    /// The page being dragged to a new place, and how far it has moved.
    @State private var dragged: (index: Int, translation: CGFloat)?
    /// The thumbnail under the pointer, which a right-click shows before its menu opens.
    @State private var hovered: Int?
    private static let rowPitch: CGFloat = 150

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Pages").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(editor.pageCount)").font(.system(size: 11)).foregroundStyle(Theme.secondaryInk)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 6)
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(0..<editor.pageCount, id: \.self) { index in
                            let isDragged = dragged?.index == index
                            cell(index)
                                .id(index)
                                .offset(y: isDragged ? dragged?.translation ?? 0 : 0)
                                .shadow(color: .black.opacity(isDragged ? 0.25 : 0), radius: 6, y: 2)
                                .zIndex(isDragged ? 1 : 0)
                                .gesture(DragGesture(minimumDistance: 4)
                                    .onChanged { dragged = (index, $0.translation.height) }
                                    .onEnded { value in
                                        dragged = nil
                                        let steps = Int((value.translation.height / Self.rowPitch).rounded())
                                        let destination = min(max(index + steps, 0), editor.pageCount - 1)
                                        if destination != index { editor.movePage(from: index, to: destination) }
                                    })
                        }
                    }
                    .padding(.horizontal, 10)
                }
                .onChange(of: editor.currentPageIndex) { scroller.scrollTo(editor.currentPageIndex) }
            }
            HStack(spacing: 2) {
                footerButton("plus", "New Page") { editor.newPage() }
                footerButton("plus.square.on.square", "Duplicate Page") { editor.duplicatePage() }
                footerButton("trash", "Delete Page") { editor.deletePage() }
                    .disabled(editor.pageCount < 2)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .frame(width: 168)
        // Right-clicking shows the page first, so the menu acts on the one clicked (Leah, 2026-10-04). Which
        // thumbnail comes from hovering: each thumbnail's own view geometry matched every click, so the last page won.
        .background(RightClickWatcher {
            if let hovered, hovered < editor.pageCount { editor.showPage(at: hovered) }
        })
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
        .padding(8)
        .disabled(editor.activeEffect != nil)
    }

    private func cell(_ index: Int) -> some View {
        let isCurrent = index == editor.currentPageIndex
        return VStack(spacing: 4) {
            // The checkerboard and the border hug the page, so a tall page isn't framed by transparency it doesn't have.
            Group {
                if let image = image(for: index) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                        .background(Checkerboard(square: 5))
                } else {
                    Image(systemName: "doc").font(.system(size: 20)).foregroundStyle(Theme.secondaryInk)
                        .frame(width: 90, height: 118)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4)
                .strokeBorder(isCurrent ? Color.accentColor : Theme.separator, lineWidth: isCurrent ? 3 : 1))
            .frame(width: 120, height: 118)
            Text("\(index + 1)").font(.system(size: 11)).monospacedDigit()
                .foregroundStyle(isCurrent ? Color.accentColor : Theme.secondaryInk)
        }
        .frame(height: Self.rowPitch)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { editor.showPage(at: index) }
        .onHover { inside in
            if inside { hovered = index } else if hovered == index { hovered = nil }
        }
        .contextMenu {
            Button("New Page") { editor.newPage() }
            Button("Duplicate Page") { editor.duplicatePage() }
            Button("Delete Page") { editor.deletePage() }.disabled(editor.pageCount < 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(index + 1)")
        .accessibilityAddTraits(isCurrent ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction { editor.showPage(at: index) }
        .accessibilityAction(named: "Move Up") { editor.movePage(from: index, to: index - 1) }
        .accessibilityAction(named: "Move Down") { editor.movePage(from: index, to: index + 1) }
        .accessibilityAction(named: "Delete") { editor.showPage(at: index); editor.deletePage() }
    }

    private func image(for index: Int) -> NSImage? {
        guard let thumbnail = editor.pageThumbnail(at: index) else { return nil }
        let buffer = PixelBuffer(width: thumbnail.width, height: thumbnail.height)
        buffer.setPixels(thumbnail.pixels, in: buffer.bounds)
        guard let image = try? ImageCodec.makeCGImage(buffer, colorSpace: editor.canvas.colorSpace) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: thumbnail.width, height: thumbnail.height))
    }

    private func footerButton(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12)).frame(width: 26, height: 22)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}
