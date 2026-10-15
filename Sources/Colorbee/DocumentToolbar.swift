import AppKit
import ColorbeeCore
import SwiftUI

/// The window toolbar (FR-1.1). Each group sits in its own capsule, a shade darker than the window so the icons stand
/// out, drawn by Colorbee in place of the Liquid Glass one (Leah, 2026-10-15).
struct DocumentToolbar: ToolbarContent {
    let editor: Editor

    var body: some ToolbarContent {
        // A toolbar builder takes at most ten entries, so the groups come in two halves.
        SelectingGroups(editor: editor)
        PaintingGroups(editor: editor)
    }
}

/// Selection tools and the other tools.
private struct SelectingGroups: ToolbarContent {
    let editor: Editor

    var body: some ToolbarContent {
        // Tools wait while an effect's bar is open: Apply or Cancel first (§23, 2026-10-02; review J, finding 17).
        ToolbarItem {
            HStack(spacing: 0) {
                ToolButton(tool: .rectangleSelect, editor: editor)
                ToolButton(tool: .ellipseSelect, editor: editor)
                ToolButton(tool: .lassoSelect, editor: editor)
                ToolButton(tool: .magicWand, editor: editor)
                TransparentSelectionButton(editor: editor)
                    .disabled(editor.activeEffect != nil)
            }
            .inToolbarCapsule()
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarSpacer(.fixed)
        // The drawing tools in one group, Brushes and Shapes beside the Pencil (Leah, 2026-10-05).
        ToolbarItem {
            HStack(spacing: 0) {
                ToolButton(tool: .pencil, editor: editor)
                BrushGalleryButton(editor: editor)
                    .disabled(editor.activeEffect != nil)
                RetouchGalleryButton(editor: editor)
                    .disabled(editor.activeEffect != nil)
                ShapeGalleryButton(editor: editor)
                    .disabled(editor.activeEffect != nil)
                ForEach([Tool.fill, .text, .eraser, .eyedropper, .magnifier, .gradient, .measure, .redactBrush, .stepBadge], id: \.self) {
                    ToolButton(tool: $0, editor: editor)
                }
            }
            .inToolbarCapsule()
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarSpacer(.fixed)
    }
}

/// Size, and outline and fill, shown only for the tools that use them. Hidden ones keep their space, so the tools
/// never move (Leah, 2026-10-15).
private struct PaintingGroups: ToolbarContent {
    let editor: Editor

    var body: some ToolbarContent {
        ToolbarItem {
            SizeControl(editor: editor)
                .disabled(editor.activeEffect != nil)
                .inToolbarCapsule()
                .hiddenKeepingSpace(editor.toolSize == nil)
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarSpacer(.fixed)
        ToolbarItem {
            OutlineFillControl(editor: editor)
                .inToolbarCapsule()
                .hiddenKeepingSpace(editor.tool != .shape)
        }
        .sharedBackgroundVisibility(.hidden)
        // Pushes the groups up against the title; the Layers button sits at the far right.
        ToolbarSpacer(.flexible)
        ToolbarItem {
            HStack(spacing: 0) {
                LayersButton(editor: editor)
                SidebarButton(editor: editor)
            }
            .inToolbarCapsule()
        }
        .sharedBackgroundVisibility(.hidden)
    }
}

private extension View {
    /// A toolbar group's capsule: a shade darker than the window.
    func inToolbarCapsule() -> some View {
        padding(.horizontal, 5)
            .frame(height: 36)
            .background(Theme.toolbarCapsule, in: Capsule())
    }

    /// Invisible and out of reach, but still taking up its room in the toolbar.
    func hiddenKeepingSpace(_ hidden: Bool) -> some View {
        opacity(hidden ? 0 : 1)
            .disabled(hidden)
            .allowsHitTesting(!hidden)
            .accessibilityHidden(hidden)
    }
}

/// The look of a toolbar button: tinted with the accent color while its tool is in use.
struct ToolbarGlyph: View {
    let symbol: String
    var selected = false
    var width: CGFloat = 30

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15))
            .frame(width: width, height: 28)
            .foregroundStyle(selected ? Color.accentColor : Color.primary)
            .background(selected ? Theme.accentSoft : .clear, in: Capsule())
            .contentShape(Capsule())
    }
}

