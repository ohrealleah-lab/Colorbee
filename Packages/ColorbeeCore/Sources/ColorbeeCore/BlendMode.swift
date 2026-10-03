import simd

/// How a layer combines with the layers below it (FR-8.2). The math follows the W3C Compositing and
/// Blending spec, in the document's color space. `Shaders.metal` repeats it for the display; keep them in step.
public enum BlendMode: Int, CaseIterable, Sendable {
    case normal
    case darken, multiply, colorBurn
    case lighten, screen, colorDodge, additive
    case overlay, softLight, hardLight
    case difference, exclusion
    case hue, saturation, color, luminosity

    public var name: String {
        switch self {
        case .normal: "Normal"
        case .darken: "Darken"
        case .multiply: "Multiply"
        case .colorBurn: "Color Burn"
        case .lighten: "Lighten"
        case .screen: "Screen"
        case .colorDodge: "Color Dodge"
        case .additive: "Additive"
        case .overlay: "Overlay"
        case .softLight: "Soft Light"
        case .hardLight: "Hard Light"
        case .difference: "Difference"
        case .exclusion: "Exclusion"
        case .hue: "Hue"
        case .saturation: "Saturation"
        case .color: "Color"
        case .luminosity: "Luminosity"
        }
    }

    /// The menu's groups, separated by dividers.
    public static let groups: [[BlendMode]] = [
        [.normal],
        [.darken, .multiply, .colorBurn],
        [.lighten, .screen, .colorDodge, .additive],
        [.overlay, .softLight, .hardLight],
        [.difference, .exclusion],
        [.hue, .saturation, .color, .luminosity],
    ]

    /// The blended color B(backdrop, source), both straight RGB in 0...1.
    public func blend(_ backdrop: SIMD3<Float>, _ source: SIMD3<Float>) -> SIMD3<Float> {
        let b = backdrop, s = source
        switch self {
        case .normal: return s
        case .darken: return simd_min(b, s)
        case .multiply: return b * s
        case .colorBurn: return Self.map(b, s, Self.colorBurn)
        case .lighten: return simd_max(b, s)
        case .screen: return b + s - b * s
        case .colorDodge: return Self.map(b, s, Self.colorDodge)
        case .additive: return simd_min(b + s, SIMD3(repeating: 1))
        case .overlay: return Self.map(b, s) { b, s in Self.hardLight(s, b) }
        case .softLight: return Self.map(b, s, Self.softLight)
        case .hardLight: return Self.map(b, s, Self.hardLight)
        case .difference: return abs(b - s)
        case .exclusion: return b + s - 2 * b * s
        case .hue: return Self.setLum(Self.setSat(s, Self.sat(b)), Self.lum(b))
        case .saturation: return Self.setLum(Self.setSat(b, Self.sat(s)), Self.lum(b))
        case .color: return Self.setLum(s, Self.lum(b))
        case .luminosity: return Self.setLum(b, Self.lum(s))
        }
    }

    // MARK: Separable

    private static func map(_ b: SIMD3<Float>, _ s: SIMD3<Float>, _ f: (Float, Float) -> Float) -> SIMD3<Float> {
        SIMD3(f(b.x, s.x), f(b.y, s.y), f(b.z, s.z))
    }

    private static func colorDodge(_ b: Float, _ s: Float) -> Float {
        if b == 0 { return 0 }
        if s >= 1 { return 1 }
        return min(1, b / (1 - s))
    }

    private static func colorBurn(_ b: Float, _ s: Float) -> Float {
        if b >= 1 { return 1 }
        if s <= 0 { return 0 }
        return 1 - min(1, (1 - b) / s)
    }

    private static func hardLight(_ b: Float, _ s: Float) -> Float {
        s <= 0.5 ? b * 2 * s : screen(b, 2 * s - 1)
    }

    private static func screen(_ b: Float, _ s: Float) -> Float {
        b + s - b * s
    }

    private static func softLight(_ b: Float, _ s: Float) -> Float {
        if s <= 0.5 { return b - (1 - 2 * s) * b * (1 - b) }
        let d = b <= 0.25 ? ((16 * b - 12) * b + 4) * b : b.squareRoot()
        return b + (2 * s - 1) * (d - b)
    }

    // MARK: Non-separable

    private static func lum(_ c: SIMD3<Float>) -> Float {
        0.3 * c.x + 0.59 * c.y + 0.11 * c.z
    }

    private static func clipColor(_ c: SIMD3<Float>) -> SIMD3<Float> {
        let l = lum(c), n = c.min(), x = c.max()
        var c = c
        if n < 0 { c = l + (c - l) * l / (l - n) }
        if x > 1 { c = l + (c - l) * (1 - l) / (x - l) }
        return c
    }

    private static func setLum(_ c: SIMD3<Float>, _ l: Float) -> SIMD3<Float> {
        clipColor(c + (l - lum(c)))
    }

    private static func sat(_ c: SIMD3<Float>) -> Float {
        c.max() - c.min()
    }

    private static func setSat(_ c: SIMD3<Float>, _ s: Float) -> SIMD3<Float> {
        let low = c.min(), high = c.max()
        guard high > low else { return .zero }
        // Scaling around the minimum puts the minimum at 0 and the maximum at `s`; the middle follows.
        return (c - low) * (s / (high - low))
    }
}

extension Compositing {
    /// Composites a straight-alpha source onto a premultiplied backdrop with a blend mode and opacity,
    /// per the W3C formula. Working in premultiplied floats keeps a stack of layers from losing precision.
    @inline(__always)
    static func blend(_ backdrop: inout SIMD4<Float>, _ source: Pixel, opacity: Float, mode: BlendMode) {
        let sourceAlpha = Float(source.a) / 255 * opacity
        guard sourceAlpha > 0 else { return }
        let s = SIMD3(Float(source.r), Float(source.g), Float(source.b)) / 255
        let backdropAlpha = backdrop.w
        let blended: SIMD3<Float>
        if mode == .normal || backdropAlpha <= 0 {
            blended = s
        } else {
            let b = SIMD3(backdrop.x, backdrop.y, backdrop.z) / backdropAlpha
            blended = (1 - backdropAlpha) * s + backdropAlpha * mode.blend(b, s)
        }
        let color = sourceAlpha * blended + (1 - sourceAlpha) * SIMD3(backdrop.x, backdrop.y, backdrop.z)
        backdrop = SIMD4(color, sourceAlpha + backdropAlpha * (1 - sourceAlpha))
    }

    /// A premultiplied float color back to a straight-alpha pixel.
    @inline(__always)
    static func pixel(_ premultiplied: SIMD4<Float>) -> Pixel {
        let alpha = premultiplied.w
        guard alpha > 0 else { return .clear }
        let straight = simd_clamp(SIMD3(premultiplied.x, premultiplied.y, premultiplied.z) / alpha, SIMD3(repeating: 0), SIMD3(repeating: 1))
        func byte(_ v: Float) -> UInt8 { UInt8((v * 255).rounded()) }
        return Pixel(r: byte(straight.x), g: byte(straight.y), b: byte(straight.z), a: byte(min(1, alpha)))
    }

    @inline(__always)
    static func premultiplied(_ pixel: Pixel) -> SIMD4<Float> {
        let alpha = Float(pixel.a) / 255
        return SIMD4(Float(pixel.r) / 255 * alpha, Float(pixel.g) / 255 * alpha, Float(pixel.b) / 255 * alpha, alpha)
    }
}
