import Testing
@testable import ColorbeeCore

struct BrushStrokeTests {
    private func makeCanvas(width: Int = 64, height: Int = 64) -> (Canvas, History) {
        let canvas = Canvas(size: IntSize(width: width, height: height), colorSpace: Canvas.defaultColorSpace, background: .white)
        return (canvas, History(byteBudget: .max))
    }

    /// Paints one stroke and returns the canvas.
    private func paint(_ brush: Brush, diameter: Double = 16, pressure: Double = 1, seed: UInt64 = 1,
                       through points: [Point2D], finish: Bool = true) -> Canvas {
        let (canvas, history) = makeCanvas()
        let edit = history.beginEdit("Brush", on: canvas)
        let stroke = brush.makeStroke(diameter: diameter, color: .black, layer: canvas.activeLayer, edit: edit, seed: seed)
        for point in points { stroke.move(to: point, pressure: pressure) }
        if finish { stroke.finish() }
        return canvas
    }

    private func painted(_ canvas: Canvas, in rect: IntRect? = nil) -> Int {
        let area = rect ?? canvas.bounds
        var count = 0
        for y in area.minY..<area.maxY {
            for x in area.minX..<area.maxX where canvas.activeLayer.buffer[x, y] != .white { count += 1 }
        }
        return count
    }

    private let middle = Point2D(x: 32, y: 32)

    @Test func dabsAreEvenlySpacedWithPressureBlended() {
        var walker = DabWalker()
        _ = walker.walk(to: Point2D(x: 0, y: 0), pressure: 0, spacing: { _ in 2 })
        let dabs = walker.walk(to: Point2D(x: 10, y: 0), pressure: 1, spacing: { _ in 2 })
        #expect(dabs.map(\.center.x) == [2, 4, 6, 8, 10])
        #expect(dabs.map(\.pressure) == [0.2, 0.4, 0.6, 0.8, 1])
        #expect(walker.length == 10)
    }

    @Test func lighterPressureDrawsAThinnerLine() {
        let line = [Point2D(x: 10, y: 32), Point2D(x: 54, y: 32)]
        let full = paint(.round, pressure: 1, through: line)
        let light = paint(.round, pressure: 0.2, through: line)
        #expect(painted(light) < painted(full) / 2)
    }

    @Test(arguments: [Brush.calligraphyForward, .calligraphyBack])
    func calligraphyNibLeansItsOwnWay(brush: Brush) {
        let canvas = paint(brush, diameter: 20, through: [middle])
        let upRight = canvas.activeLayer.buffer[38, 25]
        let downRight = canvas.activeLayer.buffer[38, 38]
        if brush == .calligraphyForward {
            #expect(upRight == .black && downRight == .white)
        } else {
            #expect(downRight == .black && upRight == .white)
        }
    }

    @Test func calligraphyIsThinAlongTheNibAndWideAcrossIt() {
        // A `/` nib dragged up-right leaves a hairline; dragged down-right it leaves a broad band.
        let alongNib = paint(.calligraphyForward, diameter: 20, through: [Point2D(x: 20, y: 44), Point2D(x: 44, y: 20)])
        let acrossNib = paint(.calligraphyForward, diameter: 20, through: [Point2D(x: 20, y: 20), Point2D(x: 44, y: 44)])
        #expect(painted(acrossNib) > painted(alongNib) * 2)
    }

    @Test func airbrushStaysInsideItsCircleAndBuildsUpWhileHeld() {
        let (canvas, history) = makeCanvas()
        let edit = history.beginEdit("Airbrush", on: canvas)
        let stroke = Brush.airbrush.makeStroke(diameter: 30, color: .black, layer: canvas.activeLayer, edit: edit, seed: 7)
        stroke.move(to: middle, pressure: 1)
        let first = painted(canvas)
        for _ in 0..<20 { stroke.hold() }
        let held = painted(canvas)
        #expect(first > 0)
        #expect(held > first * 3)
        #expect(painted(canvas, in: IntRect(x: 0, y: 0, width: 64, height: 16)) == 0)
        #expect(painted(canvas, in: IntRect(x: 0, y: 49, width: 64, height: 15)) == 0)
    }

    @Test func airbrushIsRepeatableWithTheSameSeed() {
        let a = paint(.airbrush, seed: 3, through: [Point2D(x: 10, y: 32), Point2D(x: 50, y: 32)])
        let b = paint(.airbrush, seed: 3, through: [Point2D(x: 10, y: 32), Point2D(x: 50, y: 32)])
        #expect(a.activeLayer.buffer.contentHash() == b.activeLayer.buffer.contentHash())
    }

