import AppKit
import ColorbeeCore
import ImageIO
import UniformTypeIdentifiers
@testable import Colorbee

/// Files a stranger's Mac will hand Colorbee (monkey hardening, S1, S2 and S5), opened and saved the way `ImageDocument` does.
/// Every file is made here, in a temporary folder of its own that's removed afterwards (Leah, 2026-11-21: nothing in
/// the repo).
@MainActor
enum MonkeyFiles {
    /// A kind of file, made in code so a replay makes it the same on any Mac.
    enum Kind: String, CaseIterable {
        case png = "PNG", png16 = "16-bit PNG", gray = "gray PNG", grayAlpha = "gray PNG with transparency", adobeRGB = "Adobe RGB PNG"
        case noProfile = "PNG with no color profile", jpeg = "JPEG", cmyk = "CMYK JPEG", turned = "JPEG stored turned (EXIF 6)"
        case tiff = "two-page TIFF", gif = "animated GIF", heic = "HEIC", bmp = "BMP", pdf = "two-page PDF", project = "Colorbee project"
    }

    /// How a file is damaged.
    enum Damage: CaseIterable {
        case none, empty, truncated, flipped, header, wrongType, huge

        func words(_ cut: Int) -> String {
            switch self {
            case .none: "as it is"
            case .empty: "with nothing in it"
            case .truncated: "cut short after \(cut) bytes"
            case .flipped: "with bytes changed from \(cut) on"
            case .header: "with its first bytes changed"
            case .wrongType: "named as a different kind of file"
            case .huge: "claiming to be 100,000 pixels across"
            }
        }
    }

