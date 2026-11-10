import ColorbeeCore
import Foundation
@testable import Colorbee

/// The rules that must always hold (stage 32), in plain words for the report.
@MainActor
enum MonkeyRules {
    /// What one step can hold in history at most: a crop or resize keeps every layer and mask twice.
    static func stepBytes(_ canvas: Canvas) -> Int {
        2 * (canvas.layers.count + canvas.layers.compactMap(\.mask).count) * canvas.size.width * canvas.size.height * 4
    }

    /// After every step: the document is sound. `slack` is the most one step could have held earlier in the episode,
    /// since a step that shrank the picture still holds the bigger layers it replaced.
    static func checkDocument(_ editor: Editor, slack: Int = 0) throws(MonkeyFailure) {
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
        // Pictures here are tiny, so one step (a crop holds every layer twice) is a few MB at most; the old 64 MB slack
        // let a history that never spilled pass (review AH, finding 3). The rare larger pictures need more.
        if history.byteCount > history.byteBudget + max(8 << 20, stepBytes(canvas), slack) {
            throw MonkeyFailure(rule: "History went over its memory budget", detail: "\(history.byteCount >> 20) MB held, budget \(history.byteBudget >> 20) MB.")
        }
    }

    /// Each page's History revision, undo count and snapshot count, by page.
    static func histories(of editor: Editor) -> [UUID: (revision: Int, undoCount: Int, snapshots: Int)] {
        Dictionary(uniqueKeysWithValues: editor.pages.pages.map { ($0.id, ($0.history.revision, $0.history.undoCount, $0.history.snapshots.count)) })
    }

