# Review results

What happened to each finding from the cloud review sessions (see [PLAN.md](PLAN.md)). Every fix has a
regression test that failed before it.

## Session A: undo history, memory and whole-image changes ([findings](findings-A.md))

Reviewed at `d67a862`. All eight findings were real. Fixed on 2026-10-03; tests in
`Packages/ColorbeeCore/Tests/ColorbeeCoreTests/ReviewATests.swift`.

| # | Severity | Finding | Outcome |
|---|---|---|---|
| 1 | Critical | Placing a paste after a layer-settings step merged its pixels into a step that never undoes pixels | **Fixed.** Tile changes only merge into a step that holds tiles; otherwise placing is its own step. |
| 2 | High | History's byte count drifted (even below zero) when a crop, resize or straighten was undone and dropped, on every Straighten, Drop Shadow and Border preview tick | **Fixed.** The count follows the geometry step's size as undo and redo swap it. |
| 3 | Medium | The spill file grew by a full layer each time an unchanged layer was moved out of memory again | **Fixed for layers.** A layer read back keeps a hash of its pixels; moved out again unchanged, its copy on disk is reused. Tile steps still append a new copy when re-spilled after an undo or redo (their pixels have swapped, so the old copy is out of date); the file is deleted when the document closes. |
| 4 | Medium | Undoing a crop whose step was spilled filled empty and adjustment layers with real memory | **Fixed.** Empty layers are recorded as empty and come back as fresh empty buffers. |
| 5 | Medium | A preview tick that drew nothing left the last Straighten, Drop Shadow or Border preview redoable | **Fixed.** An undone preview step is forgotten at once. |
| 6 | Medium | Straighten had no size limit | **Fixed.** It refuses results over 30,000 px a side or 256 megapixels, like Resize and Perspective Correction. |
| 7 | Low | A buffer held by both a geometry step and a layer step was counted twice | **Fixed.** Buffers a geometry step holds aren't counted again as layer bytes. |
| 8 | Low | Straighten without Crop to Fit left an empty solid background's new corners transparent | **Fixed.** Such a layer is drawn so its corners get Color 2. |

Finding 2 is a likely contributor to the heavy memory use in the first 30-minute soak (history could stop
enforcing its budget); the re-run of the soak will show.

## Session B: background work and the app's editing sessions ([findings](findings-B.md))

Reviewed at `d67a862`. All eight findings were real. Fixed on 2026-10-03. These are all in the app target,
which has no test target, so they were checked by reading and building, and by hand (STATUS lists what to
try).

| # | Severity | Finding | Outcome |
|---|---|---|---|
| 1 | High | An autosave during a Drop Shadow, Border or Straighten preview wrote the preview to the file, and Cancel never marked the document changed again | **Fixed.** Saving takes the preview step back for the copy and puts it back after, as tile previews already did. |
| 2 | High | Subject finding applied a mask made before a flip, undo or stroke during the Vision call | **Fixed.** The result is used only if history's revision is unchanged and no stroke or gradient is being drawn; otherwise a message asks to try again. |
| 3 | Medium | An autosave during a slider effect recomputed the whole effect on the main thread | **Fixed.** The preview's pixels are copied aside and put back after the save copy, not recomputed. |
| 4 | Medium | Straighten, Perspective Correction and Crop… beeped on a locked or adjustment layer | **Fixed.** Whole-image tools skip the lock check (§23). |
| 5 | Low | Select Subject with several subjects beeped on a locked layer | **Fixed.** The pick step skips the lock check; findSubject already checked it for the actions that change pixels. |
| 6 | Low | A late render from a closed effect cleared the next effect's "render running" flag | **Fixed.** A render from an older session leaves the flag alone. |
| 7 | Low | Two quick copies could put the older image at the top of Clipboard History | **Fixed.** Only the image still on the clipboard joins the history. |
| 8 | Low | With overlapping saves, "Last Saved" could be older than the file | **Fixed.** Writes don't overlap, so each save marks as saved the copy its write actually encoded. |

## Session C: pixel math, and screen versus export ([findings](findings-C.md))

Reviewed at `d67a862`. All four findings were real. Fixed on 2026-10-03; tests in
`Packages/ColorbeeCore/Tests/ColorbeeCoreTests/ReviewCTests.swift`.

| # | Severity | Finding | Outcome |
|---|---|---|---|
| 1 | Critical | Perspective Correction crashed (or folded the image) with crossed corners | **Fixed.** `Warp.isConvex` refuses crossed or folded corners in core; the tool beeps and stays open (§23). |
| 2 | High | Posterize, and steep Levels or Curves, adjustment layers looked very different on screen from the export | **Fixed.** These per-channel adjustments are drawn through a 256-entry table per channel (`ChannelTable`), read without interpolation, so the screen matches export exactly. Sepia and Adjust Photo keep the 3D table. |
| 3 | Low | Borders around shapes wider than about 8,200 px had gaps (Float precision in the distance transform) | **Fixed.** The transform's crossings are worked out in Double; the grid stays Float, so memory doesn't grow. |
| 4 | Low | A damaged project or filter file could crash instead of failing to open | **Fixed.** Project sizes are limited like Resize (30,000 px a side, 256 megapixels), and effect values must be finite and within ±1,000,000. |

## Session D: interface behavior against the FRD ([findings](findings-D.md))

Reviewed at `d67a862`. All six findings were real. Fixed on 2026-10-03, except two parts deferred. App target,
so checked by building and by hand.

| # | Severity | Finding | Outcome |
|---|---|---|---|
| 1 | Medium | Effect-bar, adjustment-layer and opacity sliders had no VoiceOver name; Curves couldn't be used with VoiceOver | **Fixed for sliders** (name and value). The curve now reads its points; **moving points with VoiceOver is deferred** (§23). |
| 2 | Low | A Levels layer's histogram and Auto used a stale picture of the layers below; working it out pauses the main thread | **Fixed: stale.** It's worked out again when a layer below changes (settings, buffers, undo or redo), not on the Levels layer's own slider ticks. **Deferred: the pause** when a Levels layer is selected on a large layered image. Doing it in the background safely needs a copy of the layers below, which costs about as much as the pause. |
| 3 | Low | Clicking near a Curves point jumped it to the pointer; a click past the white end point added a new end point | **Fixed.** Points move by the drag distance; a click at an existing point's x grabs that point. |
| 4 | Low | Renaming or deleting the chosen filter left Adjust Photo on an old copy | **Fixed.** Rename keeps it chosen under the new name; Delete takes it off (None). |
| 5 | Low | The toolbar could hide Adjust Photo's panel | **Fixed.** The Sidebar and Layers buttons are disabled while Adjust Photo is open. |
| 6 | Low | Subject commands stayed enabled during a search and did nothing | **Fixed.** Greyed out during a search and on an adjustment layer. |
