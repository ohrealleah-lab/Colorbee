import Foundation
import Testing
@testable import ColorbeeCore

/// Adjust Photo's parametric Tone Curve (FR-9.7 item 6).
struct ToneCurveTests {
    private func curve(_ amounts: [ToneCurve.Region: Double], splits: [Double]? = nil) -> ToneCurve {
        var curve = ToneCurve()
        for (region, amount) in amounts { curve[region] = amount }
        if let splits { curve.splits = splits }
        return curve
    }

    @Test func untouchedItChangesNothing() {
        #expect(ToneCurve().table == (0...255).map { UInt8($0) })
        #expect(ToneCurve().isDefault && ToneCurve().isNeutral)
    }

    @Test func darksDarkenTheLowerMiddleAndLeaveTheEnds() {
        let table = curve([.darks: -40]).table
        #expect(table[0] == 0 && table[255] == 255)
        // Darks is centered between the first two splits, at 37.5%.
        #expect(table[96] < 96 && table[96] >= 80)
        #expect(table[230] == 230 || table[230] == 229)
        #expect(table[96] < table[64] + 32)
        // Lights mirrors it, above the middle.
        let lights = curve([.lights: 40]).table
        #expect(lights[160] > 160 && lights[30] == 30)
    }

    @Test func movingASplitMovesTheChange() {
        let standard = curve([.darks: -60]).table
        let wider = curve([.darks: -60], splits: [40, 70, 85]).table
        // Darks now centers at 55% rather than 37.5%.
        #expect(Int(wider[140]) - 140 < Int(standard[140]) - 140)
        #expect(Int(wider[60]) - 60 > Int(standard[60]) - 60)
    }

    @Test func theCurveAlwaysRises() {
        let extremes: [Double] = [-100, 100]
        for shadows in extremes {
            for darks in extremes {
                for lights in extremes {
                    for highlights in extremes {
                        for splits in [[25.0, 50, 75], [5, 10, 15], [85, 90, 95], [10, 50, 90]] {
                            let table = curve([.shadows: shadows, .darks: darks, .lights: lights, .highlights: highlights], splits: splits).table
                            #expect(zip(table, table.dropFirst()).allSatisfy { $0 <= $1 })
                        }
                    }
                }
            }
        }
    }

    @Test func splitsStayInOrderAndApart() {
        var curve = ToneCurve()
        curve.setSplit(0, to: 70)
        #expect(curve.splits == [45, 50, 75])
        curve.setSplit(2, to: 100)
        #expect(curve.splits[2] == 95)
        curve.setSplit(1, to: 0)
        #expect(curve.splits == [45, 50, 95])
        // Moved splits with no amounts are still kept.
        #expect(!curve.isDefault && curve.isNeutral)
        #expect(PhotoEdit(toneCurve: curve).toneCurve?.splits == curve.splits)
    }

    @Test func intensityScalesOnlyTheAmounts() {
        let scaled = curve([.darks: -40, .highlights: 20], splits: [30, 50, 80]).scaled(by: 0.5)
        #expect(scaled.amounts == [0, -20, 0, 10] && scaled.splits == [30, 50, 80])
        let filter = PhotoFilter(name: "Fade", steps: [.photo(PhotoEdit(toneCurve: curve([.shadows: 60])))])
        guard case .photo(let atHalf) = filter.steps(atIntensity: 0.5).first else { Issue.record(); return }
        #expect(atHalf.toneCurve?[.shadows] == 30)
    }

    @Test func itComesAfterTheSlidersInAdjustPhoto() {
        let tone = curve([.lights: 50])
        let alone = PhotoEdit(toneCurve: tone).colorTransform
        let pixel = Pixel(r: 170, g: 120, b: 60)
        #expect(alone(pixel) == tone.transform(pixel))
        let both = PhotoEdit(adjustments: PhotoAdjustments([.exposure: 20]), toneCurve: tone)
        #expect(both.colorTransform(pixel) == tone.transform(PhotoAdjustments([.exposure: 20]).colorTransform(pixel)))
        #expect(both.filterPart.toneCurve == tone && both.partFiltersLeaveOut.toneCurve == nil)
        #expect(!PhotoEdit(toneCurve: tone).isNeutral)
    }

    @Test func itsSavedAndDamagedValuesAreLeftOut() throws {
        let edit = PhotoEdit(toneCurve: curve([.darks: -25], splits: [20, 45, 70]))
        #expect(try JSONDecoder().decode(PhotoEdit.self, from: JSONEncoder().encode(edit)) == edit)
        let json = #"{"amounts": [500, -20, 0], "splits": [60, 40, 80]}"#
        let read = try JSONDecoder().decode(ToneCurve.self, from: Data(json.utf8))
        #expect(read.amounts == [0, 0, 0, 0] && read.splits == ToneCurve.defaultSplits)
        let clamped = try JSONDecoder().decode(ToneCurve.self, from: Data(#"{"amounts": [500, -20, 0, 1]}"#.utf8))
        #expect(clamped.amounts == [100, -20, 0, 1])
    }

    @Test func thumbnailsAndTheirHistogramsShowAdjustPhotoLayers() {
        let canvas = Canvas(size: IntSize(width: 20, height: 20), colorSpace: Canvas.defaultColorSpace, background: Pixel(r: 100, g: 100, b: 100))
        let before = Histogram(canvas.thumbnail(maxSide: 20))
        LayerActions.addAdjustment(.photo(PhotoEdit(adjustments: PhotoAdjustments([.exposure: 60]))), named: "Brighter", canvas: canvas,
                                   history: History(byteBudget: .max), context: SelectionContext(color2: .white))
        let after = Histogram(canvas.thumbnail(maxSide: 20))
        #expect((after.highestValue ?? 0) > (before.highestValue ?? 0))
    }
}
