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

## Session F: the screen versus the saved file ([findings](findings-F.md))

Reviewed at `4df0688`; Leah confirmed all three by hand. All real. Fixed on 2026-10-04; core tests in
`Packages/ColorbeeCore/Tests/ColorbeeCoreTests/ReviewFTests.swift`. Leah chose the behavior for 1 (§23).
Leah also found that dragging layers to reorder them doesn't work; session G covers it.

| # | Severity | Finding | Outcome |
|---|---|---|---|
| 1 | High | Shapes, text and pastes on a layer that isn't Normal at 100% changed when placed | **Fixed: they preview the placed look.** On screen, such a layer is drawn with its unplaced object in it, then blended once (`blend_isolated_fragment`); exports do the same (`Canvas.compositePixels`). Text being typed is drawn by the canvas exactly as placing draws it; the text view shows only the caret and selection. |
| 2 | Medium | Saving or exporting with a stretched paste still floating wrote it blocky | **Fixed.** Saves, exports, copies and projects use the same Smooth or Sharp setting as the screen and placing. |
| 3 | Medium | Zoomed out, or for a smoothly stretched paste, transparent edges showed dark or colored fringes | **Fixed.** Smooth sampling in the shaders mixes premultiplied colors. Checked by hand only (no headless shader test). |

## Session G: undo restoring the wrong layer copies ([findings](findings-G.md))

Reviewed at `37959d2`; Leah confirmed 1–4 by hand. All five were real. Fixed on 2026-10-04; core tests in
`Packages/ColorbeeCore/Tests/ColorbeeCoreTests/ReviewGTests.swift`. Choices for 1 and 4 are in §23 (veto any).

| # | Severity | Finding | Outcome |
|---|---|---|---|
| 1 | Medium | Undo on Active Layer undid a floating paste or pending shape instead of the step its menu named | **Fixed.** It's greyed out while something on the layer isn't placed yet. |
| 2 | Medium | Dragging a layer row to reorder it didn't work | **Fixed (`199c881`).** The row follows the pointer and moves where it's let go, without the system drag (which never landed over the canvas). |
| 3 | Medium | Revert Layer went back to the layer without a paste that was floating at the save | **Fixed.** The layers as saved are built the way the project file is (`Canvas.layerBuffersAsSaved`), floating selection drawn in. |
| 4 | Low | Revert Layer after a flip or 180° rotation put one layer back unturned | **Fixed.** Revert Layer is unavailable while a crop, resize, rotation or flip made since the save is in effect (undoing it makes Revert available again). |
| 5 | Low | Duplicating an adjustment or empty layer used full-size memory | **Fixed.** Copying an untouched buffer keeps it untouched (no memory). |

## Session H: where the original pixels survive after redaction ([findings](findings-H.md))

Reviewed at `fc427a1`; Leah confirmed 1, 3 and 4 by hand and chose the behavior for 1–4 (§23). All seven were
real. Fixed on 2026-10-04 (`9a41bcd`); tests in `ReviewHIJTests.swift`.

| # | Severity | Finding | Outcome |
|---|---|---|---|
| 1 | High | File ▸ Revert To brought back the unredacted image | **Fixed (warn).** After a save with a redaction, Colorbee says earlier versions still show it, and offers Remove Earlier Versions. |
| 2 | High | Clipboard History kept the original screenshot | **Fixed.** Items can be removed one by one; after a redaction, Colorbee offers to remove the items this image was pasted from (Remove is the default). |
| 3 | Medium | Batch Redact changed only the active layer | **Fixed.** Batch Redact covers every layer under the selection, refusing on a locked one, like Auto-Redact. |
| 4 | Medium | Hidden or covered text isn't found, and survives in a project | **Fixed (note).** The sheet says only visible layers were checked; hiding a layer opts it out. |
| 5 | Low | The spill file could be left behind | **Fixed.** It's unlinked as soon as it's open, so it never outlives Colorbee. |
| 6 | Low | Share copies and old desktop pictures piled up | **Fixed.** Old Share folders go at launch and before each share; only the desktop picture in use is kept. |
| 7 | Low | Remove Background kept hidden colors in transparent pixels | **Fixed.** Fully cut-away pixels are cleared. |

## Session I: drawing tools and selections ([findings](findings-I.md))

Reviewed at `fc427a1`; Leah confirmed 1–5, 8 and 10 by hand. All sixteen were real. Fixed on 2026-10-04
(`e0e9f1a`, `9a41bcd`, `b5f4294`); tests in `ReviewHIJTests.swift` and `ReviewGTests.swift`.

