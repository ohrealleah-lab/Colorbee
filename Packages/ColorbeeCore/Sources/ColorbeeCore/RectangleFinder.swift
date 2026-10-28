import CoreGraphics
import Vision

/// The biggest rectangle Apple Vision finds in a picture, on this Mac (FR-9.7 item 7): a whiteboard, a document or
/// a sign photographed at an angle, for Perspective Correction's corners to start on.
public enum RectangleFinder {
    /// Its corners in image pixels, top-left, top-right, bottom-right, bottom-left (Perspective Correction's order),
    /// or nil if there's none at least a fifth of the picture across. Nothing leaves the Mac.
    public static func find(in image: CGImage) async throws -> [Point2D]? {
        try await Task.detached(priority: .userInitiated) {
            let request = VNDetectRectanglesRequest()
            request.maximumObservations = 8
            request.minimumSize = 0.2
            request.minimumAspectRatio = 0.1
            request.quadratureTolerance = 40
            request.minimumConfidence = 0.4
            try VNImageRequestHandler(cgImage: image).perform([request])
            let width = Double(image.width), height = Double(image.height)
            // Vision measures from the bottom-left, 0...1.
            let candidates = (request.results ?? []).map { rectangle in
                [rectangle.topLeft, rectangle.topRight, rectangle.bottomRight, rectangle.bottomLeft].map {
                    Point2D(x: Double($0.x) * width, y: (1 - Double($0.y)) * height)
                }
            }
            // Vision also reports shapes inside round or soft things; only one whose sides follow edges counts.
            guard let gray = Brightness(image) else { return nil }
            return candidates.filter { gray.followsEdges($0) }.max { area($0) < area($1) }
        }.value
    }

    private static func area(_ corners: [Point2D]) -> Double {
        abs((0..<4).reduce(0) { sum, i in
            let a = corners[i], b = corners[(i + 1) % 4]
            return sum + a.x * b.y - b.x * a.y
        }) / 2
    }

    /// The picture's brightness, at most 800 pixels across, for checking the sides.
    private struct Brightness {
        let width: Int, height: Int
        let values: [UInt8]
        /// Image pixels per pixel here.
        let scale: Double

        init?(_ image: CGImage) {
            let scale = max(1, Double(max(image.width, image.height)) / 800)
            let width = max(1, Int(Double(image.width) / scale)), height = max(1, Int(Double(image.height) / scale))
            var values = [UInt8](repeating: 0, count: width * height)
            let drawn = values.withUnsafeMutableBytes { bytes -> Bool in
                guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                              space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            guard drawn else { return nil }
            (self.scale, self.width, self.height, self.values) = (scale, width, height, values)
        }

        /// The brightness at image pixel `point`; nil off the picture. Rows here run top-down, as image pixels do.
        func value(at point: Point2D) -> Int? {
            let x = Int(point.x / scale), y = Int(point.y / scale)
            guard x >= 0, y >= 0, x < width, y < height else { return nil }
            return Int(values[y * width + x])
        }

        /// Whether most of each side has a clear step in brightness across it, as a real rectangle's edges do. A side
        /// along the picture's own edge counts too: a document can fill the photo. It looks close to the side, and a
        /// little further out, past a frame such as a whiteboard's, which can put Vision's line on the frame itself.
        func followsEdges(_ corners: [Point2D]) -> Bool {
            let diagonal = Double(width * width + height * height).squareRoot() * scale
            let center = Point2D(x: corners.map(\.x).reduce(0, +) / 4, y: corners.map(\.y).reduce(0, +) / 4)
            return (0..<4).allSatisfy { side in
                [3 * scale, diagonal * 0.02].contains { followsEdge(corners, side, center: center, reach: $0) }
            }
        }

        /// Whether three quarters of side `side` has a step in brightness between `reach` inside it and `reach` outside.
        private func followsEdge(_ corners: [Point2D], _ side: Int, center: Point2D, reach: Double) -> Bool {
            let a = corners[side], b = corners[(side + 1) % 4]
            let length = ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot()
            guard length > 0 else { return false }
            var normal = Point2D(x: -(b.y - a.y) / length, y: (b.x - a.x) / length)
            let middle = Point2D(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            if (middle.x - center.x) * normal.x + (middle.y - center.y) * normal.y < 0 { normal = Point2D(x: -normal.x, y: -normal.y) }
            let samples = (1...19).map { Double($0) / 20 }
            let stepped = samples.filter { t in
                let point = Point2D(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                guard let inside = value(at: Point2D(x: point.x - normal.x * reach, y: point.y - normal.y * reach)) else { return false }
                guard let outside = value(at: Point2D(x: point.x + normal.x * reach, y: point.y + normal.y * reach)) else { return true }
                return abs(inside - outside) >= 12
            }
            return stepped.count * 4 >= samples.count * 3
        }
    }
}
