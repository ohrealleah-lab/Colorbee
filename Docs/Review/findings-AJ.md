# Review AJ: selections and layers (stage 34b)
Reviewed at commit: f3f5623c02034eea0153b11f095fee7dd4d3ae4a
Checked: `SelectionActions.cancelFloating` and `placeFloating`/`paste`/`beginMove`/`transformSelection`; `History`
(`undoStepLeaves`, `lastStepLeftFloating`, `record` merging, `undo`, `forgetRedo`, spill and failed reads); `Canvas.isHidden`,
`insertLayerAboveActive`, `indexAboveActiveLayer`, `keepGroupsTogether`; `LayerActions+Text.addText`; `Editor+Selection`
(`pressEscape`, `cancelFloating`, drags, `recordingChanges`); `Editor+Undo` (to compare with Esc); `Editor+Layers`
(`activeLayerTakesEdits`, `activeLayerIsHidden`, `refusedBecauseLocked`, `layerSetting`, `makeActive`); every caller of
`activeLayerTakesEdits` and `refusedBecauseLocked` (painting, fill, gradient, shapes, text, badges, retouching, red-eye,
subjects, Adjust Photo, selection moves, paste, Cut, Delete, Revert Layer); `Editor+Effects` (`beginBatchRedact`,
`beginEffect`, `renderEffectPreview`), `applySolidFill`, `AutoRedact.layersWithPixels`; `CanvasView` (key handling and
the "not allowed" pointer); `DocumentWindow` (menu checks, `pixelCommands`, Cut); `MainMenu`; the monkey's `.escape`
step, `UndoTracker.note` and the shape rule; the new core and app tests; FRD §23 rows of 2026-11-20 and the help pages.

## 1. Batch Redact ▸ Blur… or Pixelate… on a piece dragged fully off the picture blurs the whole picture on every layer
- **Severity:** High (wrong result the user sees; the very case "needs a selection" is meant to stop)
- **Confidence:** High
- **Where:** `Sources/Colorbee/Editor+Effects.swift:35-36` (`beginBatchRedact`), `:45` (`placeFloatingKeepingOutline`),
  `:73-78` and `:86-87`; `Sources/Colorbee/Editor+Effects.swift:664-668` (`renderEffectPreview`);
  `Packages/ColorbeeCore/Sources/ColorbeeCore/AutoRedact+Apply.swift:11-12`. Compare `Editor+AdjustPhoto.swift:427-431`.
- **What happens:** the new guard checks `hasSelection` before the floating piece is placed. `beginEffect` then places
  it with `placeFloatingKeepingOutline`, which keeps only the part of the outline on the canvas. A piece lying wholly in
  the grey area leaves `.none`. With no marquee, `layersWithPixels(in: nil)` returns every layer with pixels and
  `effectRegions` is nil, so the preview, and Apply, blur or pixelate the whole of every layer. Solid Fill doesn't have
  this: it checks `canvas.selection.marquee != nil` again after placing.
- **How to trigger it:** test image `TestImages/Auto-Redact Practice.png`.
  1. Open `TestImages/Auto-Redact Practice.png`.
  2. View ▸ Zoom Out twice, so there's grey around the picture.
  3. With Rectangle Select, drag a small box on the picture.
  4. Edit ▸ Copy.
  5. Edit ▸ Paste.
  6. Drag the pasted piece out into the grey area until no part of it touches the picture.
  7. Redact ▸ Blur….
  - Expected: nothing is blurred; it's refused as with nothing selected.
  - Actual: the whole picture blurs in the preview, and Apply blurs every layer as one "Blur" step. Redact ▸ Pixelate…
    does the same.
- **Why:** `guard hasSelection else { return onRefused() }` runs first, then
  `placeFloatingKeepingOutline()` sets `canvas.selection = .none` when the clipped outline is empty. After that
  `effectRegions = canvas.selection.marquee?.hardened().connectedRegions()` is nil, and the preview takes the
  `Effects.apply(effect, to: layer, selection: nil, edit: edit)` branch for each layer in `effectLayers`.
- **Test that would catch it:** app test: paste a 5×5 piece, move it to (-20, -20) on a 40×30 canvas,
  `beginBatchRedact(.gaussianBlur)`; expect `activeEffect == nil` and the image hash unchanged.

