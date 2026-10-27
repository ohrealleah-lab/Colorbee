import AppKit
import ColorbeeCore
import SwiftUI

/// The right sidebar (FR-1.3): an inset glass pane over the canvas surround. The switcher at the top
/// shows or hides each panel.
struct Sidebar: View {
    @Bindable var editor: Editor

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                switcherButton("square.3.layers.3d", "Layers", ShortcutStore.shared.hint("Layers panel", command: "toggleLayers:"), panel: \.showsLayersPanel)
                switcherButton("slider.horizontal.3", "Adjustments", ShortcutStore.shared.hint("Adjustments panel", command: "toggleAdjustmentsPanel:"), panel: \.showsAdjustmentsPanel)
                switcherButton("clock.arrow.circlepath", "History", ShortcutStore.shared.hint("History panel", command: "toggleHistoryPanel:"), panel: \.showsHistoryPanel)
                switcherButton("list.clipboard", "Clipboard History", ShortcutStore.shared.hint("Clipboard History panel", command: "toggleClipboardPanel:"), panel: \.showsClipboardPanel)
                switcherButton("info.circle", "Info", ShortcutStore.shared.hint("Info panel", command: "toggleInfoPanel:"), panel: \.showsInfoPanel)
            }
            .padding(2)
            .background(Theme.field, in: Capsule())
            .padding(.top, 10)
            .padding(.bottom, 6)

            // While Adjust Photo is open it has the sidebar to itself; the other panels come back after.
            if editor.activeEffect == .adjustPhoto {
                SectionHeader(title: "Adjust Photo", detail: editor.hasSelection ? "Selection" : "Whole layer")
                ScrollView { AdjustPhotoPanel(editor: editor) }
            } else {
                panels
            }
        }
        .frame(width: 272)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
        .padding(8)
    }

    @ViewBuilder private var panels: some View {
        if editor.showsLayersPanel {
            LayersPanel(editor: editor)
        }
        if editor.showsAdjustmentsPanel {
            if editor.showsLayersPanel { Divider() }
            SectionHeader(title: "Adjustments", detail: editor.activeAdjustment.flatMap(AdjustmentChoice.init)?.title ?? "")
            AdjustmentsPanel(editor: editor)
        }
        if editor.showsHistoryPanel {
            Divider()
            SectionHeader(title: "History", detail: "\(editor.historySteps.count) steps")
            HistoryPanel(editor: editor)
        }
        if editor.showsClipboardPanel {
            Divider()
            SectionHeader(title: "Clipboard History", detail: "\(ClipboardHistory.shared.items.count)")
            ClipboardPanel(editor: editor)
        }
        if editor.showsInfoPanel {
            Divider()
            SectionHeader(title: "Info")
            InfoPanel(editor: editor)
        }
        if !editor.showsLayersPanel && !editor.showsHistoryPanel && !editor.showsClipboardPanel && !editor.showsInfoPanel {
            Spacer(minLength: 0)
        }
    }

    /// Turning off the last panel closes the sidebar, as ⌘L does (Leah, 2026-10-10).
    private func switcherButton(_ symbol: String, _ name: String, _ help: String, panel: ReferenceWritableKeyPath<Editor, Bool>) -> some View {
        let isOn = Binding(get: { editor[keyPath: panel] }, set: { _ in })
        return Button { editor.togglePanel(panel) } label: {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .frame(width: 40, height: 24)
                .foregroundStyle(isOn.wrappedValue ? Color.primary : Theme.secondaryInk)
                .background(isOn.wrappedValue ? Color.primary.opacity(0.14) : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel("\(name) panel")
        .accessibilityAddTraits(isOn.wrappedValue ? .isSelected : [])
    }
}

/// A panel's title row in the sidebar.
struct SectionHeader: View {
    let title: String
    var detail = ""

    var body: some View {
        HStack {
            Text(title).font(.system(size: 12, weight: .semibold))
            Spacer()
            Text(detail).font(.system(size: 11)).foregroundStyle(Theme.secondaryInk)
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
    }
}

/// The Layers panel (FR-8.2): the active layer's blend mode and opacity, the stack with the top
/// layer first, and buttons to add, duplicate, delete and merge.
private struct LayersPanel: View {
    @Bindable var editor: Editor
    /// The layer being dragged to a new place, and how far it has moved.
    @State private var dragged: (id: LayerID, translation: CGFloat)?
    /// A row's height plus the gap between rows.
    private static let rowPitch: CGFloat = 42
    @State private var renaming: Layer?
    @State private var newName = ""

    var body: some View {
        let layers = editor.layers
        let active = editor.activeLayerIndex
        let chosen = editor.chosenLayerIDs
        // Dragging a chosen layer brings the other chosen layers along (FR-8.6).
        let movesChosen = dragged.map { chosen.count > 1 && chosen.contains($0.id) } ?? false
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Layers", detail: "\(layers.count)")

            HStack(spacing: 6) {
                BlendModeMenu(editor: editor, mode: layers[active].blendMode)
                OpacityControl(editor: editor, opacity: layers[active].opacity)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .disabled(layers[active].isLocked)

            if layers[active].adjustment != nil {
                Toggle("Only the layer below", isOn: Binding(get: { layers[active].clipsToLayerBelow },
                                                             set: { editor.setClipsToLayerBelow($0) }))
                    .font(.system(size: 11.5))
                    .controlSize(.small)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .disabled(layers[active].isLocked || (!layers[active].clipsToLayerBelow && !editor.canvas.canClip(layerAt: active)))
                    .help("On: this adjustment changes only the layer under it. Off: everything below it")
            }

            ScrollView {
                VStack(spacing: 2) {
                    // Top of the stack first, as it's seen.
                    ForEach(Array(layers.enumerated().reversed()), id: \.element.id) { index, layer in
                        // The row itself follows the pointer and lands where it's let go. The system drag never
                        // reached the drop target over the canvas (Leah, 2026-10-04).
                        let isDragged = dragged?.id == layer.id || (movesChosen && chosen.contains(layer.id))
                        row(layer, index: index, isActive: index == active, isChosen: chosen.contains(layer.id))
                            .offset(y: isDragged ? dragged?.translation ?? 0 : 0)
                            .shadow(color: .black.opacity(isDragged ? 0.25 : 0), radius: 6, y: 2)
                            .zIndex(isDragged ? 1 : 0)
                            .gesture(DragGesture(minimumDistance: 4)
                                .onChanged { dragged = (layer.id, $0.translation.height) }
                                .onEnded { value in
                                    dragged = nil
                                    // Rows are listed top of the stack first, so moving down the list moves down the stack.
                                    let steps = Int((value.translation.height / Self.rowPitch).rounded())
                                    let destination = min(max(index - steps, 0), layers.count - 1)
                                    if destination != index { editor.moveLayer(from: index, to: destination) }
                                })
                    }
                }
                .padding(.horizontal, 6)
            }
            .frame(minHeight: 120, maxHeight: .infinity)

            HStack(spacing: 2) {
                footerButton("plus", "New Layer", ShortcutStore.shared.hint("New Layer", command: "newLayer:")) { editor.addLayer() }
                footerButton("plus.square.on.square", "Duplicate Layer", ShortcutStore.shared.hint("Duplicate Layer", command: "duplicateLayer:")) { editor.duplicateLayer() }
                footerButton("trash", "Delete Layer", ShortcutStore.shared.hint("Delete Layer", command: "deleteLayer:")) { editor.deleteLayer() }
                    .disabled(!editor.canDeleteLayers)
                footerButton("arrow.down.to.line", editor.mergeCommandTitle, ShortcutStore.shared.hint(editor.mergeCommandTitle, command: "mergeDown:")) { editor.mergeDown() }
                    .disabled(!editor.canMerge)
                Spacer()
                AddAdjustmentMenu(editor: editor)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .foregroundStyle(.primary)
    }

    private func row(_ layer: Layer, index: Int, isActive: Bool, isChosen: Bool) -> some View {
        HStack(spacing: 8) {
            Button { editor.setLayerVisible(!layer.isVisible, at: index) } label: {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                    .font(.system(size: 12))
                    .frame(width: 18, height: 18)
                    .opacity(layer.isVisible ? 1 : 0.5)
            }
            .buttonStyle(.plain)
            .help(layer.isVisible ? "Hide this layer" : "Show this layer")
            .accessibilityLabel(layer.isVisible ? "Hide \(layer.name)" : "Show \(layer.name)")

            if layer.adjustment != nil, layer.clipsToLayerBelow {
                // Clipped: it belongs to the layer under it.
                Image(systemName: "arrow.turn.left.down")
                    .font(.system(size: 10))
                    .frame(width: 10)
                    .opacity(0.7)
                    .accessibilityHidden(true)
            }
            Group {
                if let choice = layer.adjustment.flatMap(AdjustmentChoice.init) {
                    // An adjustment layer has no pixels to show; its icon says what it does.
                    Image(systemName: choice.symbol)
                        .font(.system(size: 13))
                        .frame(width: 40, height: 26)
                        .background(isActive ? Color.white.opacity(0.18) : Theme.field)
                } else {
                    Image(nsImage: LayerThumbnail.image(for: layer, revision: editor.layersRevision, colorSpace: editor.canvas.colorSpace))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 40, height: 26)
                        .background(Checkerboard(square: 4))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.gray.opacity(0.4), lineWidth: 0.5))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                if renaming === layer {
                    TextField("Name", text: $newName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .onSubmit { finishRenaming(index) }
                        .onExitCommand { renaming = nil }
                } else {
                    Text(layer.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                }
                Text(layer.adjustment == nil
                     ? "\(layer.blendMode.name) · \(Int((layer.opacity * 100).rounded()))%"
                     : layer.clipsToLayerBelow
                        ? (editor.canvas.clipBaseIndex(forLayerAt: index) == nil ? "Layer below only: none"
                            : layer.blendMode == .normal ? "Layer below only" : "Layer below only · \(layer.blendMode.name)")
                        : "Adjustment · \(layer.blendMode.name)")
                    .font(.system(size: 10.5))
                    .opacity(0.7)
            }
            Spacer(minLength: 0)
            Button { editor.setLayerLocked(!layer.isLocked, at: index) } label: {
                Image(systemName: layer.isLocked ? "lock.fill" : "lock.open")
                    .font(.system(size: 11))
                    .frame(width: 18, height: 18)
                    .opacity(layer.isLocked ? 1 : 0.35)
            }
            .buttonStyle(.plain)
            .help(layer.isLocked ? "Unlock: allow changes to this layer" : "Lock: protect this layer from changes")
            .accessibilityLabel(layer.isLocked ? "Unlock \(layer.name)" : "Lock \(layer.name)")
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .frame(height: 40)
        .foregroundStyle(isActive ? Color.white : Color.primary)
        // The other chosen layers are tinted; the active one, where drawing goes, is solid.
        .background(isActive ? Color.accentColor : isChosen ? Color.accentColor.opacity(0.3) : .clear, in: RoundedRectangle(cornerRadius: 9))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            newName = layer.name
            renaming = layer
        }
        .onTapGesture {
            let flags = NSEvent.modifierFlags
            editor.chooseLayer(at: index, extending: flags.contains(.shift), toggling: flags.contains(.command))
        }
        .contextMenu { menu(for: layer, index: index, isChosen: isChosen) }
        .help("Click to make active · Shift- or ⌘-click to choose several · double-click to rename · drag to reorder")
        .accessibilityAddTraits(isActive || isChosen ? [.isSelected] : [])
        .accessibilityAction(named: "Make Active") { editor.selectLayer(at: index) }
        // Reordering without dragging (review J, finding 29: A6).
        .accessibilityAction(named: "Move Up") { if index + 1 < editor.layers.count { editor.moveLayer(from: index, to: index + 1) } }
        .accessibilityAction(named: "Move Down") { if index > 0 { editor.moveLayer(from: index, to: index - 1) } }
        .accessibilityAction(named: "Rename") {
            newName = layer.name
            renaming = layer
        }
    }

    /// The right-click menu (FR-8.6). A layer that isn't chosen is chosen alone before its command runs, so the menu
    /// speaks for it alone.
    @ViewBuilder
    private func menu(for layer: Layer, index: Int, isChosen: Bool) -> some View {
        let several = isChosen && editor.hasSeveralChosenLayers
        let layers = several ? "Layers" : "Layer"
        let leader = isChosen ? editor.canvas.activeLayer : layer
        Button(several ? "Merge Layers" : "Merge Down") { run(index) { editor.mergeDown() } }
            .disabled(several ? !editor.canMerge : !LayerActions.canMergeDown(editor.canvas, layerAt: index))
        Button("Duplicate \(layers)") { run(index) { editor.duplicateLayer() } }
        Button("Delete \(layers)") { run(index) { editor.deleteLayer() } }
            .disabled(several ? !editor.canDeleteLayers : !LayerActions.canDelete(editor.canvas, layerAt: index))
        Divider()
        Button((leader.isVisible ? "Hide " : "Show ") + layers) { run(index) { editor.toggleChosenLayersVisible() } }
        Button((leader.isLocked ? "Unlock " : "Lock ") + layers) { run(index) { editor.toggleChosenLayersLocked() } }
        Divider()
        Button("Rename…") {
            newName = layer.name
            renaming = layer
        }
        // Its name, blend mode and opacity are at the top of this panel once it's the active layer.
        Button("Layer Properties…") { editor.selectLayer(at: index) }
    }

    private func run(_ index: Int, _ command: () -> Void) {
        editor.chooseForMenu(layerAt: index)
        command()
    }

    private func finishRenaming(_ index: Int) {
        editor.renameLayer(at: index, to: newName)
        renaming = nil
    }

    private func footerButton(_ symbol: String, _ name: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.secondaryInk)
        .help(help)
        .accessibilityLabel(name)
    }
}

/// The active layer's blend mode, as a menu in the mockup's groups (FR-8.2).
private struct BlendModeMenu: View {
    let editor: Editor
    let mode: ColorbeeCore.BlendMode

    var body: some View {
        Menu {
            ForEach(Array(ColorbeeCore.BlendMode.groups.enumerated()), id: \.offset) { index, group in
                if index > 0 { Divider() }
                ForEach(group, id: \.self) { candidate in
                    Toggle(candidate.name, isOn: Binding(get: { candidate == mode }, set: { _ in editor.setBlendMode(candidate) }))
                }
            }
        } label: {
            HStack {
                Text(mode.name)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).opacity(0.7)
            }
            .font(.system(size: 12))
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .frame(height: 24)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .help("Blend mode: how this layer mixes with the layers below")
    }
}

/// The active layer's opacity: the percentage opens a slider. Dragging it is one undo step.
private struct OpacityControl: View {
    let editor: Editor
    let opacity: Double
    @State private var isOpen = false

    var body: some View {
        Button { isOpen.toggle() } label: {
            HStack(spacing: 4) {
                Text("Opacity").font(.system(size: 11)).foregroundStyle(Theme.secondaryInk).fixedSize()
                Spacer(minLength: 0)
                Text("\(Int((opacity * 100).rounded()))%").font(.system(size: 12)).monospacedDigit()
            }
            .padding(.horizontal, 8)
            .frame(width: 108, height: 24)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Layer opacity")
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            HStack {
                Slider(value: Binding(get: { (opacity * 100).rounded() }, set: { editor.previewOpacity(($0 / 100 * 100).rounded() / 100) }), in: 0...100) { editing in
                    if !editing { editor.finishLayerSettings() }
                }
                .accessibilityLabel("Opacity")
                .accessibilityValue("\(Int((opacity * 100).rounded())) percent")
                .frame(width: 160)
                Text("\(Int((opacity * 100).rounded()))%").monospacedDigit().frame(width: 40, alignment: .trailing)
            }
            .padding(12)
        }
    }
}

/// Small pictures of each layer for the panel, redrawn only when the layer's pixels may have changed.
@MainActor
enum LayerThumbnail {
    private static var cache: [ObjectIdentifier: (revision: Int, image: NSImage)] = [:]
    private static let maxSide = 80

    static func image(for layer: Layer, revision: Int, colorSpace: CGColorSpace) -> NSImage {
        let key = ObjectIdentifier(layer)
        if let cached = cache[key], cached.revision == revision { return cached.image }
        let source = layer.buffer
        let scale = min(1, Double(maxSide) / Double(max(source.width, source.height)))
        let width = max(1, Int(Double(source.width) * scale)), height = max(1, Int(Double(source.height) * scale))
        // Sampling rather than averaging: fast enough to redraw after every stroke, even on huge images.
        let small = PixelBuffer(width: width, height: height)
        for y in 0..<height {
            let row = source.row(min(source.height - 1, Int((Double(y) + 0.5) / scale)))
            let target = small.row(y)
            for x in 0..<width { target[x] = row[min(source.width - 1, Int((Double(x) + 0.5) / scale))] }
        }
        let image: NSImage
        if let cgImage = try? ImageCodec.makeCGImage(small, colorSpace: colorSpace) {
            image = NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
        } else {
            image = NSImage(size: NSSize(width: width, height: height))
        }
        cache[key] = (revision, image)
        return image
    }
}
