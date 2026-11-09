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
            Point2D(x: Double(random.int(-4...(size.width + 4))) + 0.5, y: Double(random.int(-4...(size.height + 4))) + 0.5)
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
        // Only what the slider allows: some run from 0, others from -100.
        func sliderValue(_ slider: PhotoAdjustments.Slider) -> Double {
            Double(random.int(Int(max(-60, slider.range.lowerBound))...Int(min(60, slider.range.upperBound))))
        }
        func words() -> String { random.pick(["Hi", "Step 2", "Look here", "API key", "OK", "x", "a@b.io", "1.2.3.4"]) }

        let roll = random.int(0..<120)
        switch roll {
        case 0..<16:
            return .stroke(tool: random.pick([.brush, .brush, .pencil, .eraser]), brush: random.pick(Brush.allCases), size: Double(random.int(1...20)),
                           color: color(), points: path(), secondary: random.chance(0.2), shift: random.chance(0.15),
                           smoothing: random.chance(0.3) ? Double(random.int(1...100)) / 100 : 0,
                           symmetry: random.chance(0.15) ? random.pick(SymmetryMode.allCases) : .off)
        case 16..<20: return .fill(at: point(), color: color())
        case 20..<22: return .gradient(from: point(), to: point(), color: color())
        case 22..<27:
            return .shape(kind: random.pick([.line, .arrow, .rectangle, .ellipse, .star5, .heart, .roundedRectangleCallout]), from: point(), to: point(),
                          outline: random.chance(0.8) ? random.pick([.solid, .solid, .marker]) : nil,
                          fill: random.chance(0.5) ? .solid : nil, secondary: random.chance(0.3), color: color(), leavesOpen: random.chance(0.35))
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
        case 112: return .saveInBackground
        case 113: return random.chance(0.3) ? .forgetHistory : .saveInBackground
        case 114..<118:
            return .retouch(random.pick(RetouchKind.allCases), points: path(), source: point())
        case 109..<111:
            let slider = random.pick(PhotoAdjustments.Slider.allCases)
            return .photoLayer(slider, sliderValue(slider))
        default:
            let slider = random.pick(PhotoAdjustments.Slider.allCases)
            return .photoSetting(slider, sliderValue(slider))
        }
    }
}
