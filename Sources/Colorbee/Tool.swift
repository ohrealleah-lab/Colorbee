import ColorbeeCore
import CoreGraphics
import Foundation

enum Tool: CaseIterable {
    case pencil
    case brush
    case eraser
    case fill
    case eyedropper
    case gradient
    case measure
    case shape
    case text
    case rectangleSelect
    case ellipseSelect
    case lassoSelect
    case magicWand
    case magnifier
    case retouch
    case redactBrush
    case stepBadge

    var isSelectionTool: Bool {
        switch self {
        case .rectangleSelect, .ellipseSelect, .lassoSelect, .magicWand: true
        default: false
        }
    }

    /// Tools that change the active layer's pixels.
    var changesPixels: Bool {
        switch self {
        case .pencil, .brush, .eraser, .fill, .gradient, .shape, .text, .retouch, .redactBrush, .stepBadge: true
        default: false
        }
    }

    /// Tools that paint while the pointer is dragged.
    var isStrokeTool: Bool {
        switch self {
        case .pencil, .brush, .eraser: true
        default: false
        }
    }
}
