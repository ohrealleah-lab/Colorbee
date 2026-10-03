import AppKit
import ColorbeeCore
import SwiftUI

/// The right sidebar (FR-1.3): an inset glass pane over the canvas surround. The switcher at the top
/// shows or hides each panel; History and Clipboard History join in stage 7.
struct Sidebar: View {
    @Bindable var editor: Editor

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                switcherButton("square.3.layers.3d", "Layers", "Layers panel (⌘L)", isOn: $editor.showsLayersPanel)
                switcherButton("slider.horizontal.3", "Adjustments", "Adjustments panel", isOn: $editor.showsAdjustmentsPanel)
                switcherButton("clock.arrow.circlepath", "History", "History panel (⌘Y)", isOn: $editor.showsHistoryPanel)
                switcherButton("list.clipboard", "Clipboard History", "Clipboard History panel (⌥⌘V)", isOn: $editor.showsClipboardPanel)
            }
            .padding(2)
            .background(Theme.field, in: Capsule())
            .padding(.top, 10)
            .padding(.bottom, 6)

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
            if !editor.showsLayersPanel && !editor.showsHistoryPanel && !editor.showsClipboardPanel {
                Spacer(minLength: 0)
            }
        }
        .frame(width: 272)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
        .padding(8)
    }

    private func switcherButton(_ symbol: String, _ name: String, _ help: String, isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
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
    @State private var renaming: Layer?
    @State private var newName = ""

    var body: some View {
        let layers = editor.layers
        let active = editor.activeLayerIndex
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Layers", detail: "\(layers.count)")

            HStack(spacing: 6) {
                BlendModeMenu(editor: editor, mode: layers[active].blendMode)
                OpacityControl(editor: editor, opacity: layers[active].opacity)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .disabled(layers[active].isLocked)

            ScrollView {
                VStack(spacing: 2) {
                    // Top of the stack first, as it's seen.
                    ForEach(Array(layers.enumerated().reversed()), id: \.element.id) { index, layer in
                        row(layer, index: index, isActive: index == active)
                            .draggable(String(index))
                            .dropDestination(for: String.self) { items, _ in
                                guard let source = items.first.flatMap(Int.init) else { return false }
                                editor.moveLayer(from: source, to: index)
                                return true
                            }
                    }
                }
                .padding(.horizontal, 6)
            }
            .frame(minHeight: 120, maxHeight: .infinity)

            HStack(spacing: 2) {
                footerButton("plus", "New Layer", "New Layer (⇧⌘N)") { editor.addLayer() }
                footerButton("plus.square.on.square", "Duplicate Layer", "Duplicate Layer (⌘J)") { editor.duplicateLayer() }
                footerButton("trash", "Delete Layer", "Delete Layer (⌘⌫)") { editor.deleteLayer() }
                    .disabled(!LayerActions.canDelete(editor.canvas))
                footerButton("arrow.down.to.line", "Merge Down", "Merge Down (⇧⌘E), or Apply Adjustment on an adjustment layer") { editor.mergeDown() }
                    .disabled(!LayerActions.canMergeDown(editor.canvas))
                Spacer()
                AddAdjustmentMenu(editor: editor)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .foregroundStyle(.primary)
    }

    private func row(_ layer: Layer, index: Int, isActive: Bool) -> some View {
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
        .background(isActive ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 9))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            newName = layer.name
            renaming = layer
        }
        .onTapGesture { editor.selectLayer(at: index) }
        .help("Click to make active · double-click to rename · drag to reorder")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
        .accessibilityAction(named: "Make Active") { editor.selectLayer(at: index) }
        .accessibilityAction(named: "Rename") {
            newName = layer.name
            renaming = layer
        }
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