    /// After a redaction step: no page it changed keeps snapshots that show what was redacted (Leah, 2026-11-01), on
    /// any page an Auto-Redact reached too. With nothing redacted (Cancel, or nothing to cover), no page lost a
    /// snapshot or gained a step, except the page `placing` a floating piece first, which is a step of its own when it
    /// can't join the step that made it.
    static func checkRedacted(_ editor: Editor, before: [UUID: (revision: Int, undoCount: Int, snapshots: Int)],
                              redacted: Bool, placing: UUID?) throws(MonkeyFailure) {
        for (index, page) in editor.pages.pages.enumerated() {
            guard let was = before[page.id] else { continue }
            let history = page.history
            if redacted {
                guard history.revision == was.revision || history.snapshots.isEmpty else {
                    throw MonkeyFailure(rule: "A redaction left History Snapshots",
                                        detail: "\(history.snapshots.count) snapshots on page \(index + 1) still show what was redacted.")
                }
            } else {
                let steps = history.undoCount - was.undoCount
                guard history.snapshots.count == was.snapshots, steps == 0 || (steps == 1 && page.id == placing) else {
                    throw MonkeyFailure(rule: "A redaction that did nothing changed History",
                                        detail: "Page \(index + 1) had \(was.snapshots) snapshots and \(was.undoCount) steps; now \(history.snapshots.count) and \(history.undoCount).")
                }
            }
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

    /// Adjust Photo is drawn on screen by its own shader and in exports by the core: written apart, so agreeing is real
    /// evidence the math is right. Checked on the photo-like picture `ScreenMatchesExportTests` uses. Steep settings
    /// magnify the two sides' rounding, so the limits (from 300 random settings, 2026-11-10: at worst an average of 2,
    /// 1% of values off by more than 12 and one by 62) are wider than that test's for single controls. A control that's
    /// missing or wrong differs by about as much as it changes the picture, far past them.
    static func checkShowsAsExported(_ edit: PhotoEdit) throws(MonkeyFailure) {
        let editor = ScreenMatchesExportTests.picture()
        let before = editor.canvas.flattened()
        editor.addAdjustmentLayer(.photo(edit), named: "Adjust Photo")
        // Controls that look at neighbors are blurred by Metal on screen and vImage in exports, which round apart; a
        // filter may hold them too.
        let neighbors = edit.filter != nil || [.texture, .sharpness, .definition, .noiseReduction].contains { edit.adjustments[$0] != 0 }
        // A steep tone curve magnifies a level's difference before it many times over: one with regions squeezed close
        // together, or a steep step in its table.
        let steep = edit.toneCurve.map { curve in
            let marks = [0] + curve.splits + [100], table = curve.table
            return !curve.isNeutral && (zip(marks, marks.dropFirst()).contains { $1 - $0 < 10 }
                || zip(table, table.dropFirst()).contains { abs(Int($1) - Int($0)) >= 3 })
        } ?? false
        try compare(screen: ScreenMatchesExportTests.screen(editor.canvas), export: editor.canvas.flattened(), before: before, neighbors: neighbors, steep: steep)
    }

    static func compare(screen: PixelBuffer, export: PixelBuffer, before: PixelBuffer, neighbors: Bool, steep: Bool = false) throws(MonkeyFailure) {
        let mismatch = ScreenMatchesExportTests.difference(screen, export)
        let change = ScreenMatchesExportTests.difference(before, export)
        var farOff = 0
        for y in 0..<export.height {
            for x in 0..<export.width {
                let p = screen[x, y], q = export[x, y]
                for (u, v) in [(p.r, q.r), (p.g, q.g), (p.b, q.b), (p.a, q.a)] where abs(Int(u) - Int(v)) > 12 { farOff += 1 }
            }
        }
        let average = max(neighbors ? 2.5 : 1.5, change.average / 5), largest = neighbors ? 96 : 48
        let share = Double(farOff) / Double(max(mismatch.count, 1)), allowedShare = (neighbors ? 0.02 : 0.01) * (steep ? 3 : 1)
        guard mismatch.average <= average, mismatch.largest <= largest, share <= allowedShare else {
            throw MonkeyFailure(rule: "Adjust Photo looks different on screen than exported",
                                detail: "Screen against export: \(mismatch), \(String(format: "%.1f", share * 100))% off by more than 12; "
                                    + "allowed average \(String(format: "%.2f", average)), largest \(largest), \(Int(allowedShare * 100))%.")
        }
    }

    /// Nothing the monkey applied became Leah's "last used" Adjust Photo settings.
    static func checkLastPhoto(was: PhotoEdit?) throws(MonkeyFailure) {
        guard PhotoSettingsStore.shared.last == was else {
            throw MonkeyFailure(rule: "The monkey changed the last Adjust Photo settings", detail: "Same as Last would now use the monkey's.")
        }
    }

    /// Each pixel layer's pixels, to compare with after a redaction.
    static func pixels(of canvas: Canvas) -> [LayerID: [Pixel]] {
        Dictionary(uniqueKeysWithValues: canvas.layers.filter(\.isPixelLayer).map { ($0.id, $0.buffer.pixels(in: canvas.bounds)) })
    }

    /// The layers that had something under `area` before the redaction.
    static func layersUnder(_ area: SelectionMask, in canvas: Canvas, before: [LayerID: [Pixel]]) -> [Layer] {
        canvas.layers.filter { layer in
            guard let pixels = before[layer.id] else { return false }
            return points(of: area).contains { pixels[$0.y * canvas.size.width + $0.x].a > 0 }
        }
    }

    private static func points(of area: SelectionMask) -> [IntPoint] {
        var points: [IntPoint] = []
        for y in area.bounds.minY..<area.bounds.maxY {
            for x in area.bounds.minX..<area.bounds.maxX where area[x, y] > 0 { points.append(IntPoint(x: x, y: y)) }
        }
        return points
    }

    /// Whether two pixels look different by enough that blurring or pixelating them together must change something.
    private static func differ(_ a: Pixel, _ b: Pixel) -> Bool {
        if abs(Int(a.a) - Int(b.a)) >= 8 { return true }
        guard a.a >= 128, b.a >= 128 else { return false }
        return max(abs(Int(a.r) - Int(b.r)), abs(Int(a.g) - Int(b.g)), abs(Int(a.b) - Int(b.b))) >= 8
    }

    /// After a redaction: what's under the area is really covered on every layer, hidden ones too. A Solid Fill leaves
    /// only its color on a layer that had anything there. Blur and Pixelate can only be told apart from nothing where
    /// the layer wasn't flat, and need `before`; without it (a floating piece was placed first) they aren't checked.
    static func checkCovered(_ canvas: Canvas, area: SelectionMask, effect: Effect, before: [LayerID: [Pixel]]) throws(MonkeyFailure) {
        let inArea = points(of: area), width = canvas.size.width
        for layer in canvas.layers where layer.isPixelLayer {
            if case .solidFill(let color) = effect {
                let left = inArea.first { point in
                    let pixel = layer.buffer[point.x, point.y]
                    return pixel.a > 0 && pixel != color
                }
                if let left {
                    throw MonkeyFailure(rule: "A redaction left pixels showing",
                                        detail: "\"\(layer.name)\" still has something other than the fill at (\(left.x), \(left.y)).")
                }
                continue
            }
            guard let was = before[layer.id] else { continue }
            let mustChange: Bool
            switch effect {
            case .pixelate(let cellSize):
                let cells = Dictionary(grouping: inArea) { IntPoint(x: $0.x / cellSize, y: $0.y / cellSize) }
                mustChange = cells.values.contains { cell in
                    cell.dropFirst().contains { differ(was[$0.y * width + $0.x], was[cell[0].y * width + cell[0].x]) }
                }
            case .gaussianBlur:
                guard let first = inArea.first else { continue }
                mustChange = inArea.contains { differ(was[$0.y * width + $0.x], was[first.y * width + first.x]) }
            default:
                continue
            }
            let changed = inArea.contains { layer.buffer[$0.x, $0.y] != was[$0.y * width + $0.x] }
            if mustChange, !changed {
                throw MonkeyFailure(rule: "A redaction skipped a layer", detail: "\"\(layer.name)\" had something under \(effect.name) and didn't change.")
            }
        }
    }

    /// `checkCovered` for everything the newest redaction reports, on whichever pages it reached.
    static func checkCovered(_ editor: Editor, before: [LayerID: [Pixel]]) throws(MonkeyFailure) {
        for record in editor.lastRedaction {
            guard let page = editor.pages.pages.first(where: { $0.id == record.page }) else { continue }
            if page === editor.page {
                try checkCovered(editor.canvas, area: record.area, effect: record.effect, before: before)
            } else if let canvas = (try? page.projectData()).flatMap({ try? ProjectFile.decode($0) }) {
                try checkCovered(canvas, area: record.area, effect: record.effect, before: [:])
            }
        }
    }

    /// What an open shape or text box is, if placing it is certain to leave a step: words on a text layer of their own,
    /// or a plain outline in Color 1 between two points well inside the picture, on a layer that can take it.
    static func certainToLand(_ editor: Editor) -> String? {
        if let text = editor.pendingText, editor.textIsEditable, text.layerID == nil, !text.string.isEmpty { return "text" }
        guard let shape = editor.pendingShape, !shape.swapped, !shape.isBuilding, editor.shapeOutline != nil else { return nil }
        let canvas = editor.canvas, layer = canvas.activeLayer
        guard canvas.bounds.contains(IntPoint(x: Int(shape.start.x), y: Int(shape.start.y))),
              canvas.bounds.contains(IntPoint(x: Int(shape.end.x), y: Int(shape.end.y))),
              abs(shape.start.x - shape.end.x) >= 4, abs(shape.start.y - shape.end.y) >= 4,
              layer.isPixelLayer, !canvas.isLocked(layer), !canvas.locksTransparency(layer), !canvas.editsMask else { return nil }
        return "shape"
    }

    /// An open object that's gone must be in history. Not after Undo, which discards an open shape, or after a new shape
    /// or text: its settings land on the open one first, and None or Editable off can rightly leave nothing to place.
    static func checkLanded(_ editor: Editor, open: String?, step: MonkeyStep, page: Page, revisionBefore: Int) throws(MonkeyFailure) {
        switch step {
        case .undo, .shape, .text: return
        default: break
        }
        guard let open, editor.pendingShape == nil, editor.pendingText == nil, page.history.revision == revisionBefore else { return }
        throw MonkeyFailure(rule: "A \(open) left open vanished", detail: "\(step) closed it, but nothing was placed.")
    }

    /// After Forget History (monkey gaps, R1b): no page can undo, redo or go to a snapshot, no page change can be undone
    /// or redone (bringing back a deleted page), the picture is as it was, and Before/After's As Opened is the picture
    /// now on every page (review AH, finding 7).
    static func checkForgotten(_ editor: Editor, before: [String]?) throws(MonkeyFailure) {
        for (index, page) in editor.pages.pages.enumerated() {
            let history = page.history
            guard history.undoCount == 0, history.redoActionName == nil, history.snapshots.isEmpty else {
                throw MonkeyFailure(rule: "Forget History left something behind",
                                    detail: "Page \(index + 1) can still undo, redo or go to a snapshot.")
            }
        }
        guard editor.undoActionName == nil, editor.redoActionName == nil, editor.pages.restorablePages.isEmpty else {
            throw MonkeyFailure(rule: "Forget History left something behind",
                                detail: "Undo or Redo can still bring back \(editor.undoActionName ?? editor.redoActionName ?? "a deleted page").")
        }
        guard let before else { return }
        if before != layerStates(of: editor.canvas, floatingOn: nil) {
            throw MonkeyFailure(rule: "Forget History changed the picture", detail: UndoTracker.difference(before, layerStates(of: editor.canvas, floatingOn: nil)))
        }
        for (index, page) in editor.pages.pages.enumerated() {
            let opened: PixelBuffer?, now: PixelBuffer?
            if page === editor.page {
                (opened, now) = (editor.asOpened, editor.canvas.flattened())
            } else {
                guard let memory = editor.pageMemory[page.id] else { continue }
                opened = memory.opened.flattened
                now = (try? page.projectData()).flatMap { try? ProjectFile.decode($0) }?.flattened()
            }
            guard let opened, let now, shownHash(opened) == shownHash(now) else {
                throw MonkeyFailure(rule: "Forget History kept an older As Opened picture",
                                    detail: "Before/After on page \(index + 1) can still show the picture as it was.")
            }
        }
    }

    /// A picture's hash as it shows: a fully clear pixel's color can't be seen, and a save may keep a leftover one.
    static func shownHash(_ buffer: PixelBuffer) -> Int {
        var hasher = Hasher()
        for y in 0..<buffer.height {
            for x in 0..<buffer.width {
                let pixel = buffer[x, y]
                hasher.combine(pixel.a == 0 ? Pixel.clear : pixel)
            }
        }
        return hasher.finalize()
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
        // An adjustment by its hash: the dictionaries inside Adjust Photo's settings print in no fixed order.
        words += "|\(layer.clipsToLayerBelow)|\(layer.passesThrough)|\(layer.groupID.map { "\($0.rawValue)" } ?? "-")|\(layer.adjustment.map { "\($0.hashValue)" } ?? "-")"
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
        guard shownHash(reopened.flattened()) == shownHash(saved.flattened()) else {
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
        guard shownHash(reopened.flattened()) == shownHash(flat) else {
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
