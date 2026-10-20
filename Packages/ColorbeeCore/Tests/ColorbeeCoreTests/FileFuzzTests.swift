import CoreGraphics
import Foundation
import Testing
@testable import ColorbeeCore

/// Hardening (Leah, 2026-10-19): every kind of file Colorbee reads, cut short, with bytes scrambled, or with impossible
/// numbers in it. A damaged file must be refused with an error, never crash or hang, and anything that does open must
/// be a valid image. The damage is made from a fixed seed, so a failure is the same on every run.
struct FileFuzzTests {
    /// SplitMix64: small and seedable, so the same damage is made every run.
    struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// `data` cut short at many lengths, with a few bytes changed in many places, and some plain junk.
    static func damaged(_ data: Data, seed: UInt64, flips: Int = 120) -> [Data] {
        var random = Seeded(state: seed)
        var out: [Data] = [Data(), Data([0]), data + Data(repeating: 0xFF, count: 64)]
        let cuts = Set((0..<48).map { $0 * data.count / 48 } + Array(0..<min(64, data.count)) + [data.count - 1])
        out += cuts.sorted().filter { $0 < data.count }.map { data.prefix($0) }
        for _ in 0..<flips {
            var copy = data
            for _ in 0..<Int.random(in: 1...6, using: &random) where !copy.isEmpty {
                let at = copy.startIndex + Int.random(in: 0..<copy.count, using: &random)
                copy[at] = UInt8.random(in: 0...255, using: &random)
            }
            out.append(copy)
        }
        out.append(Data((0..<2048).map { _ in UInt8.random(in: 0...255, using: &random) }))
        return out
    }

    static func sample(width: Int = 24, height: Int = 16) -> PixelBuffer {
        let buffer = PixelBuffer(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width {
                buffer[x, y] = Pixel(r: UInt8(x * 10 & 255), g: UInt8(y * 15 & 255), b: UInt8((x + y) * 7 & 255), a: x % 5 == 0 ? 128 : 255)
            }
        }
        return buffer
    }

    /// What every opened image must be. Drawing it (`drawing`) is slow in a debug build with adjustment layers, so
    /// only the tests that change the adjustments draw what opens.
    static func checkValid(_ canvas: Canvas, drawing: Bool = false) {
        #expect(!canvas.layers.isEmpty)
        #expect(canvas.layers.allSatisfy { $0.buffer.size == canvas.size })
        #expect(canvas.layers.indices.contains(canvas.activeLayerIndex))
        #expect(ImageCodec.fitsEditing(width: canvas.size.width, height: canvas.size.height))
        if drawing { _ = canvas.thumbnail(maxSide: 32) }
    }

    // MARK: Images

    @Test(arguments: [ImageFileFormat.png, .jpeg, .bmp, .gif, .tiff, .heic])
    func aDamagedImageIsRefusedOrOpensWhole(format: ImageFileFormat) throws {
        let original = try ImageCodec.encode(Self.sample(), colorSpace: Canvas.defaultColorSpace, as: format)
        for data in Self.damaged(original, seed: 1) {
            if let decoded = try? ImageCodec.decode(data) {
                #expect(ImageCodec.fitsEditing(width: decoded.buffer.width, height: decoded.buffer.height))
            }
            _ = ImageCodec.frameThumbnails(data, maxSide: 32, limit: 4)
        }
    }

    // MARK: PDFs

    @Test func aDamagedPDFIsRefusedOrOpensWhole() throws {
        let page = try PDFWriter.encodePage(Self.sample(), colorSpace: Canvas.defaultColorSpace, resolution: 72)
        let original = try PDFWriter.document([page, page])
        for data in Self.damaged(original, seed: 2, flips: 80) {
            guard let count = try? PDFPages.pageCount(data) else { continue }
            for index in 0..<min(count, 3) {
                if let (canvas, resolution) = try? PDFPages.render(data, page: index, resolution: 144) {
                    Self.checkValid(canvas)
                    #expect(resolution.isFinite && resolution > 0)
                }
            }
        }
    }

    /// A hand-made one-page PDF with `box` as its MediaBox and `rotate` as its turn.
    static func pdf(mediaBox box: String, rotate: String = "0") -> Data {
        var body = "%PDF-1.4\n"
        var offsets: [Int] = []
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [\(box)] /Rotate \(rotate) >>",
        ]
        for (number, object) in objects.enumerated() {
            offsets.append(body.utf8.count)
            body += "\(number + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xref = body.utf8.count
        body += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets { body += String(format: "%010d 00000 n \n", offset) }
        body += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        return Data(body.utf8)
    }