    /// One file per episode: its kind and damage come from the seed. A damaged file must open to a sound document or
    /// say it can't be opened; never crash or hang. An undamaged one must open and save as a project without losing its
    /// look or colors.
    static func check(seed: UInt64) -> MonkeyFailure? {
        var random = MonkeyRandom(seed: seed &* 2_654_435_761 &+ 3)
        let kind = random.pick(Kind.allCases), damage = random.pick(Damage.allCases)
        let made: (data: Data, type: UTType)
        do { made = try file(kind, random: &random) } catch {
            return MonkeyFailure(rule: "The monkey couldn't make a \(kind.rawValue)", detail: "\(error)")
        }
        var data = made.data, type = made.type
        var cut = 0
        switch damage {
        case .none: break
        case .empty: data = Data()
        case .truncated:
            cut = random.int(0..<max(1, data.count))
            data = data.prefix(cut)
        case .flipped:
            cut = random.int(0..<max(1, data.count))
            for index in cut..<min(data.count, cut + random.int(1...64)) { data[data.startIndex + index] = UInt8(random.int(0...255)) }
        case .header:
            for index in 0..<min(data.count, 16) where random.chance(0.4) { data[data.startIndex + index] ^= UInt8(random.int(1...255)) }
        case .wrongType:
            type = random.pick([UTType.png, .jpeg, .tiff, .gif, .heic, .pdf, .colorbeeProject].filter { $0 != made.type })
        case .huge:
            guard let patched = claimingHugeSize(data, kind: kind) else { return nil }
            data = patched
        }
        let what = "A \(kind.rawValue) \(damage.words(cut))"
        try? "\(what) was being opened (episode seed \(seed)).\n".write(to: progressNote, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: progressNote) }
        let opened: Editor?
        do {
            let document = ImageDocument()
            try document.read(from: data, ofType: type.identifier)
            opened = document.editor
        } catch {
            // Saying it can't be opened is right for damaged files; an undamaged one must open.
            guard damage == .none else { return nil }
            return MonkeyFailure(rule: "A good file wouldn't open", detail: "\(what): \(error)")
        }
        guard let editor = opened else {
            return MonkeyFailure(rule: "Opening a file made no picture", detail: "\(what) opened without an error but with no picture.")
        }
        do {
            try MonkeyRules.checkDocument(editor)
        } catch {
            return MonkeyFailure(rule: "An opened file isn't sound: \(error.rule)", detail: "\(what). \(error.detail)")
        }
        if damage == .none, let failure = checkOpened(editor, kind: kind) { return MonkeyFailure(rule: failure.rule, detail: "\(what): \(failure.detail)") }
        // Whatever opened can be saved as a project and opened again, looking the same in the same colors (R13).
        do {
            let project = try editor.encodedProject()
            let (stored, current) = try ProjectFile.storedPages(project)
            guard stored.count == editor.pages.pages.count else {
                return MonkeyFailure(rule: "An opened file saves with different pages", detail: "\(what): \(stored.count) pages saved, not \(editor.pages.pages.count).")
            }
            let page = try Page(stored: stored[current], history: History(byteBudget: .max))
            try page.unpark()
            if !sameColors(page.canvas.colorSpace, editor.canvas.colorSpace) {
                return MonkeyFailure(rule: "An opened file lost its colors when saved",
                                     detail: "\(what) is in \(editor.canvas.colorSpace.name.map { "\($0)" } ?? "an unnamed profile"); saved, it came back in \(page.canvas.colorSpace.name.map { "\($0)" } ?? "an unnamed profile").")
            }
            if MonkeyRules.shownHash(page.canvas.flattened()) != MonkeyRules.shownHash(editor.shownPicture) {
                return MonkeyFailure(rule: "An opened file looks different once saved", detail: "\(what), saved as a project and opened again, looks different.")
            }
        } catch {
            return MonkeyFailure(rule: "An opened file couldn't be saved", detail: "\(what): \(error)")
        }
        return nil
    }

    /// What an undamaged file of each kind must open as.
    private static func checkOpened(_ editor: Editor, kind: Kind) -> MonkeyFailure? {
        let size = editor.canvas.size
        let pages = editor.pages.pages.count
        switch kind {
        case .tiff, .gif, .pdf:
            if pages != 2 { return MonkeyFailure(rule: "A file opened with the wrong pages", detail: "\(pages) pages, not 2.") }
        case .turned:
            // Stored 40 × 24 with a tag saying to show it turned a quarter: it opens upright, 24 × 40.
            if size != IntSize(width: 24, height: 40) {
                return MonkeyFailure(rule: "A photo stored turned didn't open upright", detail: "It opened \(size.width) × \(size.height), not 24 × 40.")
            }
        case .adobeRGB:
            // Never silently converted to sRGB (CLAUDE.md).
            if !sameColors(editor.canvas.colorSpace, CGColorSpace(name: CGColorSpace.adobeRGB1998)!) {
                return MonkeyFailure(rule: "A file's colors were converted on opening", detail: "Adobe RGB opened as \(editor.canvas.colorSpace.name.map { "\($0)" } ?? "an unnamed profile").")
            }
        default:
            if kind != .pdf, size != IntSize(width: 40, height: 24) {
                return MonkeyFailure(rule: "A file opened at the wrong size", detail: "\(size.width) × \(size.height), not 40 × 24.")
            }
        }
        return nil
    }

    /// The same colors: the same named space, or the same profile when a file's has no name. ImageIO reads a
    /// profile back with no name and a few bytes rewritten, so an unnamed one is known by the name inside it.
    static func sameColors(_ a: CGColorSpace, _ b: CGColorSpace) -> Bool {
        if let first = a.name, let second = b.name { return first == second }
        if (a.copyICCData() as Data?) == (b.copyICCData() as Data?) { return true }
        guard let first = NSColorSpace(cgColorSpace: a)?.localizedName, let second = NSColorSpace(cgColorSpace: b)?.localizedName else { return false }
        return first == second
    }

    static var progressNote: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["COLORBEE_MONKEY_REPORT"] ?? FileManager.default.temporaryDirectory.path)
            .appendingPathComponent("Monkey Opening.txt")
    }

    struct MakeFailure: Error {}

    /// A small 40 × 24 picture of `kind`, with soft colors and some transparency where the format keeps it.
    static func file(_ kind: Kind, random: inout MonkeyRandom) throws -> (Data, UTType) {
        let seed = UInt8(random.int(0...200))
        func pixels(alpha: Bool) -> PixelBuffer {
            let buffer = PixelBuffer(width: 40, height: 24)
            for y in 0..<24 {
                for x in 0..<40 {
                    buffer[x, y] = Pixel(r: UInt8((x * 6 + Int(seed)) % 256), g: UInt8(y * 10), b: seed, a: alpha && x < 8 ? UInt8(x * 30) : 255)
                }
            }
            return buffer
        }
        switch kind {
        case .project:
            let editor = Editor(canvas: Canvas(picture: pixels(alpha: true), colorSpace: Canvas.defaultColorSpace))
            editor.addLayer()
            editor.renameLayer(at: editor.activeLayerIndex, to: "API key")
            editor.paste(pixels(alpha: false), at: IntPoint(x: 4, y: 4))
            editor.placePendingObjects()
            editor.deselect()
            editor.newPage()
            return (try editor.encodedProject(), .colorbeeProject)
        case .pdf:
            return (try pdf(), .pdf)
        default:
            break
        }
        let rgb = CGColorSpace(name: CGColorSpace.displayP3)!
        var images: [CGImage] = []
        var type = UTType.png
        var properties: [CFString: Any] = [:]
        switch kind {
        case .png: images = [try ImageCodec.makeCGImage(pixels(alpha: true), colorSpace: rgb)]
        case .png16: images = [try drawn(bits: 16, space: rgb, alpha: true, seed: seed)]
        case .gray: images = [try drawn(bits: 8, space: CGColorSpace(name: CGColorSpace.linearGray)!, alpha: false, seed: seed)]
        case .grayAlpha: images = [try drawn(bits: 8, space: CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)!, alpha: true, seed: seed)]
        case .adobeRGB: images = [try ImageCodec.makeCGImage(pixels(alpha: false), colorSpace: CGColorSpace(name: CGColorSpace.adobeRGB1998)!)]
        case .noProfile: images = [try drawn(bits: 8, space: CGColorSpaceCreateDeviceRGB(), alpha: false, seed: seed)]
        case .jpeg:
            type = .jpeg
            images = [try ImageCodec.makeCGImage(pixels(alpha: false), colorSpace: rgb)]
        case .cmyk:
            type = .jpeg
            images = [try drawn(bits: 8, space: CGColorSpace(name: CGColorSpace.genericCMYK)!, alpha: false, seed: seed)]
        case .turned:
            type = .jpeg
            images = [try ImageCodec.makeCGImage(pixels(alpha: false), colorSpace: rgb)]
            properties[kCGImagePropertyOrientation] = 6
        case .tiff:
            type = .tiff
            images = [try ImageCodec.makeCGImage(pixels(alpha: true), colorSpace: rgb), try ImageCodec.makeCGImage(pixels(alpha: false), colorSpace: rgb)]
        case .gif:
            type = .gif
            let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
            images = [try ImageCodec.makeCGImage(pixels(alpha: false), colorSpace: srgb), try ImageCodec.makeCGImage(pixels(alpha: true), colorSpace: srgb)]
        case .heic:
            type = .heic
            images = [try ImageCodec.makeCGImage(pixels(alpha: false), colorSpace: rgb)]
        case .bmp:
            type = .bmp
            images = [try ImageCodec.makeCGImage(pixels(alpha: false), colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)]
        case .project, .pdf:
            break
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, images.count, nil) else { throw MakeFailure() }
        for image in images { CGImageDestinationAddImage(destination, image, properties as CFDictionary) }
        guard CGImageDestinationFinalize(destination) else { throw MakeFailure() }
        return (data as Data, type)
    }

    /// A picture drawn straight in `space`, at `bits` per component: what `ImageCodec.makeCGImage` can't make.
    private static func drawn(bits: Int, space: CGColorSpace, alpha: Bool, seed: UInt8) throws -> CGImage {
        let info: UInt32 = alpha ? CGImageAlphaInfo.premultipliedLast.rawValue
            : space.model == .rgb ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.none.rawValue
        let order: UInt32 = bits == 16 ? CGBitmapInfo.byteOrder16Little.rawValue : 0
        guard let context = CGContext(data: nil, width: 40, height: 24, bitsPerComponent: bits, bytesPerRow: 0, space: space, bitmapInfo: info | order) else {
            throw MakeFailure()
        }
        for x in 0..<40 {
            let value = CGFloat((x * 6 + Int(seed)) % 256) / 255
            let components: [CGFloat] = switch space.model {
            case .monochrome: [value, alpha && x < 8 ? CGFloat(x) / 8 : 1]
            case .cmyk: [value, 0.3, 1 - value, 0.1, 1]
            default: [value, 0.4, 1 - value, alpha && x < 8 ? CGFloat(x) / 8 : 1]
            }
            context.setFillColor(CGColor(colorSpace: space, components: components)!)
            context.fill(CGRect(x: x, y: 0, width: 1, height: 24))
        }
        guard let image = context.makeImage() else { throw MakeFailure() }
        return image
    }

    /// A two-page PDF: a page with a colored box, and one turned a quarter.
    private static func pdf() throws -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else { throw MakeFailure() }
        var box = CGRect(x: 0, y: 0, width: 40 * 72 / 200, height: 24 * 72 / 200)
        guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { throw MakeFailure() }
        for turned in [false, true] {
            let info: [CFString: Any] = turned ? ["Rotate" as CFString: 90] : [:]
            context.beginPDFPage(info as CFDictionary)
            context.setFillColor(CGColor(red: 0.8, green: 0.3, blue: 0.1, alpha: 1))
            context.fill(CGRect(x: 2, y: 2, width: 6, height: 4))
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    /// The file with its header claiming 100,000 × 100,000 pixels: it must be refused, never decoded (a size bomb).
    /// Only PNG's header is patched (with its checksum made right); other kinds aren't checked this way.
    private static func claimingHugeSize(_ data: Data, kind: Kind) -> Data? {
        guard [.png, .png16, .gray, .grayAlpha, .adobeRGB, .noProfile].contains(kind), data.count > 33 else { return nil }
        var bytes = [UInt8](data)
        let huge: [UInt8] = [0x00, 0x01, 0x86, 0xA0]
        bytes.replaceSubrange(16..<20, with: huge)
        bytes.replaceSubrange(20..<24, with: huge)
        let crc = crc32(bytes[12..<29])
        bytes.replaceSubrange(29..<33, with: [UInt8(crc >> 24), UInt8(crc >> 16 & 0xFF), UInt8(crc >> 8 & 0xFF), UInt8(crc & 0xFF)])
        return Data(bytes)
    }

    private static func crc32(_ bytes: ArraySlice<UInt8>) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        }
        return ~crc
    }

    // MARK: Saving through the document (S5)

    /// At the end of an episode: the picture saved the way a window saves it (`NSDocument`'s safe save, writing
    /// `ImageDocument.data(ofType:)`), over an older copy, then opened again the way a window opens it, must be the
    /// picture. Then a save into a folder that can't be written to must fail and leave the file that was there whole.
    static func checkDocumentSave(_ editor: Editor, seed: UInt64) -> MonkeyFailure? {
        let folder = FileManager.default.temporaryDirectory.appending(path: "Colorbee Monkey \(seed)-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
            try? FileManager.default.removeItem(at: folder)
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let flat = !editor.isLayered && editor.pages.pages.count == 1
            let type: UTType = flat ? .png : .colorbeeProject
            let file = folder.appending(path: flat ? "Picture.png" : "Picture.colorproj")
            // An older picture is there first, so the save replaces a file, as ⌘S does.
            try Data([1, 2, 3]).write(to: file)
            // The window's document holds a copy of the picture, read the way a window reads a project.
            let document = ImageDocument()
            try document.read(from: try editor.encodedProject(), ofType: UTType.colorbeeProject.identifier)
            // Elsewhere, as an untitled window autosaves: an in-place save would also keep a version of each file.
            try document.writeSafely(to: file, ofType: type.identifier, for: .autosaveElsewhereOperation)
            let saved = try Data(contentsOf: file)
            let reopened = ImageDocument()
            try reopened.read(from: saved, ofType: type.identifier)
            guard let back = reopened.editor else { return MonkeyFailure(rule: "A saved picture opened as nothing", detail: "Saved through the document, it opened with no picture.") }
            if MonkeyRules.shownHash(back.canvas.flattened()) != MonkeyRules.shownHash(editor.shownPicture) || back.pages.pages.count != editor.pages.pages.count {
                return MonkeyFailure(rule: "A picture saved through the document opens different",
                                     detail: "Saved as \(flat ? "PNG" : "a project") over an older file and opened again, it isn't the picture.")
            }
            if !sameColors(back.canvas.colorSpace, editor.canvas.colorSpace) {
                return MonkeyFailure(rule: "A picture saved through the document lost its colors", detail: "It came back in another profile.")
            }
            // Now the folder can't be written: the save must fail, and leave the file whole.
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
            if (try? document.writeSafely(to: file, ofType: type.identifier, for: .autosaveElsewhereOperation)) != nil {
                // The Mac let it through after all (as the owner can); nothing to check.
                return nil
            }
            guard (try? Data(contentsOf: file)) == saved else {
                return MonkeyFailure(rule: "A failed save damaged the file that was there", detail: "Saving into a folder that can't be written to failed, and the file it would have replaced changed.")
            }
        } catch {
            return MonkeyFailure(rule: "Saving through the document failed", detail: "\(error)")
        }
        return nil
    }
}
