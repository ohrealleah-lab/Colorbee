import ColorbeeCore
import Foundation
import Metal
import Testing
@testable import Colorbee

/// The screen matches the export (Development Plan, checklist item 4): an Adjust Photo layer is drawn on screen by
/// `adjust_photo_fragment`, not by the core, so each control is drawn through the real `Renderer`, off screen, and
/// compared with `Canvas.flattened()`, which exports use.
@MainActor
@Suite(.serialized)
struct ScreenMatchesExportTests {
    static let width = 72, height = 54

    /// Smooth ramps for the tone controls, saturated patches for the color ranges, and fine noise for the detail
    /// sliders. Opaque, as photos are.
    static func paintPicture(_ buffer: PixelBuffer) {
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func noise() -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int(seed >> 59) - 16
        }
        let patches: [Pixel] = [Pixel(r: 210, g: 40, b: 40), Pixel(r: 230, g: 140, b: 30), Pixel(r: 220, g: 210, b: 40),
                                Pixel(r: 50, g: 170, b: 60), Pixel(r: 40, g: 190, b: 200), Pixel(r: 40, g: 80, b: 210),
                                Pixel(r: 140, g: 60, b: 200), Pixel(r: 210, g: 50, b: 160), Pixel(r: 225, g: 170, b: 140)]
        for y in 0..<height {
            for x in 0..<width {
                var r = x * 255 / (width - 1), g = y * 255 / (height - 1), b = 255 - (x + y) * 255 / (width + height - 2)
                if y >= height - 12 {
                    let patch = patches[x * patches.count / width]
                    (r, g, b) = (Int(patch.r), Int(patch.g), Int(patch.b))
                }
                let n = noise()
                buffer.row(y)[x] = Pixel(r: UInt8(clamping: r + n), g: UInt8(clamping: g + n), b: UInt8(clamping: b - n))
            }
        }
    }

    static func picture() -> Editor {
        let editor = makeEditor(width: width, height: height)
        paintPicture(editor.canvas.activeLayer.buffer)
        return editor
    }

    /// What the screen shows at 100%, one screen pixel to one image pixel.
    static func screen(_ canvas: Canvas) -> PixelBuffer {
        let size = Size2D(width: Double(canvas.size.width), height: Double(canvas.size.height))
        let scene = RenderScene(canvas: canvas, viewport: Viewport(zoom: 1, center: Point2D(x: size.width / 2, y: size.height / 2), viewSize: size),
                                outline: nil, transparentKey: nil, smoothFloating: false, overlay: nil, handlePoints: [],
                                roundHandlePoints: [], showsPixelGrid: false, antsPhase: 0, lines: [], highlights: [], comparison: nil)
        return Renderer.shared.renderedPixels(scene, size: canvas.size, surround: MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1))!
    }

    struct Difference: CustomStringConvertible {
        var largest = 0
        var total = 0
        var count = 0
        var average: Double { Double(total) / Double(max(count, 1)) }
        var description: String { "largest \(largest), average \(String(format: "%.3f", average))" }
    }

    static func difference(_ a: PixelBuffer, _ b: PixelBuffer) -> Difference {
        var result = Difference()
        for y in 0..<a.height {
            for x in 0..<a.width {
                let p = a[x, y], q = b[x, y]
                for (u, v) in [(p.r, q.r), (p.g, q.g), (p.b, q.b), (p.a, q.a)] {
                    let d = abs(Int(u) - Int(v))
                    result.largest = max(result.largest, d)
                    result.total += d
                    result.count += 1
                }
            }
        }
        return result
    }

    struct Case: CustomTestStringConvertible, Sendable {
        let name: String
        let edit: PhotoEdit
        /// Controls that look at neighboring pixels are blurred by Metal on screen and by vImage in exports, which
        /// round a little differently, and sharpening makes more of that.
        var looksAtNeighbors = false
        var testDescription: String { name }
    }

    nonisolated static let warmLook: ColorLook = {
        var lines = ["LUT_3D_SIZE 5"]
        for b in 0..<5 { for g in 0..<5 { for r in 0..<5 {
            let (rr, gg, bb) = (Double(r) / 4, Double(g) / 4, Double(b) / 4)
            lines.append("\(min(1, rr * 1.1 + 0.03)) \(gg * 0.98 + 0.01) \(bb * 0.8)")
        } } }
        return try! CubeFile.read(Data(lines.joined(separator: "\n").utf8), fallbackName: "Warm").look
    }()

    nonisolated static let cases: [Case] = {
        var mixer = ColorMixer()
        mixer[.hue, .red] = 30
        mixer[.saturation, .blue] = -60
        mixer[.luminance, .green] = 40
        mixer[.saturation, .aqua] = 50
        var blackAndWhite = ColorMixer()
        blackAndWhite.blackAndWhite = 1
        blackAndWhite[.gray, .red] = 40
        blackAndWhite[.gray, .blue] = -50
        var grading = ColorGrading()
        grading.wheels[.shadows] = ColorGrading.Wheel(hue: 220, strength: 40, luminance: -10)
        grading.wheels[.highlights] = ColorGrading.Wheel(hue: 40, strength: 35, luminance: 15)
        grading.wheels[.global] = ColorGrading.Wheel(hue: 300, strength: 10)
        grading.blending = 70
        grading.balance = -20
        let points = PointColors([PointColors.Swatch(color: Pixel(r: 225, g: 170, b: 140), hue: 15, saturation: -30, luminance: 20, range: 70),
                                  PointColors.Swatch(color: Pixel(r: 40, g: 80, b: 210), hue: -20, saturation: 40)])
        var curve = ToneCurve()
        curve.amounts = [25, -30, 35, -15]
        curve.splits = [20, 45, 80]
        var detail = PhotoDetail()
        detail.radius = 2.5
        detail.sharpnessDetail = 80
        detail.masking = 30
        detail.luminanceDetail = 30
        detail.color = 40
        detail.colorDetail = 70
        var effects = PhotoEffects()
        effects.midpoint = 30
        effects.roundness = 40
        effects.feather = 70
        effects.grainSize = 60
        effects.grainRoughness = 80
        let looked = PhotoFilter(name: "Warm Look", steps: [.look(warmLook)])
        let vignetted = PhotoFilter(name: "Framed", steps: [.photo(PhotoEdit(adjustments: PhotoAdjustments([.vignette: -50, .contrast: 20])))])
        let light = PhotoAdjustments([.exposure: 30, .brilliance: 30, .highlights: -40, .shadows: 35, .contrast: 25, .brightness: 10, .whites: 20, .blackPoint: 15])
        let color = PhotoAdjustments([.saturation: 30, .vibrance: 40, .warmth: 35, .tint: -20])
        var everything = light
        for (slider, value) in color.values { everything[slider] = value }
        for (slider, value) in [PhotoAdjustments.Slider.texture: 40.0, .dehaze: 30, .sharpness: 50, .definition: 40, .noiseReduction: 30, .vignette: -40, .grain: 30] {
            everything[slider] = value
        }
        return [
            Case(name: "Light sliders", edit: PhotoEdit(adjustments: light)),
            Case(name: "Color sliders", edit: PhotoEdit(adjustments: color)),
            Case(name: "Texture", edit: PhotoEdit(adjustments: PhotoAdjustments([.texture: 70])), looksAtNeighbors: true),
            Case(name: "Negative Texture", edit: PhotoEdit(adjustments: PhotoAdjustments([.texture: -70])), looksAtNeighbors: true),
            Case(name: "Dehaze", edit: PhotoEdit(adjustments: PhotoAdjustments([.dehaze: 60]))),
            Case(name: "Sharpness and Definition", edit: PhotoEdit(adjustments: PhotoAdjustments([.sharpness: 70, .definition: 60])), looksAtNeighbors: true),
            Case(name: "Noise Reduction", edit: PhotoEdit(adjustments: PhotoAdjustments([.noiseReduction: 70])), looksAtNeighbors: true),
            Case(name: "Detail settings", edit: PhotoEdit(adjustments: PhotoAdjustments([.sharpness: 60, .noiseReduction: 40]), detail: detail), looksAtNeighbors: true),
            Case(name: "Tone curve", edit: PhotoEdit(toneCurve: curve)),
            Case(name: "Color Mixer", edit: PhotoEdit(mixer: mixer)),
            Case(name: "Black & White", edit: PhotoEdit(mixer: blackAndWhite)),
            Case(name: "Color Grading", edit: PhotoEdit(grading: grading)),
            Case(name: "Point Color", edit: PhotoEdit(pointColors: points)),
            Case(name: "Vignette", edit: PhotoEdit(adjustments: PhotoAdjustments([.vignette: -70]), effects: effects)),
            Case(name: "Grain", edit: PhotoEdit(adjustments: PhotoAdjustments([.grain: 60]), effects: effects)),
            Case(name: "A look at 70%", edit: PhotoEdit(filter: looked, filterIntensity: 70)),
            Case(name: "A built-in filter at 60%", edit: PhotoEdit(filter: PhotoFilter.builtIn[0], filterIntensity: 60)),
            Case(name: "A filter holding a vignette", edit: PhotoEdit(filter: vignetted, filterIntensity: 80)),
            Case(name: "Everything at once", edit: PhotoEdit(adjustments: everything, mixer: mixer, grading: grading, pointColors: points,
                                                             detail: detail, effects: effects, toneCurve: curve), looksAtNeighbors: true),
        ]
    }()

    /// Within a shade or two for colors, and in every case far nearer the export than the picture before: a
    /// control missing or wrong on screen differs by about as much as it changes the picture.
    static func expectShowsAsExported(_ canvas: Canvas, before: PixelBuffer, looksAtNeighbors: Bool, _ name: String) {
        let export = canvas.flattened()
        let changed = difference(before, export)
        let mismatch = difference(screen(canvas), export)
        #expect(changed.average > 1, "\(name) should visibly change the picture")
        #expect(mismatch.average <= changed.average / 5, "\(name): screen against export \(mismatch), change \(changed)")
        if looksAtNeighbors {
            #expect(mismatch.largest <= 24 && mismatch.average <= 1.5, "\(name): screen against export \(mismatch)")
        } else {
            #expect(mismatch.largest <= 4 && mismatch.average <= 0.5, "\(name): screen against export \(mismatch)")
        }
    }

    @Test func withNoAdjustmentTheScreenIsThePicture() {
        let editor = Self.picture()
        #expect(Self.difference(Self.screen(editor.canvas), editor.canvas.flattened()).largest == 0)
    }

    @Test(arguments: cases)
    func anAdjustPhotoLayerShowsAsItExports(_ test: Case) {
        let editor = Self.picture()
        let before = editor.canvas.flattened()
        editor.addAdjustmentLayer(.photo(test.edit), named: "Adjust Photo")
        Self.expectShowsAsExported(editor.canvas, before: before, looksAtNeighbors: test.looksAtNeighbors, test.name)
    }

    /// Colors, a neighbor control and a vignette together, for the layer settings below.
    static let mixed = PhotoEdit(adjustments: PhotoAdjustments([.exposure: 30, .saturation: 40, .sharpness: 50, .vignette: -60]))

    @Test func atHalfOpacityAndMultiplyItShowsAsItExports() {
        let editor = Self.picture()
        let before = editor.canvas.flattened()
        editor.addAdjustmentLayer(.photo(Self.mixed), named: "Adjust Photo")
        editor.previewOpacity(0.5)
        editor.finishLayerSettings()
        #expect(editor.canvas.activeLayer.opacity == 0.5)
        Self.expectShowsAsExported(editor.canvas, before: before, looksAtNeighbors: true, "Half opacity")
        editor.setBlendMode(.multiply)
        Self.expectShowsAsExported(editor.canvas, before: before, looksAtNeighbors: true, "Multiply")
    }

    @Test func throughALayerMaskItShowsAsItExports() {
        let editor = Self.picture()
        let before = editor.canvas.flattened()
        editor.addAdjustmentLayer(.photo(Self.mixed), named: "Adjust Photo")
        editor.selectTool(.rectangleSelect)
        editor.selectionDrag(from: pt(10, 8), to: pt(50, 40))
        editor.addMask()
        #expect(editor.canvas.activeLayer.mask != nil)
        Self.expectShowsAsExported(editor.canvas, before: before, looksAtNeighbors: true, "Masked")
    }

    /// "Only the layer below" (stage 28b's clipping): it changes the patch on the layer under it and nothing else.
    @Test func onlyOnTheLayerBelowItShowsAsItExports() {
        let editor = Self.picture()
        editor.addLayer()
        let patch = editor.canvas.activeLayer.buffer
        // Out toward the corners, where the vignette is strongest.
        for y in 3..<51 { for x in 4..<68 { patch.row(y)[x] = Pixel(r: UInt8(x * 3), g: 120, b: UInt8(200 - y * 2)) } }
        let before = editor.canvas.flattened()
        editor.addAdjustmentLayer(.photo(Self.mixed), named: "Adjust Photo")
        editor.setClipsToLayerBelow(true)
        #expect(editor.canvas.activeLayer.clipsToLayerBelow)
        Self.expectShowsAsExported(editor.canvas, before: before, looksAtNeighbors: true, "Only the layer below")
    }

    /// In a group of its own (stage 25) it changes only the group's layers, drawn into a picture of their own.
    @Test func insideAGroupItShowsAsItExports() {
        let editor = Self.picture()
        editor.addLayer()
        let patch = editor.canvas.activeLayer.buffer
        for y in 6..<30 { for x in 30..<70 { patch.row(y)[x] = Pixel(r: 230, g: UInt8(x * 3), b: 60) } }
        let before = editor.canvas.flattened()
        editor.addAdjustmentLayer(.photo(Self.mixed), named: "Adjust Photo")
        editor.chooseLayer(at: editor.canvas.activeLayerIndex - 1, extending: true, toggling: false)
        editor.groupLayers()
        editor.setBlendMode(.normal)
        #expect(editor.canvas.activeLayer.isGroup && !editor.canvas.activeLayer.passesThrough)
        Self.expectShowsAsExported(editor.canvas, before: before, looksAtNeighbors: true, "In a group")
    }
}