    @Test(arguments: [
        "0 0 612 792", "0 0 0 0", "0 0 -612 -792", "0 0 1 100000000", "0 0 100000000 100000000",
        "0 0 \(String(repeating: "9", count: 400)) 792", "0 0 612 \(String(repeating: "9", count: 400)).5",
        "-\(String(repeating: "9", count: 400)) 0 612 792", "0 0 0.0001 0.0001", "nan nan nan nan",
    ])
    func aPDFPageOfAnySizeOpensWithinLimits(box: String) {
        for rotate in ["0", "90", "45", "-270", "99999999999"] {
            let data = Self.pdf(mediaBox: box, rotate: rotate)
            guard (try? PDFPages.pageCount(data)) != nil else { continue }
            if let (canvas, resolution) = try? PDFPages.render(data, page: 0, resolution: 300) {
                Self.checkValid(canvas)
                #expect(resolution.isFinite && resolution > 0)
            }
        }
    }

    // MARK: Projects

    /// A project with a picture, a Levels layer and a clipped Curves layer, saved the way Colorbee saves it.
    static func project() throws -> Data {
        let size = IntSize(width: 40, height: 30)
        let picture = Layer(name: "Picture", buffer: PixelBuffer(width: size.width, height: size.height))
        let sample = sample(width: size.width, height: size.height)
        for y in 0..<size.height { for x in 0..<size.width { picture.buffer[x, y] = sample[x, y] } }
        let levels = Layer(name: "Levels", buffer: PixelBuffer(width: size.width, height: size.height))
        levels.adjustment = .levels(Levels(black: 12, white: 240, gamma: 1.1))
        let curves = Layer(name: "Curves", buffer: PixelBuffer(width: size.width, height: size.height))
        curves.adjustment = .curves(.identity)
        curves.clipsToLayerBelow = true
        let canvas = Canvas(colorSpace: Canvas.defaultColorSpace,
                            layers: [Layer(name: "Background", buffer: PixelBuffer(width: size.width, height: size.height, fill: .white)),
                                     picture, levels, curves],
                            hasTransparentBackground: false)
        return try ProjectFile.encode(canvas)
    }

    static func pagesProject() throws -> Data {
        let one = try project()
        let pages = try (0..<3).map { _ in ProjectFile.StoredPage(project: one, resolution: 144, thumbnail: nil) }
        return try ProjectFile.encode(stored: pages, currentIndex: 1)
    }

    /// Opens `data` the way a document does: its pages, then each page shown in turn.
    static func open(_ data: Data, drawing: Bool = false) {
        guard let (pages, current) = try? ProjectFile.storedPages(data) else { return }
        #expect(pages.indices.contains(current))
        for stored in pages {
            guard let page = try? Page(stored: stored, history: History(byteBudget: .max)) else { continue }
            if (try? page.unpark()) != nil { checkValid(page.canvas) }
        }
        if let canvas = try? ProjectFile.decode(data) { checkValid(canvas, drawing: drawing) }
    }

    @Test func aDamagedProjectIsRefusedOrOpensWhole() throws {
        for data in try Self.damaged(Self.project(), seed: 3, flips: 200) { Self.open(data) }
    }

    @Test func aDamagedPagesProjectIsRefusedOrOpensWhole() throws {
        for data in try Self.damaged(Self.pagesProject(), seed: 4, flips: 200) { Self.open(data) }
    }

