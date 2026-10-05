import CoreGraphics
import Foundation
import Testing
@testable import ColorbeeCore

/// Regression tests for the findings of cloud review E (Docs/Review/findings-E.md), which Leah confirmed by hand.
struct ReviewETests {
    private func draw(_ lines: [(String, Point2D)], on canvas: Canvas, font: String = "Helvetica", size: Double = 16) {
        let edit = History(byteBudget: .max).beginEdit("Text", on: canvas)
        for (text, origin) in lines {
            let spec = TextSpec(text: text, origin: origin, fontFamily: font, fontSize: size, color: .black)
            if let rendered = TextRenderer.render(spec, colorSpace: canvas.colorSpace, clippedTo: canvas.bounds) {
                Compositing.draw(rendered.pixels, at: rendered.origin, onto: canvas.activeLayer, edit: edit)
            }
        }
    }

    private func scan(_ canvas: Canvas) async throws -> TextScan {
        try await TextScan.read(ImageCodec.makeCGImage(canvas.flattened(), colorSpace: canvas.colorSpace))
    }

    // MARK: Finding 5: tall images and transparent backgrounds

    @Test func readsSmallTextAllTheWayDownATallImage() async throws {
        let canvas = Canvas(size: IntSize(width: 1200, height: 10_000), colorSpace: Canvas.defaultColorSpace, background: .white)
        draw((0..<10).map { ("Contact person\($0).name@example.com today", Point2D(x: 60, y: Double(400 + $0 * 1000))) }, on: canvas)
        let emails = try await scan(canvas).matches(for: RedactionPattern.builtIns).filter { $0.patternName == "Email" }
        #expect(emails.count == 10, "found \(emails.map { "\($0.text) \($0.rect)" })")
        for index in 0..<10 {
            let y = 400 + index * 1000
            #expect(emails.contains { $0.rect.minY <= y + 4 && $0.rect.maxY >= y + 14 }, "email \(index)")
        }
    }

    @Test func readsDarkTextOnATransparentBackground() async throws {
        let canvas = Canvas(size: IntSize(width: 1200, height: 800), colorSpace: Canvas.defaultColorSpace, background: .clear)
        draw([("Write to alex.morgan@example.com", Point2D(x: 60, y: 200)), ("Call +1 (415) 555-0148", Point2D(x: 60, y: 400))], on: canvas)
        let matches = try await scan(canvas).matches(for: RedactionPattern.builtIns)
        #expect(matches.contains { $0.patternName == "Email" })
        #expect(matches.contains { $0.patternName == "Phone" })
    }

    // MARK: Finding 7: Stripe-style keys

    @Test(arguments: ["sk_test_FAKE0000EXAMPLE1234abcd", "sk test FAKE0000EXAMPLE1234abcd", "sktestFAKE0000EXAMPLE1234abcd",
                      "sk_test FAKE0000EXAMPLE1234abcd", "sk_live_51Hx9TqL2vR8mZ3kP0aYwXc", "rk_live_ABCD1234efgh"])
    func keyPatternAllowsTheWaysVisionReadsUnderscores(key: String) {
        let found = AutoRedact.matches(in: "API key:  \(key)", patterns: RedactionPattern.builtIns)
        #expect(found.contains { $0.name == "API key" }, "\(key)")
    }

    @Test func findsAStripeKeyInMonospacedText() async throws {
        let canvas = Canvas(size: IntSize(width: 1000, height: 200), colorSpace: Canvas.defaultColorSpace, background: .white)
        draw([("API key:  sk_test_FAKE0000EXAMPLE1234abcd", Point2D(x: 40, y: 80))], on: canvas, font: "Menlo", size: 17)
        let scan = try await scan(canvas)
        let keys = scan.matches(for: RedactionPattern.builtIns).filter { $0.patternName == "API key" }
        #expect(!keys.isEmpty, "Vision read \(scan.text)")
    }
}

/// Findings 1, 3 and 4: what Apply changes.
struct AutoRedactApplyTests {
    private let context = SelectionContext(color2: .white)
    private let box = IntRect(x: 10, y: 10, width: 40, height: 12)

    /// A white Background with black-and-white stripes ("text") in `box`, plus an empty Layer 1 on top, active.
    private func layered() -> (Canvas, History) {
        let canvas = Canvas(size: IntSize(width: 200, height: 200), colorSpace: Canvas.defaultColorSpace, background: .white)
        for y in box.minY..<box.maxY {
            for x in box.minX..<box.maxX where x % 3 == 0 { canvas.layers[0].buffer.row(y)[x] = .black }
        }
        let history = History(byteBudget: 512 << 20)
        LayerActions.add(canvas: canvas, history: history, context: context)
        return (canvas, history)
    }

    private func match(_ rect: IntRect) -> RedactionMatch { RedactionMatch(patternName: "Email", text: "a@b.co", rect: rect) }

    @Test(arguments: [RedactionTreatment.blur, .pixelate, .solidFill])
    func textOnALayerBelowTheActiveOneIsRedacted(treatment: RedactionTreatment) {
        let (canvas, history) = layered()
        let before = canvas.flattened().pixels(in: box)
        let outcome = AutoRedact.apply([match(box)], treatment: treatment, fill: .black, canvas: canvas, history: history)
        #expect(outcome == .redacted)
        #expect(canvas.flattened().pixels(in: box) != before)
        history.undo(on: canvas)
        #expect(canvas.flattened().pixels(in: box) == before)
    }

