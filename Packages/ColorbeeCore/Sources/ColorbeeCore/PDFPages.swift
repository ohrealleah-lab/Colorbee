import CoreGraphics
import Foundation

/// Reads PDF pages as pixels (FR-11.6), with Core Graphics. Fonts, vectors and form fields aren't kept.
public enum PDFPages {
    public enum Failure: Error, LocalizedError {
        case unreadable
        case locked

        public var errorDescription: String? {
            switch self {
            case .unreadable: "This PDF can't be read."
            case .locked: "This PDF is protected with a password, so Colorbee can't open it."
            }
        }
    }

    /// The document, unlocked if it has no real password.
    private static func document(_ data: Data) throws -> CGPDFDocument {
        guard let provider = CGDataProvider(data: data as CFData), let document = CGPDFDocument(provider) else { throw Failure.unreadable }
        if document.isEncrypted, !document.isUnlocked, !document.unlockWithPassword("") { throw Failure.locked }
        guard document.numberOfPages > 0 else { throw Failure.unreadable }
        return document
    }

    public static func pageCount(_ data: Data) throws -> Int {
        try document(data).numberOfPages
    }

    /// Page `index` (from 0) drawn on white at `resolution` pixels per inch, as a one-layer canvas. A page too
    /// big for Colorbee at that resolution is drawn smaller; the resolution it got is returned with it.
    public static func render(_ data: Data, page index: Int, resolution: Double) throws -> (canvas: Canvas, resolution: Double) {
        let document = try document(data)
        guard let page = document.page(at: index + 1) else { throw Failure.unreadable }
        let box = page.getBoxRect(.cropBox)
        let turned = page.rotationAngle % 180 != 0
        let points = CGSize(width: turned ? box.height : box.width, height: turned ? box.width : box.height)
        guard points.width > 0, points.height > 0 else { throw Failure.unreadable }
        var scale = resolution / 72
        let largest = Double(ResizeSkew.maxSide)
        scale = min(scale, largest / points.width, largest / points.height,
                    (Double(ResizeSkew.maxArea) / (points.width * points.height)).squareRoot())
        let width = max(1, Int((points.width * scale).rounded(.down))), height = max(1, Int((points.height * scale).rounded(.down)))
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw Failure.unreadable }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.scaleBy(x: scale, y: scale)
        context.concatenate(page.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: points), rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        guard let image = context.makeImage() else { throw Failure.unreadable }
        let decoded = try ImageCodec.decode(image)
        let canvas = Canvas(colorSpace: decoded.colorSpace, layers: [Layer(name: "Background", buffer: decoded.buffer)], hasTransparentBackground: false)
        return (canvas, scale * 72)
    }
}
