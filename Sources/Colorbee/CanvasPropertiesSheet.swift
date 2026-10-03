import ColorbeeCore
import SwiftUI

/// Canvas Properties (⌥⌘E): the canvas size and whether its background is transparent (FR-1.4, FR-2.2).
/// The image stays at the top-left; new area gets Color 2, or transparency.
struct CanvasPropertiesSheet: View {
    let editor: Editor
    @State private var width: Int
    @State private var height: Int
    @State private var transparent: Bool

    init(editor: Editor) {
        self.editor = editor
        _width = State(initialValue: editor.canvasSize.width)
        _height = State(initialValue: editor.canvasSize.height)
        _transparent = State(initialValue: editor.hasTransparentBackground)
    }

    private var valid: Bool {
        width >= 1 && height >= 1 && width <= ResizeSkew.maxSide && height <= ResizeSkew.maxSide && width * height <= ResizeSkew.maxArea
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Canvas Properties").font(.headline)
            Grid(alignment: .leading, verticalSpacing: 8) {
                GridRow {
                    Text("Width")
                    TextField("Width", value: $width, format: .number).frame(width: 90).labelsHidden()
                    Text("px")
                }
                GridRow {
                    Text("Height")
                    TextField("Height", value: $height, format: .number).frame(width: 90).labelsHidden()
                    Text("px")
                }
            }
            Text("The image stays at the top-left. New area is filled with Color 2, or left transparent.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Transparent background", isOn: $transparent)
                .help("What erasing and new canvas area leave behind on the background. Existing pixels don't change.")
            if !valid {
                Label("Sizes run from 1 to \(ResizeSkew.maxSide.formatted()) px.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { editor.isCanvasPropertiesOpen = false }
                    .keyboardShortcut(.cancelAction)
                Button("OK") {
                    editor.applyCanvasProperties(size: IntSize(width: width, height: height), transparentBackground: transparent)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!valid)
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}

/// Pixel rulers along the top and left of the canvas area (View ▸ Show Rulers, ⌘R).
struct Rulers: View {
    let editor: Editor
    static let thickness: CGFloat = 18

    var body: some View {
        let viewport = editor.viewport
        ZStack(alignment: .topLeading) {
            ruler(viewport: viewport, horizontal: true)
                .frame(height: Self.thickness)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            ruler(viewport: viewport, horizontal: false)
                .frame(width: Self.thickness)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            Rectangle().fill(.bar).frame(width: Self.thickness, height: Self.thickness)
        }
        .allowsHitTesting(false)
    }

    private func ruler(viewport: Viewport, horizontal: Bool) -> some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(nsColor: .windowBackgroundColor).opacity(0.92)))
            let length = horizontal ? size.width : size.height
            // Label spacing: the smallest of 1, 2, 5 × a power of ten that leaves ~60 pt between labels.
            let candidates = [1.0, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000, 10000]
            let step = candidates.first { $0 * viewport.zoom >= 60 } ?? 10000
            // Small ticks every fifth of a label step, but never closer than one pixel.
            let minor = step >= 5 ? step / 5 : step
            let startImage = horizontal ? viewport.imagePoint(fromView: Point2D(x: 0, y: 0)).x : viewport.imagePoint(fromView: Point2D(x: 0, y: 0)).y
            let endImage = horizontal ? viewport.imagePoint(fromView: Point2D(x: length, y: 0)).x : viewport.imagePoint(fromView: Point2D(x: 0, y: length)).y
            var value = (startImage / minor).rounded(.down) * minor
            while value <= endImage {
                let position = horizontal ? viewport.viewPoint(fromImage: Point2D(x: value, y: 0)).x : viewport.viewPoint(fromImage: Point2D(x: 0, y: value)).y
                let isMajor = abs(value / step - (value / step).rounded()) < 1e-9
                let tick = isMajor ? Self.thickness * 0.55 : Self.thickness * 0.25
                var path = Path()
                if horizontal {
                    path.move(to: CGPoint(x: position, y: Self.thickness - tick))
                    path.addLine(to: CGPoint(x: position, y: Self.thickness))
                } else {
                    path.move(to: CGPoint(x: Self.thickness - tick, y: position))
                    path.addLine(to: CGPoint(x: Self.thickness, y: position))
                }
                context.stroke(path, with: .color(.secondary), lineWidth: 0.5)
                if isMajor {
                    let label = Text("\(Int(value))").font(.system(size: 9)).foregroundStyle(.secondary)
                    if horizontal {
                        context.draw(label, at: CGPoint(x: position + 3, y: 1), anchor: .topLeading)
                    } else {
                        var rotated = context
                        rotated.translateBy(x: 1, y: position + 3)
                        rotated.rotate(by: .degrees(90))
                        rotated.draw(label, at: .zero, anchor: .bottomLeading)
                    }
                }
                value += minor
            }
            var edge = Path()
            if horizontal {
                edge.move(to: CGPoint(x: 0, y: size.height - 0.25))
                edge.addLine(to: CGPoint(x: size.width, y: size.height - 0.25))
            } else {
                edge.move(to: CGPoint(x: size.width - 0.25, y: 0))
                edge.addLine(to: CGPoint(x: size.width - 0.25, y: size.height))
            }
            context.stroke(edge, with: .color(.secondary.opacity(0.5)), lineWidth: 0.5)
        }
    }
}

/// Numbered badges on Auto-Redact's matches, matching the numbers in the review list (mockup 1c).
struct RedactionBadges: View {
    let editor: Editor

    var body: some View {
        if let session = editor.autoRedact {
            let viewport = editor.viewport
            ZStack(alignment: .topLeading) {
                ForEach(Array(session.matches.enumerated()), id: \.element.id) { index, match in
                    let corner = viewport.viewPoint(fromImage: Point2D(x: Double(match.rect.maxX), y: Double(match.rect.minY)))
                    let active = !session.keptVisible.contains(match.id)
                    Text("\(index + 1)")
                        .font(.system(size: 10.5, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .frame(minWidth: 18, minHeight: 18)
                        .padding(.horizontal, 2)
                        .background(active ? Color.orange : Color.gray, in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.8), lineWidth: 1))
                        .position(x: corner.x + 4, y: corner.y - 4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(false)
        }
    }
}
