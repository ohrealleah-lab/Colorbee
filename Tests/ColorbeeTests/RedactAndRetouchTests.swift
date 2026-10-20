import ColorbeeCore
import Testing
@testable import Colorbee

/// The Redact Brush (FR-9.6) and the retouching tools (FR-4.6): each stroke is one undo step.
@MainActor
struct RedactAndRetouchTests {
    let red = Pixel(r: 220, g: 20, b: 30, a: 255)

    // MARK: Redact Brush

    func redactEditor() -> Editor {
        let editor = makeEditor()
        editor.selectTool(.redactBrush)
        editor.redactBrushSize = 8
        editor.redactTreatment = .solidFill
        editor.color1 = red
        return editor
    }

    func redactStroke(_ editor: Editor, _ points: [Point2D], constrain: Bool = false) {
        editor.beginRedactStroke(at: points[0], secondary: false)
        for point in points.dropFirst() { editor.continueRedactStroke(to: point, constrain: constrain) }
        editor.endRedactStroke()
    }

    @Test func aRedactStrokeChangesNothingUntilItEnds() {
        let editor = redactEditor()
        let before = editor.imageHash
        editor.beginRedactStroke(at: wobblyPath[0], secondary: false)
        for point in wobblyPath.dropFirst() { editor.continueRedactStroke(to: point, constrain: false) }
        #expect(editor.imageHash == before)
        #expect(editor.areaStrokePicture() != nil)
        editor.endRedactStroke()
        #expect(editor.imageHash != before)
    }

    @Test func aRedactStrokeIsOneStep() {
        let editor = redactEditor()
        let before = editor.imageHash
        redactStroke(editor, wobblyPath)
        #expect(editor.stepNames == ["Redact Brush"])
        #expect(editor.canvas.activeLayer.buffer[30, 21] == red)
        editor.undo()
        #expect(editor.imageHash == before)
    }

    @Test func shiftKeepsARedactStrokeOnOneLine() {
        let editor = redactEditor()
        redactStroke(editor, wobblyPath, constrain: true)
        let rows = editor.canvas.activeLayer.buffer.rowsChanged(from: paper)
        #expect(!rows.isEmpty)
        #expect(rows.allSatisfy { abs(Double($0) + 0.5 - wobblyPath[0].y) <= 5 })
    }

    /// It redacts every layer with pixels under it, still as one step, like Batch Redact.
    @Test func aRedactStrokeCoversEveryLayerInOneStep() {
        let editor = redactEditor()
        editor.addLayer()
        editor.selectTool(.pencil)
        editor.stroke(wobblyPath)
        let before = editor.imageHash
        let steps = editor.history.undoCount

        editor.selectTool(.redactBrush)
        redactStroke(editor, wobblyPath)

        #expect(editor.history.undoCount == steps + 1)
        #expect(editor.canvas.layers[0].buffer[30, 21] == red)
        #expect(editor.canvas.layers[1].buffer[30, 21] == red)
        editor.undo()
        #expect(editor.imageHash == before)
    }

    // MARK: Remove and Spot Heal (they fill in the background)

    /// A gray canvas with a black dot to remove.
    func removeEditor(_ kind: RetouchKind = .remove) -> Editor {
        let editor = makeEditor()
        editor.selectTool(.pencil)
        editor.stroke([pt(30.5, 30.5), pt(32.5, 30.5)])
        editor.selectTool(.retouch)
        editor.retouchKind = kind
        editor.retouchSize = 8
        return editor
    }

    func retouchStroke(_ editor: Editor, _ points: [Point2D]) {
        editor.beginRetouchStroke(at: points[0])
        for point in points.dropFirst() { editor.continueRetouchStroke(to: point, constrain: false) }
        editor.endRetouchStroke()
    }

    @Test(arguments: [RetouchKind.remove, .spotHeal])
    func aRemoveStrokeIsOneStep(kind: RetouchKind) async throws {
        let editor = removeEditor(kind)
        let withDot = editor.imageHash
        retouchStroke(editor, [pt(30.5, 30.5), pt(32.5, 30.5)])
        try await waitUntil { editor.fillProgress == nil }

        #expect(editor.stepNames == ["Pencil", kind.name])
        #expect(editor.canvas.activeLayer.buffer[31, 30] != .black)
        editor.undo()
        #expect(editor.imageHash == withDot)
    }

