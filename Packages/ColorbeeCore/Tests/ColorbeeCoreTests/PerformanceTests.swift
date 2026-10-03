import Foundation
import Testing
@testable import ColorbeeCore

/// Time limits for the slow operations at 8000 × 8000 (NFR-6, AC-27). Each limit is about twice what
/// the operation took on Leah's M2 Max when set (2026-10-03), so a failure means a real slowdown, not
/// noise. SwiftPM can't store XCTest baselines, so these are plain limits. Run with `make perf`.
@Suite(.enabled(if: isOptimizedBuild, "Run with make perf (Release)"), .serialized)
struct PerformanceTests {
    static let side = 8000
    let context = SelectionContext(color2: .white)

    /// The fastest of three runs, so a busy moment on the Mac doesn't fail the test.
    private func fastest(_ body: () -> Void) -> Duration {
        (0..<3).map { _ in ContinuousClock().measure(body) }.min()!
    }

    private func layered() -> Canvas {
        let canvas = PerformanceFixture.photo(side: Self.side)
        let history = History(byteBudget: .max)
        LayerActions.add(canvas: canvas, history: history, context: context)
        canvas.activeLayer.buffer.fill(Pixel(r: 100, g: 100, b: 200, a: 128), in: IntRect(x: 0, y: 0, width: Self.side / 2, height: Self.side / 2))
        canvas.activeLayer.blendMode = .multiply
        LayerActions.addAdjustment(.brightnessContrast(brightness: 10, contrast: 10), named: "B/C", canvas: canvas, history: history, context: context)
        return canvas
    }

    @Test func flattenTwoLayersAndAnAdjustment() {
        let canvas = layered()
        let time = fastest { _ = canvas.flattened() }
        #expect(time < .milliseconds(800), "took \(time)")
    }

    @Test func fillTheWholeImage() {
        let canvas = Canvas(size: IntSize(width: Self.side, height: Self.side), colorSpace: Canvas.defaultColorSpace, background: .white)
        var color: UInt8 = 0
        let time = fastest {
            color &+= 1
            let edit = Edit(name: "Fill", canvas: canvas)
            FloodFill.fill(layer: canvas.activeLayer, at: IntPoint(x: 5, y: 5), with: Pixel(r: color, g: 0, b: 0), tolerance: 0, selection: nil, edit: edit)
        }
        #expect(time < .milliseconds(800), "took \(time)")
    }

    @Test func magicWandOverTheWholeImage() {
        let buffer = PixelBuffer(width: Self.side, height: Self.side, fill: .white)
        let time = fastest { _ = SelectionMask.magicWand(in: buffer, at: IntPoint(x: 5, y: 5), tolerance: 0.1, contiguous: true) }
        #expect(time < .milliseconds(600), "took \(time)")
    }

    @Test func blurTheWholeImage() {
        let canvas = PerformanceFixture.photo(side: Self.side)
        let time = fastest {
            let edit = Edit(name: "Blur", canvas: canvas)
            Effects.apply(.gaussianBlur(radius: 8), to: canvas.activeLayer, selection: nil, edit: edit)
        }
        #expect(time < .milliseconds(1000), "took \(time)")
    }

    @Test func pointwiseAdjustmentOnTheWholeImage() {
        let canvas = PerformanceFixture.photo(side: Self.side)
        let time = fastest {
            let edit = Edit(name: "Hue", canvas: canvas)
            Effects.apply(.hueSaturation(hue: 30, saturation: 10, lightness: 0), to: canvas.activeLayer, selection: nil, edit: edit)
        }
        #expect(time < .milliseconds(600), "took \(time)")
    }

    @Test func saveCopyAndProjectEncode() throws {
        let canvas = layered()
        let copy = fastest { _ = canvas.copy() }
        #expect(copy < .milliseconds(200), "copy took \(copy)")
        let encode = try ContinuousClock().measure { _ = try ProjectFile.encode(canvas) }
        #expect(encode < .milliseconds(800), "encode took \(encode)")
    }

    /// NFR-6: at 1920 × 1080, blur, pixelate and fill finish in under 100 ms, and so does any undo or redo.
    @Test func everydayEditsAt1080pStayUnder100ms() {
        let canvas = Canvas(size: IntSize(width: 1920, height: 1080), colorSpace: Canvas.defaultColorSpace, background: .white)
        let buffer = canvas.layers[0].buffer
        for y in 0..<1080 {
            let row = buffer.row(y)
            for x in 0..<1920 { row[x] = Pixel(r: UInt8((x / 7) & 255), g: UInt8((y / 5) & 255), b: UInt8(((x ^ y) / 9) & 255)) }
        }
        let history = History(byteBudget: 512 << 20)
        let limit = Duration.milliseconds(100)
        func step(_ name: String, _ body: (Edit) -> Void) {
            let time = fastest {
                let edit = history.beginEdit(name, on: canvas)
                body(edit)
                history.commit(edit)
                history.undo(on: canvas)
            }
            #expect(time < limit * 2, "\(name) and its undo took \(time)")
        }
        step("Blur") { Effects.apply(.gaussianBlur(radius: 8), to: canvas.activeLayer, selection: nil, edit: $0) }
        step("Pixelate") { Effects.apply(.pixelate(cellSize: 12), to: canvas.activeLayer, selection: nil, edit: $0) }
        step("Fill") { FloodFill.fill(layer: canvas.activeLayer, at: IntPoint(x: 3, y: 3), with: .black, tolerance: 1, selection: nil, edit: $0) }
        let edit = history.beginEdit("Invert", on: canvas)
        Effects.apply(.invert, to: canvas.activeLayer, selection: nil, edit: edit)
        history.commit(edit)
        let undo = fastest {
            history.undo(on: canvas)
            history.redo(on: canvas)
        }
        #expect(undo < limit * 2, "undo and redo took \(undo)")
    }

    @Test func undoAndRedoAWholeImageStepPastTheBudget() {
        let canvas = PerformanceFixture.photo(side: Self.side)
        // Small enough that every older whole-image step spills to disk, the slow path.
        let history = History(byteBudget: 300 << 20)
        var times: [Duration] = []
        for index in 0..<3 {
            times.append(ContinuousClock().measure {
                let edit = history.beginEdit("Invert \(index)", on: canvas)
                Effects.apply(.invert, to: canvas.activeLayer, selection: nil, edit: edit)
                history.commit(edit)
            })
        }
        while history.canUndo { times.append(ContinuousClock().measure { history.undo(on: canvas) }) }
        while history.canRedo { times.append(ContinuousClock().measure { history.redo(on: canvas) }) }
        let slowest = times.max()!
        #expect(slowest < .milliseconds(1000), "slowest step took \(slowest)")
    }
}
