import CoreGraphics
import Foundation
import Vision

/// Copy Text (FR-10.4): reads the text in an image on this Mac, with Apple Vision's document reader, which puts
/// columns in reading order and joins a paragraph's wrapped lines. Nothing leaves the Mac.
public enum TextReader {
    /// The text in `image`, one paragraph or line per line; empty if there's none.
    public static func read(_ image: CGImage) async throws -> String {
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.automaticallyDetectLanguage = true
        // The default skips small text in a tall screenshot, as for Auto-Redact.
        request.textRecognitionOptions.minimumTextHeightFraction = min(1, Float(6) / Float(max(1, image.height)))
        let documents = try await request.perform(on: try opaque(image))
        return documents.map(\.document.text.transcript)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    /// How many words `text` has, for "Copied 42 words".
    public static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    /// Over white, so dark text on a transparent background (or outside an odd-shaped selection) isn't read as dark
    /// on black.
    private static func opaque(_ image: CGImage) throws -> CGImage {
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw ImageCodecError.unsupportedColorSpace
        }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(bounds)
        context.draw(image, in: bounds)
        guard let result = context.makeImage() else { throw ImageCodecError.unsupportedColorSpace }
        return result
    }
}