    @Test func solidFillCoversTextOnALayerAboveTheActiveOne() {
        let (canvas, history) = layered()
        // Text on the top layer; the Background (below it) is active.
        canvas.layers[1].buffer.fill(.black, in: IntRect(x: 20, y: 12, width: 4, height: 8))
        canvas.activeLayerIndex = 0
        _ = AutoRedact.apply([match(box)], treatment: .solidFill, fill: Pixel(r: 255, g: 0, b: 0), canvas: canvas, history: history)
        #expect(canvas.flattened().pixels(in: box).allSatisfy { $0 == Pixel(r: 255, g: 0, b: 0) })
    }

    @Test func aLockedLayerWithPixelsUnderABoxStopsEverything() {
        let (canvas, history) = layered()
        canvas.layers[0].isLocked = true
        let revision = history.revision
        let before = canvas.flattened().contentHash()
        #expect(AutoRedact.apply([match(box)], treatment: .solidFill, fill: .black, canvas: canvas, history: history) == .locked(layerName: "Background"))
        #expect(canvas.flattened().contentHash() == before)
        #expect(history.revision == revision)
        // Checked on its own before redacting any page (stage 10b).
        #expect(AutoRedact.lockedLayer(under: [match(box)], canvas: canvas)?.name == "Background")
        canvas.layers[0].isLocked = false
        #expect(AutoRedact.lockedLayer(under: [match(box)], canvas: canvas) == nil)
    }

    @Test func aLockedLayerWithNothingUnderTheBoxesDoesntMatter() {
        let (canvas, history) = layered()
        canvas.layers[1].isLocked = true
        #expect(AutoRedact.apply([match(box)], treatment: .solidFill, fill: .black, canvas: canvas, history: history) == .redacted)
    }

    /// Finding 3: each item at the strength for its own height, not the median.
    @Test func eachItemIsPixelatedForItsOwnHeight() {
        let canvas = Canvas(size: IntSize(width: 400, height: 400), colorSpace: Canvas.defaultColorSpace, background: .white)
        for y in 0..<400 { for x in 0..<400 where (x / 2 + y / 3) % 2 == 0 { canvas.layers[0].buffer.row(y)[x] = .black } }
        let expected = canvas.copy()
        let small = (0..<3).map { IntRect(x: 10, y: 10 + $0 * 30, width: 60, height: 20) }
        let large = IntRect(x: 150, y: 150, width: 200, height: 120)
        let history = History(byteBudget: 512 << 20)
        _ = AutoRedact.apply(small.map(match) + [match(large)], treatment: .pixelate, fill: .black, canvas: canvas, history: history)
        let edit = History(byteBudget: 512 << 20).beginEdit("Expected", on: expected)
        Effects.apply(.pixelate(cellSize: 40), to: expected.layers[0], selection: .rectangle(large, clippedTo: expected.bounds), edit: edit)
        #expect(canvas.layers[0].buffer.pixels(in: large) == expected.layers[0].buffer.pixels(in: large))
    }

    /// Finding 4: an item that touches the selection is kept, and redacted in full.
    @Test func itemsTouchingTheSelectionAreKeptWhole() throws {
        let selection = try #require(SelectionMask.rectangle(IntRect(x: 0, y: 0, width: 45, height: 200), clippedTo: IntRect(x: 0, y: 0, width: 200, height: 200)))
        let mostlyOutside = match(IntRect(x: 40, y: 50, width: 60, height: 12))
        let outside = match(IntRect(x: 60, y: 90, width: 60, height: 12))
        #expect(AutoRedact.matches([mostlyOutside, outside], touching: selection) == [mostlyOutside])
        #expect(AutoRedact.matches([mostlyOutside, outside], touching: nil) == [mostlyOutside, outside])
        let (canvas, history) = layered()
        _ = AutoRedact.apply([match(box)], treatment: .solidFill, fill: Pixel(r: 0, g: 0, b: 255), canvas: canvas, history: history)
        #expect(canvas.flattened().pixels(in: box).allSatisfy { $0 == Pixel(r: 0, g: 0, b: 255) })
    }
}

/// Leah's E1 Screenshot (2026-10-04): Vision read "sk test" and "_FAKE0000EXAMPLE1234abcd" as two pieces.
struct SplitLineTests {
    @Test func piecesSideBySideFormOneRow() {
        let tile = IntRect(x: 0, y: 0, width: 1000, height: 400)
        let rows = TextScan.rows([
            (tile, CGRect(x: 500, y: 100, width: 300, height: 24)),   // "_FAKE0000EXAMPLE1234abcd"
            (tile, CGRect(x: 40, y: 100, width: 140, height: 24)),    // "API key:"
            (tile, CGRect(x: 400, y: 102, width: 90, height: 22)),    // "sk test"
            (tile, CGRect(x: 40, y: 160, width: 140, height: 24)),    // "Server:", the next line
        ])
        // The two key pieces join; the label, a column away, and the next line stay apart.
        #expect(rows.contains([2, 0]))
        #expect(rows.contains([1]) && rows.contains([3]))
        #expect(rows.last == [3])
    }

    @Test func theKeyMatchesWhenItsPiecesAreJoined() {
        let found = AutoRedact.matches(in: "API key: sk test _FAKE0000EXAMPLE1234abcd", patterns: RedactionPattern.builtIns)
        #expect(found.contains { $0.name == "API key" })
    }
}
