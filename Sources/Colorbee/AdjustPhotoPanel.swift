import AppKit
import ColorbeeCore
import SwiftUI

/// The Adjust Photo panel (FR-9.5), docked in the sidebar while Adjustments ▸ Adjust Photo… is open.
struct AdjustPhotoPanel: View {
    @Bindable var editor: Editor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PhotoControls(edit: editor.photoEdit, autoMoved: editor.photoAutoMoved, editor: editor) { editor.setPhotoEdit($0) } onAuto: {
                editor.autoPhoto()
            }
            HStack {
                Button("As Adjustment Layer") { editor.photoAsAdjustmentLayer() }
                    .help("Add these settings as an adjustment layer instead, so they stay editable")
                Spacer()
                Button("Cancel") { editor.cancelEffect() }
                Button("Apply") { editor.applyEffect() }
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }
}

/// Filters, Auto and the fifteen sliders, for the Adjust Photo panel and for an Adjust Photo layer.
struct PhotoControls: View {
    let edit: PhotoEdit
    var autoMoved: Set<PhotoAdjustments.Slider> = []
    let editor: Editor
    let onChange: (PhotoEdit) -> Void
    var onFinish: () -> Void = {}
    let onAuto: () -> Void

    private typealias Slider = PhotoAdjustments.Slider
    private static let groups: [(String, [Slider])] = [
        ("Light", [.exposure, .brilliance, .highlights, .shadows, .contrast, .brightness, .blackPoint]),
        ("Color", [.saturation, .vibrance, .warmth, .tint]),
        ("Detail", [.sharpness, .definition, .noiseReduction, .vignette]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FilterStrip(edit: edit, editor: editor, onChange: { onChange($0); onFinish() })
            if edit.filter != nil {
                row("Intensity", value: edit.filterIntensity, range: 0...100, unit: "%") { value in
                    var changed = edit
                    changed.filterIntensity = value
                    onChange(changed)
                }
            }
            HStack {
                Button("Auto", systemImage: "wand.and.stars") { onAuto() }
                    .help("Balance exposure, brilliance, highlights, shadows, contrast, white balance and vibrance for this photo")
                Spacer()
                Button("Reset") {
                    onChange(PhotoEdit())
                    onFinish()
                }
                .disabled(edit.isNeutral)
                .help("Back to no changes")
            }
            .controlSize(.small)
            ForEach(Self.groups, id: \.0) { title, sliders in
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.secondaryInk)
                ForEach(sliders, id: \.self) { slider in
                    row(slider.title, value: edit.adjustments[slider], range: slider.range, unit: "", moved: autoMoved.contains(slider)) { value in
                        var changed = edit
                        changed.adjustments[slider] = value
                        onChange(changed)
                    }
                }
            }
        }
    }

    private func row(_ title: String, value: Double, range: ClosedRange<Double>, unit: String, moved: Bool = false, set: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(title).font(.system(size: 12))
                if moved {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.accentColor)
                        .help("Set by Auto")
                        .accessibilityLabel("Set by Auto")
                }
                Spacer()
                Text(range.lowerBound < 0 && value > 0 ? "+\(Int(value.rounded()))\(unit)" : "\(Int(value.rounded()))\(unit)")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(Theme.field, in: RoundedRectangle(cornerRadius: 5))
            }
            SwiftUI.Slider(value: Binding(get: { value }, set: { set($0.rounded()) }), in: range) { editing in
                if !editing { onFinish() }
            }
            .controlSize(.mini)
            .accessibilityLabel(title)
            // Control-click a slider to put it back to zero.
            .contextMenu { Button("Reset \(title)") { set(0); onFinish() } }
        }
    }
}

/// The filters as a wrapping set of chips, None first, with a menu to save, rename, delete, import and export.
private struct FilterStrip: View {
    let edit: PhotoEdit
    let editor: Editor
    let onChange: (PhotoEdit) -> Void
    private var store: FilterStore { FilterStore.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Filters").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.secondaryInk)
                Spacer()
                FilterMenu(edit: edit, editor: editor, onChange: onChange)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)], alignment: .leading, spacing: 4) {
                chip("None", selected: edit.filter == nil) { choose(nil) }
                ForEach(store.all, id: \.name) { filter in
                    chip(filter.name, selected: edit.filter?.name == filter.name) { choose(filter) }
                }
            }
        }
    }

    private func choose(_ filter: PhotoFilter?) {
        var changed = edit
        changed.filter = filter
        changed.filterIntensity = 100
        onChange(changed)
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 6)
                .frame(height: 22)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(selected ? Color.accentColor : Theme.field, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Save as Filter…, Save Filter from Layers, and managing your filters, like the palette menu.
private struct FilterMenu: View {
    let edit: PhotoEdit
    let editor: Editor
    let onChange: (PhotoEdit) -> Void
    private var store: FilterStore { FilterStore.shared }

    var body: some View {
        Menu {
            Button("Save as Filter…") {
                if let name = askForName("Save as Filter", message: "Saves the filter and color and tone sliders as they are now.", defaultName: "My Filter") {
                    // The new filter replaces what it was made from, so the image looks just the same.
                    if let saved = editor.saveFilter(from: edit, named: name) { onChange(saved) }
                }
            }
            .disabled(edit.isNeutral)
            Button("Save Filter from Layers…") {
                if let name = askForName("Save Filter from Layers", message: "Saves the image's color and tone adjustment layers, bottom to top, as one filter.", defaultName: "My Filter"),
                   !editor.saveFilterFromLayers(named: name) {
                    let alert = NSAlert()
                    alert.messageText = "No color or tone adjustment layers"
                    alert.informativeText = "Add Levels, Curves, Hue/Saturation, Adjust Photo or another color adjustment layer, then save the filter."
                    alert.runModal()
                }
            }
            Divider()
            if let filter = edit.filter, !filter.isBuiltIn, store.custom.contains(where: { $0.name == filter.name }) {
                // The chosen filter is a copy, so it follows the rename, and a deleted filter stops applying, the
                // way palettes behave (review D, finding 4).
                Button("Rename “\(filter.name)”…") {
                    if let name = askForName("Rename Filter", defaultName: filter.name, confirm: "Rename"), store.rename(filter.name, to: name) {
                        var changed = edit
                        changed.filter?.name = name
                        onChange(changed)
                    }
                }
                Button("Delete “\(filter.name)”") {
                    store.delete(filter.name)
                    var changed = edit
                    changed.filter = nil
                    onChange(changed)
                }
                Divider()
            }
            Button("Import Filter…") { importFilter() }
            Button("Export Filter…") { exportFilter() }
                .disabled(edit.filter == nil)
        } label: {
            Image(systemName: "ellipsis.circle").font(.system(size: 12))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Save, rename, delete, import or export filters")
        .accessibilityLabel("Filter options")
    }

    private func importFilter() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.colorbeeFilter]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try store.importFilter(from: url) } catch { NSAlert(error: error).runModal() }
    }

    private func exportFilter() {
        guard let filter = edit.filter else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.colorbeeFilter]
        panel.nameFieldStringValue = filter.name
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try store.export(filter, to: url) } catch { NSAlert(error: error).runModal() }
    }
}