private struct ToolButton: View {
    let tool: Tool
    let editor: Editor

    var body: some View {
        Button { editor.selectTool(tool) } label: {
            ToolbarGlyph(symbol: tool.symbol, selected: editor.tool == tool)
        }
        .buttonStyle(.plain)
        .disabled(editor.activeEffect != nil)
        .help("\(tool.title): \(tool.summary)")
        .accessibilityLabel(tool.name)
    }
}

private struct TransparentSelectionButton: View {
    @Bindable var editor: Editor

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(Theme.separator).frame(width: 1, height: 16).padding(.horizontal, 3)
            Button { editor.transparentSelection.toggle() } label: {
                ToolbarGlyph(symbol: "checkerboard.rectangle", selected: editor.transparentSelection)
            }
            .buttonStyle(.plain)
            .help("Transparent Selection: pixels matching Color 2 aren't placed when a selection is moved or pasted")
            .accessibilityLabel("Transparent Selection")
        }
    }
}

// MARK: Size

/// Five preset sizes and a field for any size, for the tool in use (FR-1.1). Tools without a size don't show it.
private struct SizeControl: View {
    @Bindable var editor: Editor
    @FocusState private var typing: Bool

    var body: some View {
        let size = editor.toolSize
        HStack(spacing: 1) {
            ForEach(Array(editor.toolSizePresets.enumerated()), id: \.offset) { index, preset in
                Button { editor.toolSize = preset } label: {
                    RoundedRectangle(cornerRadius: 1)
                        .frame(width: 13, height: CGFloat(index + 1))
                        .frame(width: 22, height: 28)
                        .foregroundStyle(size == preset ? Color.accentColor : Color.primary)
                        .background(size == preset ? Theme.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 9))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(preset) px")
                .accessibilityLabel("Size \(preset) pixels")
                .accessibilityAddTraits(size == preset ? .isSelected : [])
            }
            HStack(spacing: 2) {
                TextField("Size", value: Binding(get: { size ?? 1 }, set: { editor.toolSize = $0 }), format: .number)
                    .focused($typing)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 22)
                Text("px").foregroundStyle(Theme.secondaryInk)
            }
            .font(.system(size: 12))
            .monospacedDigit()
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 7))
            // Each tool keeps its size within its own limits, and reading it back stops the drag there.
            .scrubs(Binding(get: { Double(editor.toolSize ?? 1) }, set: { editor.toolSize = Int($0) }),
                    in: Double(editor.toolSizeRange.lowerBound)...Double(editor.toolSizeRange.upperBound), focus: $typing,
                    passingClicksThrough: true)
            .padding(.leading, 4)
        }
        .padding(.trailing, 2)
        .help("Size of the \(editor.tool.name). [ and ] change it.")
    }
}

// MARK: Outline and fill

/// The shape outline and fill styles (FR-5.1). Only the Shapes tool uses them.
private struct OutlineFillControl: View {
    @Bindable var editor: Editor