| # | Severity | Finding | Outcome |
|---|---|---|---|
| 1 | Critical | Delete or Cut on a selection past the edge wrote outside the image | **Fixed (`e0e9f1a`).** Selections are clipped to the canvas, and Delete only touches the canvas. |
| 2 | Medium | The wand read under a floating paste; tool keys beeped after a paste | **Fixed.** The paste is placed first; choosing a tool or pasting gives the canvas the keyboard. |
| 3 | Medium | Transparent pixels with different hidden colors didn't match | **Fixed.** Fully transparent pixels are one color to Fill, the wand and the Color Eraser. |
| 4 | Medium | Symmetry's mirrored strokes overwrote each other | **Fixed.** Mirrored strokes share one painter. |
| 5 | Medium | The mirrored Eraser (and Pencil) landed a pixel off | **Fixed.** Pixel tools mirror whole pixel areas. |
| 6 | Medium | No Color Eraser tolerance | **Fixed.** A tolerance setting, 0% by default (Leah). |
| 7 | Medium | A handle drag could make a gigantic selection | **Fixed.** Limited to the Resize/Skew limits. |
| 8 | Low | Option-click with the Eyedropper ignored blend modes and adjustments | **Fixed.** It picks the pixel as shown. |
| 9 | Low | A Force Touch stroke started with a full-size dot | **Fixed.** The press's own pressure is used. Not testable headless. |
| 10 | Low | [ and ] changed the brush, not the shape line width | **Fixed.** |
| 11 | Low | Tall clouds had a flat top | **Fixed.** Painted bounds come from the shape's path. |
| 12 | Low | Gradients drew on one core | **Fixed.** Rows on all cores. |
| 13 | Low | Shift marquees could be one pixel off square | **Fixed.** |
| 14 | Low | The marquee's "click" was measured in image pixels | **Fixed.** 2 points on screen at any zoom. |
| 15 | Low | Small selections couldn't be moved | **Fixed.** Inside a small selection, a press moves it. |
| 16 | Low | The subject pick rounded off-canvas clicks toward the canvas | **Fixed.** |
| Q | — | Sample All Layers for Fill and the wand | **Added (Leah).** |

## Session J: stages 1–7 against the FRD, and documents ([findings](findings-J.md))

Reviewed at `fc427a1`; Leah confirmed 1, 2, 4–7, 15–17 and 23 by hand, and chose the behavior for 2 and 17
(§23). All twenty-nine were real. Fixed on 2026-10-04 (`9a41bcd`, `d8faf5d`, `77dda57`); core tests in
`ReviewHIJTests.swift` and `ShortcutTests.swift`.

