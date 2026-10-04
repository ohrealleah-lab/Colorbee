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

## Round 2, local sweeps ([plan](PLAN-2.md))

Done on 2026-10-04 at `918ce67`. Core tests in `Packages/ColorbeeCore/Tests/ColorbeeCoreTests/DamagedFileTests.swift`.

**1. Damaged and unusual files.** Every reader of outside data was checked: images (open, paste, drop),
projects, filters, palettes, shortcuts, redaction patterns, Clipboard History, settings.

| Found | Outcome |
|---|---|
| Images had no size limit before decoding; a real file over 30,000 px a side or 256 megapixels was decoded in full (ImageIO refuses some oversized headers itself, but not long thin ones or every format) | **Fixed.** The size in the file's header is checked first; such images give "too large to edit" (§23). |
| Curves points, Adjust Photo values and filter intensity were read from projects and filters without range checks | **Fixed.** Clamped to their ranges as they're read. They didn't crash, but showed nonsense values. |
| A filter inside a project could hold steps a filter mustn't (blur, crop) | **Fixed.** Read through the same check as an imported filter. |
| A project with a gray or CMYK color profile opened, then crashed when text or a shape was drawn | **Fixed.** Only an RGB profile is used; otherwise Display P3. |
| A shortcuts file with a key like `f99999999999` crashed when the menus were updated | **Fixed.** Only F1 to F20 are function keys. |
| Palettes, redaction patterns, Clipboard History, settings | No problem: checked counts, invalid patterns skipped, Colorbee's own files. |

**2. Crashes on unusual numbers.** About 100 conversions from decimal to whole numbers, plus forced unwraps,
were checked. Most get values already bounded (slider ranges, pointer positions, image sizes).

| Found | Outcome |
|---|---|
| Export presets: a huge width typed in Settings crashed the File menu (sized with enlarging allowed) | **Fixed.** No preset size goes past 30,000 px a side; test. |
| Resize and Skew in pixels: a width over about 9.2 quintillion crashed before the size check | **Fixed.** Sizes over 30,000 px are refused first. |
| Crop's custom ratio: a huge number could overflow the box's sums | **Fixed.** Ratios run up to 1000:1. |

**3. Menus against commands.**

| Found | Outcome |
|---|---|
| Cut on a locked layer copied to the clipboard, then refused to delete | **Fixed.** It beeps before copying. |
| Pixel commands (effects, adjustments, Delete, Cut) stay enabled on a locked or adjustment layer and beep when chosen; Select Subject and friends are greyed out on an adjustment layer (review D, finding 6) | **Fixed (Leah: grey them out).** Commands that change the active layer's pixels, Paste included, are greyed out on a locked or adjustment layer; whole-image commands stay. |

## Session E: stale results, and Auto-Redact ([findings](findings-E.md))

Reviewed at `918ce67`; Leah confirmed findings 1–5 and 7 by hand. All seven were real. Fixed on 2026-10-04;
tests in `Packages/ColorbeeCore/Tests/ColorbeeCoreTests/ReviewETests.swift`. Leah chose the behavior for
1, 2 and 4 (§23). The redaction itself moved into core (`AutoRedact.apply`), so it's tested.

| # | Severity | Finding | Outcome |
|---|---|---|---|
| 1 | Critical | Auto-Redact read every layer but redacted only the active one | **Fixed.** Each box is redacted on every layer with pixels under it, as one step. A locked layer with pixels under a box stops it, naming the layer. |
| 2 | Critical | The image could change (menus still worked behind the sheet) between reading and Apply; a cancelled run's scan could fill in a new one | **Fixed.** Menus are greyed out while the sheet is open; Apply refuses if the image changed; each run ignores scans that aren't its own. |
| 3 | High | Blur and Pixelate used the median strength, so large text among small text stayed readable | **Fixed.** Each item at the strength for its own height. |
| 4 | High | With a selection, items were clipped to it (or dropped when their center was outside) | **Fixed.** Any item touching the selection is listed and redacted whole. |
| 5 | High | Text was missed on tall images and transparent backgrounds | **Fixed.** Text is read over white, with no minimum text height, and long images are read in overlapping pieces; matches read twice are merged. 10 of 10 found on a 1200 × 10,000 test image (was 0). |
| 6 | Medium | Several commands flatten or encode on the main thread | **Fixed:** Auto-Redact's start, Share, Set as Desktop Picture, and "Last Saved" for Before/After (prepared after each save). **Deferred:** Print, and the Auto buttons for Auto Contrast and an Adjust Photo layer, which need the result at once (like round 1's D2). |
| 7 | High | A Stripe-style key wasn't found | **Fixed.** The key patterns allow the underscores to be read as spaces or not at all. In Menlo, Vision reads the key fine; the test screenshot's DejaVu Sans Mono likely lost the underscores. |