    var body: some View {
        let open = editor.shapeKind.isOpen
        HStack(spacing: 0) {
            Menu {
                if !open {
                    Button("None") { editor.shapeOutline = nil }
                }
                ForEach(PaintStyle.allCases, id: \.self) { style in
                    Button(style.name) { editor.shapeOutline = style }
                }
            } label: {
                StyleLabel(title: "Outline", value: open ? (editor.shapeOutline ?? .solid).name : editor.shapeOutline?.name ?? "None",
                           outline: open || editor.shapeOutline != nil ? swatch(editor.color1) : nil, fill: nil)
            }
            .help("How shapes are outlined")
            Rectangle().fill(Theme.separator).frame(width: 1, height: 16)
            Menu {
                Button("None") { editor.shapeFill = nil }
                ForEach(PaintStyle.allCases, id: \.self) { style in
                    Button(style.name) { editor.shapeFill = style }
                }
            } label: {
                // The swatch shows Color 2, so a white fill on a white canvas isn't a surprise.
                StyleLabel(title: "Fill", value: open ? "None" : editor.shapeFill?.name ?? "None",
                           outline: nil, fill: !open && editor.shapeFill != nil ? swatch(editor.color2) : nil)
            }
            .disabled(open)
            .help(open ? "Lines, arrows and curves have no fill" : "How shapes are filled (with Color 2)")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }

    private func swatch(_ pixel: Pixel) -> Color {
        Color(nsColor: pixel.nsColor(in: editor.canvas.colorSpace))
    }

    /// The swatch is drawn in the colors a shape will get: Color 1 for the outline, Color 2 for the fill.
    private struct StyleLabel: View {
        let title: String
        let value: String
        let outline: Color?
        let fill: Color?

        var body: some View {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(fill ?? .clear)
                    .overlay {
                        RoundedRectangle(cornerRadius: 2.5)
                            .strokeBorder(outline ?? Color.secondary.opacity(fill == nil ? 1 : 0.6), lineWidth: outline == nil ? 1 : 2.4)
                    }
                    .frame(width: 14, height: 14)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.system(size: 9.5)).foregroundStyle(Theme.secondaryInk)
                    Text(value).font(.system(size: 12))
                }
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).opacity(0.6).accessibilityHidden(true)
            }
            .padding(.leading, 8)
            .padding(.trailing, 6)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
    }
}

// MARK: Color wells

/// Color 1 and Color 2 (FR-1.1). The ringed well is the one a swatch click sets; double-click a well
/// to choose its color, and the arrows swap them (X).
/// A color well as VoiceOver hears it: its name, its color, whether it's the ringed one, and Choose Color….
private struct WellAccessibility: ViewModifier {
    let name: String
    let color: Pixel
    let colorSpace: CGColorSpace
    let active: Bool
    let select: () -> Void
    let choose: () -> Void

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(name)
            .accessibilityValue(color.spokenDescription(in: colorSpace))
            .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { select() }
            .accessibilityAction(named: "Choose Color…") { choose() }
    }
}

struct ColorWells: View {
    @Bindable var editor: Editor

