import Foundation

/// A 3D color table from a .cube file (FR-9.7 item 4). Each color is found between the table's points and blended
/// from the four that surround it (tetrahedral interpolation, which keeps grays gray). It applies to the document's
/// own color values, as Photoshop's Color Lookup does (Q11.2).
public struct ColorLook: Sendable {
    /// Points along each axis.
    public let size: Int
    /// Red, green and blue for each point, 0...65535, red varying fastest, then green, then blue (the .cube order).
    public let values: [UInt16]
    /// How much of the look applies, 0...1: a filter's Intensity.
    public var amount: Double
    /// Worked out once, so hashing a look doesn't read its million numbers each time.
    private let digest: Int

    /// The biggest table Colorbee takes: 129 points a side is about 13 MB, and the biggest looks in use are 65.
    public static let sizes = 2...129

    /// `values` as red, green and blue in 0...1, `size`³ of them in .cube order.
    public init(size: Int, values: [UInt16], amount: Double = 1) {
        precondition(Self.sizes.contains(size) && values.count == size * size * size * 3)
        self.size = size
        self.values = values
        self.amount = amount
        var hasher = Hasher()
        hasher.combine(size)
        values.withUnsafeBytes { hasher.combine(bytes: $0) }
        digest = hasher.finalize()
    }

    /// Each pixel looked up, then mixed with the original by `amount`. Alpha is kept.
    public var transform: (Pixel) -> Pixel {
        let table = values.map { Float($0) / 65535 * 255 }
        let n = size, mix = Float(min(max(amount, 0), 1))
        let scale = Float(n - 1) / 255
        let dg = 3 * n, db = 3 * n * n
        return { pixel in
            let r = Float(pixel.r), g = Float(pixel.g), b = Float(pixel.b)
            let x = r * scale, y = g * scale, z = b * scale
            let i = min(Int(x), n - 2), j = min(Int(y), n - 2), k = min(Int(z), n - 2)
            let fr = x - Float(i), fg = y - Float(j), fb = z - Float(k)
            let base = 3 * i + dg * j + db * k
            // The tetrahedron the color falls in, from which fraction is largest: its four corners and their weights.
            let (o1, o2, w0, w1, w2, w3): (Int, Int, Float, Float, Float, Float)
            if fr > fg {
                if fg > fb { (o1, o2, w0, w1, w2, w3) = (3, 3 + dg, 1 - fr, fr - fg, fg - fb, fb) }
                else if fr > fb { (o1, o2, w0, w1, w2, w3) = (3, 3 + db, 1 - fr, fr - fb, fb - fg, fg) }
                else { (o1, o2, w0, w1, w2, w3) = (db, 3 + db, 1 - fb, fb - fr, fr - fg, fg) }
            } else {
                if fb > fg { (o1, o2, w0, w1, w2, w3) = (db, dg + db, 1 - fb, fb - fg, fg - fr, fr) }
                else if fb > fr { (o1, o2, w0, w1, w2, w3) = (dg, dg + db, 1 - fg, fg - fb, fb - fr, fr) }
                else { (o1, o2, w0, w1, w2, w3) = (dg, 3 + dg, 1 - fg, fg - fr, fr - fb, fb) }
            }
            let o3 = 3 + dg + db
            func channel(_ c: Int, _ original: Float) -> UInt8 {
                let looked = w0 * table[base + c] + w1 * table[base + o1 + c] + w2 * table[base + o2 + c] + w3 * table[base + o3 + c]
                return UInt8(min(max(original + (looked - original) * mix, 0), 255).rounded())
            }
            return Pixel(r: channel(0, r), g: channel(1, g), b: channel(2, b), a: pixel.a)
        }
    }
}

extension ColorLook: Hashable {
    public static func == (a: ColorLook, b: ColorLook) -> Bool {
        a.size == b.size && a.amount == b.amount && a.digest == b.digest && a.values == b.values
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(digest)
        hasher.combine(amount)
    }
}

/// In projects and filter files the table is binary (as base64 in their JSON), about a third the size of text.
extension ColorLook: Codable {
    private enum CodingKeys: String, CodingKey {
        case size, table, amount
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(size, forKey: .size)
        try container.encode(values.withUnsafeBufferPointer { Data(buffer: $0) }, forKey: .table)
        try container.encode(amount, forKey: .amount)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let size = try container.decode(Int.self, forKey: .size)
        let data = try container.decode(Data.self, forKey: .table)
        let amount = try container.decode(Double.self, forKey: .amount)
        guard Self.sizes.contains(size), data.count == size * size * size * 3 * 2, amount.isFinite else {
            throw DecodingError.dataCorruptedError(forKey: .table, in: container, debugDescription: "Damaged look")
        }
        let values = [UInt16](unsafeUninitializedCapacity: data.count / 2) { buffer, count in
            _ = data.copyBytes(to: buffer)
            count = buffer.count
        }
        self.init(size: size, values: values, amount: amount)
    }
}
