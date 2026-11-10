import CoreGraphics
import Foundation
import Testing
@testable import ColorbeeCore

/// Known-good pictures for Adjust Photo (Leah, 2026-11-10): each control, and some together, on a small copy of a
/// practice photo, exported as `Canvas.flattened()` exports it and compared with a reference picture in
/// `TestImages/Known Good` that was looked over by eye. A control that changes what it does fails here, until the
/// references are made again on purpose with `make known-good` and looked over again.
@Suite(.serialized)
struct PhotoKnownGoodTests {
    private static let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    static let photos = here.appending(path: "../../../../TestImages/Photo Editing").standardized
    static let references = here.appending(path: "../../../../TestImages/Known Good").standardized
    static let review = here.appending(path: "../../../../build/Known Good Review").standardized
    static let writing = ProcessInfo.processInfo.environment["COLORBEE_WRITE_KNOWN_GOOD"] != nil

    struct Case: CustomTestStringConvertible, Sendable {
        let name: String
        let photo: String
        let edit: PhotoEdit
        /// Adjust Photo's Auto, worked out from the photo, in place of `edit`'s sliders.
        var auto = false
        var testDescription: String { name }
    }

    static let warmLook: ColorLook = {
        var lines = ["LUT_3D_SIZE 5"]
        for b in 0..<5 { for g in 0..<5 { for r in 0..<5 {
            let (rr, gg, bb) = (Double(r) / 4, Double(g) / 4, Double(b) / 4)
            lines.append("\(min(1, rr * 1.1 + 0.03)) \(gg * 0.98 + 0.01) \(bb * 0.8)")
        } } }
        return try! CubeFile.read(Data(lines.joined(separator: "\n").utf8), fallbackName: "Warm").look
    }()

    static let cases: [Case] = {
        func sliders(_ photo: String, _ values: [PhotoAdjustments.Slider: Double]) -> Case {
            let name = values.sorted { $0.key.title < $1.key.title }.map { "\($0.key.title) \(Int($0.value))" }.joined(separator: ", ")
            return Case(name: name, photo: photo, edit: PhotoEdit(adjustments: PhotoAdjustments(values)))
        }
        let (dull, cast, hazy, texture) = ("Dull Photo", "Color Cast", "Hazy", "Texture Practice")
        var mixer = ColorMixer()
        mixer[.hue, .red] = 30
        mixer[.saturation, .blue] = -60
        mixer[.luminance, .green] = 40
        mixer[.saturation, .aqua] = 50
        var blackAndWhite = ColorMixer()
        blackAndWhite.blackAndWhite = 1
        blackAndWhite[.gray, .green] = 40
        blackAndWhite[.gray, .blue] = -50
        var grading = ColorGrading()
        grading[.shadows] = ColorGrading.Wheel(hue: 220, strength: 40, luminance: -10)
        grading[.highlights] = ColorGrading.Wheel(hue: 40, strength: 35, luminance: 15)
        grading[.global] = ColorGrading.Wheel(hue: 300, strength: 10)
        grading.blending = 70
        grading.balance = -20
        let points = PointColors([PointColors.Swatch(color: Pixel(r: 100, g: 120, b: 175), hue: 30, saturation: -40, luminance: 20, range: 60),
                                  PointColors.Swatch(color: Pixel(r: 80, g: 105, b: 100), hue: -20, saturation: 40)])
        var curve = ToneCurve()
        curve.amounts = [25, -30, 35, -15]
        curve.splits = [20, 45, 80]
        var detail = PhotoDetail()
        detail.radius = 2.5
        detail.sharpnessDetail = 80
        detail.masking = 30
        detail.luminanceDetail = 30
        detail.color = 40
        detail.colorDetail = 70
        var effects = PhotoEffects()
        effects.midpoint = 30
        effects.roundness = 40
        effects.feather = 70
        effects.grainSize = 60
        effects.grainRoughness = 80
        let filters = ["Vivid Warm", "Dramatic Cool", "Noir"].compactMap { name in PhotoFilter.builtIn.first { $0.name == name } }
        var everything = PhotoAdjustments([.exposure: 20, .brilliance: 30, .highlights: -40, .shadows: 35, .contrast: 25, .saturation: 30,
                                           .vibrance: 20, .warmth: 25, .texture: 40, .dehaze: 20, .sharpness: 50, .definition: 30,
                                           .noiseReduction: 20, .vignette: -40, .grain: 20])
        everything[.tint] = -10
        return [
            sliders(dull, [.exposure: 50]), sliders(dull, [.exposure: -50]), sliders(dull, [.brilliance: 60]),
            sliders("Bright Photo", [.highlights: -70]), sliders(dull, [.shadows: 70]), sliders(dull, [.contrast: 50]),
            sliders(dull, [.contrast: -40]), sliders(dull, [.brightness: 40]), sliders(dull, [.whites: 50]),
            sliders(dull, [.blackPoint: 40]), sliders(dull, [.vignette: -70]), sliders(dull, [.vignette: 50]),
            sliders(dull, [.grain: 60]),
            sliders(cast, [.saturation: 60]), sliders(cast, [.saturation: -60]), sliders(cast, [.vibrance: 70]),
            sliders(cast, [.warmth: -60]), sliders(cast, [.tint: 50]),
            sliders(hazy, [.dehaze: 70]), sliders(hazy, [.dehaze: -40]),
            sliders(texture, [.texture: 80]), sliders(texture, [.texture: -60]), sliders(texture, [.sharpness: 80]),
            sliders(texture, [.definition: 80]), sliders(texture, [.noiseReduction: 80]),
            Case(name: "Detail settings", photo: texture, edit: PhotoEdit(adjustments: PhotoAdjustments([.sharpness: 60, .noiseReduction: 40]), detail: detail)),
            Case(name: "Vignette and Grain shapes", photo: dull, edit: PhotoEdit(adjustments: PhotoAdjustments([.vignette: -60, .grain: 50]), effects: effects)),
            Case(name: "Tone Curve", photo: dull, edit: PhotoEdit(toneCurve: curve)),
            Case(name: "Color Grading", photo: dull, edit: PhotoEdit(grading: grading)),
            Case(name: "Color Mixer", photo: cast, edit: PhotoEdit(mixer: mixer)),
            Case(name: "Black and White", photo: cast, edit: PhotoEdit(mixer: blackAndWhite)),
            Case(name: "Point Color", photo: cast, edit: PhotoEdit(pointColors: points)),
            Case(name: "A look at 70%", photo: dull, edit: PhotoEdit(filter: PhotoFilter(name: "Warm Look", steps: [.look(warmLook)]), filterIntensity: 70)),
            Case(name: "Everything at once", photo: dull, edit: PhotoEdit(adjustments: everything, mixer: mixer, grading: grading, pointColors: points,
                                                                          detail: detail, effects: effects, toneCurve: curve)),
            Case(name: "Auto on Dull Photo", photo: dull, edit: PhotoEdit(), auto: true),
            Case(name: "Auto on Color Cast", photo: cast, edit: PhotoEdit(), auto: true),
            Case(name: "Auto on Hazy", photo: hazy, edit: PhotoEdit(), auto: true),
        ] + filters.map { Case(name: "Filter \($0.name) at 80%", photo: dull, edit: PhotoEdit(filter: $0, filterIntensity: 80)) }
    }()

