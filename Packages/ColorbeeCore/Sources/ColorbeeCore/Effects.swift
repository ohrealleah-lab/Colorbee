import Accelerate

public enum Effect: Sendable, Equatable {
    /// Gaussian blur; `radius` is the standard deviation in pixels (1...100).
    case gaussianBlur(radius: Double)
    /// Square mosaic blocks of `cellSize` pixels (2...100), aligned to the canvas.
    case pixelate(cellSize: Int)

    public var name: String {
        switch self {
        case .gaussianBlur: "Gaussian Blur"
        case .pixelate: "Pixelate"
        }
    }
}

public enum Effects {
    /// Applies `effect` to the selected pixels of `layer`, or to the whole layer without a selection.
    /// Each separate region of the selection is processed from its own pixels, so blur never bleeds between regions.
    @discardableResult
    public static func apply(_ effect: Effect, to layer: Layer, selection: SelectionMask?, edit: Edit) -> IntRect {
        guard let selection else { return applyToRegion(effect, layer: layer, selection: nil, edit: edit) }
        return selection.connectedRegions().reduce(IntRect.zero) { changed, region in
            changed.union(applyToRegion(effect, layer: layer, selection: region, edit: edit))
        }
    }

    private static func applyToRegion(_ effect: Effect, layer: Layer, selection: SelectionMask?, edit: Edit) -> IntRect {
        let region = (selection?.bounds ?? layer.buffer.bounds).intersection(layer.buffer.bounds)
        guard !region.isEmpty else { return .zero }
        let result: PixelBuffer
        let origin: IntPoint
        switch effect {
        case .gaussianBlur(let radius):
            (result, origin) = blurred(layer.buffer, region: region, sigma: radius, selection: selection)
        case .pixelate(let cellSize):
            (result, origin) = pixelated(layer.buffer, region: region, cellSize: max(2, cellSize), selection: selection)
        }
        edit.willModify(region, in: layer)
        for y in region.minY..<region.maxY {
            let source = result.row(y - origin.y)
            let destination = layer.buffer.row(y)
            for x in region.minX..<region.maxX where (selection?[x, y] ?? 255) > 0 {
                destination[x] = source[x - origin.x]
            }
        }
        return region
    }

    /// Blurs `region` plus a margin. Unselected pixels are left out of the sampling, so the blur of
    /// one region never picks up color from outside the selection.
    private static func blurred(_ buffer: PixelBuffer, region: IntRect, sigma: Double, selection: SelectionMask?) -> (PixelBuffer, IntPoint) {
        // Three box blurs approximate a Gaussian; each box is about 2σ wide.
        let boxWidth = max(1, Int((12 * sigma * sigma / 3 + 1).squareRoot().rounded()) | 1)
        let margin = 3 * (boxWidth / 2) + 1
        let work = IntRect(x: region.minX - margin, y: region.minY - margin, width: region.width + 2 * margin, height: region.height + 2 * margin)
            .intersection(buffer.bounds)
        let scratch = PixelBuffer(width: work.width, height: work.height)
        for y in work.minY..<work.maxY {
            let source = buffer.row(y)
            let destination = scratch.row(y - work.minY)
            for x in work.minX..<work.maxX where (selection?[x, y] ?? 255) > 0 {
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
                for x in work.minX..<work.maxX where selection[x, y] > 0 {
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

    private static func pixelated(_ buffer: PixelBuffer, region: IntRect, cellSize: Int, selection: SelectionMask?) -> (PixelBuffer, IntPoint) {
        let result = PixelBuffer(width: region.width, height: region.height)
        var cellY = region.minY / cellSize * cellSize
        while cellY < region.maxY {
            var cellX = region.minX / cellSize * cellSize
            while cellX < region.maxX {
                let cell = IntRect(x: cellX, y: cellY, width: cellSize, height: cellSize).intersection(region)
                let average = averageColor(of: buffer, in: cell, selection: selection)
                for y in cell.minY..<cell.maxY {
                    (result.row(y - region.minY) + (cell.minX - region.minX)).update(repeating: average, count: cell.width)
                }
                cellX += cellSize
            }
            cellY += cellSize
        }
        return (result, IntPoint(x: region.minX, y: region.minY))
    }

    /// Alpha-weighted average of the selected pixels in `rect`.
    private static func averageColor(of buffer: PixelBuffer, in rect: IntRect, selection: SelectionMask?) -> Pixel {
        var red = 0.0, green = 0.0, blue = 0.0, alpha = 0.0, count = 0.0
        for y in rect.minY..<rect.maxY {
            let row = buffer.row(y)
            for x in rect.minX..<rect.maxX where (selection?[x, y] ?? 255) > 0 {
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
