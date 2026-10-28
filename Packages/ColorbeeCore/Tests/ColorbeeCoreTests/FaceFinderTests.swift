import CoreGraphics
import Foundation
import Testing
@testable import ColorbeeCore

/// Auto-Redact's faces (FR-9.7 item 10).
struct FaceFinderTests {
    @Test func boxesGrowThirtyPercentAndStayOnThePicture() {
        let bounds = IntRect(x: 0, y: 0, width: 200, height: 100)
        // 40 × 50 grows 6 and 7.5 on each side.
        #expect(FaceFinder.padded(CGRect(x: 100, y: 20, width: 40, height: 50), in: bounds) == IntRect(x: 94, y: 12, width: 52, height: 66))
        // At the edge, cut to the picture.
        #expect(FaceFinder.padded(CGRect(x: 0, y: 0, width: 20, height: 20), in: bounds) == IntRect(x: 0, y: 0, width: 23, height: 23))
    }

    @Test func facesAreInReadingOrderAndNumberedThroughTheDocument() {
        let boxes = [IntRect(x: 300, y: 10, width: 50, height: 60), IntRect(x: 20, y: 200, width: 50, height: 60), IntRect(x: 40, y: 25, width: 50, height: 60)]
        #expect(FaceFinder.ordered(boxes) == [boxes[2], boxes[0], boxes[1]])
        let ids = [UUID(), UUID()]
        let matches = FaceFinder.matches([(ids[0], boxes[0]), (ids[1], boxes[1])], numberedFrom: 4)
        #expect(matches.map(\.text) == ["Face 4", "Face 5"] && matches.map(\.id) == ids && matches.allSatisfy { $0.patternName == "Faces" })
    }

    @Test func theFacesRowNeverMatchesText() {
        #expect(RedactionPattern.builtIns.contains { $0.isFaces && $0.isEnabled && $0.name == "Faces" })
        let found = AutoRedact.matches(in: "jo@example.com and anything else", patterns: RedactionPattern.builtIns)
        #expect(found.map(\.name) == ["Email"])
    }

    @Test func itFindsTheMadeUpFacesInTheTestPicture() async throws {
        let url = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../../../TestImages/Auto-Redact Faces.png")
        let decoded = try ImageCodec.decode(Data(contentsOf: url))
        let faces = try await FaceFinder.find(in: ImageCodec.makeCGImage(decoded.buffer, colorSpace: decoded.colorSpace))
        #expect(faces.count == 3)
        // Each box covers its face's middle (the faces are drawn at x 170, 450 and 720, y about 270).
        for (face, middle) in zip(faces, [170, 450, 720]) {
            #expect(face.contains(IntPoint(x: middle, y: 270)), "\(face)")
        }
    }
}
