import ColorbeeCore
import Foundation
import Observation

/// The 4 custom-color slots in the palette bar (FR-1.2), shared by every window and kept between launches.
@MainActor
@Observable
final class CustomColors {
    static let shared = CustomColors()
    static let slotCount = 4
    private static let key = "CustomColors"

    private(set) var slots: [Pixel?]
    /// Filled slots, oldest first, so a new color replaces the oldest when all are full.
    @ObservationIgnored private var order: [Int]

    private init() {
        let loaded = Self.unpacked(UserDefaults.standard.array(forKey: Self.key) as? [Int] ?? [])
        slots = loaded
        order = loaded.indices.filter { loaded[$0] != nil }
    }

    /// The slots from packed numbers. There used to be 12 slots: from an older list, the last 4 colors are kept, since
    /// colors fill the slots from the left (Leah, 2026-10-15).
    static func unpacked(_ packed: [Int]) -> [Pixel?] {
        if packed.count <= slotCount {
            return (0..<slotCount).map { packed.indices.contains($0) ? pixel(packed[$0]) : nil }
        }
        let colors = Array(packed.compactMap(pixel).suffix(slotCount))
        return (0..<slotCount).map { colors.indices.contains($0) ? colors[$0] : nil }
    }

    /// A packed RGBA number as a color. A palette file can hold any number; out of range means an empty slot
    /// (review J, finding 21).
    private static func pixel(_ value: Int) -> Pixel? {
        guard (0...Int(UInt32.max)).contains(value) else { return nil }
        let v = UInt32(value)
        return Pixel(r: UInt8(v >> 24 & 0xFF), g: UInt8(v >> 16 & 0xFF), b: UInt8(v >> 8 & 0xFF), a: UInt8(v & 0xFF))
    }

    /// Puts a color in the next empty slot, or over the oldest one. A color already there isn't added twice.
    func add(_ color: Pixel) {
        guard !slots.contains(color) else { return }
        let index = slots.firstIndex(where: { $0 == nil }) ?? order.removeFirst()
        slots[index] = color
        order.removeAll { $0 == index }
        order.append(index)
        save()
    }

    /// Puts a color in a particular slot (a double-clicked empty one).
    func set(_ color: Pixel, at index: Int) {
        guard slots.indices.contains(index) else { return }
        slots[index] = color
        order.removeAll { $0 == index }
        order.append(index)
        save()
    }

    /// The slots packed as RGBA numbers, -1 for an empty slot, for saving in a palette.
    var packed: [Int] {
        slots.map { pixel in pixel.map { Int(UInt32($0.r) << 24 | UInt32($0.g) << 16 | UInt32($0.b) << 8 | UInt32($0.a)) } ?? -1 }
    }

    /// Replaces every slot, as when a palette is loaded.
    func replace(with packed: [Int]) {
        slots = Self.unpacked(packed)
        order = slots.indices.filter { slots[$0] != nil }
        save()
    }

    func remove(at index: Int) {
        guard slots.indices.contains(index) else { return }
        slots[index] = nil
        order.removeAll { $0 == index }
        save()
    }

    private func save() {
        UserDefaults.standard.set(packed, forKey: Self.key)
    }
}
