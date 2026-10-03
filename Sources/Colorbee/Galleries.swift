import AppKit
import ColorbeeCore
import SwiftUI

// MARK: Brushes

/// Picks the Brush tool, and opens the gallery of nine brushes (FR-4.2).
struct BrushGalleryButton: View {
    @Bindable var editor: Editor
    @State private var isOpen = false

    var body: some View {
        Button {
            editor.selectTool(.brush)
            isOpen.toggle()
        } label: {
            GalleryLabel(symbol: "paintbrush.pointed", selected: editor.tool == .brush || isOpen)
        }
        .buttonStyle(.plain)
        .help("Brushes (B): \(editor.brush.name)")
        .accessibilityLabel("Brushes")
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            BrushGallery(editor: editor) { isOpen = false }
        }
    }
}

private struct BrushGallery: View {
    @Bindable var editor: Editor
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Brushes").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("Left-click Color 1 · Right-click Color 2").font(.system(size: 10.5)).foregroundStyle(Theme.secondaryInk)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(64), spacing: 8), count: 3), spacing: 8) {
                ForEach(Brush.allCases, id: \.self) { brush in
                    Button {
                        editor.brush = brush
                        dismiss()
                    } label: {
                        VStack(spacing: 4) {
                            Image(nsImage: BrushPreview.image(for: brush))
                                .renderingMode(.template)
                                .foregroundStyle(.primary)
                                .frame(width: 60, height: 26)
                                .background(.background, in: RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(editor.brush == brush ? Color.accentColor : Theme.separator, lineWidth: editor.brush == brush ? 1.5 : 0.5))
                            Text(brush.name)
                                .font(.system(size: 10.5))
                                .foregroundStyle(editor.brush == brush ? Color.accentColor : .primary)
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .frame(width: 64)
                        .padding(.vertical, 4)
                        .background(editor.brush == brush ? Theme.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            // Clicking picks a brush; the keyboard focus ring around the first card only looked like a selection.
            .focusEffectDisabled()
            Divider()
            Toggle("Pressure changes the size", isOn: $editor.usesPressure)
                .font(.system(size: 11))
                .controlSize(.small)
                .help("Press harder on a Force Touch trackpad or a pen tablet for a bigger stroke")
        }
        .padding(12)
        .frame(width: 280)
    }
}

/// A short wavy stroke of each brush, drawn by the brush itself, for the gallery.
@MainActor
enum BrushPreview {
    private static var cache: [Brush: NSImage] = [:]

    static func image(for brush: Brush) -> NSImage {
        if let cached = cache[brush] { return cached }
        let scale = 2, width = 60, height = 26
        let canvas = Canvas(size: IntSize(width: width * scale, height: height * scale), colorSpace: Canvas.defaultColorSpace, background: .clear)
        let history = History(byteBudget: .max)
        let edit = history.beginEdit("Preview", on: canvas)
        let stroke = brush.makeStroke(diameter: brush == .naturalPencil ? 6 : 10, color: .black, layer: canvas.activeLayer, edit: edit, seed: 4)
        for step in 0...60 {
            let t = Double(step) / 60
            let x = (8 + t * Double(width - 16)) * Double(scale)
            let y = (Double(height) / 2 + sin(t * .pi * 2) * 5) * Double(scale)
            stroke.move(to: Point2D(x: x, y: y), pressure: 1)
        }
        stroke.finish()
        let image: NSImage
        if let cgImage = try? ImageCodec.makeCGImage(canvas.activeLayer.buffer, colorSpace: Canvas.defaultColorSpace) {
            image = NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
        } else {
            image = NSImage(size: NSSize(width: width, height: height))
        }
        image.isTemplate = true
        cache[brush] = image
        return image
    }
}

// MARK: Shapes

/// Picks the Shapes tool, and opens the gallery of shapes (FR-5.1).
struct ShapeGalleryButton: View {
    @Bindable var editor: Editor
    @State private var isOpen = false

    var body: some View {
        Button {
            editor.selectTool(.shape)
            isOpen.toggle()
        } label: {
            GalleryLabel(symbol: editor.shapeKind.symbol, selected: editor.tool == .shape || isOpen)
        }
        .buttonStyle(.plain)
        .help("Shapes (U): \(editor.shapeKind.name)")
        .accessibilityLabel("Shapes")
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            ShapeGallery(editor: editor) { isOpen = false }
        }
    }
}

private struct ShapeGallery: View {
    @Bindable var editor: Editor
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Shapes").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(ShapeKind.allCases.count)").font(.system(size: 10.5)).foregroundStyle(Theme.secondaryInk)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 6), count: 6), spacing: 6) {
                ForEach(ShapeKind.allCases, id: \.self) { kind in
                    Button {
                        editor.shapeKind = kind
                        dismiss()
                    } label: {
                        ToolbarGlyph(symbol: kind.symbol, selected: editor.shapeKind == kind)
                    }
                    .buttonStyle(.plain)
                    .help(kind.name)
                }
            }
            .focusEffectDisabled()
            Divider()
            VStack(alignment: .leading, spacing: 2) {
                Text(editor.shapeKind.name).font(.system(size: 11, weight: .semibold))
                Text(editor.shapeKind.hint).font(.system(size: 10.5)).foregroundStyle(Theme.secondaryInk)
            }
        }
        .padding(12)
        .frame(width: 236)
    }
}

/// A gallery button's face: the symbol and a small chevron.
private struct GalleryLabel: View {
    let symbol: String
    let selected: Bool

    var body: some View {
        HStack(spacing: 1) {
            Image(systemName: symbol).font(.system(size: 15))
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).opacity(0.6)
        }
        .padding(.leading, 8)
        .padding(.trailing, 5)
        .frame(height: 28)
        .foregroundStyle(selected ? Color.accentColor : Color.primary)
        .background(selected ? Theme.accentSoft : .clear, in: Capsule())
        .contentShape(Capsule())
    }
}

extension ShapeKind {
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

    var hint: String {
        switch self {
        case .polygon: "Click each corner; click the first corner or double-click to close"
        case .curve: "Drag a line, then drag twice to bend it"
        case .line, .arrow: "Shift snaps to 45° · editable until ⏎"
        default: "Shift keeps proportions · editable until ⏎"
        }
    }
}
