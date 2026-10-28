import simd

extension Effects {
    /// Adjust Photo on a region: detail (from the original pixels), then color and tone, then the vignettes and then
    /// the grain (the filter's, then the panel's own).
    /// Shaders.metal's photo_fragment does the same for adjustment layers on screen.
    /// With `placement`, `buffer` is a patch of a bigger canvas, and the vignette and grain are placed by the whole.
    static func photoAdjusted(_ buffer: PixelBuffer, region: IntRect, edit: PhotoEdit, selection: SelectionMask?,
                              placement: Placement? = nil) -> (PixelBuffer, IntPoint) {
        let amounts = DetailAmounts(edit), vignettes = edit.vignettes, grains = edit.grains
        func blur(_ needed: Bool, _ sigma: Double) -> (PixelBuffer, IntPoint)? {
            needed ? blurred(buffer, region: region, sigma: sigma, selection: selection) : nil
        }
        let fine = blur(amounts.needsFine, PhotoAdjustments.fineRadius)
        let sharp = blur(amounts.needsSharpenBlur, amounts.radius) ?? fine
        let medium = blur(amounts.needsMedium, PhotoAdjustments.textureRadius)
        let wide = blur(amounts.needsWide, PhotoAdjustments.definitionRadius)
        let transform = edit.colorTransform
        let memory = region.width * region.height >= ColorMemory.minimumPixels ? ColorMemory(transform) : nil
        let color = memory.map { memory in { memory($0) } } ?? transform
        let result = PixelBuffer(width: region.width, height: region.height)
        func straight(_ pixel: Pixel) -> SIMD3<Double> { SIMD3(Double(pixel.r), Double(pixel.g), Double(pixel.b)) / 255 }
        ParallelRows.forEach(region.minY..<region.maxY) { rows in
            for y in rows {
                let source = buffer.row(y), target = result.row(y - region.minY)
                func row(_ copy: (PixelBuffer, IntPoint)?) -> (UnsafeMutablePointer<Pixel>, Int)? {
                    copy.map { ($0.0.row(y - $0.1.y), $0.1.x) }
                }
                let fineRow = row(fine), sharpRow = row(sharp), mediumRow = row(medium), wideRow = row(wide)
                for x in region.minX..<region.maxX {
                    var pixel = source[x]
                    if amounts.isNeeded {
                        let original = straight(pixel)
                        func read(_ row: (UnsafeMutablePointer<Pixel>, Int)?) -> SIMD3<Double> {
                            row.map { straight($0.0[x - $0.1]) } ?? original
                        }
                        let detailed = PhotoAdjustments.detail(original, fine: read(fineRow), sharp: read(sharpRow), medium: read(mediumRow),
                                                               wide: read(wideRow), amounts) * 255
                        pixel = Pixel(r: UInt8(detailed.x.rounded()), g: UInt8(detailed.y.rounded()), b: UInt8(detailed.z.rounded()), a: pixel.a)
                        // The mask view shows the mask alone, not the photo's colors.
                        if amounts.showsMask {
                            target[x - region.minX] = pixel
                            continue
                        }
                    }
                    pixel = color(pixel)
                    let (px, py) = (x + (placement?.origin.x ?? 0), y + (placement?.origin.y ?? 0))
                    for vignette in vignettes {
                        let strength = Vignette.strength(x: px, y: py, in: placement?.canvas ?? region, shape: vignette)
                        pixel = Vignette.apply(strength * vignette.amount / 100, to: pixel)
                    }
                    for grain in grains { pixel = grain.apply(to: pixel, x: px, y: py) }
                    target[x - region.minX] = pixel
                }
            }
        }
        return (result, IntPoint(x: region.minX, y: region.minY))
    }
}
