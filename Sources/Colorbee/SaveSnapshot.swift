import ColorbeeCore
import Foundation

/// Everything saving or exporting needs. Made from a copy of the canvas, it can be encoded off the
/// main thread while editing carries on (NFR-6); nothing else holds the copy.
struct SaveSnapshot: @unchecked Sendable {
    let canvas: ColorbeeCore.Canvas
    let transparentKey: Pixel?
    /// What formats without transparency are flattened over (Color 2).
    let matte: Pixel

    func encoded(as format: ImageFileFormat, quality: Double = 0.9) throws -> Data {
        try ImageCodec.encode(canvas.flattened(transparentKey: transparentKey), colorSpace: canvas.colorSpace, as: format, quality: quality, matte: matte)
    }

    func encodedProject() throws -> Data {
        try ProjectFile.encode(canvas, transparentKey: transparentKey)
    }

    /// A PNG scaled by an export preset, using the sharpness that suits the image's size.
    func encoded(using preset: ExportPreset) throws -> Data {
        let image = canvas.flattened(transparentKey: transparentKey)
        let scaled = image.resampled(to: preset.targetSize(for: image.size), using: ExportPreset.resampling(for: image.size))
        return try ImageCodec.encode(scaled, colorSpace: canvas.colorSpace, as: .png)
    }
}
