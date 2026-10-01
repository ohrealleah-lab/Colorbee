import CoreGraphics
import Testing
@testable import ColorbeeCore

struct AutoRedactPatternTests {
    private let patterns = RedactionPattern.builtIns

    private func names(in text: String) -> [String] {
        AutoRedact.matches(in: text, patterns: patterns).map(\.name)
    }

    private func matched(in text: String) -> [String] {
        AutoRedact.matches(in: text, patterns: patterns).map { String(text[$0.range]) }
    }

    @Test func findsEmails() {
        #expect(matched(in: "Contact priya.natarajan@northwind.io today") == ["priya.natarajan@northwind.io"])
    }

    @Test func findsPhoneNumbers() {
        #expect(matched(in: "Call +1 (415) 555-0148 now") == ["+1 (415) 555-0148"])
        #expect(names(in: "or 415.555.0148") == ["Phone"])
    }

    @Test func findsCardNumbersThatPassTheChecksum() {
        #expect(names(in: "Card 4242 4242 4242 4242 on file") == ["Card number"])
        #expect(names(in: "Order 4242 4242 4242 4241").contains("Card number") == false)
    }

    @Test func findsAPIKeys() {
        #expect(matched(in: "key=sk_live_51Hx9TqL2vR8mZ3kP0aYw") == ["sk_live_51Hx9TqL2vR8mZ3kP0aYw"])
        #expect(names(in: "AKIAIOSFODNN7EXAMPLE") == ["API key"])
        #expect(names(in: "token ghp_abcdefghijklmnopqrstuvwxyz0123456789") == ["API key"])
    }

    @Test func findsIPAddressesAndURLs() {
        #expect(names(in: "Server 10.0.12.255 down") == ["IP address"])
        #expect(names(in: "Not an IP: 999.1.1.1") == [])
        #expect(matched(in: "See https://example.com/a?b=1 please") == ["https://example.com/a?b=1"])
    }

    @Test func ordinaryTextHasNoMatches() {
        #expect(names(in: "Payment failed (502). Please try again.") == [])
    }

    @Test func disabledPatternsAreSkipped() {
        var custom = patterns
        custom[0].isEnabled = false
        #expect(AutoRedact.matches(in: "a@b.co", patterns: custom).isEmpty)
    }

    @Test func customPatternsWork() {
        let ticket = RedactionPattern(name: "Ticket", expression: #"\bCB-\d{4}\b"#)
        #expect(ticket.isValid)
        #expect(AutoRedact.matches(in: "See CB-1234", patterns: [ticket]).map(\.name) == ["Ticket"])
        #expect(!RedactionPattern(name: "Broken", expression: "(unclosed").isValid)
    }

    @Test func maskCoversEveryRect() {
        let mask = AutoRedact.mask(covering: [IntRect(x: 0, y: 0, width: 10, height: 5), IntRect(x: 50, y: 50, width: 5, height: 5)],
                                   in: IntRect(x: 0, y: 0, width: 100, height: 100))
        #expect(mask?.connectedRegions().count == 2)
    }
}

struct AutoRedactRecognitionTests {
    /// Renders text with Colorbee's own text renderer, then reads it back with Vision.
    private func image(lines: [String]) throws -> (CGImage, Canvas) {
        let canvas = Canvas(size: IntSize(width: 1200, height: 80 + 60 * lines.count), colorSpace: Canvas.defaultColorSpace, background: .white)
        let edit = History(byteBudget: .max).beginEdit("Text", on: canvas)
        for (index, line) in lines.enumerated() {
            let spec = TextSpec(text: line, origin: Point2D(x: 40, y: Double(40 + index * 60)), fontFamily: "Helvetica", fontSize: 32, color: .black)
            if let rendered = TextRenderer.render(spec, colorSpace: canvas.colorSpace, clippedTo: canvas.bounds) {
                Compositing.draw(rendered.pixels, at: rendered.origin, onto: canvas.activeLayer, edit: edit)
            }
        }
        return (try ImageCodec.makeCGImage(canvas.flattened(), colorSpace: canvas.colorSpace), canvas)
    }

    @Test func findsAndLocatesSensitiveTextInAnImage() async throws {
        let (cgImage, canvas) = try image(lines: [
            "Customer report from jordan.ellis@northwind.io",
            "Support line +1 (415) 555-0148",
            "Payment failed. Please try again.",
        ])
        let scan = try await TextScan.read(cgImage)
        let matches = scan.matches(for: RedactionPattern.builtIns)

        let email = try #require(matches.first { $0.patternName == "Email" })
        #expect(email.text == "jordan.ellis@northwind.io")
        // The email is on the first line, toward its right end.
        #expect(email.rect.minY < 80 && email.rect.maxY > 50)
        #expect(email.rect.minX > 300)
        #expect(canvas.bounds.contains(email.rect))

        let phone = try #require(matches.first { $0.patternName == "Phone" })
        #expect(phone.rect.minY > 90 && phone.rect.minY < 140)
        #expect(matches.count == 2)
    }

    @Test func offsetPlacesMatchesOnTheCanvas() async throws {
        let (cgImage, _) = try image(lines: ["Mail me at a.person@example.com"])
        let shifted = try await TextScan.read(cgImage, offset: IntPoint(x: 500, y: 300))
        let plain = try await TextScan.read(cgImage)
        let shiftedRect = try #require(shifted.matches(for: RedactionPattern.builtIns).first?.rect)
        let plainRect = try #require(plain.matches(for: RedactionPattern.builtIns).first?.rect)
        #expect(shiftedRect == plainRect.offsetBy(dx: 500, dy: 300))
    }
}
