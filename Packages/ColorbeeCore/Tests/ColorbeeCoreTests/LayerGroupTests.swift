import Foundation
import Testing
@testable import ColorbeeCore

/// Layer groups (FR-8.7, stages 25 and 26): compositing, the commands, undo and saving.
struct LayerGroupTests {
    private let context = SelectionContext(color2: .white)
    private let red = Pixel(r: 220, g: 30, b: 30), green = Pixel(r: 30, g: 200, b: 60), blue = Pixel(r: 40, g: 60, b: 230)

    /// White paper, then Red, Green and Blue squares overlapping, each on its own layer.
    private func picture() -> (Canvas, History) {
        let canvas = Canvas(size: IntSize(width: 30, height: 20), colorSpace: Canvas.defaultColorSpace, background: .white)
        let history = History(byteBudget: .max)
        for (offset, (name, color)) in [("Red", red), ("Green", green), ("Blue", blue)].enumerated() {
            LayerActions.add(canvas: canvas, history: history, context: context)
            canvas.activeLayer.name = name
            canvas.activeLayer.buffer.fill(color, in: IntRect(x: 2 + offset * 6, y: 2, width: 12, height: 12))
        }
        return (canvas, history)
    }

    private func ids(_ canvas: Canvas, _ names: String...) -> Set<LayerID> {
        Set(canvas.layers.filter { names.contains($0.name) }.map(\.id))
    }

    private func names(_ canvas: Canvas) -> [String] { canvas.layers.map(\.name) }

    @Test func groupingKeepsTheLookAndUndoesExactly() throws {
        let (canvas, history) = picture()
        let before = canvas.flattened().contentHash()
        #expect(LayerActions.group(ids(canvas, "Red", "Green"), canvas: canvas, history: history, context: context))
        #expect(names(canvas) == ["Background", "Red", "Green", "Group 1", "Blue"])
        let group = canvas.layers[3]
        #expect(group.isGroup && canvas.activeLayer === group)
        #expect(canvas.layers[1].groupID == group.id && canvas.layers[2].groupID == group.id && canvas.layers[4].groupID == nil)
        // Pass Through at 100% looks exactly as before.
        #expect(canvas.flattened().contentHash() == before)
        history.undo(on: canvas)
        #expect(names(canvas) == ["Background", "Red", "Green", "Blue"] && canvas.layers.allSatisfy { $0.groupID == nil })
        history.redo(on: canvas)
        #expect(names(canvas) == ["Background", "Red", "Green", "Group 1", "Blue"])
    }

    @Test func layersApartAreGatheredUnderTheGroup() {
        let (canvas, history) = picture()
        #expect(LayerActions.group(ids(canvas, "Red", "Blue"), canvas: canvas, history: history, context: context))
        #expect(names(canvas) == ["Background", "Green", "Red", "Blue", "Group 1"])
    }

    @Test func hidingOrFadingAGroupDoesItToEverythingInIt() throws {
        let (canvas, history) = picture()
        LayerActions.group(ids(canvas, "Red", "Green"), canvas: canvas, history: history, context: context)
        let group = canvas.layers[3]
        group.isVisible = false
        let flat = canvas.flattened()
        #expect(flat[4, 8] == .white && flat[22, 8] == blue)
        #expect(!canvas.isShown(canvas.layers[1]))
        group.isVisible = true
        group.opacity = 0.5
        // Red alone at (4, 8): half red over white.
        let half = canvas.flattened()[4, 8]
        #expect(abs(Int(half.r) - 238) <= 1 && abs(Int(half.g) - 143) <= 1)
    }

    @Test func aNormalGroupKeepsItsAdjustmentsInside() throws {
        let (canvas, history) = picture()
        LayerActions.group(ids(canvas, "Red", "Green"), canvas: canvas, history: history, context: context)
        canvas.activeLayerIndex = 2
        LayerActions.addAdjustment(.invert, named: "Invert", canvas: canvas, history: history, context: context)
        #expect(names(canvas) == ["Background", "Red", "Green", "Invert", "Group 1", "Blue"])
        #expect(canvas.layers[3].groupID == canvas.layers[4].id)
        // Pass Through: the paper outside the squares is inverted too.
        #expect(canvas.flattened()[28, 18] == .black)
        canvas.layers[4].passesThrough = false
        // Normal: only the group's own pixels change; the paper stays white.
        let flat = canvas.flattened()
        #expect(flat[28, 18] == .white)
        #expect(flat[4, 8] == Pixel(r: 35, g: 225, b: 225))
    }

