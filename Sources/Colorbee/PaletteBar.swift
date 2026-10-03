import AppKit
import ColorbeeCore
import SwiftUI

/// The row under the toolbar (FR-1.2): the color wells, swatches, custom colors, Alpha, Edit Colors…,
/// the palette, and the active tool's own settings.
struct PaletteBar<Options: View>: View {
    @Bindable var editor: Editor
    @ViewBuilder let toolOptions: Options

    var body: some View {
        HStack(spacing: 16) {
            ColorWells(editor: editor)
            SwatchGrid(editor: editor, custom: CustomColors.shared.slots)
                .frame(width: SwatchGridView.size.width, height: SwatchGridView.size.height)
            divider
            HStack(spacing: 10) {
                Text("Alpha").foregroundStyle(Theme.secondaryInk)
                Slider(value: alpha, in: 0...100)
                    .controlSize(.small)
                    .frame(width: 120)
                Text("\(Int(alpha.wrappedValue))%")
                    .monospacedDigit()
                    .frame(minWidth: 30, alignment: .trailing)
                    .padding(.horizontal, 7)
                    .frame(height: 22)
                    .background(Theme.field, in: RoundedRectangle(cornerRadius: 7))
            }
            .help("How see-through the \(editor.activeWell == .color1 ? "Color 1" : "Color 2") well is")
            Button("Edit Colors…") { ColorPanelController.shared.open(for: editor) }
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .help("Choose any color for the ringed well, with the Mac color picker")
            Menu {
                Button("Paint Classic") {}
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "paintpalette").foregroundStyle(Theme.secondaryInk)
                    Text("Paint Classic")
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).opacity(0.6)
                }
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("The palette. Saving and importing palettes comes in a later stage.")
            divider
            HStack(spacing: 10) { toolOptions }
                .controlSize(.small)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12))
        .padding(.leading, 18)
        .padding(.trailing, 16)
        .frame(height: 46)
    }

    private var divider: some View {
        Rectangle().fill(Theme.separator).frame(width: 1, height: 26)
    }

    private var alpha: Binding<Double> {
        Binding(
            get: { (Double(editor.activeColor.a) / 255 * 100).rounded() },
            set: { editor.activeColor.a = UInt8(($0 / 100 * 255).rounded()) }
        )
    }
}

private struct SwatchGrid: NSViewRepresentable {
    let editor: Editor
    /// Passed in so SwiftUI redraws the grid when a custom color changes.
    let custom: [Pixel?]

    func makeNSView(context: Context) -> SwatchGridView {
        SwatchGridView(editor: editor)
    }

    func updateNSView(_ view: SwatchGridView, context: Context) {
        view.custom = custom
    }
}

/// The 28 classic swatches and the 12 custom slots. Left-click sets the ringed well, right-click
/// Color 2, and Control-click on a custom color offers Remove (FR-1.2).
final class SwatchGridView: NSView, NSViewToolTipOwner {
    /// The classic Paint palette, as in the mockups.
    static let classic: [UInt32] = [
        0x000000, 0x808080, 0x800000, 0x808000, 0x008000, 0x008080, 0x000080, 0x800080, 0x808040, 0x004040, 0x0080FF, 0x004080, 0x8000FF, 0x804000,
        0xFFFFFF, 0xC0C0C0, 0xFF0000, 0xFFFF00, 0x00FF00, 0x00FFFF, 0x0000FF, 0xFF00FF, 0xFFFF80, 0x00FF80, 0x80FFFF, 0x8080FF, 0xFF0080, 0xFF8040,
    ]
    private static let cell: CGFloat = 17, gap: CGFloat = 2, groupGap: CGFloat = 10
    private static let classicWidth = 14 * cell + 13 * gap
    static let size = NSSize(width: classicWidth + groupGap + 6 * cell + 5 * gap, height: 2 * cell + gap)

    private let editor: Editor
    var custom: [Pixel?] = [] {
        didSet { needsDisplay = true }
    }