    @Test func removeIsRepeatable() async throws {
        var results: [Int] = []
        for _ in 0..<2 {
            let editor = removeEditor()
            retouchStroke(editor, [pt(30.5, 30.5), pt(32.5, 30.5)])
            try await waitUntil { editor.fillProgress == nil }
            results.append(editor.imageHash)
        }
        #expect(results[0] == results[1])
    }

    @Test func onlyOneFillRunsAtATime() async throws {
        let editor = removeEditor()
        retouchStroke(editor, [pt(30.5, 30.5)])
        var refusals = 0
        editor.onRefused = { refusals += 1 }
        editor.beginRetouchStroke(at: pt(10.5, 10.5))
        #expect(refusals == 1)
        try await waitUntil { editor.fillProgress == nil }
        #expect(editor.stepNames == ["Pencil", "Remove"])
    }

    @Test func aFillIsDroppedIfTheImageChangesMeanwhile() async throws {
        let editor = removeEditor()
        retouchStroke(editor, [pt(30.5, 30.5)])
        editor.undo()
        let undone = editor.imageHash
        try await waitUntil { editor.fillProgress == nil }
        #expect(editor.history.undoCount == 0)
        #expect(editor.imageHash == undone)
        #expect(editor.notice?.text == "The image changed while filling. Try again.")
    }

    @Test func aLockedLayerRefusesARemoveStroke() {
        let editor = removeEditor()
        editor.setLayerLocked(true, at: 0)
        var refusals = 0
        editor.onRefused = { refusals += 1 }
        editor.beginRetouchStroke(at: pt(30.5, 30.5))
        editor.endRetouchStroke()
        #expect(refusals == 1)
        #expect(editor.fillProgress == nil)
    }

    // MARK: Retouching brushes (they change pixels as you paint)

    nonisolated static let brushKinds: [RetouchKind] = [.lighten, .darken, .saturate, .desaturate, .blur, .sharpen, .smudge]

    @Test(arguments: brushKinds)
    func aRetouchBrushStrokeIsOneStep(kind: RetouchKind) {
        // Something with edges and color, so every brush has something to change.
        let editor = makeEditor(background: Pixel(r: 40, g: 120, b: 200, a: 255))
        editor.selectTool(.pencil)
        editor.color1 = red
        editor.stroke([pt(10.5, 30.5), pt(50.5, 30.5)])
        editor.selectTool(.retouch)
        editor.retouchKind = kind
        editor.retouchSize = 10
        editor.retouchStrength = 1
        let before = editor.imageHash

        editor.beginRetouchBrush(at: pt(10.5, 28.5), pressure: 1)
        for x in stride(from: 12.5, through: 50.5, by: 2) { editor.continueRetouchBrush(to: pt(x, 31.5), constrain: false, pressure: 1) }
        editor.endRetouchBrush()

        #expect(editor.imageHash != before, "\(kind.name)")
        #expect(editor.stepNames == ["Pencil", kind.name])
        editor.undo()
        #expect(editor.imageHash == before, "\(kind.name)")
    }

    @Test func theCloneStampNeedsASourceFirst() {
        let editor = makeEditor()
        editor.selectTool(.retouch)
        editor.retouchKind = .cloneStamp
        var refusals = 0
        editor.onRefused = { refusals += 1 }
        editor.beginRetouchBrush(at: pt(30, 30), pressure: 1)
        editor.endRetouchBrush()
        #expect(refusals == 1)
        #expect(editor.notice?.text == "Option-click where to copy from first")
        #expect(editor.history.undoCount == 0)
    }

    @Test func aCloneStampStrokeCopiesAsOneStep() {
        let editor = makeEditor()
        editor.selectTool(.pencil)
        editor.stroke([pt(10.5, 10.5), pt(20.5, 10.5)])
        editor.selectTool(.retouch)
        editor.retouchKind = .cloneStamp
        editor.retouchSize = 6
        editor.retouchHardness = 1
        editor.setCloneSource(pt(15.5, 10.5))
        let before = editor.imageHash

        editor.beginRetouchBrush(at: pt(15.5, 40.5), pressure: 1)
        editor.continueRetouchBrush(to: pt(16.5, 40.5), constrain: false, pressure: 1)
        editor.endRetouchBrush()

        #expect(editor.stepNames == ["Pencil", "Clone Stamp"])
        #expect(editor.canvas.activeLayer.buffer[15, 40] == .black)
        editor.undo()
        #expect(editor.imageHash == before)
    }

