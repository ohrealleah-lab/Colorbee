import ColorbeeCore
import Testing
@testable import Colorbee

/// The same input always gives the same picture, and undoing everything gives back the original exactly.
@MainActor
struct RepeatabilityTests {
    /// Every brush whose look is fixed. The Airbrush spray and Oil bristles are different on each stroke on purpose
    /// (`Brush.makeStroke`'s `seed`), like a real spray can.
    static let repeatableBrushes = Brush.allCases.filter { $0 != .airbrush && $0 != .oil }

    /// One of each kind of Editor action, as a person would do them.
    func session(_ editor: Editor) {
        editor.selectTool(.pencil)
        editor.stroke(wobblyPath)
        editor.selectTool(.brush)
        for (index, brush) in Self.repeatableBrushes.enumerated() {
            editor.brush = brush
            editor.brushDiameter = 4
            editor.stroke(wobblyPath.map { pt($0.x, $0.y + Double(4 * index)) }, constrain: index.isMultiple(of: 2))
        }
        editor.selectTool(.eraser)
        editor.stroke([pt(5, 5), pt(5, 60), pt(20, 40)])

        editor.selectTool(.shape)
        editor.shapeKind = .ellipse
        editor.shapeFill = .solid
        editor.shapeDrag(from: pt(30, 30), to: pt(55, 50))
        editor.shapeKind = .arrow
        editor.shapeDrag(from: pt(5, 60), to: pt(40, 45))

        editor.selectTool(.stepBadge)
        editor.badgeDiameter = 16
        editor.badgeClick(at: pt(50, 10))

        editor.selectTool(.gradient)
        editor.addLayer()
        editor.beginGradient(at: pt(0, 0), secondary: false)
        editor.continueGradient(to: pt(64, 64))
        editor.endGradient()
        editor.setBlendMode(.multiply)

        editor.selectTool(.rectangleSelect)
        editor.selectionDrag(from: pt(8, 8), to: pt(24, 24))
        editor.selectionDrag(from: pt(16, 16), to: pt(40, 20))
        editor.apply(.rotate90Clockwise)
        editor.deselect()

        editor.selectTool(.redactBrush)
        editor.redactBrushSize = 6
        editor.beginRedactStroke(at: pt(10, 50), secondary: true)
        editor.continueRedactStroke(to: pt(30, 52), constrain: true)
        editor.endRedactStroke()

        editor.selectTool(.retouch)
        editor.retouchKind = .lighten
        editor.retouchSize = 8
        editor.beginRetouchBrush(at: pt(40, 40), pressure: 1)
        editor.continueRetouchBrush(to: pt(50, 44), constrain: false, pressure: 1)
        editor.endRetouchBrush()

        editor.selectTool(.fill)
        editor.fill(at: pt(62, 2), secondary: false)
        editor.placePendingObjects()
    }

    @Test func theSameInputGivesTheSamePicture() {
        let first = makeEditor(), second = makeEditor()
        session(first)
        session(second)
        #expect(first.imageHash == second.imageHash)
        #expect(first.stepNames == second.stepNames)
        #expect(first.imageHash != makeEditor().imageHash)
    }

    @Test func undoingAWholeSessionGivesBackTheOriginal() {
        let editor = makeEditor()
        let original = editor.imageHash
        session(editor)
        let finished = editor.imageHash
        while editor.history.canUndo { editor.undo() }
        #expect(editor.imageHash == original)
        #expect(editor.canvas.layers.count == 1)
        while editor.history.canRedo { editor.redo() }
        #expect(editor.imageHash == finished)
    }

    /// N random actions, then undo them all: the image must be exactly the original (CLAUDE.md's undo property test,
    /// here through the Editor rather than the core).
    @Test(arguments: [1, 2, 3, 4])
    func randomActionsUndoToTheOriginal(seed: UInt64) {
        var random = TestRandom(seed: seed)
        let editor = makeEditor(width: 48, height: 48)
        let original = editor.imageHash
        var finished: Int?
        for _ in 0..<30 { randomAction(editor, &random) }
        editor.placePendingObjects()
        finished = editor.imageHash

        while editor.history.canUndo { editor.undo() }
        #expect(editor.imageHash == original, "seed \(seed)")
        while editor.history.canRedo { editor.redo() }
        #expect(editor.imageHash == finished, "seed \(seed)")
    }

    func randomAction(_ editor: Editor, _ random: inout TestRandom) {
        func point() -> Point2D { pt(random.double(in: 0..<48), random.double(in: 0..<48)) }
        func path() -> [Point2D] { (0..<random.int(in: 1..<6)).map { _ in point() } }
        switch random.int(in: 0..<12) {
        case 0:
            editor.selectTool(.pencil)
            editor.stroke(path(), constrain: random.bool())
        case 1:
            editor.selectTool(.brush)
            editor.brush = Self.repeatableBrushes[random.int(in: 0..<Self.repeatableBrushes.count)]
            editor.stroke(path(), constrain: random.bool(), secondary: random.bool())
        case 2:
            editor.selectTool(.eraser)
            editor.stroke(path(), secondary: random.bool())
        case 3:
            editor.selectTool(.fill)
            editor.fill(at: point(), secondary: random.bool())
        case 4:
            editor.selectTool(.shape)
            editor.shapeKind = [.rectangle, .ellipse, .line, .arrow, .star5][random.int(in: 0..<5)]
            editor.shapeDrag(from: point(), to: point())
        case 5:
            editor.selectTool(.stepBadge)
            editor.badgeStyle = random.bool() ? .numbers : .letters
            editor.badgeClick(at: point())
        case 6:
            editor.selectTool(.rectangleSelect)
            editor.selectionDrag(from: point(), to: point(), shift: random.bool(), option: random.bool())
        case 7:
            // Drags inside a selection move it.
            if let bounds = editor.canvas.selection.bounds {
                let grab = pt(Double(bounds.minX) + 0.5, Double(bounds.minY) + 0.5)
                editor.selectionDrag(from: grab, to: point(), shift: random.bool(), option: random.bool())
            }
        case 8:
            editor.apply([Orientation.flipHorizontal, .flipVertical, .rotate180][random.int(in: 0..<3)])
        case 9:
            if editor.canvas.layers.count < 3 { editor.addLayer() } else { editor.mergeDown() }
        case 10:
            editor.selectTool(.redactBrush)
            editor.beginRedactStroke(at: point(), secondary: random.bool())
            editor.continueRedactStroke(to: point(), constrain: random.bool())
            editor.endRedactStroke()
        default:
            editor.selectTool(.retouch)
            editor.retouchKind = [RetouchKind.lighten, .darken, .blur, .smudge][random.int(in: 0..<4)]
            editor.beginRetouchBrush(at: point(), pressure: 1)
            editor.continueRetouchBrush(to: point(), constrain: false, pressure: 1)
            editor.endRetouchBrush()
        }
    }
}

/// A small fixed-seed generator, so a failing run can be repeated.
struct TestRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func int(in range: Range<Int>) -> Int {
        range.lowerBound + Int(next() % UInt64(range.count))
    }

    mutating func double(in range: Range<Double>) -> Double {
        range.lowerBound + Double(next() >> 11) / Double(1 << 53) * (range.upperBound - range.lowerBound)
    }

    mutating func bool() -> Bool {
        next() & 1 == 1
    }
}
