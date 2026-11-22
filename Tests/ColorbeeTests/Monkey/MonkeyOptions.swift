import ColorbeeCore
import Foundation
@testable import Colorbee

/// How Feather, Expand, Contract or Smooth is closed: OK once the new outline is worked out, OK at once (it's applied
/// when ready), or Cancel.
enum SelectionEnding: String, CaseIterable {
    case ok = "OK", okAtOnce = "OK at once", cancel = "Cancel"
}

/// A Layer menu command on several chosen layers (monkey gaps, C7).
enum SeveralCommand: CustomStringConvertible {
    case align(LayerAlignment), distribute(LayerDistribution), visible, locked, lockTransparency, group

    var description: String {
        switch self {
        case .align(let alignment): "Align \(alignment.title)"
        case .distribute(let distribution): "Distribute \(distribution.title)"
        case .visible: "Show or hide them"
        case .locked: "Lock or unlock them"
        case .lockTransparency: "Lock or unlock their transparent pixels"
        case .group: "Group them"
        }
    }

    static func random(_ random: inout MonkeyRandom) -> SeveralCommand {
        switch random.int(0..<6) {
        case 0: .align(random.pick(LayerAlignment.allCases))
        case 1: .distribute(random.pick(LayerDistribution.allCases))
        case 2: .visible
        case 3: .locked
        case 4: .lockTransparency
        default: .group
        }
    }
}

/// Tool options off their defaults (monkey gaps, C6), set on the `Editor` directly as the tool bar does. None of them
/// is saved there: only a window's settings are, and the test host has no settings folder.
struct MonkeyOptions: CustomStringConvertible {
    var fillTolerance: Double
    var fillAllLayers: Bool
    var gradient: GradientMode
    var lineWidth: Double
    var colorEraser: Bool
    var colorEraserTolerance: Double
    var wandTolerance: Double
    var wandContiguous: Bool
    var wandAllLayers: Bool
    var retouchSize: Double
    var retouchStrength: Double
    var retouchHardness: Double
    var toneRange: ToneRange
    var retouchAllLayers: Bool
    var cloneAligned: Bool
    var cloneMatchesTone: Bool
    var transparentSelection: Bool
    var smoothResize: Bool
    var usesPressure: Bool
    var badgeStyle: BadgeStyle
    var text: TextStyle

    /// System fonts only, so a replay looks the same on any Mac.
    static let fonts = ["Helvetica Neue", "Menlo", "Times New Roman", "Avenir Next", "Courier New", "Georgia"]

    static func random(_ random: inout MonkeyRandom) -> MonkeyOptions {
        // Each end of a control as often as anywhere between (edge values).
        func amount(_ range: ClosedRange<Double>) -> Double {
            switch random.int(0..<4) {
            case 0: range.lowerBound
            case 1: range.upperBound
            default: range.lowerBound + Double(random.int(0...100)) / 100 * (range.upperBound - range.lowerBound)
            }
        }
        var text = TextStyle()
        text.fontFamily = random.pick(fonts)
        text.fontSize = random.pick([6, 9, 14, 24, 48, 120, 500])
        text.bold = random.chance(0.3)
        text.italic = random.chance(0.3)
        text.underline = random.chance(0.2)
        text.strikethrough = random.chance(0.1)
        text.alignment = random.pick(TextAlignment.allCases)
        text.opaqueBackground = random.chance(0.3)
        text.curve = random.chance(0.4) ? amount(-100...100).rounded() : 0
        return MonkeyOptions(
            fillTolerance: amount(0...1), fillAllLayers: random.chance(0.4), gradient: random.pick(GradientMode.allCases),
            lineWidth: amount(1...50).rounded(), colorEraser: random.chance(0.4), colorEraserTolerance: amount(0...1),
            wandTolerance: amount(0...1), wandContiguous: random.chance(0.6), wandAllLayers: random.chance(0.4),
            retouchSize: amount(1...300).rounded(), retouchStrength: amount(0.01...1), retouchHardness: amount(0...1),
            toneRange: random.pick(ToneRange.allCases), retouchAllLayers: random.chance(0.4), cloneAligned: random.chance(0.6),
            cloneMatchesTone: random.chance(0.4), transparentSelection: random.chance(0.4), smoothResize: random.chance(0.6),
            usesPressure: random.chance(0.7), badgeStyle: random.pick(BadgeStyle.allCases), text: text)
    }

    @MainActor
    func apply(to editor: Editor) {
        editor.fillTolerance = fillTolerance
        editor.fillSamplesAllLayers = fillAllLayers
        editor.gradientMode = gradient
        editor.shapeLineWidth = lineWidth
        editor.colorEraserMode = colorEraser
        editor.colorEraserTolerance = colorEraserTolerance
        editor.wandTolerance = wandTolerance
        editor.wandContiguous = wandContiguous
        editor.wandSamplesAllLayers = wandAllLayers
        editor.retouchSize = retouchSize
        editor.retouchStrength = retouchStrength
        editor.retouchHardness = retouchHardness
        editor.toneRange = toneRange
        editor.retouchSamplesAllLayers = retouchAllLayers
        editor.cloneAligned = cloneAligned
        editor.cloneMatchesTone = cloneMatchesTone
        editor.transparentSelection = transparentSelection
        editor.smoothResize = smoothResize
        editor.usesPressure = usesPressure
        editor.badgeStyle = badgeStyle
        editor.textStyle = text
    }

    var description: String {
        var words = ["fill tolerance \(Int(fillTolerance * 100))%\(fillAllLayers ? " on all layers" : "")", "gradient \(gradient)",
                     "line width \(Int(lineWidth))", colorEraser ? "color eraser at \(Int(colorEraserTolerance * 100))%" : "plain eraser",
                     "wand \(Int(wandTolerance * 100))%\(wandContiguous ? "" : " anywhere")\(wandAllLayers ? " on all layers" : "")",
                     "retouch \(Int(retouchSize)) px, strength \(Int(retouchStrength * 100))%, hardness \(Int(retouchHardness * 100))%, \(toneRange)",
                     "text \(text.fontFamily) \(Int(text.fontSize)) pt \(text.alignment)"]
        if text.curve != 0 { words.append("curve \(Int(text.curve))") }
        if text.bold { words.append("bold") }
        if text.italic { words.append("italic") }
        if text.opaqueBackground { words.append("opaque background") }
        if transparentSelection { words.append("transparent selection") }
        if !smoothResize { words.append("sharp resize") }
        if !usesPressure { words.append("pressure off") }
        return words.joined(separator: ", ")
    }
}
