import ColorbeeCore
import Foundation
import Testing
@testable import Colorbee

/// The color wheel's point and its hue and strength (FR-9.7 item 2, stage 5).
@MainActor
struct ColorWheelTests {
    @Test func theAngleIsTheHueAndTheDistanceTheStrength() {
        let radius: CGFloat = 70
        // Red at the right, yellow-green above, counterclockwise as on a color circle.
        #expect(ColorWheel.wheel(at: CGPoint(x: 140, y: 70), radius: radius, keeping: .init()) == .init(hue: 0, strength: 100))
        #expect(ColorWheel.wheel(at: CGPoint(x: 70, y: 35), radius: radius, keeping: .init(luminance: 20)) == .init(hue: 90, strength: 50, luminance: 20))
        #expect(ColorWheel.wheel(at: CGPoint(x: 400, y: 70), radius: radius, keeping: .init()).strength == 100)
        for wheel in [ColorGrading.Wheel(hue: 30, strength: 60), .init(hue: 200, strength: 25), .init(hue: 315, strength: 90)] {
            #expect(ColorWheel.wheel(at: ColorWheel.point(for: wheel, radius: radius), radius: radius, keeping: wheel) == wheel)
        }
    }
}
