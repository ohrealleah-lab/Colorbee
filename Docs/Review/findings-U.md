# Review U: history, layers and selections
Reviewed at commit: b48dadab8be9bcd4a6a6240bb3234bcfc5e830c8
Checked:
- `HistorySnapshot.swift`, `History+Snapshots.swift`: taking, going to, renaming and deleting snapshots; the scratch file; memory
- `History.swift`: `removeAll`, `record`, `swapPixels`, `undoOnLayer` and `candidate`, spilling (`heldLayerBuffers`, `evictLayers`, `evict`, `restore`, `load`) with steps holding buffers of another size; `Edit.keepLockedTransparency`
- `Canvas.swift`: `LayerStackState.size`, `restore`, `layerStackState`, `keepLockedTransparency` and `lockedEdits`, `erasedFill`, `layerBuffersAsSaved`, `composite` and `clipped` (for Stamp Visible)
- Every layer step that calls `willChangeLayers` (merges, flatten, delete, move, settings, Lift Subject, transparent background, Go to Snapshot) for a stale size: none found apart from finding 1
- Lock Transparent Pixels in every `willModify` caller (`CoveragePainter`, `Compositing.draw`, `EffectPreview.write`, `FloodFill`, `Gradient`, `Effects`, `Decorations`, `FloatingSelection`, `MatchSurroundings`, `RedEye`, `RetouchStroke`, `Subjects`, `SelectionActions.delete`, Revert Layer); effect previews and `restoreOriginals`; Symmetry's shared painter; Match Tone and Remove landing; Undo on Active Layer; `ProjectFile` and `Canvas.copy`; `LayerActions.duplicate`; the renderer's call
- `Page.swift` parking and unparking with snapshots; `PageStack.forgetHistory` and `Editor.forgetHistory`
- `Editor`: History Snapshots, Undo on Active Layer, Revert Layer, `toggleIsolation`, `selectAllLayers`, `stampVisible`, Align and Distribute, `trim`, `applyCanvasProperties`, the range bars (`refreshRangePreview`, `applyRange`, `rangeSampled`), Paste in Place
- `LayerActions.stampVisible`, `setVisibility`; `LayerAlign.swift` and `PixelBuffer.visibleBounds`; `CanvasAnchor.swift`; `ImageActions.resizeCanvas(to:anchor:)` and `crop(to:named:)`; `Trim.swift`
- `SelectionMask+Modify.swift` (the hard distance transform, the soft rectangles, padding at the canvas's edge), `ColorRange.swift`, `LuminanceRange.swift`, `GraduatedSelection.swift`
- `ClipboardImage.swift` place type, `DocumentWindow` copy and paste, `SelectionActions.selectedPixelsOrigin` against `selectedPixels`
- `HistoryPanels.swift` (snapshot rows, `SnapshotPrompt`); `DocumentWindow` menu validation for the new commands

## 1. Undo on Active Layer after Go to Snapshot leaves a layer a different size from the canvas
- **Severity:** Critical (crash, corrupted image)
- **Confidence:** High that the sizes disagree; Medium on whether it crashes or only draws garbage (it depends on how far the reads run past the smaller buffer)
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/History.swift:505-517` (`undoOnLayer`), `History.swift:535-558` (`candidate`); `History+Snapshots.swift:114-124`
- **What happens:** On a one-layer picture, Go to Snapshot after a crop (or resize, or 90° rotation) is offered as "Undo Go to Snapshot on Active Layer". Choosing it puts the layer's old buffer back (the cropped size) but leaves the canvas at the snapshot's size. Everything that then reads the layer with the canvas's size (the History thumbnail made straight away, the display, the next stroke, Save) reads or writes past the end of the buffer: a crash, a garbled picture, or memory corruption, and a save could write a project whose layer doesn't match its canvas. With a snapshot smaller than the image it doesn't overrun, but shows only the top-left part of the layer.
- **How to trigger it:** One-layer image. New Snapshot. Crop. Click the snapshot. Edit ▸ Undo on Active Layer.
- **Why:** Going to a snapshot is a layer step that now changes the size (`LayerStackState.size`). `candidate` stops only at `entry.geometry` or `entry.transform` steps; for a layer step it returns the step when only this layer's record changed and the stack has the same layers, which is always true with one layer. `undoOnLayer` then copies just that layer's record back (`target.buffer = record.buffer`) and never restores `state.size`, so `canvas.size` stays as the snapshot left it. With several layers it can't happen, because every layer gets a fresh buffer and the "others unchanged" check fails.
- **Steps for Leah** (it may crash, so close other documents first):
  1. Open `TestImages/Magic Wand Practice.png` (one layer, 1600 × 1100).
  2. Edit ▸ New Snapshot…, then Take Snapshot.
  3. With the Rectangle Select tool, select roughly the top-left quarter of the picture, then Image ▸ Crop to Selection.
  4. In the History panel, click "Snapshot 1". The whole picture comes back.
  5. Open the Edit menu. Expected: Undo on Active Layer is greyed out, or brings back the cropped picture at the cropped size. Actual: it reads "Undo Go to Snapshot on Active Layer"; choose it. The canvas stays 1600 × 1100 and the picture is garbled or striped, or Colorbee quits.
- **Test that would catch it:** Core test: a one-layer canvas, take a snapshot, crop it, go to the snapshot, then either `undoOnLayerActionName` is nil or, after `undoOnLayer`, every layer's `buffer.size` equals `canvas.size`. The same with a snapshot taken after the crop and gone to after undoing it.

## 2. Drop Shadow and Border paint into a locked layer's clear area whenever the canvas grows to fit them
- **Severity:** Medium (wrong result; Lock Transparent Pixels not kept)
- **Confidence:** High
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/Decorations.swift:112-131` (the growing branch); compare `Decorations.swift:97-111`
- **What happens:** On a layer with Lock Transparent Pixels, the same command gives opposite results. If the shadow or border fits inside the canvas, the lock wipes it out (nothing is added). If it reaches past the edge, so the canvas grows, the shadow or border is painted into the layer's clear pixels, inside the old canvas area too, and the lock isn't applied.
- **How to trigger it:** Lock Transparent Pixels on a cutout layer, then Drop Shadow (or Border) large enough to pass the canvas's edge.
- **Why:** The fitting branch writes through `edit.willModify(region, in: layer)`, which queues the lock fix. The growing branch is a geometry step: it builds a new buffer with `composed(x, y)` (shadow included wherever the object is clear) and calls `canvas.replaceContents`, so no `willModify` call is made and `keepLockedTransparency` never sees it. FR §23 (2026-10-28) keeps only new canvas space clear "since they move its outline"; this paints on the old area.
- **Steps for Leah:**
  1. Open `TestImages/Stage 9 Practice Cutout.png`.
  2. In the Layers panel, click the padlock and choose Lock Transparent Pixels.
  3. Effects ▸ Drop Shadow… with a small distance and blur, so the shadow stays inside the picture. Note that no shadow appears (the lock keeps the clear area clear). Cancel.
  4. Drop Shadow… again with a distance large enough that the shadow passes the canvas's edge (the canvas grows), and apply. Expected: still no shadow in the clear area. Actual: the shadow is painted into the layer's clear pixels.
- **Test that would catch it:** Core test: a canvas with a small opaque square near the right edge on a locked-transparency layer; apply a drop shadow that grows the canvas; every pixel that was clear before (in the old canvas area) is still exactly clear.

## 3. A floating selection, shape or text on a locked layer shows, saves and exports pixels that placing it removes
- **Severity:** Medium (the screen and the export disagree with the result)
- **Confidence:** High for floating selections; Medium for pending shapes and text (I didn't trace their overlay code)
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/Canvas.swift:432-450` (`layerBuffersAsSaved`), `Canvas.swift` `compositePixels` (floating span); `SelectionActions.swift:85-98` (`placeFloating`), `History.swift:89-112`, `History.swift:335`
- **What happens:**
  - While a selection floats over a locked layer's clear area, the screen shows it there, and Save and Export write it there. Deselecting (placing it) makes those pixels vanish, because placing is an edit and the lock puts the clear pixels back. A paste onto such a layer can disappear entirely when deselected.
  - Lifting a selection on such a layer and putting it back tints its soft edges with Color 2. Lifting leaves Color 2 at each pixel's old opacity (`erasedFill`, per Q23.2). Placing the floating pixels back blends them over that Color 2, and the lock then restores the old opacity, so the half-clear edge pixels keep some Color 2 in their color.
- **How to trigger it:** Lock Transparent Pixels on a cutout; select part of the object with its soft edge, drag it partly over clear area, export; then deselect.
- **Why:** The lock is applied only to written pixels (`willModify` → `keepLockedTransparency`). A floating selection isn't written until placed. Display and `layerBuffersAsSaved` composite it with `Compositing.over`, which raises opacity and covers clear pixels, and the lock isn't applied there. `stamp(onto:)` then composites over the Color 2 hole before the opacity is restored.
- **Steps for Leah:**
  1. Open `TestImages/Stage 9 Practice Cutout.png`, then Lock Transparent Pixels in the layer's padlock menu.
  2. Rectangle-select part of the object, including some of its edge, and drag it so half of it is over the clear area.
  3. File ▸ Export… as a PNG and look at the file: the moved part shows over the clear area. Back in Colorbee, press Esc or ⌘D to place it. Expected: what you saw is what you get. Actual: the part over the clear area disappears.
  4. Undo back to the start. Set Color 2 to bright red. Select a part of the object that includes its soft, half-clear edge, press → once and then ← once, then deselect. Expected: unchanged. Actual: the soft edge has a red tint.
- **Test that would catch it:** Core test: on a locked-transparency layer with a 50%-opaque pixel, lift a marquee over it, nudge it right and back, place; the pixel equals the original exactly. Another: with a floating selection over clear pixels of a locked layer, `layerBuffersAsSaved` equals the layer after `placeFloating`.

## 4. Revert Layer after Go to Snapshot can put one layer back unturned (review G, finding 4 again)
- **Severity:** Low
- **Confidence:** High
- **Where:** `Sources/Colorbee/Editor.swift:978-983` (`canRevertLayer`); `History+Snapshots.swift:95-125`
- **What happens:** A snapshot taken after a 180° rotation or a flip, then gone to after the rotation was undone and the image saved, shows the turned picture with no rotation or flip step in the history. Revert Layer is then allowed and puts the saved, unturned pixels into one layer while the others stay turned.
- **How to trigger it:** Two or more layers; Rotate 180°; New Snapshot; Undo; ⌘S; click the snapshot; Layer ▸ Revert Layer.
- **Why:** `canRevertLayer` trusts `canvas.size == saved.size && history.geometrySteps == savedGeometrySteps` to mean "same orientation as the save". Going to a snapshot changes orientation through a layer step, which `geometrySteps` doesn't list.
- **Steps for Leah:**
  1. Open `TestImages/Several Layers/Align Practice.colorproj`.
  2. Image ▸ Rotate ▸ 180°. Edit ▸ New Snapshot…, Take Snapshot.
  3. ⌘Z (the picture turns back), then ⌘S.
  4. Click the snapshot in the History panel (the picture is turned again).
  5. Choose a layer with something on it, then Layer ▸ Revert Layer. Expected: greyed out, or everything matches. Actual: that layer comes back unturned and no longer lines up with the others.
- **Test that would catch it:** Editor test: as above on a two-layer canvas; `canRevertLayer` is false after going to the snapshot.

## 5. New Snapshot from the History panel quietly cancels an open effect
- **Severity:** Low
- **Confidence:** High
- **Where:** `Sources/Colorbee/HistoryPanels.swift:37-62`, `HistoryPanels.swift:112-118`; `Editor.swift:886-891` and `Editor.swift:1142`
- **What happens:** While an effect's bar is open (Gaussian Blur, Levels, Color Range and so on; not Adjust Photo, which hides the panel), the History panel's camera button and snapshot rows still work. The camera cancels the effect, throwing its settings away, and snapshots the picture without it. Clicking a snapshot cancels it too. The menu item is greyed out in the same situation (`blocksDocumentCommands`), so the two disagree.
- **How to trigger it:** History panel showing; Effects ▸ Gaussian Blur…, set a radius; click the camera.
- **Why:** `takeSnapshot` and `goToSnapshot` call `finishInteractions()`, which calls `cancelEffect()`. Unlike the menu, the panel isn't disabled while `blocksDocumentCommands` is true.
- **Steps for Leah:**
  1. Open `TestImages/Stage 9 Practice Photo.png`, and show the History panel.
  2. Effects ▸ Gaussian Blur… and drag the radius up until the preview is clearly blurred.
  3. Click the camera button by "Snapshots", then Take Snapshot. Expected: the button does nothing until Apply or Cancel (like Edit ▸ New Snapshot…, which is greyed out). Actual: the blur bar closes, the blur is gone, and the snapshot is of the sharp picture.
- **Test that would catch it:** Editor test: with an effect active, taking a snapshot either is refused or leaves `activeEffect` set.

## 6. Option-click on an eye shows every layer instead of isolating, after the isolation was undone
- **Severity:** Low
- **Confidence:** High
- **Where:** `Sources/Colorbee/Editor.swift:4501-4524` (`isolation`, `toggleIsolation`)
- **What happens:** Isolating a layer, undoing it with ⌘Z, changing any layer's eye, then Option-clicking the same layer's eye again shows every layer ("Show Layers") instead of showing only that layer.
- **How to trigger it:** As in the steps.
- **Why:** The `isolation` record is never cleared by Undo, Redo, page changes or layer deletion. After the undo, the layers no longer match `isolation.before` because of the eye click, so the code takes the "visibility changed while isolated, so show everything" path (Q22.4), although nothing is isolated any more.
- **Steps for Leah:**
  1. Open `TestImages/Several Layers/Opacity Test.colorproj`.
  2. Option-click the eye of "Red": only Red shows.
  3. ⌘Z: everything shows again.
  4. Click the eye of "Green" to hide it.
  5. Option-click the eye of "Red" again. Expected: only Red shows. Actual: every layer shows, Green included, and the History panel says "Show Layers".
- **Test that would catch it:** Editor test of the same sequence: after step 5 only Red is visible.

## 7. Taking or going to a snapshot holds the whole image's compressed copy in memory at once
- **Severity:** Low
- **Confidence:** Medium (how much depends on how well the picture compresses)
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/History+Snapshots.swift:68-79`, `History+Snapshots.swift:98-113`
- **What happens:** New Snapshot compresses every band of every layer into one array before writing any of it, and Go to Snapshot reads every band back into one array while also allocating every new layer. Photos barely compress with LZ4, so on a big multi-layer photo the peak is about one more copy of the whole image: for example, about 1 GB for five 8000 × 8000 photo layers, on top of the image and its history. That's memory the history budget doesn't know about. The 0.07 s figure in §23 was likely measured on a picture that compresses well.
- **How to trigger it:** New Snapshot, then Go to Snapshot, on a large photo with several layers; watch memory in Activity Monitor.
- **Why:** `ParallelRows.map(pixelLayers.count * bands.count) { … compress … }` returns every band before the write loop. `goToSnapshot` gathers `data` for every location before decoding.
- **Steps for Leah:** None. A big enough test is the kind of memory-heavy run that has upset the Mac before, so I'd leave this to a measured test.
- **Test that would catch it:** A Release-only `make perf` test: snapshot an 8000 × 8000 four-layer noise image and check peak resident memory stays under the image size plus a fixed margin.

## 8. Snapshots keep removed layers' pixels in memory, and the scratch file keeps growing
- **Severity:** Low
- **Confidence:** Medium
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/HistorySnapshot.swift:18-31` (`StoredLayer.layer`); `History+Snapshots.swift:136-140`
- **What happens:**
  - A snapshot holds each `Layer` object strongly, and so the buffer that layer last had. If a painted layer then leaves the canvas and history lets go of it, its full-size pixels stay in memory, outside the history budget, until the snapshot is deleted. For example: a layer whose New Layer step was undone and then dropped by a new edit.
  - The scratch file is let go only when the last snapshot is deleted. Deleting and retaking snapshots while one stays keeps adding to it, on disk.
- **How to trigger it:** New Layer, paint on it, New Snapshot, ⌘Z twice, paint elsewhere: the layer's pixels stay in memory. Or keep "Snapshot 1" and take and delete another ten times.
- **Why:** `goToSnapshot` needs the same `Layer` objects back, but only their identity and id. Their buffers are replaced on the way in, so holding the old ones serves no purpose. `deleteSnapshot` resets `snapshotStore` only when `snapshots.isEmpty`.
- **Steps for Leah:** None: it's only visible as memory and disk use.
- **Test that would catch it:** Core test: as above with a weak reference to the dropped layer's buffer; once the redo step is gone, the buffer has been freed (or its memory discarded) even with the snapshot kept.
