import AppKit
import ColorbeeCore
import SwiftUI

/// A color wheel for Color Grading (FR-9.7 item 2): drag the point around, and its angle is the hue and its distance
/// from the middle the strength. Hold Option to move it finely; double-click to put it back in the middle. The other
/// wheels show as small dots (Leah, 2026-10-27).
struct ColorWheel: View {
    let title: String
    let wheel: ColorGrading.Wheel
    var others: [ColorGrading.Wheel] = []
    let onChange: (ColorGrading.Wheel) -> Void
    var onFinish: () -> Void = {}

    /// Where the point was, and where the drag began, so Option slows it from there.
    @State private var dragStart: (point: CGPoint, location: CGPoint)?

    /// Hue increases counterclockwise from red at the right, as on a color circle; SwiftUI's angular gradient
    /// runs clockwise, so its stops go the other way.
    private static let ring = AngularGradient(gradient: Gradient(colors: (0...12).map { step in
        Color(hue: Double((12 - step) % 12) / 12, saturation: 1, brightness: 1)
    }), center: .center)

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let radius = side / 2
            ZStack {
                Circle().fill(Self.ring)
                Circle().fill(RadialGradient(colors: [.white, .white.opacity(0)], center: .center, startRadius: 0, endRadius: radius))
                Circle().strokeBorder(Theme.secondaryInk.opacity(0.35), lineWidth: 1)
                ForEach(Array(others.enumerated()), id: \.offset) { _, other in
                    Circle().fill(Color.black.opacity(0.35)).frame(width: 5, height: 5)
                        .position(Self.point(for: other, radius: radius))
                }
                Circle()
                    .strokeBorder(Color.white, lineWidth: 2)
                    .background(Circle().fill(Color.black.opacity(0.25)))
                    .frame(width: 12, height: 12)
                    .shadow(radius: 1)
                    .position(Self.point(for: wheel, radius: radius))
            }
            .frame(width: side, height: side)
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let start = dragStart ?? (Self.point(for: wheel, radius: radius), value.startLocation)
                    if dragStart == nil {
                        dragStart = start
                        // A click lands the point where it was clicked; a drag from the point moves it from there.
                        let fromPoint = hypot(value.startLocation.x - start.point.x, value.startLocation.y - start.point.y) < 10
                        if !fromPoint { dragStart = (value.startLocation, value.startLocation) }
                    }
                    let speed = NSEvent.modifierFlags.contains(.option) ? 0.25 : 1
                    let origin = dragStart!
                    let point = CGPoint(x: origin.point.x + (value.location.x - origin.location.x) * speed,
                                        y: origin.point.y + (value.location.y - origin.location.y) * speed)
                    onChange(Self.wheel(at: point, radius: radius, keeping: wheel))
                }
                .onEnded { _ in
                    dragStart = nil
                    onFinish()
                })
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                onChange(ColorGrading.Wheel(luminance: wheel.luminance))
                onFinish()
            })
        }
        .aspectRatio(1, contentMode: .fit)
        .help("Drag to tint toward a color; farther out is stronger. Option-drag moves finely; double-click resets.")
        .accessibilityElement()
        .accessibilityLabel("\(title) color wheel")
        .accessibilityValue("Hue \(Int(wheel.hue.rounded())) degrees, strength \(Int(wheel.strength.rounded()))")
        .accessibilityAdjustableAction { direction in
            var changed = wheel
            changed.strength += direction == .increment ? 5 : -5
            onChange(changed)
            onFinish()
        }
        .accessibilityAction(named: "Turn hue counterclockwise") { turn(15) }
        .accessibilityAction(named: "Turn hue clockwise") { turn(-15) }
    }

    private func turn(_ degrees: Double) {
        var changed = wheel
        changed.hue += degrees
        onChange(changed)
        onFinish()
    }

    static func point(for wheel: ColorGrading.Wheel, radius: CGFloat) -> CGPoint {
        let angle = wheel.hue * .pi / 180, distance = wheel.strength / 100 * radius
        return CGPoint(x: radius + cos(angle) * distance, y: radius - sin(angle) * distance)
    }

    static func wheel(at point: CGPoint, radius: CGFloat, keeping wheel: ColorGrading.Wheel) -> ColorGrading.Wheel {
        let dx = point.x - radius, dy = radius - point.y
        var hue = atan2(dy, dx) * 180 / .pi
        if hue < 0 { hue += 360 }
        let strength = min(hypot(dx, dy) / radius, 1) * 100
        return ColorGrading.Wheel(hue: hue.rounded(), strength: strength.rounded(), luminance: wheel.luminance)
    }
}
