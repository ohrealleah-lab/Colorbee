import ColorbeeCore
import SwiftUI

/// The bar along the bottom (FR-1.5): pointer, selection, measurement and canvas size on the left;
/// Pixel Grid, Symmetry and zoom on the right.
struct StatusBar: View {
    @Bindable var editor: Editor

    var body: some View {
        HStack(spacing: 10) {
            item("cursorarrow", pointerText).frame(minWidth: 92, alignment: .leading)
            divider
            ColorReadout(color: editor.pointerColor)
                .frame(minWidth: 150, alignment: .leading)
                .layoutPriority(-1)
            divider
            item("rectangle.dashed", selectionText).frame(minWidth: 100, alignment: .leading)
            divider
            item("ruler", measureText).frame(minWidth: 80, alignment: .leading)
            divider
            item("aspectratio", canvasText)
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                PixelGridChip(editor: editor)
                SymmetryChip(editor: editor)
            }
            divider
            ZoomControl(editor: editor)
        }
        .font(.system(size: 11))
        .monospacedDigit()
        .foregroundStyle(Theme.secondaryInk)
        .lineLimit(1)
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .frame(height: 28)
    }

    private var divider: some View {
        Rectangle().fill(Theme.separator).frame(width: 1, height: 12)
    }

    private func item(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 11)).accessibilityHidden(true)
            Text(text)
        }
    }

    private var selectionText: String {
        guard let bounds = editor.selectionBounds else { return "—" }
        let size = "\(bounds.width) × \(bounds.height) px"
        return editor.selectionScalePercent.map { "\(size) · \($0)%" } ?? size
    }

    private var pointerText: String {
        guard let pointer = editor.pointer else { return "—" }
        return "\(pointer.x), \(pointer.y) px"
    }

    /// The canvas size, and while an edge handle is dragged, the size it will become.
    private var canvasText: String {
        let size = "\(editor.canvasSize.width) × \(editor.canvasSize.height) px"
        guard let preview = editor.canvasResizePreview else { return size }
        return "\(size) → \(preview.width) × \(preview.height) px"
    }

    private var measureText: String {
        guard let measurement = editor.measurement else { return "—" }
        return String(format: "%.1f px · ΔX %d · ΔY %d · %.1f°", measurement.distance, measurement.dx, measurement.dy, measurement.angle)
    }
}

/// The color under the pointer (FR-9.7 item 9): a swatch, its sRGB values and hex. A click on the hex copies it.
private struct ColorReadout: View {
    let color: Pixel?
    @State private var copied = false

    var body: some View {
        if let color {
            let hex = String(format: "#%02X%02X%02X", color.r, color.g, color.b)
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(.sRGB, red: Double(color.r) / 255, green: Double(color.g) / 255, blue: Double(color.b) / 255, opacity: Double(color.a) / 255))
                    .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Theme.separator))
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                Text("sRGB \(color.r) \(color.g) \(color.b)" + (color.a < 255 ? " · \(Int((Double(color.a) / 255 * 100).rounded()))%" : ""))
                Button(copied ? "Copied" : hex) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(hex, forType: .string)
                    copied = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.2))
                        copied = false
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .help("Copy \(hex)")
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Color under the pointer, sRGB \(color.r), \(color.g), \(color.b), \(hex)")
        } else {
            HStack(spacing: 5) {
                Image(systemName: "eyedropper").font(.system(size: 11)).accessibilityHidden(true)
                Text("—")
            }
        }
    }
}

/// A rounded switch for the status bar, tinted while on.
private struct Chip: View {
    let symbol: String
    let title: String
    let on: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 11)).accessibilityHidden(true)
            Text(title)
        }
        .padding(.horizontal, 8)
        .frame(height: 20)
        .foregroundStyle(on ? Color.accentColor : Theme.secondaryInk)
        .background(on ? Theme.accentSoft : Theme.field, in: Capsule())
        .contentShape(Capsule())
        // On and off aren't only a color for VoiceOver (review J, finding 29: A7).
        .accessibilityElement(children: .combine)
        .accessibilityValue(on ? "On" : "Off")
    }
}

private struct PixelGridChip: View {
    @Bindable var editor: Editor

    var body: some View {
        let available = editor.viewport.zoom >= Renderer.pixelGridMinimumZoom
        Button { editor.showsPixelGrid.toggle() } label: {
            Chip(symbol: "grid", title: "Pixel Grid", on: editor.showsPixelGrid && available)
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .opacity(available ? 1 : 0.5)
        .help(ShortcutStore.shared.hint("Pixel grid", command: "togglePixelGrid:") + ". Shown at 400% and above.")
    }
}

private struct SymmetryChip: View {
    @Bindable var editor: Editor

    var body: some View {
        Menu {
            Picker("Symmetry", selection: $editor.symmetry) {
                ForEach(SymmetryMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Chip(
                symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right",
                title: editor.symmetry == .off ? "Symmetry" : "Symmetry: \(editor.symmetry.title)",
                on: editor.symmetry != .off
            )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Mirror Pencil, Brush and Eraser strokes across the image's center lines")
    }
}

/// The zoom slider (logarithmic, 12.5% to 3200%), then − and + around the percentage, which opens a
/// list of common zoom levels.
private struct ZoomControl: View {
    let editor: Editor

    private static let presets = [0.25, 0.5, 0.75, 1.0]

    var body: some View {
        HStack(spacing: 6) {
            Slider(value: Binding(
                get: { Viewport.sliderPosition(forZoom: editor.viewport.zoom) },
                set: { editor.zoom(to: Viewport.zoom(forSliderPosition: $0)) }
            ), in: 0...1)
            .controlSize(.mini)
            .frame(width: 100)
            .help("Zoom")
            .accessibilityLabel("Zoom")
            .accessibilityValue("\(Int((editor.viewport.zoom * 100).rounded())) percent")
            HStack(spacing: 2) {
                Button("Zoom Out", systemImage: "minus.magnifyingglass") { editor.zoomOut() }
                    .labelStyle(.iconOnly)
                    .disabled(editor.viewport.zoom <= Viewport.minZoom)
                    .help(ShortcutStore.shared.hint("Zoom out", command: "zoomOut:"))
                Menu("\(Int((editor.viewport.zoom * 100).rounded()))%") {
                    ForEach(Self.presets, id: \.self) { scale in
                        Button("\(Int(scale * 100))%") { editor.zoom(to: scale) }
                    }
                }
                .menuStyle(.button)
                .menuIndicator(.visible)
                .foregroundStyle(.primary)
                .frame(width: 62)
                .help("Choose a zoom level")
                Button("Zoom In", systemImage: "plus.magnifyingglass") { editor.zoomIn() }
                    .labelStyle(.iconOnly)
                    .disabled(editor.viewport.zoom >= Viewport.maxZoom)
                    .help(ShortcutStore.shared.hint("Zoom in", command: "zoomIn:"))
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
    }
}
