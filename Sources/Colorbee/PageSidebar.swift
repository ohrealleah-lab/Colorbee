import ColorbeeCore
import SwiftUI

/// The pages, down the left side (FR-11.6): a thumbnail each, in order. Clicking one shows it; dragging one moves it.
struct PageSidebar: View {
    @Bindable var editor: Editor
    /// The page being dragged to a new place.
    @State private var drag: PageDrag?
    /// Where the list is scrolled to, so a drag can scroll it and count how far it has gone (review L, finding 13).
    @State private var scroll = ScrollPosition(edge: .top)
    @State private var scrolled: CGFloat = 0
    @State private var maxScroll: CGFloat = 0
    @State private var places = Places()
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
                            let isDragged = drag?.index == index
                            cell(index)
                                .id(index)
                                .offset(y: isDragged ? travel : 0)
                                .shadow(color: .black.opacity(isDragged ? 0.25 : 0), radius: 6, y: 2)
                                .zIndex(isDragged ? 1 : 0)
                                .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .global)
                                    .onChanged { value in
                                        if drag == nil {
                                            drag = PageDrag(index: index, startY: value.startLocation.y, startScroll: scrolled, y: value.location.y)
                                            scrollWhileHeldAtAnEdge()
                                        }
                                        drag?.y = value.location.y
                                    }
                                    .onEnded { _ in
                                        guard let ended = drag else { return }
                                        let destination = min(max(ended.index + Int((travel / Self.rowPitch).rounded()), 0), editor.pageCount - 1)
                                        drag = nil
                                        if destination != ended.index { editor.movePage(from: ended.index, to: destination) }
                                    })
                        }
                    }
                    .padding(.horizontal, 10)
                }
                .scrollPosition($scroll)
                .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, offset in scrolled = offset }
                .onScrollGeometryChange(for: CGFloat.self) { max(0, $0.contentSize.height - $0.containerSize.height) } action: { _, most in
                    maxScroll = most
                }
                .onChange(of: editor.currentPageIndex) { scroller.scrollTo(editor.currentPageIndex) }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { places.list = $0 }
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
        // Right-clicking shows the page first, so the menu acts on the one clicked (Leah, 2026-10-04). The page is
        // found from where the thumbnails are: hover state only catches up after the click is handled.
        .background(RightClickWatcher { point in
            guard places.list.contains(point),
                  let index = places.thumbnails.first(where: { $0.value.contains(point) })?.key,
                  index < editor.pageCount else { return }
            editor.showPage(at: index)
        })
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
        .padding(8)
        .disabled(editor.activeEffect != nil)
    }

    /// How far the dragged page has moved within the list: the pointer's movement plus any scrolling since.
    private var travel: CGFloat {
        guard let drag else { return 0 }
        return drag.y - drag.startY + scrolled - drag.startScroll
    }

    /// While a dragged page is held near the top or bottom of the list, the list scrolls, so a page can go anywhere
    /// in a long document.
    private func scrollWhileHeldAtAnEdge() {
        Task { @MainActor in
            while let held = drag {
                let edge: CGFloat = 40, list = places.list
                let step: CGFloat = held.y < list.minY + edge ? -14 : held.y > list.maxY - edge ? 14 : 0
                if step != 0 { scroll.scrollTo(y: min(max(scrolled + step, 0), maxScroll)) }
                try? await Task.sleep(for: .milliseconds(30))
            }
        }
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
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { places.thumbnails[index] = $0 }
        // Each command shows its page first too, in case the right-click didn't.
        .contextMenu {
            Button("New Page") { editor.showPage(at: index); editor.newPage() }
            Button("Duplicate Page") { editor.showPage(at: index); editor.duplicatePage() }
            Button("Delete Page") { editor.showPage(at: index); editor.deletePage() }.disabled(editor.pageCount < 2)
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

/// Where the list and each thumbnail are in the window, for right-clicks. Not observed: they change as the list
/// scrolls, and nothing on screen depends on them.
private final class Places {
    var list: CGRect = .zero
    var thumbnails: [Int: CGRect] = [:]
}

/// A page being dragged: where the pointer started and is, and how far the list was scrolled at the start.
private struct PageDrag {
    let index: Int
    let startY: CGFloat
    let startScroll: CGFloat
    var y: CGFloat
}