    @Test func shiftKeepsARetouchBrushOnOneLine() {
        let editor = makeEditor()
        editor.selectTool(.retouch)
        editor.retouchKind = .darken
        editor.retouchSize = 4
        editor.retouchStrength = 1

        editor.beginRetouchBrush(at: wobblyPath[0], pressure: 1)
        for point in wobblyPath.dropFirst() { editor.continueRetouchBrush(to: point, constrain: true, pressure: 1) }
        editor.endRetouchBrush()

        let rows = editor.canvas.activeLayer.buffer.rowsChanged(from: paper)
        #expect(!rows.isEmpty)
        #expect(rows.allSatisfy { abs(Double($0) + 0.5 - wobblyPath[0].y) <= 3 })
    }
}

/// Batch Redact never softens: on a feathered selection, Blur… and Pixelate… hide every partly selected pixel
/// completely, exactly as on the same selection with a hard edge (FR-3.4; review N, finding 1).
@MainActor
struct SoftBatchRedactTests {
    private func striped() -> Editor {
        let editor = makeEditor()
        for x in stride(from: 0, to: 64, by: 3) {
            editor.canvas.activeLayer.buffer.fill(.black, in: IntRect(x: x, y: 0, width: 1, height: 64))
        }
        return editor
    }

    private func redact(_ kind: EffectKind, soft: Bool) -> Int {
        let editor = striped()
        let box = SelectionMask.rectangle(IntRect(x: 16, y: 20, width: 30, height: 12), clippedTo: editor.canvas.bounds)!
        let feathered = box.feathered(radius: 8, clippedTo: editor.canvas.bounds)!
        // The hard edge to compare with: every pixel the feathered selection touches at all.
        editor.canvas.selection = .marquee(soft ? feathered : feathered.hardened())
        editor.beginBatchRedact(kind)
        editor.applyEffect()
        return editor.imageHash
    }

    @Test(arguments: [EffectKind.gaussianBlur, .pixelate])
    func aFeatheredSelectionIsRedactedCompletely(_ kind: EffectKind) {
        #expect(redact(kind, soft: true) == redact(kind, soft: false))
        #expect(redact(kind, soft: true) != striped().imageHash)
    }
}

/// Sample All Layers reads the active layer and those below it, so an adjustment above applies once
/// (Leah, 2026-10-13; review O, finding 4).
@MainActor
struct SampleAllLayersTests {
    @Test func aCloneUnderAnInvertLooksLikeItsSource() {
        let editor = makeEditor(background: Pixel(r: 30, g: 60, b: 220, a: 255))
        editor.canvas.activeLayer.buffer.fill(Pixel(r: 220, g: 40, b: 30, a: 255), in: IntRect(x: 0, y: 0, width: 32, height: 64))
        editor.addLayer()
        editor.addAdjustmentLayer(.invert, named: "Invert")
        editor.canvas.activeLayerIndex = 1
        editor.selectTool(.retouch)
        editor.retouchKind = .cloneStamp
        editor.retouchSize = 8
        editor.retouchHardness = 1
        editor.retouchSamplesAllLayers = true
        editor.setCloneSource(pt(10.5, 10.5))
        editor.beginRetouchBrush(at: pt(50.5, 50.5), pressure: 1)
        editor.endRetouchBrush()
        let shown = editor.canvas.flattened()
        #expect(shown[50, 50] == shown[10, 10])
    }
}

/// The Clone Stamp's Match Tone on a big stroke is worked out in the background and folded into the stroke's one
/// step (review O, finding 13). The size limit is lowered so a small, quick canvas takes that path.
@MainActor
@Suite(.serialized)
struct MatchToneTests {
    private func cloned(matchingTone: Bool, hardness: Double = 1) async throws -> Editor {
        // Dark on the left, light on the right; the stroke copies dark into the light half, straight across.
        let editor = makeEditor(width: 200, height: 120, background: Pixel(r: 220, g: 220, b: 220, a: 255))
        editor.canvas.activeLayer.buffer.fill(Pixel(r: 40, g: 40, b: 40, a: 255), in: IntRect(x: 0, y: 0, width: 80, height: 120))
        // Faint stripes, so a matched copy still differs from what was there: texture stays, tone changes.
        for x in stride(from: 0, to: 80, by: 4) {
            editor.canvas.activeLayer.buffer.fill(Pixel(r: 50, g: 50, b: 50, a: 255), in: IntRect(x: x, y: 0, width: 2, height: 120))
        }
        editor.selectTool(.retouch)
        editor.retouchKind = .cloneStamp
        editor.retouchSize = 40
        editor.retouchHardness = hardness
        editor.cloneMatchesTone = matchingTone
        editor.setCloneSource(pt(40.5, 40.5))
        editor.beginRetouchBrush(at: pt(150.5, 40.5), pressure: 1)
        editor.continueRetouchBrush(to: pt(150.5, 80.5), constrain: false, pressure: 1)
        editor.endRetouchBrush()
        for _ in 0..<1000 where editor.isMatchingTone { try await Task.sleep(for: .milliseconds(5)) }
        #expect(!editor.isMatchingTone)
        return editor
    }

