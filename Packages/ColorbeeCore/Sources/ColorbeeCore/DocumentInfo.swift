import Foundation

/// What the Info panel shows (FR-1.3): read-only facts about the document and the page being viewed, in sections
/// of label–value rows. The app gathers the facts; this decides the rows and how each value reads.
public struct DocumentInfo: Equatable, Sendable {
    public struct Row: Equatable, Sendable {
        public let label: String
        public let value: String
    }

    public struct Section: Equatable, Sendable {
        public let title: String
        public let rows: [Row]
    }

    public var fileName: String
    /// The format's name ("PNG image"), or nil while the document has never been saved.
    public var kind: String?
    public var bytesOnDisk: Int64?
    public var size: IntSize
    public var profileName: String?
    public var hasTransparentBackground: Bool
    public var layerCount: Int
    public var pageIndex: Int
    public var pageCount: Int
    public var resolution: Double
    public var camera: CameraDetails?
    public var locationRemoved: Bool

    public init(fileName: String, kind: String?, bytesOnDisk: Int64?, size: IntSize, profileName: String?,
                hasTransparentBackground: Bool, layerCount: Int, pageIndex: Int = 0, pageCount: Int = 1,
                resolution: Double = Page.defaultResolution, camera: CameraDetails? = nil, locationRemoved: Bool = false) {
        self.fileName = fileName
        self.kind = kind
        self.bytesOnDisk = bytesOnDisk
        self.size = size
        self.profileName = profileName
        self.hasTransparentBackground = hasTransparentBackground
        self.layerCount = layerCount
        self.pageIndex = pageIndex
        self.pageCount = pageCount
        self.resolution = resolution
        self.camera = camera
        self.locationRemoved = locationRemoved
    }

    public var sections: [Section] {
        var result = [Section(title: "File", rows: fileRows), Section(title: "Image", rows: imageRows)]
        let photo = photoRows
        if !photo.isEmpty { result.append(Section(title: "Photo", rows: photo)) }
        return result
    }

    private var fileRows: [Row] {
        var rows = [Row(label: "Name", value: fileName), Row(label: "Kind", value: kind ?? "Not saved yet")]
        if let bytesOnDisk {
            rows.append(Row(label: "Size", value: ByteCountFormatter.string(fromByteCount: bytesOnDisk, countStyle: .file)))
        }
        return rows
    }

    private var imageRows: [Row] {
        var rows = [Row(label: "Dimensions", value: "\(size.width) × \(size.height) px")]
        if let profileName { rows.append(Row(label: "Color profile", value: profileName)) }
        rows.append(Row(label: "Background", value: hasTransparentBackground ? "Transparent" : "Solid"))
        rows.append(Row(label: "Layers", value: "\(layerCount)"))
        if pageCount > 1 { rows.append(Row(label: "Page", value: "\(pageIndex + 1) of \(pageCount)")) }
        // Other pictures' resolution only sets their size in Export as PDF, so it isn't worth showing.
        if resolution != Page.defaultResolution { rows.append(Row(label: "Resolution", value: "\(Self.number(resolution)) DPI")) }
        return rows
    }

    private var photoRows: [Row] {
        var rows: [Row] = []
        if let camera {
            if let name = Self.cameraName(make: camera.make, model: camera.model) { rows.append(Row(label: "Camera", value: name)) }
            if let lens = camera.lens { rows.append(Row(label: "Lens", value: lens)) }
            if let iso = camera.iso { rows.append(Row(label: "ISO", value: "\(iso)")) }
            if let time = camera.exposureTime, time > 0 { rows.append(Row(label: "Shutter", value: Self.shutter(time))) }
            if let f = camera.fNumber { rows.append(Row(label: "Aperture", value: "ƒ/\(Self.number(f))")) }
            if let focal = camera.focalLength { rows.append(Row(label: "Focal length", value: "\(Self.number(focal)) mm")) }
            if let date = camera.dateTaken { rows.append(Row(label: "Taken", value: Self.dateTaken(date))) }
        }
        if locationRemoved { rows.append(Row(label: "Location", value: "Removed")) }
        return rows
    }

    /// Makers often repeat their name in the model ("Canon" and "Canon EOS R5"); it's shown once.
    static func cameraName(make: String?, model: String?) -> String? {
        switch (make, model) {
        case let (make?, model?):
            let firstWord = make.split(separator: " ").first.map(String.init) ?? make
            return model.range(of: firstWord, options: [.caseInsensitive, .anchored]) != nil ? model : "\(make) \(model)"
        case let (make?, nil): return make
        case let (nil, model?): return model
        case (nil, nil): return nil
        }
    }

    /// "1/120 s" for fast shutters, as cameras write them; "0.5 s" or "2 s" for slow ones.
    static func shutter(_ seconds: Double) -> String {
        if seconds < 0.5 { return "1/\(Int((1 / seconds).rounded())) s" }
        return "\(number(seconds)) s"
    }

    /// EXIF's "2026:10:05 10:30:00" as a readable date and time; anything else as it was written.
    static func dateTaken(_ exif: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy:MM:dd HH:mm:ss"
        guard let date = parser.date(from: exif) else { return exif }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    /// Up to one decimal place, without a trailing ".0".
    static func number(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? "\(Int(rounded))" : "\(rounded)"
    }
}
