import AppKit
import ColorbeeCore
import Darwin
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Colorbee

/// The overnight monkey test (stage 32; Leah, 2026-10-29): thousands of random, legal edits to small documents, with
/// the rules checked after each. `make monkey` runs it for 8 hours (`MINUTES=30 make monkey` for less) and writes a
/// report of every different rule broken, each shrunk to the fewest steps that still break it. It keeps going after a
/// failure, up to 20 different ones (Q32.2), and checks no speeds (Q32.3).
@MainActor
struct MonkeyTests {
    nonisolated private static let environment = ProcessInfo.processInfo.environment
    /// Set only by `make monkey`, so `make test` skips the long run.
    nonisolated private static let minutes = environment["COLORBEE_MONKEY_MINUTES"].flatMap(Double.init)
    static let stepsPerEpisode = 60
    static let maxFailures = 20
    /// How many Auto-Redacts ran and how many found something to cover, for the report: rules about it need it to.
    static var autoRedacts = (tried: 0, found: 0)

    /// A few short episodes on every `make test`, so the monkey itself keeps working and today's code breaks no rule.
    @Test func aShortRunBreaksNoRules() async {
        var hygiene = MonkeyHygiene.take()
        for seed in [UInt64(1), 2, 3, 4, 11] {
            var episode = MonkeyEpisode.random(seed: seed)
            MonkeyLeaks.forget()
            do {
                try await episode.explore(count: 40)
            } catch {
                let (shrunk, failure) = await Self.shrink(episode, failure: error)
                Issue.record(Comment(rawValue: Self.describe(shrunk, failure: failure)))
            }
            for failure in await Self.afterEpisode(seed: seed, hygiene: &hygiene) {
                Issue.record(Comment(rawValue: "**\(failure.rule).** \(failure.detail) Seed \(seed)."))
            }
        }
    }

    /// The checks made between episodes (monkey hardening): nothing kept in memory, no preference or settings file touched, no
    /// network, and one file, made from the seed, opened.
    static func afterEpisode(seed: UInt64, hygiene: inout MonkeyHygiene) async -> [MonkeyFailure] {
        var failures: [MonkeyFailure] = []
        if let leak = await MonkeyLeaks.check() { failures.append(leak) }
        if let dirty = hygiene.check() { failures.append(dirty) }
        if let file = MonkeyFiles.check(seed: seed) { failures.append(file) }
        return failures
    }

    /// Every kind of file, whole and damaged each way, opens to a sound document or is refused; whole ones open as they
    /// should and save as projects keeping their look and colors.
    @Test func everyKindOfFileOpensOrIsRefused() {
        var tried = Set<String>()
        var seed: UInt64 = 0
        while tried.count < MonkeyFiles.Kind.allCases.count * MonkeyFiles.Damage.allCases.count, seed < 4000 {
            var random = MonkeyRandom(seed: seed &* 2_654_435_761 &+ 3)
            tried.insert("\(random.pick(MonkeyFiles.Kind.allCases)) \(random.pick(MonkeyFiles.Damage.allCases))")
            if let failure = MonkeyFiles.check(seed: seed) { Issue.record(Comment(rawValue: "**\(failure.rule).** \(failure.detail) Seed \(seed).")) }
            seed += 1
        }
        #expect(tried.count == MonkeyFiles.Kind.allCases.count * MonkeyFiles.Damage.allCases.count)
    }

    /// A PNG claiming a huge size is refused before anything is decoded, and a whole one opens.
    @Test func aSizeBombIsRefused() throws {
        var random = MonkeyRandom(seed: 1)
        let (data, _) = try MonkeyFiles.file(.png, random: &random)
        let good = ImageDocument()
        try good.read(from: data, ofType: UTType.png.identifier)
        #expect(good.editor?.canvas.size == IntSize(width: 40, height: 24))
        var bytes = [UInt8](data)
        bytes.replaceSubrange(16..<24, with: [0x00, 0x01, 0x86, 0xA0, 0x00, 0x01, 0x86, 0xA0])
        #expect(throws: (any Error).self) { try ImageDocument().read(from: Data(bytes), ofType: UTType.png.identifier) }
    }