    var body: some View {
        ZStack(alignment: .topLeading) {
            well(editor.color2, active: editor.activeWell == .color2)
                .offset(x: 15, y: 9)
                .onTapGesture(count: 2) { open(.color2) }
                .onTapGesture { editor.activeWell = .color2 }
                .help("Color 2: right-click colors, fills and the eraser. Double-click to choose.")
                .modifier(WellAccessibility(name: "Color 2", color: editor.color2, colorSpace: editor.canvas.colorSpace, active: editor.activeWell == .color2,
                                            select: { editor.activeWell = .color2 }, choose: { open(.color2) }))
            well(editor.color1, active: editor.activeWell == .color1)
                .offset(x: 2, y: 2)
                .onTapGesture(count: 2) { open(.color1) }
                .onTapGesture { editor.activeWell = .color1 }
                .help("Color 1: left-click colors and outlines. Double-click to choose.")
                .modifier(WellAccessibility(name: "Color 1", color: editor.color1, colorSpace: editor.canvas.colorSpace, active: editor.activeWell == .color1,
                                            select: { editor.activeWell = .color1 }, choose: { open(.color1) }))
            Button { editor.swapColors() } label: {
                SwapArrow()
                    .stroke(Theme.secondaryInk, style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
                    .frame(width: 12, height: 12)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .offset(x: 34, y: -2)
            .help(ShortcutStore.shared.hint("Swap Color 1 and Color 2", command: "canvas.swapColors"))
            .accessibilityLabel("Swap Colors")
        }
        .frame(width: 48, height: 30, alignment: .topLeading)
        .padding(.horizontal, 6)
    }

    /// A curved arrow with a head at each end, from the left over the top and down on the right, as Leah drew it:
    /// SF Symbols has none (Leah, 2026-10-15).
    private struct SwapArrow: Shape {
        func path(in rect: CGRect) -> Path {
            let head = rect.width * 0.24
            let start = CGPoint(x: rect.minX + 1, y: rect.minY + head + 1)
            let end = CGPoint(x: rect.maxX - head - 1, y: rect.maxY - 1)
            var path = Path()
            path.move(to: start)
            path.addQuadCurve(to: end, control: CGPoint(x: end.x, y: start.y))
            // Pointing left at the start, down at the end.
            path.move(to: CGPoint(x: start.x + head, y: start.y - head))
            path.addLine(to: start)
            path.addLine(to: CGPoint(x: start.x + head, y: start.y + head))
            path.move(to: CGPoint(x: end.x - head, y: end.y - head))
            path.addLine(to: end)
            path.addLine(to: CGPoint(x: end.x + head, y: end.y - head))
            return path
        }
    }

    private func open(_ well: ColorWell) {
        editor.activeWell = well
        ColorPanelController.shared.open(for: editor)
    }

    private func well(_ color: Pixel, active: Bool) -> some View {
        ZStack {
            Checkerboard(square: 5)
            Rectangle().fill(Color(nsColor: color.nsColor(in: editor.canvas.colorSpace)))
        }
        .frame(width: 20, height: 20)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.gray.opacity(0.6), lineWidth: 0.5))
        .padding(2)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(active ? Color.accentColor : .clear, lineWidth: 1.5))
        .contentShape(Rectangle())
    }
}

/// Light and mid gray squares, shown behind see-through colors.
struct Checkerboard: View {
    let square: CGFloat

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            var y: CGFloat = 0, row = 0
            while y < size.height {
                var x: CGFloat = row.isMultiple(of: 2) ? 0 : square
                while x < size.width {
                    context.fill(Path(CGRect(x: x, y: y, width: square, height: square)), with: .color(Color(white: 0.8)))
                    x += square * 2
                }
                y += square
                row += 1
            }
        }
    }
}

/// Shows or hides the Layers panel (FR-1.1, FR-8.1), with the layer count once there's more than one.
private struct LayersButton: View {
    @Bindable var editor: Editor

    var body: some View {
        let count = editor.layers.count
        Button { editor.toggleLayersPanel() } label: {
            HStack(spacing: 4) {
                Image(systemName: "square.3.layers.3d").font(.system(size: 15))
                if count > 1 {
                    Text("\(count)")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(Color.accentColor, in: Capsule())
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .foregroundStyle(layersShowing ? Color.accentColor : Color.primary)
            .background(layersShowing ? Theme.accentSoft : .clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(ShortcutStore.shared.hint("Layers", command: "toggleLayers:"))
        .accessibilityLabel("Layers")
        .disabled(editor.activeEffect == .adjustPhoto)
    }

    private var layersShowing: Bool { editor.isSidebarOpen && editor.showsLayersPanel }
}

/// Shows or hides the whole sidebar.
private struct SidebarButton: View {
    @Bindable var editor: Editor

    var body: some View {
        Button { editor.toggleSidebar() } label: {
            ToolbarGlyph(symbol: "sidebar.right", selected: editor.isSidebarOpen)
        }
        .buttonStyle(.plain)
        // Adjust Photo's sliders are in the sidebar (review D, finding 5).
        .disabled(editor.activeEffect == .adjustPhoto)
        .help("Sidebar")
        .accessibilityLabel("Sidebar")
    }
}
