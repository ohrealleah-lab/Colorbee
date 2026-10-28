import Testing
@testable import ColorbeeCore

/// Edit ▸ Modify Selection: Expand, Contract and Smooth (FR-9.7 item 3).
struct SelectionModifyTests {
    private let canvas = IntRect(x: 0, y: 0, width: 20, height: 20)

    /// A mask from rows of characters: "#" fully selected, "." not, a digit d selected d × 25.
    private func mask(_ rows: [String], at origin: IntPoint = IntPoint(x: 5, y: 5)) -> SelectionMask {
        let values = rows.flatMap { row in
            row.map { character -> UInt8 in
                switch character {
                case "#": 255
                case ".": 0
                default: UInt8(character.wholeNumberValue! * 25)
                }
            }
        }
        return SelectionMask(bounds: IntRect(x: origin.x, y: origin.y, width: rows[0].count, height: rows.count), values: values)
    }

    /// The mask as rows over `area`, in the same characters ("?" for any other value).
    private func rows(_ mask: SelectionMask?, _ area: IntRect) -> [String] {
        (area.minY..<area.maxY).map { y in
            String((area.minX..<area.maxX).map { x -> Character in
                let value = mask?[x, y] ?? 0
                switch value {
                case 255: return "#"
                case 0: return "."
                case _ where value % 25 == 0: return Character(String(value / 25))
                default: return "?"
                }
            })
        }
    }

    @Test func theRoundAreaIsMadeOfItsSteps() {
        #expect(SelectionMask.diskRectangles(radius: 1).map { [$0.0, $0.1] } == [[1, 1]])
        #expect(SelectionMask.diskRectangles(radius: 2).map { [$0.0, $0.1] } == [[2, 1], [1, 2]])
        // Every pixel of the disk is in one of the rectangles, and nothing outside it is.
        for radius in [3, 7, 12] {
            let rectangles = SelectionMask.diskRectangles(radius: radius)
            let limit = (Double(radius) + 0.5) * (Double(radius) + 0.5)
            for dy in -radius - 1...radius + 1 {
                for dx in -radius - 1...radius + 1 {
                    let inDisk = Double(dx * dx + dy * dy) <= limit
                    let covered = rectangles.contains { abs(dx) <= $0.0 && abs(dy) <= $0.1 }
                    #expect(inDisk == covered, "radius \(radius) at (\(dx), \(dy))")
                }
            }
        }
    }

