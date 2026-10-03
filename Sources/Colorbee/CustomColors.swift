import ColorbeeCore
import Foundation
import Observation

/// The 12 custom-color slots in the palette bar (FR-1.2), shared by every window and kept between launches.
@MainActor
@Observable
final class CustomColors {
    static let shared = CustomColors()
    static let slotCount = 12
    private static let key = "CustomColors"

    private(set) var slots: [Pixel?]
    /// Filled slots, oldest first, so a new color replaces the oldest when all are full.
    @ObservationIgnored private var order: [Int]

    private init() {
        let stored = UserDefaults.standard.array(forKey: Self.key) as? [Int] ?? []
        let loaded: [Pixel?] = (0..<Self.slotCount).map { index in
            guard stored.indices.contains(index), stored[index] >= 0 else { return nil }
            let v = UInt32(stored[index])
            return Pixel(r: UInt8(v >> 24 & 0xFF), g: UInt8(v >> 16 & 0xFF), b: UInt8(v >> 8 & 0xFF), a: UInt8(v & 0xFF))
        }
        slots = loaded
        order = loaded.indices.filter { loaded[$0] != nil }
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

    func remove(at index: Int) {
        guard slots.indices.contains(index) else { return }
        slots[index] = nil
        order.removeAll { $0 == index }
        save()
    }

    private func save() {
        let packed = slots.map { pixel -> Int in
            guard let p = pixel else { return -1 }
            return Int(UInt32(p.r) << 24 | UInt32(p.g) << 16 | UInt32(p.b) << 8 | UInt32(p.a))
        }
        UserDefaults.standard.set(packed, forKey: Self.key)
    }
}
