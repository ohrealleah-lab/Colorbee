import Testing
@testable import ColorbeeCore

/// Edit ▸ Color Range… and Luminance Range… (FR-9.7 item 3).
struct SelectionRangeTests {
    /// One pixel per color, in a row.
    private func strip(_ colors: [Pixel]) -> PixelBuffer {
        let buffer = PixelBuffer(width: colors.count, height: 1)
        for (x, color) in colors.enumerated() { buffer.row(0)[x] = color }
        return buffer
    }

    private func amounts(_ mask: SelectionMask?, width: Int) -> [UInt8] {
        (0..<width).map { mask?[$0, 0] ?? 0 }
    }

    @Test func colorRangeSelectsNearColorsAndFadesOut() {
        let sky = Pixel(r: 100, g: 140, b: 200)
        // 0, 20, 40, 70 and 100 levels away in blue; and a green far off.
        let buffer = strip([sky, Pixel(r: 100, g: 140, b: 220), Pixel(r: 100, g: 140, b: 240), Pixel(r: 100, g: 140, b: 130),
                            Pixel(r: 100, g: 140, b: 100), Pixel(r: 40, g: 160, b: 60)])
        // 25% is a range of about 64 levels: fully selected to 32, fading to nothing at 64.
        let mask = ColorRange(colors: [sky], fuzziness: 25).selection(in: buffer)
        let values = amounts(mask, width: 6)
        #expect(values[0] == 255 && values[1] == 255)
        #expect(values[2] > 0 && values[2] < 255)
        #expect(values[3] == 0 && values[4] == 0 && values[5] == 0)
        #expect(mask?.isSoft == true)
    }

    @Test func colorRangeAtZeroTakesOnlyTheExactColor() {
        let red = Pixel(r: 220, g: 30, b: 30)
        let buffer = strip([red, Pixel(r: 221, g: 30, b: 30), red])
        #expect(amounts(ColorRange(colors: [red], fuzziness: 0).selection(in: buffer), width: 3) == [255, 0, 255])
    }

    @Test func moreFuzzinessTakesInMore() {
        let blue = Pixel(r: 40, g: 80, b: 200)
        let buffer = strip([blue, Pixel(r: 40, g: 80, b: 130)])
        #expect(amounts(ColorRange(colors: [blue], fuzziness: 25).selection(in: buffer), width: 2)[1] == 0)
        #expect(amounts(ColorRange(colors: [blue], fuzziness: 60).selection(in: buffer), width: 2)[1] == 255)
    }

    @Test func severalColorsEachSelectTheirOwn() {
        let red = Pixel(r: 220, g: 30, b: 30), green = Pixel(r: 30, g: 200, b: 60), gray = Pixel(r: 128, g: 128, b: 128)
        let buffer = strip([red, green, gray])
        #expect(amounts(ColorRange(colors: [red, green], fuzziness: 10).selection(in: buffer), width: 3) == [255, 255, 0])
        #expect(ColorRange(colors: [], fuzziness: 50).selection(in: buffer) == nil)
    }

    @Test func colorRangeTreatsTransparencyAsTheWandDoes() {
        let clear = Pixel(r: 9, g: 9, b: 9, a: 0), white = Pixel(r: 255, g: 255, b: 255)
        let buffer = strip([Pixel(r: 200, g: 0, b: 0, a: 0), white])
        #expect(amounts(ColorRange(colors: [clear], fuzziness: 0).selection(in: buffer), width: 2) == [255, 0])
        #expect(amounts(ColorRange(colors: [white], fuzziness: 20).selection(in: buffer), width: 2) == [0, 255])
    }

