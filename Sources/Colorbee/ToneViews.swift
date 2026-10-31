import ColorbeeCore
import SwiftUI

/// Levels' histogram: how many pixels have each brightness, scaled so a spike doesn't flatten the rest.
struct HistogramView: View {
    let histogram: Histogram?
    var black: Double = 0
    var white: Double = 255

    var body: some View {
        Canvas { context, size in
            guard let histogram, !histogram.isEmpty else { return }
            // Square roots keep small counts visible next to a big spike (a white background, say).
            let heights = histogram.luminance.map { Double($0).squareRoot() }
            let tallest = max(heights.max() ?? 1, 1)
            var path = Path()
            for (value, height) in heights.enumerated() {
                let x = Double(value) / 256 * size.width
                path.addRect(CGRect(x: x, y: size.height * (1 - height / tallest), width: max(1, size.width / 256), height: size.height * height / tallest))
            }
            context.fill(path, with: .color(Theme.secondaryInk.opacity(0.75)))
            // Shade what the black and white points clip.
            context.fill(Path(CGRect(x: 0, y: 0, width: black / 255 * size.width, height: size.height)), with: .color(.black.opacity(0.18)))
            let whiteX = white / 255 * size.width
            context.fill(Path(CGRect(x: whiteX, y: 0, width: size.width - whiteX, height: size.height)), with: .color(.black.opacity(0.18)))
        }
        .background(Theme.field, in: RoundedRectangle(cornerRadius: 4))
        .accessibilityLabel("Histogram")
    }
}

/// The Curves graph (FR-9.5): click to add a point, drag to move it, drag it off the side or
/// double-click it to remove it. The end points can move but not be removed.
struct CurvesEditor: View {
    let curves: Curves
    @Binding var channel: Curves.Channel
    let onChange: (Curves) -> Void
    var onFinish: () -> Void = {}

    @State private var drag: CurveDrag?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Channel", selection: $channel) {
                Text("RGB").tag(Curves.Channel.rgb)
                Text("Red").tag(Curves.Channel.red)
                Text("Green").tag(Curves.Channel.green)
                Text("Blue").tag(Curves.Channel.blue)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("Which curve to edit: all channels together, or one color")
            GeometryReader { geometry in
                let size = geometry.size
                let points = curves[channel]
                Canvas { context, fullSize in
                    // Inset so the end points' handles aren't cut off at the corners.
                    context.translateBy(x: CurveDrag.inset, y: CurveDrag.inset)
                    let size = CGSize(width: fullSize.width - 2 * CurveDrag.inset, height: fullSize.height - 2 * CurveDrag.inset)
                    for step in 1..<4 {
                        let x = size.width * Double(step) / 4, y = size.height * Double(step) / 4
                        context.stroke(Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: size.height)) }, with: .color(.gray.opacity(0.25)))
                        context.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y)) }, with: .color(.gray.opacity(0.25)))
                    }
                    context.stroke(Path { $0.move(to: CGPoint(x: 0, y: size.height)); $0.addLine(to: CGPoint(x: size.width, y: 0)) }, with: .color(.gray.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    let table = Curves.table(points)
                    var curve = Path()
                    for value in 0..<256 {
                        let point = CGPoint(x: Double(value) / 255 * size.width, y: (1 - Double(table[value]) / 255) * size.height)
                        if value == 0 { curve.move(to: point) } else { curve.addLine(to: point) }
                    }
                    context.stroke(curve, with: .color(lineColor), lineWidth: 1.5)
                    for point in points {
                        let center = CGPoint(x: point.x / 255 * size.width, y: (1 - point.y / 255) * size.height)
                        context.fill(Path(ellipseIn: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)), with: .color(.white))
                        context.stroke(Path(ellipseIn: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)), with: .color(lineColor), lineWidth: 1.5)
                    }
                }
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        var moving = drag ?? CurveDrag(size: size)
                        let points = moving.moved(curves[channel], start: value.startLocation, location: value.location, translation: value.translation)
                        drag = moving
                        if let points { change(to: points) }
                    }
                    .onEnded { _ in
                        drag = nil
                        onFinish()
                    })
                .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { tap in
                    guard let points = CurveDrag(size: size).removing(near: tap.location, from: curves[channel]) else { return }
                    change(to: points)
                    onFinish()
                })
            }
            .aspectRatio(1, contentMode: .fit)
            .accessibilityLabel("Curve")
            .accessibilityValue(curves[channel].map { "\(Int($0.x)) to \(Int($0.y))" }.joined(separator: ", "))
        }
    }

    private var lineColor: Color {
        switch channel {
        case .rgb: .primary
        case .red: .red
        case .green: .green
        case .blue: .blue
        }
    }

    private func change(to points: [Curves.Point]) {
        var changed = curves
        changed[channel] = points
        onChange(changed)
    }
}

