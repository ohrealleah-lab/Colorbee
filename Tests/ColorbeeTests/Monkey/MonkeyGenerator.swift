import ColorbeeCore
import Foundation
@testable import Colorbee

/// Chooses the monkey's next step from what the document has now (stage 32). Drawing comes up most, as in real use;
/// whole-picture changes, which replace every layer, less often.
@MainActor
enum MonkeyGenerator {
    static func step(_ random: inout MonkeyRandom, editor: Editor, large: Bool = false) -> MonkeyStep {
        let size = editor.canvas.size
        let layers = editor.canvas.layers.count
        // Large pictures reach past one 256-pixel undo tile, so strokes, pastes and resizes have to as well.
        let reach = large ? 90 : 20, maxSide = large ? 480 : 160
        func point() -> Point2D {
            // Now and then exactly on an edge or a pixel's corner, where off-by-one mistakes live.
            if random.chance(0.1) {
                return Point2D(x: random.pick([0, 1, Double(size.width - 1), Double(size.width), -1]),
                               y: random.pick([0, 1, Double(size.height - 1), Double(size.height), -1]))
            }
            return Point2D(x: Double(random.int(-4...(size.width + 4))) + 0.5, y: Double(random.int(-4...(size.height + 4))) + 0.5)
        }
        func path() -> [Point2D] {
            var points = [point()]
            for _ in 0..<random.int(1...8) {
                let last = points.last!
                points.append(Point2D(x: last.x + Double(random.int(-reach...reach)), y: last.y + Double(random.int(-reach...reach))))
            }
            return points
        }
        func color() -> Pixel {
            Pixel(r: UInt8(random.int(0...255)), g: UInt8(random.int(0...255)), b: UInt8(random.int(0...255)), a: random.chance(0.2) ? UInt8(random.int(40...255)) : 255)
        }
        // Empty words delete a text layer (C9); emoji, accents made of two characters, right-to-left words and line
        // breaks must redact and save like any other.
        func words() -> String {
            // An email or IP address a quarter of the time, as before the new words, so Auto-Redact finds something.
            if random.chance(0.25) { return random.pick(["a@b.io", "1.2.3.4"]) }
            return random.pick(["Hi", "Step 2", "Look here", "API key", "OK", "x", "a@b.io", "1.2.3.4", "", " ", "🐝 secret", "café", "e\u{301}clair",
                         "שלום עולם", "line one\nline two", String(repeating: "long words ", count: 12)])
        }

        func box() -> IntRect {
            let (a, b) = (point(), point())
            return IntRect(x: Int(min(a.x, b.x)), y: Int(min(a.y, b.y)), width: max(1, Int(abs(a.x - b.x))), height: max(1, Int(abs(a.y - b.y))))
        }
        let roll = random.int(0..<176)
        switch roll {
        case 0..<16:
            return .stroke(tool: random.pick([.brush, .brush, .pencil, .eraser]), brush: random.pick(Brush.allCases), size: Double(random.int(1...20)),
                           color: color(), points: path(), secondary: random.chance(0.2), shift: random.chance(0.15),
                           smoothing: random.chance(0.3) ? Double(random.int(1...100)) / 100 : 0,
                           symmetry: random.chance(0.15) ? random.pick(SymmetryMode.allCases) : .off)
        case 16..<20: return .fill(at: point(), color: color())
        case 20..<22: return .gradient(from: point(), to: point(), color: color())
        case 22..<27:
            // Every shape and paint style (C6), the everyday ones most.
            let kind = random.chance(0.5) ? random.pick([.line, .arrow, .rectangle, .ellipse, .star5, .heart, .roundedRectangleCallout]) : random.pick(ShapeKind.allCases)
            return .shape(kind: kind, from: point(), to: point(),
                          outline: random.chance(0.8) ? random.pick([.solid, .solid] + PaintStyle.allCases) : nil,
                          fill: random.chance(0.5) ? random.pick([.solid] + PaintStyle.allCases) : nil, secondary: random.chance(0.3), color: color(), leavesOpen: random.chance(0.35))
        case 27..<31: return .text(words(), at: point(), editable: random.chance(0.7), color: color(), leavesOpen: random.chance(0.35))
        case 31..<33: return .editText(layer: random.int(0..<8), words())
        case 33..<35: return .redact(points: path(), treatment: random.pick([.solidFill, .blur, .pixelate]), cancels: random.chance(0.3))
        case 35..<39: return .select(from: point(), to: point())
        case 39: return .selectAll
        case 40..<42: return .deselect
        case 42: return .invertSelection
        case 43..<45: return .moveSelection(dx: random.int(-15...15), dy: random.int(-15...15))
        case 45: return .nudge(dx: random.int(-3...3), dy: random.int(-3...3))
        case 46: return .deleteSelection
        case 47..<49: return .paste(width: random.int(2...(large ? 320 : 40)), height: random.int(2...(large ? 300 : 30)), color: color(), at: IntPoint(x: random.int(-10...size.width), y: random.int(-10...size.height)))
        case 49: return .cropToSelection
        case 50: return .orientation(random.pick(Orientation.allCases))
        case 51:
            let scale = random.pick([0.5, 0.75, 1.25, 1.5])
            let stretch = random.chance(0.3) ? 1.3 : 1
            return .resize(width: max(4, min(maxSide, Int(Double(size.width) * scale * stretch))), height: max(4, min(maxSide, Int(Double(size.height) * scale))),
                           skew: random.chance(0.2) ? Double(random.int(-20...20)) : 0)
        case 52: return .resizeCanvas(width: random.int(16...(large ? 460 : 150)), height: random.int(16...(large ? 380 : 120)))
        case 53..<57: return .addLayer
        case 57: return .duplicateLayer
        case 58: return layers > 1 ? .deleteLayer : .addLayer
        case 59..<61: return .mergeDown
        case 61: return random.chance(0.5) ? .mergeVisible : .stampVisible
        case 62: return random.chance(0.3) ? .flatten : .addLayer
        case 63..<67: return .chooseLayer(random.int(0..<max(1, layers)))
        case 67..<69: return .group
        case 69: return .ungroup
        case 70..<72: return .moveLayer(random.int(0..<max(1, layers)), onto: random.int(0..<max(1, layers)), how: random.int(0..<3))
        case 72..<74:
            let adjustment: (Effect, String) = random.pick([(.invert, "Invert"), (.desaturate, "Desaturate"), (.sepia(amount: 80), "Sepia"),
                                                            (.posterize(levels: 4), "Posterize"), (.hueSaturation(hue: 40, saturation: 20, lightness: 0), "Hue/Saturation"),
                                                            (.gaussianBlur(radius: 2), "Gaussian Blur")])
            return .adjustmentLayer(adjustment.0, name: adjustment.1)
        case 74: return .mergeAdjustment
        case 75..<77: return .effect(random.pick([.invert, .desaturate, .gaussianBlur(radius: 2), .pixelate(cellSize: 4), .sepia(amount: 60)]))
        case 77: return .blendMode(random.pick(BlendMode.allCases))
        case 78: return .opacity(random.pick([0.25, 0.5, 1]))
        case 79: return .toggleVisible
        case 80: return .toggleLocked
        case 81: return .toggleLockTransparency
        case 82: return .clip(random.chance(0.6))
        case 83..<85: return .addMask(hidingAll: random.chance(0.3))
        case 85: return .paintOnMask(random.chance(0.7))
        case 86: return random.pick([.invertMask, .applyMask, .deleteMask, .toggleMask])
        case 87: return .rasterizeText
        case 88: return .takeSnapshot
        case 89: return .goToSnapshot(random.int(0..<10))
        case 90..<96: return .undo
        case 96..<99: return .redo
        case 99: return .undoOnActiveLayer
        case 100: return .newPage
        case 101: return .duplicatePage
        case 102: return .deletePage
        case 103..<105: return .showPage(random.int(0..<4))
        case 105: return .movePage(from: random.int(0..<4), to: random.int(0..<4))
        case 106: return .batchRedact(blur: random.chance(0.5), apply: random.chance(0.6), cancels: random.chance(0.3))
        case 107: return .autoRedact(cancels: random.chance(0.3))
        case 108: return .saveAndReopen
        case 111: return .escape
        case 112: return .saveInBackground
        case 113: return random.chance(0.3) ? .forgetHistory : .saveInBackground
        case 114..<118:
            return .retouch(random.pick(RetouchKind.allCases), points: path(), source: point())
        case 109..<111: return .photoLayer(MonkeyPhoto.edit(&random))
        case 120..<123: return .adjustPhoto(MonkeyPhoto.edit(&random), select: random.chance(0.6) ? box() : nil, apply: random.chance(0.7))
        case 124..<126: return .export(pdf: random.chance(0.4))
        case 126..<131:
            let kind = random.pick([EffectKind.gaussianBlur, .pixelate, .sharpen, .hueSaturation, .levels, .curves, .sepia, .posterize, .addNoise,
                                    .motionBlur, .emboss, .vignette, .dropShadow, .border, .spotlight, .straighten, .perspective, .crop])
            let values = kind.parameters.map { parameter -> Double in
                if let options = parameter.options { return Double(random.int(0..<max(1, options.count))) }
                let steps = Int(((parameter.range.upperBound - parameter.range.lowerBound) / parameter.step).rounded(.down))
                return parameter.range.lowerBound + Double(random.int(0...max(0, steps))) * parameter.step
            }
            // Perspective's corners: top left, top right, bottom right, bottom left, each moved about a bit.
            let (w, h) = (Double(size.width), Double(size.height))
            let corners = [(0.1, 0.1), (0.9, 0.1), (0.9, 0.9), (0.1, 0.9)].map { x, y in
                Point2D(x: w * x + Double(random.int(-15...15)), y: h * y + Double(random.int(-15...15)))
            }
            return .effectDialog(kind, values: values, select: random.chance(0.4) ? box() : nil, box: box(), corners: corners,
                                 ending: random.pick(EffectEnding.allCases))
        // Monkey hardening (2026-11-21): raw input, and what monkey-hardening.md found still open.
        case 132..<139: return .input(MonkeyInputScripts.script(&random, size: size))
        case 139: return .solidFill(color: color(), cancels: random.chance(0.3))
        case 140: return .autoContrast(asLayer: random.chance(0.4))
        case 141: return .removeRedEye
        case 142: return .subject(random.pick([.select, .removeBackground, .liftToNewLayer]), click: random.chance(0.5) ? point() : nil, take: random.chance(0.7))
        case 143: return .modifySelection(random.pick(SelectionModification.allCases), radius: random.pick([1, 2, 5, 20, 100]), ending: random.pick(SelectionEnding.allCases))
        case 144:
            let kind = random.pick([EffectKind.colorRange, .luminanceRange, .graduatedSelection])
            let values = kind.parameters.map { parameter -> Double in
                if let options = parameter.options { return Double(random.int(0..<max(1, options.count))) }
                return random.pick([parameter.range.lowerBound, parameter.range.upperBound, (parameter.range.lowerBound + parameter.range.upperBound) / 2])
            }
            return .rangeSelect(kind, values: values, points: (0..<random.int(1...3)).map { _ in point() }, apply: random.chance(0.7))
        case 145..<147: return .selectWith(ellipse: random.chance(0.5), from: point(), to: point(), shift: random.chance(0.4), option: random.chance(0.3))
        case 147: return .dragHandle(random.pick(SelectionHandle.allCases), by: Point2D(x: Double(random.int(-30...30)), y: Double(random.int(-30...30))))
        case 148: return .copy(merged: random.chance(0.4), cut: random.chance(0.3))
        case 149: return .pasteInPlace
        case 150:
            let chosen = random.chance(0.2) ? [] : (0..<random.int(2...4)).map { _ in random.int(0..<max(1, layers)) }
            return .several(chosen, command: SeveralCommand.random(&random))
        case 151: return .renameLayer(random.chance(0.5) ? words() : "Layer \(random.int(1...9))")
        case 152: return .passThrough
        case 153: return .isolate(random.int(0..<max(1, layers)))
        case 154: return .renameSnapshot(random.int(0..<10), random.pick(["Before", "API key", "", "🐝"]))
        case 155..<157: return .toolOptions(MonkeyOptions.random(&random))
        case 157: return .zoom(random.pick([0.1, 0.5, 1, 2, 8, 32]))
        case 158:
            return .canvasProperties(width: random.int(1...(large ? 460 : 150)), height: random.int(1...(large ? 380 : 120)),
                                     anchor: random.pick(CanvasAnchor.allCases))
        case 159..<162: return .fill(at: point(), color: color())
        // Second hardening round (2026-11-22).
        case 162: return .trim
        case 163: return .revertLayer
        case 164: return .drop(width: random.int(1...(large ? 200 : 30)), height: random.int(1...(large ? 200 : 30)), color: color(), at: point())
        case 165: return .historyJump(random.int(0...30))
        case 166..<168: return .wand(at: point(), object: random.chance(0.2), shift: random.chance(0.3), option: random.chance(0.2))
        case 168: return .lasso(points: path(), shift: random.chance(0.3), option: random.chance(0.2))
        case 169..<171: return .badge(at: point(), to: random.chance(0.4) ? point() : nil, secondary: random.chance(0.2), leavesOpen: random.chance(0.35))
        case 171: return random.chance(0.5) ? .measure(from: point(), to: point()) : .eyedropper(at: point(), secondary: random.chance(0.3), allLayers: random.chance(0.4))
        case 172..<174: return .dragOpen(which: random.int(0..<12), by: Point2D(x: Double(random.int(-reach...reach)), y: Double(random.int(-reach...reach))))
        case 174: return random.chance(0.3) ? .copyText : .lasso(points: path(), shift: false, option: false)
        case 175: return .markSubjects(random.pick([.select, .removeBackground, .liftToNewLayer]), clicks: (0..<random.int(1...3)).map { _ in point() })
        default: return .photoSetting(MonkeyPhoto.edit(&random))
        }
    }
}
