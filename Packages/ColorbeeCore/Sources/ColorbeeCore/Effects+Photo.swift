import simd

extension Effects {
    /// Adjust Photo on a region: detail (from the original pixels), then color and tone, then the vignettes (the
    /// filter's, then the panel's own).
    /// Shaders.metal's photo_fragment does the same for adjustment layers on screen.
    static func photoAdjusted(_ buffer: PixelBuffer, region: IntRect, edit: PhotoEdit, selection: SelectionMask?) -> (PixelBuffer, IntPoint) {
        let adjustments = edit.adjustments
        let sharpness = adjustments[.sharpness] / 100, definition = adjustments[.definition] / 100, texture = adjustments[.texture] / 100
        let noiseReduction = adjustments[.noiseReduction] / 100, vignettes = edit.vignetteAmounts
        let fine = sharpness > 0 || noiseReduction > 0 ? blurred(buffer, region: region, sigma: PhotoAdjustments.fineRadius, selection: selection) : nil
        let medium = texture != 0 ? blurred(buffer, region: region, sigma: PhotoAdjustments.textureRadius, selection: selection) : nil
        let wide = definition > 0 ? blurred(buffer, region: region, sigma: PhotoAdjustments.definitionRadius, selection: selection) : nil
        let transform = edit.colorTransform
        let memory = region.width * region.height >= ColorMemory.minimumPixels ? ColorMemory(transform) : nil
        let color = memory.map { memory in { memory($0) } } ?? transform
        let result = PixelBuffer(width: region.width, height: region.height)
        func straight(_ pixel: Pixel) -> SIMD3<Double> { SIMD3(Double(pixel.r), Double(pixel.g), Double(pixel.b)) / 255 }
        ParallelRows.forEach(region.minY..<region.maxY) { rows in
            for y in rows {
                let source = buffer.row(y), target = result.row(y - region.minY)
                let fineRow = fine.map { $0.0.row(y - $0.1.y) }, mediumRow = medium.map { $0.0.row(y - $0.1.y) }
                let wideRow = wide.map { $0.0.row(y - $0.1.y) }
                for x in region.minX..<region.maxX {
                    var pixel = source[x]
                    if fine != nil || medium != nil || wide != nil {
                        let original = straight(pixel)
                        let soft = fineRow.map { straight($0[x - fine!.1.x]) } ?? original
                        let middle = mediumRow.map { straight($0[x - medium!.1.x]) } ?? original
                        let wider = wideRow.map { straight($0[x - wide!.1.x]) } ?? original
                        let detailed = PhotoAdjustments.detail(original, fine: soft, medium: middle, wide: wider, sharpness: sharpness,
                                                               definition: definition, texture: texture, noiseReduction: noiseReduction) * 255
                        pixel = Pixel(r: UInt8(detailed.x.rounded()), g: UInt8(detailed.y.rounded()), b: UInt8(detailed.z.rounded()), a: pixel.a)
                    }
                    pixel = color(pixel)
                    if !vignettes.isEmpty {
                        let strength = Vignette.strength(x: x, y: y, in: region, size: 50)
                        for amount in vignettes { pixel = Vignette.apply(strength * amount / 100, to: pixel) }
                    }
                    target[x - region.minX] = pixel
                }
            }
        }
        return (result, IntPoint(x: region.minX, y: region.minY))
    }
}
