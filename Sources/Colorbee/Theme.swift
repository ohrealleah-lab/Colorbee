import AppKit
import SwiftUI

/// Colors from the mockups (Docs/Design), each with a light and a dark version.
enum Theme {
    static let surround = dynamic(light: (0xD3, 0xD3, 0xD7, 1), dark: (0x16, 0x16, 0x18, 1))
    /// The tint behind the selected tool.
    static let accentSoft = Color(nsColor: NSColor(name: nil) { appearance in
        NSColor.controlAccentColor.withAlphaComponent(isDark(appearance) ? 0.26 : 0.14)
    })
    /// Sunken fields: the size box, slider tracks, the percentage.
    static let field = Color(nsColor: dynamic(light: (0, 0, 0, 0.055), dark: (255, 255, 255, 0.08)))
    static let separator = Color(nsColor: dynamic(light: (0, 0, 0, 0.1), dark: (255, 255, 255, 0.1)))
    static let secondaryInk = Color(nsColor: dynamic(light: (0, 0, 0, 0.56), dark: (255, 255, 255, 0.6)))
    static let tertiaryInk = Color(nsColor: dynamic(light: (0, 0, 0, 0.28), dark: (255, 255, 255, 0.3)))

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private static func dynamic(light: (Int, Int, Int, Double), dark: (Int, Int, Int, Double)) -> NSColor {
        NSColor(name: nil) { appearance in
            let c = isDark(appearance) ? dark : light
            return NSColor(srgbRed: CGFloat(c.0) / 255, green: CGFloat(c.1) / 255, blue: CGFloat(c.2) / 255, alpha: c.3)
        }
    }
}
