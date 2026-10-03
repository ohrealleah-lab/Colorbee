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
        }
    }

    var title: String {
        switch self {
        case .pencil: "Pencil (P)"
        case .brush: "Brush (B)"
        case .eraser: "Eraser (E)"
        case .fill: "Fill (G)"
        case .eyedropper: "Eyedropper (I)"
        case .measure: "Measure (R)"
        case .gradient: "Gradient"
        case .shape: "Shapes (U)"
        case .text: "Text (T)"
        case .rectangleSelect: "Rectangle Select (M)"
        case .ellipseSelect: "Ellipse Select"
        case .lassoSelect: "Free-Form Select (L)"
        case .magicWand: "Magic Wand (W)"
        case .magnifier: "Magnifier (Z)"
        }
    }

    /// The name without its shortcut, as VoiceOver says it ("Pencil").
    var name: String {
        title.components(separatedBy: " (").first ?? title
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
        }
    }
}