/// Adjust Photo's live histogram (FR-9.7 item 6), with the clipping warning buttons in its top corners: shadows at the
/// left, highlights at the right, off to start (Q15.2).
struct PhotoHistogram: View {
    let editor: Editor

    var body: some View {
        HistogramView(histogram: editor.photoHistogram)
            .frame(height: 54)
            .overlay(alignment: .topLeading) {
                warning("arrowtriangle.left.fill", isOn: editor.clipsShadows, color: .blue, name: "Shadow clipping") {
                    editor.clipsShadows.toggle()
                }
            }
            .overlay(alignment: .topTrailing) {
                warning("arrowtriangle.right.fill", isOn: editor.clipsHighlights, color: .red, name: "Highlight clipping") {
                    editor.clipsHighlights.toggle()
                }
            }
            .onAppear { editor.refreshPhotoHistogram() }
    }

    private func warning(_ symbol: String, isOn: Bool, color: Color, name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9))
                .frame(width: 18, height: 16)
                .foregroundStyle(isOn ? color : Theme.secondaryInk.opacity(0.6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isOn ? "\(name) is on: click to hide it" : color == .red
              ? "Show blown highlights in red on the picture (only on screen)"
              : "Show crushed shadows in blue on the picture (only on screen)")
        .accessibilityLabel(name)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// The Tone Curve's graph (FR-9.7 item 6): the curve, the straight line it started as, and the split points between
/// its regions. Display only: the regions are changed with their sliders.
struct ToneCurveGraph: View {
    let curve: ToneCurve

    var body: some View {
        let table = curve.table
        Canvas { context, size in
            var grid = Path()
            for quarter in 1..<4 {
                let x = size.width * Double(quarter) / 4, y = size.height * Double(quarter) / 4
                grid.move(to: CGPoint(x: x, y: 0))
                grid.addLine(to: CGPoint(x: x, y: size.height))
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(grid, with: .color(Theme.separator), lineWidth: 0.5)
            var diagonal = Path()
            diagonal.move(to: CGPoint(x: 0, y: size.height))
            diagonal.addLine(to: CGPoint(x: size.width, y: 0))
            context.stroke(diagonal, with: .color(Theme.secondaryInk.opacity(0.35)), style: StrokeStyle(lineWidth: 0.75, dash: [3, 3]))
            for split in curve.splits {
                var line = Path()
                let x = size.width * split / 100
                line.move(to: CGPoint(x: x, y: 0))
                line.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(line, with: .color(Theme.secondaryInk.opacity(0.4)), lineWidth: 1)
            }
            var path = Path()
            for (value, output) in table.enumerated() {
                let point = CGPoint(x: size.width * Double(value) / 255, y: size.height * (1 - Double(output) / 255))
                if value == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.stroke(path, with: .color(Color.primary), lineWidth: 1.5)
        }
        .background(Theme.field, in: RoundedRectangle(cornerRadius: 4))
        .accessibilityElement()
        .accessibilityLabel("Tone curve")
        .accessibilityValue(ToneCurve.Region.allCases.map { "\($0.title) \(Int(curve[$0]))" }.joined(separator: ", "))
    }
}

/// The Tone Curve's three split points on one line, under the graph. Dragging moves whichever handle is nearest where
/// the drag starts; they stay in order.
struct SplitSlider: View {
    let splits: [Double]
    let onChange: (Int, Double) -> Void
    let onEnd: () -> Void

    @State private var moving: Int?
    private let thumb: CGFloat = 12

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            // Exactly under the graph's lines; splits never reach the ends, so the handles stay inside.
            let x = { (value: Double) in CGFloat(value / 100) * width }
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.25)).frame(height: 3)
                ForEach(0..<3, id: \.self) { index in
                    Image(systemName: "triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.secondaryInk)
                        .frame(width: thumb, height: thumb)
                        .offset(x: x(splits[index]) - thumb / 2)
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    let index = moving ?? Self.handle(nearest: drag.startLocation.x, splits: splits, width: width)
                    moving = index
                    onChange(index, Self.split(at: drag.location.x, width: width))
                }
                .onEnded { _ in
                    moving = nil
                    onEnd()
                })
        }
        .frame(height: 16)
        .help("Drag a split point to move where the regions meet")
        .accessibilityElement()
        .accessibilityLabel("Split points")
        .accessibilityValue(splits.map { "\(Int($0))" }.joined(separator: ", "))
    }

    /// The handle a drag starting at `x` moves: the nearest one.
    static func handle(nearest x: CGFloat, splits: [Double], width: CGFloat) -> Int {
        (0..<3).min { abs(CGFloat(splits[$0] / 100) * width - x) < abs(CGFloat(splits[$1] / 100) * width - x) }!
    }

    /// The split at `x`, 0...100 across the line; the tone curve keeps it in order and away from the ends.
    static func split(at x: CGFloat, width: CGFloat) -> Double {
        Double(x / max(width, 1)) * 100
    }
}
