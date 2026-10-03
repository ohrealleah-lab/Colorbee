import Foundation

/// Effects as stored in projects (adjustment layers) and filters: a kind, its numbers, and the settings
/// that aren't plain numbers. Projects from before stage 9 used the same shape.
extension Effect: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, values, levels, curves, photo, color
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(numbers, forKey: .values)
        switch self {
        case .levels(let levels): try container.encode(levels, forKey: .levels)
        case .curves(let curves): try container.encode(curves, forKey: .curves)
        case .photo(let edit): try container.encode(edit, forKey: .photo)
        case .solidFill(let color): try container.encode([color.r, color.g, color.b, color.a], forKey: .color)
        default: break
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        let v = try container.decodeIfPresent([Double].self, forKey: .values) ?? []
        func value(_ i: Int) -> Double { v.indices.contains(i) ? v[i] : 0 }
        switch kind {
        case "invert": self = .invert
        case "desaturate": self = .desaturate
        case "brightnessContrast": self = .brightnessContrast(brightness: value(0), contrast: value(1))
        case "hueSaturation": self = .hueSaturation(hue: value(0), saturation: value(1), lightness: value(2))
        case "gaussianBlur": self = .gaussianBlur(radius: value(0))
        case "sharpen": self = .sharpen(amount: value(0))
        case "pixelate": self = .pixelate(cellSize: Int(value(0)))
        case "levels": self = .levels(try container.decode(Levels.self, forKey: .levels))
        case "curves": self = .curves(try container.decode(Curves.self, forKey: .curves))
        case "sepia": self = .sepia(amount: value(0))
        case "posterize": self = .posterize(levels: Int(value(0)))
        case "addNoise": self = .addNoise(amount: value(0), monochrome: value(1) != 0)
        case "motionBlur": self = .motionBlur(angle: value(0), distance: value(1))
        case "emboss": self = .emboss(angle: value(0), depth: value(1))
        case "vignette": self = .vignette(amount: value(0), size: value(1))
        case "photo": self = .photo(try container.decode(PhotoEdit.self, forKey: .photo))
        case "solidFill":
            let c = try container.decode([UInt8].self, forKey: .color)
            guard c.count == 4 else { throw DecodingError.dataCorruptedError(forKey: .color, in: container, debugDescription: "Needs RGBA") }
            self = .solidFill(Pixel(r: c[0], g: c[1], b: c[2], a: c[3]))
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Unknown effect \(kind)")
        }
    }

    private var kind: String {
        switch self {
        case .gaussianBlur: "gaussianBlur"
        case .pixelate: "pixelate"
        case .solidFill: "solidFill"
        case .invert: "invert"
        case .desaturate: "desaturate"
        case .brightnessContrast: "brightnessContrast"
        case .hueSaturation: "hueSaturation"
        case .sharpen: "sharpen"
        case .levels: "levels"
        case .curves: "curves"
        case .sepia: "sepia"
        case .posterize: "posterize"
        case .addNoise: "addNoise"
        case .motionBlur: "motionBlur"
        case .emboss: "emboss"
        case .vignette: "vignette"
        case .photo: "photo"
        }
    }

    private var numbers: [Double] {
        switch self {
        case .gaussianBlur(let radius): [radius]
        case .pixelate(let size): [Double(size)]
        case .brightnessContrast(let b, let c): [b, c]
        case .hueSaturation(let h, let s, let l): [h, s, l]
        case .sharpen(let amount): [amount]
        case .sepia(let amount): [amount]
        case .posterize(let levels): [Double(levels)]
        case .addNoise(let amount, let monochrome): [amount, monochrome ? 1 : 0]
        case .motionBlur(let angle, let distance): [angle, distance]
        case .emboss(let angle, let depth): [angle, depth]
        case .vignette(let amount, let size): [amount, size]
        case .solidFill, .invert, .desaturate, .levels, .curves, .photo: []
        }
    }
}
