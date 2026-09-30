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
}
