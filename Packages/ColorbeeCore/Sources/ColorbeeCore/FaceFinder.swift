import CoreGraphics
import Vision

/// The faces Apple Vision finds in a picture, on this Mac (FR-9.7 item 10), for Auto-Redact. Even tiny ones are
/// listed, for the person to untick (Q21.5). Faces that are turned away, half hidden or drawn can be missed.
public enum FaceFinder {
    /// How much bigger than Vision's tight box each face's box is, to cover hair and chin (Q21.3).
    static let padding = 0.3

    /// Each face's box in image pixels, padded, top to bottom and then left to right. Nothing leaves the Mac.
    public static func find(in image: CGImage) async throws -> [IntRect] {
        try await Task.detached(priority: .userInitiated) {
            let request = VNDetectFaceRectanglesRequest()
            try VNImageRequestHandler(cgImage: image).perform([request])
            let bounds = IntRect(x: 0, y: 0, width: image.width, height: image.height)
            let width = Double(image.width), height = Double(image.height)
            // Vision measures from the bottom-left, 0...1.
            let boxes = (request.results ?? []).map { face in
                let box = face.boundingBox
                return CGRect(x: box.minX * width, y: (1 - box.maxY) * height, width: box.width * width, height: box.height * height)
            }
            return ordered(boxes.compactMap { padded($0, in: bounds) })
        }.value
    }

    /// `box` grown by `padding` about its middle, in whole pixels, kept on the picture.
    static func padded(_ box: CGRect, in bounds: IntRect) -> IntRect? {
        let grown = box.insetBy(dx: -box.width * padding / 2, dy: -box.height * padding / 2)
        let minX = Int(grown.minX.rounded(.down)), minY = Int(grown.minY.rounded(.down))
        let rect = IntRect(x: minX, y: minY, width: Int(grown.maxX.rounded(.up)) - minX, height: Int(grown.maxY.rounded(.up)) - minY)
            .intersection(bounds)
        return rect.isEmpty ? nil : rect
    }

    /// Reading order: rows top to bottom (a face starting below another's middle is on a new row), each left to right.
    static func ordered(_ boxes: [IntRect]) -> [IntRect] {
        boxes.sorted { a, b in
            let sameRow = abs(Double(a.minY - b.minY)) < Double(min(a.height, b.height)) / 2
            return sameRow ? a.minX < b.minX : a.minY < b.minY
        }
    }

    /// The faces as Auto-Redact items, "Face 1" and on from `number`, keeping the ids given.
    public static func matches(_ boxes: [(id: UUID, rect: IntRect)], numberedFrom number: Int) -> [RedactionMatch] {
        boxes.enumerated().map { index, face in
            RedactionMatch(id: face.id, patternName: "Faces", text: "Face \(number + index)", rect: face.rect)
        }
    }
}
