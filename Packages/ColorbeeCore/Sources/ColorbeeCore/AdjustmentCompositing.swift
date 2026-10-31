import simd

extension Compositing {
    /// What an adjustment layer does to the image beneath it (FR-8.4): the adjusted image, mixed by the
    /// layer's blend mode, then faded in by its opacity. `Shaders.metal` does the same for the display.
    static func adjust(_ below: PixelBuffer, by adjustment: Effect, opacity: Double, mode: BlendMode, mask: PixelBuffer? = nil,
                       placement: Effects.Placement? = nil) -> PixelBuffer {
        mixed(below, Effects.adjusted(below, by: adjustment, placement: placement), opacity: opacity, mode: mode, mask: mask)
    }

    /// `adjusted` over `below` by `mode`, faded in by `opacity`: an adjustment layer's result, and a Pass Through
    /// group's (stage 25).
    /// A mask fades it further, pixel by pixel (stage 28a).
    static func mixed(_ below: PixelBuffer, _ adjusted: PixelBuffer, opacity: Double, mode: BlendMode, mask: PixelBuffer? = nil) -> PixelBuffer {
        let result = PixelBuffer(width: below.width, height: below.height)
        let fade = Float(min(1, max(0, opacity)))
        ParallelRows.forEach(0..<below.height) { rows in
            for y in rows {
            let beneath = below.row(y), changed = adjusted.row(y), target = result.row(y), masked = mask?.row(y)
            for x in 0..<below.width {
                let backdrop = premultiplied(beneath[x])
                let source = changed[x]
                let sourceAlpha = Float(source.a) / 255
                var color = SIMD3(Float(source.r), Float(source.g), Float(source.b)) / 255
                if mode != .normal, backdrop.w > 0 {
                    color = mode.blend(SIMD3(backdrop.x, backdrop.y, backdrop.z) / backdrop.w, color)
                }
                let goal = SIMD4(color * sourceAlpha, sourceAlpha)
                target[x] = pixel(backdrop + (goal - backdrop) * (masked.map { fade * reveal($0[x]) } ?? fade))
            }
          }
        }
        return result
    }
}

extension Effects {
    /// Where a patch of the canvas sits in the whole, so Adjust Photo's vignette and grain land on it as they do on
    /// the whole picture (`Canvas.patchAsShown`).
    struct Placement {
        let origin: IntPoint
        let canvas: IntRect
    }

    /// A whole image with an effect applied, leaving the original untouched. Used by adjustment layers.
    static func adjusted(_ buffer: PixelBuffer, by effect: Effect, placement: Placement? = nil) -> PixelBuffer {
        if let placement, case .photo(let edit) = effect {
            return photoAdjusted(buffer, region: buffer.bounds, edit: edit, selection: nil, placement: placement).0
        }
        let canvas = Canvas(colorSpace: Canvas.defaultColorSpace, layers: [Layer(name: "Adjust", buffer: buffer.copy())], hasTransparentBackground: true)
        // Nothing to undo here, so the edit keeps no before-images.
        let edit = Edit(name: "Adjust", canvas: canvas, recordsPixels: false)
        apply(effect, to: canvas.layers[0], selection: nil, edit: edit)
        return canvas.layers[0].buffer
    }
}

extension Compositing {
    /// `source` blended onto `base` only where it has pixels, keeping its opacity: a pixel layer set to "Only the layer
    /// below" (stage 28b), faded by `mask`.
    static func blendAtop(_ base: PixelBuffer, _ source: PixelBuffer, opacity: Double, mode: BlendMode, mask: PixelBuffer?) -> PixelBuffer {
        let result = PixelBuffer(width: base.width, height: base.height)
        ParallelRows.forEach(0..<base.height) { rows in
            for y in rows {
                let below = base.row(y), above = source.row(y), target = result.row(y), masked = mask?.row(y)
                for x in 0..<base.width {
                    let fade = Float(opacity) * (masked.map { reveal($0[x]) } ?? 1)
                    target[x] = blendAtop(below[x], above[x], opacity: fade, mode: mode)
                }
            }
        }
        return result
    }
}