    @Test func thumbnailsAndPatchesMatchTheExport() throws {
        let (canvas, history) = picture()
        LayerActions.group(ids(canvas, "Red", "Green"), canvas: canvas, history: history, context: context)
        canvas.layers[3].passesThrough = false
        canvas.layers[3].blendMode = .multiply
        canvas.layers[3].opacity = 0.7
        let flat = canvas.flattened()
        let thumbnail = canvas.thumbnail(maxSide: 30)
        #expect(thumbnail.pixels == flat.pixels(in: flat.bounds))
        #expect(canvas.pixelAsShown(at: IntPoint(x: 10, y: 8)) == flat[10, 8])
    }

    @Test func ungroupLeavesTheLayersInTheGroupAbove() {
        let (canvas, history) = picture()
        LayerActions.group(ids(canvas, "Red", "Green"), canvas: canvas, history: history, context: context)
        LayerActions.group(ids(canvas, "Group 1", "Blue"), canvas: canvas, history: history, context: context)
        #expect(names(canvas) == ["Background", "Red", "Green", "Group 1", "Blue", "Group 2"])
        let outer = canvas.layers[5].id
        canvas.activeLayerIndex = 3
        #expect(LayerActions.ungroup(canvas: canvas, history: history, context: context))
        #expect(names(canvas) == ["Background", "Red", "Green", "Blue", "Group 2"])
        #expect(canvas.layers[1...3].allSatisfy { $0.groupID == outer })
    }

    @Test func layersMoveIntoAndOutOfGroupsButNotIntoThemselves() {
        let (canvas, history) = picture()
        LayerActions.group(ids(canvas, "Red", "Green"), canvas: canvas, history: history, context: context)
        let group = canvas.layers[3]
        let blue = ids(canvas, "Blue")
        #expect(LayerActions.moveLayers(blue, to: .into(group.id), canvas: canvas, history: history, context: context))
        #expect(names(canvas) == ["Background", "Red", "Green", "Blue", "Group 1"] && canvas.layers[3].groupID == group.id)
        #expect(LayerActions.moveLayers(blue, to: .below(canvas.layers[1].id), canvas: canvas, history: history, context: context))
        #expect(names(canvas) == ["Background", "Blue", "Red", "Green", "Group 1"] && canvas.layers[1].groupID == group.id)
        #expect(LayerActions.moveLayers(blue, to: .above(group.id), canvas: canvas, history: history, context: context))
        #expect(names(canvas) == ["Background", "Red", "Green", "Group 1", "Blue"] && canvas.layers[4].groupID == nil)
        // A group moves with everything in it, and never into itself.
        #expect(!LayerActions.canMove([group.id], to: .into(group.id), in: canvas))
        #expect(!LayerActions.canMove([group.id], to: .above(canvas.layers[1].id), in: canvas))
        #expect(LayerActions.moveLayers([group.id], to: .below(canvas.layers[0].id), canvas: canvas, history: history, context: context))
        #expect(names(canvas) == ["Red", "Green", "Group 1", "Background", "Blue"])
    }

    @Test func mergeDownOnAGroupMakesOneLayerThatLooksTheSame() {
        let (canvas, history) = picture()
        LayerActions.group(ids(canvas, "Red", "Green"), canvas: canvas, history: history, context: context)
        canvas.layers[3].passesThrough = false
        canvas.layers[3].opacity = 0.6
        let before = canvas.flattened().contentHash()
        #expect(LayerActions.mergeDown(canvas: canvas, history: history, context: context))
        #expect(names(canvas) == ["Background", "Group 1", "Blue"] && canvas.layers[1].isPixelLayer && canvas.layers[1].opacity == 0.6)
        #expect(canvas.flattened().contentHash() == before)
        history.undo(on: canvas)
        #expect(names(canvas) == ["Background", "Red", "Green", "Group 1", "Blue"])
    }

    @Test func deletingAndDuplicatingAGroupTakeEverythingInIt() {
        let (canvas, history) = picture()
        LayerActions.group(ids(canvas, "Red", "Green"), canvas: canvas, history: history, context: context)
        #expect(LayerActions.duplicate(canvas: canvas, history: history, context: context))
        #expect(names(canvas) == ["Background", "Red", "Green", "Group 1", "Red", "Green", "Group 1 copy", "Blue"])
        let copy = canvas.layers[6]
        #expect(canvas.layers[4].groupID == copy.id && canvas.layers[5].groupID == copy.id && copy.id != canvas.layers[3].id)
        #expect(canvas.layers[4].buffer !== canvas.layers[1].buffer)
        canvas.activeLayerIndex = 3
        #expect(LayerActions.delete(canvas: canvas, history: history, context: context))
        #expect(names(canvas) == ["Background", "Red", "Green", "Group 1 copy", "Blue"])
    }

