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
            SwatchGrid(editor: editor, swatches: PaletteStore.shared.swatches, custom: CustomColors.shared.slots)
                .frame(width: SwatchGridView.size.width, height: SwatchGridView.size.height)
            divider
            HStack(spacing: 10) {
                Text("Alpha").foregroundStyle(Theme.secondaryInk)
                Slider(value: alpha, in: 0...100)
                    .controlSize(.small)
                    .frame(width: 120)
                    .accessibilityLabel("Alpha")
                    .accessibilityValue("\(Int(alpha.wrappedValue)) percent")
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
            PaletteMenu(store: PaletteStore.shared) {
                HStack(spacing: 5) {
                    Image(systemName: "paintpalette").foregroundStyle(Theme.secondaryInk).accessibilityHidden(true)
                    Text(PaletteStore.shared.activeName)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).opacity(0.6).accessibilityHidden(true)
                }
            }
            .accessibilityLabel("Palette: \(PaletteStore.shared.activeName)")
            .help("Palettes: switch, save, rename, import or export your swatches and custom colors")
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
    /// Passed in so SwiftUI redraws the grid when the palette or a custom color changes.
    let swatches: [UInt32]
    let custom: [Pixel?]

    func makeNSView(context: Context) -> SwatchGridView {
        SwatchGridView(editor: editor)
    }

    func updateNSView(_ view: SwatchGridView, context: Context) {
        view.swatches = swatches
        view.custom = custom
    }
}

/// The 28 classic swatches and the 12 custom slots. Left-click sets the ringed well, right-click
/// Color 2, and Control-click on a custom color offers Remove (FR-1.2).
final class SwatchGridView: NSView, NSViewToolTipOwner {
    private static let cell: CGFloat = 17, gap: CGFloat = 2, groupGap: CGFloat = 10
    private static let classicWidth = 14 * cell + 13 * gap
    static let size = NSSize(width: classicWidth + groupGap + 6 * cell + 5 * gap, height: 2 * cell + gap)

    private let editor: Editor
    var swatches: [UInt32] = Palette.classic.swatches {
        didSet { needsDisplay = true }
    }
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
            let hex = swatches.indices.contains(index) ? swatches[index] : 0
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

    // MARK: Accessibility

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityLabel() -> String? { "Colors" }

    /// Each swatch and custom slot as a button VoiceOver can press: it sets the ringed well, as a click does.
    override func accessibilityChildren() -> [Any]? {
        let classic = (0..<28).map { index in
            SwatchElement(parent: self, frame: rect(.classic(index)), label: "Swatch \(index + 1)",
                          value: color(of: .classic(index))?.spokenDescription(in: editor.canvas.colorSpace),
                          actions: [("Set Color 2", { [weak self] in
                              guard let self, let pixel = color(of: .classic(index)) else { return }
                              editor.applySwatch(pixel, secondary: true)
                          })]) { [weak self] in
                guard let self, let pixel = color(of: .classic(index)) else { return }
                editor.applySwatch(pixel, secondary: false)
            }
        }
        let customs = (0..<CustomColors.slotCount).map { index in
            let pixel = color(of: .custom(index))
            let actions: [(String, () -> Void)] = pixel == nil ? [] : [
                ("Set Color 2", { [weak self] in
                    guard let self, let pixel = color(of: .custom(index)) else { return }
                    editor.applySwatch(pixel, secondary: true)
                }),
                ("Remove", { CustomColors.shared.remove(at: index) }),
            ]
            return SwatchElement(parent: self, frame: rect(.custom(index)), label: "Custom color \(index + 1)",
                                 value: pixel?.spokenDescription(in: editor.canvas.colorSpace) ?? "Empty", actions: actions) { [weak self] in
                guard let self else { return }
                if let pixel = color(of: .custom(index)) {
                    editor.applySwatch(pixel, secondary: false)
                } else {
                    ColorPanelController.shared.open(for: editor, slot: index)
                }
            }
        }
        return classic + customs
    }

    /// Hover text for the custom slots, which depends on whether the slot holds a color.
    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        guard case .custom(let index)? = slot(at: point) else { return "" }
        return color(of: .custom(index)) == nil
            ? "Double-click to pick a custom color"
            : "Control-click to remove custom color"
    }
}

/// One swatch in the grid, for VoiceOver.
private final class SwatchElement: NSAccessibilityElement {
    private let press: () -> Void

    /// Right-click and Control-click actions, for VoiceOver (review J, finding 29: A8).
    init(parent: NSView, frame: NSRect, label: String, value: String?, actions: [(String, () -> Void)] = [], press: @escaping () -> Void) {
        self.press = press
        super.init()
        setAccessibilityCustomActions(actions.map { name, handler in
            NSAccessibilityCustomAction(name: name) { handler(); return true }
        })
        setAccessibilityParent(parent)
        setAccessibilityRole(.button)
        setAccessibilityLabel(label)
        setAccessibilityValue(value)
        setAccessibilityFrameInParentSpace(frame)
    }

    override func accessibilityPerformPress() -> Bool {
        press()
        return true
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

/// The palette menu (FR-15.1): switch palettes, save the current colors, rename, delete, import, export, reset.
private struct PaletteMenu<Label: View>: View {
    let store: PaletteStore
    @ViewBuilder let label: Label

    var body: some View {
        Menu {
            ForEach(store.all, id: \.name) { palette in
                Toggle(palette.name, isOn: Binding(get: { palette.name == store.activeName }, set: { _ in store.load(palette) }))
            }
            Divider()
            Button("Save Palette As…") {
                if let name = askForName("Save Palette", message: "Saves the 28 swatches and the 12 custom colors.", defaultName: "My Palette") {
                    store.saveCurrent(as: name)
                }
            }
            Button("Rename Palette…") {
                if let name = askForName("Rename Palette", defaultName: store.activeName, confirm: "Rename") {
                    store.rename(store.activeName, to: name)
                }
            }
            .disabled(store.activeName == Palette.classic.name)
            Button("Delete Palette") { store.delete(store.activeName) }
                .disabled(store.activeName == Palette.classic.name)
            Divider()
            Button("Import Palette…") { importPalette() }
            Button("Export Palette…") { exportPalette() }
            Divider()
            Button("Reset to Paint Classic") { store.resetToClassic() }
        } label: {
            label
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func importPalette() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.colorbeePalette]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try store.importPalette(from: url) } catch { NSAlert(error: error).runModal() }
    }

    private func exportPalette() {
        let palette = Palette(name: store.activeName, swatches: store.swatches, custom: CustomColors.shared.packed)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.colorbeePalette]
        panel.nameFieldStringValue = palette.name
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try store.export(palette, to: url) } catch { NSAlert(error: error).runModal() }
    }
}
