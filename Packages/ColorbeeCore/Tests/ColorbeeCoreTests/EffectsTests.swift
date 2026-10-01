import CoreGraphics
import Foundation
import Testing
@testable import ColorbeeCore

struct EffectsTests {
    private let red = Pixel(r: 255, g: 0, b: 0)
    private let blue = Pixel(r: 0, g: 0, b: 255)

    private func makeCanvas(width: Int = 60, height: Int = 60) -> (Canvas, History) {
        (Canvas(size: IntSize(width: width, height: height), colorSpace: Canvas.defaultColorSpace, background: .white),
         History(byteBudget: .max))
    }

    private func stripes(_ canvas: Canvas) {
        for x in stride(from: 0, to: canvas.size.width, by: 2) {
            canvas.activeLayer.buffer.fill(.black, in: IntRect(x: x, y: 0, width: 1, height: canvas.size.height))
        }
    }

    @Test func blurLeavesAUniformAreaUnchanged() {
        let (canvas, history) = makeCanvas()
        let edit = history.beginEdit("Blur", on: canvas)
        Effects.apply(.gaussianBlur(radius: 5), to: canvas.activeLayer, selection: nil, edit: edit)
        #expect(canvas.activeLayer.buffer[30, 30] == .white)
        #expect(canvas.activeLayer.buffer[0, 0] == .white)
    }

    @Test func blurSmoothsStripesInsideTheSelectionOnly() {
        let (canvas, history) = makeCanvas()
        stripes(canvas)
        let selection = SelectionMask.rectangle(IntRect(x: 10, y: 10, width: 20, height: 20), clippedTo: canvas.bounds)
        let edit = history.beginEdit("Blur", on: canvas)
        Effects.apply(.gaussianBlur(radius: 3), to: canvas.activeLayer, selection: selection, edit: edit)

        let buffer = canvas.activeLayer.buffer
        let inside = buffer[20, 20]
        #expect(inside.r > 60 && inside.r < 200)
        #expect(buffer[40, 40] == .black || buffer[40, 40] == .white)
        #expect(buffer[41, 40] != buffer[40, 40])
    }

    @Test func blurredSelectionEdgesStayOpaque() {
        let (canvas, history) = makeCanvas()
        stripes(canvas)
        let selection = SelectionMask.ellipse(in: IntRect(x: 5, y: 5, width: 40, height: 40), clippedTo: canvas.bounds)
        let edit = history.beginEdit("Blur", on: canvas)
        Effects.apply(.gaussianBlur(radius: 8), to: canvas.activeLayer, selection: selection, edit: edit)
        for y in 0..<60 {
            for x in 0..<60 {
                #expect(canvas.activeLayer.buffer[x, y].a == 255, "(\(x), \(y))")
            }
        }
    }

    @Test func blurDoesNotBleedBetweenSelectedRegions() {
        let (canvas, history) = makeCanvas()
        canvas.activeLayer.buffer.fill(red, in: IntRect(x: 0, y: 0, width: 30, height: 60))
        canvas.activeLayer.buffer.fill(blue, in: IntRect(x: 30, y: 0, width: 30, height: 60))
        let left = SelectionMask.rectangle(IntRect(x: 5, y: 5, width: 24, height: 50), clippedTo: canvas.bounds)
        let right = SelectionMask.rectangle(IntRect(x: 31, y: 5, width: 24, height: 50), clippedTo: canvas.bounds)
        let both = SelectionMask.combine(left, with: right, mode: .add)
        let edit = history.beginEdit("Blur", on: canvas)
        Effects.apply(.gaussianBlur(radius: 10), to: canvas.activeLayer, selection: both, edit: edit)

        #expect(canvas.activeLayer.buffer[28, 30] == red)
        #expect(canvas.activeLayer.buffer[31, 30] == blue)
    }

    @Test func pixelateMakesUniformCells() {
        let (canvas, history) = makeCanvas()
        stripes(canvas)
        let edit = history.beginEdit("Pixelate", on: canvas)
        Effects.apply(.pixelate(cellSize: 10), to: canvas.activeLayer, selection: nil, edit: edit)

        let buffer = canvas.activeLayer.buffer
        let cell = buffer[20, 20]
        #expect(cell.r > 100 && cell.r < 155)
        #expect(buffer[29, 29] == cell)
        #expect(buffer[21, 25] == cell)
    }

    @Test func restoringOriginalsUndoesAPreview() {
        let (canvas, history) = makeCanvas()
        stripes(canvas)
        let original = canvas.activeLayer.buffer.contentHash()
        let edit = history.beginEdit("Blur", on: canvas)
        Effects.apply(.gaussianBlur(radius: 4), to: canvas.activeLayer, selection: nil, edit: edit)
        #expect(canvas.activeLayer.buffer.contentHash() != original)

        edit.restoreOriginals()
        #expect(canvas.activeLayer.buffer.contentHash() == original)
        #expect(!history.commit(edit))
    }

    @Test(arguments: ImageFileFormat.allCases.filter(\.canWrite))
    func everyWritableFormatRoundTrips(format: ImageFileFormat) throws {
        let buffer = PixelBuffer(width: 16, height: 16, fill: Pixel(r: 200, g: 40, b: 30))
        let data = try ImageCodec.encode(buffer, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, as: format, quality: 1)
        let decoded = try ImageCodec.decode(data)
        let pixel = decoded.buffer[8, 8]
        #expect(decoded.buffer.size == buffer.size)
        #expect(abs(Int(pixel.r) - 200) <= 12 && abs(Int(pixel.g) - 40) <= 12 && abs(Int(pixel.b) - 30) <= 12, "\(format.name): \(pixel)")
    }

    @Test func jpegIsCompositedOverTheMatte() throws {
        let buffer = PixelBuffer(width: 8, height: 8)
        let data = try ImageCodec.encode(buffer, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, as: .jpeg, quality: 1, matte: blue)
        let pixel = try ImageCodec.decode(data).buffer[4, 4]
        #expect(pixel.a == 255 && pixel.b > 240 && pixel.r < 15)
    }

    @Test func formatIsFoundFromTheFileType() {
        #expect(ImageFileFormat(type: .jpeg) == .jpeg)
        #expect(ImageFileFormat(type: .png) == .png)
        #expect(ImageFileFormat(type: .heic) == .heic)
    }
}
