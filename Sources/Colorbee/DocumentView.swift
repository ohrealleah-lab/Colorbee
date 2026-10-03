import AppKit
import ColorbeeCore
import SwiftUI

struct DocumentView: View {
    @Bindable var editor: Editor
    let canvasView: CanvasView

    var body: some View {
        VStack(spacing: 0) {
            PaletteBar(editor: editor) { ToolOptions(editor: editor) }
                .disabled(editor.activeEffect != nil)
            Divider()
            // Docked rather than a sheet, so the image stays fully visible while the preview updates.
            if let kind = editor.activeEffect {
                EffectBar(editor: editor, kind: kind)
                Divider()
            }
            if editor.comparison != nil {
                CompareBar(editor: editor)
                Divider()
            }
            CanvasHost(view: canvasView)
                .overlay {
                    if editor.showsRulers { Rulers(editor: editor) }
                }
                // Floats over the gray surround rather than narrowing the canvas, as in the mockups.
                .overlay(alignment: .trailing) {
                    if editor.isSidebarOpen {
                        Sidebar(editor: editor)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(.snappy(duration: 0.2), value: editor.isSidebarOpen)
                .sheet(isPresented: autoRedactBinding) {
                    AutoRedactSheet(editor: editor)
                }
            if editor.showsStatusBar {
                Divider()
                StatusBar(editor: editor)
            }
        }
        .toolbar { DocumentToolbar(editor: editor) }
        .sheet(isPresented: $editor.isCanvasPropertiesOpen) {
            CanvasPropertiesSheet(editor: editor)
        }
        .sheet(isPresented: $editor.isResizeSkewOpen) {
            ResizeSkewSheet(editor: editor, base: editor.resizeSkewBaseSize, appliesToSelection: editor.hasSelection)
        }
    }
}

extension DocumentView {
    fileprivate var autoRedactBinding: Binding<Bool> {
        Binding(get: { editor.autoRedact != nil }, set: { if !$0, editor.autoRedact != nil { editor.cancelAutoRedact() } })
    }
}

private struct CanvasHost: NSViewRepresentable {
    let view: CanvasView

    func makeNSView(context: Context) -> CanvasView { view }
    func updateNSView(_ nsView: CanvasView, context: Context) {}
}

/// Settings for the active tool.
private struct ToolOptions: View {
    @Bindable var editor: Editor

    var body: some View {
        switch editor.tool {
        case .brush:
            hint("\(editor.brush.name) · Shift has no effect · pressure \(editor.usesPressure ? "on" : "off")")
        case .eraser:
            hint("Right-drag replaces only Color 1 with Color 2 · [ and ] change the size")
        case .fill:
            Text("Tolerance")
            Slider(value: $editor.fillTolerance, in: 0...1)
                .frame(width: 120)
            Text("\(Int((editor.fillTolerance * 100).rounded()))%")
                .monospacedDigit()
                .frame(width: 36, alignment: .trailing)
        case .eyedropper:
            hint("Click: Color 1 · Right-click: Color 2 · Option: all layers")
            Button("Add Color 1 to Custom Colors") { CustomColors.shared.add(editor.color1) }
                .help("Keep Color 1 in the next custom-color slot")
        case .gradient:
            Picker("Gradient", selection: $editor.gradientMode) {
                ForEach(GradientMode.allCases, id: \.self) { Text($0.name).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            hint("Right-drag reverses")
        case .measure:
            hint("Drag between two points · the status bar shows the distance")
        case .magnifier:
            hint("Click to zoom in · right-click or Option-click to zoom out")
        case .magicWand:
            Text("Tolerance")
            Slider(value: $editor.wandTolerance, in: 0...1)
                .frame(width: 100)
            Text("\(Int((editor.wandTolerance * 100).rounded()))%")
                .monospacedDigit()
                .frame(width: 36, alignment: .trailing)
            Toggle("Contiguous", isOn: $editor.wandContiguous)
                .help("Contiguous selects only the connected area; off selects every matching pixel")
            selectionOptions
        case .rectangleSelect, .ellipseSelect, .lassoSelect:
            selectionOptions
        case .shape:
            hint(editor.shapeKind.hint)
        case .text:
            TextOptions(style: $editor.textStyle)
        case .pencil:
            hint("1 px · Shift draws straight lines")
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text).foregroundStyle(Theme.secondaryInk).lineLimit(1)
    }

    @ViewBuilder
    private var selectionOptions: some View {
        Picker("Resize", selection: $editor.smoothResize) {
            Text("Smooth").tag(true)
            Text("Sharp pixels").tag(false)
        }
        .fixedSize()
        .help("How resized selections are scaled. Drag a handle to stretch; hold Shift to keep proportions.")
    }
}

/// The dialog for an effect, with a live preview on the canvas.
private struct EffectBar: View {
    @Bindable var editor: Editor
    let kind: EffectKind

    var body: some View {
        HStack(spacing: 14) {
            Text(kind.title).font(.headline)
            ForEach(Array(kind.parameters.enumerated()), id: \.offset) { index, parameter in
                HStack(spacing: 6) {
                    Text(parameter.label)
                    Slider(value: value(at: index), in: parameter.range)
                        .frame(minWidth: 90, maxWidth: 180)
                    Text("\(Int(editor.effectValues[safe: index] ?? 0))\(parameter.unit)")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            }
            Spacer(minLength: 0)
            Text(editor.hasSelection ? "Applies to the selection" : "Applies to the whole layer")
                .foregroundStyle(.secondary)
                .fixedSize()
            Button("Cancel", role: .cancel) { editor.cancelEffect() }
                .keyboardShortcut(.cancelAction)
            Button("Apply") { editor.applyEffect() }
                .keyboardShortcut(.defaultAction)
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .onChange(of: editor.effectValues) { editor.previewEffect() }
    }

    private func value(at index: Int) -> Binding<Double> {
        Binding(
            get: { editor.effectValues[safe: index] ?? 0 },
            set: { if editor.effectValues.indices.contains(index) { editor.effectValues[index] = $0.rounded() } }
        )
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private struct TextOptions: View {
    @Binding var style: TextStyle
    private static let families = NSFontManager.shared.availableFontFamilies

    var body: some View {
        Picker("Font", selection: $style.fontFamily) {
            ForEach(Self.families, id: \.self) { Text($0).tag($0) }
        }
        .labelsHidden()
        .frame(width: 160)
        HStack(spacing: 2) {
            TextField("Size", value: $style.fontSize, format: .number)
                .frame(width: 40)
                .multilineTextAlignment(.trailing)
            Stepper("Size", value: $style.fontSize, in: 6...500)
                .labelsHidden()
            Text("pt")
        }
        HStack(spacing: 2) {
            Toggle("Bold", systemImage: "bold", isOn: $style.bold)
            Toggle("Italic", systemImage: "italic", isOn: $style.italic)
            Toggle("Underline", systemImage: "underline", isOn: $style.underline)
            Toggle("Strikethrough", systemImage: "strikethrough", isOn: $style.strikethrough)
        }
        .toggleStyle(.button)
        .labelStyle(.iconOnly)
        Picker("Alignment", selection: $style.alignment) {
            Label("Left", systemImage: "text.alignleft").tag(ColorbeeCore.TextAlignment.left)
            Label("Center", systemImage: "text.aligncenter").tag(ColorbeeCore.TextAlignment.center)
            Label("Right", systemImage: "text.alignright").tag(ColorbeeCore.TextAlignment.right)
        }
        .pickerStyle(.segmented)
        .labelStyle(.iconOnly)
        .labelsHidden()
        .fixedSize()
        Picker("Background", selection: $style.opaqueBackground) {
            Text("Transparent").tag(false)
            Text("Opaque").tag(true)
        }
        .fixedSize()
        .help("Opaque puts a Color 2 rectangle behind the text")
    }
}

/// The Before/After controls (FR-11.3).
private struct CompareBar: View {
    @Bindable var editor: Editor

    var body: some View {
        HStack(spacing: 14) {
            Label("Compare", systemImage: "square.split.2x1")
                .font(.headline)
            Text("Edited against")
                .foregroundStyle(.secondary)
            Picker("Baseline", selection: baseline) {
                Text("As Opened").tag(Comparison.Baseline.asOpened)
                Text("Last Saved").tag(Comparison.Baseline.lastSaved)
                    .selectionDisabled(editor.lastSaved == nil)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help(editor.lastSaved == nil ? "Last Saved is available after you save with ⌘S" : "")
            Spacer()
            Picker("Layout", selection: layout) {
                Label("Side by side", systemImage: "rectangle.split.2x1").tag(Comparison.Layout.sideBySide)
                Label("Split", systemImage: "square.split.2x1").tag(Comparison.Layout.split)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Button("Done") { editor.comparison = nil }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var baseline: Binding<Comparison.Baseline> {
        Binding(get: { editor.comparison?.baseline ?? .asOpened }, set: { editor.comparison?.baseline = $0 })
    }

    private var layout: Binding<Comparison.Layout> {
        Binding(get: { editor.comparison?.layout ?? .split }, set: { editor.comparison?.layout = $0 })
    }
}

/// Rounds a slider's value to whole numbers. A stepped Slider would do this too, but draws a tick mark for every step.
private func wholeNumber(_ value: Binding<Double>) -> Binding<Double> {
    Binding(get: { value.wrappedValue }, set: { value.wrappedValue = $0.rounded() })
}
