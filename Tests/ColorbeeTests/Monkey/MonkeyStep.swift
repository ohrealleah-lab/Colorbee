import ColorbeeCore
import CoreGraphics
import Foundation
@testable import Colorbee

/// How an effect's dialog is closed (monkey gaps, C2): after its preview is worked out, or racing it (Leah, 2026-11-10).
enum EffectEnding: String, CaseIterable {
    case apply, cancel
    case applyAtOnce = "Apply at once", cancelAtOnce = "Cancel at once", undoAtOnce = "Undo at once"
    case showPageAtOnce = "show another page at once", autosaveAtOnce = "an autosave at once, then Cancel"
}

/// One thing the monkey does (stage 32), kept as data so a failing run can be replayed and shrunk. Each is done the
/// way `CanvasView` and the menus do it, so it's always legal; anything that would save a preference, use the clipboard
/// or run in the background is left out. Layer numbers wrap around whatever layers there are when it's replayed.
enum MonkeyStep: CustomStringConvertible {
    case stroke(tool: Tool, brush: Brush, size: Double, color: Pixel, points: [Point2D], secondary: Bool, shift: Bool,
                smoothing: Double, symmetry: SymmetryMode)
    case fill(at: Point2D, color: Pixel)
    case gradient(from: Point2D, to: Point2D, color: Pixel)
    /// `leavesOpen`: not placed, so the next step meets it (monkey gaps, C3).
    case shape(kind: ShapeKind, from: Point2D, to: Point2D, outline: PaintStyle?, fill: PaintStyle?, secondary: Bool, color: Pixel, leavesOpen: Bool)
    case text(String, at: Point2D, editable: Bool, color: Pixel, leavesOpen: Bool)
    case editText(layer: Int, String)
    /// `cancels`: answers Cancel if asked to delete History Snapshots, rather than Delete Snapshots and Redact.
    case redact(points: [Point2D], treatment: RedactionTreatment, cancels: Bool)
    case select(from: Point2D, to: Point2D)
    case selectAll
    case deselect
    /// Esc on the canvas: floating pixels go back to before they were lifted or pasted (stage 34b).
    case escape
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
    case moveLayer(Int, onto: Int, how: Int)
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
    // Pages (FR-11.6), where lost work would hurt most.
    case newPage
    case duplicatePage
    case deletePage
    case showPage(Int)
    case movePage(from: Int, to: Int)
    /// Batch Redact ▸ Blur… or Pixelate… on the selection, applied or cancelled after its preview.
    case batchRedact(blur: Bool, apply: Bool, cancels: Bool)
    /// Auto-Redact: reads the picture in the background, then applies what it found.
    case autoRedact(cancels: Bool)
    /// Saves the project and carries on in the reopened copy (`MonkeyEpisode.drive` does it).
    case saveAndReopen
    /// An Adjust Photo layer made directly, with whole random settings (`MonkeyPhoto`).
    case photoLayer(PhotoEdit)
    /// New settings, all of them, on the active Adjust Photo layer.
    case photoSetting(PhotoEdit)
    /// Adjust Photo's dialog on the active layer, over a new rectangle selection or what's selected now, then Apply or
    /// Cancel. Nothing applied becomes "last used" (`LastPhotoSettings.frozenForTests`).
    case adjustPhoto(PhotoEdit, select: IntRect?, apply: Bool)
    /// An effect's dialog (monkey gaps, C2) over a new rectangle selection or what's selected now, with its settings
    /// (Crop…'s box and Perspective Correction's corners too), closed as `ending` says.
    case effectDialog(EffectKind, values: [Double], select: IntRect?, box: IntRect, corners: [Point2D], ending: EffectEnding)
    /// Export as PNG, or as PDF with every page, read back and checked against the picture (monkey gaps, R4).
    case export(pdf: Bool)
    /// Takes a save copy now and writes it in the background a few steps later, as autosave does (`MonkeyEpisode.drive`).
    case saveInBackground
    /// Edit > Forget History: nothing can bring an earlier picture back.
    case forgetHistory
    /// A Retouch tool along a path; the Clone Stamp copies from `source`. Remove and Spot Heal land in the background.
    case retouch(RetouchKind, points: [Point2D], source: Point2D)
    /// Raw mouse, pen and key events through the canvas view, in odd orders too (Leah, 2026-11-21: raw input now).
    case input([InputEvent])
    /// Redact ▸ Solid Fill with Color 1 over the selection: a redaction (monkey gaps, C11).
    case solidFill(color: Pixel, cancels: Bool)
    /// Auto Contrast on the layer, or as an adjustment layer (C11).
    case autoContrast(asLayer: Bool)
    /// Remove Red-Eye: in the selection, or where Vision finds eyes (C11).
    case removeRedEye
    /// Select Subject, Remove Background or Lift Subject; then a click on a subject (or near one, to look closer), and
    /// Return takes every subject found, or Cancel (C10).
    case subject(Editor.SubjectAction, click: Point2D?, take: Bool)
    /// Select ▸ Feather, Expand, Contract or Smooth, then OK once worked out, OK at once, or Cancel (C5).
    case modifySelection(SelectionModification, radius: Double, ending: SelectionEnding)
    /// Color Range (clicked), Luminance Range or Graduated Selection (drawn), then Return or Cancel (C5).
    case rangeSelect(EffectKind, values: [Double], points: [Point2D], apply: Bool)
    /// A Rectangle or Ellipse Select drag, adding with Shift or taking away with Option (C5).
    case selectWith(ellipse: Bool, from: Point2D, to: Point2D, shift: Bool, option: Bool)
    /// A handle of the selection dragged: a marquee's outline, or a floating piece stretched (C5).
    case dragHandle(SelectionHandle, by: Point2D)
    /// Copy, Copy Merged or Cut, kept for a later Paste in Place, never on the Mac's clipboard (C4).
    case copy(merged: Bool, cut: Bool)
    case pasteInPlace
    /// Layers chosen together, then a command on all of them (C7).
    case several([Int], command: SeveralCommand)
    /// Rename the active layer (C8).
    case renameLayer(String)
    /// Pass Through on the active group (C8).
    case passThrough
    /// Option-click a layer's eye: only it shows, or back (C8).
    case isolate(Int)
    /// Rename a History Snapshot, so going to one finds it by id (R7).
    case renameSnapshot(Int, String)
    /// Tool options off their defaults, kept for the steps after (C6).
    case toolOptions(MonkeyOptions)
    /// View ▸ Zoom: strokes, drags and handles behave differently at other zooms (C13).
    case zoom(Double)
    /// Image ▸ Canvas Properties: a new size, kept to one side or corner (C13).
    case canvasProperties(width: Int, height: Int, anchor: CanvasAnchor)
    // Second hardening round (Leah, 2026-11-22): the smaller commands and tools.
    /// Image ▸ Trim: every layer cropped to what shows.
    case trim
    /// Layer ▸ Revert Layer: back to the last save.
    case revertLayer
    /// A picture dropped onto the canvas (as `CanvasView.performDragOperation`): decoded from a PNG in another color
    /// space, converted, and pasted floating, centered where it lands.
    case drop(width: Int, height: Int, color: Pixel, at: Point2D)
    /// A click in the History panel: undone or redone straight to that many steps.
    case historyJump(Int)
    /// A Magic Wand click, Color or Object mode, adding with Shift or taking away with Option.
    case wand(at: Point2D, object: Bool, shift: Bool, option: Bool)
    /// A Free-Form (lasso) Select drag.
    case lasso(points: [Point2D], shift: Bool, option: Bool)
    /// A step badge clicked, or dragged out into an arrow; placed, or left open for the next step.
    case badge(at: Point2D, to: Point2D?, secondary: Bool, leavesOpen: Bool)
    /// The Measure tool: changes nothing.
    case measure(from: Point2D, to: Point2D)
    /// The Eyedropper: changes a color, never the picture.
    case eyedropper(at: Point2D, secondary: Bool, allLayers: Bool)
    /// A handle of the open shape or text box dragged (`which` picks one; past the last, the middle, which moves it).
    case dragOpen(which: Int, by: Point2D)
    /// Copy Text: Vision reads the picture, which must not change, and the Mac's clipboard is never touched.
    case copyText
    /// Select Subject and friends, with Shift-clicks marking several subjects before Return (FR-9.5).
    case markSubjects(Editor.SubjectAction, clicks: [Point2D])

