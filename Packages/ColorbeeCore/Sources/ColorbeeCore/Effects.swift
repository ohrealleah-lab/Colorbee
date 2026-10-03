import Accelerate

public enum Effect: Sendable, Hashable {
    /// Gaussian blur; `radius` is the standard deviation in pixels (1...100).
    case gaussianBlur(radius: Double)
    /// Square mosaic blocks of `cellSize` pixels (2...100), aligned to the canvas.
    case pixelate(cellSize: Int)
    /// Every selected pixel becomes this color (redaction).
    case solidFill(Pixel)
    case invert
    /// Grayscale by luminance.
    case desaturate
    /// Brightness and contrast, each -100...100.
    case brightnessContrast(brightness: Double, contrast: Double)
    /// Hue shift in degrees (-180...180); saturation and lightness -100...100.
    case hueSaturation(hue: Double, saturation: Double, lightness: Double)
    /// Unsharp mask; `amount` 0...200 percent.
    case sharpen(amount: Double)
    case levels(Levels)
    case curves(Curves)
    /// Warm brown tones; `amount` 0...100 percent.
    case sepia(amount: Double)
    /// Each channel reduced to 2...32 evenly spaced values.
    case posterize(levels: Int)
    /// Grain; `amount` 0...100 percent. The same pixel always gets the same grain, so previews match the result.
    case addNoise(amount: Double, monochrome: Bool)
    /// Streaks along `angle` degrees (counterclockwise from the right), `distance` 1...200 pixels long.
    case motionBlur(angle: Double, distance: Double)
    /// A gray relief lit from `angle` degrees; `depth` 1...10.
    case emboss(angle: Double, depth: Double)
    /// Darkens (positive `amount`) or lightens (negative) toward the edges, -100...100; `size` 0...100 is how
    /// much of the middle stays untouched.
    case vignette(amount: Double, size: Double)
    /// The Adjust Photo panel: a filter, then the sliders (FR-9.5).
    case photo(PhotoEdit)

    public var name: String {
        switch self {
        case .gaussianBlur: "Gaussian Blur"
        case .pixelate: "Pixelate"
        case .solidFill: "Solid Fill"
        case .invert: "Invert Colors"
        case .desaturate: "Desaturate"
        case .brightnessContrast: "Brightness/Contrast"
        case .hueSaturation: "Hue/Saturation"
        case .sharpen: "Sharpen"
        case .levels: "Levels"
        case .curves: "Curves"
        case .sepia: "Sepia"
        case .posterize: "Posterize"
        case .addNoise: "Add Noise"
        case .motionBlur: "Motion Blur"
        case .emboss: "Emboss"
        case .vignette: "Vignette"
        case .photo: "Adjust Photo"
        }
    }

    /// Color adjustments the display shows through a `ColorLookup` table.
    public var usesColorLookup: Bool {
        switch self {
        case .levels, .curves, .sepia, .posterize, .photo: true
        default: false
        }
    }

    /// The per-pixel color part: the whole effect for point adjustments; for Adjust Photo, everything but
    /// its detail sliders and vignette.
    public var colorTransform: ((Pixel) -> Pixel)? {
        if case .photo(let edit) = self { return edit.colorTransform }
        return pointwise
    }

