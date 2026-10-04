import Foundation
import Testing
@testable import ColorbeeCore

/// Regression tests for the findings of cloud reviews H, I and J (Docs/Review/findings-H.md, -I.md, -J.md).
struct ReviewHIJTests {
    private let context = SelectionContext(color2: .white)

    /// H5: the spill file can't outlive Colorbee, even after a crash: it's unlinked as soon as it's open.
    @Test func theSpillFileHasNoNameOnDisk() throws {
        let store = try SpillStore()
        let location = try store.write([Pixel](repeating: Pixel(r: 1, g: 2, b: 3), count: 64))
        #expect(!FileManager.default.fileExists(atPath: store.path))
        #expect(try store.read(location, count: 64).first == Pixel(r: 1, g: 2, b: 3))
    }

    /// H7: pixels Remove Background makes fully transparent keep none of their old color.
    @Test func removeBackgroundLeavesNoHiddenColor() {
        let canvas = Canvas(size: IntSize(width: 2, height: 1), colorSpace: Canvas.defaultColorSpace, background: Pixel(r: 200, g: 100, b: 50))
        let history = History(byteBudget: 512 << 20)
        SubjectActions.removeBackground([0, 255], canvas: canvas, history: history, context: context)
        #expect(canvas.layers[0].buffer.row(0)[0] == .clear)
        #expect(canvas.layers[0].buffer.row(0)[1] == Pixel(r: 200, g: 100, b: 50))
    }

    /// I3: fully transparent pixels count as one color, whatever their hidden channels.
    @Test func transparentPixelsAreOneColorToFillAndTheWand() throws {
        let buffer = PixelBuffer(width: 3, height: 1)
        buffer.row(0)[0] = Pixel(r: 10, g: 20, b: 30, a: 0)
        buffer.row(0)[1] = Pixel(r: 200, g: 0, b: 0, a: 0)
        let wand = try #require(SelectionMask.magicWand(in: buffer, at: IntPoint(x: 0, y: 0), tolerance: 0, contiguous: true))
        #expect((0..<3).allSatisfy { wand[$0, 0] > 0 })
    }

    /// J19: a damaged project whose layers share an id is refused, not a crash.
    @Test func aProjectWithRepeatedLayerIDsIsDamaged() throws {
        let canvas = Canvas(size: IntSize(width: 4, height: 4), colorSpace: Canvas.defaultColorSpace, background: .white)
        LayerActions.add(canvas: canvas, history: History(byteBudget: 512 << 20), context: context)
        let data = try ProjectFile.encode(canvas)
        let first = canvas.layers[0].id.rawValue.uuidString, second = canvas.layers[1].id.rawValue.uuidString
        let damaged = try #require(String(data: data, encoding: .isoLatin1)?.replacingOccurrences(of: second, with: first).data(using: .isoLatin1))
        #expect(throws: ProjectFile.Failure.damaged) { try ProjectFile.decode(damaged) }
    }

    /// J20: a pixel range near Int.max is refused, not an overflow.
    @Test func aProjectWithAHugePixelOffsetIsDamaged() throws {
        let canvas = Canvas(size: IntSize(width: 4, height: 4), colorSpace: Canvas.defaultColorSpace, background: .white)
        let data = try ProjectFile.encode(canvas)
        let jsonStart = ProjectFile.magic.count + 4
        let length = Int(data[ProjectFile.magic.count..<jsonStart].withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) })
        var manifest = try JSONDecoder().decode(ProjectFile.Manifest.self, from: data[jsonStart..<(jsonStart + length)])
        manifest.layers[0].pixels = (Int.max - 1)..<Int.max
        let json = try JSONEncoder().encode(manifest)
        var damaged = Data(ProjectFile.magic)
        var newLength = UInt32(json.count).littleEndian
        damaged.append(Data(bytes: &newLength, count: 4))
        damaged.append(json)
        damaged.append(data[(jsonStart + length)...])
        #expect(throws: ProjectFile.Failure.damaged) { try ProjectFile.decode(damaged) }
    }
}

extension ReviewHIJTests {
    /// H3: Batch Redact covers every layer under the selection, like Auto-Redact.
    @Test func batchRedactCoversTheLayerBelowTheActiveOne() throws {
        let canvas = Canvas(size: IntSize(width: 16, height: 16), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: 512 << 20)
        LayerActions.add(canvas: canvas, history: history, context: context)
        let box = IntRect(x: 2, y: 2, width: 6, height: 6)
        let selection = try #require(SelectionMask.rectangle(box, clippedTo: canvas.bounds))
        let outcome = AutoRedact.apply(.solidFill(Pixel(r: 9, g: 9, b: 9)), in: selection, canvas: canvas, history: history)
        #expect(outcome == .redacted)
        #expect(canvas.layers[0].buffer.row(4)[4] == Pixel(r: 9, g: 9, b: 9))
        canvas.layers[0].isLocked = true
        #expect(AutoRedact.apply(.solidFill(.black), in: selection, canvas: canvas, history: history) == .locked(layerName: "Background"))
    }
}