## 2. Editable text placed on a layer inside a hidden group disappears as soon as it's placed
- **Severity:** Medium (the words vanish; nothing is lost, but they're hidden somewhere she didn't expect)
- **Confidence:** High
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/Canvas.swift:130-131` (`insertLayerAboveActive` copies
  `activeLayer.groupID`); `LayerActions+Text.swift:12-15`; `Sources/Colorbee/CanvasView.swift:556`;
  `Sources/Colorbee/Editor+Text.swift:12`, `:222`; FRD FR-8.2 "Hidden" (stage 34b).
- **What happens:** stage 34b says Editable text still works on a hidden layer, and the pointer no longer shows "not
  allowed" for it (§23 Stage 34b built, choice 1). On a plain hidden layer that's true, since the new text layer has
  its own eye on. But when the active layer is inside a hidden group, the text layer joins that group, so it's hidden
  too. While typing, the words are drawn on top (`pendingTextMakesLayer`), so they look fine until Esc places them.
  Then they vanish, and the Layers panel shows them inside the hidden group. Double-clicking a hidden text layer's
  thumbnail to change it does the same: the words show while typing and vanish once placed.
- **How to trigger it:** test image `TestImages/Several Layers/Align Practice.colorproj`.
  1. Open `TestImages/Several Layers/Align Practice.colorproj`.
  2. Layer ▸ Group Layers.
  3. In the Layers panel, click the layer inside the new group, so it's the active layer.
  4. Click the group's eye, so the group is hidden.
  5. Choose the Text tool and turn on Editable in the palette bar.
  6. Click on the picture and type "Hello".
  7. Press Esc.
  - Expected: "Hello" stays on the picture, on a text layer of its own.
  - Actual: "Hello" disappears; its layer is inside the hidden group.
- **Why:** `layer.groupID = activeLayer.groupID` in `insertLayerAboveActive`, and `Canvas.isHidden` counts a hidden
  ancestor, so the new text layer is hidden from the moment it's made. Nothing in `addText` or `commitPendingText`
  checks for that.
- **Test that would catch it:** core test: group the active layer, hide the group, make the inner layer active,
  `addText`; expect the text layer to be shown (`canvas.isShown(textLayer)`), or the add to be refused, whichever
  Leah picks.

## 3. The monkey's Esc check can't tell whether Esc stopped at the right step, and checks nothing after a paste on a paste
- **Severity:** Medium (no direct harm, but it's the overnight safety net for Esc being an exact undo, and it would pass
  if Esc went one step too far or stopped one step early)
- **Confidence:** High
- **Where:** `Tests/ColorbeeTests/Monkey/MonkeyEpisode.swift:420-436` (the `.escape` case); `:443-445` (a merged placing
  sets the mark to nil).
- **What happens:** the check compares the picture after Esc with the tracker's mark at whatever undo count Esc ended
  on (`line[count]`). Every mark on the line is a real place in history, so stopping early or overshooting still
  matches the mark for that count, and the selection check passes too, since that mark's `before` is whatever floated
  there. It never checks that `count` is the undo count from just before the lift or paste, or that nothing with the
  piece's id still floats. Also, a paste on top of an unplaced paste merges the placing into the older step, so
  `line[before.undoCount]` is set to nil. That's exactly the mark Esc returns to, so after a paste on a paste the
  check compares nothing and only the "nothing to redo" part runs. Repeated pastes are common in monkey runs.
- **How to trigger it:** not visible by hand. To prove it, change `SelectionActions.cancelFloating` to do one extra
  `history.undo` after the loop; a monkey run would still pass this rule.
- **Why:** `if line.indices.contains(count), let want = line[count] { if want.layers != now.layers … }`; nothing records
  the undo count at the moment the piece first floated.
- **Test that would catch it:** let the tracker remember, per floating id, the undo count just before the step that
  first left it floating (from `before.undoCount` when `now.after` starts floating with a new id), and have `.escape`
  require `count` to equal it. Check it with a deliberately broken `cancelFloating` (one extra undo), which should fail.

## 4. Revert Layer still changes a hidden layer's pixels
- **Severity:** Low
- **Confidence:** High
- **Where:** `Sources/Colorbee/Editor+Canvas.swift:41-45` (`canRevertLayer`), `:50-66`;
  `Sources/Colorbee/DocumentWindow.swift:619-629` (`pixelCommands` doesn't list it).
- **What happens:** FR-8.2 (stage 34b) says a hidden layer refuses pixel changes as a locked one does. Revert Layer
  refuses a locked layer (`!canvas.isLocked(layer)`) but not a hidden one. It stays enabled and throws away the
  hidden layer's changes since the save, which she can't see happen.
- **How to trigger it:** test image `TestImages/Several Layers/Opacity Test.colorproj`.
  1. Open `TestImages/Several Layers/Opacity Test.colorproj`.
  2. Choose the Brush and draw a stroke on the picture.
  3. Layer ▸ Hide Layer.
  4. Open the Layer menu.
  - Expected: Revert Layer is greyed out, as on a locked layer.
  - Actual: Revert Layer is enabled; choosing it, then Layer ▸ Show Layer, shows the stroke gone.
- **Why:** `canRevertLayer` checks `layer.isPixelLayer && !canvas.isLocked(layer) && …`, with no `canvas.isHidden`.
- **Test that would catch it:** app test: hide the active layer; expect `canRevertLayer == false`.

## 5. After Esc, a picture that's back to how it was opened can still show as edited
- **Severity:** Low (it only ever says "edited" too often, never too rarely, so no work is at risk)
- **Confidence:** High
- **Where:** `Sources/Colorbee/Editor+Selection.swift:258-261` (`cancelFloating` counts one `.undone` per step);
  `:212-224` (`recordingChanges` reports `.done` for a placing that merges into the previous step without adding one);
  `Packages/ColorbeeCore/Sources/ColorbeeCore/SelectionActions.swift:91-96`.
- **What happens:** §23 Stage 34b built, choice 5, says Esc counts as that many undos, so a picture back to how it was
  saved isn't marked as changed. That holds unless a placing was merged into one of the steps Esc takes back. The
  merge reported a `.done` but made no step, so one undo per step leaves the document one change ahead. ⌘Z has the
  same gap; Esc inherits it.
- **How to trigger it:** test image `TestImages/Magic Wand Practice.png`.
  1. Open `TestImages/Magic Wand Practice.png`.
  2. With Rectangle Select, drag a box on the picture.
  3. Press → (Right Arrow).
  4. Press → again.
  5. Press Return.
  6. Edit ▸ Undo.
  7. Press Esc.
  - Expected: the picture is as opened, and the window isn't marked as edited.
  - Actual: the picture is as opened, but the window is still marked as edited.
- **Why:** step 5 merges "Place Selection" into the second nudge and reports `.done` (count 3, two steps). Undo and Esc
  report two `.undone`, leaving 1.
- **Test that would catch it:** app test like `escOnAMovedPasteTakesItAwayWithNothingToRedo`, with two nudges, a
  `deselect()`, an `undo()`, then `cancelFloating()`; expect the change counter back at 0.

## 6. A hidden group or adjustment layer says "Show it to change it", then still refuses once shown
- **Severity:** Low
- **Confidence:** High
- **Where:** `Sources/Colorbee/Editor+Layers.swift:618-621`, then `:626-628`.
- **What happens:** the hidden check comes before the "has no pixels" check, so a hidden group (or adjustment layer) as
  the active layer gets "This layer is hidden. Show it to change it." She shows it, tries again, and gets only a beep,
  since a group has no pixels to paint.
- **How to trigger it:** test image `TestImages/Several Layers/Align Practice.colorproj`.
  1. Open `TestImages/Several Layers/Align Practice.colorproj`.
  2. Layer ▸ Group Layers (the new group is the active layer).
  3. Click the group's eye to hide it.
  4. Choose the Brush and draw on the picture.
  5. Click the group's eye to show it again.
  6. Draw on the picture again.
  - Expected: the first message tells her what would actually let her paint (choose a layer inside the group).
  - Actual: step 4 says "This layer is hidden. Show it to change it."; step 6 only beeps.
- **Why:** `if canvas.isHidden(canvas.activeLayer), !canvas.isLocked(canvas.activeLayer)` returns before
  `guard canvas.isLocked(canvas.activeLayer) || !canvas.paintLayer.isPixelLayer`.
- **Test that would catch it:** app test: a hidden group active, `stroke(...)`; expect no "hidden" notice (or the
  wording Leah picks).

---

## Also checked (no finding)

- **Esc stopping too early:** placing merges only into a step that left the same piece (`lastStepLeftFloating`), and
  every pixel path that could make a step while a piece floats (painting, fill, shapes, text, badges, retouching,
  effects, page and layer-stack commands, snapshots) places the piece first. Steps that keep it floating are Layers
  panel settings (hide, lock, opacity, rename…), which §23 choice 3 accepts. Redaction steps, Undo on Active Layer's
  steps, page changes and parked pages can't sit between a lift and Esc, since each places the piece first.
- **Esc going too far:** a piece keeps its `id` only through moves, nudges, resizes, smears, duplicates and selection
  rotate/flip/resize-skew; `paste` and a new lift start a new `id`, and `paste` places the old piece before it begins
  its step, so its `selectionBefore` is `.none`. The loop stops at the lift's marquee or the paste's empty selection.
- **History never drops steps for its byte budget;** it spills them, and `selectionAfter` stays in memory, so
  `undoStepLeaves` works on spilled steps. Only a failed spill read drops steps (`discardUndo`). Then Esc's loop
  breaks with the piece still floating and its source hole still in the layer. No pixel is lost: the piece holds them,
  and a second Esc places it.
- **Esc order:** a text box keeps Esc (`CanvasTextView.cancelOperation`); effect bars, the eyedroppers and hex picking
  take Esc before `pressEscape`; a drag under way falls through to `deselect`, which ends the drag first (§23 choice 4).
- **Hidden-layer menu checks:** Copy, Copy Merged, Select All, the wand, Crop to Selection, Trim, whole-image rotate,
  flip and resize, Auto-Redact, Batch Redact and Solid Fill stay enabled; Paste, Cut, Delete, the effects and a
  selection's rotate or resize are greyed out, as on a locked layer. Background jobs (red-eye, Remove/Spot Heal)
  re-check `activeLayerTakesEdits`, and hiding a layer is a step, so they don't land on a newly hidden layer.
- **Placed text:** with a clipped layer, the clip base, a group row or an adjustment layer active, the text goes above
  the whole clip stack or group, and the layer you were on stays active through `keepGroupsTogether` (no reorder
  happens for these inserts). Undo and redo restore the active layer.