    @Test func expandGrowsIntoARoundShape() {
        let dot = mask(["#"], at: IntPoint(x: 10, y: 10))
        let area = IntRect(x: 7, y: 7, width: 7, height: 7)
        #expect(rows(dot.expanded(by: 1, clippedTo: canvas), area) == [
            ".......",
            ".......",
            "..###..",
            "..###..",
            "..###..",
            ".......",
            ".......",
        ])
        #expect(rows(dot.expanded(by: 2, clippedTo: canvas), area) == [
            ".......",
            "..###..",
            ".#####.",
            ".#####.",
            ".#####.",
            "..###..",
            ".......",
        ])
    }

    @Test func contractShrinksFromEveryEdge() {
        let block = mask(Array(repeating: "#######", count: 7))
        let area = IntRect(x: 5, y: 5, width: 7, height: 7)
        #expect(rows(block.contracted(by: 2, clippedTo: canvas), area) == [
            ".......",
            ".......",
            "..###..",
            "..###..",
            "..###..",
            ".......",
            ".......",
        ])
        #expect(block.contracted(by: 4, clippedTo: canvas) == nil)
    }

    @Test func aSoftEdgeMovesAndStaysSoft() {
        let ramp = mask(Array(repeating: "..2468####", count: 3), at: IntPoint(x: 5, y: 8))
        let row = IntRect(x: 5, y: 9, width: 10, height: 1)
        #expect(rows(ramp.expanded(by: 1, clippedTo: canvas), row) == [".2468#####"])
        #expect(rows(ramp.contracted(by: 1, clippedTo: canvas), row) == ["...2468##."])
    }

    @Test func atTheCanvasEdgeTheSelectionCarriesOn() throws {
        let all = try #require(SelectionMask.rectangle(canvas, clippedTo: canvas))
        let contracted = try #require(all.contracted(by: 3, clippedTo: canvas))
        #expect(contracted.bounds == canvas && !contracted.values.contains { $0 != 255 })
        // Growing stops at the canvas's edge.
        let corner = mask(["##", "##"], at: IntPoint(x: 0, y: 0))
        #expect(corner.expanded(by: 3, clippedTo: canvas)?.bounds == IntRect(x: 0, y: 0, width: 5, height: 5))
    }

    @Test func expandingThenContractingAConvexShapeGivesItBack() throws {
        let block = mask(Array(repeating: "######", count: 4))
        let back = try #require(block.expanded(by: 3, clippedTo: canvas)?.contracted(by: 3, clippedTo: canvas))
        #expect(back.bounds == block.bounds && back.values == block.values)
    }

    @Test func smoothFillsNotchesAndRemovesSpecks() {
        let ragged = mask([
            "#######.....",
            "#######..#..",
            "###.###.....",
            "#######.....",
            "#######.....",
        ])
        let area = IntRect(x: 5, y: 5, width: 12, height: 5)
        let smooth = rows(ragged.smoothed(radius: 1, clippedTo: canvas), area)
        // The notch fills in and the speck goes. At 1 px the round area is a 3 × 3 square, so square corners stay.
        #expect(smooth == [
            "#######.....",
            "#######.....",
            "#######.....",
            "#######.....",
            "#######.....",
        ])
    }

    @Test func smoothRoundsOffCorners() throws {
        let block = mask(Array(repeating: "#########", count: 9))
        let smooth = try #require(block.smoothed(radius: 3, clippedTo: canvas))
        #expect(smooth[5, 5] == 0 && smooth[13, 13] == 0)
        #expect(smooth[9, 9] == 255 && smooth[9, 5] == 255 && smooth[5, 9] == 255)
    }

    @Test func modifyingKeepsEverySelectionWithinTheCanvas() throws {
        let edge = mask(["####", "####"], at: IntPoint(x: 16, y: 18))
        let grown = try #require(edge.expanded(by: 5, clippedTo: canvas))
        #expect(canvas.contains(grown.bounds))
    }

    /// Every pixel of the canvas the slow, plain way: the most (or least) value over the round area, leaving out
    /// pixels beyond the canvas.
    private func reference(_ mask: SelectionMask, radius: Int, growing: Bool) -> [UInt8] {
        let limit = (Double(radius) + 0.5) * (Double(radius) + 0.5)
        var out: [UInt8] = []
        for y in canvas.minY..<canvas.maxY {
            for x in canvas.minX..<canvas.maxX {
                var value: UInt8 = growing ? 0 : 255
                for dy in -radius...radius {
                    for dx in -radius...radius where Double(dx * dx + dy * dy) <= limit {
                        let point = IntPoint(x: x + dx, y: y + dy)
                        guard canvas.contains(point) else { continue }
                        value = growing ? max(value, mask[point.x, point.y]) : min(value, mask[point.x, point.y])
                    }
                }
                out.append(value)
            }
        }
        return out
    }

    private func everyPixel(_ mask: SelectionMask?) -> [UInt8] {
        (canvas.minY..<canvas.maxY).flatMap { y in (canvas.minX..<canvas.maxX).map { x in mask?[x, y] ?? 0 } }
    }

    @Test(arguments: [false, true])
    func matchesThePlainWayOnRandomSelections(soft: Bool) {
        var generator = SystemRandomNumberGenerator()
        for trial in 0..<12 {
            let bounds = IntRect(x: trial % 4, y: trial % 3, width: 12 + trial % 5, height: 10 + trial % 6)
            let values = (0..<bounds.area).map { _ -> UInt8 in
                let selected = Int.random(in: 0..<10, using: &generator) < 6
                return soft ? (selected ? UInt8.random(in: 1...255, using: &generator) : 0) : (selected ? 255 : 0)
            }
            let mask = SelectionMask(bounds: bounds, values: values)
            for radius in [1, 2, 3, 5] {
                #expect(everyPixel(mask.expanded(by: radius, clippedTo: canvas)) == reference(mask, radius: radius, growing: true),
                        "expand \(radius), trial \(trial)")
                #expect(everyPixel(mask.contracted(by: radius, clippedTo: canvas)) == reference(mask, radius: radius, growing: false),
                        "contract \(radius), trial \(trial)")
            }
        }
    }
}
