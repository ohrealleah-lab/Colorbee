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
                .overlay { RedactionBadges(editor: editor) }
                .overlay(alignment: .top) {
                    if editor.isFindingSubject || editor.isReadingText {
                        Label(editor.isReadingText ? "Reading text…" : "Finding the subject…",
                              systemImage: editor.isReadingText ? "text.viewfinder" : "person.crop.rectangle")
                            .font(.system(size: 12))
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .glassEffect(.regular, in: Capsule())
                            .padding(.top, 12)
                    }
                }
                // "Copied 42 words": fades by itself.
                .overlay(alignment: .bottom) {
                    if let notice = editor.notice {
                        Text(notice.text)
                            .font(.system(size: 13))
                            .padding(.horizontal, 14)
                            .frame(height: 30)
                            .glassEffect(.regular, in: Capsule())
                            .padding(.bottom, 16)
                            .transition(.opacity)
                            .id(notice.id)
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: editor.notice)
                .alert("Couldn't use the subject", isPresented: Binding(get: { editor.subjectMessage != nil }, set: { if !$0 { editor.subjectMessage = nil } })) {
                    Button("OK") { editor.subjectMessage = nil }
                } message: {
                    Text(editor.subjectMessage ?? "")
                }
                .overlay {
                    if editor.showsRulers { Rulers(editor: editor) }
                }
                // The pages, down the left (FR-11.6), once there's more than one.
                .overlay(alignment: .leading) {
                    if editor.pageCount > 1, editor.showsPageSidebar {
                        PageSidebar(editor: editor)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
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
        // File ▸ Import from iPhone or iPad while a SwiftUI view has focus (FR-11.7).
        .importsItemProviders(ContinuityImport.contentTypes) { ContinuityImport.receive($0, into: editor) }
        .sheet(isPresented: $editor.isCanvasPropertiesOpen) {
            CanvasPropertiesSheet(editor: editor)
        }
        .sheet(isPresented: $editor.isResizeSkewOpen) {
            ResizeSkewSheet(editor: editor, base: editor.resizeSkewBaseSize, appliesToSelection: editor.hasSelection)
        }
        .alert("Nothing was redacted", isPresented: Binding(get: { editor.redactionMessage != nil }, set: { if !$0 { editor.redactionMessage = nil } })) {
            Button("OK") { editor.redactionMessage = nil }
        } message: {
            Text(editor.redactionMessage ?? "")
        }
        // After a redaction, the image as it was pasted is still in Clipboard History (Leah; review H, finding 2).
        .alert("Remove the unredacted image from Clipboard History and the clipboard?",
               isPresented: Binding(get: { editor.clipboardCleanup != nil }, set: { if !$0 { editor.clipboardCleanup = nil } })) {
            Button("Remove") { editor.removeClipboardSources() }
                .keyboardShortcut(.defaultAction)
            Button("Keep", role: .cancel) { editor.clipboardCleanup = nil }
        } message: {
            Text("Clipboard History still has the image this was pasted from, before the redaction. If it's still on the clipboard, that's cleared too; anything you've copied since is left alone.")
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
            Toggle("Color Eraser", isOn: $editor.colorEraserMode)
                .help("On: dragging replaces only Color 1 with Color 2. Right-drag always does.")
            Text("Tolerance")
            Slider(value: $editor.colorEraserTolerance, in: 0...1)
                .frame(width: 100)
                .accessibilityLabel("Color Eraser tolerance")
            Text("\(Int((editor.colorEraserTolerance * 100).rounded()))%")
                .monospacedDigit()
                .frame(width: 36, alignment: .trailing)
                .scrubs($editor.colorEraserTolerance, in: 0...1, step: 0.01)
            hint(editor.colorEraserMode ? "Drag replaces Color 1 with Color 2 · [ and ] change the size"
                 : "Right-drag replaces Color 1 with Color 2 · [ and ] change the size")
        case .fill:
            Text("Tolerance")
            Slider(value: $editor.fillTolerance, in: 0...1)
                .frame(width: 120)
                .accessibilityLabel("Fill tolerance")
            Text("\(Int((editor.fillTolerance * 100).rounded()))%")
                .monospacedDigit()
                .frame(width: 36, alignment: .trailing)
                .scrubs($editor.fillTolerance, in: 0...1, step: 0.01)
            Toggle("Sample All Layers", isOn: $editor.fillSamplesAllLayers)
                .help("Find the area to fill in all visible layers together, and fill it on this layer")
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
                .scrubs($editor.wandTolerance, in: 0...1, step: 0.01)
            Toggle("Contiguous", isOn: $editor.wandContiguous)
                .help("Contiguous selects only the connected area; off selects every matching pixel")
            Toggle("Sample All Layers", isOn: $editor.wandSamplesAllLayers)
                .help("Select by the colors of all visible layers together, not just this layer")
            selectionOptions
        case .rectangleSelect, .ellipseSelect, .lassoSelect:
            selectionOptions
        case .shape:
            hint(editor.shapeKind.hint)
        case .text:
            TextStyleMenu(editor: editor, store: TextStyleStore.shared)
            TextOptions(style: $editor.textStyle)
        case .pencil:
            hint("1 px · Shift draws straight lines")
        case .stepBadge:
            Picker("Badges", selection: $editor.badgeStyle) {
                Text("1, 2, 3").tag(BadgeStyle.numbers)
                Text("A, B, C").tag(BadgeStyle.letters)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Number the badges, or letter them")
            Text("Next")
            TextField("Next", text: Binding(
                get: { StepBadge.label(for: editor.nextBadge, style: editor.badgeStyle) },
                set: { if let value = StepBadge.value(of: $0, style: editor.badgeStyle) { editor.nextBadge = value } }))
                .textFieldStyle(.roundedBorder)
                .frame(width: 52)
                .labelsHidden()
                .help("What the next badge shows")
            hint("Drag to point an arrow · Right-click swaps the colors")
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
    @State private var curvesChannel = Curves.Channel.rgb

    var body: some View {
        HStack(alignment: kind == .curves ? .top : .center, spacing: 14) {
            Text(kind.title).font(.headline)
            if kind == .levels {
                HistogramView(histogram: editor.effectHistogram, black: editor.effectValues[safe: 0] ?? 0, white: editor.effectValues[safe: 2] ?? 255)
                    .frame(width: 160, height: 34)
                    .help("How many pixels have each brightness, darkest on the left")
            }
            if kind == .curves {
                CurvesEditor(curves: editor.effectCurves, channel: $curvesChannel) { curves in
                    editor.effectCurves = curves
                    editor.previewEffect()
                }
                .frame(width: 180)
                Button("Reset") {
                    editor.effectCurves = .identity
                    editor.previewEffect()
                }
                .help("Back to a straight line")
            }
            ForEach(Array(kind.parameters.enumerated()), id: \.offset) { index, parameter in
                HStack(spacing: 6) {
                    Text(parameter.label)
                    if let options = parameter.options {
                        Picker(parameter.label, selection: value(at: index, step: 1)) {
                            ForEach(Array(options.enumerated()), id: \.offset) { option, title in
                                Text(title).tag(Double(option))
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    } else {
                        Slider(value: value(at: index, step: parameter.step), in: parameter.range)
                            .accessibilityLabel(parameter.label)
                            .accessibilityValue(EffectBar.formatted(editor.effectValues[safe: index] ?? 0, parameter))
                            .frame(minWidth: 90, maxWidth: 180)
                        Text(EffectBar.formatted(editor.effectValues[safe: index] ?? 0, parameter))
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
            if kind == .adjustPhoto {
                Text("Use the sliders and filters in the panel at the right.")
                    .foregroundStyle(.secondary)
            }
            if kind == .crop {
                CropOptions(editor: editor)
            }
            if kind == .pickSubject {
                Text("There's more than one subject. Click the one you want, or press Return for all of them.")
                    .foregroundStyle(.secondary)
            }
            if kind == .perspective {
                Text("Drag the four corners onto the corners of what should be a rectangle.")
                    .foregroundStyle(.secondary)
            }
            if kind == .straighten {
                Text("Or drag along something that should be level.")
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            if kind == .levels {
                Button("Auto") { editor.autoLevels() }
                    .help("Set the black and white points to the darkest and lightest pixels")
            }
            Spacer(minLength: 0)
            if kind != .pickSubject {
                Text(kind.appliesToWholeImage ? "Applies to every layer"
                     : editor.effectCoversAllLayers ? (editor.hasSelection ? "Redacts every layer in the selection" : "Redacts every layer")
                     : editor.hasSelection ? "Applies to the selection" : "Applies to the whole layer")
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
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

    static func formatted(_ value: Double, _ parameter: EffectKind.Parameter) -> String {
        let text = parameter.step < 0.1 ? String(format: "%.2f", value) : parameter.step < 1 ? String(format: "%.1f", value) : "\(Int(value.rounded()))"
        let signed = parameter.range.lowerBound < 0 && value > 0 && parameter.step >= 1 ? "+" + text : text
        return signed + parameter.unit
    }

    private func value(at index: Int, step: Double) -> Binding<Double> {
        Binding(
            get: { editor.effectValues[safe: index] ?? 0 },
            set: { if editor.effectValues.indices.contains(index) { editor.effectValues[index] = ($0 / step).rounded() * step } }
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
    @FocusState private var typingSize: Bool
    private static let families = NSFontManager.shared.availableFontFamilies

    var body: some View {
        Picker("Font", selection: $style.fontFamily) {
            ForEach(Self.families, id: \.self) { Text($0).tag($0) }
        }
        .labelsHidden()
        .frame(width: 160)
        HStack(spacing: 2) {
            TextField("Size", value: $style.fontSize, format: .number)
                .focused($typingSize)
                .frame(width: 40)
                .multilineTextAlignment(.trailing)
                .scrubs($style.fontSize, in: 6...500, focus: $typingSize)
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
                    .selectionDisabled(!editor.hasLastSaved)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help(!editor.hasLastSaved ? "Last Saved is available after you save with ⌘S" : "")
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