    @Test func lockingAGroupLocksEverythingInIt() {
        let (canvas, history) = picture()
        LayerActions.group(ids(canvas, "Red", "Green"), canvas: canvas, history: history, context: context)
        canvas.layers[3].isLocked = true
        #expect(canvas.isLocked(canvas.layers[1]) && !canvas.isLocked(canvas.layers[4]))
        canvas.activeLayerIndex = 1
        #expect(!LayerActions.canDelete(canvas))
        canvas.layers[3].isLocked = false
        canvas.layers[3].locksTransparency = true
        #expect(canvas.locksTransparency(canvas.layers[1]))
    }

    @Test func newLayersJoinTheActiveLayersGroup() {
        let (canvas, history) = picture()
        LayerActions.group(ids(canvas, "Red", "Green"), canvas: canvas, history: history, context: context)
        canvas.activeLayerIndex = 1
        LayerActions.add(canvas: canvas, history: history, context: context)
        #expect(canvas.activeLayerIndex == 2 && canvas.activeLayer.groupID == canvas.layers[4].id)
        // Above a group's row, a new layer sits beside the group, not in it.
        canvas.activeLayerIndex = 4
        LayerActions.add(canvas: canvas, history: history, context: context)
        #expect(canvas.activeLayerIndex == 5 && canvas.activeLayer.groupID == nil)
    }

    @Test func projectsKeepGroupsAndBeta7SeesEveryLayer() throws {
        let (canvas, history) = picture()
        LayerActions.group(ids(canvas, "Red", "Green"), canvas: canvas, history: history, context: context)
        LayerActions.group(ids(canvas, "Green"), canvas: canvas, history: history, context: context)
        canvas.layers[4].passesThrough = false
        canvas.layers[4].blendMode = .screen
        canvas.layers[4].opacity = 0.8
        let data = try ProjectFile.encode(canvas)
        let reopened = try ProjectFile.decode(data)
        #expect(reopened.layers.map(\.name) == names(canvas))
        #expect(reopened.layers.map(\.isGroup) == canvas.layers.map(\.isGroup))
        #expect(reopened.layers.map(\.groupID) == canvas.layers.map(\.groupID))
        #expect(!reopened.layers[4].passesThrough && reopened.layers[4].blendMode == .screen)
        #expect(reopened.activeLayerIndex == canvas.activeLayerIndex)
        #expect(reopened.flattened().contentHash() == canvas.flattened().contentHash())
        // Beta 7 reads `layers` only: every layer, in order, no groups.
        let json = try #require(manifest(data))
        let layers = try #require(json["layers"] as? [[String: Any]])
        #expect(layers.compactMap { $0["name"] as? String } == ["Background", "Red", "Green", "Blue"])
        #expect((json["activeLayerIndex"] as? Int).map { (0..<4).contains($0) } == true)
    }

    private func manifest(_ data: Data) -> [String: Any]? {
        let start = ProjectFile.magic.count
        let length = data[start..<(start + 4)].withUnsafeBytes { Int(UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))) }
        return try? JSONSerialization.jsonObject(with: data[(start + 4)..<(start + 4 + length)]) as? [String: Any]
    }

    @Test func aTornGroupIsMendedOnOpening() {
        let (canvas, history) = picture()
        LayerActions.group(ids(canvas, "Red", "Green"), canvas: canvas, history: history, context: context)
        let group = canvas.layers[3]
        canvas.layers[4].groupID = group.id
        canvas.keepGroupsTogether()
        #expect(names(canvas) == ["Background", "Red", "Green", "Blue", "Group 1"])
    }

    @Test func snapshotsKeepGroups() throws {
        let (canvas, history) = picture()
        LayerActions.group(ids(canvas, "Red", "Green"), canvas: canvas, history: history, context: context)
        let snapshot = try history.takeSnapshot(named: "Grouped", of: canvas)
        canvas.activeLayerIndex = 3
        LayerActions.ungroup(canvas: canvas, history: history, context: context)
        try history.goToSnapshot(snapshot.id, on: canvas)
        #expect(names(canvas) == ["Background", "Red", "Green", "Group 1", "Blue"] && canvas.layers[3].isGroup)
        #expect(canvas.layers[1].groupID == canvas.layers[3].id)
    }

    @Test func alignMovesAChosenGroupAsOne() {
        let (canvas, history) = picture()
        LayerActions.group(ids(canvas, "Red", "Green"), canvas: canvas, history: history, context: context)
        let units = LayerAlign.units(ids(canvas, "Group 1"), in: canvas)
        #expect(units.count == 1 && units[0].layers.count == 2)
        let offsets = LayerAlign.offsets(aligning: units, to: .left, reference: canvas.bounds)
        #expect(offsets[canvas.layers[1].id] == IntPoint(x: -2, y: 0) && offsets[canvas.layers[2].id] == IntPoint(x: -2, y: 0))
    }
}