    @Test func aBigStrokesToneIsMatchedAsPartOfItsStep() async throws {
        let limit = Editor.backgroundToneArea
        Editor.backgroundToneArea = 100
        defer { Editor.backgroundToneArea = limit }
        let plain = try await cloned(matchingTone: false)
        let matched = try await cloned(matchingTone: true)
        #expect(matched.stepNames == ["Clone Stamp"])
        // The copied dark is brought toward the light surroundings.
        #expect(matched.canvas.activeLayer.buffer[150, 60].r > plain.canvas.activeLayer.buffer[150, 60].r + 20)
        matched.undo()
        #expect(matched.canvas.activeLayer.buffer[150, 60] == Pixel(r: 220, g: 220, b: 220, a: 255))
    }

    /// A soft brush blends in too: its rim is still mostly the original, so the difference is measured from what was
    /// there before and what was copied (Leah's test, 2026-10-14).
    @Test(arguments: [false, true])
    func aSoftStrokeBlendsIn(inBackground: Bool) async throws {
        let limit = Editor.backgroundToneArea
        if inBackground { Editor.backgroundToneArea = 100 }
        defer { Editor.backgroundToneArea = limit }
        let matched = try await cloned(matchingTone: true, hardness: 0.5)
        let buffer = matched.canvas.activeLayer.buffer
        // The copied dark is brought all the way to the light surroundings, middle and edge alike.
        for y in stride(from: 30, through: 90, by: 10) {
            for x in stride(from: 132, through: 168, by: 6) {
                #expect(abs(Int(buffer[x, y].r) - 220) <= 12, "\(x), \(y): \(buffer[x, y].r)")
            }
        }
    }

    @Test func aDabIsMatchedAtOnce() async throws {
        let matched = try await cloned(matchingTone: true)
        #expect(matched.stepNames == ["Clone Stamp"])
        #expect(matched.canvas.activeLayer.buffer[150, 60].r > 100)
    }

    /// Review R, finding 1: an edit started while the tone is still being worked out lands it first, so undoing that
    /// edit, or cancelling an effect, keeps the tone.
    @Test func aNewEditLandsThePendingToneFirst() async throws {
        let limit = Editor.backgroundToneArea
        Editor.backgroundToneArea = 100
        defer { Editor.backgroundToneArea = limit }
        let landed = try await cloned(matchingTone: true).canvas.activeLayer.buffer.contentHash()

        func pending() -> Editor {
            let editor = makeEditor(width: 200, height: 120, background: Pixel(r: 220, g: 220, b: 220, a: 255))
            editor.canvas.activeLayer.buffer.fill(Pixel(r: 40, g: 40, b: 40, a: 255), in: IntRect(x: 0, y: 0, width: 80, height: 120))
            for x in stride(from: 0, to: 80, by: 4) {
                editor.canvas.activeLayer.buffer.fill(Pixel(r: 50, g: 50, b: 50, a: 255), in: IntRect(x: x, y: 0, width: 2, height: 120))
            }
            editor.selectTool(.retouch)
            editor.retouchKind = .cloneStamp
            editor.retouchSize = 40
            editor.retouchHardness = 1
            editor.cloneMatchesTone = true
            editor.setCloneSource(pt(40.5, 40.5))
            editor.beginRetouchBrush(at: pt(150.5, 40.5), pressure: 1)
            editor.continueRetouchBrush(to: pt(150.5, 80.5), constrain: false, pressure: 1)
            editor.endRetouchBrush()
            #expect(editor.isMatchingTone)
            return editor
        }

        // Another stroke across it, then undone.
        let stroked = pending()
        stroked.selectTool(.pencil)
        stroked.stroke([pt(120.5, 60.5), pt(180.5, 60.5)])
        #expect(!stroked.isMatchingTone)
        stroked.undo()
        #expect(stroked.canvas.activeLayer.buffer.contentHash() == landed)
        #expect(stroked.stepNames == ["Clone Stamp"])

        // An effect's bar opened and cancelled.
        let cancelled = pending()
        cancelled.beginEffect(.gaussianBlur)
        cancelled.cancelEffect()
        #expect(cancelled.canvas.activeLayer.buffer.contentHash() == landed)
        #expect(cancelled.stepNames == ["Clone Stamp"])
    }
}

