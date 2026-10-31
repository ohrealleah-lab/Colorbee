import ColorbeeCore
import Foundation
@testable import Colorbee

/// The rules that must always hold (stage 32), in plain words for the report.
@MainActor
enum MonkeyRules {
    /// After every step: the document is sound.
    static func checkDocument(_ editor: Editor) throws(MonkeyFailure) {
        let canvas = editor.canvas
        guard !canvas.layers.isEmpty, canvas.layers.indices.contains(canvas.activeLayerIndex) else {
            throw MonkeyFailure(rule: "The active layer went missing", detail: "Active layer \(canvas.activeLayerIndex) of \(canvas.layers.count).")
        }
        for layer in canvas.layers + canvas.layers.compactMap(\.mask) where layer.buffer.size != canvas.size {
            throw MonkeyFailure(rule: "A layer isn't the picture's size",
                                detail: "\"\(layer.name)\" is \(layer.buffer.size.width) × \(layer.buffer.size.height); the picture is \(canvas.size.width) × \(canvas.size.height).")
        }
        // Every group's layers sit just below its row, and nothing names a group that isn't there.
        let ids = Set(canvas.layers.map(\.id))
        for layer in canvas.layers {
            if let group = layer.groupID, !ids.contains(group) || canvas.layers.first(where: { $0.id == group })?.isGroup != true {
                throw MonkeyFailure(rule: "A layer is in a group that doesn't exist", detail: "\"\(layer.name)\" names a group that isn't in the list.")
            }
        }
        for (index, group) in canvas.layers.enumerated() where group.isGroup {
            let members = canvas.layers.filter { canvas.ancestors(of: $0).contains { $0 === group } }.map(\.id)
            guard Array(canvas.layers[canvas.memberRange(ofGroupAt: index)]).map(\.id) == members else {
                throw MonkeyFailure(rule: "A group's layers came apart", detail: "\"\(group.name)\"'s layers aren't all just below it.")
            }
        }
        // A text layer is always its words drawn, so editing it can never lose anything.
        for layer in canvas.layers {
            guard let text = layer.text, text.isUpright, text.hasFont else { continue }
            guard layer.buffer.contentHash() == text.drawn(size: canvas.size, colorSpace: canvas.colorSpace).contentHash() else {
                throw MonkeyFailure(rule: "A text layer's pixels don't match its words", detail: "\"\(layer.name)\" shows something other than its text.")
            }
        }
        let history = editor.history
        if history.byteCount > history.byteBudget + 64 << 20 {
            throw MonkeyFailure(rule: "History went over its memory budget", detail: "\(history.byteCount >> 20) MB held, budget \(history.byteBudget >> 20) MB.")
        }
    }

    /// A layer's pixels, mask and settings, as text, for comparing.
    static func state(of layer: Layer, pixels: Bool) -> String {
        var words = "\(layer.name)|\(layer.isVisible)|\(layer.opacity)|\(layer.blendMode.rawValue)|\(layer.isLocked)|\(layer.locksTransparency)"
        words += "|\(layer.clipsToLayerBelow)|\(layer.passesThrough)|\(layer.groupID.map { "\($0.rawValue)" } ?? "-")|\(layer.adjustment.map { "\($0)" } ?? "-")"
        // Whether a mask is on means nothing without one, and isn't saved then.
        words += "|\(layer.text.map { "\($0)" } ?? "-")|\(layer.mask == nil || layer.maskEnabled)"
        if pixels {
            words += "|\(layer.isPixelLayer ? layer.buffer.contentHash() : 0)|\(layer.mask.map { $0.buffer.contentHash() } ?? 0)"
        } else {
            words += "|\(layer.mask != nil)"
        }
        return words
    }

    /// At the end: a saved project reopens the same, and the thumbnail matches the export.
    static func checkSaving(_ editor: Editor) throws(MonkeyFailure) {
        editor.placePendingObjects()
        let canvas = editor.canvas
        let flat = canvas.flattened()
        // Thumbnails are a quick sketch by design: they leave out blurs and sharpening (adjustments with no color
        // transform) and a floating piece, and round a little differently.
        let sketched = canvas.selection.floating != nil || canvas.shownLayers.contains { $0.adjustment != nil && $0.adjustment?.colorTransform == nil }
        if !sketched {
            let thumbnail = canvas.thumbnail(maxSide: max(canvas.size.width, canvas.size.height))
            let exported = flat.pixels(in: canvas.bounds)
            let apart = zip(thumbnail.pixels, exported).contains { a, b in
                max(abs(Int(a.r) - Int(b.r)), abs(Int(a.g) - Int(b.g)), abs(Int(a.b) - Int(b.b)), abs(Int(a.a) - Int(b.a))) > 6
            }
            guard !apart else {
                throw MonkeyFailure(rule: "The thumbnail doesn't match the export", detail: "The History and Layers thumbnails would show a different picture than Export writes.")
            }
        }
        let reopened: Canvas
        do {
            reopened = try ProjectFile.decode(try ProjectFile.encode(canvas))
        } catch {
            throw MonkeyFailure(rule: "Saving or reopening a project failed", detail: "\(error)")
        }
        guard reopened.flattened().contentHash() == flat.contentHash() else {
            throw MonkeyFailure(rule: "A saved project reopens looking different", detail: "The reopened picture differs from what was saved.")
        }
        // Every layer as it was, hidden ones too (review Z, finding 2); a floating piece is saved stamped in, so its layer's
        // pixels are left out of the comparison.
        let floatingOn = canvas.selection.floating?.layerID
        let saved = canvas.layers.map { state(of: $0, pixels: $0.id != floatingOn && $0.mask?.id != floatingOn) }
        let back = reopened.layers.map { layer in
            state(of: layer, pixels: layer.id != floatingOn && layer.mask?.id != floatingOn)
        }
        guard reopened.layers.map(\.id) == canvas.layers.map(\.id), back == saved else {
            let first = saved.indices.first { $0 >= back.count || saved[$0] != back[$0] } ?? 0
            throw MonkeyFailure(rule: "A saved project reopens with different layers",
                                detail: "Layer \(first + 1) (\"\(canvas.layers[min(first, canvas.layers.count - 1)].name)\") came back changed.")
        }
    }
}
