import ColorbeeCore
import Foundation

/// Everything saving or exporting needs. Made from a copy of the canvas, it can be encoded off the
/// main thread while editing carries on (NFR-6); nothing else holds the copy.
struct SaveSnapshot: @unchecked Sendable {
    let canvas: ColorbeeCore.Canvas
    let transparentKey: Pixel?
    /// How a stretched floating selection is drawn, as it will be placed (review F, finding 2).
    let resampling: Resampling
    /// What formats without transparency are flattened over (Color 2).
    let matte: Pixel
    /// History's crop, resize, rotation and flip steps when the copy was made, for Revert Layer.
    let geometrySteps: [ObjectIdentifier]

    func encoded(as format: ImageFileFormat, quality: Double = 0.9, tiffLZW: Bool = false) throws -> Data {
        try ImageCodec.encode(canvas.flattened(transparentKey: transparentKey, resampling: resampling), colorSpace: canvas.colorSpace, as: format, quality: quality,
                              matte: matte, tiffLZW: tiffLZW)
    }

    func encodedProject() throws -> Data {
        try ProjectFile.encode(canvas, transparentKey: transparentKey, resampling: resampling)
    }

    /// A PNG scaled by an export preset, with the chosen scaling or the one that suits the image's size.
    func encoded(using preset: ExportPreset, scaling: Resampling? = nil) throws -> Data {
        let image = canvas.flattened(transparentKey: transparentKey, resampling: resampling)
        let scaled = image.resampled(to: preset.targetSize(for: image.size), using: scaling ?? ExportPreset.resampling(for: image.size))
        return try ImageCodec.encode(scaled, colorSpace: canvas.colorSpace, as: .png)
    }
}
