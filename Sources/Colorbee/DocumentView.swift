import AppKit
import ColorbeeCore
import SwiftUI

struct DocumentView: View {
    @Bindable var editor: Editor
    let canvasView: CanvasView

    var body: some View {
        VStack(spacing: 0) {
            ToolStrip(editor: editor)
            Divider()
            CanvasHost(view: canvasView)
            Divider()
            StatusBar(editor: editor)
        }
        .sheet(item: effectBinding) { kind in
            EffectSheet(editor: editor, kind: kind)
        }
    }
}

extension DocumentView {
    fileprivate var effectBinding: Binding<EffectKind?> {
        Binding(get: { editor.activeEffect }, set: { if $0 == nil, editor.activeEffect != nil { editor.cancelEffect() } })
    }
}

extension EffectKind: Identifiable {
    var id: Self { self }
}

private struct CanvasHost: NSViewRepresentable {
    let view: CanvasView

    func makeNSView(context: Context) -> CanvasView { view }
    func updateNSView(_ nsView: CanvasView, context: Context) {}
}

private struct ToolStrip: View {
    @Bindable var editor: Editor

    var body: some View {
        HStack(spacing: 14) {
            Picker("Tool", selection: toolBinding) {
                ForEach(Tool.allCases, id: \.self) { tool in
                    Label(tool.title, systemImage: tool.symbol).tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .labelsHidden()
            .fixedSize()
            Divider().frame(height: 20)
            ColorPicker("Color 1", selection: colorBinding(\.color1))
            ColorPicker("Color 2", selection: colorBinding(\.color2))
            Button("Swap", systemImage: "arrow.left.arrow.right") { editor.swapColors() }
                .labelStyle(.iconOnly)
                .help("Swap Color 1 and Color 2 (X)")
            Divider().frame(height: 20)
            ToolOptions(editor: editor)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var toolBinding: Binding<Tool> {
        Binding(get: { editor.tool }, set: { editor.selectTool($0) })
    }

    private func colorBinding(_ keyPath: ReferenceWritableKeyPath<Editor, Pixel>) -> Binding<Color> {
        let colorSpace = editor.canvas.colorSpace
        return Binding(
            get: { Color(nsColor: editor[keyPath: keyPath].nsColor(in: colorSpace)) },
            set: { editor[keyPath: keyPath] = Pixel(NSColor($0), in: colorSpace) }
        )
    }
}

/// Settings for the active tool.
private struct ToolOptions: View {
    @Bindable var editor: Editor

    var body: some View {
        switch editor.tool {
        case .brush:
            Picker("Brush", selection: $editor.brushKind) {
                Text("Round").tag(BrushKind.round)
                Text("Marker").tag(BrushKind.marker)
            }
            .fixedSize()
            sizeSlider
        case .eraser:
            Picker("Eraser size", selection: $editor.eraserSize) {
                ForEach(Editor.eraserSizes, id: \.self) { Text("\($0) px").tag($0) }
                if !Editor.eraserSizes.contains(editor.eraserSize) {
                    Text("\(editor.eraserSize) px").tag(editor.eraserSize)
                }
            }
            .fixedSize()
            .help("Left-drag erases. Right-drag replaces only Color 1 with Color 2. [ and ] change the size.")
        case .fill:
            Text("Tolerance")
            Slider(value: $editor.fillTolerance, in: 0...1)
                .frame(width: 140)
            Text("\(Int((editor.fillTolerance * 100).rounded()))%")
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
        case .eyedropper:
            Text("Click: Color 1 · Right-click: Color 2 · Option: all layers")
                .foregroundStyle(.secondary)
        case .rectangleSelect, .ellipseSelect, .lassoSelect:
            Toggle("Transparent Selection", systemImage: "square.on.square.dashed", isOn: $editor.transparentSelection)
                .toggleStyle(.button)
                .help("Transparent Selection: pixels matching Color 2 aren't placed")
            Picker("Resize", selection: $editor.smoothResize) {
                Text("Smooth").tag(true)
                Text("Sharp pixels").tag(false)
            }
            .fixedSize()
            .help("How resized selections are scaled. Drag a handle to stretch; hold Shift to keep proportions.")
        case .shape:
            Picker("Shape", selection: $editor.shapeKind) {
                ForEach(ShapeKind.allCases, id: \.self) { kind in
                    Label(kind.name, systemImage: kind.symbol).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .labelsHidden()
            .fixedSize()
            HStack {
                Text("Width")
                Slider(value: $editor.shapeLineWidth, in: 1...50, step: 1)
                    .frame(width: 100)
                Text("\(Int(editor.shapeLineWidth)) px")
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
            }
            if !editor.shapeKind.isLinear {
                Picker("Outline", selection: $editor.shapeHasOutline) {
                    Text("Solid").tag(true)
                    Text("None").tag(false)
                }
                .fixedSize()
                Picker("Fill", selection: $editor.shapeHasFill) {
                    Text("None").tag(false)
                    Text("Solid").tag(true)
                }
                .fixedSize()
            }
        case .pencil:
            Text("1 px · Shift draws straight lines")
                .foregroundStyle(.secondary)
        }
    }

    private var sizeSlider: some View {
        HStack {
            Text("Size")
            Slider(value: $editor.brushDiameter, in: 1...50, step: 1)
                .frame(width: 140)
            Text("\(Int(editor.brushDiameter)) px")
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
        }
    }
}

private extension Tool {
    var title: String {
        switch self {
        case .pencil: "Pencil (P)"
        case .brush: "Brush (B)"
        case .eraser: "Eraser (E)"
        case .fill: "Fill (G)"
        case .eyedropper: "Eyedropper (I)"
        case .shape: "Shapes (U)"
        case .rectangleSelect: "Rectangle Select (M)"
        case .ellipseSelect: "Ellipse Select"
        case .lassoSelect: "Free-Form Select (L)"
        }
    }

    var symbol: String {
        switch self {
        case .pencil: "pencil"
        case .brush: "paintbrush.pointed"
        case .eraser: "eraser"
        case .fill: "drop.fill"
        case .eyedropper: "eyedropper"
        case .shape: "square.on.circle"
        case .rectangleSelect: "rectangle.dashed"
        case .ellipseSelect: "circle.dashed"
        case .lassoSelect: "lasso"
        }
    }
}

/// The dialog for an effect, with a live preview on the canvas.
private struct EffectSheet: View {
    @Bindable var editor: Editor
    let kind: EffectKind

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(kind.title).font(.headline)
            HStack {
                Text(kind.valueLabel)
                Slider(value: $editor.effectValue, in: kind.range, step: 1)
                    .frame(width: 220)
                Text("\(Int(editor.effectValue)) px")
                    .monospacedDigit()
                    .frame(width: 50, alignment: .trailing)
            }
            Text(editor.hasSelection ? "Applies to the selection." : "Applies to the whole layer.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { editor.cancelEffect() }
                    .keyboardShortcut(.cancelAction)
                Button("Apply") { editor.applyEffect() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .onChange(of: editor.effectValue) { editor.previewEffect() }
    }
}

private struct StatusBar: View {
    @Bindable var editor: Editor

    var body: some View {
        HStack(spacing: 20) {
            Label(pointerText, systemImage: "cursorarrow")
                .frame(width: 130, alignment: .leading)
            Label(selectionText, systemImage: "rectangle.dashed")
                .frame(width: 170, alignment: .leading)
            Label("\(editor.canvasSize.width) × \(editor.canvasSize.height) px", systemImage: "photo")
            Spacer()
            Toggle("Pixel Grid", systemImage: "grid", isOn: $editor.showsPixelGrid)
                .toggleStyle(.button)
                .controlSize(.small)
                .disabled(editor.viewport.zoom < Renderer.pixelGridMinimumZoom)
                .help("Pixel grid (⌘') — shown at 400% and above")
            Text("\(Int((editor.viewport.zoom * 100).rounded()))%")
                .frame(width: 60, alignment: .trailing)
            Button("100%") { editor.zoomToActualSize() }
                .controlSize(.small)
        }
        .font(.callout)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
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
}

private extension ShapeKind {
    var symbol: String {
        switch self {
        case .line: "line.diagonal"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .roundedRectangle: "app"
        case .ellipse: "circle"
        }
    }
}
