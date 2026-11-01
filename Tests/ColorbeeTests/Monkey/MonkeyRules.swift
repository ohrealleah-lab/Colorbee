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

    /// After a redaction that changed the page shown: none of its snapshots are left to show what was redacted
    /// (Leah, 2026-11-01).
    static func checkRedacted(_ editor: Editor) throws(MonkeyFailure) {
        let left = editor.history.snapshots.count
        guard left == 0 else {
            throw MonkeyFailure(rule: "A redaction left History Snapshots", detail: "\(left) snapshots still show what was redacted.")
        }
    }

    /// After a redaction (monkey gaps, R1): no layer it changed is still a text layer or carries those words in its name or
    /// its mask's, and the saved project holds them nowhere unless a layer it didn't touch still does.
    static func checkNothingLeft(_ editor: Editor, redacted: [Layer], words: [LayerID: String]) throws(MonkeyFailure) {
        let canvas = editor.canvas
        var gone: [String] = []
        for layer in redacted {
            guard let text = words[layer.id], text.count >= 2 else { continue }
            if layer.text != nil {
                throw MonkeyFailure(rule: "A redacted text layer kept its words", detail: "\"\(layer.name)\" is still a text layer.")
            }
            if layer.name.contains(text) || layer.mask?.name.contains(text) == true {
                throw MonkeyFailure(rule: "Redacted words survive in a layer's name", detail: "\"\(layer.name)\" still names \"\(text)\".")
            }
            gone.append(text)
        }
        let kept = canvas.layers.flatMap { [$0.name, $0.mask?.name ?? "", $0.text?.spec.text ?? ""] }
        let lost = gone.filter { text in text.count >= 4 && !kept.contains { $0.contains(text) } }
        guard !lost.isEmpty else { return }
        let data: Data
        do { data = try ProjectFile.encode(canvas) } catch { return }
        for text in lost where data.range(of: Data(text.utf8)) != nil {
            throw MonkeyFailure(rule: "Redacted words survive in the saved project", detail: "\"\(text)\" is still in the file.")
        }
    }

    /// After Forget History (monkey gaps, R1b): no page can undo, redo or go to a snapshot, and the picture is as it was.
    static func checkForgotten(_ editor: Editor, before: [String]?) throws(MonkeyFailure) {
        for (index, page) in editor.pages.pages.enumerated() {
            let history = page.history
            guard history.undoCount == 0, history.redoActionName == nil, history.snapshots.isEmpty else {
                throw MonkeyFailure(rule: "Forget History left something behind",
                                    detail: "Page \(index + 1) can still undo, redo or go to a snapshot.")
            }
        }
        if let before, before != layerStates(of: editor.canvas, floatingOn: nil) {
            throw MonkeyFailure(rule: "Forget History changed the picture", detail: UndoTracker.difference(before, layerStates(of: editor.canvas, floatingOn: nil)))
        }
    }

    /// The size, then each layer's state with its id; a layer a piece floats on (or whose mask it floats on) without its
    /// pixels, since saving stamps the piece in.
    static func layerStates(of canvas: Canvas, floatingOn: LayerID?) -> [String] {
        ["\(canvas.size.width) × \(canvas.size.height)"] + canvas.layers.map { layer in
            state(of: layer, pixels: floatingOn == nil || (layer.id != floatingOn && layer.mask?.id != floatingOn)) + "|\(layer.id.rawValue)"
        }
    }

    /// The marquee or floating piece, as text (monkey gaps, R3): a floating piece's pixels live only here until placed.
    static func selectionState(of canvas: Canvas) -> String {
        if let floating = canvas.selection.floating {
            return "a floating piece on layer \(floating.layerID.rawValue) at \(floating.destination), pixels \(floating.pixels.contentHash())"
        }
        guard let mask = canvas.selection.marquee else { return "no selection" }
        var hasher = Hasher()
        for y in mask.bounds.minY..<mask.bounds.maxY {
            for x in mask.bounds.minX..<mask.bounds.maxX { hasher.combine(mask[x, y]) }
        }
        return "a marquee over \(mask.bounds), \(hasher.finalize())"
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

    /// A project reopened mid-way holds what was saved: as many pages, and the shown one with the same layers.
    static func checkSame(_ saved: Canvas, _ reopened: Canvas, pages: (Int, Int)) throws(MonkeyFailure) {
        guard pages.0 == pages.1 else {
            throw MonkeyFailure(rule: "A saved project reopens with different pages", detail: "\(pages.1) pages came back, not \(pages.0).")
        }
        let floatingOn = saved.selection.floating?.layerID
        let before = saved.layers.map { state(of: $0, pixels: $0.id != floatingOn && $0.mask?.id != floatingOn) }
        let after = reopened.layers.map { state(of: $0, pixels: $0.id != floatingOn && $0.mask?.id != floatingOn) }
        guard reopened.flattened().contentHash() == saved.flattened().contentHash() else {
            throw MonkeyFailure(rule: "A saved project reopens looking different", detail: "The page shown came back looking different.")
        }
        guard before == after else {
            throw MonkeyFailure(rule: "A saved project reopens with different layers", detail: "The page shown came back with different layers.")
        }
    }

    /// At the end: a saved project reopens the same, and the thumbnail matches the export.
    static func checkSaving(_ editor: Editor) throws(MonkeyFailure) {
        editor.placePendingObjects()
        let canvas = editor.canvas
        let flat = canvas.flattened()
        // Thumbnails are a quick sketch by design: they leave out blurs and sharpening (adjustments with no color
        // transform). They show a floating piece, and round where the export does (review round 11).
        // Posterize turns a rounding difference of one level into a whole step, so it's left out too.
        let sketched = canvas.shownLayers.contains { layer in
            guard let adjustment = layer.adjustment else { return false }
            if case .posterize = adjustment { return true }
            // Adjust Photo's detail and vignette are left out of thumbnails by design (stage 15).
            if case .photo(let edit) = adjustment,
               [.sharpness, .definition, .texture, .noiseReduction, .vignette, .grain].contains(where: { edit.adjustments[$0] != 0 }) { return true }
            return adjustment.colorTransform == nil
        }
        if !sketched {
            let thumbnail = canvas.thumbnail(maxSide: max(canvas.size.width, canvas.size.height))
            let exported = flat.pixels(in: canvas.bounds)
            // Clear pixels' colors don't show, and a hue shift can magnify a lone pixel's rounding: a few are allowed.
            let apart = zip(thumbnail.pixels, exported).filter { a, b in
                let alphaA = Int(a.a), alphaB = Int(b.a)
                func shown(_ value: UInt8, _ alpha: Int) -> Int { Int(value) * alpha / 255 }
                return max(abs(shown(a.r, alphaA) - shown(b.r, alphaB)), abs(shown(a.g, alphaA) - shown(b.g, alphaB)),
                           abs(shown(a.b, alphaA) - shown(b.b, alphaB)), abs(alphaA - alphaB)) > 6
            }.count > 3
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