    /// Redacts, so it must leave no History Snapshots on the pages it changed (Leah, 2026-11-01). Asked first, the
    /// monkey answers Delete Snapshots and Redact, or sometimes Cancel, which must change nothing.
    var redacts: Bool {
        switch self {
        case .redact, .batchRedact, .autoRedact, .solidFill: true
        default: false
        }
    }

    /// Steps that may rightly change a locked layer: undo and its kin go back past the lock, a redaction covers every
    /// layer, and whole-picture changes move every pixel (monkey gaps, R10). Raw input can hold ⌘Z or Esc.
    var mayChangeLockedLayers: Bool {
        switch self {
        case .undo, .redo, .undoOnActiveLayer, .goToSnapshot, .escape, .input, .forgetHistory, .saveAndReopen, .orientation, .resize,
             .resizeCanvas, .cropToSelection, .canvasProperties, .trim, .historyJump, .showPage, .newPage, .duplicatePage, .deletePage, .movePage:
            true
        case let .effectDialog(kind, _, _, _, _, ending): [.crop, .perspective, .straighten].contains(kind) || ending == .undoAtOnce
        default: redacts
        }
    }

    /// Align or Distribute: moves whole layers, outline and all, like Flip, so a layer with its transparent pixels locked
    /// may have paint where it was clear (§23, 2026-11-23).
    var movesLayers: Bool {
        switch self {
        case .several(_, command: .align), .several(_, command: .distribute): true
        default: false
        }
    }

