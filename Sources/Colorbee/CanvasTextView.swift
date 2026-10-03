import AppKit
import ColorbeeCore

/// The in-place editor for the text tool: a borderless text view laid over the canvas and scaled to its zoom.
/// What's typed here is rasterized by `TextRenderer` when it's placed.
final class CanvasTextView: NSTextView {
    var onCommit: () -> Void = {}
    /// Layout managers don't retain their storage, so the view has to.
    private var ownedStorage: NSTextStorage?

    static func make() -> CanvasTextView {
        let container = NSTextContainer(size: NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.widthTracksTextView = false
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(container)
        let storage = NSTextStorage()
        storage.addLayoutManager(layoutManager)

        let view = CanvasTextView(frame: .zero, textContainer: container)
        view.ownedStorage = storage
        view.textContainerInset = .zero
        view.isRichText = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = true
        view.focusRingType = .none
        // A selected wrapped line highlights to the far edge of its line; keep that inside the box.
        view.clipsToBounds = true
        return view
    }

    /// Esc places the text (FR-6.3).
    override func cancelOperation(_ sender: Any?) {
        onCommit()
    }

    /// Applies the style at the given zoom to all of the text and to what's typed next.
    func apply(_ spec: TextSpec, zoom: Double, colorSpace: CGColorSpace) {
        var traits: NSFontDescriptor.SymbolicTraits = []
        if spec.bold { traits.insert(.bold) }
        if spec.italic { traits.insert(.italic) }
        let descriptor = NSFontDescriptor(fontAttributes: [.family: spec.fontFamily]).withSymbolicTraits(traits)
        let font = NSFont(descriptor: descriptor, size: spec.fontSize * zoom) ?? .systemFont(ofSize: spec.fontSize * zoom)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = switch spec.alignment {
        case .left: .left
        case .center: .center
        case .right: .right
        }
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: spec.color.nsColor(in: colorSpace),
            .paragraphStyle: paragraph,
        ]
        if spec.underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if spec.strikethrough { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }

        typingAttributes = attributes
        textStorage?.setAttributes(attributes, range: NSRange(location: 0, length: textStorage?.length ?? 0))
        insertionPointColor = spec.color.nsColor(in: colorSpace)
        if let background = spec.background {
            drawsBackground = true
            backgroundColor = background.nsColor(in: colorSpace)
        } else {
            drawsBackground = false
        }
    }

    /// Sizes the view to its text. `wrapWidth` is in view points.
    func fit(at origin: NSPoint, wrapWidth: Double?, minimumHeight: Double = 0) {
        guard let container = textContainer, let layoutManager else { return }
        if let wrapWidth {
            isHorizontallyResizable = false
            container.containerSize = NSSize(width: wrapWidth, height: .greatestFiniteMagnitude)
        } else {
            isHorizontallyResizable = true
            container.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        }
        layoutManager.ensureLayout(for: container)
        let used = layoutManager.usedRect(for: container)
        let font = typingAttributes[.font] as? NSFont ?? .systemFont(ofSize: 12)
        let lineHeight = layoutManager.defaultLineHeight(for: font)
        let width = wrapWidth ?? max(used.width + 4, lineHeight / 2)
        frame = NSRect(x: origin.x, y: origin.y, width: width, height: max(used.height, lineHeight, minimumHeight))
    }
}
