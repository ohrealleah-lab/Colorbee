import ColorbeeCore
import Foundation
@testable import Colorbee

/// One thing the monkey does (stage 32), kept as data so a failing run can be replayed and shrunk. Each is done the
/// way `CanvasView` and the menus do it, so it's always legal; anything that would save a preference, use the clipboard
/// or run in the background is left out. Layer numbers wrap around whatever layers there are when it's replayed.
enum MonkeyStep: CustomStringConvertible {
    case stroke(tool: Tool, brush: Brush, size: Double, color: Pixel, points: [Point2D], secondary: Bool, shift: Bool,
                smoothing: Double, symmetry: SymmetryMode)
    case fill(at: Point2D, color: Pixel)
    case gradient(from: Point2D, to: Point2D, color: Pixel)
    case shape(kind: ShapeKind, from: Point2D, to: Point2D, outline: PaintStyle?, fill: PaintStyle?, secondary: Bool, color: Pixel)
    case text(String, at: Point2D, editable: Bool, color: Pixel)
    case editText(layer: Int, String)
    case redact(points: [Point2D], treatment: RedactionTreatment)
    case select(from: Point2D, to: Point2D)
    case selectAll
    case deselect
    case invertSelection
    case moveSelection(dx: Int, dy: Int)
    case nudge(dx: Int, dy: Int)
    case deleteSelection
    case paste(width: Int, height: Int, color: Pixel, at: IntPoint)
    case cropToSelection
    case orientation(Orientation)
    case resize(width: Int, height: Int, skew: Double)
    case resizeCanvas(width: Int, height: Int)
    case addLayer
    case duplicateLayer
    case deleteLayer
    case mergeDown
    case mergeVisible
    case flatten
    case stampVisible
    case chooseLayer(Int)
    case group
    case ungroup
    case moveLayer(from: Int, to: Int)
    case adjustmentLayer(Effect, name: String)
    case mergeAdjustment
    case effect(Effect)
    case blendMode(BlendMode)
    case opacity(Double)
    case toggleVisible
    case toggleLocked
    case toggleLockTransparency
    case clip(Bool)
    case addMask(hidingAll: Bool)
    case paintOnMask(Bool)
    case invertMask
    case applyMask
    case deleteMask
    case toggleMask
    case rasterizeText
    case takeSnapshot
    case goToSnapshot(Int)
    case undo
    case redo
    case undoOnActiveLayer

    /// A short name for grouping failures: the same rule broken by the same kind of step counts once.
    var kind: String { String(describing: self).split(separator: "(").first.map(String.init) ?? "" }