    /// Saving through the document, and a save that fails, keep the file sound.
    @Test func savingThroughTheDocumentKeepsThePicture() async {
        let editor = MonkeyEpisode.random(seed: 3).makeEditor()
        #expect(MonkeyFiles.checkDocumentSave(editor, seed: 3) == nil)
        editor.addLayer()
        editor.paste(PixelBuffer(width: 8, height: 8, fill: Pixel(r: 0, g: 200, b: 90)), at: IntPoint(x: 3, y: 3))
        editor.placePendingObjects()
        #expect(MonkeyFiles.checkDocumentSave(editor, seed: 3) == nil)
    }

    /// Many layers, deep groups and a big picture work and undo back (smaller here than in a monkey run).
    @Test func theLimitsHold() async {
        if let failure = await MonkeyLimits.check(layers: 40, depth: 6, big: 600) {
            Issue.record(Comment(rawValue: "**\(failure.rule).** \(failure.detail)"))
        }
    }

    /// A change that isn't marked edited, or a mark with nothing changed, is caught (R9).
    @Test func anUnmarkedChangeIsCaught() {
        let editor = MonkeyEpisode.random(seed: 1).makeEditor()
        let before = MonkeyRules.pageHistories(of: editor)
        // Straight into the core, past `recordingChanges`, as a command that forgot to mark the document would.
        ImageActions.setTransparentBackground(!editor.canvas.hasTransparentBackground, canvas: editor.canvas, history: editor.history)
        #expect(throws: MonkeyFailure.self) { try MonkeyRules.checkMarked(editor, before: before, marked: false) }
        let now = MonkeyRules.pageHistories(of: editor)
        #expect(throws: MonkeyFailure.self) { try MonkeyRules.checkMarked(editor, before: now, marked: true) }
        #expect(throws: Never.self) { try MonkeyRules.checkMarked(editor, before: before, marked: true) }
    }

    /// A locked layer that changes, or paint on locked transparent pixels, is caught (R10).
    @Test func aChangedLockedLayerIsCaught() {
        let editor = MonkeyEpisode.random(seed: 1).makeEditor()
        editor.addLayer()
        editor.setLayerLocked(true, at: editor.activeLayerIndex)
        var before = MonkeyRules.lockedLayers(of: editor.canvas)
        editor.canvas.activeLayer.buffer[2, 2] = Pixel(r: 9, g: 9, b: 9)
        #expect(throws: MonkeyFailure.self) { try MonkeyRules.checkLocks(before: before, canvas: editor.canvas, step: .addLayer) }
        editor.setLayerLocked(false, at: editor.activeLayerIndex)
        editor.setLayerLocksTransparency(true, at: editor.activeLayerIndex)
        before = MonkeyRules.lockedLayers(of: editor.canvas)
        editor.canvas.activeLayer.buffer[5, 5] = Pixel(r: 9, g: 9, b: 9)
        #expect(throws: MonkeyFailure.self) { try MonkeyRules.checkLocks(before: before, canvas: editor.canvas, step: .addLayer) }
    }

    /// A chosen layer or floating piece pointing at a layer that's gone is caught (R12).
    @Test func aStaleReferenceIsCaught() {
        let editor = MonkeyEpisode.random(seed: 1).makeEditor()
        #expect(throws: Never.self) { try MonkeyRules.checkReferences(editor) }
        editor.otherChosenLayerIDs = [LayerID()]
        #expect(throws: MonkeyFailure.self) { try MonkeyRules.checkReferences(editor) }
    }

    /// An episode's editor kept after it ends is caught (S6).
    @Test func aKeptEditorIsCaught() async {
        MonkeyLeaks.forget()
        MonkeyLeaks.resetCounts()
        let editor = MonkeyEpisode.random(seed: 1).makeEditor()
        MonkeyLeaks.note(editor)
        #expect(await MonkeyLeaks.check(limit: 1) != nil)
        #expect(editor.canvas.layers.count == 1)
        MonkeyLeaks.forget()
        MonkeyLeaks.resetCounts()
    }

    /// An internet socket the process opens is counted (S4). It's never connected, so nothing is sent.
    @Test func anOpenSocketIsCounted() {
        let before = MonkeyHygiene.openDescriptors().sockets
        let socketFile = socket(AF_INET, SOCK_STREAM, 0)
        #expect(socketFile >= 0)
        #expect(MonkeyHygiene.openDescriptors().sockets == before + 1)
        close(socketFile)
        #expect(MonkeyHygiene.openDescriptors().sockets == before)
    }

