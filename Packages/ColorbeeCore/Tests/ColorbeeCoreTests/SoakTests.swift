import Foundation
import Testing
@testable import ColorbeeCore

/// Optimized builds only: Debug pixel loops are ~50× slower, so the timings would mean nothing.
#if DEBUG
let isOptimizedBuild = false
#else
let isOptimizedBuild = true
#endif

/// AC-27 at 8000 × 8000: random drawing, effects and layer changes, then undo everything. No step may
/// take a second, and undoing all of it must bring back the exact original image (NFR-7). Run with `make perf`.
@Suite(.enabled(if: isOptimizedBuild, "Run with make perf (Release)"), .serialized)
struct SoakTests {
    static let side = 8000
    static let limit = Duration.seconds(1)
    /// Five full 8000 × 8000 layers are 1.3 GB of pixels; with many more, merely reading them back for an
    /// undo is over a second, which is the memory's speed rather than something to fix.
    static let maxLayers = 5
    let context = SelectionContext(color2: .white)

    /// One round by default. NFR-7's 30-minute session: `COLORBEE_SOAK_MINUTES=30 make perf`.
    @Test func randomEditsAt8000UndoBackWithNoStall() {
        let minutes = Double(ProcessInfo.processInfo.environment["COLORBEE_SOAK_MINUTES"] ?? "") ?? 0
        let deadline = ContinuousClock.now + .seconds(minutes * 60)
        let canvas = PerformanceFixture.photo(side: Self.side)
        var round: UInt64 = 0
        repeat {
            soakRound(canvas: canvas, seed: 0x50AC + round)
            round += 1
        } while ContinuousClock.now < deadline
        print("Soak: \(round) round(s)")
    }

    /// 60 random steps, then undo them all and redo them all, checking the image each way.
    private func soakRound(canvas: Canvas, seed: UInt64) {
        // The app's budget, so old steps spill to disk as they would in use.
        let history = History(byteBudget: 512 << 20)
        history.makeThumbnail = { $0.thumbnail(maxSide: 64) }
        let original = canvas.flattened().contentHash()
        let originalLayers = canvas.layers.count
        var random = SplitMix64(seed: seed)
        var slowest: (name: String, time: Duration) = ("", .zero)

        func timed(_ name: String, _ body: () -> Void) {
            let time = ContinuousClock().measure(body)
            if time > slowest.time { slowest = (name, time) }
            #expect(time < Self.limit, "\(name) took \(time)")
        }

        func randomRect() -> IntRect {
            let width = random.int(1..<Self.side), height = random.int(1..<Self.side)
            return IntRect(x: random.int(0..<(Self.side - width + 1)), y: random.int(0..<(Self.side - height + 1)), width: width, height: height)
        }

        for step in 0..<60 {
            let color = Pixel(r: random.byte(), g: random.byte(), b: random.byte())
            switch random.int(0..<10) {
            case 0:
                timed("Fill") {
                    let edit = history.beginEdit("Fill", on: canvas)
                    let seed = IntPoint(x: random.int(0..<Self.side), y: random.int(0..<Self.side))
                    FloodFill.fill(layer: canvas.activeLayer, at: seed, with: color, tolerance: 0.3, selection: nil, edit: edit)
                    history.commit(edit)
                }
            case 1:
                timed("Brush") {
                    let edit = history.beginEdit("Brush", on: canvas)
                    let stroke = Brush.round.makeStroke(diameter: Double(random.int(5..<200)), color: color, layer: canvas.activeLayer, edit: edit)
                    for _ in 0..<30 {
                        stroke.move(to: Point2D(x: Double(random.int(0..<Self.side)), y: Double(random.int(0..<Self.side))))
                    }
                    _ = stroke.finish()
                    history.commit(edit)
                }
            case 2:
                let effect: Effect = [.gaussianBlur(radius: 8), .pixelate(cellSize: 16), .sharpen(amount: 50), .invert][random.int(0..<4)]
                let selection = SelectionMask.rectangle(randomRect(), clippedTo: canvas.bounds)
                timed("Effect \(effect)") {
                    let edit = history.beginEdit("Effect", on: canvas)
                    Effects.apply(effect, to: canvas.activeLayer, selection: selection, edit: edit)
                    history.commit(edit)
                }
            case 3:
                timed("Rectangle fill") {
                    let edit = history.beginEdit("Rectangle", on: canvas)
                    let rect = randomRect()
                    edit.willModify(rect, in: canvas.activeLayer)
                    canvas.activeLayer.buffer.fill(color, in: rect)
                    history.commit(edit)
                }
            case 4 where canvas.layers.count < Self.maxLayers:
                timed("New Layer") { LayerActions.add(canvas: canvas, history: history, context: context) }
            case 5 where canvas.layers.count < Self.maxLayers:
                timed("Adjustment Layer") {
                    LayerActions.addAdjustment(.brightnessContrast(brightness: 10, contrast: 20), named: "B/C", canvas: canvas, history: history, context: context)
                }
            case 4, 5: continue
            case 6: timed("Merge Down") { LayerActions.mergeDown(canvas: canvas, history: history, context: context) }
            case 7: timed("Flatten") { LayerActions.flatten(canvas: canvas, history: history, context: context) }
            case 8:
                let orientation = Orientation.allCases[step % Orientation.allCases.count]
                timed("\(orientation.name)") { ImageActions.transform(orientation, canvas: canvas, history: history, context: context) }
            default:
                let mode = BlendMode.allCases[step % BlendMode.allCases.count]
                timed("Blend mode") {
                    LayerActions.update("Blend Mode", layerAt: canvas.activeLayerIndex, canvas: canvas, history: history) { $0.blendMode = mode }
                }
            }
        }
        timed("Export flatten") { _ = canvas.flattened() }
        let final = canvas.flattened().contentHash()

        while history.canUndo { timed("Undo") { history.undo(on: canvas) } }
        #expect(canvas.layers.count == originalLayers)
        #expect(canvas.flattened().contentHash() == original)

        while history.canRedo { timed("Redo") { history.redo(on: canvas) } }
        #expect(canvas.flattened().contentHash() == final)
        print("Soak: slowest step \(slowest.name), \(slowest.time); history \(history.byteCount >> 20) MB in memory")
    }
}

enum PerformanceFixture {
    /// A square image with varied color everywhere, like a photo, so nothing compresses or fills trivially.
    static func photo(side: Int) -> Canvas {
        let canvas = Canvas(size: IntSize(width: side, height: side), colorSpace: Canvas.defaultColorSpace, background: .white)
        let buffer = canvas.layers[0].buffer
        ParallelRows.forEach(0..<side) { rows in
            for y in rows {
                let row = buffer.row(y)
                for x in 0..<side { row[x] = Pixel(r: UInt8((x / 7) & 255), g: UInt8((y / 5) & 255), b: UInt8(((x ^ y) / 9) & 255)) }
            }
        }
        return canvas
    }
}
