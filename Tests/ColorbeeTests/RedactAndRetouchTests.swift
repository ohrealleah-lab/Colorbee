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
