import CoreGraphics
import Foundation
import Testing
@testable import ColorbeeCore

struct ProjectFileTests {
    private let context = SelectionContext(color2: .white)

    @Test func aProjectReopensExactly() throws {
        let canvas = Canvas(size: IntSize(width: 13, height: 7), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: .max)
        canvas.layers[0].buffer[2, 3] = Pixel(r: 10, g: 20, b: 30)
        LayerActions.add(canvas: canvas, history: history, context: context)
        let top = canvas.activeLayer
        top.buffer[5, 5] = Pixel(r: 200, g: 100, b: 50, a: 3)
        top.name = "Notes"
        top.opacity = 0.37
        top.blendMode = .softLight
        top.isLocked = true
        top.isVisible = false
        LayerActions.addAdjustment(.hueSaturation(hue: 30, saturation: -20, lightness: 5), named: "Hue", canvas: canvas, history: history, context: context)
        canvas.activeLayerIndex = 1

        let reopened = try ProjectFile.decode(ProjectFile.encode(canvas))
        #expect(reopened.size == canvas.size)
        #expect(reopened.layers.count == 3)
        #expect(reopened.activeLayerIndex == 1)
        #expect(reopened.backgroundLayerID == canvas.backgroundLayerID)
        for (a, b) in zip(canvas.layers, reopened.layers) {
            #expect(a.id == b.id && a.name == b.name && a.isVisible == b.isVisible && a.opacity == b.opacity)
            #expect(a.blendMode == b.blendMode && a.isLocked == b.isLocked && a.adjustment == b.adjustment)
            #expect(a.buffer.contentHash() == b.buffer.contentHash())
        }
        // Nearly transparent pixels keep their exact color.
        #expect(reopened.layers[1].buffer[5, 5] == Pixel(r: 200, g: 100, b: 50, a: 3))
        #expect(reopened.colorSpace.name == canvas.colorSpace.name)
    }

    @Test func theColorProfileIsKept() throws {
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let canvas = Canvas(size: IntSize(width: 4, height: 4), colorSpace: srgb, background: .clear)
        let reopened = try ProjectFile.decode(ProjectFile.encode(canvas))
        #expect(reopened.colorSpace.name == srgb.name)
        #expect(reopened.hasTransparentBackground)
    }

    @Test func aFloatingSelectionIsSavedWhereItSits() throws {
        let canvas = Canvas(size: IntSize(width: 8, height: 8), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: .max)
        SelectionActions.paste(PixelBuffer(width: 2, height: 2, fill: .black), at: IntPoint(x: 3, y: 3), canvas: canvas, history: history, context: context)
        let reopened = try ProjectFile.decode(ProjectFile.encode(canvas))
        #expect(reopened.layers[0].buffer[4, 4] == .black)
        #expect(canvas.layers[0].buffer[4, 4] == .white)
    }

    @Test func otherFilesAreRefused() {
        #expect(throws: ProjectFile.Failure.self) { try ProjectFile.decode(Data("not a project".utf8)) }
        var truncated = try! ProjectFile.encode(Canvas(size: IntSize(width: 4, height: 4), colorSpace: Canvas.defaultColorSpace, background: .white))
        truncated.removeLast(10)
        #expect(throws: (any Error).self) { try ProjectFile.decode(truncated) }
    }
}
