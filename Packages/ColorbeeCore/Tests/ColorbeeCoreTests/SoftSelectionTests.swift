import Testing
@testable import ColorbeeCore

/// Soft-edged selections (FR-3.4).
struct SoftSelectionTests {
    private let canvasBounds = IntRect(x: 0, y: 0, width: 100, height: 100)
    private let context = SelectionContext(color2: .white)

    private func feathered(_ rect: IntRect = IntRect(x: 30, y: 30, width: 40, height: 40), radius: Double = 8) throws -> SelectionMask {
        try #require(SelectionMask.rectangle(rect, clippedTo: canvasBounds)?.feathered(radius: radius, clippedTo: canvasBounds))
    }

    @Test func featheringSoftensTheEdgeEvenly() throws {
        let mask = try feathered()
        #expect(mask[50, 50] == 255)
        #expect(mask[10, 50] == 0)
        // At the original edge, about half selected, and fading outward.
        #expect((100...155).contains(mask[30, 50]))
        #expect(mask[26, 50] < mask[30, 50] && mask[30, 50] < mask[34, 50])
        #expect(mask.isSoft && !mask.hardened().isSoft)
    }

    @Test func aSelectionReachingTheCanvasEdgeStaysSelectedThere() throws {
        let mask = try feathered(IntRect(x: 0, y: 0, width: 100, height: 100))
        #expect(mask[0, 0] == 255 && mask[50, 0] == 255)
    }

    @Test func softSelectionsCombine() throws {
        let soft = try feathered()
        let hard = try #require(SelectionMask.rectangle(IntRect(x: 0, y: 0, width: 30, height: 100), clippedTo: canvasBounds))
        let edge = soft[30, 50]
        #expect(SelectionMask.combine(soft, with: hard, mode: .add)?[29, 50] == 255)
        #expect(SelectionMask.combine(soft, with: hard, mode: .add)?[30, 50] == edge)
        #expect(SelectionMask.combine(soft, with: hard, mode: .intersect)?[29, 50] == soft[29, 50])
        #expect(SelectionMask.combine(soft, with: hard, mode: .subtract)?[29, 50] ?? 0 == 0)
        #expect(SelectionMask.combine(soft, with: hard, mode: .subtract)?[30, 50] == edge)
        #expect(soft.inverted(in: canvasBounds)?[30, 50] == 255 - edge)
        // Each region keeps its soft edge.
        #expect(soft.connectedRegions().first?[30, 50] == edge)
    }

    private func gray() -> (Canvas, History) {
        (Canvas(size: IntSize(width: 100, height: 100), colorSpace: Canvas.defaultColorSpace, background: Pixel(r: 200, g: 200, b: 200)),
         History(byteBudget: .max))
    }

    @Test func anEffectChangesAPartlySelectedPixelPartly() throws {
        let (canvas, history) = gray()
        let mask = try feathered()
        let edit = history.beginEdit("Fill", on: canvas)
        Effects.apply(.solidFill(.black), to: canvas.activeLayer, selection: mask, edit: edit)
        #expect(canvas.activeLayer.buffer[50, 50] == .black)
        let edge = canvas.activeLayer.buffer[30, 50].r
        #expect(edge > 60 && edge < 140)
        #expect(canvas.activeLayer.buffer[10, 50].r == 200)
    }

    @Test func deleteCopyAndFillFollowTheSoftEdge() throws {
        let (canvas, history) = gray()
        let mask = try feathered()
        canvas.selection = .marquee(mask)
        let copied = try #require(SelectionActions.selectedPixels(canvas: canvas, context: context))
        #expect(copied[50 - mask.bounds.minX, 50 - mask.bounds.minY].a == 255)
        #expect(copied[30 - mask.bounds.minX, 50 - mask.bounds.minY].a == mask[30, 50])

        let edit = history.beginEdit("Fill", on: canvas)
        FloodFill.fill(layer: canvas.activeLayer, at: IntPoint(x: 50, y: 50), with: .black, tolerance: 0, selection: mask, edit: edit)
        history.commit(edit)
        #expect(canvas.activeLayer.buffer[50, 50] == .black)
        #expect(canvas.activeLayer.buffer[30, 50].r > 50 && canvas.activeLayer.buffer[30, 50].r < 150)

        // Delete on a transparent layer leaves the partly selected pixels partly there.
        LayerActions.add(canvas: canvas, history: history, context: context)
        canvas.activeLayer.buffer.fill(Pixel(r: 0, g: 0, b: 255), in: canvasBounds)
        canvas.selection = .marquee(mask)
        SelectionActions.deleteSelection(canvas: canvas, history: history, context: context)
        let left = canvas.activeLayer.buffer[30, 50]
        #expect(left.b == 255 && abs(Int(left.a) - (255 - Int(mask[30, 50]))) <= 1)
        #expect(canvas.activeLayer.buffer[50, 50].a == 0)
    }

    @Test func liftingTakesAPartlySelectedPixelPartly() throws {
        let (canvas, history) = gray()
        LayerActions.add(canvas: canvas, history: history, context: context)
        canvas.activeLayer.buffer.fill(Pixel(r: 255, g: 0, b: 0), in: canvasBounds)
        let mask = try feathered()
        let edit = history.beginEdit("Move", on: canvas)
        let floating = try #require(FloatingSelection.lift(from: canvas.activeLayer, selection: mask, holeFill: .clear, edit: edit))
        let x = 30 - floating.destination.minX, y = 50 - floating.destination.minY
        #expect(floating.pixels[x, y].a == mask[30, 50])
        #expect(Int(canvas.activeLayer.buffer[30, 50].a) + Int(mask[30, 50]) == 255)
    }

    /// Redaction is never softened: every partly selected pixel is hidden completely.
    @Test func batchRedactHidesEveryPartlySelectedPixelCompletely() throws {
        let (canvas, history) = gray()
        let mask = try feathered()
        #expect(AutoRedact.apply(.solidFill(.black), in: mask, canvas: canvas, history: history) == .redacted)
        for x in 0..<100 where mask[x, 50] > 0 { #expect(canvas.activeLayer.buffer[x, 50] == .black) }
    }
}
