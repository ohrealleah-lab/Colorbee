# Review X: groups and masks in the model
Reviewed at commit: 079bee95d41f6a27c4bf7bc6590288dc28d764b8
Checked:
- `Layer.swift`, `Canvas+Groups.swift`: ancestors, `isShown`/`isLocked`, `memberRange`, `tree(of:)`, `keepGroupsTogether` (cycles, torn groups)
- `Canvas.swift`: `clipped`, `clipBaseIndex`, `clippedLayers`, `composite` (Pass Through and Normal groups, stand-ins), `thumbnail`, `patch`, `flattened`, `copy`, `restore`, `LayerStackState.Record`
- `Compositing.swift`, `AdjustmentCompositing.swift` (`mixed`, `blendAtop`), `BlendMode.swift` `reveal`
- `LayerActions.swift`: Merge Adjustment (plain and clipped), Duplicate, Delete, Merge Down, Merge Visible, Flatten, Move
- `LayerActions+Groups.swift`: Group, Ungroup, Merge Group, `moveLayers`/`plannedMove`, `movingLayers`; `LayersPanel.drop(onto:)`
- `LayerActions+Several.swift`: Merge Layers, Delete Layers, Duplicate Layers, Move Layers (dragging)
- `LayerActions+Masks.swift`: Add, Delete, Apply (`bakeMask`), Turn On/Off, Invert (exact both ways)
- `LayerActions+Text.swift` with groups, masks and clipped layers; `Canvas.fitText`
- `LayerAlign.swift` (units, groups) and `Editor` Align/Distribute
- `History.swift`: `willModify`, text changes, `swapPixels`, `undoOnLayer` and `candidate`, `heldLayerBuffers`, spills and `load`
- `History+Snapshots.swift`, `HistorySnapshot.swift`: masks, groups and text in snapshots
- `ProjectFile.swift`: groups (`at`), masks, text, beta 7's `activeLayerIndex`, parked pages
- Masks in `ImageActions`, `Warp`, `Decorations`, `SelectionActions`, `AutoRedact+Apply`; the app's `paintLayer` callers, `refusedBecauseLocked`, `saveSnapshot`

No problem found: Pass Through and Normal groups in `composite` against `thumbnail` and `patch`; Invert Mask (exact twice over); snapshots with groups, masks and text; groups' places and beta 7's active layer in projects; crops, resizes, turns and canvas growth carrying masks along; mask buffers never being written out while on the canvas.