    init(editor: Editor) {
        self.editor = editor
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        for index in 0..<CustomColors.slotCount {
            addToolTip(rect(.custom(index)), owner: self, userData: nil)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }

    private enum Slot {
        case classic(Int)
        case custom(Int)
    }

    private func rect(_ slot: Slot) -> NSRect {
        let (column, row, originX): (Int, Int, CGFloat) = switch slot {
        case .classic(let index): (index % 14, index / 14, 0)
        case .custom(let index): (index % 6, index / 6, Self.classicWidth + Self.groupGap)
        }
        return NSRect(x: originX + CGFloat(column) * (Self.cell + Self.gap), y: CGFloat(row) * (Self.cell + Self.gap), width: Self.cell, height: Self.cell)
    }

    private func slot(at point: NSPoint) -> Slot? {
        for index in 0..<28 where rect(.classic(index)).contains(point) { return .classic(index) }
        for index in 0..<CustomColors.slotCount where rect(.custom(index)).contains(point) { return .custom(index) }
        return nil
    }

    private func color(of slot: Slot) -> Pixel? {
        switch slot {
        case .classic(let index):
            let hex = Self.classic[index]
            let color = NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
            return Pixel(color, in: editor.canvas.colorSpace)
        case .custom(let index):
            return custom.indices.contains(index) ? custom[index] : nil
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        for index in 0..<28 {
            let path = NSBezierPath(roundedRect: rect(.classic(index)), xRadius: 4, yRadius: 4)
            color(of: .classic(index))?.nsColor(in: editor.canvas.colorSpace).setFill()
            path.fill()
            NSColor.gray.withAlphaComponent(0.55).setStroke()
            path.lineWidth = 0.5
            path.stroke()
        }
        for index in 0..<CustomColors.slotCount {
            let box = rect(.custom(index))
            if let pixel = color(of: .custom(index)) {
                let path = NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4)
                pixel.nsColor(in: editor.canvas.colorSpace).setFill()
                path.fill()
                NSColor.gray.withAlphaComponent(0.55).setStroke()
                path.lineWidth = 0.5
                path.stroke()
            } else {
                let path = NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
                path.setLineDash([2, 2], count: 2, phase: 0)
                NSColor.tertiaryLabelColor.setStroke()
                path.stroke()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let slot = slot(at: point) else { return }
        if event.modifierFlags.contains(.control) {
            showMenu(for: slot, event: event)
        } else if case .custom(let index) = slot, color(of: slot) == nil {
            // Double-clicking an empty slot picks a color for it.
            if event.clickCount == 2 { ColorPanelController.shared.open(for: editor, slot: index) }
        } else if let pixel = color(of: slot) {
            editor.applySwatch(pixel, secondary: false)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let slot = slot(at: point), let pixel = color(of: slot) else { return }
        editor.applySwatch(pixel, secondary: true)
    }

    private func showMenu(for slot: Slot, event: NSEvent) {
        guard case .custom(let index) = slot, color(of: slot) != nil else { return }
        let menu = NSMenu()
        let remove = NSMenuItem(title: "Remove", action: #selector(removeCustom(_:)), keyEquivalent: "")
        remove.tag = index
        remove.target = self
        menu.addItem(remove)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func removeCustom(_ sender: NSMenuItem) {
        CustomColors.shared.remove(at: sender.tag)
    }

    /// Hover text for the custom slots, which depends on whether the slot holds a color.
    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        guard case .custom(let index)? = slot(at: point) else { return "" }
        return color(of: .custom(index)) == nil
            ? "Double-click to pick a custom color"
            : "Control-click to remove custom color"
    }
}

/// Edit Colors…: the Mac color picker, changing the ringed well. A color chosen there joins the custom
/// colors when the picker closes (FR-1.2): in the slot that was double-clicked, or the next empty one.
@MainActor
final class ColorPanelController: NSObject {
    static let shared = ColorPanelController()
    private weak var editor: Editor?
    private var changed = false
    private var slot: Int?

    func open(for editor: Editor, slot: Int? = nil) {
        finish()
        self.editor = editor
        self.slot = slot
        let panel = NSColorPanel.shared
        panel.showsAlpha = true
        panel.setTarget(nil)
        panel.color = editor.activeColor.nsColor(in: editor.canvas.colorSpace)
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        NotificationCenter.default.removeObserver(self)
        NotificationCenter.default.addObserver(self, selector: #selector(panelClosed(_:)), name: NSWindow.willCloseNotification, object: panel)
        panel.orderFront(nil)
    }

    @objc private func colorChanged(_ panel: NSColorPanel) {
        guard let editor else { return }
        editor.activeColor = Pixel(panel.color, in: editor.canvas.colorSpace)
        changed = true
    }

    @objc private func panelClosed(_ notification: Notification) {
        finish()
    }

    private func finish() {
        if changed, let color = editor?.activeColor {
            if let slot { CustomColors.shared.set(color, at: slot) } else { CustomColors.shared.add(color) }
        }
        changed = false
        slot = nil
    }
}
