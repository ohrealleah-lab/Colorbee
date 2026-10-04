# Review A: undo history, memory and whole-image changes
Reviewed at commit: d67a8626cc8f975618ca03a10a8cf722cece4b5d
Checked:
- `History.swift`: `Edit`, `record` (including merging into the previous step), `undo`/`redo`/`swapPixels`, `undoOnLayer` and `candidate`, `forgetRedo`/`discardRedo`/`discardUndo`, `spillToBudget`, `heldLayerBuffers`, `refreshLayerBytes`, `evictLayers`, `restore`, `spill`, `load`, `SpillStore`
- `PixelBuffer.swift`: `isUntouched` (`mincore` flags, including compressed and swapped pages), `discardContents`/`reuseContents`, `generation`
- `Canvas.swift`: `copy`, `transform`, `replaceContents`, `restore`, `layerStackState`, the parallel `compositePixels`
- `Layer.swift` (`holdsNoPixels`), `ImageActions.swift` (crop, transform, resize and skew, resize canvas), `Orientation.swift` (inverse, vImage constants and row bytes)
- `Warp.swift`: the `ImageActions` extension (straighten, perspective, Crop…, `replaceEveryLayer`)
- `Decorations.swift`: growing the canvas, the same-size and geometry paths, the selection shift, the parallel distance transform
- `ParallelRows.swift`: band splitting, `map` result storage; every caller in the files above writes only its own rows or columns
- `FloodFill.swift`: the word-skipping scanline search (serial; checked the visited-bit logic and span growth)
- `Renderer.swift`: `PixelTexture.generation` and cache pruning, the two blur target sets and the photo path's use of them (no problems found)
- Followed the callers in `Editor.swift`, `LayerActions.swift` and `SelectionActions.swift` where they decide what reaches history

Two findings (1 and 2) involve code that predates commit `0970a64`, but stage 8 and 9 features hit them more often. They're included because they're in this session's files and break undo or the memory budget.

## 1. Placing a floating selection after a layer-settings step: its pixels can't be undone
- **Severity:** Critical (corrupted image and undo)
- **Confidence:** High
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/History.swift:282-289` (merge) and `:335-340` (`swapPixels` returns early for layer steps); `Packages/ColorbeeCore/Sources/ColorbeeCore/LayerActions.swift:168-174` (`update` doesn't place the floating selection); `Sources/Colorbee/Editor.swift:2424-2428` (`layerSetting`), `:2375-2385` (`previewLayerSettings`), `:572-578` (`applyCanvasProperties`)
- **What happens:** The pasted or moved pixels are stamped into the layer for good. The first ⌘Z brings the floating selection back on top of its own stamped copy, and undoing further never removes the stamped pixels.
- **How to trigger it:**
  1. Paste an image (⌘V), so a floating selection is showing.
  2. In the Layers panel, hide or show any layer, rename it, lock it, change its blend mode or drag its opacity. Or open Canvas Properties, switch the transparent background and change the size.
  3. Press Return to place the paste.
  4. Press ⌘Z twice. The pasted image is still in the layer, and the history has no step left that removes it.
- **Why:** `LayerActions.update` and `previewLayerSettings` record a layer step without placing the floating selection first (unlike `LayerActions.change`, which calls `placeFloating`), so the step's `selectionAfter` is still that floating selection. Then `placeFloating` sees `history.lastStepLeftFloating(floating.id) == true` and commits with `mergingIntoPrevious: true`. `record` appends the tile changes to the layer step (`previous.changes += added`). On undo, `swapPixels` handles `entry.layers` first and `return`s, so `entry.changes` is never swapped:
  ```swift
  if let layers = entry.layers { ...; canvas.restore(layers); entry.layers = current; return canvas.bounds }
  ```
  Canvas Properties hits the same path: `setTransparentBackground` is a layer step that keeps the floating selection, and `resizeCanvas` then places it, merging into that step. `candidate` (Undo on Active Layer) also looks only at `entry.layers` for such a step.
- **Test that would catch it:** One-layer canvas. Paste a floating selection through `SelectionActions`, then `LayerActions.update("Hide Layer", …)`, then `SelectionActions.placeFloating`. Undo until `canUndo` is false, and expect the layer's `contentHash()` to equal the original. Add these steps to the random-operation undo property test as well.

## 2. History's byte count drifts when a crop, resize or straighten is undone and then dropped; every Straighten, Drop Shadow and Border preview tick does this
- **Severity:** High (memory budget not enforced, or everything spilled)
- **Confidence:** High
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/History.swift:346-349` (`swapPixels` replaces `entry.geometry` with the current geometry), `:270-279` (bytes added at the old size), `:367-372` (`discardRedo` subtracts at the new size), `:362-365` (`forgetRedo`); `Sources/Colorbee/Editor.swift:1932-1936` (each preview tick undoes the last preview step, then commits a new one), `:2226-2228` (Cancel)
- **What happens:** `tileBytes` is increased by a geometry step's size when it's recorded. After undo, though, the entry holds the canvas's other-size buffers, and that other size is what gets subtracted when the redo stack is dropped. Each cycle leaves the count wrong by the difference:
  - When the step made the canvas smaller (Crop, Crop to Fit), history counts memory it doesn't hold, stays over budget for good, and spills every older step on every commit, undo and redo.
  - When the step made the canvas bigger (Resize Canvas up, Straighten without Crop to Fit, a Drop Shadow or Border that grows the canvas), the count goes down, possibly below zero, and the budget stops being enforced, so history memory grows without limit. This may be related to the heavy swap in the 2026-10-03 soak (unconfirmed).