    /// Every fifth pixel of a practice photo: small, with no resampling code in between to change under it.
    static func small(_ photo: String) throws -> (PixelBuffer, CGColorSpace) {
        let decoded = try ImageCodec.decode(Data(contentsOf: photos.appending(path: "\(photo).png")))
        let full = decoded.buffer, step = 5
        let small = PixelBuffer(width: full.width / step, height: full.height / step)
        for y in 0..<small.height {
            let row = small.row(y), source = full.row(y * step)
            for x in 0..<small.width { row[x] = source[x * step] }
        }
        return (small, decoded.colorSpace)
    }

    /// The photo with the case's Adjust Photo layer on it, as an export flattens it.
    static func exported(_ test: Case) throws -> (before: PixelBuffer, after: PixelBuffer, colorSpace: CGColorSpace) {
        let (photo, space) = try small(test.photo)
        let canvas = Canvas(size: IntSize(width: photo.width, height: photo.height), colorSpace: space, background: .white)
        let base = canvas.layers[0].buffer
        for y in 0..<photo.height { base.row(y).update(from: photo.row(y), count: photo.width) }
        let layer = Layer(name: "Adjust Photo", buffer: PixelBuffer(width: photo.width, height: photo.height))
        layer.adjustment = .photo(test.auto ? PhotoEdit(adjustments: PhotoAdjustments.auto(for: photo)) : test.edit)
        canvas.insertLayer(layer, at: 1)
        return (photo, canvas.flattened(), space)
    }

    @Test(arguments: cases)
    func looksAsItDidWhenLookedOver(_ test: Case) throws {
        let (before, after, space) = try Self.exported(test)
        let file = Self.references.appending(path: "\(test.name).png")
        if Self.writing {
            try FileManager.default.createDirectory(at: Self.references, withIntermediateDirectories: true)
            try ImageCodec.encodePNG(after, colorSpace: space).write(to: file)
            try FileManager.default.createDirectory(at: Self.review, withIntermediateDirectories: true)
            try ImageCodec.encodePNG(before, colorSpace: space).write(to: Self.review.appending(path: "\(test.photo).png"))
            // Which photo the case started from, for the review page (Scripts/known-good-review.py).
            try Data(test.photo.utf8).write(to: Self.review.appending(path: "\(test.name).photo"))
            return
        }
        guard let data = try? Data(contentsOf: file) else {
            Issue.record("No known-good picture for \(test.name). Run make known-good, then look it over.")
            return
        }
        let reference = try ImageCodec.decode(data).buffer
        try #require(reference.width == after.width && reference.height == after.height)
        var largest = 0, apart = 0, changed = 0
        for y in 0..<after.height {
            let a = after.row(y), b = reference.row(y), c = before.row(y)
            for x in 0..<after.width {
                let d = max(abs(Int(a[x].r) - Int(b[x].r)), abs(Int(a[x].g) - Int(b[x].g)), abs(Int(a[x].b) - Int(b[x].b)), abs(Int(a[x].a) - Int(b[x].a)))
                largest = max(largest, d)
                if d > 2 { apart += 1 }
                if a[x] != c[x] { changed += 1 }
            }
        }
        // Rounding may move a level or two between Macs; a control that changed moves far more pixels further.
        #expect(largest <= 2, "\(test.name) no longer looks as it did: \(apart) pixels differ by more than 2 levels, by up to \(largest). If that's on purpose, run make known-good and look it over.")
        #expect(changed > after.width * after.height / 20, "\(test.name) hardly changes the photo, so its picture would prove little.")
    }
}