    /// A pen's event carries its pressure to the canvas, and odd orders of events break no rule.
    /// Before/After coming on mid-drag ends the drag (§23, 2026-11-22; found by the monkey, seed 6031): the canvas edge
    /// doesn't resize, and a stroke keeps only what was drawn before.
    @Test func beforeAfterEndsADragUnderWay() async throws {
        let point = { (x: Double, y: Double) in Point2D(x: x, y: y) }
        let editor = MonkeyEpisode.random(seed: 1).makeEditor()
        let size = editor.canvasSize
        let corner = point(Double(size.width), Double(size.height))
        #expect(MonkeyCanvas.view(for: editor).play([.key(.canvas("canvas.pencil"), shift: false, command: false), .down(corner, right: false, shift: false, option: false, clicks: 1, pressure: nil),
                                                     .drag(point(corner.x + 6, corner.y + 6), right: false, shift: false, pressure: nil),
                                                     .menu(.beforeAfter),
                                                     .drag(point(corner.x + 12, corner.y + 12), right: false, shift: false, pressure: nil),
                                                     .up(point(corner.x + 12, corner.y + 12), right: false)]) == nil)
        // `play` turns Before/After off again at the end, and fails if the picture changed while it showed.
        #expect(editor.canvasSize == size && editor.canvasResizePreview == nil && editor.history.undoCount == 0)
        MonkeyCanvas.reset()

        let painted = MonkeyEpisode.random(seed: 1).makeEditor()
        #expect(MonkeyCanvas.view(for: painted).play([.key(.canvas("canvas.pencil"), shift: false, command: false),
                                                      .down(point(2.5, 3.5), right: false, shift: false, option: false, clicks: 1, pressure: nil),
                                                      .drag(point(6.5, 3.5), right: false, shift: false, pressure: nil), .menu(.beforeAfter),
                                                      .drag(point(14.5, 3.5), right: false, shift: false, pressure: nil), .up(point(14.5, 3.5), right: false)]) == nil)
        let layer = painted.canvas.layers[0].buffer
        #expect(painted.history.undoCount == 1 && layer[4, 3] == painted.color1 && layer[12, 3] != painted.color1)
        MonkeyCanvas.reset()
    }

    @Test func rawInputReachesTheCanvas() async throws {
        let event = try #require(MonkeyCanvas.penEvent(.leftMouseDown, at: NSPoint(x: 30, y: 40), flags: [], clicks: 1, pressure: 0.25))
        #expect(event.subtype == .tabletPoint && abs(event.pressure - 0.25) < 0.01)
        let point = { (x: Double, y: Double) in Point2D(x: x, y: y) }
        // A stroke really lands where it was aimed: on the picture, as one step.
        let editor = MonkeyEpisode.random(seed: 1).makeEditor()
        #expect(MonkeyCanvas.view(for: editor).play([.key(.canvas("canvas.pencil"), shift: false, command: false),
                                                     .down(point(3.5, 3.5), right: false, shift: false, option: false, clicks: 1, pressure: nil),
                                                     .drag(point(12.5, 3.5), right: false, shift: false, pressure: nil), .up(point(12.5, 3.5), right: false)]) == nil)
        #expect(editor.tool == .pencil && editor.history.undoCount == 1)
        #expect(editor.canvas.layers[0].buffer[8, 3] == editor.color1)
        MonkeyCanvas.reset()
        let scripts: [[InputEvent]] = [
            [.key(.canvas("canvas.brush"), shift: false, command: false), .down(point(5, 5), right: false, shift: false, option: false, clicks: 1, pressure: 0.3),
             .drag(point(20, 9), right: false, shift: false, pressure: 0.9), .up(point(20, 9), right: false)],
            // A lost release, a second button mid-drag, ⌘Z mid-drag.
            [.key(.canvas("canvas.pencil"), shift: false, command: false), .down(point(2, 2), right: false, shift: false, option: false, clicks: 1, pressure: nil),
             .drag(point(9, 9), right: false, shift: false, pressure: nil), .down(point(12, 3), right: false, shift: false, option: false, clicks: 1, pressure: nil),
             .down(point(4, 4), right: true, shift: false, option: false, clicks: 1, pressure: nil), .menu(.undo), .drag(point(14, 14), right: false, shift: true, pressure: nil)],
            // A selection with Esc and Space mid-drag, then Before/After on and a drag.
            [.key(.canvas("canvas.rectangleSelect"), shift: false, command: false), .down(point(3, 3), right: false, shift: false, option: false, clicks: 1, pressure: nil),
             .key(.space, shift: false, command: false), .drag(point(15, 12), right: false, shift: false, pressure: nil), .key(.escape, shift: false, command: false),
             .up(point(15, 12), right: false), .menu(.beforeAfter), .down(point(6, 6), right: false, shift: false, option: false, clicks: 1, pressure: nil),
             .drag(point(19, 4), right: false, shift: false, pressure: nil)],
            // A text box dragged out and typed into, then a double-click.
            [.key(.canvas("canvas.text"), shift: false, command: false), .down(point(4, 4), right: false, shift: false, option: false, clicks: 1, pressure: nil),
             .drag(point(30, 20), right: false, shift: false, pressure: nil), .up(point(30, 20), right: false), .typing("API key"),
             .down(point(2, 30), right: false, shift: false, option: false, clicks: 2, pressure: nil), .up(point(2, 30), right: false)],
        ]
        for script in scripts {
            var steps = [MonkeyStep.input(script), .addLayer, .undo, .redo].makeIterator()
            try await MonkeyEpisode.drive(MonkeyEpisode.random(seed: 1).makeEditor(), finishing: true) { _ in steps.next() }
        }
    }

    /// Each new kind of step, once, breaks no rule.
    @Test func everyNewStepMeetsTheRules() async throws {
        var random = MonkeyRandom(seed: 9)
        let p = { (x: Double, y: Double) in Point2D(x: x, y: y) }
        let red = Pixel(r: 220, g: 30, b: 30)
        let script: [MonkeyStep] = [
            .fill(at: p(3, 3), color: red), .text("API key", at: p(4, 4), editable: true, color: red, leavesOpen: false), .select(from: p(2, 2), to: p(20, 16)),
            .solidFill(color: red, cancels: false), .autoContrast(asLayer: false), .autoContrast(asLayer: true), .removeRedEye,
            .modifySelection(.feather, radius: 5, ending: .ok), .modifySelection(.expand, radius: 2, ending: .okAtOnce), .modifySelection(.smooth, radius: 20, ending: .cancel),
            .rangeSelect(.colorRange, values: EffectKind.colorRange.parameters.map(\.defaultValue), points: [p(5, 5), p(10, 10)], apply: true),
            .rangeSelect(.luminanceRange, values: EffectKind.luminanceRange.parameters.map(\.defaultValue), points: [], apply: true),
            .rangeSelect(.graduatedSelection, values: EffectKind.graduatedSelection.parameters.map(\.defaultValue), points: [p(0, 0), p(20, 20)], apply: false),
            .selectWith(ellipse: true, from: p(1, 1), to: p(15, 15), shift: false, option: false), .selectWith(ellipse: false, from: p(5, 5), to: p(25, 18), shift: true, option: false),
            .moveSelection(dx: 4, dy: 2), .dragHandle(.bottomRight, by: p(6, 4)), .copy(merged: true, cut: false), .addLayer, .pasteInPlace, .deselect,
            .copy(merged: false, cut: true), .pasteInPlace, .several([0, 1, 2], command: .align(.left)), .several([], command: .distribute(.horizontally)),
            .several([0, 1], command: .group), .passThrough, .renameLayer("API key"), .isolate(0), .isolate(0), .takeSnapshot, .fill(at: p(1, 1), color: .white),
            .renameSnapshot(0, "Before"), .goToSnapshot(0), .toolOptions(MonkeyOptions.random(&random)), .zoom(8),
            .text("curved", at: p(2, 10), editable: true, color: red, leavesOpen: false), .canvasProperties(width: 50, height: 30, anchor: .bottomRight),
            .subject(.removeBackground, click: nil, take: true), .subject(.select, click: p(10, 10), take: false), .editText(layer: 0, ""),
        ]
        var steps = script.makeIterator()
        try await MonkeyEpisode.drive(MonkeyEpisode.random(seed: 1).makeEditor(), finishing: true) { _ in steps.next() }
    }

    /// The end still compares exact pictures after another page was shown (review AH, finding 2). Here a change History
    /// never recorded, on the first page's background, stands in for an undo that gives back the wrong picture.
    @Test func aWrongPictureIsCaughtAfterShowingAnotherPage() async {
        var steps: IndexingIterator<[MonkeyStep]> = [.fill(at: Point2D(x: 2, y: 2), color: Pixel(r: 255, g: 0, b: 0)), .addLayer,
                                                     .newPage, .showPage(0)].makeIterator()
        do {
            try await MonkeyEpisode.drive(MonkeyEpisode.random(seed: 1).makeEditor(), finishing: true) { editor in
                if let step = steps.next() { return step }
                editor.canvas.layers[0].buffer[1, 1] = Pixel(r: 0, g: 200, b: 0)
                return nil
            }
            Issue.record("The monkey missed a picture that undo didn't give back.")
        } catch {
            #expect(error.failure.rule == "Undoing everything didn't give back each picture")
            #expect(error.atEnd)
        }
    }

    /// A layer the redaction didn't reach is caught, whichever way it covers.
    @Test func aRedactionThatMissesALayerIsCaught() throws {
        let size = IntSize(width: 20, height: 20)
        let canvas = Canvas(size: size, colorSpace: Canvas.defaultColorSpace, background: .white)
        let area = try #require(SelectionMask.rectangle(IntRect(x: 2, y: 2, width: 12, height: 12), clippedTo: canvas.bounds))
        let black = Pixel(r: 0, g: 0, b: 0)
        #expect(throws: MonkeyFailure.self) { try MonkeyRules.checkCovered(canvas, area: area, effect: .solidFill(black), before: [:]) }

        canvas.layers[0].buffer[3, 3] = Pixel(r: 255, g: 0, b: 0)
        let before = MonkeyRules.pixels(of: canvas)
        #expect(throws: MonkeyFailure.self) { try MonkeyRules.checkCovered(canvas, area: area, effect: .gaussianBlur(radius: 6), before: before) }
        #expect(throws: MonkeyFailure.self) { try MonkeyRules.checkCovered(canvas, area: area, effect: .pixelate(cellSize: 6), before: before) }

        for y in 2..<14 { for x in 2..<14 { canvas.layers[0].buffer[x, y] = black } }
        try MonkeyRules.checkCovered(canvas, area: area, effect: .solidFill(black), before: [:])
        try MonkeyRules.checkCovered(canvas, area: area, effect: .pixelate(cellSize: 6), before: before)
    }

    /// One flat layer has nothing a blur or pixelate could change, so it isn't a miss.
    @Test func aFlatLayerNeedsNoChange() throws {
        let canvas = Canvas(size: IntSize(width: 20, height: 20), colorSpace: Canvas.defaultColorSpace, background: .white)
        let area = try #require(SelectionMask.rectangle(IntRect(x: 2, y: 2, width: 12, height: 12), clippedTo: canvas.bounds))
        try MonkeyRules.checkCovered(canvas, area: area, effect: .gaussianBlur(radius: 6), before: MonkeyRules.pixels(of: canvas))
    }

    /// Text left open and then closed with nothing placed is caught.
    @Test func openTextThatVanishesIsCaught() {
        let episode = MonkeyEpisode.random(seed: 1), editor = episode.makeEditor()
        editor.textIsEditable = true
        editor.selectTool(.text)
        editor.beginText(at: Point2D(x: 4, y: 4), wrapWidth: nil)
        editor.updatePendingText("Hi")
        let open = MonkeyRules.certainToLand(editor), revision = editor.history.revision
        #expect(open == "text")
        editor.pendingText = nil
        #expect(throws: MonkeyFailure.self) {
            try MonkeyRules.checkLanded(editor, open: open, step: .addLayer, page: editor.page, revisionBefore: revision)
        }
    }

    /// Objects left open meet the next step, and Undo with text open still lines up with what happened.
    @Test func objectsLeftOpenMeetTheNextStep() async throws {
        let red = Pixel(r: 255, g: 0, b: 0)
        let shape = MonkeyStep.shape(kind: .rectangle, from: Point2D(x: 4, y: 4), to: Point2D(x: 20, y: 20), outline: .solid, fill: nil, secondary: false, color: red, leavesOpen: true)
        let text = MonkeyStep.text("Hi", at: Point2D(x: 4, y: 4), editable: true, color: red, leavesOpen: true)
        for script in [[.addLayer, .opacity(0.5), .undo, shape], [shape, .addLayer, .undo, .redo], [shape, .undo, .redo], [text, .undo, .redo, .undo], [text, .redo, .undo], [text, .newPage, .showPage(0), .undo],
                       [text, .saveInBackground, .addLayer, .undo, .undo], [shape, .forgetHistory], [text, .saveAndReopen]] as [[MonkeyStep]] {
            var steps = script.makeIterator()
            try await MonkeyEpisode.drive(MonkeyEpisode.random(seed: 1).makeEditor(), finishing: true) { _ in steps.next() }
        }
    }

    /// The dialog's Apply makes a step without becoming "last used" while the monkey runs.
    @Test func adjustPhotoAppliedByTheMonkeyIsNotLastUsed() {
        let last = PhotoSettingsStore.shared.last
        LastPhotoSettings.$frozenForTests.withValue(true) {
            let editor = ScreenMatchesExportTests.picture()
            editor.beginEffect(.adjustPhoto)
            editor.photoEdit = PhotoEdit(adjustments: PhotoAdjustments([.exposure: 40]))
            editor.applyEffect()
            #expect(editor.history.undoCount == 1)
        }
        #expect(PhotoSettingsStore.shared.last == last)
    }

    /// Random whole settings use every part, and a sample of them shows on screen as it exports.
    @Test func randomAdjustPhotoSettingsShowAsExported() throws {
        var random = MonkeyRandom(seed: 7)
        let edits = (0..<200).map { _ in MonkeyPhoto.edit(&random) }
        #expect(edits.contains { $0.mixer != nil } && edits.contains { $0.grading != nil } && edits.contains { $0.pointColors != nil })
        #expect(edits.contains { $0.toneCurve != nil } && edits.contains { $0.detail != nil } && edits.contains { $0.effects != nil })
        #expect(edits.contains { $0.filter != nil } && edits.contains { $0.adjustments.values.count > 3 })
        for edit in edits.prefix(25) { try MonkeyRules.checkShowsAsExported(edit) }
    }

    /// A control the screen draws wrong is caught: here one Point Color shows on screen that the export doesn't have.
    @Test func aControlMissingFromTheExportIsCaught() {
        let swatch = PointColors.Swatch(color: Pixel(r: 40, g: 80, b: 210), hue: 30, saturation: 40)
        let shown = ScreenMatchesExportTests.picture(), exported = ScreenMatchesExportTests.picture()
        shown.addAdjustmentLayer(.photo(PhotoEdit(adjustments: PhotoAdjustments([.exposure: 20]), pointColors: PointColors([swatch]))), named: "A")
        exported.addAdjustmentLayer(.photo(PhotoEdit(adjustments: PhotoAdjustments([.exposure: 20]))), named: "A")
        #expect(throws: MonkeyFailure.self) {
            try MonkeyRules.compare(screen: ScreenMatchesExportTests.screen(shown.canvas), export: exported.canvas.flattened())
        }
    }

    /// An export that doesn't hold the picture is caught: here the picture changes after the copy for exporting was taken.
    @Test(arguments: [false, true])
    func anExportThatDiffersIsCaught(pdf: Bool) {
        let editor = ScreenMatchesExportTests.picture()
        editor.newPage()
        editor.showPage(at: 0)
        let snapshot = editor.saveSnapshot()
        #expect(throws: Never.self) { pdf ? try MonkeyRules.checkPDF(snapshot, editor) : try MonkeyRules.checkPNG(snapshot, editor.canvas) }
        editor.canvas.layers[0].buffer.fill(Pixel(r: 255, g: 0, b: 0), in: IntRect(x: 0, y: 0, width: 40, height: 40))
        #expect(throws: MonkeyFailure.self) { pdf ? try MonkeyRules.checkPDF(snapshot, editor) : try MonkeyRules.checkPNG(snapshot, editor.canvas) }
    }

    /// Every effect's dialog, closed each way in turn, breaks no rule.
    @Test func everyEffectDialogMeetsTheRules() async throws {
        let kinds: [EffectKind] = [.gaussianBlur, .pixelate, .sharpen, .hueSaturation, .levels, .curves, .sepia, .posterize, .addNoise,
                                   .motionBlur, .emboss, .vignette, .dropShadow, .border, .spotlight, .straighten, .perspective, .crop]
        let corners = [Point2D(x: 10, y: 8), Point2D(x: 90, y: 6), Point2D(x: 95, y: 70), Point2D(x: 6, y: 66)]
        for (index, kind) in kinds.enumerated() {
            let ending = EffectEnding.allCases[index % EffectEnding.allCases.count]
            let values = kind.parameters.map { $0.options == nil ? ($0.range.lowerBound + $0.range.upperBound) / 2 : 0 }
            var steps = [MonkeyStep.fill(at: Point2D(x: 20, y: 20), color: Pixel(r: 200, g: 60, b: 40)), .newPage, .showPage(0),
                         .effectDialog(kind, values: values, select: kind == .spotlight ? IntRect(x: 10, y: 10, width: 30, height: 20) : nil,
                                       box: IntRect(x: 5, y: 5, width: 50, height: 40), corners: corners, ending: ending),
                         .undo, .redo].makeIterator()
            do {
                try await MonkeyEpisode.drive(MonkeyEpisode.random(seed: 5).makeEditor(), finishing: true) { _ in steps.next() }
            } catch {
                Issue.record(Comment(rawValue: "\(kind.title), then \(ending.rawValue): \(error.failure.rule). \(error.failure.detail) (step \(error.steps))"))
            }
        }
    }

    @Test func someEpisodesCrossAnUndoTile() {
        let episode = MonkeyEpisode.random(seed: 11)
        #expect(episode.large && episode.width > TileGrid.tileSize && episode.height > TileGrid.tileSize)
        #expect(!MonkeyEpisode.random(seed: 1).large)
    }

    @Test(.enabled(if: minutes != nil, "Run with make monkey")) func overnight() async {
        let started = Date()
        let deadline = started.addingTimeInterval((Self.minutes ?? 0) * 60)
        let baseSeed = Self.environment["COLORBEE_MONKEY_SEED"].flatMap(UInt64.init) ?? UInt64(started.timeIntervalSince1970)
        let episodeLimit = Self.environment["COLORBEE_MONKEY_EPISODES"].flatMap(Int.init) ?? .max
        let folder = URL(fileURLWithPath: Self.environment["COLORBEE_MONKEY_REPORT"] ?? FileManager.default.temporaryDirectory.path)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let inProgress = folder.appendingPathComponent("Monkey In Progress.txt")
        var found: [(key: String, count: Int, text: String)] = []
        var episodes = 0, steps = 0
        // A finding between episodes (monkey hardening): nothing to shrink, just the seed it came after.
        func note(_ failure: MonkeyFailure, seed: UInt64?) {
            if let index = found.firstIndex(where: { $0.key == failure.rule }) {
                found[index].count += 1
                return
            }
            let replay = seed.map { "\n\nIt came after episode seed \($0). Replay that with: make monkey SEED=\($0) EPISODES=1\n" } ?? "\n"
            found.append((failure.rule, 1, "**\(failure.rule).** \(failure.detail)\(replay)"))
            Self.writeReport(found: found, episodes: episodes, steps: steps, started: started, finished: nil, to: folder)
        }
        var hygiene = MonkeyHygiene.take()
        // Far more than everyday use, once (S7). The huge picture is bigger in a Release run (`make monkey-release`).
        try? "The limits check (many layers, deep groups, a huge picture) was running.\n".write(to: inProgress, atomically: true, encoding: .utf8)
        let big = Self.environment["COLORBEE_MONKEY_BIG"].flatMap(Int.init) ?? 3000
        if let failure = await MonkeyLimits.check(layers: 200, depth: 12, big: big) { note(failure, seed: nil) }

        while Date() < deadline, episodes < episodeLimit, found.count < Self.maxFailures {
            let seed = baseSeed &+ UInt64(episodes)
            // If Colorbee itself crashes, this says which episode to replay.
            try? "Episode seed \(seed) was running. Replay it with: make monkey SEED=\(seed) EPISODES=1\n".write(to: inProgress, atomically: true, encoding: .utf8)
            var episode = MonkeyEpisode.random(seed: seed)
            MonkeyLeaks.forget()
            do {
                try await episode.explore(count: Self.stepsPerEpisode)
            } catch {
                // At the end, the last step says little about the cause: one cause there is one finding.
                let key = error.failure.rule + " · " + (error.atEnd ? "at the end" : episode.steps.prefix(error.steps).last?.kind ?? "")
                if let index = found.firstIndex(where: { $0.key == key }) {
                    found[index].count += 1
                } else {
                    // Checked before shrinking, whose replays make editors of their own.
                    let leak = await MonkeyLeaks.check()
                    MonkeyLeaks.forget()
                    let (shrunk, failure) = await Self.shrink(episode, failure: error)
                    found.append((key, 1, Self.describe(shrunk, failure: failure)))
                    Self.writeReport(found: found, episodes: episodes + 1, steps: steps + episode.steps.count, started: started, finished: nil, to: folder)
                    if let leak { note(leak, seed: seed) }
                }
            }
            for failure in await Self.afterEpisode(seed: seed, hygiene: &hygiene) { note(failure, seed: seed) }
            episodes += 1
            steps += episode.steps.count
            // Lets the app's own queued work run between episodes.
            try? await Task.sleep(for: .milliseconds(2))
        }
        try? FileManager.default.removeItem(at: inProgress)
        let report = Self.writeReport(found: found, episodes: episodes, steps: steps, started: started, finished: Date(), to: folder)
        print("Monkey report: \(report.path)")
    }

    /// The fewest steps that still break the same rule: everything after the failure goes, then each step that isn't
    /// needed, one at a time from the end.
    static func shrink(_ episode: MonkeyEpisode, failure: MonkeyFailureAt, tries: Int = 150) async -> (MonkeyEpisode, MonkeyFailureAt) {
        var best = episode
        best.steps = Array(episode.steps.prefix(failure.steps))
        var bestFailure = failure
        var index = best.steps.count - 1
        var attempts = 0
        while index >= 0, attempts < tries {
            var candidate = best
            candidate.steps.remove(at: index)
            attempts += 1
            do {
                try await candidate.run()
            } catch where error.failure.rule == failure.failure.rule {
                best = candidate
                best.steps = Array(candidate.steps.prefix(error.steps))
                bestFailure = error
            } catch {}
            index = min(index - 1, best.steps.count - 1)
        }
        return (best, bestFailure)
    }

    static func describe(_ episode: MonkeyEpisode, failure: MonkeyFailureAt) -> String {
        var text = "**\(failure.failure.rule).** \(failure.failure.detail)\n\n"
        text += "Seed \(episode.seed). \(episode.start)\n\n"
        for (index, step) in episode.steps.enumerated() {
            text += "\(index + 1). \(step)\n"
        }
        if failure.atEnd {
            text += "\(episode.steps.count + 1). (At the end: save and reopen, then undo and redo everything.)\n"
        }
        return text
    }

    @discardableResult
    static func writeReport(found: [(key: String, count: Int, text: String)], episodes: Int, steps: Int, started: Date, finished: Date?,
                            to folder: URL) -> URL {
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd HHmm"
        let file = folder.appendingPathComponent("Monkey Report \(stamp.string(from: started)).md")
        let time = DateFormatter()
        time.dateStyle = .medium
        time.timeStyle = .short
        var text = "# Colorbee monkey test\n\n"
        text += "Started \(time.string(from: started))"
        if let finished {
            let minutes = Int(finished.timeIntervalSince(started) / 60)
            text += ", finished \(time.string(from: finished)) (\(minutes / 60) h \(minutes % 60) min)"
        } else {
            text += ", still running"
        }
        text += ". \(episodes) pictures (one in sixteen large), \(steps) steps. Auto-Redact found something to cover \(autoRedacts.found) of \(autoRedacts.tried) times. \(MonkeyLeaks.strays) of the last \(MonkeyLeaks.checked) episodes left their editor held in memory (about one in ten is the test run itself; most would be a leak, and is reported).\n\n"
        if found.isEmpty {
            text += "No rule was broken.\n"
        } else {
            text += "\(found.count) different rule\(found.count == 1 ? "" : "s") broken. Each is shrunk to the fewest steps that still break it.\n"
            for (number, failure) in found.enumerated() {
                text += "\n## \(number + 1). Seen \(failure.count) time\(failure.count == 1 ? "" : "s")\n\n\(failure.text)"
            }
        }
        try? text.write(to: file, atomically: true, encoding: .utf8)
        return file
    }
}