    /// Merge Down, Merge Visible or Flatten: a new combined picture, which may paint over locked clear pixels (§23, 2026-11-22).
    var merges: Bool {
        switch self {
        case .mergeDown, .mergeVisible, .flatten: true
        default: false
        }
    }

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
        case let .shape(kind, from, to, outline, fill, secondary, color, leavesOpen):
            return "\(kind) from \(from.words) to \(to.words), outline \(outline.map { "\($0)" } ?? "none"), fill \(fill.map { "\($0)" } ?? "none"), Color 1 \(color.words)\(secondary ? ", right-drag" : ""), \(leavesOpen ? "left open" : "placed")"
        case let .text(words, point, editable, color, leavesOpen):
            return "Text \"\(words)\" at \(point.words) in \(color.words), Editable \(editable ? "on" : "off"), \(leavesOpen ? "left open" : "placed")"
        case let .editText(layer, words): return "Double-click text layer \(layer + 1) and change it to \"\(words)\""
        case let .redact(points, treatment, cancels): return "Redact Brush (\(treatment)) through \(points.words)" + Self.answer(cancels)
        case let .select(from, to): return "Rectangle Select from \(from.words) to \(to.words)"
        case .selectAll: return "Select All"
        case .deselect: return "Deselect"
        case .escape: return "Press Esc"
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
        case let .moveLayer(layer, target, how):
            return "Drag layer \(layer + 1) \(["above", "below", "into"][how % 3]) layer \(target + 1)"
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
        case .newPage: return "Page > New Page"
        case .duplicatePage: return "Page > Duplicate Page"
        case .deletePage: return "Page > Delete Page"
        case let .showPage(index): return "Show page \(index + 1)"
        case let .movePage(from, to): return "Drag page \(from + 1) to place \(to + 1)"
        case let .batchRedact(blur, apply, cancels):
            return "Batch Redact > \(blur ? "Blur" : "Pixelate")…, then \(apply ? "Apply" : "Cancel")" + (apply ? Self.answer(cancels) : "")
        case let .autoRedact(cancels): return "Auto-Redact, then Apply" + Self.answer(cancels)
        case .saveAndReopen: return "Save, close and reopen"
        case let .photoLayer(edit): return "New Adjust Photo layer with \(MonkeyPhoto.words(edit))"
        case let .photoSetting(edit): return "Set the Adjust Photo layer to \(MonkeyPhoto.words(edit))"
        case let .effectDialog(kind, values, select, box, corners, ending):
            let area = select.map { "select (\($0.minX), \($0.minY)) to (\($0.maxX), \($0.maxY)), then " } ?? ""
            var settings = values.map { String(format: "%g", $0) }.joined(separator: ", ")
            if kind == .crop { settings = "box (\(box.minX), \(box.minY)) to (\(box.maxX), \(box.maxY))" }
            if kind == .perspective { settings = "corners " + corners.map { "(\(Int($0.x)), \(Int($0.y)))" }.joined(separator: ", ") }
            return "\(area)\(kind.title)… with \(settings.isEmpty ? "its settings" : settings), then \(ending.rawValue)"
        case let .export(pdf): return pdf ? "File > Export as PDF…" : "File > Export… as PNG"
        case let .adjustPhoto(edit, select, apply):
            let area = select.map { "select (\($0.minX), \($0.minY)) to (\($0.maxX), \($0.maxY)), then " } ?? ""
            return "\(area)Adjustments > Adjust Photo… with \(MonkeyPhoto.words(edit)), then \(apply ? "Apply" : "Cancel")"
        case .saveInBackground: return "Autosave in the background while editing goes on"
        case .forgetHistory: return "Edit > Forget History"
        case let .retouch(kind, points, source):
            let from = kind == .cloneStamp ? ", copying from (\(Int(source.x)), \(Int(source.y)))" : ""
            return "Retouch > \(kind.name) through \(points.map { "(\(Int($0.x.rounded())), \(Int($0.y.rounded())))" }.joined(separator: ", "))\(from)"
        case let .input(events): return "On the canvas: " + events.map(\.description).joined(separator: ", ")
        case let .solidFill(color, cancels): return "Redact > Solid Fill with Color 1 (\(color.words))" + Self.answer(cancels)
        case let .autoContrast(asLayer): return asLayer ? "New Adjustment Layer: Auto Contrast" : "Adjustments > Auto Contrast"
        case .removeRedEye: return "Adjustments > Remove Red-Eye"
        case let .subject(action, click, take):
            let name = switch action { case .select: "Select Subject"; case .removeBackground: "Remove Background"; case .liftToNewLayer: "Lift Subject" }
            return "\(name), \(click.map { "click at \($0.words), " } ?? "")then \(take ? "Return (every subject found)" : "Cancel")"
        case let .modifySelection(change, radius, ending): return "Select > \(change.title)… \(Int(radius)) px, then \(ending.rawValue)"
        case let .rangeSelect(kind, values, points, apply):
            let settings = values.map { String(format: "%g", $0) }.joined(separator: ", ")
            return "\(kind.title)… with \(settings), at \(points.words), then \(apply ? "Return" : "Cancel")"
        case let .selectWith(ellipse, from, to, shift, option):
            let held = shift ? "Shift-" : option ? "Option-" : ""
            return "\(held)\(ellipse ? "Ellipse" : "Rectangle") Select from \(from.words) to \(to.words)"
        case let .dragHandle(handle, by): return "Drag the selection's \(handle) handle by \(by.words)"
        case let .copy(merged, cut): return cut ? "Cut" : merged ? "Copy Merged" : "Copy"
        case .pasteInPlace: return "Paste in Place"
        case let .several(layers, command): return "Choose layers \(layers.map { "\($0 + 1)" }.joined(separator: ", ")), then \(command)"
        case let .renameLayer(name): return "Rename the active layer \"\(name)\""
        case .passThrough: return "Pass Through on the active group"
        case let .isolate(index): return "Option-click layer \(index + 1)'s eye"
        case let .renameSnapshot(index, name): return "Rename History Snapshot \(index + 1) \"\(name)\""
        case let .toolOptions(options): return "Tool options: \(options)"
        case let .zoom(scale): return "Zoom to \(Int(scale * 100))%"
        case let .canvasProperties(width, height, anchor): return "Canvas Properties: \(width) × \(height), anchored \(anchor)"
        case .trim: return "Image > Trim"
        case .revertLayer: return "Layer > Revert Layer"
        case let .drop(width, height, color, at): return "Drop a \(width) × \(height) \(color.words) PNG (sRGB) onto the canvas at \(at.words)"
        case let .historyJump(count): return "Click step \(count) in the History panel"
        case let .wand(at, object, shift, option):
            return "\(shift ? "Shift-" : option ? "Option-" : "")Magic Wand (\(object ? "Object" : "Color")) click at \(at.words)"
        case let .lasso(points, shift, option): return "\(shift ? "Shift-" : option ? "Option-" : "")Free-Form Select through \(points.words)"
        case let .badge(at, to, secondary, leavesOpen):
            return "Step badge at \(at.words)\(to.map { ", dragged to \($0.words)" } ?? "")\(secondary ? " (right button)" : ""), \(leavesOpen ? "left open" : "placed")"
        case let .measure(from, to): return "Measure from \(from.words) to \(to.words)"
        case let .eyedropper(at, secondary, allLayers): return "\(allLayers ? "Option-" : "")\(secondary ? "right-" : "")click the Eyedropper at \(at.words)"
        case let .dragOpen(which, by): return "Drag handle \(which + 1) of the open shape or text box by \(by.words)"
        case .copyText: return "Edit > Copy Text"
        case let .markSubjects(action, clicks):
            let name = switch action { case .select: "Select Subject"; case .removeBackground: "Remove Background"; case .liftToNewLayer: "Lift Subject" }
            return "\(name), click \(clicks.first?.words ?? "nowhere")\(clicks.dropFirst().map { ", Shift-click \($0.words)" }.joined()), then Return"
        }
    }

    /// Does the step to `editor`.
    @MainActor
    func perform(on editor: Editor) async {
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
        case let .shape(kind, from, to, outline, fill, secondary, color, leavesOpen):
            editor.selectTool(.shape)
            editor.shapeKind = kind
            editor.shapeOutline = outline
            editor.shapeFill = fill
            editor.color1 = color
            editor.beginShapeDrag(at: from, viewPoint: editor.viewport.viewPoint(fromImage: from), secondary: secondary, clickCount: 1)
            editor.continueShapeDrag(to: to, shiftDown: false)
            editor.endShapeDrag()
            if !leavesOpen { editor.commitPendingShape() }
        case let .text(words, point, editable, color, leavesOpen):
            editor.textIsEditable = editable
            editor.selectTool(.text)
            editor.color1 = color
            editor.beginText(at: point, wrapWidth: nil)
            editor.updatePendingText(words)
            if !leavesOpen { editor.commitPendingText() }
        case let .editText(index, words):
            let texts = editor.canvas.layers.indices.filter { editor.canvas.layers[$0].text != nil }
            guard !texts.isEmpty else { return }
            editor.editText(layerAt: texts[((index % texts.count) + texts.count) % texts.count])
            guard editor.pendingText != nil else { return }
            editor.updatePendingText(words)
            editor.commitPendingText()
        case let .redact(points, treatment, cancels):
            editor.selectTool(.redactBrush)
            editor.redactTreatment = treatment
            editor.beginRedactStroke(at: points[0], secondary: false)
            for point in points.dropFirst() { editor.continueRedactStroke(to: point, constrain: false) }
            editor.endRedactStroke()
            Self.answerSnapshots(editor, cancels: cancels)
        case let .select(from, to):
            editor.selectTool(.rectangleSelect)
            editor.selectionDrag(from: from, to: to)
        case .selectAll: editor.selectAll()
        case .deselect: editor.deselect()
        case .escape: editor.pressEscape()
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
        case let .moveLayer(moving, target, how):
            // As the Layers panel drops it (review Z, finding 3).
            let id = editor.canvas.layers[layer(moving)].id, onto = editor.canvas.layers[layer(target)].id
            editor.moveLayer(id, to: [LayerDrop.above(onto), .below(onto), .into(onto)][how % 3])
        case let .adjustmentLayer(effect, name): editor.addAdjustmentLayer(effect, named: name)
        case .mergeAdjustment: editor.applyAdjustmentLayer()
        case let .effect(effect): editor.applyAdjustment(effect)
        case let .blendMode(mode): editor.setBlendMode(mode)
        case let .opacity(opacity):
            // Only where the panel allows it (review Z, finding 7).
            guard !editor.canvas.isLocked(editor.canvas.activeLayer) else { return }
            editor.previewOpacity(opacity)
            editor.finishLayerSettings()
        case .toggleVisible: editor.setLayerVisible(!editor.canvas.activeLayer.isVisible, at: editor.activeLayerIndex)
        case .toggleLocked: editor.setLayerLocked(!editor.canvas.activeLayer.isLocked, at: editor.activeLayerIndex)
        case .toggleLockTransparency:
            editor.setLayerLocksTransparency(!editor.canvas.activeLayer.locksTransparency, at: editor.activeLayerIndex)
        case let .clip(clips):
            let active = editor.activeLayerIndex
            guard !editor.canvas.isLocked(editor.canvas.activeLayer), !clips || editor.canvas.canClip(layerAt: active) else { return }
            editor.setClipsToLayerBelow(clips)
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
        case .redo: editor.redoAnsweringSnapshots()
        case .undoOnActiveLayer: editor.undoOnActiveLayer()
        case .newPage:
            guard editor.pages.pages.count < 4 else { return }
            editor.newPage()
        case .duplicatePage:
            guard editor.pages.pages.count < 4 else { return }
            editor.duplicatePage()
        case .deletePage: editor.deletePage()
        case let .showPage(index): editor.showPage(at: index % editor.pages.pages.count)
        case let .movePage(from, to):
            let count = editor.pages.pages.count
            guard count > 1 else { return }
            editor.movePage(from: from % count, to: to % count)
        case let .batchRedact(blur, apply, cancels):
            guard editor.hasSelection else { return }
            editor.beginBatchRedact(blur ? .gaussianBlur : .pixelate)
            if apply {
                editor.applyEffect()
                Self.answerSnapshots(editor, cancels: cancels)
            }
            // Cancel leaves the bar open, with nothing applied.
            if editor.activeEffect != nil { editor.cancelEffect() }
        case let .autoRedact(cancels):
            editor.beginAutoRedact()
            // Reading happens in the background; wait for it, a few seconds at most.
            for _ in 0..<400 where editor.autoRedact?.isReading == true {
                try? await Task.sleep(for: .milliseconds(25))
            }
            if let session = editor.autoRedact, !session.isReading, session.problem == nil {
                editor.applyAutoRedact()
                Self.answerSnapshots(editor, cancels: cancels)
                for _ in 0..<400 where editor.autoRedact?.applying != nil {
                    try? await Task.sleep(for: .milliseconds(25))
                }
            }
            if editor.autoRedact != nil { editor.cancelAutoRedact() }
        case .saveAndReopen, .saveInBackground: break
        case .forgetHistory: editor.forgetHistory()
        case let .retouch(kind, points, source):
            editor.selectTool(.retouch)
            editor.retouchKind = kind
            if kind == .cloneStamp { editor.setCloneSource(source) }
            if kind.fillsArea {
                editor.beginRetouchStroke(at: points[0])
                for point in points.dropFirst() { editor.continueRetouchStroke(to: point, constrain: false) }
                editor.endRetouchStroke()
            } else {
                editor.beginRetouchBrush(at: points[0], pressure: 1)
                for point in points.dropFirst() { editor.continueRetouchBrush(to: point, constrain: false, pressure: 1) }
                editor.endRetouchBrush()
            }
            // Remove and Spot Heal fill, and the Clone Stamp matches tone, in the background: wait for them.
            for _ in 0..<400 where editor.fillProgress != nil || editor.fillingArea != nil || editor.isMatchingTone || editor.pendingTone != nil {
                try? await Task.sleep(for: .milliseconds(25))
            }
        case let .photoLayer(edit):
            editor.addAdjustmentLayer(.photo(edit), named: "Adjust Photo")
        case let .photoSetting(edit):
            guard case .photo = editor.canvas.activeLayer.adjustment else { return }
            editor.setAdjustment(.photo(edit))
        case let .effectDialog(kind, values, select, box, corners, ending):
            if let select {
                editor.selectTool(.rectangleSelect)
                editor.selectionDrag(from: Point2D(x: Double(select.minX) + 0.5, y: Double(select.minY) + 0.5),
                                     to: Point2D(x: Double(select.maxX) + 0.5, y: Double(select.maxY) + 0.5))
            }
            // Opening places what's open and what floats (the selection drag above may have made a floating piece), then
            // Drop Shadow, Border and Straighten preview as a step at once: Cancel goes back to after the placing.
            editor.finishInteractions()
            editor.placeFloatingKeepingOutline()
            Self.effectOpened = MonkeyRules.layerStates(of: editor.canvas, floatingOn: nil)
            editor.beginEffect(kind)
            guard editor.activeEffect == kind else {
                Self.effectOpened = nil
                return
            }
            if values.count == editor.effectValues.count { editor.effectValues = values }
            if kind == .crop {
                let fitted = box.intersection(editor.canvas.bounds)
                if !fitted.isEmpty { editor.cropRect = fitted }
            }
            if kind == .perspective, corners.count == 4 { editor.perspectiveCorners = corners }
            editor.previewEffect()
            switch ending {
            case .apply, .cancel:
                await Self.waitForPreview(editor)
                if ending == .apply { editor.applyEffect() } else { editor.cancelEffect() }
            case .applyAtOnce: editor.applyEffect()
            case .cancelAtOnce: editor.cancelEffect()
            case .undoAtOnce: editor.undo()
            case .showPageAtOnce:
                let count = editor.pages.pages.count
                if count > 1 { editor.showPage(at: (editor.pages.currentIndex + 1) % count) }
            case .autosaveAtOnce: return
            }
            // Apply can refuse (crossed corners), leaving the bar open; it's closed as Cancel would.
            if editor.activeEffect != nil { editor.cancelEffect() }
        case .export: break
        case let .adjustPhoto(edit, select, apply):
            if let select {
                editor.selectTool(.rectangleSelect)
                editor.selectionDrag(from: Point2D(x: Double(select.minX) + 0.5, y: Double(select.minY) + 0.5),
                                     to: Point2D(x: Double(select.maxX) + 0.5, y: Double(select.maxY) + 0.5))
            }
            editor.beginEffect(.adjustPhoto)
            guard editor.activeEffect == .adjustPhoto else { return }
            editor.photoEdit = edit
            if apply { editor.applyEffect() }
            if editor.activeEffect != nil { editor.cancelEffect() }
        case let .input(events):
            let canvas = MonkeyCanvas.view(for: editor)
            Self.inputFailure = canvas.play(events)
            Self.inputPageChanges = canvas.pageChanges
            Self.inputLowestUndoCount = canvas.lowestUndoCount
            // A redaction's question about snapshots blocks the window, so it's answered, as Return would, before the
            // next step; left up, the next step's own answer took it (monkey, 2026-11-23 overnight).
            Self.answerSnapshots(editor, cancels: false)
            await Self.settle(editor)
        case let .solidFill(color, cancels):
            editor.color1 = color
            editor.applySolidFill()
            Self.answerSnapshots(editor, cancels: cancels)
        case let .autoContrast(asLayer):
            if asLayer { editor.addAutoContrastLayer() } else { editor.autoContrast() }
        case .removeRedEye:
            editor.removeRedEye()
            await Self.settle(editor)
        case let .subject(action, click, take):
            editor.findSubject(action)
            await Self.settle(editor)
            if let click, editor.activeEffect == .pickSubject {
                editor.beginCanvasToolDrag(at: click, viewPoint: editor.viewport.viewPoint(fromImage: click), adding: false)
                editor.endCanvasToolDrag()
                await Self.settle(editor)
            }
            if editor.activeEffect == .pickSubject { if take { editor.applyEffect() } else { editor.cancelEffect() } }
            await Self.settle(editor)
            if editor.activeEffect != nil { editor.cancelEffect() }
        case let .modifySelection(change, radius, ending):
            editor.beginSelectionChange(change)
            guard editor.selectionChange != nil else { return }
            editor.setSelectionChangeRadius(radius)
            switch ending {
            case .ok:
                await Self.settle(editor)
                editor.applySelectionChange()
            case .okAtOnce:
                // Applied once worked out, in the background.
                editor.applySelectionChange()
                await Self.settle(editor)
            case .cancel:
                editor.cancelSelectionChange()
            }
            // Refused (nothing would be left): closed as Cancel would.
            if editor.selectionChange != nil { editor.cancelSelectionChange() }
        case let .rangeSelect(kind, values, points, apply):
            editor.beginEffect(kind)
            guard editor.activeEffect == kind else { return }
            if values.count == editor.effectValues.count { editor.effectValues = values }
            if kind == .graduatedSelection, points.count > 1 {
                editor.beginCanvasToolDrag(at: points[0], viewPoint: editor.viewport.viewPoint(fromImage: points[0]), adding: false)
                editor.continueCanvasToolDrag(to: points[1], constrain: false)
                editor.endCanvasToolDrag()
            } else if kind == .colorRange {
                for (index, point) in points.enumerated() {
                    editor.beginCanvasToolDrag(at: point, viewPoint: editor.viewport.viewPoint(fromImage: point), adding: index > 0)
                    editor.endCanvasToolDrag()
                }
            }
            editor.previewEffect()
            if apply, points.count % 2 == 0 { await Self.settle(editor) }
            if apply { editor.applyEffect() } else { editor.cancelEffect() }
            if editor.activeEffect != nil { editor.cancelEffect() }
        case let .selectWith(ellipse, from, to, shift, option):
            editor.selectTool(ellipse ? .ellipseSelect : .rectangleSelect)
            editor.selectionDrag(from: from, to: to, shift: shift, option: option)
        case let .dragHandle(handle, by):
            guard let bounds = editor.canvas.selection.bounds else { return }
            if !editor.tool.isSelectionTool { editor.selectTool(.rectangleSelect) }
            let start = handle.point(on: bounds), end = Point2D(x: start.x + by.x, y: start.y + by.y)
            editor.beginResize(handle, at: start)
            editor.continueSelectionDrag(to: end, shiftDown: false)
            editor.endSelectionDrag(at: end)
        case let .copy(merged, cut):
            // As Edit ▸ Copy, Copy Merged and Cut do (`DocumentWindow`), kept here instead of on the Mac's clipboard. An
            // adjustment layer has no pixels of its own, so Copy takes what shows.
            if cut, !editor.hasSelection || editor.refusedBecauseLocked() { return }
            let shows = merged || !editor.canvas.activeLayer.isPixelLayer
            let pixels = (shows ? editor.selectedMergedPixels() : editor.selectedPixels()) ?? editor.saveSnapshot().flattened
            Self.copied = (pixels, editor.copiedPlace(merged: shows))
            if cut { editor.deleteSelection(named: "Cut") }
        case .pasteInPlace:
            guard let copied = Self.copied else { return }
            editor.paste(copied.pixels, inPlaceAt: copied.place)
        case let .several(indices, command):
            if indices.isEmpty {
                editor.selectAllLayers()
            } else {
                editor.selectLayer(at: layer(indices[0]))
                for index in indices.dropFirst() { editor.chooseLayer(at: layer(index), extending: false, toggling: true) }
            }
            switch command {
            case .align(let alignment): editor.alignChosenLayers(alignment)
            case .distribute(let distribution): editor.distributeChosenLayers(distribution)
            case .visible: editor.toggleChosenLayersVisible()
            case .locked: editor.toggleChosenLayersLocked()
            case .lockTransparency: editor.toggleChosenLayersLockTransparency()
            case .group: editor.groupLayers()
            }
        case let .renameLayer(name): editor.renameLayer(at: editor.activeLayerIndex, to: name)
        case .passThrough:
            guard editor.canvas.activeLayer.isGroup else { return }
            editor.setPassesThrough()
        case let .isolate(index): editor.toggleIsolation(at: layer(index))
        case let .renameSnapshot(index, name):
            let snapshots = editor.history.snapshots
            guard !snapshots.isEmpty else { return }
            editor.renameSnapshot(snapshots[index % snapshots.count].id, to: name)
        case let .toolOptions(options): options.apply(to: editor)
        case let .zoom(scale): editor.zoom(to: scale)
        case let .canvasProperties(width, height, anchor):
            editor.applyCanvasProperties(size: IntSize(width: width, height: height), anchor: anchor,
                                         transparentBackground: editor.canvas.hasTransparentBackground)
        case .trim: editor.trim()
        case .revertLayer: editor.revertLayer()
        case let .drop(width, height, color, at):
            let picture = PixelBuffer(width: width, height: height, fill: color)
            guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB), let data = try? ImageCodec.encodePNG(picture, colorSpace: sRGB),
                  let decoded = try? ImageCodec.decode(data, convertingTo: editor.canvas.colorSpace) else { return }
            editor.paste(decoded.buffer, at: IntPoint(x: Int(at.x) - width / 2, y: Int(at.y) - height / 2))
        case let .historyJump(count):
            let steps = editor.history.undoCount + editor.history.redoCount
            editor.jump(toStep: count % (steps + 1))
            if editor.snapshotQuestion != nil { editor.deleteSnapshotsAndRedact() }
        case let .wand(at, object, shift, option):
            editor.selectTool(.magicWand)
            editor.wandMode = object ? .object : .color
            editor.beginSelectionDrag(at: at, modifiers: DragModifiers(shift: shift, option: option))
            editor.endSelectionDrag(at: at)
            await Self.settle(editor)
            editor.wandMode = .color
        case let .lasso(points, shift, option):
            editor.selectTool(.lassoSelect)
            editor.beginSelectionDrag(at: points[0], modifiers: DragModifiers(shift: shift, option: option))
            for point in points.dropFirst() { editor.continueSelectionDrag(to: point, shiftDown: shift) }
            editor.endSelectionDrag(at: points[points.count - 1])
        case let .badge(at, to, secondary, leavesOpen):
            editor.selectTool(.stepBadge)
            editor.beginBadge(at: at, secondary: secondary)
            if let to { editor.continueBadge(to: to) }
            editor.endBadge()
            if !leavesOpen { editor.commitPendingBadge() }
        case let .measure(from, to):
            editor.selectTool(.measure)
            editor.measure(from: from, to: to)
        case let .eyedropper(at, secondary, allLayers):
            editor.selectTool(.eyedropper)
            editor.pickColor(at: at, secondary: secondary, allLayers: allLayers)
        case let .dragOpen(which, by):
            if let spec = editor.pendingShapeSpec, editor.pendingShape?.isBuilding == false {
                // Each handle `shapeHandle(atView:)` finds, then a point on the shape, which moves it.
                var grabs: [Point2D] = if spec.kind.isLinear { [spec.end, spec.start] }
                    else if spec.kind.isPointBased { spec.points }
                    else { [editor.pendingShapeRotateHandle].compactMap { $0 } + SelectionHandle.allCases.map { spec.rotated($0.point(on: spec.box)) } }
                grabs.append(spec.kind.isLinear ? Point2D(x: (spec.start.x + spec.end.x) / 2, y: (spec.start.y + spec.end.y) / 2)
                                                : spec.boxCenter)
                let start = grabs[which % grabs.count], end = Point2D(x: start.x + by.x, y: start.y + by.y)
                editor.beginShapeDrag(at: start, viewPoint: editor.viewport.viewPoint(fromImage: start), secondary: false, clickCount: 1)
                editor.continueShapeDrag(to: end, shiftDown: false)
                editor.endShapeDrag()
            } else if editor.pendingText != nil {
                let handles = editor.pendingTextHandles
                let grab: TextBoxGrab = which % (handles.count + 1) < handles.count ? .handle(handles[which % (handles.count + 1)].handle) : .border
                let start = handles.first { TextBoxGrab.handle($0.handle) == grab }?.point ?? handles.first?.point ?? Point2D(x: 0, y: 0)
                editor.beginTextBoxDrag(grab, at: start)
                editor.continueTextBoxDrag(to: Point2D(x: start.x + by.x, y: start.y + by.y))
                editor.endTextBoxDrag()
            }
        case .copyText:
            // A clipboard count no real one has, so a later redaction never offers to clear the Mac's clipboard.
            editor.copyText { _ in Int.min }
            for _ in 0..<400 where editor.isReadingText { try? await Task.sleep(for: .milliseconds(25)) }
        case let .markSubjects(action, clicks):
            editor.findSubject(action)
            await Self.settle(editor)
            for (index, click) in clicks.enumerated() where editor.activeEffect == .pickSubject {
                editor.beginCanvasToolDrag(at: click, viewPoint: editor.viewport.viewPoint(fromImage: click), adding: index > 0)
                editor.endCanvasToolDrag()
                await Self.settle(editor)
            }
            if editor.activeEffect == .pickSubject { editor.applyEffect() }
            await Self.settle(editor)
            if editor.activeEffect != nil { editor.cancelEffect() }
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

