import CoreGraphics

/// The colors an exported file is written in (FR-9.7 item 8): the document's own (usually Display P3), or converted
/// to sRGB or Display P3. Copy, Share and PDF always keep the document's (Q19.1).
public enum ExportColor: String, CaseIterable, Sendable, Codable {
    case keep, sRGB, displayP3

    public var title: String {
        switch self {
        case .keep: "Keep Document's"
        case .sRGB: "sRGB"
        case .displayP3: "Display P3"
        }
    }

    /// The color space to write in, for a document in `document`.
    public func space(for document: CGColorSpace) -> CGColorSpace {
        switch self {
        case .keep: document
        case .sRGB: CGColorSpace(name: CGColorSpace.sRGB)!
        case .displayP3: CGColorSpace(name: CGColorSpace.displayP3)!
        }
    }
}
