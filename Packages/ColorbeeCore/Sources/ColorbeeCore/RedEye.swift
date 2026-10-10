import CoreGraphics
import Vision

/// Remove Red-Eye (FR-9.5): red pupils from a flash turned dark, on this Mac. Vision finds the eyes; with a selection,
/// the red pixels inside it are fixed instead, for eyes it misses (pets, faces turned away). Only red pixels change,
/// so the white highlight in an eye stays.
public enum RedEye {
    /// Where to look for red pupils: a circle around each pupil Vision finds.
    public struct Eye: Sendable, Equatable {
        public let center: Point2D
        public let radius: Double

        public init(center: Point2D, radius: Double) {
            self.center = center
            self.radius = radius
        }
    }

    /// The eyes in `image`, as circles a little larger than the iris, in image coordinates (origin top-left).
    public static func findEyes(in image: CGImage) async throws -> [Eye] {
        try await Task.detached(priority: .userInitiated) {
            let request = VNDetectFaceLandmarksRequest()
            try VNImageRequestHandler(cgImage: image).perform([request])
            let size = CGSize(width: image.width, height: image.height)
            var eyes: [Eye] = []
            for face in request.results ?? [] {
                guard let landmarks = face.landmarks else { continue }
                for (pupil, outline) in [(landmarks.leftPupil, landmarks.leftEye), (landmarks.rightPupil, landmarks.rightEye)] {
                    guard let outline, outline.pointCount > 0 else { continue }
                    let points = outline.pointsInImage(imageSize: size)
                    let xs = points.map(\.x), ys = points.map(\.y)
                    let width = (xs.max()! - xs.min()!), height = (ys.max()! - ys.min()!)
                    let center = pupil?.pointsInImage(imageSize: size).first
                        ?? CGPoint(x: (xs.max()! + xs.min()!) / 2, y: (ys.max()! + ys.min()!) / 2)
                    // Vision's y runs up from the bottom.
                    eyes.append(Eye(center: Point2D(x: center.x, y: size.height - center.y), radius: max(3, max(width * 0.32, height * 0.6))))
                }
            }
            return eyes
        }.value
    }

    /// Darkens the red pixels inside `eyes`. Returns whether anything changed.
    @discardableResult
    public static func fix(_ eyes: [Eye], in layer: Layer, edit: Edit) -> Bool {
        var changed = false
        for eye in eyes {
            let area = IntRect(enclosingMinX: eye.center.x - eye.radius, minY: eye.center.y - eye.radius,
                               maxX: eye.center.x + eye.radius, maxY: eye.center.y + eye.radius).intersection(layer.buffer.bounds)
            guard !area.isEmpty else { continue }
            changed = fix(layer, in: area, edit: edit) { x, y in
                let dx = Double(x) + 0.5 - eye.center.x, dy = Double(y) + 0.5 - eye.center.y
                return dx * dx + dy * dy <= eye.radius * eye.radius
            } || changed
        }
        return changed
    }

    /// Darkens the red pixels in `mask`. Returns whether anything changed.
    @discardableResult
    public static func fix(in mask: SelectionMask, layer: Layer, edit: Edit) -> Bool {
        fix(layer, in: mask.bounds.intersection(layer.buffer.bounds), edit: edit) { x, y in mask[x, y] > 0 }
    }

    private static func fix(_ layer: Layer, in area: IntRect, edit: Edit, inside: (Int, Int) -> Bool) -> Bool {
        var changed = false
        var recorded = false
        for y in area.minY..<area.maxY {
            let row = layer.buffer.row(y)
            for x in area.minX..<area.maxX where inside(x, y) {
                let pixel = row[x]
                guard let fixed = darkened(pixel) else { continue }
                if !recorded {
                    edit.willModify(area, in: layer)
                    recorded = true
                }
                row[x] = fixed
                changed = true
            }
        }
        return changed
    }

    /// A red-eye pixel with its red brought down to the other channels, fading in with how red it is so the pupil's
    /// edge stays soft; nil if it isn't red enough to be red-eye.
    static func darkened(_ pixel: Pixel) -> Pixel? {
        let r = Float(pixel.r), g = Float(pixel.g), b = Float(pixel.b)
        let others = max(g, b)
        guard r > 50, r > others else { return nil }
        let redness = (r - others) / r
        // Skin and brown irises are reddish too, but nowhere near as red as a flash's red-eye.
        let amount = min(1, max(0, (redness - 0.45) / 0.2))
        guard amount > 0 else { return nil }
        let target = (g + b) / 2
        let red = UInt8((r + (target - r) * amount).rounded())
        return red == pixel.r ? nil : Pixel(r: red, g: pixel.g, b: pixel.b, a: pixel.a)
    }
}