    /// The per-pixel function for effects that don't look at neighbors.
    var pointwise: ((Pixel) -> Pixel)? {
        switch self {
        case .solidFill(let color):
            return { _ in color }
        case .invert:
            return { Pixel(r: 255 - $0.r, g: 255 - $0.g, b: 255 - $0.b, a: $0.a) }
        case .desaturate:
            return { pixel in
                let red = 0.2126 * Double(pixel.r)
                let green = 0.7152 * Double(pixel.g)
                let blue = 0.0722 * Double(pixel.b)
                let luminance = UInt8((red + green + blue).rounded())
                return Pixel(r: luminance, g: luminance, b: luminance, a: pixel.a)
            }
        case .brightnessContrast(let brightness, let contrast):
            let factor = 1 + contrast / 100
            let offset = brightness * 2.55
            return { pixel in
                func adjust(_ value: UInt8) -> UInt8 {
                    UInt8(min(255, max(0, ((Double(value) - 128) * factor + 128 + offset).rounded())))
                }
                return Pixel(r: adjust(pixel.r), g: adjust(pixel.g), b: adjust(pixel.b), a: pixel.a)
            }
        case .hueSaturation(let hue, let saturation, let lightness):
            return { pixel in HSL(pixel).adjusted(hue: hue, saturation: saturation, lightness: lightness).pixel(alpha: pixel.a) }
        case .levels(let levels):
            let table = levels.table
            return { Pixel(r: table[Int($0.r)], g: table[Int($0.g)], b: table[Int($0.b)], a: $0.a) }
        case .curves(let curves):
            let tables = curves.tables
            return { Pixel(r: tables.red[Int($0.r)], g: tables.green[Int($0.g)], b: tables.blue[Int($0.b)], a: $0.a) }
        case .sepia(let amount):
            let mix = min(max(amount, 0), 100) / 100
            return { pixel in
                let r = Double(pixel.r), g = Double(pixel.g), b = Double(pixel.b)
                func channel(_ original: Double, _ toned: Double) -> UInt8 {
                    UInt8(min(255, max(0, (original + (toned - original) * mix).rounded())))
                }
                return Pixel(r: channel(r, 0.393 * r + 0.769 * g + 0.189 * b),
                             g: channel(g, 0.349 * r + 0.686 * g + 0.168 * b),
                             b: channel(b, 0.272 * r + 0.534 * g + 0.131 * b), a: pixel.a)
            }
        case .posterize(let levels):
            let steps = Double(min(max(levels, 2), 32) - 1)
            let table = (0..<256).map { UInt8(((Double($0) / 255 * steps).rounded() / steps * 255).rounded()) }
            return { Pixel(r: table[Int($0.r)], g: table[Int($0.g)], b: table[Int($0.b)], a: $0.a) }
        case .gaussianBlur, .pixelate, .sharpen, .addNoise, .motionBlur, .emboss, .vignette, .photo:
            return nil
        }
    }
}

public enum Effects {
    /// Applies `effect` to the selected pixels of `layer`, or to the whole layer without a selection.
    /// Each separate region of the selection is processed from its own pixels, so blur never bleeds between regions.
    @discardableResult
    public static func apply(_ effect: Effect, to layer: Layer, selection: SelectionMask?, edit: Edit) -> IntRect {
        guard let selection else { return applyToRegion(effect, layer: layer, selection: nil, edit: edit) }
        return apply(effect, to: layer, regions: selection.connectedRegions(), edit: edit)
    }

    /// Applies `effect` to each region separately. Pass regions from `SelectionMask.connectedRegions()`;
    /// callers that apply repeatedly (live previews) should compute them once.
    @discardableResult
    public static func apply(_ effect: Effect, to layer: Layer, regions: [SelectionMask], edit: Edit) -> IntRect {
        regions.reduce(IntRect.zero) { changed, region in
            changed.union(applyToRegion(effect, layer: layer, selection: region, edit: edit))
        }
    }

    private static func applyToRegion(_ effect: Effect, layer: Layer, selection: SelectionMask?, edit: Edit) -> IntRect {
        let region = (selection?.bounds ?? layer.buffer.bounds).intersection(layer.buffer.bounds)
        guard !region.isEmpty else { return .zero }
        if let transform = effect.pointwise {
            edit.willModify(region, in: layer)
            ParallelRows.forEach(region.minY..<region.maxY) { rows in
                for y in rows {
                    let row = layer.buffer.row(y)
                    for x in region.minX..<region.maxX where isSelected(selection, x, y) {
                        row[x] = transform(row[x])
                    }
                }
            }
            return region
        }
        let result: PixelBuffer
        let origin: IntPoint
        switch effect {
        case .gaussianBlur(let radius):
            (result, origin) = blurred(layer.buffer, region: region, sigma: radius, selection: selection)
        case .pixelate(let cellSize):
            (result, origin) = pixelated(layer.buffer, region: region, cellSize: max(2, cellSize), selection: selection)
        case .sharpen(let amount):
            (result, origin) = sharpened(layer.buffer, region: region, amount: amount / 100, selection: selection)
        case .addNoise(let amount, let monochrome):
            (result, origin) = noisy(layer.buffer, region: region, amount: amount, monochrome: monochrome)
        case .motionBlur(let angle, let distance):
            (result, origin) = motionBlurred(layer.buffer, region: region, angle: angle, distance: distance, selection: selection)
        case .emboss(let angle, let depth):
            (result, origin) = embossed(layer.buffer, region: region, angle: angle, depth: depth)
        case .vignette(let amount, let size):
            (result, origin) = vignetted(layer.buffer, region: region, amount: amount, size: size)
        case .photo(let edit):
            (result, origin) = photoAdjusted(layer.buffer, region: region, edit: edit, selection: selection)
        case .solidFill, .invert, .desaturate, .brightnessContrast, .hueSaturation, .levels, .curves, .sepia, .posterize:
            return .zero
        }
        edit.willModify(region, in: layer)
        for y in region.minY..<region.maxY {
            let source = result.row(y - origin.y)
            let destination = layer.buffer.row(y)
            for x in region.minX..<region.maxX where isSelected(selection, x, y) {
                destination[x] = source[x - origin.x]
            }
        }
        return region
    }

