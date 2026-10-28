import SwiftUI

/// A slider with two handles for a range's lower and upper ends, as Luminance Range uses (FR-9.7 item 3). Dragging
/// moves whichever handle is nearer where the drag starts; the handles can't cross.
struct RangeSlider: View {
    @Binding var lower: Double
    @Binding var upper: Double
    let bounds: ClosedRange<Double>
    /// A set width rather than a GeometryReader, which grew the effect bar's height to fill the window.
    var width: CGFloat = 150

    /// The handle a drag moves, chosen when it starts.
    @State private var movingUpper: Bool?

    private let thumb: CGFloat = 14

    private func position(of value: Double, width: CGFloat) -> CGFloat {
        CGFloat((value - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound)) * max(width - thumb, 1) + thumb / 2
    }

    private func value(at x: CGFloat, width: CGFloat) -> Double {
        let fraction = Double((x - thumb / 2) / max(width - thumb, 1))
        return min(max(fraction * (bounds.upperBound - bounds.lowerBound) + bounds.lowerBound, bounds.lowerBound), bounds.upperBound)
    }

    var body: some View {
        Group {
            let x = { (value: Double) in position(of: value, width: width) }
            let value = { (x: CGFloat) in self.value(at: x, width: width) }
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.25)).frame(height: 4)
                Capsule().fill(Color.accentColor)
                    .frame(width: max(x(upper) - x(lower), 0), height: 4)
                    .offset(x: x(lower))
                ForEach([false, true], id: \.self) { isUpper in
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
                        .frame(width: thumb, height: thumb)
                        .offset(x: x(isUpper ? upper : lower) - thumb / 2)
                }
            }
            .frame(width: width, height: 18)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    let moving = movingUpper ?? (abs(drag.startLocation.x - x(upper)) < abs(drag.startLocation.x - x(lower))
                        || (upper == lower && drag.startLocation.x > x(upper)))
                    movingUpper = moving
                    let new = value(drag.location.x)
                    if moving { upper = max(new, lower) } else { lower = min(new, upper) }
                }
                .onEnded { _ in movingUpper = nil })
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Range")
        .accessibilityValue("\(Int(lower)) to \(Int(upper))")
        .accessibilityAdjustableAction { direction in
            // VoiceOver moves the whole range together, keeping its width.
            let step = direction == .increment ? 5.0 : -5.0
            let width = upper - lower
            let newLower = min(max(lower + step, bounds.lowerBound), bounds.upperBound - width)
            lower = newLower
            upper = newLower + width
        }
    }
}
