import Testing
@testable import ColorbeeCore

/// The local brushes, the Clone Stamp and Smudge (FR-4.6).
struct RetouchStrokeTests {
    private func canvas(_ fill: Pixel = Pixel(r: 128, g: 128, b: 128)) -> (Canvas, History) {
        (Canvas(size: IntSize(width: 120, height: 80), colorSpace: Canvas.defaultColorSpace, background: fill), History(byteBudget: .max))
    }

    /// One stroke from `a` to `b` (and back, if `back`), hard-edged at full strength unless asked.
    @discardableResult
    private func stroke(_ kind: RetouchStroke.Kind, on canvas: Canvas, history: History, from a: Point2D, to b: Point2D,
                        diameter: Double = 20, hardness: Double = 1, strength: Double = 1, back: Bool = false) -> RetouchStroke {
        let edit = history.beginEdit("Retouch", on: canvas)
        let stroke = RetouchStroke(diameter: diameter, hardness: hardness, strength: strength, kind: kind, layer: canvas.activeLayer, edit: edit)
        stroke.move(to: a)
        stroke.move(to: b)
        if back { stroke.move(to: a) }
        history.commit(edit)
        return stroke
    }

    @Test func lightenAndDarkenChangeTheirRangeOfTones() {
        let (lit, history) = canvas()
        stroke(.adjust(.lighten(.midtones)), on: lit, history: history, from: Point2D(x: 30, y: 40), to: Point2D(x: 60, y: 40))
        #expect(lit.activeLayer.buffer[45, 40] == Pixel(r: 204, g: 204, b: 204))
        #expect(lit.activeLayer.buffer[100, 40] == Pixel(r: 128, g: 128, b: 128))
        let (dark, darkHistory) = canvas()
        stroke(.adjust(.darken(.midtones)), on: dark, history: darkHistory, from: Point2D(x: 30, y: 40), to: Point2D(x: 60, y: 40))
        #expect(dark.activeLayer.buffer[45, 40] == Pixel(r: 52, g: 52, b: 52))
        // A mid gray isn't a highlight, so Lighten on Highlights leaves it nearly alone.
        let (highlights, highlightHistory) = canvas()
        stroke(.adjust(.lighten(.highlights)), on: highlights, history: highlightHistory, from: Point2D(x: 30, y: 40), to: Point2D(x: 60, y: 40))
        #expect(highlights.activeLayer.buffer[45, 40].r < 160)
    }

    @Test func goingOverAPlaceAgainInOneStrokeDoesntAddUpButANewStrokeDoes() {
        let (canvas, history) = canvas()
        stroke(.adjust(.darken(.midtones)), on: canvas, history: history, from: Point2D(x: 30, y: 40), to: Point2D(x: 60, y: 40), strength: 0.5, back: true)
        let once = canvas.activeLayer.buffer[45, 40]
        #expect(once == Pixel(r: 90, g: 90, b: 90))
        stroke(.adjust(.darken(.midtones)), on: canvas, history: history, from: Point2D(x: 30, y: 40), to: Point2D(x: 60, y: 40), strength: 0.5)
        #expect(canvas.activeLayer.buffer[45, 40].r < once.r)
    }

    @Test func desaturateTurnsColorGrayAndKeepsAlpha() {
        let (canvas, history) = canvas(Pixel(r: 200, g: 40, b: 40, a: 180))
        stroke(.adjust(.desaturate), on: canvas, history: history, from: Point2D(x: 30, y: 40), to: Point2D(x: 60, y: 40))
        let pixel = canvas.activeLayer.buffer[45, 40]
        #expect(pixel.r == pixel.g && pixel.g == pixel.b && pixel.a == 180)
    }

    @Test func blurSoftensAndSharpenStrengthensAnEdge() {
        func edged() -> (Canvas, History) {
            let (canvas, history) = canvas()
            canvas.activeLayer.buffer.fill(.black, in: IntRect(x: 0, y: 0, width: 60, height: 80))
            canvas.activeLayer.buffer.fill(.white, in: IntRect(x: 60, y: 0, width: 60, height: 80))
            return (canvas, history)
        }
        let (blurred, blurHistory) = edged()
        stroke(.adjust(.blur), on: blurred, history: blurHistory, from: Point2D(x: 60, y: 20), to: Point2D(x: 60, y: 60))
        #expect(blurred.activeLayer.buffer[59, 40].r > 0 && blurred.activeLayer.buffer[60, 40].r < 255)
        let (sharp, sharpHistory) = edged()
        sharp.activeLayer.buffer.fill(Pixel(r: 100, g: 100, b: 100), in: IntRect(x: 0, y: 0, width: 60, height: 80))
        sharp.activeLayer.buffer.fill(Pixel(r: 150, g: 150, b: 150), in: IntRect(x: 60, y: 0, width: 60, height: 80))
        stroke(.adjust(.sharpen), on: sharp, history: sharpHistory, from: Point2D(x: 60, y: 20), to: Point2D(x: 60, y: 60))
        #expect(sharp.activeLayer.buffer[59, 40].r < 100 && sharp.activeLayer.buffer[60, 40].r > 150)
    }

