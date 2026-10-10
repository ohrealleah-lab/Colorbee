import CoreGraphics
import Foundation
import ImageIO

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

    /// A page scanned by an iPhone or iPad (FR-11.7): the phone puts each scan, as one JPEG, on a Letter page. The
    /// JPEG itself becomes the page, with the phone's own pixels and no white strips beside it (Leah, 2026-10-10), at
    /// the resolution that fits it on the page as the phone placed it. Any other kind of page is drawn like an opened
    /// PDF's, at `resolution`.
    public static func scannedPage(_ data: Data, page index: Int, resolution: Double) throws -> (canvas: Canvas, resolution: Double) {
        let document = try document(data)
        guard let page = document.page(at: index + 1) else { throw Failure.unreadable }
        let box = page.getBoxRect(.cropBox)
        guard page.rotationAngle % 360 == 0, box.width > 0, box.height > 0, let scan = soleJPEG(on: page),
              let decoded = try? decodeScan(scan) else {
            return try render(data, page: index, resolution: resolution)
        }
        let canvas = Canvas(colorSpace: decoded.colorSpace, layers: [Layer(name: "Background", buffer: decoded.buffer)], hasTransparentBackground: false)
        let fitted = max(Double(decoded.buffer.width) / (box.width / 72), Double(decoded.buffer.height) / (box.height / 72))
        return (canvas, fitted)
    }

    /// The page's only image, if it's a JPEG with nothing masking it, and its color space from the PDF.
    private static func soleJPEG(on page: CGPDFPage) -> (jpeg: Data, colorSpace: CGColorSpace?)? {
        guard let pageDictionary = page.dictionary, let resources = dictionary("Resources", in: pageDictionary),
              let objects = dictionary("XObject", in: resources) else { return nil }
        var images: [CGPDFStreamRef] = []
        var others = 0
        CGPDFDictionaryApplyBlock(objects, { _, object, _ in
            var stream: CGPDFStreamRef?
            if CGPDFObjectGetValue(object, .stream, &stream), let stream, let info = CGPDFStreamGetDictionary(stream),
               name("Subtype", in: info) == "Image" {
                images.append(stream)
            } else {
                others += 1
            }
            return true
        }, nil)
        guard images.count == 1, others == 0, let info = CGPDFStreamGetDictionary(images[0]) else { return nil }
        var mask: CGPDFObjectRef?
        guard !CGPDFDictionaryGetObject(info, "SMask", &mask), !CGPDFDictionaryGetObject(info, "Mask", &mask),
              !CGPDFDictionaryGetObject(info, "Decode", &mask) else { return nil }
        var format = CGPDFDataFormat.raw
        guard let bytes = CGPDFStreamCopyData(images[0], &format), format == .jpegEncoded else { return nil }
        return (bytes as Data, iccColorSpace(in: info))
    }

    /// The JPEG's pixels, in its own profile, or the PDF's when the JPEG has none.
    private static func decodeScan(_ scan: (jpeg: Data, colorSpace: CGColorSpace?)) throws -> DecodedImage {
        guard let source = CGImageSourceCreateWithData(scan.jpeg as CFData, nil) else { throw Failure.unreadable }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        guard properties[kCGImagePropertyProfileName] == nil, let pdfSpace = scan.colorSpace,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil), image.colorSpace?.model == pdfSpace.model,
              let tagged = image.copy(colorSpace: pdfSpace) else {
            return try ImageCodec.decode(scan.jpeg)
        }
        return try ImageCodec.decode(tagged)
    }

    /// An ICCBased color space: [/ICCBased stream].
    private static func iccColorSpace(in info: CGPDFDictionaryRef) -> CGColorSpace? {
        var array: CGPDFArrayRef?
        var family: UnsafePointer<CChar>?
        var stream: CGPDFStreamRef?
        guard CGPDFDictionaryGetArray(info, "ColorSpace", &array), let array, CGPDFArrayGetName(array, 0, &family),
              let family, String(cString: family) == "ICCBased", CGPDFArrayGetStream(array, 1, &stream), let stream else { return nil }
        var format = CGPDFDataFormat.raw
        guard let profile = CGPDFStreamCopyData(stream, &format), format == .raw else { return nil }
        return CGColorSpace(iccData: profile)
    }

    private static func dictionary(_ key: String, in dictionary: CGPDFDictionaryRef) -> CGPDFDictionaryRef? {
        var result: CGPDFDictionaryRef?
        return CGPDFDictionaryGetDictionary(dictionary, key, &result) ? result : nil
    }

    private static func name(_ key: String, in dictionary: CGPDFDictionaryRef) -> String? {
        var value: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetName(dictionary, key, &value), let value else { return nil }
        return String(cString: value)
    }
}