    var description: String {
        switch self {
        case let .stroke(tool, brush, size, color, points, secondary, shift, smoothing, symmetry):
            let name = tool == .brush ? "\(brush.name) brush" : "\(tool)".capitalized
            var words = "\(name) stroke, \(Int(size)) px, in \(color.words)\(secondary ? " (right button)" : ""), through \(points.words)"
            if shift { words += ", holding Shift" }
            if smoothing > 0 { words += ", Smoothing \(Int(smoothing * 100))%" }
            if symmetry != .off { words += ", Symmetry \(symmetry)" }
            return words
        case let .fill(point, color): return "Fill at \(point.words) with \(color.words)"
        case let .gradient(from, to, color): return "Gradient from \(from.words) to \(to.words), \(color.words) to Color 2"
        case let .shape(kind, from, to, outline, fill, secondary, color):
            return "\(kind) from \(from.words) to \(to.words), outline \(outline.map { "\($0)" } ?? "none"), fill \(fill.map { "\($0)" } ?? "none"), Color 1 \(color.words)\(secondary ? ", right-drag" : ""), placed"
        case let .text(words, point, editable, color):
            return "Text \"\(words)\" at \(point.words) in \(color.words), Editable \(editable ? "on" : "off"), placed"
        case let .editText(layer, words): return "Double-click text layer \(layer + 1) and change it to \"\(words)\""
        case let .redact(points, treatment): return "Redact Brush (\(treatment)) through \(points.words)"
        case let .select(from, to): return "Rectangle Select from \(from.words) to \(to.words)"
        case .selectAll: return "Select All"
        case .deselect: return "Deselect"
        case .invertSelection: return "Invert Selection"
        case let .moveSelection(dx, dy): return "Drag the selection by (\(dx), \(dy))"
        case let .nudge(dx, dy): return "Nudge the selection by (\(dx), \(dy)) with the arrow keys"
        case .deleteSelection: return "Delete the selection"
        case let .paste(width, height, color, at): return "Paste a \(width) × \(height) \(color.words) picture at (\(at.x), \(at.y))"
        case .cropToSelection: return "Crop to Selection"
        case let .orientation(orientation): return orientation.name
        case let .resize(width, height, skew): return "Resize and Skew to \(width) × \(height)\(skew != 0 ? ", skew \(Int(skew))°" : "")"
        case let .resizeCanvas(width, height): return "Canvas size \(width) × \(height)"
        case .addLayer: return "New Layer"
        case .duplicateLayer: return "Duplicate Layer"
        case .deleteLayer: return "Delete Layer"
        case .mergeDown: return "Merge Down"
        case .mergeVisible: return "Merge Visible"
        case .flatten: return "Flatten"
        case .stampVisible: return "Stamp Visible"
        case let .chooseLayer(index): return "Click layer \(index + 1) (counting from the bottom)"
        case .group: return "Group the active layer with the one below"
        case .ungroup: return "Ungroup the top group"
        case let .moveLayer(from, to): return "Drag layer \(from + 1) to place \(to + 1)"
        case let .adjustmentLayer(_, name): return "New Adjustment Layer: \(name)"
        case .mergeAdjustment: return "Merge Adjustment"
        case let .effect(effect): return "Effect: \(effect.name)"
        case let .blendMode(mode): return "Blend mode \(mode.name)"
        case let .opacity(opacity): return "Opacity \(Int(opacity * 100))%"
        case .toggleVisible: return "Hide or show the active layer"
        case .toggleLocked: return "Lock or unlock the active layer"
        case .toggleLockTransparency: return "Lock or unlock the active layer's transparent pixels"
        case let .clip(clips): return "Only the layer below \(clips ? "on" : "off")"
        case let .addMask(hidingAll): return hidingAll ? "Add Mask Hiding All" : "Add Mask"
        case let .paintOnMask(mask): return mask ? "Click the mask to paint on it" : "Click the layer's own picture"
        case .invertMask: return "Invert Mask"
        case .applyMask: return "Apply Mask"
        case .deleteMask: return "Delete Mask"
        case .toggleMask: return "Shift-click the mask (turn it off or on)"
        case .rasterizeText: return "Rasterize Text"
        case .takeSnapshot: return "New History Snapshot"
        case let .goToSnapshot(index): return "Go to History Snapshot \(index + 1)"
        case .undo: return "Undo"
        case .redo: return "Redo"
        case .undoOnActiveLayer: return "Undo on Active Layer"
        }
    }