    /// Height of the painted band in one column.
    private func bandHeight(_ canvas: Canvas, column x: Int) -> Int {
        (0..<canvas.size.height).filter { canvas.activeLayer.buffer[x, $0] != .white }.count
    }

    @Test func oilTapersAtBothEnds() {
        let canvas = paint(.oil, diameter: 20, through: [Point2D(x: 4, y: 32), Point2D(x: 60, y: 32)])
        let middleHeight = bandHeight(canvas, column: 32)
        #expect(bandHeight(canvas, column: 5) < middleHeight)
        #expect(bandHeight(canvas, column: 59) < middleHeight)
    }

    @Test func oilTailIsOnlyTaperedOnceTheStrokeEnds() {
        let line = [Point2D(x: 4, y: 32), Point2D(x: 60, y: 32)]
        // 12px tapers over 18px, so the middle of this 56px line is outside both tapers.
        let open = paint(.oil, diameter: 12, through: line, finish: false)
        let finished = paint(.oil, diameter: 12, through: line)
        #expect(bandHeight(finished, column: 59) < bandHeight(open, column: 59))
        #expect(bandHeight(finished, column: 32) == bandHeight(open, column: 32))
    }

    @Test func oilBristlesLeaveStreaksOfDifferentStrength() {
        let canvas = paint(.oil, diameter: 24, through: [Point2D(x: 4, y: 32), Point2D(x: 60, y: 32)])
        let column = (20..<44).map { canvas.activeLayer.buffer[32, $0].r }
        #expect(Set(column).count > 3)
    }

    @Test func crayonLeavesGapsInsideTheStroke() {
        let canvas = paint(.crayon, diameter: 24, through: [Point2D(x: 8, y: 32), Point2D(x: 56, y: 32)])
        let core = IntRect(x: 16, y: 28, width: 32, height: 8)
        let covered = painted(canvas, in: core)
        #expect(covered > core.area / 3)
        #expect(covered < core.area)
    }

    @Test func pressingHarderFillsMoreOfTheCrayonGrain() {
        let line = [Point2D(x: 8, y: 32), Point2D(x: 56, y: 32)]
        let core = IntRect(x: 20, y: 30, width: 24, height: 4)
        let light = paint(.crayon, diameter: 24, pressure: 0.6, through: line)
        let hard = paint(.crayon, diameter: 24, pressure: 1, through: line)
        #expect(painted(hard, in: core) > painted(light, in: core))
    }

    @Test func naturalPencilIsNeverFullyOpaqueAndHasGrain() {
        let canvas = paint(.naturalPencil, diameter: 12, through: [Point2D(x: 8, y: 32), Point2D(x: 56, y: 32)])
        let row = (16..<48).map { canvas.activeLayer.buffer[$0, 32].r }
        #expect(row.allSatisfy { $0 > 0 && $0 < 255 })
        #expect(Set(row).count > 4)
    }

    @Test func watercolorIsDarkerAtTheRimThanInTheMiddle() {
        let canvas = paint(.watercolor, diameter: 30, through: [Point2D(x: 4, y: 32), Point2D(x: 60, y: 32)])
        let column = (0..<64).map { canvas.activeLayer.buffer[32, $0].r }
        let darkest = column.min() ?? 255
        // Pure black at full strength would be 0; the wash is see-through.
        #expect(darkest > 0)
        #expect(column[32] > darkest + 40)
    }

    @Test func watercolorTransferRisesToTheRimThenSettles() {
        let transfer = BrushStroke.watercolorTransfer
        #expect(transfer[0] == 0)
        #expect(transfer[20] > transfer[200])
        #expect(transfer[255] == transfer[200])
    }

    @Test(arguments: Brush.allCases)
    func everyBrushUndoesExactly(brush: Brush) {
        let (canvas, history) = makeCanvas()
        let original = canvas.activeLayer.buffer.contentHash()
        let edit = history.beginEdit(brush.name, on: canvas)
        let stroke = brush.makeStroke(diameter: 14, color: .black, layer: canvas.activeLayer, edit: edit, seed: 2)
        for x in stride(from: 6.0, through: 58, by: 4) { stroke.move(to: Point2D(x: x, y: 20 + x / 3), pressure: 0.7) }
        stroke.hold()
        stroke.finish()
        history.commit(edit)
        #expect(canvas.activeLayer.buffer.contentHash() != original)
        history.undo(on: canvas)
        #expect(canvas.activeLayer.buffer.contentHash() == original)
    }

    @Test func mirroringSwapsTheCalligraphyNibs() {
        #expect(Brush.calligraphyForward.mirrored == .calligraphyBack)
        #expect(Brush.calligraphyBack.mirrored == .calligraphyForward)
        #expect(Brush.oil.mirrored == .oil)
    }
}
