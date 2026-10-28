import Foundation
import Testing
@testable import ColorbeeCore

/// Sharpness's Radius, Detail and Masking, and Luminance and Color noise reduction with their Detail (FR-9.7 item 5).
struct PhotoDetailTests {
    private let context = SelectionContext(color2: .white)

    /// Dark on the left, light on the right, with a little grain of `grain` levels in a checker pattern.
    private func edge(width: Int = 40, height: Int = 8, grain: Int = 0) -> PixelBuffer {
        let buffer = PixelBuffer(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width {
                let base = x < width / 2 ? 60 : 190
                let v = UInt8(base + ((x + y) % 2 == 0 ? grain : -grain))
                buffer.row(y)[x] = Pixel(r: v, g: v, b: v)
            }
        }
        return buffer
    }

    private func applied(_ edit: PhotoEdit, to buffer: PixelBuffer) -> PixelBuffer {
        let canvas = Canvas(colorSpace: Canvas.defaultColorSpace, layers: [Layer(name: "Photo", buffer: buffer.copy())],
                            hasTransparentBackground: false)
        Effects.apply(.photo(edit), to: canvas.activeLayer, selection: nil, edit: Edit(name: "Adjust Photo", canvas: canvas, recordsPixels: false))
        return canvas.activeLayer.buffer
    }

    private func sharpen(_ change: (inout PhotoDetail) -> Void = { _ in }, amount: Double = 80) -> PhotoEdit {
        var detail = PhotoDetail()
        change(&detail)
        return PhotoEdit(adjustments: PhotoAdjustments([.sharpness: amount]), detail: detail)
    }

    /// How far each column of row 4 is from the original, left to right.
    private func changes(_ result: PixelBuffer, from original: PixelBuffer) -> [Int] {
        (0..<original.width).map { abs(Int(result.row(4)[$0].r) - Int(original.row(4)[$0].r)) }
    }

    @Test func atTheirStartTheSettingsChangeNothing() {
        let photo = edge(grain: 6)
        let plain = PhotoEdit(adjustments: PhotoAdjustments([.sharpness: 60, .noiseReduction: 40]))
        let explicit = PhotoEdit(adjustments: PhotoAdjustments([.sharpness: 60, .noiseReduction: 40]), detail: PhotoDetail())
        #expect(explicit.detail == nil)
        #expect(applied(plain, to: photo).contentHash() == applied(explicit, to: photo).contentHash())
    }

    @Test func aWiderRadiusSharpensFurtherFromTheEdge() {
        let photo = edge()
        let narrow = changes(applied(sharpen { $0.radius = 0.5 }, to: photo), from: photo)
        let wide = changes(applied(sharpen { $0.radius = 3 }, to: photo), from: photo)
        // Four pixels from the edge, only the wide radius reaches.
        #expect(narrow[16] == 0 && wide[16] > 0)
    }

    @Test func lowDetailHoldsBackHalosAndHighDetailBringsOutFineGrain() {
        let photo = edge(grain: 3)
        let normal = changes(applied(sharpen(), to: photo), from: photo)
        let low = changes(applied(sharpen { $0.sharpnessDetail = 0 }, to: photo), from: photo)
        let high = changes(applied(sharpen { $0.sharpnessDetail = 100 }, to: photo), from: photo)
        // At the edge (column 19 and 20) the halo is smaller with low Detail...
        #expect(low[19] < normal[19] && low[20] < normal[20])
        // ...and away from it the fine grain is brought out more with high Detail.
        #expect(high[8] > normal[8])
    }

    @Test func maskingLeavesFlatAreasAlone() {
        let photo = edge(grain: 3)
        let everywhere = changes(applied(sharpen(), to: photo), from: photo)
        let masked = changes(applied(sharpen { $0.masking = 80 }, to: photo), from: photo)
        #expect(everywhere[6] > 0 && masked[6] == 0)
        #expect(masked[19] > 0 && masked[20] > 0)
    }

    @Test func theMaskViewIsWhiteAtEdgesAndBlackInFlatAreas() {
        var edit = sharpen { $0.masking = 80 }
        edit.showsSharpeningMask = true
        let mask = applied(edit, to: edge(grain: 3))
        #expect(mask.row(4)[6] == Pixel(r: 0, g: 0, b: 0) && mask.row(4)[20].r > 200)
        // It's never saved.
        let decoded = try? JSONDecoder().decode(PhotoEdit.self, from: JSONEncoder().encode(edit))
        #expect(decoded?.showsSharpeningMask == false && decoded?.detail?.masking == 80)
    }

    @Test func colorNoiseReductionSmoothsColorAndKeepsBrightness() {
        // Gray with red and green speckles of the same brightness change.
        let photo = PixelBuffer(width: 24, height: 24)
        for y in 0..<24 {
            for x in 0..<24 {
                photo.row(y)[x] = (x + y) % 2 == 0 ? Pixel(r: 150, g: 120, b: 120) : Pixel(r: 110, g: 134, b: 130)
            }
        }
        var detail = PhotoDetail()
        detail.color = 100
        let result = applied(PhotoEdit(detail: detail), to: photo)
        func spread(_ p: Pixel) -> Int { Int(max(p.r, p.g, p.b)) - Int(min(p.r, p.g, p.b)) }
        let before = photo.row(12)[12], after = result.row(12)[12]
        #expect(spread(after) < spread(before) / 2)
        func luma(_ p: Pixel) -> Double { 0.2126 * Double(p.r) + 0.7152 * Double(p.g) + 0.0722 * Double(p.b) }
        #expect(abs(luma(after) - luma(before)) < 1.5)
        #expect(!PhotoEdit(detail: detail).isNeutral)
    }

    @Test func luminanceDetailKeepsMoreGrainWhenHigher() {
        let photo = edge(grain: 8)
        func noise(_ detail: Double) -> Int {
            var settings = PhotoDetail()
            settings.luminanceDetail = detail
            let result = applied(PhotoEdit(adjustments: PhotoAdjustments([.noiseReduction: 80]), detail: settings), to: photo)
            return abs(Int(result.row(4)[6].r) - Int(result.row(4)[7].r))
        }
        #expect(noise(100) > noise(50) && noise(50) >= noise(0))
    }

    @Test func settingsAreSavedKeptInRangeAndLeftOutOfFilters() throws {
        var detail = PhotoDetail()
        detail.radius = 2.5
        detail.masking = 40
        detail.color = 30
        let edit = PhotoEdit(adjustments: PhotoAdjustments([.sharpness: 50]), detail: detail)
        #expect(try JSONDecoder().decode(PhotoEdit.self, from: JSONEncoder().encode(edit)) == edit)
        let json = #"{"radius": 9, "masking": -4, "color": "a lot"}"#
        let read = try JSONDecoder().decode(PhotoDetail.self, from: Data(json.utf8))
        #expect(read.radius == 3 && read.masking == 0 && read.color == 0 && read.colorDetail == 50)
        #expect(edit.filterPart.detail == nil && edit.partFiltersLeaveOut.detail == detail)
    }
}