## 1. Merge Adjustment crashes when a clipped pixel layer sits under the clipped adjustment
- **Severity:** Critical (crash)
- **Confidence:** High
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/LayerActions.swift:59-62` (`applyClippedAdjustment`), `LayerActions.swift:78-80` (`canApplyAdjustment`)
- **What happens:** Colorbee quits.
- **How to trigger it:** Layer A (pixels), above it pixel layer B set to "Only the layer below", above that adjustment C set to "Only the layer below". C active, Merge Adjustment.
- **Why:** Since stage 28b a clip chain can hold pixel layers. `clipBaseIndex` walks past B to A, so the command is enabled. Then `merged = layers[(baseIndex + 1)...index]` holds B, and `clip.adjustment!` is nil for B.
- **Steps for Leah** (it crashes; close other documents first):
  1. Open `TestImages/Magic Wand Practice.png`.
  2. Layer ▸ New Layer; paint a stroke on it; turn on "Only the layer below" for it.
  3. Add any adjustment layer (Invert) above it and turn on "Only the layer below" for it too.
  4. Layer ▸ Merge Adjustment. Expected: the look stays. Actual: Colorbee quits.
- **Test that would catch it:** Core test: base, clipped pixel layer, clipped adjustment; `applyAdjustment` doesn't crash and the flattened image is unchanged (or the command is unavailable).

## 2. Undo on Active Layer doesn't put a mask back, so undoing Delete Mask or Apply Mask loses the mask
- **Severity:** Critical (lost work, undo not exact)
- **Confidence:** High
- **Where:** `History.swift:555-569` (`undoOnLayer`); `Canvas.swift:638-643` (`Record.matches` compares `mask` and `maskEnabled`)
- **What happens:** "Undo Delete Layer Mask" (or "Undo Apply Layer Mask", "Undo Turn Off Layer Mask") on the active layer removes that step from history but copies back only name, visibility, opacity, blend, locks, adjustment, clip, Pass Through, text and buffer. It never copies back `mask` or `maskEnabled`. After Delete Mask, the mask stays gone and the only step that held it is gone too. After Apply Mask, the layer's unmasked pixels come back with no mask, so what the mask hid shows again. "Undo Add Layer Mask" leaves the mask in place.
- **How to trigger it:** Paint on a mask, Delete Mask, Edit ▸ Undo on Active Layer.
- **Why:** `candidate` returns these steps (the record differs only in `mask`), but `undoOnLayer` doesn't set `target.mask = record.mask` or `target.maskEnabled = record.maskEnabled`.
- **Steps for Leah:**
  1. Open `TestImages/Magic Wand Practice.png`, Layer ▸ Duplicate Layer.
  2. Layer ▸ Layer Mask ▸ Add Mask; paint black over half the picture on the mask.
  3. Layer ▸ Layer Mask ▸ Delete.
  4. Edit ▸ Undo on Active Layer. Expected: the mask comes back. Actual: no mask, and History says "Undo Delete Layer Mask". ⌘Z doesn't bring it back either.
- **Test that would catch it:** Core test: mask with strokes, `deleteMask`, `undoOnLayer`; the layer has a mask with the same pixels. The same for `applyMask` (buffer and mask both back) and `setMaskEnabled(false)`.

## 3. Merge Down and Merge Layers throw away a pixel layer set to "Only the layer below"
- **Severity:** High (wrong result; work lost unless undone)
- **Confidence:** High
- **Where:** `LayerActions.swift:166-195` (`mergeDown`, `canMergeDown`); `LayerActions+Several.swift:56-67` (`mergedIndices`), `:20-21`; `Canvas.swift:210-214` (`clipped`)
- **What happens:** Merge Down on a clipped pixel layer deletes it and leaves the layer below unchanged, so what it painted disappears. Merge Layers with a clipped pixel layer chosen but not its base does the same, and the clipped layer even becomes the holder, so its own pixels are replaced by the others'.
- **How to trigger it:** Pixel layer B clipped onto pixel layer A; B active; Merge Down. Or choose B and a layer above it (not A); Merge Layers.
- **Why:** Both call `canvas.composite(...)`, whose `clipped(stack)` drops any layer with `clipsToLayerBelow` whose base exists in the canvas, even when the base isn't in the stack being merged. So B is never drawn. (`mergedIndices` skips clipped adjustments whose base isn't chosen, but not clipped pixel layers.) Merge Down should blend B atop A (`Compositing.blendAtop`). The same happens when the lower layer is itself clipped to the same base.
- **Steps for Leah:**
  1. Open `TestImages/Magic Wand Practice.png`, Layer ▸ New Layer, paint a bright stroke across the picture.
  2. Turn on "Only the layer below" for it.
  3. Layer ▸ Merge Down. Expected: the stroke stays where it showed. Actual: it's gone.
- **Test that would catch it:** Core tests: the flattened image is the same before and after `mergeDown` on a clipped pixel layer, and after `mergeLayers` of a clipped pixel layer with a layer above it.

## 4. Align and Distribute move a text layer's pixels but not its words, so the text jumps back later
- **Severity:** High (wrong picture after a crop or canvas size change)
- **Confidence:** High
- **Where:** `LayerAlign.swift:111-131` (`move` replaces `layer.buffer` only); `Editor.swift:4737-4740` (`canAlignChosenLayers` allows text layers); `TextLayer.swift:90-107` (`fitText` redraws from `text`)
- **What happens:** A text layer's pixels move, but its `text` keeps the old position. The next Crop, Canvas Size, Resize or Drop Shadow/Border growth redraws the words from `text`, so they jump back where they were before the Align. Edit Text opens the box at the old place too. FR-6.3's rule that a text layer's pixels are always its words drawn is broken.
- **How to trigger it:** Text layer near the left; Layer ▸ Align ▸ Right; then crop.
- **Why:** `LayerAlign.move` sets `layer.buffer = moved` and leaves `layer.text` alone. Text layers are pixel layers, so `units` takes them. FRD §23 2026-10-31 item 6 greys out pixel-changing commands on a text layer, but Align isn't checked.
- **Steps for Leah:**
  1. Open `TestImages/Magic Wand Practice.png`. Text tool, Editable on, type "Hello" near the top left, place it.
  2. Layer ▸ Align ▸ Right. The words move to the right edge.
  3. Select a rectangle covering almost the whole picture, Image ▸ Crop to Selection. Expected: "Hello" stays at the right. Actual: it jumps back to the left.
- **Test that would catch it:** Core test: text layer, align it, crop; the layer's pixels equal its `text` drawn, at the aligned place. (Or the fix moves `text` with the offset.)

## 5. Merge Adjustment on a clipped adjustment ignores its mask
- **Severity:** High (the picture changes)
- **Confidence:** High
- **Where:** `LayerActions.swift:61`
- **What happens:** A clipped adjustment with a mask is merged into its layer everywhere, not just where the mask shows.
- **Why:** `Compositing.adjust(base.buffer, by: clip.adjustment!, opacity:, mode:)` passes no `mask: clip.activeMask`. The composite path in `Canvas.clipped` does pass it.
- **Steps for Leah:**
  1. Open `TestImages/Magic Wand Practice.png`, Layer ▸ Duplicate Layer.
  2. Add an Invert adjustment layer, turn on "Only the layer below", Layer Mask ▸ Add Mask, paint black over the left half of the mask.
  3. Merge Adjustment. Expected: only the right half stays inverted. Actual: the whole layer is inverted.
- **Test that would catch it:** Core test: masked clipped adjustment; the flattened image is unchanged by `applyAdjustment`.

## 6. Saving while a moved piece floats on a mask saves the hole but not the piece
- **Severity:** Medium (lost work in the saved file)
- **Confidence:** High
- **Where:** `Canvas.swift:562-572` (`layerBuffersAsSaved` walks only `layers`); `SelectionActions.swift:110` (lifts from `paintLayer`); `Editor.swift:5504-5509` (`saveSnapshot` doesn't place a floating piece)
- **What happens:** A piece lifted from a mask has `layerID` = the mask's id. Saves and autosaves stamp floating pieces only into `canvas.layers`, so the project gets the mask with the lifted area cleared (the layer shows there) and without the piece. Quitting autosaves, so the piece is lost on reopening. Revert Layer's "last saved" uses the same buffers.
- **Steps for Leah:**
  1. Open `TestImages/Magic Wand Practice.png`, Duplicate Layer, Layer Mask ▸ Add Mask, paint a black blob on the mask.
  2. Rectangle-select the blob and drag it a little with the Move tool; don't click elsewhere.
  3. Save As a project, close, reopen. Expected: the blob where you moved it. Actual: no blob; the mask is clear where it was.
- **Test that would catch it:** Core test: lift from a mask, encode, decode; the mask equals the mask after placing.

## 7. A text layer's words survive a redaction in its mask's name, in the saved project
- **Severity:** Medium (a secret left in the file)
- **Confidence:** High that the words are written; the name isn't shown anywhere in the app
- **Where:** `LayerActions+Masks.swift:23` (mask named `"\(layer.name) Mask"`); `History.swift:73-79` renames only the layer; written in `ProjectFile.swift:195` and snapshots' `maskName`
- **What happens:** A text layer is named after its first line, so its mask is named "<first line> Mask". Redacting the layer renames it "Text" but not the mask. The words stay as plain text in the project's manifest and in History Snapshots.
- **Steps for Leah:** can't be seen in the app; a core test is the check.
- **Test that would catch it:** Core test: text layer "secret", add a mask, redact the layer; no layer or mask name in the canvas or the encoded project contains "secret".

## 8. Align and Distribute move a layer but not its mask
- **Severity:** Medium (the look changes)
- **Confidence:** Medium (no FRD decision says which is meant; Photoshop moves a mask with its layer by default)
- **Where:** `LayerAlign.swift:111-131`; `LayerAlign.units` (`:50-57`)
- **What happens:** The layer's pixels move; its mask stays, so the mask now hides a different part, and a group's mask stays put while its layers move.
- **Steps for Leah:**
  1. Open `TestImages/Magic Wand Practice.png`, Layer ▸ New Layer, paint a blob on the left.
  2. Add Mask, paint black over the left half of the blob.
  3. Layer ▸ Align ▸ Right. Expected: the half-hidden blob moves to the right edge. Actual: the whole blob shows at the right edge.
- **Test that would catch it:** Core test: masked layer, align; the flattened image is the old one shifted.

## 9. Dragging a layer up onto a layer that has "Only the layer below" layers puts it between them
- **Severity:** Medium (the look changes)
- **Confidence:** High
- **Where:** `LayerActions+Groups.swift:121-124` (`.above` inserts at `at + 1`); `LayersPanel.swift:231-234`
- **What happens:** Dragging a layer up onto base A puts it just above A, under A's clipped layers. They then clip onto the dragged layer, or show as ordinary layers if it's an adjustment. Dragging down onto a clipped layer's row (`.below`) splits the chain the same way.
- **Why:** `plannedMove` uses the target's own index. It doesn't skip past `clippedLayers(onLayerAt:)` for `.above`, or down to the base for `.below` on a clipped layer.
- **Steps for Leah:**
  1. Open `TestImages/Magic Wand Practice.png`, Duplicate Layer, add a Hue/Saturation adjustment with Saturation at minimum, turn on "Only the layer below" (the copy turns gray).
  2. Layer ▸ New Layer, paint a red blob, then drag it down to the bottom of the stack.
  3. Drag the red layer up and let go over the gray copy's row. Expected: it lands above the adjustment; the blob stays red. Actual: it lands under the adjustment, and the blob turns gray.
- **Test that would catch it:** Core test: `moveLayers(_, to: .above(base))` leaves every clipped layer on its base.

## 10. Deleting every word of a text layer leaves its "Only the layer below" layers behind
- **Severity:** Low
- **Confidence:** High
- **Where:** `LayerActions+Text.swift:23-29`
- **What happens:** The text layer goes (§23 2026-10-31 item 3), but the layers clipped onto it stay and clip onto the layer below it instead. Delete Layer deletes them with it (Leah, 2026-10-13).
- **Why:** It calls `canvas.removeLayer(at: index)` rather than removing `deletedRange(ofLayerAt:)`.
- **Steps for Leah:** Place editable text, add a layer with "Only the layer below" on it, double-click the text, delete every word, click away. The clipped layer is still there, now changing the layer below.
- **Test that would catch it:** Core test: `setText` with empty text removes the clipped layers too.

## 11. Masks that only history holds are never written to disk
- **Severity:** Low (memory)
- **Confidence:** High
- **Where:** `History.swift:636-651` (`heldLayerBuffers` reads `record.buffer` only)
- **What happens:** After deleting a masked layer, deleting a mask or applying one, the mask's buffer stays in memory and isn't counted in the byte budget.
- **Test that would catch it:** Core test: paint a full mask, delete it, set a small budget; `byteCount` counts the mask or it's spilled.
