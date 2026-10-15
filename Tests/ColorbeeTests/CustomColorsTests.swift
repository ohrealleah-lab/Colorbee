import ColorbeeCore
import Testing
@testable import Colorbee

/// The 4 custom-color slots (FR-1.2), read from what was saved. Nothing here saves preferences.
@MainActor
struct CustomColorsTests {
    private let red = Int(0xFF00_00FF), green = Int(0x00FF_00FF), blue = Int(0x0000_FFFF), gray = Int(0x8080_80FF)

    /// Twelve slots saved before keep their last 4 colors, which filled in latest, in order.
    @Test func twelveSavedSlotsKeepTheLastFourColors() {
        let saved = [red, -1, green, gray, -1, blue, red + 0x100, -1, -1, -1, -1, -1]
        let slots = CustomColors.unpacked(saved)
        #expect(slots.count == 4)
        #expect(slots.map { $0.map { Int($0.r) } } == [0x00, 0x80, 0x00, 0xFF])
        #expect(slots[3]?.b == 0x01)
    }

    /// Four saved slots keep their places, gaps included.
    @Test func fourSavedSlotsKeepTheirPlaces() {
        let slots = CustomColors.unpacked([-1, red, -1, blue])
        #expect(slots[0] == nil && slots[2] == nil)
        #expect(slots[1]?.r == 0xFF && slots[3]?.b == 0xFF)
    }

    /// Fewer colors than slots leave the rest empty, and numbers out of range are empty slots.
    @Test func shortOrBadListsLeaveSlotsEmpty() {
        #expect(CustomColors.unpacked([]).allSatisfy { $0 == nil })
        let slots = CustomColors.unpacked([red, Int(UInt32.max) + 1])
        #expect(slots[0]?.r == 0xFF && slots[1] == nil && slots.count == 4)
    }
}
