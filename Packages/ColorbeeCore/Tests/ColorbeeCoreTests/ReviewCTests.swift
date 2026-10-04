import Foundation
import Testing
@testable import ColorbeeCore

/// Regression tests for the findings of cloud review C (Docs/Review/findings-C.md).
struct ReviewCTests {
    private let context = SelectionContext(color2: .white)

    /// Finding 1: crossed corners put the homography's divisor through zero.
    @Test func perspectiveRefusesCrossedCorners() {
        let canvas = Canvas(size: IntSize(width: 1000, height: 801), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: 512 << 20)
        let corners = [Point2D(x: 0, y: 0), Point2D(x: 1000, y: 0), Point2D(x: 0, y: 801), Point2D(x: 1000, y: 801)]
        #expect(!Warp.isConvex(corners))
        #expect(!ImageActions.correctPerspective(corners: corners, canvas: canvas, history: history, context: context))
        #expect(canvas.size == IntSize(width: 1000, height: 801))
        #expect(!history.canUndo)
    }

    @Test func convexCornersInEitherTurnAreAccepted() {
        let square = [Point2D(x: 0, y: 0), Point2D(x: 10, y: 1), Point2D(x: 9, y: 10), Point2D(x: 1, y: 9)]
        #expect(Warp.isConvex(square))
        #expect(Warp.isConvex(square.reversed()))
        #expect(!Warp.isConvex([Point2D(x: 0, y: 0), Point2D(x: 10, y: 0), Point2D(x: 2, y: 2), Point2D(x: 0, y: 10)]))
        #expect(!Warp.isConvex([Point2D(x: 0, y: 0), Point2D(x: 0, y: 0), Point2D(x: 10, y: 10), Point2D(x: 0, y: 10)]))
    }

    /// Finding 2: the screen's table must give exactly what export gives, even for hard steps.
    @Test(arguments: [
        Effect.posterize(levels: 2), .posterize(levels: 4), .posterize(levels: 8), .posterize(levels: 32),
        .levels(Levels(black: 100, white: 140)),
        .curves(Curves(rgb: Curves.straight, red: [.init(x: 0, y: 0), .init(x: 120, y: 10), .init(x: 130, y: 250), .init(x: 255, y: 255)], green: Curves.straight, blue: Curves.straight)),
    ])
    func channelTablesMatchExport(effect: Effect) throws {
        let table = try #require(ChannelTable(effect))
        let transform = try #require(effect.colorTransform)
        var random = SplitMix64(seed: 7)
        for value in 0..<256 {
            for pixel in [Pixel(r: UInt8(value), g: UInt8(value), b: UInt8(value)), Pixel(r: random.byte(), g: random.byte(), b: random.byte())] {
                let expected = transform(pixel)
                let shown = table.apply(pixel)
                #expect(shown == expected, "\(effect) at \(pixel)")
            }
        }
    }

    @Test func onlyPerChannelAdjustmentsUseChannelTables() {
        #expect(ChannelTable(.posterize(levels: 4)) != nil)
        #expect(ChannelTable(.sepia(amount: 50)) == nil)
        #expect(ChannelTable(.photo(PhotoEdit())) == nil)
        #expect(ColorLookup(.posterize(levels: 4)) == nil)
        #expect(ColorLookup(.sepia(amount: 50)) != nil)
    }

    /// Finding 3: squared column positions past 2^24 lost precision in Float.
    @Test func distancesStayExactAlongVeryWideShapes() throws {
        let buffer = PixelBuffer(width: 16_000, height: 1)
        buffer.fill(.black, in: buffer.bounds)
        let shape = try #require(Shape(buffer, selection: nil))
        let field = shape.distanceField(pad: 2)
        for x in 0..<16_000 {
            #expect(abs(field.value(x, -1) - 1) < 0.01, "x \(x)")
            #expect(abs(field.value(x, -2) - 2) < 0.01, "x \(x)")
        }
    }

    /// Finding 4: damaged files give an error, not a crash.
    @Test func aProjectWithAnImpossibleSizeIsDamaged() throws {
        let canvas = Canvas(size: IntSize(width: 4, height: 4), colorSpace: Canvas.defaultColorSpace, background: .white)
        let data = try ProjectFile.encode(canvas)
        let jsonStart = ProjectFile.magic.count + 4
        let length = Int(data[ProjectFile.magic.count..<jsonStart].withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) })
        var manifest = try JSONDecoder().decode(ProjectFile.Manifest.self, from: data[jsonStart..<(jsonStart + length)])
        manifest.width = 4_000_000_000
        let json = try JSONEncoder().encode(manifest)
        var damaged = Data(ProjectFile.magic)
        var newLength = UInt32(json.count).littleEndian
        damaged.append(Data(bytes: &newLength, count: 4))
        damaged.append(json)
        damaged.append(data[(jsonStart + length)...])
        #expect(throws: ProjectFile.Failure.damaged) { try ProjectFile.decode(damaged) }
    }

    @Test(arguments: ["posterize", "pixelate", "gaussianBlur"])
    func anEffectWithAnOutOfRangeNumberIsRejected(kind: String) {
        let json = Data(#"{"kind": "\#(kind)", "values": [1e300]}"#.utf8)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(Effect.self, from: json) }
    }
}
