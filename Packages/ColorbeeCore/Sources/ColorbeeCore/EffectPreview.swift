/// An effect worked out away from the document (FR-9.1 live previews, NFR-6): computed in the background
/// from a private copy of the layer, then copied into the layer on the main thread.
public struct EffectPreview: @unchecked Sendable {
    /// The part of the layer the effect changed.
    public let region: IntRect
    /// That region as it should look, unselected pixels included.
    let pixels: PixelBuffer

    /// `effect` applied to a copy of `source` (the layer's original pixels), in `regions` or everywhere.
    /// Reads `source` only, so it's safe off the main thread while nothing else writes to it.
    public static func render(_ effect: Effect, from source: PixelBuffer, regions: [SelectionMask]?) -> EffectPreview? {
        let scratch = Canvas(colorSpace: Canvas.defaultColorSpace, layers: [Layer(name: "Preview", buffer: source.copy())], hasTransparentBackground: true)
        let layer = scratch.layers[0]
        let edit = Edit(name: "Preview", canvas: scratch, recordsPixels: false)
        let changed = if let regions {
            Effects.apply(effect, to: layer, regions: regions, edit: edit)
        } else {
            Effects.apply(effect, to: layer, selection: nil, edit: edit)
        }
        guard !changed.isEmpty else { return nil }
        let pixels = PixelBuffer(width: changed.width, height: changed.height)
        for y in changed.minY..<changed.maxY {
            (pixels.row(y - changed.minY)).update(from: layer.buffer.row(y) + changed.minX, count: changed.width)
        }
        return EffectPreview(region: changed, pixels: pixels)
    }

    /// Puts the preview into `layer`, recording the original pixels in `edit` first.
    public func write(into layer: Layer, edit: Edit) {
        edit.willModify(region, in: layer)
        for y in region.minY..<region.maxY {
            (layer.buffer.row(y) + region.minX).update(from: pixels.row(y - region.minY), count: region.width)
        }
    }
}
