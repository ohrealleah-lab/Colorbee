import AppKit
import ColorbeeCore

extension Pixel {
    init(_ color: NSColor, in colorSpace: CGColorSpace) {
        let converted = NSColorSpace(cgColorSpace: colorSpace).flatMap { color.usingColorSpace($0) } ?? color
        func byte(_ value: CGFloat) -> UInt8 { UInt8((min(max(value, 0), 1) * 255).rounded()) }
        self.init(
            r: byte(converted.redComponent),
            g: byte(converted.greenComponent),
            b: byte(converted.blueComponent),
            a: byte(converted.alphaComponent)
        )
    }

    func nsColor(in colorSpace: CGColorSpace) -> NSColor {
        let components = [r, g, b, a].map { CGFloat($0) / 255 }
        guard let space = NSColorSpace(cgColorSpace: colorSpace) else {
            return NSColor(srgbRed: components[0], green: components[1], blue: components[2], alpha: components[3])
        }
        return NSColor(colorSpace: space, components: components, count: 4)
    }

    /// How VoiceOver says a color: the name macOS gives it, its sRGB hex value, and its opacity when not solid.
    func spokenDescription(in colorSpace: CGColorSpace) -> String {
        let color = nsColor(in: colorSpace).usingColorSpace(.sRGB) ?? nsColor(in: colorSpace)
        func byte(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        let name = color.withAlphaComponent(1).accessibilityName
        let hex = String(format: "#%02X%02X%02X", byte(color.redComponent), byte(color.greenComponent), byte(color.blueComponent))
        guard a < 255 else { return "\(name), \(hex)" }
        return "\(name), \(hex), \(Int((Double(a) / 255 * 100).rounded()))% opaque"
    }
}

extension Thumbnail {
    /// The History and Pages panels' picture of it, in `colorSpace`.
    func nsImage(in colorSpace: CGColorSpace) -> NSImage? {
        let buffer = PixelBuffer(width: width, height: height)
        buffer.setPixels(pixels, in: buffer.bounds)
        guard let cgImage = try? ImageCodec.makeCGImage(buffer, colorSpace: colorSpace) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }
}
