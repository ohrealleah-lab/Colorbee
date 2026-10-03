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

    @State private var dragging: Int?

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
                    context.translateBy(x: Self.inset, y: Self.inset)
                    let size = CGSize(width: fullSize.width - 2 * Self.inset, height: fullSize.height - 2 * Self.inset)
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
                    .onChanged { drag in move(drag, in: size) }
                    .onEnded { _ in
                        dragging = nil
                        onFinish()
                    })
                .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { tap in remove(near: tap.location, in: size) })
            }
            .aspectRatio(1, contentMode: .fit)
            .accessibilityLabel("Curve")
        }
    }

    private static let inset: CGFloat = 5

    private var lineColor: Color {
        switch channel {
        case .rgb: .primary
        case .red: .red
        case .green: .green
        case .blue: .blue
        }
    }

    /// Where a point sits in the view, whose plot area is inset on every side.
    private func location(of point: Curves.Point, in size: CGSize) -> CGPoint {
        let width = size.width - 2 * Self.inset, height = size.height - 2 * Self.inset
        return CGPoint(x: Self.inset + point.x / 255 * width, y: Self.inset + (1 - point.y / 255) * height)
    }

    private func value(at location: CGPoint, in size: CGSize) -> Curves.Point {
        let width = Double(size.width - 2 * Self.inset), height = Double(size.height - 2 * Self.inset)
        let x: Double = min(max(Double(location.x - Self.inset) / width, 0), 1) * 255
        let y: Double = min(max(1 - Double(location.y - Self.inset) / height, 0), 1) * 255
        return Curves.Point(x: x.rounded(), y: y.rounded())
    }

    private func nearest(to location: CGPoint, in size: CGSize) -> Int? {
        let points = curves[channel]
        let distances = points.indices.map { index -> (Int, Double) in
            let center = self.location(of: points[index], in: size)
            return (index, hypot(center.x - location.x, center.y - location.y))
        }
        return distances.filter { $0.1 <= 10 }.min { $0.1 < $1.1 }?.0
    }

    private func move(_ drag: DragGesture.Value, in size: CGSize) {
        var points = curves[channel]
        if dragging == nil {
            if let index = nearest(to: drag.startLocation, in: size) {
                dragging = index
            } else {
                points.append(value(at: drag.startLocation, in: size))
                points.sort { $0.x < $1.x }
                dragging = points.firstIndex(of: value(at: drag.startLocation, in: size))
            }
        }
        guard let index = dragging, points.indices.contains(index) else { return }
        // Dragging a middle point well outside the graph removes it.
        let outside = drag.location.x < -20 || drag.location.x > size.width + 20 || drag.location.y < -20 || drag.location.y > size.height + 20
        if outside, index != 0, index != points.count - 1 {
            points.remove(at: index)
            dragging = -1
        } else {
            var point = value(at: drag.location, in: size)
            // A point stays between its neighbors, so the curve stays a function of x.
            let low = index > 0 ? points[index - 1].x + 1 : 0
            let high = index < points.count - 1 ? points[index + 1].x - 1 : 255
            point.x = min(max(point.x, low), high)
            points[index] = point
        }
        var changed = curves
        changed[channel] = points
        onChange(changed)
    }

    private func remove(near location: CGPoint, in size: CGSize) {
        var points = curves[channel]
        guard let index = nearest(to: location, in: size), index != 0, index != points.count - 1 else { return }
        points.remove(at: index)
        var changed = curves
        changed[channel] = points
        onChange(changed)
        onFinish()
    }
}
