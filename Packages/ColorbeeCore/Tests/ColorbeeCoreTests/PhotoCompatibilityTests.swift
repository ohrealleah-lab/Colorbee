import Foundation
import Testing
@testable import ColorbeeCore

/// Files saved before stage 1a still open as they did, and beta 7 can still read what's saved now (FR-9.7's rule).
struct PhotoCompatibilityTests {
    private typealias S = PhotoAdjustments.Slider
    private static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appending(path: "../../../../TestImages/Photo Editing").standardized

    /// `Old Adjust Photo.colorproj` and the picture it showed, both saved by the code before stage 1a.
    @Test func theOldProjectLooksExactlyAsBefore() throws {
        let canvas = try ProjectFile.decode(Data(contentsOf: Self.folder.appending(path: "Old Adjust Photo.colorproj")))
        let before = try ImageCodec.decode(Data(contentsOf: Self.folder.appending(path: "Old Adjust Photo (as shown before stage 1a).png")))
        let now = canvas.flattened()
        #expect(now.size == before.buffer.size)
        #expect(now.pixels(in: now.bounds) == before.buffer.pixels(in: before.buffer.bounds))
    }

    @Test func theOldProjectKeepsEverySetting() throws {
        let canvas = try ProjectFile.decode(Data(contentsOf: Self.folder.appending(path: "Old Adjust Photo.colorproj")))
        #expect(canvas.layers.map(\.name) == ["Background", "Layer Below Only", "Every Slider", "Vivid Warm 60%"])
        #expect(canvas.layers.map(\.clipsToLayerBelow) == [false, true, false, false])
        guard case .photo(let every) = canvas.layers[2].adjustment, case .photo(let withFilter) = canvas.layers[3].adjustment else {
            Issue.record("Not Adjust Photo layers")
            return
        }
        #expect(every.adjustments.values.count == 15)
        #expect(every.adjustments[.vignette] == -25 && every.adjustments[.sharpness] == 30)
        #expect(withFilter.filter?.name == "Vivid Warm" && withFilter.filterIntensity == 60)
        #expect(withFilter.adjustments == PhotoAdjustments([.exposure: -5, .contrast: 10, .warmth: -8]))
    }

    @Test func theOldFilterImportsAsBefore() throws {
        let filter = try PhotoFilter.imported(from: Data(contentsOf: Self.folder.appending(path: "Old Filter.colorbeefilter")))
        #expect(filter.name == "Old Filter")
        #expect(filter.steps.count == 1)
        guard case .photo(let edit) = filter.steps[0] else { Issue.record("Not a photo step"); return }
        #expect(edit.filter?.name == "Vivid Warm" && edit.filterIntensity == 60)
    }

    // MARK: Beta 7

    /// How beta 7 reads Adjust Photo's sliders: a dictionary keyed by the fifteen it knows, so any other name in
    /// `values` fails the whole adjustment. Kept here so newer files are checked against it.
    private struct Beta7Adjustments: Decodable {
        enum Slider: String, Decodable {
            case exposure, brilliance, highlights, shadows, contrast, brightness, blackPoint
            case saturation, vibrance, warmth, tint
            case sharpness, definition, noiseReduction, vignette
        }
        let values: [Slider: Double]
    }

    @Test func beta7ReadsWhatIsSavedNow() throws {
        let adjustments = PhotoAdjustments(Dictionary(uniqueKeysWithValues: S.allCases.enumerated().map { ($0.element, Double($0.offset + 1)) }))
        let read = try JSONDecoder().decode(Beta7Adjustments.self, from: JSONEncoder().encode(adjustments))
        #expect(read.values.count == S.original.count)
        #expect(read.values[.vignette] == adjustments[.vignette])
    }

    @Test func beta7SkipsSlidersSavedUnderAdded() throws {
        // Where a slider added after beta 7 (such as Whites) is saved.
        let json = #"{"values": ["exposure", 20], "added": {"whites": 30}}"#
        let read = try JSONDecoder().decode(Beta7Adjustments.self, from: Data(json.utf8))
        #expect(read.values == [.exposure: 20])
        // A name beta 7 doesn't know in `values` is what loses the whole adjustment there.
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(Beta7Adjustments.self, from: Data(#"{"values": ["exposure", 20, "whites", 30]}"#.utf8))
        }
    }

    @Test func unknownSlidersAreSkippedNotTheAdjustment() throws {
        let json = #"{"values": ["exposure", 20, "fromTheFuture", 5], "added": {"alsoNew": 7, "warmth": -10}}"#
        let read = try JSONDecoder().decode(PhotoAdjustments.self, from: Data(json.utf8))
        #expect(read == PhotoAdjustments([.exposure: 20, .warmth: -10]))
    }

    @Test func slidersRoundTrip() throws {
        let adjustments = PhotoAdjustments([.exposure: 12, .tint: -4, .vignette: -30, .noiseReduction: 55])
        #expect(try JSONDecoder().decode(PhotoAdjustments.self, from: JSONEncoder().encode(adjustments)) == adjustments)
    }

    @Test func aFilterStepOfAnUnknownKindIsSkipped() throws {
        let json = #"""
        {"version": 1, "name": "Mixed", "steps": [
            {"kind": "fromTheFuture", "values": [1]},
            {"kind": "sepia", "values": [40]}
        ]}
        """#
        let filter = try PhotoFilter.imported(from: Data(json.utf8))
        #expect(filter.steps == [.sepia(amount: 40)])
        #expect(throws: (any Error).self) {
            try PhotoFilter.imported(from: Data(#"{"version": 1, "name": "None", "steps": [{"kind": "fromTheFuture"}]}"#.utf8))
        }
    }
}