- **How to trigger it:**
  - Straighten a 4000 × 3000 single-layer image with Crop to Fit on. Each slider tick near 10° adds about +15.6 MB of phantom bytes; with Crop to Fit off, each tick removes about 17.1 MB. A slider drag is dozens of ticks, multiplied by the number of layers.
  - Canvas Properties from 1000 × 1000 to 8000 × 8000, ⌘Z, then any brush stroke: about −252 MB of drift each time.
- **Why:**
  ```swift
  if let geometry = entry.geometry, let buffers = geometry.buffers {
      entry.geometry = canvas.currentGeometry   // byteCount now uses the *current* size and layer count
  ```
  `record` did `tileBytes += entry.byteCount` with the old size. `discardRedo` does `tileBytes -= entry.byteCount` with the swapped size. In `renderDecorationPreview`, `history.undo` followed by the next preview's `commit` (whose `record` calls `discardRedo`) runs this on every tick. Spill and load use the current size consistently with each other, so only the add at record time and the subtract at drop time disagree.
- **Test that would catch it:** History with a small budget. Record a crop from 64 × 64 to 16 × 16, undo, then commit a pixel edit. Expect `history.byteCount` to equal the pixel edit's bytes plus any layer bytes, with no geometry left. Repeat with a canvas resize from 16 × 16 to 64 × 64. Also: 20 straighten preview cycles (undo, then straighten again) at different angles, then `forgetRedo`, and expect `byteCount` to equal one straighten step's old-size bytes.

## 3. The history spill file only grows; an evicted layer is written out in full again on every eviction
- **Severity:** Medium (disk fills over a long session; slow undo and redo)
- **Confidence:** High
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/History.swift:495-513` (`evictLayers` appends), `:516-537` (`restore` forgets the locations: `evicted[id] = nil`), `:636-697` (`SpillStore` is append-only; `end` only grows)
- **What happens:** Space in the temporary file is never reused or freed until the document closes. A layer that only history holds (deleted, merged or flattened) is compressed and appended each time it's evicted. Undo past its step reads it back, and redo makes it history-only again, so it's appended again. At 8000 × 8000 that's about 100–250 MB each time. Jumping around in the History panel, or the soak test's random undo and redo, can write many gigabytes to the temporary folder. Tile spills behave the same way (load, then spill again appends a new copy), but layers make it large.
- **How to trigger it:** An 8000 × 8000 photo with 3 layers and a budget small enough to spill. Delete a layer, paint two strokes, then repeat ten times: undo three times, redo three times. The `colorbee-history-*.bin` file in the temporary folder grows by about one compressed layer per cycle.
- **Why:** `restore` sets `evicted[id] = nil` and drops the locations, although the data on disk is still valid while the buffer stays history-only and unchanged. `evictLayers` always appends fresh copies, and `SpillStore` has no free list or compaction.
- **Test that would catch it:** Expose the spill file's length (or `end`) to tests. Evict a layer, then undo and redo across it N times without changing its pixels. Expect the file to stop growing after the first eviction, or to stay under a bound.

## 4. Undoing a crop, resize or straighten whose step was spilled fills empty and adjustment layers with real memory
- **Severity:** Medium (memory, NFR-3)
- **Confidence:** High
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/History.swift:551-565` (spill compresses every layer of the geometry), `:600-619` (load makes a new buffer per layer and writes every band), `:143-145` (`GeometryChange.byteCount` counts every layer at full size)
- **What happens:** A geometry step keeps every layer's old buffer, including adjustment layers and never-painted layers, which take no memory (`isUntouched`). If that step spills, `load` makes new buffers and writes every band into them, zeros included, so after undo each empty and adjustment layer has a fully committed buffer. At 8000 × 8000 that's 256 MB per such layer. It also stops counting as `holdsNoPixels`, so later crops and rotations copy it in full. The byte count likewise counts these layers at full size, which makes history spill sooner than it needs to.
- **How to trigger it:** An 8000 × 8000 image with one pixel layer and three adjustment layers. Crop it, then do enough other steps that the crop step spills. Undo back past the crop. Resident memory rises by about 768 MB more than the image needs.
- **Why:** `spill` compresses `buffer.pixels(in: band)` for every buffer in `geometry.buffers`, and `load` does `let buffer = PixelBuffer(...)` then `buffer.setPixels(pixels, in: bandRects[index])` for each one, with no case for an untouched buffer.
- **Test that would catch it:** Canvas with a pixel layer and an adjustment layer. Crop with a 1-byte budget so the crop spills, add one more step, then undo twice. Expect the adjustment layer's `buffer.isUntouched` to still be true.