extension MonkeyStep {
    /// The layers just after the newest effect's bar opened, for checking that Cancel goes back to them.
    @MainActor static var effectOpened: [String]?

    /// A rule a raw input script broke while it played, for `MonkeyEpisode.drive` to report.
    @MainActor static var inputFailure: MonkeyFailure?
    /// The pages a raw input script's keys or menu commands showed, in order: the page left, its layers just before (nil
    /// when something open or floating would be placed on the way out), and the page shown with its layers as it came
    /// into view. What followed may edit the new page, so it's checked as it arrived (monkey, seed 1795400231).
    @MainActor static var inputPageChanges: [(left: Page, leftLayers: [String]?, shown: Page, shownLayers: [String])] = []
    @MainActor static var inputLowestUndoCount = 0
    /// What Copy, Copy Merged or Cut took, and where from, for Paste in Place. Cleared at the start of each episode.
    @MainActor static var copied: (pixels: PixelBuffer, place: IntPoint)?

    /// Waits, ten seconds at most, for whatever a step started in the background: a fill or tone match, a subject or
    /// eye search, a changed selection or range, an effect's preview.
    @MainActor
    static func settle(_ editor: Editor) async {
        for _ in 0..<400 where editor.fillProgress != nil || editor.fillingArea != nil || editor.isMatchingTone || editor.pendingTone != nil
            || editor.isFindingSubject || editor.isFindingEyes || editor.isWorkingOnSelectionChange || editor.rangeRunning
            || editor.previewRunning || editor.previewWanted || editor.effectPreviewScheduled || editor.straightenRunning {
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    /// Waits, a few seconds at most, for an effect's preview to be worked out in the background.
    @MainActor
    static func waitForPreview(_ editor: Editor) async {
        for _ in 0..<400 where editor.previewRunning || editor.previewWanted || editor.effectPreviewScheduled || editor.straightenRunning {
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    /// Answers the question asked before a redaction over History Snapshots, if one is up.
    @MainActor
    static func answerSnapshots(_ editor: Editor, cancels: Bool) {
        guard editor.snapshotQuestion != nil else { return }
        if cancels { editor.snapshotQuestion = nil } else { editor.deleteSnapshotsAndRedact() }
    }

    static func answer(_ cancels: Bool) -> String { cancels ? " (Cancel if asked about snapshots)" : "" }
}
