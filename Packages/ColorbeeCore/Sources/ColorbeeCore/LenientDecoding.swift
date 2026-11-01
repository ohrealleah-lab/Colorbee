import Foundation

// Reading saved settings leniently (review round 11, AE 8): a value that's missing, damaged, or of a kind this version
// doesn't know reads as nil or its start, so the rest of what holds it still opens. Each type still chooses which of
// its values may be lenient; these make that choice easy to see.

extension KeyedDecodingContainer {
    /// The value under `key`, or nil if it's missing or can't be read.
    func lenient<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }
}

extension Double {
    /// Within `range`; a value that isn't a number reads as `start`.
    func clamped(to range: ClosedRange<Double>, orIfNotFinite start: Double) -> Double {
        isFinite ? Swift.min(Swift.max(self, range.lowerBound), range.upperBound) : start
    }
}

/// An effect that reads back as nil if it's damaged or of a kind this version doesn't know, so the layer or filter
/// holding it keeps the rest.
struct LenientEffect: Codable {
    var effect: Effect?

    init(_ effect: Effect) { self.effect = effect }
    init(from decoder: Decoder) throws { effect = try? Effect(from: decoder) }
    func encode(to encoder: Encoder) throws { try effect?.encode(to: encoder) }
}

/// One item of a list saved as names and numbers one after the other: a damaged item reads as `other`.
enum NameOrNumber: Decodable {
    case name(String), number(Double), other

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let name = try? value.decode(String.self) {
            self = .name(name)
        } else if let number = try? value.decode(Double.self) {
            self = .number(number)
        } else {
            self = .other
        }
    }
}