    /// Blurs `region` plus a margin. Unselected pixels are left out of the sampling, so the blur of
    /// one region never picks up color from outside the selection.
    static func blurred(_ buffer: PixelBuffer, region: IntRect, sigma: Double, selection: SelectionMask?) -> (PixelBuffer, IntPoint) {
        // Three box blurs approximate a Gaussian; each box is about 2σ wide.
        let boxWidth = max(1, Int((12 * sigma * sigma / 3 + 1).squareRoot().rounded()) | 1)
        let margin = 3 * (boxWidth / 2) + 1
        let work = IntRect(x: region.minX - margin, y: region.minY - margin, width: region.width + 2 * margin, height: region.height + 2 * margin)
            .intersection(buffer.bounds)
        let scratch = PixelBuffer(width: work.width, height: work.height)
        for y in work.minY..<work.maxY {
            let source = buffer.row(y)
            let destination = scratch.row(y - work.minY)
            for x in work.minX..<work.maxX where isSelected(selection, x, y) {
                destination[x - work.minX] = source[x]
            }
        }
        let result = boxBlurred(scratch, boxWidth: boxWidth)
        if let selection {
            // Unselected pixels were left out as transparent; divide by how much of each pixel's
            // neighborhood was selected so edge pixels keep their real opacity.
            let coverage = PixelBuffer(width: work.width, height: work.height)
            for y in work.minY..<work.maxY {
                let row = coverage.row(y - work.minY)
                for x in work.minX..<work.maxX where isSelected(selection, x, y) {
                    row[x - work.minX] = .white
                }
            }
            let blurredCoverage = boxBlurred(coverage, boxWidth: boxWidth)
            for y in 0..<work.height {
                let pixels = result.row(y)
                let weights = blurredCoverage.row(y)
                for x in 0..<work.width where weights[x].a > 0 {
                    let alpha = Double(pixels[x].a) * 255 / Double(weights[x].a)
                    pixels[x].a = UInt8(min(255, alpha.rounded()))
                }
            }
        }
        return (result, IntPoint(x: work.minX, y: work.minY))
    }

    /// Unsharp mask: push each pixel away from a slightly blurred copy of itself.
    private static func sharpened(_ buffer: PixelBuffer, region: IntRect, amount: Double, selection: SelectionMask?) -> (PixelBuffer, IntPoint) {
        let (blurred, origin) = blurred(buffer, region: region, sigma: 1, selection: selection)
        let result = PixelBuffer(width: blurred.width, height: blurred.height)
        for y in 0..<blurred.height {
            let sourceRow = buffer.row(y + origin.y)
            let softRow = blurred.row(y)
            let destination = result.row(y)
            for x in 0..<blurred.width {
                let original = sourceRow[x + origin.x], soft = softRow[x]
                func boost(_ value: UInt8, _ blurredValue: UInt8) -> UInt8 {
                    UInt8(min(255, max(0, (Double(value) + amount * (Double(value) - Double(blurredValue))).rounded())))
                }
                destination[x] = Pixel(r: boost(original.r, soft.r), g: boost(original.g, soft.g), b: boost(original.b, soft.b), a: original.a)
            }
        }
        return (result, origin)
    }

    /// Three passes of a premultiplied box blur.
    private static func boxBlurred(_ source: PixelBuffer, boxWidth: Int) -> PixelBuffer {
        let first = source.copy()
        let second = PixelBuffer(width: source.width, height: source.height)
        var image = first.vImageBuffer
        var other = second.vImageBuffer
        vImagePremultiplyData_RGBA8888(&image, &image, vImage_Flags(kvImageNoFlags))
        let size = UInt32(boxWidth)
        for _ in 0..<3 {
            vImageBoxConvolve_ARGB8888(&image, &other, nil, 0, 0, size, size, nil, vImage_Flags(kvImageEdgeExtend))
            swap(&image, &other)
        }
        vImageUnpremultiplyData_RGBA8888(&image, &image, vImage_Flags(kvImageNoFlags))
        // Three swaps leave the result in the second buffer.
        return second
    }

    /// Whether a pixel is selected; no selection means everything is. Reads the mask's storage directly.
    @inline(__always)
    static func isSelected(_ selection: SelectionMask?, _ x: Int, _ y: Int) -> Bool {
        guard let selection else { return true }
        let bounds = selection.bounds
        guard x >= bounds.minX, x < bounds.maxX, y >= bounds.minY, y < bounds.maxY else { return false }
        return selection.values.withUnsafeBufferPointer { $0[(y - bounds.minY) * bounds.width + (x - bounds.minX)] } > 0
    }