    /// The project's manifest as JSON to change, and a way to put it back with the same pixels after it.
    static func manifest(of data: Data, magic: Data) throws -> (json: [String: Any], rebuild: ([String: Any]) throws -> Data) {
        let lengthStart = magic.count
        let length = Int(data[lengthStart..<(lengthStart + 4)].withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) })
        let json = try #require(try JSONSerialization.jsonObject(with: data[(lengthStart + 4)..<(lengthStart + 4 + length)]) as? [String: Any])
        let rest = data[(lengthStart + 4 + length)...]
        return (json, { changed in
            let encoded = try JSONSerialization.data(withJSONObject: changed)
            var out = magic
            withUnsafeBytes(of: UInt32(encoded.count).littleEndian) { out.append(contentsOf: $0) }
            return out + encoded + rest
        })
    }

    nonisolated(unsafe) static let impossibleNumbers: [Any] = [0, -1, 1, 2, 30_001, 16_000, Int.max, Int.min, -1e300, 1e300, 0.5, "12", NSNull(), [1], ["x": 1]]

    @Test func impossibleNumbersInAProjectAreRefusedOrMadeSafe() throws {
        let (json, rebuild) = try Self.manifest(of: Self.project(), magic: ProjectFile.magic)
        let layers = try #require(json["layers"] as? [[String: Any]])
        var variants: [[String: Any]] = []
        var drawn: Set<Int> = []
        for key in ["width", "height", "activeLayerIndex", "resolution", "hasTransparentBackground", "iccProfile", "colorSpaceName",
                    "backgroundLayerID", "cameraDetails", "layers"] {
            for value in Self.impossibleNumbers + ["AAAA", "junk", [] as [Any]] {
                var changed = json
                changed[key] = value
                variants.append(changed)
            }
            var removed = json
            removed[key] = nil
            variants.append(removed)
        }
        for index in layers.indices {
            for key in ["id", "name", "isVisible", "opacity", "blendMode", "isLocked", "adjustment", "pixels", "pieceRows", "pieces", "clipped"] {
                for value in Self.impossibleNumbers + [[-5, 10], [0, 1_000_000_000], [10, 5], [Int.max, Int.max], [0], [-1], [Int.max]] as [Any] {
                    if key == "adjustment", layers[index]["adjustment"] != nil { drawn.insert(variants.count) }
                    var changedLayers = layers
                    changedLayers[index][key] = value
                    var changed = json
                    changed["layers"] = changedLayers
                    variants.append(changed)
                }
            }
        }
        // Repeated layers, and many of them.
        var repeated = json
        repeated["layers"] = layers + layers
        variants.append(repeated)
        var many = json
        many["layers"] = Array(repeating: layers[2], count: 400).enumerated().map { index, layer in
            var copy = layer
            copy["id"] = UUID().uuidString
            return copy
        }
        variants.append(many)
        for (number, variant) in variants.enumerated() {
            guard let data = try? rebuild(variant) else { continue }
            Self.open(data, drawing: drawn.contains(number))
        }
    }

    @Test func impossibleNumbersInAPagesProjectAreRefusedOrMadeSafe() throws {
        let (json, rebuild) = try Self.manifest(of: Self.pagesProject(), magic: ProjectFile.pagesMagic)
        let pages = try #require(json["pages"] as? [[String: Any]])
        var variants: [[String: Any]] = []
        for value in Self.impossibleNumbers {
            var changed = json
            changed["currentIndex"] = value
            variants.append(changed)
        }
        for value in [[] as [Any], [pages[0]], Array(repeating: pages[0], count: 50)] as [Any] {
            var changed = json
            changed["pages"] = value
            variants.append(changed)
        }
        for key in ["resolution", "project", "thumbnail"] {
            for value in Self.impossibleNumbers + [[-5, 10], [0, 1_000_000_000], [10, 5], ["width": 4096, "height": 4096, "pixels": "AAAA"],
                                                   ["width": Int.max, "height": 2, "pixels": ""], ["width": -4, "height": -4, "pixels": ""]] as [Any] {
                var changedPages = pages
                changedPages[1][key] = value
                var changed = json
                changed["pages"] = changedPages
                variants.append(changed)
            }
        }
        for variant in variants {
            guard let data = try? rebuild(variant) else { continue }
            Self.open(data)
        }
    }

    // MARK: Adjustments and filters

    static let effectKinds = ["invert", "desaturate", "brightnessContrast", "hueSaturation", "gaussianBlur", "sharpen", "pixelate",
                              "levels", "curves", "sepia", "posterize", "addNoise", "motionBlur", "emboss", "vignette", "photo", "solidFill"]

    /// Every kind of adjustment with numbers at and past the edges, as a damaged project or filter could hold them.
    static func extremeEffects() -> [Data] {
        let numbers: [Double] = [0, -1, 1, 0.5, 255, 1_000_000, -1_000_000, 1e-300]
        var out: [Data] = []
        for kind in effectKinds {
            for a in numbers {
                for b in [0, 1_000_000, -1_000_000] as [Double] {
                    let values = "[\(a), \(b), \(a)]"
                    let extra = switch kind {
                    case "levels": #", "levels": {"black": \#(a), "white": \#(b), "gamma": \#(a)}"#
                    case "curves": #", "curves": {"rgb": [{"x": \#(a), "y": \#(b)}, {"x": \#(a), "y": \#(a)}], "red": [], "green": [{"x": \#(b), "y": 0}], "blue": [{"x": 0, "y": 0}, {"x": 0, "y": 255}, {"x": 0, "y": 9}]}"#
                    case "photo": #", "photo": {"adjustments": {"values": ["exposure", \#(a), "vignette", \#(b), "definition", \#(a), "sharpness", \#(b), "noiseReduction", \#(b)]}, "filterIntensity": \#(a)}"#
                    case "solidFill": #", "color": [255, 0, 0, 255]"#
                    default: ""
                    }
                    out.append(Data(#"{"kind": "\#(kind)", "values": \#(values)\#(extra)}"#.utf8))
                }
            }
        }
        return out
    }

    @Test(.timeLimit(.minutes(1)))
    func anAdjustmentWithExtremeNumbersFinishesQuickly() throws {
        for json in Self.extremeEffects() {
            guard let effect = try? JSONDecoder().decode(Effect.self, from: json) else { continue }
            let canvas = Canvas(size: IntSize(width: 24, height: 24), colorSpace: Canvas.defaultColorSpace, background: .white)
            let sample = Self.sample(width: 24, height: 24)
            for y in 0..<24 { for x in 0..<24 { canvas.activeLayer.buffer[x, y] = sample[x, y] } }
            let history = History(byteBudget: .max)
            Effects.apply(effect, to: canvas.activeLayer, selection: nil, edit: history.beginEdit("Fuzz", on: canvas))
            // As an adjustment layer, drawn over the picture.
            let adjustment = Layer(name: "Adjustment", buffer: PixelBuffer(width: 24, height: 24))
            adjustment.adjustment = effect
            canvas.insertLayer(adjustment, at: canvas.layers.count)
            _ = canvas.flattened()
        }
    }

    @Test func aDamagedFilterFileIsRefusedOrUsable() throws {
        let filter = PhotoFilter(name: "Warm", steps: [.photo(PhotoEdit(adjustments: PhotoAdjustments([.warmth: 40, .exposure: 0.3]))),
                                                       .levels(Levels(black: 10, white: 245, gamma: 1)), .sepia(amount: 30)])
        var files = Self.damaged(try filter.exported(), seed: 5, flips: 200)
        files += Self.extremeEffects().map { Data(#"{"version": 1, "name": "Odd", "steps": [\#(String(decoding: $0, as: UTF8.self))]}"#.utf8) }
        files += [#"{"version": 1, "name": "", "steps": []}"#, #"{"version": 99, "name": "\#(String(repeating: "x", count: 100_000))", "steps": [{"kind": "invert"}]}"#,
                  #"{"steps": 5}"#, "[]", "null", #"{"version": 1, "name": "Deep", "steps": [\#(String(repeating: #"{"kind": "invert"},"#, count: 5000))"#
                  + #"{"kind": "invert"}]}"#].map { Data($0.utf8) }
        for data in files {
            guard let imported = try? PhotoFilter.imported(from: data) else { continue }
            #expect(!imported.steps.isEmpty)
            let canvas = Canvas(size: IntSize(width: 16, height: 16), colorSpace: Canvas.defaultColorSpace, background: .white)
            let history = History(byteBudget: .max)
            for step in imported.steps.prefix(20) {
                Effects.apply(step.scaled(by: 0.5), to: canvas.activeLayer, selection: nil, edit: history.beginEdit("Filter", on: canvas))
            }
        }
    }

    // MARK: Shortcuts

    @Test func aDamagedShortcutsFileIsRefusedOrApplied() throws {
        var book = ShortcutBook(commands: [
            ShortcutCommand(id: "undo", title: "Undo", group: "Edit", kind: .menu, defaultShortcut: KeyShortcut("z", .command)),
            ShortcutCommand(id: "flatten", title: "Flatten", group: "Layer", kind: .menu, defaultShortcut: nil),
            ShortcutCommand(id: "pencil", title: "Pencil", group: "Tools", kind: .canvas, defaultShortcut: KeyShortcut("p")),
        ])
        book.assign(KeyShortcut("f", [.command, .option]), to: "flatten")
        let original = try book.exported()
        var files = Self.damaged(original, seed: 6, flips: 200)
        for key in ["", "K", "space", "f1", "delete", "\u{0}", "🐝", String(repeating: "a", count: 10_000), "left"] {
            for modifiers in [0, 8, -1, Int.max, 1 << 40] {
                files.append(Data(#"{"version": 1, "shortcuts": {"flatten": {"key": "\#(key)", "modifiers": \#(modifiers)}, "unknown": {"key": "q", "modifiers": 8}, "pencil": null}}"#.utf8))
            }
        }
        files += [#"{"version": 1, "shortcuts": []}"#, #"{"shortcuts": {"flatten": 5}}"#, "{}", "[]"].map { Data($0.utf8) }
        for data in files {
            var copy = book
            _ = try? copy.importChanges(from: data)
            for command in copy.commands { _ = copy.shortcut(for: command.id)?.display }
        }
    }
}
