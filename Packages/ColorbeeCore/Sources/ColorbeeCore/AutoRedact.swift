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
                // Vision can read a key's underscores as spaces, or drop them (review E, finding 7).
                #"\b[spr]k[_ ]?(?:live|test)[_ ]{0,2}[A-Z0-9]{8,}"#,
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
        /// The part of the image Vision read this line in; its boxes are relative to it.
        let tile: IntRect
    }

    private let lines: [Line]
    private let imageSize: IntSize
    private let offset: IntPoint
    /// The image in gray, one byte per pixel, for finding the gaps between words.
    private let gray: [UInt8]

    private init(lines: [Line], imageSize: IntSize, offset: IntPoint, gray: [UInt8]) {
        self.lines = lines
        self.imageSize = imageSize
        self.offset = offset
        self.gray = gray
    }

    /// The recognized lines of text, top to bottom.
    public var text: [String] { lines.map(\.string) }

    /// Reads the text in `image`. `offset` is where the image's top-left sits on the canvas.
    public static func read(_ image: CGImage, offset: IntPoint = IntPoint(x: 0, y: 0)) async throws -> TextScan {
        try await Task.detached(priority: .userInitiated) {
            // Over white, so dark text on a transparent background isn't read as dark on black
            // (review E, finding 5).
            let opaque = try opaqueCopy(of: image)
            let size = IntSize(width: image.width, height: image.height)
            var lines: [Line] = []
            for tile in tiles(for: size) {
                guard let part = opaque.cropping(to: CGRect(x: tile.minX, y: tile.minY, width: tile.width, height: tile.height)) else { continue }
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                // Correction would "fix" tokens and keys into words, hiding exactly what needs redacting.
                request.usesLanguageCorrection = false
                // Without a language, Vision sometimes reads Latin letters in keys as Cyrillic look-alikes.
                request.recognitionLanguages = ["en-US"]
                // The default skips text under 1/32 of the image's height: most text in a tall screenshot.
                request.minimumTextHeight = Float(6) / Float(tile.height)
                try VNImageRequestHandler(cgImage: part).perform([request])
                lines += (request.results ?? []).compactMap { observation -> Line? in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    return Line(text: candidate, string: candidate.string, tile: tile)
                }
            }
            return TextScan(lines: lines, imageSize: size, offset: offset, gray: grayscale(opaque))
        }.value
    }

    /// Vision shrinks a large image to read it, so small text in a long screenshot gets too small to read.
    /// Long images are read in overlapping pieces about as long as they're wide; text in an overlap is read
    /// twice, and the matches are merged.
    static func tiles(for size: IntSize) -> [IntRect] {
        func spans(_ length: Int, piece: Int) -> [Range<Int>] {
            guard length > piece * 3 / 2 else { return [0..<length] }
            let overlap = piece / 8, step = piece - overlap
            var spans: [Range<Int>] = []
            var start = 0
            while true {
                let end = min(length, start + piece)
                spans.append(max(0, end - piece)..<end)
                if end == length { break }
                start += step
            }
            return spans
        }
        let piece = max(1600, min(size.width, size.height))
        return spans(size.height, piece: piece).flatMap { rows in
            spans(size.width, piece: piece).map { columns in
                IntRect(x: columns.lowerBound, y: rows.lowerBound, width: columns.count, height: rows.count)
            }
        }
    }

    private static func opaqueCopy(of image: CGImage) throws -> CGImage {
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw ImageCodecError.unsupportedColorSpace
        }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(bounds)
        context.draw(image, in: bounds)
        guard let opaque = context.makeImage() else { throw ImageCodecError.unsupportedColorSpace }
        return opaque
    }

    /// Every match of the enabled patterns, in reading order.
    public func matches(for patterns: [RedactionPattern]) -> [RedactionMatch] {
        var results: [RedactionMatch] = []
        // Vision can read one line as separate pieces ("sk test" and "_FAKE…"), so pieces side by side on a
        // line are matched together, joined by a space (Leah's E1 Screenshot; review E, finding 7).
        let boxes = lines.map { line in (tile: line.tile, box: bounds(of: line)) }
        for row in Self.rows(boxes) {
            var joined = ""
            var starts: [Int] = []
            for index in row {
                if !joined.isEmpty { joined += " " }
                starts.append(joined.count)
                joined += lines[index].string
            }
            // Match on Latin-folded text; folding is one character for one, so positions carry over.
            let folded = AutoRedact.foldingLookalikes(joined)
            for found in AutoRedact.matches(in: folded, patterns: patterns) {
                let start = folded.distance(from: folded.startIndex, to: found.range.lowerBound)
                let end = start + folded.distance(from: found.range.lowerBound, to: found.range.upperBound)
                // The match's part in each piece it reaches into, as one box.
                var rect: IntRect?
                for (index, pieceStart) in zip(row, starts) {
                    let line = lines[index]
                    let lower = max(start, pieceStart) - pieceStart, upper = min(end, pieceStart + line.string.count) - pieceStart
                    guard lower < upper else { continue }
                    let range = line.string.index(line.string.startIndex, offsetBy: lower)..<line.string.index(line.string.startIndex, offsetBy: upper)
                    guard let box = self.rect(for: range, in: line) else { continue }
                    rect = rect.map { $0.union(box) } ?? box
                }
                guard let rect else { continue }
                let match = RedactionMatch(patternName: found.name, text: String(folded[found.range]), rect: rect)
                // Read twice where pieces overlap (not always the same way): one item, covering both boxes.
                if let twin = results.firstIndex(where: { $0.patternName == match.patternName && !$0.rect.intersection(match.rect).isEmpty }) {
                    results[twin] = RedactionMatch(id: results[twin].id, patternName: match.patternName, text: results[twin].text,
                                                   rect: results[twin].rect.union(match.rect))
                } else {
                    results.append(match)
                }
            }
        }
        return results
    }

    /// Where a whole piece of text is in the image, top-left origin.
    private func bounds(of line: Line) -> CGRect? {
        guard let box = try? line.text.boundingBox(for: line.string.startIndex..<line.string.endIndex)?.boundingBox else { return nil }
        let width = Double(line.tile.width), height = Double(line.tile.height)
        return CGRect(x: Double(line.tile.minX) + box.minX * width, y: Double(line.tile.minY) + (1 - box.maxY) * height,
                      width: box.width * width, height: box.height * height)
    }

    /// Pieces of text that sit side by side on one line, left to right: read in the same piece of the image,
    /// overlapping by at least half their height, and no further apart than twice that height.
    static func rows(_ pieces: [(tile: IntRect, box: CGRect?)]) -> [[Int]] {
        var rows: [[Int]] = []
        var placed = Set<Int>()
        let order = pieces.indices.sorted { (pieces[$0].box?.minX ?? 0) < (pieces[$1].box?.minX ?? 0) }
        for first in order where !placed.contains(first) {
            placed.insert(first)
            var row = [first]
            guard var last = pieces[first].box else {
                rows.append(row)
                continue
            }
            for next in order where !placed.contains(next) && pieces[next].tile == pieces[first].tile {
                guard let box = pieces[next].box, box.minX >= last.minX else { continue }
                let height = min(box.height, last.height)
                let overlap = min(box.maxY, last.maxY) - max(box.minY, last.minY)
                guard overlap >= height / 2, box.minX - last.maxX <= 2 * max(box.height, last.height) else { continue }
                row.append(next)
                placed.insert(next)
                last = box
            }
            rows.append(row)
        }
        // In reading order: top to bottom, then left to right.
        func top(_ row: [Int]) -> (CGFloat, CGFloat) { (pieces[row[0]].box?.minY ?? 0, pieces[row[0]].box?.minX ?? 0) }
        return rows.sorted { top($0) < top($1) }
    }

    /// Where a match is in the image. It never shrinks below Vision's box for the match: for redaction,
    /// covering a sliver of a neighboring letter is fine, but leaving part of a secret showing is not.
    /// The padding around it reaches into a space between words only partway, so it doesn't touch the
    /// next word; where there's no space (as in "key=sk_live…"), the full padding is kept.
    private func rect(for range: Range<String.Index>, in line: Line) -> IntRect? {
        guard let box = try? line.text.boundingBox(for: range)?.boundingBox else { return nil }
        // Vision's boxes are normalized to the piece read, with the origin at the bottom-left.
        let width = Double(line.tile.width), height = Double(line.tile.height)
        let minY = Double(line.tile.minY) + (1 - box.maxY) * height, maxY = Double(line.tile.minY) + (1 - box.minY) * height
        let padding = 2 + (maxY - minY) * 0.1
        let rawMinX = Double(line.tile.minX) + box.minX * width, rawMaxX = Double(line.tile.minX) + box.maxX * width
        var minX = rawMinX - padding, maxX = rawMaxX + padding
        let band = Int(minY.rounded(.down))..<Int(maxY.rounded(.up))
        let lineHeight = maxY - minY
        // Vision's box may spill a sliver past the space into the neighboring word. Ink narrower than
        // half a line's height beyond a word space can't be the match's own first or last part
        // ("+1", "4242" are wider), so the box may be trimmed back to the space there.
        let sliver = lineHeight * 0.5
        var floorMinX = rawMinX, ceilingMaxX = rawMaxX
        if range.lowerBound > line.string.startIndex, line.string[line.string.index(before: range.lowerBound)].isWhitespace,
           let space = wordSpace(near: rawMinX, band: band, lineHeight: lineHeight, endingAt: true) {
            let edge = Double(space.upperBound) - min(padding, Double(space.count) / 2)
            minX = max(minX, edge)
            if Double(space.lowerBound) - rawMinX < sliver { floorMinX = max(rawMinX, edge) }
        }
        if range.upperBound < line.string.endIndex, line.string[range.upperBound].isWhitespace,
           let space = wordSpace(near: rawMaxX, band: band, lineHeight: lineHeight, endingAt: false) {
            let edge = Double(space.lowerBound) + min(padding, Double(space.count) / 2)
            maxX = min(maxX, edge)
            if rawMaxX - Double(space.upperBound) < sliver { ceilingMaxX = min(rawMaxX, edge) }
        }
        // Otherwise never smaller than Vision's own box.
        minX = min(minX, floorMinX)
        maxX = max(maxX, ceilingMaxX)
        return IntRect(enclosingMinX: minX, minY: minY - padding, maxX: maxX, maxY: maxY + padding)
            .offsetBy(dx: offset.x, dy: offset.y)
    }

    /// The run of empty columns (a space between words) nearest `x` within the text's rows: the one
    /// whose right end is nearest for a gap before the match, or whose left end is nearest after it.
    private func wordSpace(near x: Double, band: Range<Int>, lineHeight: Double, endingAt: Bool) -> Range<Int>? {
        // Only the upper part of the line: descenders (the hook of a "j") curl under the space before them.
        let upper = band.lowerBound + Int((Double(band.count) * 0.7).rounded())
        let rows = max(0, band.lowerBound)..<min(imageSize.height, upper)
        guard !rows.isEmpty else { return nil }
        let reach = Int(lineHeight.rounded(.up))
        let columns = max(0, Int(x) - reach)..<min(imageSize.width, Int(x) + reach)
        func empty(_ column: Int) -> Bool {
            var low: UInt8 = 255, high: UInt8 = 0
            for row in rows {
                let value = gray[row * imageSize.width + column]
                low = min(low, value)
                high = max(high, value)
            }
            return high - low <= 24
        }
        // A word space is wider than the gaps between letters.
        let minimum = max(2, Int((lineHeight * 0.15).rounded()))
        var runs: [Range<Int>] = []
        var start: Int?
        for column in columns {
            if empty(column) {
                if start == nil { start = column }
            } else if let begin = start {
                if column - begin >= minimum { runs.append(begin..<column) }
                start = nil
            }
        }
        if let begin = start, columns.upperBound - begin >= minimum { runs.append(begin..<columns.upperBound) }
        return runs.min { a, b in
            let edgeA = Double(endingAt ? a.upperBound : a.lowerBound), edgeB = Double(endingAt ? b.upperBound : b.lowerBound)
            return abs(edgeA - x) < abs(edgeB - x)
        }
    }

    private static func grayscale(_ image: CGImage) -> [UInt8] {
        var pixels = [UInt8](repeating: 255, count: image.width * image.height)
        pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(
                data: bytes.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return pixels
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