    private static func pixelated(_ buffer: PixelBuffer, region: IntRect, cellSize: Int, selection: SelectionMask?) -> (PixelBuffer, IntPoint) {
        let result = PixelBuffer(width: region.width, height: region.height)
        let firstCellY = region.minY / cellSize * cellSize
        let cellRows = (region.maxY - firstCellY + cellSize - 1) / cellSize
        // Rows of cells are independent, so they run on all cores.
        ParallelRows.forEach(0..<cellRows, minimumRows: 1) { band in
            for cellRow in band {
                let cellY = firstCellY + cellRow * cellSize
                var cellX = region.minX / cellSize * cellSize
                while cellX < region.maxX {
                    let cell = IntRect(x: cellX, y: cellY, width: cellSize, height: cellSize).intersection(region)
                    let average = averageColor(of: buffer, in: cell, selection: selection)
                    for y in cell.minY..<cell.maxY {
                        (result.row(y - region.minY) + (cell.minX - region.minX)).update(repeating: average, count: cell.width)
                    }
                    cellX += cellSize
                }
            }
        }
        return (result, IntPoint(x: region.minX, y: region.minY))
    }

    /// Alpha-weighted average of the selected pixels in `rect`.
    private static func averageColor(of buffer: PixelBuffer, in rect: IntRect, selection: SelectionMask?) -> Pixel {
        var red = 0.0, green = 0.0, blue = 0.0, alpha = 0.0, count = 0.0
        for y in rect.minY..<rect.maxY {
            let row = buffer.row(y)
            for x in rect.minX..<rect.maxX where isSelected(selection, x, y) {
                let pixel = row[x]
                let weight = Double(pixel.a)
                red += Double(pixel.r) * weight
                green += Double(pixel.g) * weight
                blue += Double(pixel.b) * weight
                alpha += weight
                count += 1
            }
        }
        guard count > 0, alpha > 0 else { return .clear }
        return Pixel(
            r: UInt8((red / alpha).rounded()),
            g: UInt8((green / alpha).rounded()),
            b: UInt8((blue / alpha).rounded()),
            a: UInt8((alpha / count).rounded())
        )
    }
}

/// Hue (0...360), saturation and lightness (0...1).
struct HSL {
    var hue: Double
    var saturation: Double
    var lightness: Double

    init(_ pixel: Pixel) {
        let r = Double(pixel.r) / 255, g = Double(pixel.g) / 255, b = Double(pixel.b) / 255
        let high = max(r, g, b), low = min(r, g, b)
        lightness = (high + low) / 2
        let chroma = high - low
        guard chroma > 0 else {
            hue = 0
            saturation = 0
            return
        }
        saturation = chroma / (1 - abs(2 * lightness - 1))
        switch high {
        case r: hue = 60 * ((g - b) / chroma).truncatingRemainder(dividingBy: 6)
        case g: hue = 60 * ((b - r) / chroma + 2)
        default: hue = 60 * ((r - g) / chroma + 4)
        }
        if hue < 0 { hue += 360 }
    }

    /// Hue shifts by degrees; saturation and lightness move toward their limits by percent.
    func adjusted(hue shift: Double, saturation saturationChange: Double, lightness lightnessChange: Double) -> HSL {
        var result = self
        result.hue = (hue + shift).truncatingRemainder(dividingBy: 360)
        if result.hue < 0 { result.hue += 360 }
        let s = saturationChange / 100, l = lightnessChange / 100
        result.saturation = s >= 0 ? saturation + (1 - saturation) * s : saturation * (1 + s)
        result.lightness = l >= 0 ? lightness + (1 - lightness) * l : lightness * (1 + l)
        return result
    }

    func pixel(alpha: UInt8) -> Pixel {
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let section = hue / 60
        let second = chroma * (1 - abs(section.truncatingRemainder(dividingBy: 2) - 1))
        let (r, g, b): (Double, Double, Double) = switch section {
        case ..<1: (chroma, second, 0)
        case ..<2: (second, chroma, 0)
        case ..<3: (0, chroma, second)
        case ..<4: (0, second, chroma)
        case ..<5: (second, 0, chroma)
        default: (chroma, 0, second)
        }
        let match = lightness - chroma / 2
        func byte(_ value: Double) -> UInt8 { UInt8(min(255, max(0, ((value + match) * 255).rounded()))) }
        return Pixel(r: byte(r), g: byte(g), b: byte(b), a: alpha)
    }
}
