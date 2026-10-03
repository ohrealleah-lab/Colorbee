import CoreGraphics
import Foundation
import Vision

/// A kind of sensitive text to look for (FR-9.3). Built-in patterns can be turned off; custom ones can be added.
public struct RedactionPattern: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// An ICU regular expression, matched case-insensitively.
    public var expression: String
    public var isEnabled: Bool
    public var isBuiltIn: Bool

    public init(id: UUID = UUID(), name: String, expression: String, isEnabled: Bool = true, isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.expression = expression
        self.isEnabled = isEnabled
        self.isBuiltIn = isBuiltIn
    }

    /// Whether the expression compiles.
    public var isValid: Bool {
        (try? NSRegularExpression(pattern: expression)) != nil
    }

    static let creditCardID = UUID(uuidString: "C0B1EE00-0000-4000-8000-000000000003")!

    public static let builtIns: [RedactionPattern] = [
        RedactionPattern(
            id: UUID(uuidString: "C0B1EE00-0000-4000-8000-000000000001")!,
            name: "Email",
            expression: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
            isBuiltIn: true
        ),
        RedactionPattern(
            id: UUID(uuidString: "C0B1EE00-0000-4000-8000-000000000002")!,
            name: "Phone",
            expression: #"(?<![\w+])(?:\+?\d{1,3}[\s.-]?)?(?:\(\d{3}\)|\d{3})[\s.-]?\d{3}[\s.-]?\d{4}(?!\w)"#,
            isBuiltIn: true
        ),
        RedactionPattern(
            id: creditCardID,
            name: "Card number",
            expression: #"(?<!\d)(?:\d[ -]?){12,18}\d(?!\d)"#,
            isBuiltIn: true
        ),
        RedactionPattern(
            id: UUID(uuidString: "C0B1EE00-0000-4000-8000-000000000004")!,
            name: "API key",
            expression: [
                #"\b[spr]k_(?:live|test)_[A-Z0-9]{8,}"#,
                #"\bgh[pousr]_[A-Z0-9]{20,}"#,
                #"\bgithub_pat_[A-Z0-9_]{20,}"#,
                #"\bxox[abprs]-[A-Z0-9-]{10,}"#,
                #"\bAKIA[0-9A-Z]{16}\b"#,
                #"\bAIza[0-9A-Z_-]{30,}"#,
                #"\beyJ[A-Z0-9_-]{10,}\.[A-Z0-9_-]{10,}\.[A-Z0-9_-]{5,}"#,
                // Long tokens that mix letters and digits.
                #"\b(?=[A-Z0-9_-]*\d)(?=[A-Z0-9_-]*[A-Z])[A-Z0-9_-]{32,}\b"#,
            ].joined(separator: "|"),
            isBuiltIn: true
        ),
        RedactionPattern(
            id: UUID(uuidString: "C0B1EE00-0000-4000-8000-000000000005")!,
            name: "IP address",
            expression: #"\b(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)\b|\b(?:[0-9A-F]{1,4}:){7}[0-9A-F]{1,4}\b"#,
            isBuiltIn: true
        ),
        RedactionPattern(
            id: UUID(uuidString: "C0B1EE00-0000-4000-8000-000000000006")!,
            name: "URL",
            expression: #"\bhttps?://\S+|\bwww\.\S+"#,
            isBuiltIn: true
        ),
    ]
}

/// One piece of text Auto-Redact found.
public struct RedactionMatch: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let patternName: String
    public let text: String
    /// Where it is in the image, padded a little so the whole glyphs are covered.
    public let rect: IntRect

    public init(id: UUID = UUID(), patternName: String, text: String, rect: IntRect) {
        self.id = id
        self.patternName = patternName
        self.text = text
        self.rect = rect
    }
}

/// Text recognized in an image, kept so patterns can be re-run without reading the image again.
/// Reading happens on this Mac with Vision; nothing is sent anywhere.
public final class TextScan: @unchecked Sendable {
    private struct Line {
        let text: VNRecognizedText
        let string: String
    }

    private let lines: [Line]
    private let imageSize: IntSize
    private let offset: IntPoint

    private init(lines: [Line], imageSize: IntSize, offset: IntPoint) {
        self.lines = lines
        self.imageSize = imageSize
        self.offset = offset
    }

    /// The recognized lines of text, top to bottom.
    public var text: [String] { lines.map(\.string) }

