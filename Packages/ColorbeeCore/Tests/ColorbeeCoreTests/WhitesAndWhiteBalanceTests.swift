import Foundation
import Testing
@testable import ColorbeeCore

/// Whites, Auto's Whites and the white-balance eyedropper's math (FR-9.7 item 1, stage 1b).
struct WhitesAndWhiteBalanceTests {
    private static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appending(path: "../../../../TestImages/Photo Editing").standardized

    private func gray(_ value: UInt8) -> Pixel { Pixel(r: value, g: value, b: value) }

    @Test func whitesMovesTheBrightestPartsMost() {
        let up = PhotoAdjustments([.whites: 60]).colorTransform
        let down = PhotoAdjustments([.whites: -60]).colorTransform
        // Darks don't move at all, mids a little, brights most.
        #expect(up(gray(50)) == gray(50))
        let mid = Int(up(gray(128)).r) - 128, bright = Int(up(gray(200)).r) - 200
        #expect(mid >= 0 && bright > 3 * max(mid, 1))
        #expect(down(gray(200)).r < 200 && down(gray(50)) == gray(50))
        #expect(PhotoAdjustments([.whites: 100]).colorTransform(gray(220)) == gray(255))
        // A colored pixel keeps its order of channels.
        let color = up(Pixel(r: 220, g: 180, b: 120))
        #expect(color.r > color.g && color.g > color.b)
    }

    @Test func whitesIsSavedWhereBeta7DoesntLook() throws {
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(PhotoAdjustments([.whites: 30, .exposure: 10]))) as! [String: Any]
        #expect((json["values"] as? [Any])?.count == 2)
        #expect((json["added"] as? [String: Double]) == ["whites": 30])
        #expect(try JSONDecoder().decode(PhotoAdjustments.self, from: JSONEncoder().encode(PhotoAdjustments([.whites: 30]))) == PhotoAdjustments([.whites: 30]))
    }

    @Test func whitesIsInFiltersAndScales() {
        #expect(PhotoAdjustments.Slider.whites.inFilters)
        let filter = PhotoFilter(name: "Bright", adjustments: PhotoAdjustments([.whites: 40]))
        guard case .photo(let half) = filter.steps(atIntensity: 0.5)[0] else { Issue.record("Not a photo step"); return }
        #expect(half.adjustments == PhotoAdjustments([.whites: 20]))
    }

    @Test func autoRaisesWhitesOnlyWhenTheBrightsFallShort() throws {
        let dull = try ImageCodec.decode(Data(contentsOf: Self.folder.appending(path: "Dull Photo.png"))).buffer
        let bright = try ImageCodec.decode(Data(contentsOf: Self.folder.appending(path: "Bright Photo.png"))).buffer
        let dullWhites = PhotoAdjustments.auto(for: dull)[.whites]
        #expect(dullWhites > 0 && dullWhites <= 50)
        #expect(PhotoAdjustments.auto(for: bright)[.whites] == 0)
        #expect(PhotoAdjustments.autoSliders.contains(.whites))
    }

    @Test func theEyedropperMakesAGrayPatchGray() {
        // Casts Warmth and Tint can reach: Color Cast.png's gray card (also under Vivid Warm, as in the hand test),
        // and a green one.
        let card = Pixel(r: 132, g: 144, b: 165), green = Pixel(r: 120, g: 140, b: 125)
        let vividHalf = PhotoEdit(filter: PhotoFilter.builtIn[0], filterIntensity: 50)
        for (sample, edit) in [(card, PhotoEdit()), (card, vividHalf), (card, PhotoEdit(filter: PhotoFilter.builtIn[1])), (green, PhotoEdit()), (green, vividHalf)] {
            let out = edit.neutralizing(sample).colorTransform(sample)
            let channels = [Int(out.r), Int(out.g), Int(out.b)]
            #expect(channels.max()! - channels.min()! <= 1, "\(sample) came out \(out)")
        }
    }

    @Test func theEyedropperGoesAsFarAsItCan() {
        let fixed = PhotoEdit().neutralizing(Pixel(r: 40, g: 60, b: 230))
        #expect(fixed.adjustments[.warmth] == 100)
        // More Saturation on top of Vivid Warm makes the gray card's cast stronger before Warmth applies, beyond its reach.
        let saturated = PhotoEdit(adjustments: PhotoAdjustments([.exposure: 20, .saturation: 30]), filter: PhotoFilter.builtIn[1], filterIntensity: 80)
        #expect(saturated.neutralizing(Pixel(r: 132, g: 144, b: 165)).adjustments[.warmth] == 100)
        #expect(PhotoEdit().neutralizing(.black).adjustments[.warmth] == 0)
        // The other settings are kept; only Warmth and Tint change.
        let edit = PhotoEdit(adjustments: PhotoAdjustments([.exposure: 15, .warmth: -40, .tint: 30]))
        #expect(edit.neutralizing(gray(128)).adjustments == PhotoAdjustments([.exposure: 15]))
    }

    @Test func theAverageIsWeightedByOpacity() {
        let buffer = PixelBuffer(width: 4, height: 4)
        buffer.row(1)[1] = Pixel(r: 200, g: 100, b: 0, a: 255)
        buffer.row(1)[2] = Pixel(r: 0, g: 100, b: 200, a: 85)
        #expect(buffer.averageColor(in: IntRect(x: 0, y: 0, width: 4, height: 4)) == Pixel(r: 150, g: 100, b: 50))
        #expect(buffer.averageColor(in: IntRect(x: 2, y: 2, width: 9, height: 9)) == nil)
    }

    @Test func aPatchAsShownMatchesTheWholeComposite() {
        let canvas = Canvas(size: IntSize(width: 8, height: 6), colorSpace: Canvas.defaultColorSpace, background: Pixel(r: 90, g: 120, b: 200))
        let history = History(byteBudget: .max), context = SelectionContext(color2: .white)
        LayerActions.addAdjustment(.hueSaturation(hue: 40, saturation: 20, lightness: 0), named: "Hue", canvas: canvas, history: history, context: context)
        LayerActions.addAdjustment(.invert, named: "Invert", canvas: canvas, history: history, context: context)
        let rect = IntRect(x: 2, y: 1, width: 5, height: 5)
        let whole = canvas.composited(through: 1)
        #expect(canvas.patchAsShown(rect, through: 1).pixels(in: IntRect(x: 0, y: 0, width: 5, height: 5)) == whole.pixels(in: rect))
        #expect(canvas.pixelAsShown(at: IntPoint(x: 3, y: 3)) == canvas.flattened().pixels(in: IntRect(x: 3, y: 3, width: 1, height: 1))[0])
    }
}