/// What the earlier tests left untested (review P, finding 12).
@MainActor
struct RedactBrushRulesTests {
    private func redactEditor() -> Editor {
        let editor = makeEditor()
        editor.selectTool(.redactBrush)
        editor.redactBrushSize = 8
        editor.redactTreatment = .solidFill
        return editor
    }

    private func redactStroke(_ editor: Editor, at y: Double) {
        editor.beginRedactStroke(at: pt(10.5, y), secondary: false)
        editor.continueRedactStroke(to: pt(50.5, y), constrain: false)
        editor.endRedactStroke()
    }

    /// A redaction, so the after-redaction offers apply, as for Batch Redact (FR-9.6).
    @Test func aStrokeCountsAsARedaction() {
        let editor = redactEditor()
        redactStroke(editor, at: 20.5)
        #expect(editor.redactedSinceSave)
    }

    @Test func aLockedLayerWithPixelsUnderTheStrokeBlocksItByName() {
        let editor = redactEditor()
        editor.setLayerLocked(true, at: 0)
        let before = editor.imageHash
        redactStroke(editor, at: 20.5)
        #expect(editor.imageHash == before)
        #expect(editor.redactionMessage?.contains(editor.canvas.layers[0].name) == true)
    }

    @Test func aLockedLayerWithNothingUnderTheStrokeDoesntBlockIt() {
        let editor = redactEditor()
        editor.addLayer()
        editor.selectTool(.pencil)
        editor.stroke([pt(10.5, 50.5), pt(50.5, 50.5)])
        editor.setLayerLocked(true, at: 1)
        editor.selectTool(.redactBrush)
        let before = editor.imageHash
        redactStroke(editor, at: 20.5)
        #expect(editor.redactionMessage == nil)
        #expect(editor.imageHash != before)
    }
}

@MainActor
struct RetouchRulesTests {
    /// Esc while Remove fills: nothing changes and no step is added, even once the fill finishes.
    @Test func escDuringAFillChangesNothing() async throws {
        let editor = makeEditor()
        editor.selectTool(.pencil)
        editor.stroke([pt(30.5, 10.5), pt(30.5, 50.5)])
        editor.selectTool(.retouch)
        editor.retouchKind = .remove
        editor.retouchSize = 8
        let before = (editor.imageHash, editor.stepNames)
        editor.beginRetouchStroke(at: pt(30.5, 30.5))
        editor.endRetouchStroke()
        editor.cancelFill()
        try await Task.sleep(for: .milliseconds(300))
        #expect(editor.imageHash == before.0)
        #expect(editor.stepNames == before.1)
    }

    /// With Aligned off, every stroke starts again from the source.
    @Test func cloneWithAlignedOffStartsEachStrokeFromTheSource() {
        let editor = makeEditor(width: 80, height: 40)
        let red = Pixel(r: 220, g: 30, b: 30, a: 255), blue = Pixel(r: 30, g: 30, b: 220, a: 255)
        editor.canvas.activeLayer.buffer.fill(red, in: IntRect(x: 0, y: 0, width: 10, height: 40))
        editor.canvas.activeLayer.buffer.fill(blue, in: IntRect(x: 10, y: 0, width: 10, height: 40))
        editor.selectTool(.retouch)
        editor.retouchKind = .cloneStamp
        editor.retouchSize = 4
        editor.retouchHardness = 1
        editor.cloneAligned = false
        editor.setCloneSource(pt(5.5, 20.5))
        for x in [40.5, 60.5] {
            editor.beginRetouchBrush(at: pt(x, 20.5), pressure: 1)
            editor.endRetouchBrush()
        }
        // Both dabs copied the red at the source; aligned, the second would have copied from 20 px right of it.
        #expect(editor.canvas.activeLayer.buffer[40, 20] == red)
        #expect(editor.canvas.activeLayer.buffer[60, 20] == red)
    }
}
