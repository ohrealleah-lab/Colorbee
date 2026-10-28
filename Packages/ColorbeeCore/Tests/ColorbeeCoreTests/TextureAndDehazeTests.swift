import Foundation
import Testing
@testable import ColorbeeCore

/// Texture and Dehaze (FR-9.7 item 1, stage 3).
struct TextureAndDehazeTests {
    private static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appending(path: "../../../../TestImages/Photo Editing").standardized

    private func spread(_ pixels: [Pixel]) -> Double {
        let values = pixels.map { Double($0.luminance) }
        let mean = values.reduce(0, +) / Double(values.count)
        return (values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)).squareRoot()
    }

    @Test func dehazeTakesOffAnEvenVeilAndKeepsWhiteWhite() {
        let colors = [Pixel(r: 200, g: 40, b: 30), Pixel(r: 60, g: 90, b: 70), Pixel(r: 120, g: 150, b: 210)]
        // −50 lays a 30% veil of haze gray on; +50 takes it off again.
        let addHaze = PhotoAdjustments([.dehaze: -50]).colorTransform, remove = PhotoAdjustments([.dehaze: 50]).colorTransform
        for color in colors {
            let hazy = addHaze(color)
            #expect(Int(hazy.r) > Int(color.r) - 60 && hazy.luminance > color.luminance)
            let back = remove(hazy)
            #expect(abs(Int(back.r) - Int(color.r)) <= 1 && abs(Int(back.g) - Int(color.g)) <= 1 && abs(Int(back.b) - Int(color.b)) <= 1)
        }
        #expect(remove(.white) == .white)
        #expect(PhotoAdjustments([.dehaze: 0]).colorTransform(colors[0]) == colors[0])
    }

    @Test func dehazeBringsBackContrastInAHazyPhoto() throws {
        let hazy = try ImageCodec.decode(Data(contentsOf: Self.folder.appending(path: "Hazy.png"))).buffer
        let hills = IntRect(x: 0, y: 620, width: 1600, height: 300)
        let before = hazy.pixels(in: hills)
        let after = before.map(PhotoAdjustments([.dehaze: 50]).colorTransform)
        #expect(spread(after) > spread(before) * 1.3)
    }

    @Test func textureWorksOnFineDetailWithoutWideHalos() {
        // A flat field with 3-pixel grain on the left and a hard edge at x = 40.
        let buffer = PixelBuffer(width: 80, height: 24, fill: Pixel(r: 100, g: 100, b: 100))
        for y in 0..<24 { for x in 0..<20 where (x / 3 + y / 3) % 2 == 0 { buffer.row(y)[x] = Pixel(r: 130, g: 130, b: 130) } }
        for y in 0..<24 { for x in 40..<80 { buffer.row(y)[x] = Pixel(r: 200, g: 200, b: 200) } }
        func run(_ values: [PhotoAdjustments.Slider: Double]) -> PixelBuffer {
            Effects.photoAdjusted(buffer, region: buffer.bounds, edit: PhotoEdit(adjustments: PhotoAdjustments(values)), selection: nil).0
        }
        let grain = IntRect(x: 4, y: 4, width: 12, height: 16)
        #expect(spread(run([.texture: 80]).pixels(in: grain)) > spread(buffer.pixels(in: grain)) * 1.2)
        #expect(spread(run([.texture: -80]).pixels(in: grain)) < spread(buffer.pixels(in: grain)) * 0.9)
        // Fourteen pixels from the edge, Definition still glows; Texture leaves it alone.
        let near = IntRect(x: 26, y: 12, width: 1, height: 1)
        #expect(run([.texture: 100]).pixels(in: near) == buffer.pixels(in: near))
        #expect(run([.definition: 100]).pixels(in: near) != buffer.pixels(in: near))
    }

    @Test func dehazeIsInFiltersAndTextureIsnt() throws {
        #expect(PhotoAdjustments.Slider.dehaze.inFilters && !PhotoAdjustments.Slider.texture.inFilters)
        let filter = PhotoFilter(name: "Clear", adjustments: PhotoAdjustments([.dehaze: 50, .texture: 40]))
        #expect(filter.steps == [.photo(PhotoEdit(adjustments: PhotoAdjustments([.dehaze: 50])))])
        // Both are saved where beta 7 doesn't look.
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(PhotoAdjustments([.dehaze: 50, .texture: 40]))) as! [String: Any]
        #expect((json["added"] as? [String: Double]) == ["dehaze": 50, "texture": 40])
    }
}