    @Test func luminanceRangeSelectsBetweenItsBoundsAndFades() {
        let ramp = strip((0...10).map { step in
            let v = UInt8(step * 255 / 10)
            return Pixel(r: v, g: v, b: v)
        })
        // Shadows, 0 to 30, with no fade: the darkest four steps (0, 10, 20 and 30).
        let hard = LuminanceRange(lower: 0, upper: 30, smoothness: 0).selection(in: ramp)
        #expect(amounts(hard, width: 11) == [255, 255, 255, 255, 0, 0, 0, 0, 0, 0, 0])
        // With Smoothness, it fades out past 30 rather than stopping.
        let soft = amounts(LuminanceRange(lower: 0, upper: 30, smoothness: 50).selection(in: ramp), width: 11)
        #expect(soft[3] == 255 && soft[4] > 0 && soft[4] < 255 && soft[5] < soft[4])
        #expect(soft[8] == 0 && soft[10] == 0)
        // Highlights mirror it.
        let highlights = amounts(LuminanceRange.highlights.selection(in: ramp), width: 11)
        #expect(highlights[10] == 255 && highlights[0] == 0)
    }

    @Test func luminanceRangeLeavesOutTransparentPixels() {
        let buffer = strip([Pixel(r: 0, g: 0, b: 0, a: 0), Pixel(r: 0, g: 0, b: 0, a: 128), Pixel(r: 0, g: 0, b: 0)])
        #expect(amounts(LuminanceRange.shadows.selection(in: buffer), width: 3) == [0, 128, 255])
    }

    @Test func boundsGivenTheWrongWayRoundStillWork() {
        let buffer = strip([Pixel(r: 128, g: 128, b: 128)])
        #expect(amounts(LuminanceRange(lower: 70, upper: 30, smoothness: 0).selection(in: buffer), width: 1) == [255])
    }
}

/// Edit ▸ Graduated Selection (FR-9.7 item 3).
struct GraduatedSelectionTests {
    @Test func fullAtTheStartFadingToNothingAtTheEnd() throws {
        let bounds = IntRect(x: 0, y: 0, width: 4, height: 20)
        // Down the canvas from y = 5 to y = 15.
        let mask = try #require(GraduatedSelection(start: Point2D(x: 2, y: 5), end: Point2D(x: 2, y: 15)).selection(in: bounds))
        let column = (0..<20).map { mask[1, $0] }
        #expect(column[0...4].allSatisfy { $0 == 255 })
        #expect(column[15...].allSatisfy { $0 == 0 })
        // Smoothly down from full to nothing, half way at y = 10, between rows 9 and 10.
        #expect(zip(column, column.dropFirst()).allSatisfy { $0 >= $1 })
        #expect(column[9] > 128 && column[10] < 128)
        // The fade runs across the line, so every column is the same.
        #expect((0..<20).allSatisfy { mask[0, $0] == mask[3, $0] })
        #expect(mask.isSoft)
    }

    @Test func aDiagonalLineFadesAcrossIt() throws {
        let bounds = IntRect(x: 0, y: 0, width: 10, height: 10)
        let mask = try #require(GraduatedSelection(start: Point2D(x: 0, y: 0), end: Point2D(x: 10, y: 10)).selection(in: bounds))
        #expect(mask[0, 0] > mask[5, 5] && mask[5, 5] > mask[9, 9])
        // Points the same distance along the line match.
        #expect(mask[2, 7] == mask[7, 2])
    }

    @Test func aLineWithNoLengthSelectsNothing() {
        let point = Point2D(x: 3, y: 3)
        #expect(GraduatedSelection(start: point, end: point).selection(in: IntRect(x: 0, y: 0, width: 8, height: 8)) == nil)
    }

    @Test func shiftKeepsTheLineAcrossDownOrAt45Degrees() {
        let anchor = Point2D(x: 10, y: 10)
        #expect(GraduatedSelection.constrained(Point2D(x: 30, y: 12), from: anchor) == Point2D(x: 30, y: 10))
        let down = GraduatedSelection.constrained(Point2D(x: 11, y: 40), from: anchor)
        #expect(abs(down.x - 10) < 1e-9 && abs(down.y - 40) < 1e-9)
        let diagonal = GraduatedSelection.constrained(Point2D(x: 20, y: 22), from: anchor)
        #expect(abs((diagonal.x - 10) - (diagonal.y - 10)) < 1e-9)
    }
}
