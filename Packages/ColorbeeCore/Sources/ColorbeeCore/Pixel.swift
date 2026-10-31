/// One stored pixel. Field order is the in-memory byte order (BGRA8), and alpha is straight, not premultiplied.
public struct Pixel: Hashable, Sendable {
    public var b: UInt8
    public var g: UInt8
    public var r: UInt8
    public var a: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        self.b = b
        self.g = g
        self.r = r
        self.a = a
    }

    public static let black = Pixel(r: 0, g: 0, b: 0)
    public static let white = Pixel(r: 255, g: 255, b: 255)
    public static let clear = Pixel(r: 0, g: 0, b: 0, a: 0)
}

extension Pixel {
    /// The gray a mask uses for this color (Q28.3): its brightness, at the same opacity.
    public var maskGray: Pixel {
        let red: Double = 0.2126 * Double(r), green: Double = 0.7152 * Double(g), blue: Double = 0.0722 * Double(b)
        let gray = UInt8((red + green + blue).rounded())
        return Pixel(r: gray, g: gray, b: gray, a: a)
    }
}