    /// The Clone Stamp copies the pixels as they were before the stroke, so a short offset doesn't smear.
    @Test func cloningCopiesTheOriginalPixelsAtTheOffset() {
        let (canvas, history) = canvas()
        for x in 0..<120 { canvas.activeLayer.buffer.fill(Pixel(r: UInt8(x * 2), g: 0, b: 0), in: IntRect(x: x, y: 0, width: 1, height: 80)) }
        stroke(.clone(offset: IntPoint(x: 5, y: 0), source: nil), on: canvas, history: history, from: Point2D(x: 30, y: 40), to: Point2D(x: 80, y: 40))
        for x in 30..<80 { #expect(canvas.activeLayer.buffer[x, 40].r == UInt8((x + 5) * 2)) }
    }

    @Test func cloningFromAnotherBufferReadsIt() {
        let (canvas, history) = canvas()
        let source = PixelBuffer(width: 120, height: 80, fill: Pixel(r: 0, g: 200, b: 0))
        stroke(.clone(offset: IntPoint(x: 0, y: 0), source: source), on: canvas, history: history, from: Point2D(x: 30, y: 40), to: Point2D(x: 60, y: 40))
        #expect(canvas.activeLayer.buffer[45, 40] == Pixel(r: 0, g: 200, b: 0))
    }

    @Test func aRetouchStrokeUndoesExactly() {
        let (canvas, history) = canvas()
        canvas.activeLayer.buffer.fill(Pixel(r: 30, g: 90, b: 160), in: IntRect(x: 20, y: 20, width: 40, height: 30))
        let before = canvas.activeLayer.buffer.contentHash()
        stroke(.adjust(.saturate), on: canvas, history: history, from: Point2D(x: 10, y: 30), to: Point2D(x: 90, y: 30), hardness: 0.3, strength: 0.7)
        #expect(canvas.activeLayer.buffer.contentHash() != before)
        history.undo(on: canvas)
        #expect(canvas.activeLayer.buffer.contentHash() == before)
    }

    @Test func smudgeDragsColorAlongTheStroke() {
        func smudged(strength: Double) -> Pixel {
            let (canvas, history) = canvas(.white)
            canvas.activeLayer.buffer.fill(Pixel(r: 220, g: 0, b: 0), in: IntRect(x: 0, y: 0, width: 30, height: 80))
            let edit = history.beginEdit("Smudge", on: canvas)
            let stroke = SmudgeStroke(diameter: 16, hardness: 0.5, strength: strength, layer: canvas.activeLayer, edit: edit)
            stroke.move(to: Point2D(x: 20, y: 40))
            stroke.move(to: Point2D(x: 70, y: 40))
            history.commit(edit)
            return canvas.activeLayer.buffer[50, 40]
        }
        let weak = smudged(strength: 0.2), strong = smudged(strength: 0.9)
        // Red has been dragged into the white, further with more strength.
        #expect(strong.g < 255 && strong.g < weak.g)
    }

    @Test func matchToneEvensACopiedPatchWithItsSurroundings() throws {
        let (canvas, history) = canvas(Pixel(r: 180, g: 180, b: 180))
        canvas.activeLayer.buffer.fill(Pixel(r: 90, g: 90, b: 90), in: IntRect(x: 0, y: 0, width: 30, height: 80))
        let painted = stroke(.clone(offset: IntPoint(x: -60, y: 0), source: nil), on: canvas, history: history,
                             from: Point2D(x: 75, y: 30), to: Point2D(x: 75, y: 50))
        #expect(canvas.activeLayer.buffer[75, 40].r == 90)
        let mask = try #require(painted.coverage)
        let edit = history.beginEdit("Match Tone", on: canvas)
        ToneMatch.apply(to: canvas.activeLayer, in: mask, edit: edit)
        history.commit(edit)
        #expect(abs(Int(canvas.activeLayer.buffer[75, 40].r) - 180) < 8)
    }
}
