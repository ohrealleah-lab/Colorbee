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
                    if let eye = eye(outline: points, pupil: pupil?.pointsInImage(imageSize: size).first, imageHeight: size.height) {
                        eyes.append(eye)
                    }
                }
            }
            return eyes
        }.value
    }

    /// The circle around one eye, from Vision's outline of it and its pupil (in Vision's image coordinates, y up);
    /// nil for an empty outline. Without a pupil, the outline's middle is used.
    static func eye(outline points: [CGPoint], pupil: CGPoint?, imageHeight: Double) -> Eye? {
        let xs = points.map(\.x), ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return nil }
        let width = maxX - minX, height = maxY - minY
        let center = pupil ?? CGPoint(x: (maxX + minX) / 2, y: (maxY + minY) / 2)
        // Vision's y runs up from the bottom.
        return Eye(center: Point2D(x: center.x, y: imageHeight - center.y), radius: max(3, max(width * 0.32, height * 0.6)))
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
                return dx * dx + dy * dy <= eye.radius * eye.radius ? 255 : 0
            } || changed
        }
        return changed
    }

    /// Darkens the red pixels in `mask`, partly where it's partly selected (FR-3.4; review O, finding 11). Returns
    /// whether anything changed.
    @discardableResult
    public static func fix(in mask: SelectionMask, layer: Layer, edit: Edit) -> Bool {
        fix(layer, in: mask.bounds.intersection(layer.buffer.bounds), edit: edit) { x, y in mask[x, y] }
    }

    /// `amount` says how much of each pixel to fix, 0...255.
    private static func fix(_ layer: Layer, in area: IntRect, edit: Edit, amount: (Int, Int) -> UInt8) -> Bool {
        var changed = false
        var recorded = false
        for y in area.minY..<area.maxY {
            let row = layer.buffer.row(y)
            for x in area.minX..<area.maxX {
                let weight = amount(x, y)
                guard weight > 0 else { continue }
                let pixel = row[x]
                guard let darker = darkened(pixel) else { continue }
                let fixed = Effects.mixed(pixel, darker, weight)
                guard fixed != pixel else { continue }
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
