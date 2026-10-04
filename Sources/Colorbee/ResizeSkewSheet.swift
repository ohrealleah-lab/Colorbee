import ColorbeeCore
import SwiftUI

/// The Resize and Skew dialog (⌘E, FR-7.2).
struct ResizeSkewSheet: View {
    let editor: Editor
    let base: IntSize
    let appliesToSelection: Bool

    @State private var byPercentage = true
    @State private var horizontal = 100.0
    @State private var vertical = 100.0
    @State private var keepsAspectRatio = true
    @State private var smooth: Bool
    @State private var horizontalSkew = 0.0
    @State private var verticalSkew = 0.0

    init(editor: Editor, base: IntSize, appliesToSelection: Bool) {
        self.editor = editor
        self.base = base
        self.appliesToSelection = appliesToSelection
        _smooth = State(initialValue: editor.smoothResize)
    }

    private var unit: String { byPercentage ? "%" : "px" }

    private var size: IntSize {
        byPercentage
            ? IntSize(width: max(1, Int((Double(base.width) * horizontal / 100).rounded())),
                      height: max(1, Int((Double(base.height) * vertical / 100).rounded())))
            : IntSize(width: max(1, Int(horizontal.rounded())), height: max(1, Int(vertical.rounded())))
    }

    private var settings: ResizeSkew {
        ResizeSkew(size: size, horizontalSkew: horizontalSkew, verticalSkew: verticalSkew, resampling: smooth ? .smooth : .nearestNeighbor)
    }

    private var problem: String? {
        if byPercentage, !(1...500).contains(horizontal) || !(1...500).contains(vertical) {
            return "Percentages run from 1% to 500%."
        }
        if !byPercentage, horizontal < 1 || vertical < 1 { return "Sizes must be at least 1 px." }
        // Checked before anything converts the typed sizes to whole numbers, which a huge one would crash.
        if !byPercentage, horizontal > Double(ResizeSkew.maxSide) || vertical > Double(ResizeSkew.maxSide) {
            return "That would be too large (over \(ResizeSkew.maxSide.formatted()) px on a side)."
        }
        if !(-89...89).contains(horizontalSkew) || !(-89...89).contains(verticalSkew) { return "Skew runs from −89° to 89°." }
        if !settings.fits { return "That would be too large (over \(ResizeSkew.maxSide.formatted()) px on a side)." }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Resize and Skew").font(.headline)
            Text(appliesToSelection ? "Applies to the selection (\(base.width) × \(base.height) px)." : "Applies to the whole image (\(base.width) × \(base.height) px).")
                .foregroundStyle(.secondary)

            GroupBox("Resize") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("By", selection: $byPercentage) {
                        Text("Percentage").tag(true)
                        Text("Pixels").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .onChange(of: byPercentage) { _, percent in
                        // Keep the same size when switching units.
                        if percent {
                            horizontal = (horizontal / Double(base.width) * 100).rounded()
                            vertical = (vertical / Double(base.height) * 100).rounded()
                        } else {
                            horizontal = (Double(base.width) * horizontal / 100).rounded()
                            vertical = (Double(base.height) * vertical / 100).rounded()
                        }
                    }
                    Grid(alignment: .leading, verticalSpacing: 8) {
                        GridRow {
                            Text("Horizontal")
                            TextField("Horizontal", value: Binding(get: { horizontal }, set: { setHorizontal($0) }), format: .number)
                                .frame(width: 80)
                                .labelsHidden()
                            Text(unit)
                        }
                        GridRow {
                            Text("Vertical")
                            TextField("Vertical", value: Binding(get: { vertical }, set: { setVertical($0) }), format: .number)
                                .frame(width: 80)
                                .labelsHidden()
                            Text(unit)
                        }
                    }
                    Toggle("Maintain aspect ratio", isOn: $keepsAspectRatio)
                    Picker("Resampling", selection: $smooth) {
                        Text("Smooth (photos)").tag(true)
                        Text("Sharp (pixel art)").tag(false)
                    }
                    .fixedSize()
                }
                .padding(6)
            }

            GroupBox("Skew") {
                Grid(alignment: .leading, verticalSpacing: 8) {
                    GridRow {
                        Text("Horizontal")
                        TextField("Horizontal skew", value: $horizontalSkew, format: .number)
                            .frame(width: 80)
                            .labelsHidden()
                        Text("°")
                    }
                    GridRow {
                        Text("Vertical")
                        TextField("Vertical skew", value: $verticalSkew, format: .number)
                            .frame(width: 80)
                            .labelsHidden()
                        Text("°")
                    }
                }
                .padding(6)
            }

            Group {
                if let problem {
                    Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                } else {
                    let result = settings.resultSize
                    Text("Result: \(result.width) × \(result.height) px").foregroundStyle(.secondary)
                }
            }
            .monospacedDigit()

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { editor.isResizeSkewOpen = false }
                    .keyboardShortcut(.cancelAction)
                Button("OK") { editor.apply(settings) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(problem != nil)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func setHorizontal(_ value: Double) {
        horizontal = value
        guard keepsAspectRatio else { return }
        vertical = byPercentage ? value : (value * Double(base.height) / Double(base.width)).rounded()
    }

    private func setVertical(_ value: Double) {
        vertical = value
        guard keepsAspectRatio else { return }
        horizontal = byPercentage ? value : (value * Double(base.width) / Double(base.height)).rounded()
    }
}
