import Testing
@testable import ColorbeeCore

/// Match Surroundings (FR-4.6), on small made-up pictures.
struct MatchSurroundingsTests {
    private let object = Pixel(r: 20, g: 20, b: 25)

    /// Grainy sand with a dark stone in the middle; the area covers the stone.
    private func sand() -> (PixelBuffer, SelectionMask) {
        var state: UInt64 = 11
        let buffer = PixelBuffer(width: 160, height: 120)
        for y in 0..<120 {
            for x in 0..<160 {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                let grain = UInt8(state >> 59)
                let inStone = (x - 80) * (x - 80) + (y - 60) * (y - 60) < 14 * 14
                buffer[x, y] = inStone ? object : Pixel(r: 190 &+ grain, g: 165 &+ grain, b: 120 &+ grain)
            }
        }
        return (buffer, area { x, y in (x - 80) * (x - 80) + (y - 60) * (y - 60) < 17 * 17 })
    }

    private func area(_ inside: (Int, Int) -> Bool) -> SelectionMask {
        let bounds = IntRect(x: 0, y: 0, width: 160, height: 120)
        var values = [UInt8](repeating: 0, count: bounds.area)
        for y in 0..<120 { for x in 0..<160 where inside(x, y) { values[y * 160 + x] = 255 } }
        return SelectionMask(bounds: bounds, values: values)
    }

    @Test func aStoneOnSandIsReplacedBySand() throws {
        let (buffer, mask) = sand()
        let fill = try #require(MatchSurroundings.Job(image: buffer, area: mask)).run()
        let filled = zip(fill.pixels, fill.filled).filter(\.1).map(\.0)
        #expect(!filled.isEmpty)
        // Nothing of the stone is left, and the fill is sand colored.
        #expect(filled.allSatisfy { $0.r >= 185 && $0.g >= 160 && $0.b >= 115 })
    }

    @Test func theSameAreaFillsTheSameWayEveryTime() throws {
        let (buffer, mask) = sand()
        let job = try #require(MatchSurroundings.Job(image: buffer, area: mask))
        #expect(try job.run().pixels == job.run().pixels)
    }

    @Test func onlyTheAreaChanges() throws {
        let (buffer, mask) = sand()
        let before = buffer.copy()
        let layer = Layer(name: "Sand", buffer: buffer)
        let canvas = Canvas(colorSpace: Canvas.defaultColorSpace, layers: [layer], hasTransparentBackground: false)
        let history = History(byteBudget: .max)
        let edit = history.beginEdit("Remove", on: canvas)
        try #require(MatchSurroundings.Job(image: buffer, area: mask)).run().apply(to: layer, edit: edit)
        #expect(history.commit(edit))
        for y in 0..<120 {
            for x in 0..<160 where mask[x, y] == 0 { #expect(buffer[x, y] == before[x, y]) }
        }
        history.undo(on: canvas)
        #expect(buffer.contentHash() == before.contentHash())
    }

    /// Around a flat area, as in a screenshot, the fill is exactly that color: nothing nearby, such as other lines of
    /// text, is carried in.
    @Test func aLineOfTextOnAFlatPanelLeavesThePanelColor() throws {
        let buffer = PixelBuffer(width: 160, height: 120, fill: .white)
        for line in stride(from: 20, to: 110, by: 20) {
            buffer.fill(Pixel(r: 30, g: 30, b: 35), in: IntRect(x: 20, y: line, width: 110, height: 6))
        }
        let fill = try #require(MatchSurroundings.Job(image: buffer, area: area { x, y in x >= 16 && x < 134 && y >= 56 && y < 70 })).run()
        let filled = zip(fill.pixels, fill.filled).filter(\.1).map(\.0)
        #expect(!filled.isEmpty && filled.allSatisfy { $0 == .white })
    }

    @Test func cancellingStopsTheFill() throws {
        let (buffer, mask) = sand()
        let job = try #require(MatchSurroundings.Job(image: buffer, area: mask))
        #expect(throws: MatchSurroundings.Cancelled.self) { try job.run(isCancelled: { true }) }
    }

    @Test func anEmptyAreaIsNoJob() {
        let (buffer, _) = sand()
        #expect(MatchSurroundings.Job(image: buffer, area: area { _, _ in false }) == nil)
    }
}
