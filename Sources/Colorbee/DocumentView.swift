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
    }
}

private struct CanvasHost: NSViewRepresentable {
    let view: CanvasView

    func makeNSView(context: Context) -> CanvasView { view }
    func updateNSView(_ nsView: CanvasView, context: Context) {}
}

private struct ToolStrip: View {
    @Bindable var editor: Editor

    var body: some View {
        HStack(spacing: 16) {
            Picker("Tool", selection: toolBinding) {
                Label("Brush (B)", systemImage: "paintbrush.pointed").tag(Tool.brush)
                Label("Rectangle Select (M)", systemImage: "rectangle.dashed").tag(Tool.rectangleSelect)
                Label("Ellipse Select", systemImage: "circle.dashed").tag(Tool.ellipseSelect)
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .labelsHidden()
            .fixedSize()
            Toggle("Transparent Selection", systemImage: "square.on.square.dashed", isOn: $editor.transparentSelection)
                .toggleStyle(.button)
                .labelStyle(.iconOnly)
                .help("Transparent Selection: pixels matching Color 2 aren't placed")
            Divider().frame(height: 20)
            ColorPicker("Color 1", selection: colorBinding(\.color1))
            ColorPicker("Color 2", selection: colorBinding(\.color2))
            Button("Swap", systemImage: "arrow.left.arrow.right") { editor.swapColors() }
                .labelStyle(.iconOnly)
                .help("Swap Color 1 and Color 2 (X)")
            Divider().frame(height: 20)
            Text("Size")
            Slider(value: $editor.brushDiameter, in: 1...50, step: 1)
                .frame(width: 160)
            Text("\(Int(editor.brushDiameter)) px")
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
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

private struct StatusBar: View {
    @Bindable var editor: Editor

    var body: some View {
        HStack(spacing: 20) {
            Label(pointerText, systemImage: "cursorarrow")
                .frame(width: 130, alignment: .leading)
            Label(selectionText, systemImage: "rectangle.dashed")
                .frame(width: 130, alignment: .leading)
            Label("\(editor.canvas.size.width) × \(editor.canvas.size.height) px", systemImage: "photo")
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
        return "\(bounds.width) × \(bounds.height) px"
    }

    private var pointerText: String {
        guard let pointer = editor.pointer else { return "—" }
        return "\(pointer.x), \(pointer.y) px"
    }
}
