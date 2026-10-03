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
        .help("Pixel grid (⌘'). Shown at 400% and above.")
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
            HStack(spacing: 2) {
                Button("Zoom Out", systemImage: "minus.magnifyingglass") { editor.zoomOut() }
                    .labelStyle(.iconOnly)
                    .disabled(editor.viewport.zoom <= Viewport.minZoom)
                    .help("Zoom out (⌘-)")
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
                    .help("Zoom in (⌘=)")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
    }
}