| # | Severity | Finding | Outcome |
|---|---|---|---|
| 1 | Critical | After Revert To, the window kept editing an unsaved copy | **Fixed.** The window is rebuilt around the reverted document. |
| 2 | High | Editing a multi-frame or 16-bit file overwrote it with less | **Fixed (Leah).** Such files open as untitled copies; a frame bar and Choose Frame… for GIFs and TIFFs. WebP (which can't be written) opens as a copy too. |
| 3 | High | Portrait photos opened sideways | **Fixed.** The orientation tag is applied. |
| 4 | Medium | ⌘⌫ while typing deleted the layer | **Fixed.** Menu commands give way while typing. |
| 5 | Medium | Moving a standard shortcut named the wrong command | **Fixed.** Both what's given up and who loses the key are named. |
| 6 | Medium | Pasted and dropped new images weren't kept safe | **Fixed.** They start unsaved. |
| 7 | Low-Medium | Menus acted behind Resize and Skew and Canvas Properties | **Fixed.** Greyed out while they're open. |
| 8 | Low | The shortcut recorder caught keys from other windows | **Fixed.** |
| 9 | Low | Canvas keys could be assigned and then didn't work | **Fixed.** Refused. |
| 10 | Low | macOS's tab shortcuts weren't protected | **Fixed.** |
| 11 | Low | Window commands were missing from Settings ▸ Shortcuts | **Fixed.** Listed with a padlock. |
| 12 | Low | Clearing ⌘Z and the like didn't ask | **Fixed.** |
| 13 | Low | Imports skipped the checks | **Fixed.** Keys normalized; what couldn't be kept is reported. |
| 14 | Low | Tooltips showed default keys | **Fixed.** They follow the current shortcuts. |
| 15 | Low | Hiding Layers or Adjustments closed the whole sidebar | **Fixed.** |
| 16 | Low | ⌘Z didn't discard an unplaced shape | **Fixed.** |
| 17 | Low | Tools stayed clickable during an effect | **Fixed (Leah: grey them out).** |
| 18 | Low | Close, Minimize, Zoom and Full Screen were greyed out during an effect | **Fixed.** They work. |
| 19–21 | Low | Damaged projects (repeated ids, huge offsets) and palettes crashed | **Fixed.** Refused or ignored. |
| 22 | Low | "NaN" in Resize and Skew | **Fixed.** |
| 23–25 | Low | Palette named Paint Classic; deleting the palette in use; duplicate text style names | **Fixed.** |
| 26 | Low | Canvas Properties gave the wrong reason | **Fixed.** |
| 27 | Low | Damaged files showed an error code, or nothing | **Fixed.** Plain messages, and drops and Services say why. |
| 28 | Low | Relaunch lost an image-turned-project's name, zoom and panels | **Fixed.** |
| 29 | Low | VoiceOver gaps (A1–A8) | **Fixed**, except bare readouts in the status bar (A7, part) and Curves points (round 1, deferred). |

---

# Round 4: pages, PDFs, Auto-Redact on every page, RAW photos ([plan](PLAN-4.md))

Reviewed at `9cf0fc5` by two local sessions (K and L). Verified by the engineer against the code on 2026-10-05:
all 29 are real, except K8, which was a judgment call for Leah. Several overlap (K3 = L4, K9 = L6, K5/K7 = L14), so
they come to 17 fixes, done in three batches. Leah's decisions: Export as PDF converts pages with a non-standard
color profile to Display P3 (K8); the Clipboard History offer covers copies made from the document too (K11).

## Session K: privacy with pages, PDFs and camera details ([findings](findings-K.md))

| # | Severity | Finding | Outcome |
|---|---|---|---|
| 1 | High | A shape or text not yet placed was left out of saves, exports, copies, Share and Print | **Fixed (batch A).** Placed first; autosave leaves them alone. |
| 2 | Medium | After a page failed to read, Apply redacted only the pages read | **Fixed (batch A).** Apply is refused, and the page is named. |
| 3 | Medium | Hidden pages kept full-size copies, also after Remove Earlier Versions | **Fixed (batch B).** Hidden pages' baselines are kept compressed (`PageBaseline`) and replaced by Remove Earlier Versions. |
| 4 | Medium | Pages redacted before being shown got the redacted page as "As Opened" | **Fixed (batch B).** Every page's opened state is its bytes at open. |
| 5 | Medium | A page that couldn't be brought back left the Editor on the wrong page | **Fixed (batch A).** Page changes bring the new page back first; a failure changes nothing. Core tests. |
| 6 | Medium | A one-page project forgot its PDF resolution | **Fixed (batch B).** Kept in its manifest. Core test. |
| 7 | Low-Medium | A failure partway through Apply gave a wrong message, and a page could drop out of saves | **Fixed (batch A).** Saves include every page; the message says which pages were redacted. |
| 8 | Low | Export as PDF embedded custom color profiles | Batch C (Leah: convert to Display P3). |
| 9 | Low | A damaged project could crash on a thumbnail's size | **Fixed (batch B, in passing).** Sizes are bounded first. Core test. |
| 10 | Low | The PDF writer could fail silently | Batch C. |
| 11 | Low | Copies made from the document weren't in the Clipboard History offer | **Fixed (batch A, Leah).** |

## Session L: RAW photos, opening files, and background work ([findings](findings-L.md))

| # | Severity | Finding | Outcome |
|---|---|---|---|
| 1 | High | A History panel click could undo or redo a page change | **Fixed (batch A).** The panel steps only the page shown. |
| 2 | High | Save, Export, Share and Revert worked behind Auto-Redact; autosave could write half a redaction | **Fixed (batch A).** Greyed out behind any sheet or effect bar; autosave waits while Apply runs. |
| 3 | Medium | A cancelled Save panel could make autosave write a lossy format | **Fixed (batch A).** Untitled documents autosave as projects. |
| 4 | Medium | Every page visited kept a full-size copy (same as K3) | **Fixed (batch B).** |
| 5 | Medium | Deleted pages were never freed | **Fixed (batch A, in passing).** Let go once they can't be undone. Core test. |
| 6 | Medium | A damaged project could crash on a thumbnail's size (same as K9) | **Fixed (batch B).** |
| 7 | Medium | Opening a PDF rendered every page at once on all cores | **Fixed (batch B).** Four pages at a time. Opening in the background with progress is for later. Core test. |
| 8 | Medium | Dropped PDFs, projects and RAW files didn't open like File ▸ Open | Batch C. |
| 9 | Low | Develop's Cancel didn't work while developing | Batch C. |
| 10 | Low | Undoing Delete Page lost the page's baselines | **Fixed (batch B).** Kept while undo can bring the page back. |
| 11 | Low | A developed photo lost its camera details after a relaunch | **Fixed (batch A)** with L3: projects keep them. |
| 12 | Low | Other pages' saved state was taken when shown, not when saved | **Fixed (batch B).** Each page's saved state is the bytes written for it. |
| 13 | Low | Reordering by dragging stopped at the sidebar's edge | Batch C. |
| 14 | Low | A failure halfway through a page change left things inconsistent (same as K5, K7) | **Fixed (batch A).** |
| 15 | Low | Page switches compress and expand on the main thread | Later (logged in STATUS). |
| 16 | Low | The Export panel was never freed | Batch C. |
| 17 | Low | Develop's final size came from the default render | Batch C. |
| 18 | Low | Export as PDF held pages twice; failed compression went unnoticed | Batch C. |