    /// Reads the text in `image`. `offset` is where the image's top-left sits on the canvas.
    public static func read(_ image: CGImage, offset: IntPoint = IntPoint(x: 0, y: 0)) async throws -> TextScan {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            // Correction would "fix" tokens and keys into words, hiding exactly what needs redacting.
            request.usesLanguageCorrection = false
            // Without a language, Vision sometimes reads Latin letters in keys as Cyrillic look-alikes.
            request.recognitionLanguages = ["en-US"]
            try VNImageRequestHandler(cgImage: image).perform([request])
            let lines = (request.results ?? []).compactMap { observation -> Line? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return Line(text: candidate, string: candidate.string)
            }
            return TextScan(lines: lines, imageSize: IntSize(width: image.width, height: image.height), offset: offset)
        }.value
    }

    /// Every match of the enabled patterns, in reading order.
    public func matches(for patterns: [RedactionPattern]) -> [RedactionMatch] {
        var results: [RedactionMatch] = []
        for line in lines {
            // Match on Latin-folded text; folding is one character for one, so positions carry over.
            let folded = AutoRedact.foldingLookalikes(line.string)
            for found in AutoRedact.matches(in: folded, patterns: patterns) {
                let start = folded.distance(from: folded.startIndex, to: found.range.lowerBound)
                let length = folded.distance(from: found.range.lowerBound, to: found.range.upperBound)
                let lower = line.string.index(line.string.startIndex, offsetBy: start)
                let range = lower..<line.string.index(lower, offsetBy: length)
                guard let rect = rect(for: range, in: line) else { continue }
                results.append(RedactionMatch(patternName: found.name, text: String(folded[found.range]), rect: rect))
            }
        }
        return results
    }

    private func rect(for range: Range<String.Index>, in line: Line) -> IntRect? {
        guard let box = try? line.text.boundingBox(for: range)?.boundingBox else { return nil }
        // Vision's boxes are normalized with the origin at the bottom-left.
        let width = Double(imageSize.width), height = Double(imageSize.height)
        let minY = (1 - box.maxY) * height, maxY = (1 - box.minY) * height
        let padding = 2 + (maxY - minY) * 0.1
        var minX = box.minX * width - padding, maxX = box.maxX * width + padding
        // Vision's box for part of a line often spills into the letters beside it, and the padding adds
        // more; never reach past the nearest visible character on either side (the spaces between still go).
        if let before = neighbor(of: range, in: line, before: true), let edge = edge(of: before, in: line, leading: false) {
            minX = max(minX, edge * width + 1)
        }
        if let after = neighbor(of: range, in: line, before: false), let edge = edge(of: after, in: line, leading: true) {
            maxX = min(maxX, edge * width - 1)
        }
        guard maxX > minX else { return nil }
        return IntRect(enclosingMinX: minX, minY: minY - padding, maxX: maxX, maxY: maxY + padding)
            .offsetBy(dx: offset.x, dy: offset.y)
    }

    /// The closest non-space character before (or after) `range` on the line.
    private func neighbor(of range: Range<String.Index>, in line: Line, before: Bool) -> Range<String.Index>? {
        let string = line.string
        if before {
            var index = range.lowerBound
            while index > string.startIndex {
                index = string.index(before: index)
                if !string[index].isWhitespace { return index..<string.index(after: index) }
            }
        } else {
            var index = range.upperBound
            while index < string.endIndex {
                if !string[index].isWhitespace { return index..<string.index(after: index) }
                index = string.index(after: index)
            }
        }
        return nil
    }

    /// A character's left or right edge, normalized like Vision's boxes.
    private func edge(of character: Range<String.Index>, in line: Line, leading: Bool) -> Double? {
        guard let box = try? line.text.boundingBox(for: character)?.boundingBox else { return nil }
        return leading ? box.minX : box.maxX
    }
}

public enum AutoRedact {
    /// Matches of the enabled patterns in one line of text. Overlapping matches keep the earliest pattern.
    public static func matches(in text: String, patterns: [RedactionPattern]) -> [(name: String, range: Range<String.Index>)] {
        var found: [(name: String, range: Range<String.Index>)] = []
        for pattern in patterns where pattern.isEnabled {
            guard let regex = try? NSRegularExpression(pattern: pattern.expression, options: [.caseInsensitive]) else { continue }
            for result in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(result.range, in: text), !range.isEmpty else { continue }
                if pattern.id == RedactionPattern.creditCardID, !passesLuhnCheck(String(text[range])) { continue }
                if found.contains(where: { $0.range.overlaps(range) }) { continue }
                found.append((pattern.name, range))
            }
        }
        return found.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    /// Replaces Cyrillic and Greek letters that look like Latin ones, character for character.
    public static func foldingLookalikes(_ text: String) -> String {
        String(text.map { lookalikes[$0] ?? $0 })
    }

    private static let lookalikes: [Character: Character] = {
        let pairs: [(String, String)] = [
            // Cyrillic
            ("АВЕКМНОРСТХУЅІЈ", "ABEKMHOPCTXYSIJ"),
            ("аеорсухѕіјԁһԛԝ", "aeopcyxsijdhqw"),
            // Greek
            ("ΑΒΕΖΗΙΚΜΝΟΡΤΥΧ", "ABEZHIKMNOPTYX"),
            ("οινκρτυχ", "oivkptux"),
        ]
        var map: [Character: Character] = [:]
        for (from, to) in pairs {
            for (a, b) in zip(from, to) { map[a] = b }
        }
        return map
    }()

    /// The checksum every real card number passes, which filters out most other long digit runs.
    static func passesLuhnCheck(_ candidate: String) -> Bool {
        let digits = candidate.compactMap(\.wholeNumberValue)
        guard (13...19).contains(digits.count) else { return false }
        var sum = 0
        for (index, digit) in digits.reversed().enumerated() {
            if index % 2 == 1 {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += digit
            }
        }
        return sum % 10 == 0
    }

    /// One selection covering all the rects, clipped to the canvas.
    public static func mask(covering rects: [IntRect], in canvasBounds: IntRect) -> SelectionMask? {
        rects.reduce(nil) { mask, rect in
            SelectionMask.combine(mask, with: .rectangle(rect, clippedTo: canvasBounds), mode: .add)
        }
    }
}