    /// Does the step to `editor`.
    @MainActor
    func perform(on editor: Editor) {
        let layers = editor.canvas.layers.count
        func layer(_ index: Int) -> Int { ((index % layers) + layers) % layers }
        switch self {
        case let .stroke(tool, brush, size, color, points, secondary, shift, smoothing, symmetry):
            editor.selectTool(tool)
            editor.brush = brush
            editor.brushDiameter = size
            editor.eraserSize = max(2, Int(size))
            editor.color1 = color
            editor.smoothing = smoothing
            editor.symmetry = symmetry
            editor.beginStroke(at: points[0], secondary: secondary)
            for point in points.dropFirst() { editor.continueStroke(to: point, constrain: shift) }
            editor.endStroke()
            editor.symmetry = .off
        case let .fill(point, color):
            editor.selectTool(.fill)
            editor.color1 = color
            editor.fill(at: point, secondary: false)
        case let .gradient(from, to, color):
            editor.selectTool(.gradient)
            editor.color1 = color
            editor.beginGradient(at: from, secondary: false)
            editor.continueGradient(to: to)
            editor.endGradient()
        case let .shape(kind, from, to, outline, fill, secondary, color):
            editor.selectTool(.shape)
            editor.shapeKind = kind
            editor.shapeOutline = outline
            editor.shapeFill = fill
            editor.color1 = color
            editor.beginShapeDrag(at: from, viewPoint: editor.viewport.viewPoint(fromImage: from), secondary: secondary, clickCount: 1)
            editor.continueShapeDrag(to: to, shiftDown: false)
            editor.endShapeDrag()
            editor.commitPendingShape()
        case let .text(words, point, editable, color):
            editor.textIsEditable = editable
            editor.selectTool(.text)
            editor.color1 = color
            editor.beginText(at: point, wrapWidth: nil)
            editor.updatePendingText(words)
            editor.commitPendingText()
        case let .editText(index, words):
            let texts = editor.canvas.layers.indices.filter { editor.canvas.layers[$0].text != nil }
            guard !texts.isEmpty else { return }
            editor.editText(layerAt: texts[((index % texts.count) + texts.count) % texts.count])
            guard editor.pendingText != nil else { return }
            editor.updatePendingText(words)
            editor.commitPendingText()
        case let .redact(points, treatment):
            editor.selectTool(.redactBrush)
            editor.redactTreatment = treatment
            editor.beginRedactStroke(at: points[0], secondary: false)
            for point in points.dropFirst() { editor.continueRedactStroke(to: point, constrain: false) }
            editor.endRedactStroke()
        case let .select(from, to):
            editor.selectTool(.rectangleSelect)
            editor.selectionDrag(from: from, to: to)
        case .selectAll: editor.selectAll()
        case .deselect: editor.deselect()
        case .invertSelection: editor.invertSelection()
        case let .moveSelection(dx, dy):
            guard let bounds = editor.canvas.selection.bounds else { return }
            editor.selectTool(.rectangleSelect)
            let center = Point2D(x: Double(bounds.minX) + Double(bounds.width) / 2, y: Double(bounds.minY) + Double(bounds.height) / 2)
            guard editor.selectionContains(center) else { return }
            editor.selectionDrag(from: center, to: Point2D(x: center.x + Double(dx), y: center.y + Double(dy)))
        case let .nudge(dx, dy):
            editor.selectTool(.rectangleSelect)
            editor.nudgeSelection(dx: dx, dy: dy)
        case .deleteSelection: editor.deleteSelection()
        case let .paste(width, height, color, at): editor.paste(PixelBuffer(width: width, height: height, fill: color), at: at)
        case .cropToSelection: editor.cropToSelection()
        case let .orientation(orientation): editor.apply(orientation)
        case let .resize(width, height, skew):
            editor.apply(ResizeSkew(size: IntSize(width: width, height: height), horizontalSkew: skew, resampling: .smooth))
        case let .resizeCanvas(width, height): editor.resizeCanvas(to: IntSize(width: width, height: height))
        case .addLayer: editor.addLayer()
        case .duplicateLayer: editor.duplicateLayer()
        case .deleteLayer: editor.deleteLayer()
        case .mergeDown: editor.mergeDown()
        case .mergeVisible: editor.mergeVisible()
        case .flatten: editor.flatten()
        case .stampVisible: editor.stampVisible()
        case let .chooseLayer(index): editor.selectLayer(at: layer(index))
        case .group:
            let active = editor.activeLayerIndex
            guard active > 0 else { return }
            editor.chooseLayer(at: active, extending: false, toggling: false)
            editor.chooseLayer(at: active - 1, extending: false, toggling: true)
            editor.groupLayers()
        case .ungroup:
            guard let group = editor.canvas.layers.lastIndex(where: \.isGroup) else { return }
            editor.selectLayer(at: group)
            editor.ungroupLayers()
        case let .moveLayer(from, to): editor.moveLayer(from: layer(from), to: layer(to))
        case let .adjustmentLayer(effect, name): editor.addAdjustmentLayer(effect, named: name)
        case .mergeAdjustment: editor.applyAdjustmentLayer()
        case let .effect(effect): editor.applyAdjustment(effect)
        case let .blendMode(mode): editor.setBlendMode(mode)
        case let .opacity(opacity):
            editor.previewOpacity(opacity)
            editor.finishLayerSettings()
        case .toggleVisible: editor.setLayerVisible(!editor.canvas.activeLayer.isVisible, at: editor.activeLayerIndex)
        case .toggleLocked: editor.setLayerLocked(!editor.canvas.activeLayer.isLocked, at: editor.activeLayerIndex)
        case .toggleLockTransparency:
            editor.setLayerLocksTransparency(!editor.canvas.activeLayer.locksTransparency, at: editor.activeLayerIndex)
        case let .clip(clips): editor.setClipsToLayerBelow(clips)
        case let .addMask(hidingAll): editor.addMask(hidingAll: hidingAll)
        case let .paintOnMask(mask): editor.paint(onMask: mask, at: editor.activeLayerIndex)
        case .invertMask: editor.invertMask()
        case .applyMask: editor.applyMask()
        case .deleteMask: editor.deleteMask()
        case .toggleMask: editor.toggleMaskEnabled()
        case .rasterizeText: editor.rasterizeText()
        case .takeSnapshot:
            guard editor.history.snapshots.count < History.snapshotLimit else { return }
            try? editor.takeSnapshot(named: "Monkey")
        case let .goToSnapshot(index):
            let snapshots = editor.history.snapshots
            guard !snapshots.isEmpty else { return }
            editor.goToSnapshot(snapshots[index % snapshots.count].id)
        case .undo: editor.undo()
        case .redo: editor.redo()
        case .undoOnActiveLayer: editor.undoOnActiveLayer()
        }
    }
}

extension Pixel {
    fileprivate var words: String { String(format: "#%02X%02X%02X", r, g, b) }
}

extension Point2D {
    fileprivate var words: String { "(\(Int(x.rounded())), \(Int(y.rounded())))" }
}

extension [Point2D] {
    fileprivate var words: String { map(\.words).joined(separator: ", ") }
}