## 5. A preview tick that draws nothing leaves the last preview step on the redo stack
- **Severity:** Medium (broken behavior: a cancelled or refused straighten can be redone)
- **Confidence:** High
- **Where:** `Sources/Colorbee/Editor.swift:1932-1951` (`renderDecorationPreview`), `:2192-2203` (Apply), `:2225-2231` (Cancel). This overlaps session B, but it's history state.
- **What happens:** Each tick undoes the previous preview step, which moves it to the redo stack, then draws a new one. A new step clears the redo stack. If the new tick draws nothing, `decorationPreviewed` becomes false and the old preview step stays on the redo stack. Apply then beeps and Cancel skips `forgetRedo()`, so Edit ▸ Redo Straighten (or Redo Drop Shadow) is offered and re-applies a preview the user never applied.
- **How to trigger it:** Image ▸ Straighten…, drag to 3°, drag back to 0°, then press Return (or Esc). Edit ▸ Redo shows "Redo Straighten", and ⌘⇧Z turns the image 3°. Drop Shadow does the same with Opacity dragged to 0 when the shadow fits inside the canvas.
- **Why:** `ImageActions.straighten` returns false for `abs(angle) < 0.05`, and `Decorations.decorate` returns false when the commit records no change. In those cases nothing calls `discardRedo` (via `record`) or `forgetRedo`. Cancel calls `forgetRedo` only `if decorationPreviewed`.
- **Test that would catch it:** An Editor-level test, or a core test of the same sequence: commit a straighten at 3°, undo, call `straighten(angle: 0)` (returns false), then expect `history.canRedo == false` after the session ends (Apply or Cancel).

## 6. Straighten has no size limit
- **Severity:** Medium (edge case: memory exhaustion)
- **Confidence:** High
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/Warp.swift:167-174`
- **What happens:** With Crop to Fit off, the canvas can grow past `ResizeSkew.maxArea` (256 MP), which Resize/Skew, Perspective Correction and Drop Shadow/Border all refuse. Each preview tick allocates the full result for every layer.
- **How to trigger it:** A 16000 × 16000 image (256 MP, allowed). Straighten to 45° with Crop to Fit off: 22628 × 22628 = 512 MP, which is 2 GB per layer per tick.
- **Why:** `straighten` computes `Warp.straightenedSize(...)` and goes straight to `replaceEveryLayer` without the `maxSide`/`maxArea` guard that `correctPerspective` has on line 182.
- **Test that would catch it:** `straighten(angle: 45, cropToFit: false)` on a canvas sized so the result exceeds `maxArea` (or a lowered test limit) returns false and leaves history unchanged.

## 7. Layer bytes can be counted twice when a geometry step and a layer step hold the same buffer
- **Severity:** Low (history spills more than it needs to)
- **Confidence:** Medium
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/History.swift:470-487` (`heldLayerBuffers`/`refreshLayerBytes` look only at `entry.layers`), `:143-145`
- **What happens:** A buffer referenced both by a geometry step's `buffers` and by a layer step's records is counted once in `tileBytes` (geometry) and once in `layerBytes`. After `evictLayers` frees it, `tileBytes` still counts it until that geometry step is redone or spilled.
- **How to trigger it:** Two layers. Crop, delete a layer, undo twice. The redo stack's Delete step and Crop step both hold the cropped buffers (the comment at `load` notes this sharing).
- **Why:** `heldLayerBuffers` skips buffers in the canvas but not buffers also held in `geometry.buffers`.
- **Test that would catch it:** The sequence above with `byteBudget: .max`. Expect `history.byteCount` to equal the sum of the distinct buffers that history alone holds.

## 8. Straighten without Crop to Fit leaves transparent corners on an empty solid background
- **Severity:** Low (edge case: wrong pixels)
- **Confidence:** Medium
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/Warp.swift:211` (with `:172`)
- **What happens:** `replaceEveryLayer` gives any `holdsNoPixels` layer an empty buffer before `make` runs, so the Color 2 fill for the exposed corners is skipped. `resizeCanvas` (`ImageActions.swift:82`) and Decorations (`Decorations.swift:118`) handle this case (`holdsNoPixels && fill == .clear`); Straighten doesn't.
- **How to trigger it:** A new image with a transparent background (the background is never written). Canvas Properties: turn the transparent background off. Image ▸ Straighten 10°, Crop to Fit off. The new corners are transparent instead of Color 2.
- **Why:** `buffers[layer.id] = layer.holdsNoPixels ? PixelBuffer(size: size) : make(layer)`, while `make` is what passes `fill: canvas.vacatedFill(...)`.
- **Test that would catch it:** The sequence above in core. Expect a corner pixel of the background layer to equal Color 2.
