import ColorbeeCore
import Foundation
@testable import Colorbee

/// Far more than everyday use (monkey hardening, S7): many layers, groups inside groups, a huge picture. Each must work, or be
/// refused cleanly, and undo all the way back. Run once at the start of a monkey run; `big` is the huge picture's side.
@MainActor
enum MonkeyLimits {
    static func check(layers layerCount: Int, depth: Int, big: Int) async -> MonkeyFailure? {
        do {
            try await manyLayers(layerCount)
            try await nestedGroups(depth)
            try await hugePicture(big)
        } catch let failure as MonkeyFailure {
            return failure
        } catch {
            return MonkeyFailure(rule: "The limits check failed", detail: "\(error)")
        }
        return nil
    }

    private static func editor(_ size: Int) -> Editor {
        let canvas = Canvas(size: IntSize(width: size, height: size), colorSpace: Canvas.defaultColorSpace, background: .white)
        let editor = Editor(pages: PageStack(pages: [Page(canvas: canvas, history: Editor.makeHistory())]))
        editor.textIsEditable = false
        editor.smoothing = 0
        return editor
    }

    /// Hundreds of layers, each painted, merged, saved and reopened, then every step undone.
    private static func manyLayers(_ count: Int) async throws {
        let editor = editor(64)
        let start = editor.documentState
        for index in 1..<count {
            editor.addLayer()
            editor.selectTool(.pencil)
            editor.color1 = Pixel(r: UInt8(index % 256), g: 80, b: 160)
            editor.beginStroke(at: Point2D(x: Double(index % 60) + 0.5, y: 2.5), secondary: false)
            editor.continueStroke(to: Point2D(x: Double(index % 60) + 0.5, y: 60.5), constrain: false)
            editor.endStroke()
        }
        guard editor.canvas.layers.count == count else {
            throw MonkeyFailure(rule: "Many layers couldn't be made", detail: "\(editor.canvas.layers.count) layers, not \(count).")
        }
        try MonkeyRules.checkDocument(editor)
        try MonkeyRules.checkSaving(editor)
        editor.mergeVisible()
        editor.undo()
        editor.flatten()
        try MonkeyRules.checkDocument(editor)
        try undoAll(editor, back: start, what: "\(count) layers")
    }

    /// Groups inside groups, `depth` deep, then ungrouped and undone.
    private static func nestedGroups(_ depth: Int) async throws {
        let editor = editor(48)
        let start = editor.documentState
        editor.addLayer()
        for _ in 0..<depth {
            // The active layer (a group, after the first time) and a new layer above it, grouped.
            let active = editor.activeLayerIndex
            editor.addLayer()
            editor.chooseLayer(at: editor.activeLayerIndex, extending: false, toggling: false)
            editor.chooseLayer(at: active, extending: false, toggling: true)
            editor.groupLayers()
            try MonkeyRules.checkDocument(editor)
        }
        let deepest = editor.canvas.layers.map { editor.canvas.ancestors(of: $0).count }.max() ?? 0
        guard deepest >= depth else {
            throw MonkeyFailure(rule: "Groups couldn't go deep", detail: "The deepest layer is in \(deepest) groups, not \(depth).")
        }
        try MonkeyRules.checkSaving(editor)
        while let group = editor.canvas.layers.lastIndex(where: \.isGroup) {
            editor.selectLayer(at: group)
            let count = editor.canvas.layers.count
            editor.ungroupLayers()
            guard editor.canvas.layers.count < count else { break }
        }
        try MonkeyRules.checkDocument(editor)
        try undoAll(editor, back: start, what: "groups \(depth) deep")
    }

    /// A picture `side` pixels square: a fill, a stroke, a selection moved, a turn, then all undone and redone.
    private static func hugePicture(_ side: Int) async throws {
        let editor = editor(side)
        let start = editor.documentState
        editor.selectTool(.fill)
        editor.color1 = Pixel(r: 200, g: 40, b: 40)
        editor.fill(at: Point2D(x: 1, y: 1), secondary: false)
        editor.addLayer()
        editor.selectTool(.brush)
        editor.brushDiameter = 40
        editor.beginStroke(at: Point2D(x: 10, y: 10), secondary: false)
        editor.continueStroke(to: Point2D(x: Double(side) - 10, y: Double(side) - 10), constrain: false)
        editor.endStroke()
        editor.selectTool(.rectangleSelect)
        editor.selectionDrag(from: Point2D(x: 5, y: 5), to: Point2D(x: Double(side) / 2, y: Double(side) / 2))
        editor.selectionDrag(from: Point2D(x: Double(side) / 4, y: Double(side) / 4), to: Point2D(x: Double(side) / 4 + 300, y: Double(side) / 4 + 200))
        editor.deselect()
        editor.apply(.rotate90Clockwise)
        try MonkeyRules.checkDocument(editor)
        let end = editor.documentState
        try undoAll(editor, back: start, what: "a \(side) × \(side) picture")
        while editor.history.canRedo { editor.redo() }
        guard editor.documentState == end else {
            throw MonkeyFailure(rule: "Redo didn't bring back a huge picture", detail: UndoTracker.difference(end, editor.documentState))
        }
    }

    private static func undoAll(_ editor: Editor, back start: [String], what: String) throws {
        var guardSteps = 0
        while editor.history.canUndo, guardSteps < 2000 {
            editor.undo()
            guardSteps += 1
        }
        guard editor.documentState == start else {
            throw MonkeyFailure(rule: "Undoing everything didn't go back to the start", detail: "With \(what): " + UndoTracker.difference(start, editor.documentState))
        }
    }
}
