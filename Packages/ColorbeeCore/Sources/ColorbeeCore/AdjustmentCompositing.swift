import simd

extension Compositing {
    /// What an adjustment layer does to the image beneath it (FR-8.4): the adjusted image, mixed by the
    /// layer's blend mode, then faded in by its opacity. `Shaders.metal` does the same for the display.
    static func adjust(_ below: PixelBuffer, by adjustment: Effect, opacity: Double, mode: BlendMode) -> PixelBuffer {
        let adjusted = Effects.adjusted(below, by: adjustment)
        let result = PixelBuffer(width: below.width, height: below.height)
        let fade = Float(min(1, max(0, opacity)))
        ParallelRows.forEach(0..<below.height) { rows in
            for y in rows {
            let beneath = below.row(y), changed = adjusted.row(y), target = result.row(y)
            for x in 0..<below.width {
                let backdrop = premultiplied(beneath[x])
                let source = changed[x]
                let sourceAlpha = Float(source.a) / 255
                var color = SIMD3(Float(source.r), Float(source.g), Float(source.b)) / 255
                if mode != .normal, backdrop.w > 0 {
                    color = mode.blend(SIMD3(backdrop.x, backdrop.y, backdrop.z) / backdrop.w, color)
                }
                let goal = SIMD4(color * sourceAlpha, sourceAlpha)
                target[x] = pixel(backdrop + (goal - backdrop) * fade)
            }
          }
        }
        return result
    }
}

extension Effects {
    /// A whole image with an effect applied, leaving the original untouched. Used by adjustment layers.
    static func adjusted(_ buffer: PixelBuffer, by effect: Effect) -> PixelBuffer {
        let canvas = Canvas(colorSpace: Canvas.defaultColorSpace, layers: [Layer(name: "Adjust", buffer: buffer.copy())], hasTransparentBackground: true)
        // Nothing to undo here, so the edit keeps no before-images.
        let edit = Edit(name: "Adjust", canvas: canvas, recordsPixels: false)
        apply(effect, to: canvas.layers[0], selection: nil, edit: edit)
        return canvas.layers[0].buffer
    }
}
