import CoreGraphics
import Foundation
import Testing
@testable import ColorbeeCore

/// Perspective Correction's starting corners (FR-9.7 item 7), found by Apple Vision on this Mac.
struct RectangleFinderTests {
    /// A gray picture with a light four-sided shape on it, as a whiteboard photographed at an angle looks.
    private func picture(_ corners: [CGPoint]?, circle: Bool = false) throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: 600, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        // Drawn top-down, as image pixels are counted.
        context.translateBy(x: 0, y: 400)
        context.scaleBy(x: 1, y: -1)
        context.setFillColor(CGColor(gray: 0.25, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 600, height: 400))
        context.setFillColor(CGColor(gray: 0.95, alpha: 1))
        if let corners {
            context.move(to: corners[0])
            corners.dropFirst().forEach { context.addLine(to: $0) }
            context.closePath()
            context.fillPath()
        }
        if circle { context.fillEllipse(in: CGRect(x: 180, y: 80, width: 240, height: 240)) }
        return try #require(context.makeImage())
    }

    @Test func itFindsTheCornersOfASlantedRectangle() async throws {
        let corners = [CGPoint(x: 120, y: 70), CGPoint(x: 480, y: 95), CGPoint(x: 455, y: 330), CGPoint(x: 140, y: 310)]
        let found = try #require(try await RectangleFinder.find(in: picture(corners)))
        #expect(found.count == 4)
        for (corner, point) in zip(corners, found) {
            #expect(abs(point.x - corner.x) <= 2 && abs(point.y - corner.y) <= 2, "\(point) is not at \(corner)")
        }
    }

    @Test func aPictureWithNoRectangleFindsNone() async throws {
        #expect(try await RectangleFinder.find(in: picture(nil, circle: true)) == nil)
    }

    private func testImage(_ name: String) throws -> CGImage {
        let url = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../../../TestImages/\(name)")
        let decoded = try ImageCodec.decode(Data(contentsOf: url))
        return try ImageCodec.makeCGImage(decoded.buffer, colorSpace: decoded.colorSpace)
    }

    @Test func itFindsThePracticeWhiteboardAndNothingInAPlainPhoto() async throws {
        // The whiteboard's outer frame corners, as drawn.
        let frame = [Point2D(x: 403, y: 120), Point2D(x: 1302, y: 196), Point2D(x: 1400, y: 903), Point2D(x: 226, y: 995)]
        let found = try #require(try await RectangleFinder.find(in: testImage("Stage 9 Practice Perspective.png")))
        for (corner, point) in zip(frame, found) {
            #expect(abs(point.x - corner.x) <= 40 && abs(point.y - corner.y) <= 40, "\(point) is not near \(corner)")
        }
        #expect(try await RectangleFinder.find(in: testImage("Photo Editing/Dull Photo.png")) == nil)
    }
}

/// Crop…'s guides (FR-9.7 item 7).
struct CropOverlayTests {
    @Test func thirdsSplitTheBoxEvenly() {
        let lines = CropOverlay.thirds.lines(in: IntRect(x: 10, y: 20, width: 300, height: 90))
        #expect(lines.count == 4)
        #expect(lines.contains { $0.0 == Point2D(x: 110, y: 20) && $0.1 == Point2D(x: 110, y: 110) })
        #expect(lines.contains { $0.0 == Point2D(x: 10, y: 80) && $0.1 == Point2D(x: 310, y: 80) })
    }

    @Test func everyGuideStaysInsideTheBox() {
        let box = IntRect(x: 5, y: 5, width: 200, height: 120)
        for overlay in CropOverlay.allCases {
            for rect in [box, IntRect(x: 5, y: 5, width: 90, height: 160)] {
                let points = overlay.lines(in: rect).flatMap { [$0.0, $0.1] }
                #expect(!points.isEmpty)
                #expect(points.allSatisfy { $0.x >= Double(rect.minX) - 1e-6 && $0.x <= Double(rect.maxX) + 1e-6
                    && $0.y >= Double(rect.minY) - 1e-6 && $0.y <= Double(rect.maxY) + 1e-6 }, "\(overlay.title)")
            }
        }
    }

    @Test func oGoesThroughThemAllInTurn() {
        var overlay = CropOverlay.thirds
        var seen: [CropOverlay] = []
        for _ in CropOverlay.allCases {
            seen.append(overlay)
            overlay = overlay.next
        }
        #expect(seen == CropOverlay.allCases && overlay == .thirds)
        #expect(CropOverlay.allCases.map(\.title) == ["Thirds", "Grid", "Diagonal", "Triangle", "Golden Ratio", "Golden Spiral"])
    }
}
