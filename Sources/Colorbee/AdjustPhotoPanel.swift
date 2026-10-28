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

/// Filters, Auto and the sliders, for the Adjust Photo panel and for an Adjust Photo layer.
struct PhotoControls: View {
    let edit: PhotoEdit
    var autoMoved: Set<PhotoAdjustments.Slider> = []
    let editor: Editor
    let onChange: (PhotoEdit) -> Void
    var onFinish: () -> Void = {}
    let onAuto: () -> Void

    private typealias Slider = PhotoAdjustments.Slider
    /// The titles of the folded sections, one per line, the same in every window (Leah, 2026-10-27).
    @AppStorage("adjustPhotoFoldedSections") private var folded = ""
    /// The sliders whose finer settings are open (Sharpness, Noise Reduction, Vignette, Grain), one per line; closed to
    /// start (Q13.3).
    @AppStorage("adjustPhotoOpenDetails") private var openDetails = ""
    /// Which of the Color Mixer's settings its eight sliders show.
    @State var mixerSetting = ColorMixer.Setting.hue
    /// Which Color Grading wheel shows.
    @State var gradingRegion = ColorGrading.Region.shadows
    /// Which picked color's sliders Point Color shows.
    @State var chosenSwatch = 0
    private static let groups: [(String, [Slider])] = [
        ("Light", [.exposure, .brilliance, .dehaze, .highlights, .shadows, .contrast, .brightness, .whites, .blackPoint]),
        ("Color", [.saturation, .vibrance, .warmth, .tint]),
        ("Detail", [.sharpness, .definition, .texture, .noiseReduction]),
        // Vignette moved here from Detail, beside Grain, as in Lightroom (Q14.4).
        ("Effects", [.vignette, .grain]),
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
                    .help("Balance exposure, brilliance, highlights, shadows, contrast, whites, white balance and vibrance for this photo")
                Spacer()
                // Icons, so Auto and Reset keep their names in the narrow sidebar.
                settingsButton("Copy Settings", "doc.on.doc", help: "Copy Settings: copy these settings, to paste onto another picture or Adjust Photo layer") {
                    editor.copyPhotoSettings()
                }
                settingsButton("Paste Settings", "doc.on.clipboard", help: "Paste Settings: use the copied settings here") {
                    editor.pastePhotoSettings()
                }
                .disabled(PhotoSettingsStore.shared.copied == nil)
                Button("Reset") {
                    onChange(PhotoEdit())
                    onFinish()
                }
                .disabled(edit.isNeutral)
                .help("Back to no changes")
            }
            .controlSize(.small)
            ForEach(Self.groups, id: \.0) { title, sliders in
                sectionHeading(title)
                ForEach(isFolded(title) ? [] : sliders, id: \.self) { slider in
                    let hasMore = [.sharpness, .noiseReduction, .vignette, .grain].contains(slider)
                    row(slider.title, value: edit.adjustments[slider], range: slider.range, unit: "", moved: autoMoved.contains(slider),
                        dropper: slider == .warmth, disclosure: hasMore ? detailDisclosure(slider) : nil) { value in
                        var changed = edit
                        changed.adjustments[slider] = value
                        onChange(changed)
                    }
                    if hasMore && isOpen(slider) { finerSettings(for: slider) }
                }
                if title == "Color" {
                    colorMixerSection
                    pointColorSection
                    colorGradingSection
                }
            }
        }
    }

    func isFolded(_ title: String) -> Bool {
        foldedTitles.contains(title)
    }

    // MARK: Sharpness's and Noise Reduction's finer settings (FR-9.7 item 5)

    private func isOpen(_ slider: Slider) -> Bool {
        openDetails.split(separator: "\n").contains { $0 == slider.rawValue }
    }

    private func detailDisclosure(_ slider: Slider) -> Binding<Bool> {
        Binding(get: { isOpen(slider) }, set: { open in
            var names = Set(openDetails.split(separator: "\n").map(String.init))
            if open { names.insert(slider.rawValue) } else { names.remove(slider.rawValue) }
            openDetails = names.sorted().joined(separator: "\n")
        })
    }

    private func effectsRow(_ title: String, _ key: WritableKeyPath<PhotoEffects, Double>, range: ClosedRange<Double>, help: String) -> some View {
        let effects = edit.effects ?? PhotoEffects()
        return row(title, value: effects[keyPath: key], range: range, unit: "", resetValue: PhotoEffects()[keyPath: key]) { value in
            var changed = edit
            var settings = changed.effects ?? PhotoEffects()
            settings[keyPath: key] = value
            changed.effects = settings
            onChange(changed)
        }
        .help(help)
        .padding(.leading, 14)
    }

    private func detailRow(_ title: String, _ key: WritableKeyPath<PhotoDetail, Double>, range: ClosedRange<Double>, unit: String = "",
                           step: Double = 1, help: String, onEditing: ((Bool) -> Void)? = nil) -> some View {
        let detail = edit.detail ?? PhotoDetail()
        return row(title, value: detail[keyPath: key], range: range, unit: unit, step: step, resetValue: PhotoDetail()[keyPath: key],
                   onEditing: onEditing) { value in
            var changed = edit
            var settings = changed.detail ?? PhotoDetail()
            settings[keyPath: key] = value
            changed.detail = settings
            onChange(changed)
        }
        .help(help)
        .padding(.leading, 14)
    }

    @ViewBuilder private func finerSettings(for slider: Slider) -> some View {
        if slider == .vignette {
            effectsRow("Midpoint", \.midpoint, range: PhotoEffects.range, help: "Higher leaves more of the middle untouched")
            effectsRow("Roundness", \.roundness, range: PhotoEffects.roundnessRange,
                       help: "Left toward a rectangle, right toward a circle; 0 follows the picture's shape")
            effectsRow("Feather", \.feather, range: PhotoEffects.range, help: "How gradually it fades in: 0 is a hard edge")
        } else if slider == .grain {
            effectsRow("Size", \.grainSize, range: PhotoEffects.range, help: "How big each grain is")
            effectsRow("Roughness", \.grainRoughness, range: PhotoEffects.range, help: "How uneven the grain is")
        } else if slider == .sharpness {
            detailRow("Radius", \.radius, range: PhotoDetail.radiusRange, unit: " px", step: 0.1,
                      help: "The size of the detail Sharpness brings out")
            detailRow("Detail", \.sharpnessDetail, range: PhotoDetail.range,
                      help: "Lower holds back halos along strong edges; higher brings out the finest detail")
            detailRow("Masking", \.masking, range: PhotoDetail.range,
                      help: "Sharpen only edges, leaving smooth areas such as sky alone. Hold Option while dragging to see where it sharpens (white).") { editing in
                // Option-drag shows the edge mask on the picture while the slider is held (Q13.2).
                let showsMask = editing && NSEvent.modifierFlags.contains(.option)
                guard showsMask != edit.showsSharpeningMask else { return }
                var changed = edit
                changed.showsSharpeningMask = showsMask
                onChange(changed)
            }
        } else {
            detailRow("Detail", \.luminanceDetail, range: PhotoDetail.range,
                      help: "Higher keeps more fine detail; lower smooths more")
            detailRow("Color", \.color, range: PhotoDetail.range,
                      help: "Smooth colored speckles, keeping the brightness")
            detailRow("Color Detail", \.colorDetail, range: PhotoDetail.range,
                      help: "Higher keeps more small color detail")
        }
    }

    /// A section's name, which folds it away or opens it again.
    func sectionHeading(_ title: String) -> some View {
        let folded = isFolded(title)
        return Button {
            var titles = foldedTitles
            if folded { titles.remove(title) } else { titles.insert(title) }
            self.folded = titles.sorted().joined(separator: "\n")
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(folded ? 0 : 90))
                Text(title).font(.system(size: 11, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(Theme.secondaryInk)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(folded ? "Show the \(title) settings" : "Hide the \(title) settings")
        .accessibilityLabel(title)
        .accessibilityValue(folded ? "Folded" : "Open")
    }

    private func settingsButton(_ title: String, _ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.secondaryInk)
        .help(help)
        .accessibilityLabel(title)
    }

    /// Click something in the picture that should be gray, and Warmth and Tint are set (FR-9.7).
    private var whiteBalanceDropper: some View {
        let isOn = editor.isPicking(.whiteBalance)
        return Button { editor.togglePicturePick(.whiteBalance) } label: {
            Image(systemName: "eyedropper")
                .font(.system(size: 11))
                .frame(width: 18, height: 18)
                .background(isOn ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(isOn ? Color.accentColor : Theme.secondaryInk)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("White balance: click something in the picture that should be gray. Esc cancels.")
        .accessibilityLabel("White balance eyedropper")
        .accessibilityValue(isOn ? "On" : "Off")
    }

    private var foldedTitles: Set<String> {
        Set(folded.split(separator: "\n").map(String.init))
    }

    /// A slider with its name and value above it. `step` below 1 shows one decimal; `disclosure` adds an arrow that
    /// shows finer settings; `onEditing` hears when the slider is pressed and let go.
    func row(_ title: String, value: Double, range: ClosedRange<Double>, unit: String, step: Double = 1, moved: Bool = false,
             dropper: Bool = false, swatch: Color? = nil, resetValue: Double = 0, disclosure: Binding<Bool>? = nil,
             onEditing: ((Bool) -> Void)? = nil, end: (() -> Void)? = nil, set: @escaping (Double) -> Void) -> some View {
        let snapped = { (value: Double) in step == 1 ? value.rounded() : (value / step).rounded() * step }
        let shown = step == 1 ? "\(Int(value.rounded()))" : value.formatted(.number.precision(.fractionLength(1)))
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                // Before the line, not on it: the grab area would take its clicks (Leah, 2026-10-28).
                if let disclosure {
                    Button { disclosure.wrappedValue.toggle() } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .rotationEffect(.degrees(disclosure.wrappedValue ? 90 : 0))
                            .frame(width: 12, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.secondaryInk)
                    .help(disclosure.wrappedValue ? "Hide the finer \(title) settings" : "Show the finer \(title) settings")
                    .accessibilityLabel("\(title) settings")
                    .accessibilityValue(disclosure.wrappedValue ? "Open" : "Closed")
                    .padding(.trailing, -2)
                }
                HStack(spacing: 4) {
                    if let swatch {
                        Circle().fill(swatch).frame(width: 8, height: 8).accessibilityHidden(true)
                    }
                    Text(title).font(.system(size: 12))
                    if moved {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.accentColor)
                            .help("Set by Auto")
                            .accessibilityLabel("Set by Auto")
                    }
                    Spacer()
                    Text(range.lowerBound < 0 && value > 0 ? "+\(shown)\(unit)" : "\(shown)\(unit)")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .padding(.horizontal, 6)
                        .frame(height: 18)
                        .background(Theme.field, in: RoundedRectangle(cornerRadius: 5))
                }
                // The wand's own tooltip is under the grab area, so the line carries it (review T, finding 6).
                .slides(Binding(get: { value }, set: { set(snapped($0)) }), in: range, help: moved ? "Set by Auto" : nil, onEnd: end ?? onFinish)
                // Beside the line, not on it: the grab area would take its clicks.
                if dropper { whiteBalanceDropper }
            }
            SwiftUI.Slider(value: Binding(get: { value }, set: { set(snapped($0)) }), in: range) { editing in
                onEditing?(editing)
                if !editing { (end ?? onFinish)() }
            }
            // The size the Adjustments panel uses, easier to grab than mini (Leah, 2026-10-27).
            .controlSize(.small)
            .accessibilityLabel(title)
            // Control-click a slider to put it back to zero.
            .contextMenu { Button("Reset \(title)") { set(resetValue); onFinish() } }
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
                if let name = askForName("Save as Filter", message: "Saves the filter, the light and color sliders, and the vignette as they are now. Sharpness, Definition, Texture and Noise Reduction stay on the panel.", defaultName: "My Filter") {
                    // The new filter replaces what it was made from, so the image looks just the same.
                    if let saved = editor.saveFilter(from: edit, named: name) { onChange(saved) }
                }
            }
            .disabled(edit.isNeutral)
            Button("Save Filter from Layers…") {
                if let name = askForName("Save Filter from Layers", message: "Saves the image's visible color and tone adjustment layers, bottom to top, as one filter. Adjust Photo layers keep everything but Sharpness, Definition, Texture and Noise Reduction.", defaultName: "My Filter"),
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
        panel.allowedContentTypes = [.colorbeeFilter, .cubeLook]
        panel.message = "Choose a Colorbee filter, or a .cube color look."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // The imported filter is chosen, so you see it straight away.
        do {
            var changed = edit
            changed.filter = store.filter(named: try store.importFilter(from: url))
            changed.filterIntensity = 100
            onChange(changed)
        } catch {
            NSAlert(error: error).runModal()
        }
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
