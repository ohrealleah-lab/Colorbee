import Testing
@testable import ColorbeeCore

/// Refine Edge (Leah, 2026-11-02), on small made-up pictures.
struct RefineEdgeTests {
    /// RGBA bytes: black left of `edge`, white from it on.
    private func split(width: Int, height: Int, edge: Int) -> [UInt8] {
        (0..<(width * height)).flatMap { index -> [UInt8] in
            let value: UInt8 = index % width < edge ? 0 : 255
            return [value, value, value, 255]
        }
    }

    @Test func theRadiusIsEightPixelsForMostPictures() {
        #expect(RefineEdge.radius(for: IntSize(width: 1126, height: 2000)) == 8)
        #expect(RefineEdge.radius(for: IntSize(width: 3266, height: 2144)) == 8)
        #expect(RefineEdge.radius(for: IntSize(width: 800, height: 700)) == 5)
        #expect(RefineEdge.radius(for: IntSize(width: 300, height: 200)) == 4)
        #expect(RefineEdge.radius(for: IntSize(width: 6000, height: 4000)) == 14)
        #expect(RefineEdge.radius(for: IntSize(width: 9000, height: 6000)) == 16)
    }

    @Test func boxMeansAreClippedAtTheEdges() {
        #expect(RefineEdge.boxMean([0, 3, 6], width: 3, height: 1, radius: 1) == [1.5, 3, 4.5])
        #expect(RefineEdge.boxMean([0, 3, 6, 9], width: 2, height: 2, radius: 1) == [4.5, 4.5, 4.5, 4.5])
    }

    @Test func aMaskWithNoEdgeIsLeftAlone() {
        let guide = split(width: 12, height: 4, edge: 6)
        for value: UInt8 in [0, 255, 100] {
            let mask = [UInt8](repeating: value, count: 48)
            #expect(RefineEdge.refined(mask, guide: guide, size: IntSize(width: 12, height: 4), radius: 2) == mask)
        }
    }

    /// Vision's edge is a soft ramp centered near the picture's edge; refined, it steps up where the picture does,
    /// and stays as it was away from it.
    @Test func aSoftEdgeMovesOntoThePicturesEdge() {
        let width = 24, height = 8
        let ramp: [UInt8] = (0..<width).map { x in UInt8((min(max(Double(x - 9) / 6, 0), 1) * 255).rounded()) }
        let mask = (0..<height).flatMap { _ in ramp }
        let refined = RefineEdge.refined(mask, guide: split(width: width, height: height, edge: 12), size: IntSize(width: width, height: height), radius: 3)
        for y in 0..<height {
            let row = Array(refined[(y * width)..<((y + 1) * width)])
            #expect(row[11] < ramp[11] && row[12] > ramp[12])
            #expect(Int(row[12]) - Int(row[11]) > Int(ramp[12]) - Int(ramp[11]))
            #expect(row[0] == 0 && row[23] == 255)
        }
    }

    @Test func tilesJoinWithNoSeams() {
        let size = IntSize(width: 320, height: 30)
        let guide = (0..<(size.width * size.height)).flatMap { index -> [UInt8] in
            let x = index % size.width, y = index / size.width
            return [UInt8((x * 7 + y * 3) % 256), UInt8((x / 3) % 256), (x + y) % 90 < 45 ? 30 : 220, 255]
        }
        let mask = (0..<(size.width * size.height)).map { index -> UInt8 in
            let x = Double(index % size.width), y = Double(index / size.width)
            let distance = ((x - 160) * (x - 160) / 10_000 + (y - 15) * (y - 15) / 225).squareRoot()
            return UInt8((min(max((1.2 - distance) * 2, 0), 1) * 255).rounded())
        }
        let tiled = RefineEdge.refined(mask, guide: guide, size: size, radius: 6, tile: 48)
        let whole = RefineEdge.refined(mask, guide: guide, size: size, radius: 6, tile: 1000)
        #expect(tiled != mask)
        #expect(zip(tiled, whole).allSatisfy { abs(Int($0) - Int($1)) <= 1 })
    }
}
