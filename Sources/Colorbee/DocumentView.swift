import AppKit
import ColorbeeCore
import SwiftUI

struct DocumentView: View {
    @Bindable var editor: Editor
    let canvasView: CanvasView

    var body: some View {
        VStack(spacing: 0) {
            ToolStrip(editor: editor)
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
                .sheet(isPresented: autoRedactBinding) {
                    AutoRedactSheet(editor: editor)
                }
            Divider()
            StatusBar(editor: editor)
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

private struct ToolStrip: View {
    @Bindable var editor: Editor

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 2) {
                ForEach(Tool.allCases, id: \.self) { tool in
                    Button {
                        editor.selectTool(tool)
                    } label: {
                        Image(systemName: tool.symbol)
                            .frame(width: 26, height: 22)
                            .background(editor.tool == tool ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 5))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(editor.tool == tool ? Color.accentColor : .primary)
                    .help("\(tool.title): \(tool.summary)")
                    .accessibilityLabel(tool.title)
                }
            }
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
        case .gradient:
            Picker("Gradient", selection: $editor.gradientMode) {
                ForEach(GradientMode.allCases, id: \.self) { Text($0.name).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Text("Drag: Color 1 → Color 2 · Right-drag reverses")
                .foregroundStyle(.secondary)
        case .measure:
            Text("Drag between two points · the status bar shows the distance")
                .foregroundStyle(.secondary)
        case .magicWand:
            Text("Tolerance")
            Slider(value: $editor.wandTolerance, in: 0...1)
                .frame(width: 120)
            Text("\(Int((editor.wandTolerance * 100).rounded()))%")
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
            Toggle("Contiguous", isOn: $editor.wandContiguous)
                .help("Contiguous selects only the connected area; off selects every matching pixel")
            selectionOptions
        case .rectangleSelect, .ellipseSelect, .lassoSelect:
            selectionOptions
        case .shape:
            Picker("Shape", selection: $editor.shapeKind) {
                ForEach(ShapeKind.allCases, id: \.self) { kind in
                    Label(kind.name, systemImage: kind.symbol).tag(kind)
                }
            }
            .labelsHidden()
            .fixedSize()
            .help(editor.shapeKind == .polygon ? "Click each corner; click the first corner or double-click to close"
                  : editor.shapeKind == .curve ? "Drag a line, then drag twice to bend it" : "Shift keeps proportions")
            HStack {
                Text("Width").fixedSize()
                Slider(value: $editor.shapeLineWidth, in: 1...50, step: 1)
                    .frame(width: 100)
                Text("\(Int(editor.shapeLineWidth)) px")
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
            }
            if !editor.shapeKind.isOpen {
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
        case .text:
            TextOptions(style: $editor.textStyle)
        case .pencil:
            Text("1 px · Shift draws straight lines")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var selectionOptions: some View {
        Toggle("Transparent Selection", systemImage: "square.on.square.dashed", isOn: $editor.transparentSelection)
            .toggleStyle(.button)
            .help("Transparent Selection: pixels matching Color 2 aren't placed")
        Picker("Resize", selection: $editor.smoothResize) {
            Text("Smooth").tag(true)
            Text("Sharp pixels").tag(false)
        }
        .fixedSize()
        .help("How resized selections are scaled. Drag a handle to stretch; hold Shift to keep proportions.")
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
    var summary: String {
        switch self {
        case .pencil: "1-pixel hard line. Shift draws straight lines."
        case .brush: "Soft round brush or translucent marker."
        case .eraser: "Erase to Color 2. Right-drag replaces only Color 1."
        case .fill: "Fill an area of similar color."
        case .eyedropper: "Pick a color from the image."
        case .gradient: "Drag to blend Color 1 into Color 2."
        case .measure: "Drag to measure distance and angle."
        case .shape: "Lines, arrows, boxes, stars, callouts and more."
        case .text: "Click to type, or drag out a box."
        case .rectangleSelect: "Drag to select a rectangle. Shift adds, Option subtracts."
        case .ellipseSelect: "Drag to select an oval. Shift adds, Option subtracts."
        case .lassoSelect: "Draw around an area to select it."
        case .magicWand: "Click to select an area of similar color."
        }
    }

    var title: String {
        switch self {
        case .pencil: "Pencil (P)"
        case .brush: "Brush (B)"
        case .eraser: "Eraser (E)"
        case .fill: "Fill (G)"
        case .eyedropper: "Eyedropper (I)"
        case .measure: "Measure (R)"
        case .gradient: "Gradient"
        case .shape: "Shapes (U)"
        case .text: "Text (T)"
        case .rectangleSelect: "Rectangle Select (M)"
        case .ellipseSelect: "Ellipse Select"
        case .lassoSelect: "Free-Form Select (L)"
        case .magicWand: "Magic Wand (W)"
        }
    }

    var symbol: String {
        switch self {
        case .pencil: "pencil"
        case .brush: "paintbrush.pointed"
        case .eraser: "eraser"
        case .fill: "drop.fill"
        case .eyedropper: "eyedropper"
        case .measure: "ruler"
        case .gradient: "square.tophalf.filled"
        case .shape: "square.on.circle"
        case .text: "textformat"
        case .rectangleSelect: "rectangle.dashed"
        case .ellipseSelect: "circle.dashed"
        case .lassoSelect: "lasso"
        case .magicWand: "wand.and.stars"
        }
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
                    Slider(value: value(at: index), in: parameter.range, step: 1)
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
            set: { if editor.effectValues.indices.contains(index) { editor.effectValues[index] = $0 } }
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
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
            if let measurement = editor.measurement {
                Label(String(format: "%.1f px · ΔX %d · ΔY %d · %.1f°", measurement.distance, measurement.dx, measurement.dy, measurement.angle),
                      systemImage: "ruler")
            }
            Spacer()
            Picker(selection: $editor.symmetry) {
                ForEach(SymmetryMode.allCases, id: \.self) { Text($0.title).tag($0) }
            } label: {
                Label("Symmetry", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
            }
            .fixedSize()
            .controlSize(.small)
            .help("Mirror Pencil, Brush and Eraser strokes")
            Toggle("Pixel Grid", systemImage: "grid", isOn: $editor.showsPixelGrid)
                .toggleStyle(.button)
                .controlSize(.small)
                .disabled(editor.viewport.zoom < Renderer.pixelGridMinimumZoom)
                .help("Pixel grid (⌘') — shown at 400% and above")
            ZoomControl(editor: editor)
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
        case .curve: "scribble"
        case .rectangle: "rectangle"
        case .roundedRectangle: "app"
        case .ellipse: "circle"
        case .triangle: "triangle"
        case .rightTriangle: "righttriangle"
        case .diamond: "diamond"
        case .pentagon: "pentagon"
        case .hexagon: "hexagon"
        case .rightArrow: "arrowshape.right"
        case .leftArrow: "arrowshape.left"
        case .upArrow: "arrowshape.up"
        case .downArrow: "arrowshape.down"
        case .star4: "sparkle"
        case .star5: "star"
        case .star6: "staroflife"
        case .roundedRectangleCallout: "bubble.left"
        case .ovalCallout: "bubble"
        case .cloudCallout: "cloud"
        case .heart: "heart"
        case .lightning: "bolt"
        case .polygon: "pentagon.righthalf.filled"
        }
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

/// − and + step through the zoom levels; the percentage opens a list of common ones.
private struct ZoomControl: View {
    let editor: Editor

    private static let presets = [0.25, 0.5, 0.75, 1.0]

    var body: some View {
        HStack(spacing: 2) {
            Button("Zoom Out", systemImage: "minus") { editor.zoomOut() }
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
            .frame(width: 70)
            .help("Choose a zoom level")
            Button("Zoom In", systemImage: "plus") { editor.zoomIn() }
                .labelStyle(.iconOnly)
                .disabled(editor.viewport.zoom >= Viewport.maxZoom)
                .help("Zoom in (⌘=)")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
    }
}
