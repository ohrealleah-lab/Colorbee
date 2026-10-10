import Foundation

/// How each tool is shown: its name with shortcut, a one-line hint and an SF Symbol.
extension Tool {
    var summary: String {
        switch self {
        case .pencil: "1-pixel hard line. Shift draws straight lines."
        case .brush: "Nine brushes, from round to watercolor."
        case .eraser: "Erase to Color 2. Right-drag replaces only Color 1."
        case .fill: "Fill an area of similar color."
        case .eyedropper: "Pick a color from the image."
        case .gradient: "Drag to blend Color 1 into Color 2."
        case .measure: "Drag to measure distance and angle."
        case .shape: "Lines, arrows, boxes, stars, callouts and more."
        case .text: "Click to type, or drag out a box."
        case .rectangleSelect: "Drag to select a rectangle. Shift adds, Option subtracts."
        case .ellipseSelect: "Drag to select an oval. Shift adds, Option subtracts."
        case .lassoSelect: "Draw around an area to select it."
        case .magicWand: "Click to select an area of similar color."
        case .magnifier: "Click to zoom in. Right-click or Option-click zooms out."
        case .remove: "Paint over something to remove it. It's filled from around it."
        case .redactBrush: "Paint over anything to hide it, on every layer."
        case .stepBadge: "Click to place numbered steps. Drag to point an arrow."
        }
    }

    /// The tool's name with its current key, for tooltips.
    @MainActor
    var title: String {
        ShortcutStore.shared.hint(name, command: "canvas.\(self)")
    }

    /// The name without its shortcut, as VoiceOver says it ("Pencil").
    var name: String {
        switch self {
        case .pencil: "Pencil"
        case .brush: "Brush"
        case .eraser: "Eraser"
        case .fill: "Fill"
        case .eyedropper: "Eyedropper"
        case .measure: "Measure"
        case .gradient: "Gradient"
        case .shape: "Shapes"
        case .text: "Text"
        case .rectangleSelect: "Rectangle Select"
        case .ellipseSelect: "Ellipse Select"
        case .lassoSelect: "Free-Form Select"
        case .magicWand: "Magic Wand"
        case .magnifier: "Magnifier"
        case .remove: "Remove"
        case .redactBrush: "Redact Brush"
        case .stepBadge: "Step Badge"
        }
    }

    var symbol: String {
        switch self {
        case .pencil: "pencil"
        case .brush: "paintbrush.pointed"
        case .eraser: "eraser"
        case .fill: "drop.fill"
        case .eyedropper: "eyedropper"
        case .measure: "ruler"
        case .gradient: "square.tophalf.filled"
        case .shape: "square.on.circle"
        case .text: "textformat"
        case .rectangleSelect: "rectangle.dashed"
        case .ellipseSelect: "circle.dashed"
        case .lassoSelect: "lasso"
        case .magicWand: "wand.and.stars"
        case .magnifier: "plus.magnifyingglass"
        case .remove: "wand.and.rays"
        case .redactBrush: "eye.slash"
        case .stepBadge: "1.circle"
        }
    }
}
