import ColorbeeCore
import CoreGraphics
import Foundation

/// A page as opened, or its layers as saved: what Before/After's "As Opened" and Revert Layer go back to (FR-8.3,
/// FR-11.3). While its page is hidden it's kept compressed, as a one-page project, and it's only decoded the first
/// time it's needed, so visiting many pages doesn't keep a full-size copy of each (review K, finding 3; L, finding 4).
@MainActor
final class PageBaseline {
    private var data: Data?
    private var canvas: Canvas?
    private var flattenedImage: PixelBuffer?
    /// The pixel layers' ids and the size, known without decoding, for whether Revert Layer can apply.
    let layerIDs: Set<LayerID>
    let size: IntSize

    /// From compressed bytes (a parked page's, or a page as it was saved), described by `page` as it is then.
    init(data: Data, describing canvas: Canvas) {
        self.data = data
        layerIDs = Set(canvas.layers.filter { $0.adjustment == nil }.map(\.id))
        size = canvas.size
    }

    /// From a canvas nothing else changes (a copy).
    init(canvas: Canvas) {
        self.canvas = canvas
        layerIDs = Set(canvas.layers.filter { $0.adjustment == nil }.map(\.id))
        size = canvas.size
    }

    /// From the pixel layers as saved, by id.
    convenience init?(layers: [LayerID: PixelBuffer], colorSpace: CGColorSpace) {
        guard !layers.isEmpty else { return nil }
        let canvas = Canvas(colorSpace: colorSpace, layers: layers.map { Layer(name: "", buffer: $0.value, id: $0.key) },
                            hasTransparentBackground: true)
        self.init(canvas: canvas)
    }

    private var decoded: Canvas? {
        if canvas == nil, let data { canvas = try? ProjectFile.decode(data) }
        return canvas
    }

    /// The page as it looked, for Before/After.
    var flattened: PixelBuffer? {
        if flattenedImage == nil { flattenedImage = decoded?.flattened() }
        return flattenedImage
    }

    /// One pixel layer's pixels, for Revert Layer.
    func layer(_ id: LayerID) -> PixelBuffer? {
        decoded?.layers.first { $0.id == id && $0.adjustment == nil }?.buffer
    }

    /// Back to compressed form, for when the page is hidden.
    func pack() {
        if data == nil, let canvas { data = try? ProjectFile.encode(canvas) }
        if data != nil {
            canvas = nil
            flattenedImage = nil
        }
    }
}
