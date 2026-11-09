# Monkey test gaps (review, 2026-11-01)

Where the overnight monkey (`Tests/ColorbeeTests/Monkey`) could catch bugs but doesn't look yet. Review only: no code
was changed and nothing was run.

**Where this list stands (audit, 2026-11-09).** Closed: C12, R2, R5, R6. Partly closed: C1 (default settings only), C14,
R1 (pixels now proven covered; the transparency lock isn't separately checked), R1b (spill files aren't checked), R1c
(the report now counts finds: about 3 Auto-Redacts in 110 find anything), R3 (marquee outlines aren't compared). C3 is
closed for leaving objects open; handles and cancel by Escape aren't driven. Still open: C2, C4 to C11, C13, R4, R7 to
R14. New since the review: pictures never passed one 256 px undo tile (fixed: one episode in sixteen does), and the
monkey has no timeout, so a hang would use up the night. Next in line: R4 (real exports), then C2 (effect dialogs).

**Priorities.** High: lost work, crashes, secrets left after a redaction, or exports that don't match the screen, and
the monkey could reach it. Medium: a real bug class, but rarer or less harmful. Low: worth having, little risk.

**Safety rules for every addition.** The monkey must never save preferences (custom colors, text styles, redaction
patterns, export options, Adjust Photo's "last used"), never touch the Mac clipboard, and must wait for background work.
Two facts from the code matter throughout:

- `StoredSettings.canWrite` and `SettingsFolder` already refuse to write under `TestHost`, but several settings bypass
  them and write `UserDefaults` directly: the Smoothing slider and Editable switch (`DocumentView.swift:159, 263`), the
  last save format (`ImageDocument.swift:192`) and every export option (`ImageDocument.swift:529–564`). So "the guard
  will catch it" is not safe; the monkey must call the Editor directly, never the controls or option objects.
- `PhotoSettingsStore.shared.last` is set by Adjust Photo's Apply, As Adjustment Layer and Paste Photo Settings as
  Adjustment Layer (`Editor+AdjustPhoto.swift:179, 268, 444`). Even if it isn't written to disk under the test host,
  it carries over between episodes, so replays wouldn't repeat exactly.

Already known (not repeated below): Straighten, Border, Drop Shadow, Revert Layer, Step Badges, Magic Wand, lasso,
Trim, the transparent background setting, and jumping around in the History panel.

---

## Part 1: Commands it never runs

### C1. The Retouch tool, all ten kinds · **High**

- **Missing:** Remove, Spot Heal, Clone Stamp, Lighten, Darken, Saturate, Desaturate, Blur, Sharpen and Smudge are
  never used. `Tool.retouch` isn't in the stroke list at all.
- **Why risky:** Lost work. Remove and Spot Heal work out their fill in the background and land later
  (`endRetouchStroke`, `Editor+Retouching.swift:240`); a big Clone Stamp stroke with Match Tone does too
  (`matchTone`, line 164). Earlier reviews (O 8, O 13, R 1) found landings that lost or corrupted edits. Nothing
  tests a landing against undo, a page switch or another edit.
- **How:** `selectTool(.retouch)`, set `retouchKind`, `retouchSize`, `retouchStrength`, `retouchHardness`,
  `toneRange`, `retouchSamplesAllLayers`; for Clone Stamp, `setCloneSource(_:)`, `cloneAligned`, `cloneMatchesTone`.
  Brush kinds: `beginRetouchBrush` / `continueRetouchBrush` / `endRetouchBrush`. Remove and Spot Heal:
  `beginRetouchStroke` / `continueRetouchStroke` / `endRetouchStroke`. Then wait while `fillCancel != nil` or
  `isMatchingTone` (as `.autoRedact` waits). Also a "racing" variant that starts the next step without waiting, which
  is what `stopFillForChange` and `finishPendingTone` exist for.
- **Tricky:** A late landing adds a history step after the monkey has noted the step, so `UndoTracker` would blame the
  next step. The racing variant needs the tracker to treat "a fill landed" as its own step (or wait at the end of the
  next step and re-note). Match Surroundings can refuse an area ("too big", "not enough picture"), which is fine.

### C2. Effect dialogs: preview, then Apply or Cancel · **High**

- **Missing:** `.effect` uses the one-click `applyAdjustment` for five effects. The dialog path (`beginEffect` →
  background preview → `applyEffect` or `cancelEffect`) is only used by Batch Redact. Never used: Levels, Curves,
  Hue/Saturation, Sepia…, Posterize…, Add Noise, Motion Blur, Emboss, Sharpen, Vignette, Spotlight, Gaussian Blur…,
  Pixelate…, Perspective Correction and Crop… (with its shapes and pixel size).
- **Why risky:** Lost work. Cancel must put back the exact pixels (`effectEdit?.restoreOriginals()`); a preview still
  rendering in the background when you press Apply, undo or switch pages is where generation bugs hide. Perspective
  and Crop… replace every layer's buffer.
- **How:** `beginEffect(kind)`, set that kind's values the way its bar does, wait for `previewRunning == false`, then
  `applyEffect()` or `cancelEffect()`. Variants: undo, show another page, or save and reopen while the preview runs.
  New rule: after Cancel, `documentState` equals what it was before `beginEffect`.
- **Tricky:** Each kind keeps its settings in different properties (`effectValues`, `effectCurves`, `cropRect`,
  `perspectiveCorners`); each needs a small setter. **Adjust Photo's dialog can't be applied safely:** Apply sets
  "last used" (line 444). Cancel is safe. To apply it, the code would need a test-only way to skip `last`.

### C3. Placing pending shapes and text by another command · **High**

- **Missing:** The monkey always places a shape or text at once (`commitPendingShape`, `commitPendingText`). It never
  leaves one open and then does something else, so `finishInteractions()` placing it "before any other command" is
  never tested. It also never cancels one (`cancelPendingShape`).
- **Why risky:** Lost work and crashes. A pending object meeting undo, a crop, a page switch, a layer delete or a save
  is exactly where an object could vanish or land on the wrong layer or page. Closing and quitting are meant to place
  them too (FRD §23, 2026-10-31).
- **How:** Give `.shape` and `.text` a "leave open" flag; the next random step then meets the pending object. Also
  steps that move or resize the pending shape by its handles (`shapeHandle(atView:)`, `beginShapeDrag` on a handle)
  and the text box (`textBoxGrab`, `beginTextBoxDrag`).
- **Tricky:** The tracker must expect the placing to show up as an extra step inside the next one; its existing
  "one action, several steps" branch already allows that.

### C4. Copy and Paste in Place without the clipboard · **Medium**

- **Missing:** Copy, Copy Merged, Cut and Paste in Place are never used; `.paste` pastes a solid-color box.
- **Why risky:** Exports and screen. Copy Merged and Paste in Place must line up to the pixel; layer masks, clipped
  layers and floating pieces make that easy to get wrong.
- **How:** Without touching the Mac clipboard: `let pixels = editor.selectedPixels()` (or `selectedMergedPixels()`),
  `let place = editor.copiedPlace(merged:)`, then later `editor.paste(pixels, inPlaceAt: place)`. Cut is that plus
  `deleteSelection(named: "Cut")`. New rule: Copy Merged then Paste in Place on a new top layer with nothing else
  changed leaves the look unchanged where the paste is opaque.
- **Tricky:** `ClipboardImage.copy` and `ClipboardHistory.shared.add` must not be called: they write the real
  clipboard and Clipboard History. Copy Text's Vision reading is safe only with a closure that doesn't write the
  pasteboard, and its later cleanup offer (`removeClipboardSources`) clears the real clipboard, so never call that.

### C5. More selection shapes and ways to change them · **Medium**

- **Missing:** Ellipse Select; Shift (add) and Option (subtract) drags (`selectionDrag` supports both, the monkey never
  passes them); resizing a floating piece by its handles (`beginResize`); `resizeMarquee`; Feather, Expand, Contract,
  Smooth (`beginSelectionChange`, background for soft edges); Color Range, Luminance Range, Graduated Selection.
- **Why risky:** Crashes and lost work. A soft (feathered) mask meeting crop, resize, Delete or a floating move is a
  rarely hand-tested mix. A resized floating piece must keep its source exact (CLAUDE.md: "moves and resizes always
  start from the original").
- **How:** As named above; for the background ones, wait for the result the way OK does, then `applySelectionChange`
  or `applyRange`, or cancel.
- **Tricky:** Color Range picks a color from the picture (`pickRangeColor`), so the monkey needs a point, not a color.

### C6. Tool options that stay at their defaults · **Medium**

- **Missing:** `fillTolerance` (always 0) and `fillSamplesAllLayers`; `colorEraserMode` and `colorEraserTolerance`;
  `gradientMode` (always linear); `shapeLineWidth`; 16 of the 23 shape kinds (only 7 are picked); shape styles other
  than solid and marker; `transparentSelection` and `smoothResize` (these change how a floating piece is placed and
  stretched; possibly part of the known "transparent background" gap, but they are separate settings); text style
  (`textStyle`: font, size, alignment, opaque background) and wrapped text (`wrapWidth`); pressure.
- **Why risky:** Exports and screen. Each option is another code path in fill, color erase, gradient and shape
  drawing that today only hand tests reach. Fill with all layers flattens the picture, which matters with masks and
  adjustment layers.
- **How:** Randomize them in the existing steps. None of these are saved preferences when set on `Editor` directly.
- **Tricky:** `textStyle` comes from Text Styles; set the property, never use the store. Fonts: pick only system fonts
  so replays work on any Mac.

### C7. Several chosen layers: Select All Layers, Align, Distribute, and the menu toggles · **Medium**

- **Missing:** `selectAllLayers`, `alignChosenLayers`, `distributeChosenLayers`, and the menu's
  `toggleChosenLayersVisible` / `Locked` / `LockTransparency` (the monkey uses the one-layer panel versions). `.group`
  only ever groups two layers.
- **Why risky:** Lost work. FRD §23 (2026-10-31): Align moves a layer's mask with it, and a text layer's words with
  its pixels. Commands over a set of layers that includes groups, locked layers or adjustment layers are easy to get
  half right.
- **How:** `chooseLayer(at:extending:toggling:)` a few times, then the command.
- **Tricky:** None beyond choosing sensibly.

### C8. Layers panel extras · **Low**

- **Missing:** `renameLayer`, `setPassesThrough`, `toggleIsolation`, `toggleMaskAlone`, `toggleFold`, and New
  Adjustment Layer kinds Levels, Curves, Auto Contrast and Sharpen (the monkey picks 6 of 11), with their panel sliders
  (`previewAdjustment` then `finishLayerSettings`). `.photoSetting` replaces every slider with one; the Color Mixer,
  Color Grading, Point Color, tone curve and photo geometry are never set.
- **Why risky:** Isolation hides other layers for a while; if that leaks into a save or an export, the export would
  be wrong. Rename is the step that clears "named from its words" (matters for R1).
- **How:** As named. Build `PhotoEdit` values directly for the photo parts, as `.photoLayer` does.
- **Tricky:** `.cube` looks and saved filters come from the settings folder; build a small look in code rather than
  reading Leah's.

### C9. Delete every word of a text layer · **Medium**

- **Missing:** `words()` never returns "", so "deleting every word of a text layer removes the layer" (FRD §23,
  2026-10-31, item 3) is never run.
- **Why risky:** Crashes: a layer removed from inside a text edit, perhaps the active one, perhaps in a group.
- **How:** Add "" (and a multi-line string) to `words()` for `.editText`.

### C10. Subject tools: Select Subject, Remove Background, Lift Subject · **Medium**

- **Missing:** `findSubject(_:)` in all three forms.
- **Why risky:** Lost work: Remove Background erases pixels from a Vision mask worked out in the background, and a
  closer look can still be running when you Cancel (review T, finding 5).
- **How:** `findSubject(.select)` etc.; wait while `isFindingSubject`; then `applyEffect()` or `cancelEffect()`.
- **Tricky:** On small flat pictures Vision may find nothing; that's fine, but the monkey should count how often it
  finds something, or the step is mostly a no-op. Vision results may differ between macOS versions, so replays
  aren't guaranteed.

### C11. Remove Red-Eye, Auto Contrast, Solid Fill with Color 1 · **Medium**

- **Missing:** `removeRedEye`, `autoContrast`, `addAutoContrastLayer` and Redact ▸ Solid Fill with Color 1
  (`applySolidFill`).
- **Why risky:** Solid Fill is a redaction command (secrets); it should meet the R1 rules.
- **How:** One call each.

### C12. Forget history after a redaction · **High**

- **Missing:** `forgetHistory()` (what "Remove Earlier Versions and Undo History" does after a redacted save) is never
  run.
- **Why risky:** Secrets. It must drop every page's undo, every snapshot, the page changes that could bring a deleted
  page back, and reset each page's "As Opened" (review K, finding 3). It walks parked pages too.
- **How:** Call `editor.forgetHistory()` directly; the alert and `NSFileVersion` aren't needed. Then the R1b rules.
- **Tricky:** After it, the tracker must restart with nothing to undo.

### C13. Before/After, zoom and canvas anchors · **Low**

- **Missing:** `toggleComparison`, zoom (`zoomIn`, `zoom(to:)`), and Canvas Properties' anchor
  (`applyCanvasProperties(size:anchor:transparentBackground:)`; the monkey's `resizeCanvas` is centered only).
- **Why risky:** Before/After is read-only: nothing may change while it's on. Zoom changes `smoothingReach` and how
  handles are hit, so strokes and drags behave differently at other zooms.
- **How:** Toggle comparison, run a few random steps, check `documentState` didn't change, toggle back. Zoom is view
  state only.

### C14. Page commands the sidebar and menu add · **Low**

- **Missing:** Move Page Up/Down and Previous/Next are covered by `movePage` / `showPage`. Not covered: undoing a page
  change itself (Undo after New, Duplicate or Delete Page) as a checked step. See R2.

### C15. Things that can't be covered safely today

- **Clipboard History panel** (paste from history, remove items): it uses `ClipboardHistory.shared`, which keeps
  Leah's real history and can clear the Mac clipboard (`remove(_:clearingClipboard:)`). Coverable only if the Editor
  could be given a private in-memory history.
- **Copy Color as Hex, Copy (real), Paste (real), Paste into New Image:** the real clipboard. C4 covers the document
  side.
- **Export dialog, presets and Export as PDF through `ImageDocument`:** they read and write export options in
  `UserDefaults`. R4 covers the encoding side without them.
- **Adjust Photo: Same as Last, Apply in the dialog, Paste Photo Settings as Adjustment Layer:** they read or write
  "last used". Copy Photo Settings and Paste Photo Settings only use the in-memory `copied` and are coverable if the
  monkey sets `PhotoSettingsStore.shared.copied = nil` at the start of every episode, so replays stay exact.
- **Saved filters, palettes, text styles, shortcut editing, Settings:** preferences.
- **Revert To Saved, Duplicate, autosave, window restoration:** `NSDocument` and windows, which the test host must not
  open.

---

## Part 2: Rules it never checks

### R1. Redaction leaves nothing behind · **High**

- **Missing:** After a Redact Brush stroke, Batch Redact or Auto-Redact, nothing checks what's left. The FRD says:
  a redaction turns a text layer under it into pixels (Q29.2), renames a layer (and its mask) named from its words to
  "Text", even if it became pixels some other way (§23, 2026-10-31), and ignores the transparency lock so the
  letters' outline can't survive.
- **Why risky:** Secrets. This is what Colorbee is most often for.
- **How:** Before a redaction step, note each text layer whose box meets the redacted area, and its words. After:
  (a) none of those layers is still a text layer; (b) no layer name or mask name contains those words; (c) the
  redacted area of every pixel layer changed, or was already blank, even on a transparency-locked layer; (d)
  `ProjectFile.encode` → decode has no text layer, name or mask name with those words; (e) on other pages too, for
  Auto-Redact. The monkey already writes "API key" as text, which makes this easy to search for.
- **Tricky:** What "the area" is differs by kind: the brush's `RedactBrushArea`, the selection, or each match's box.
  Undo is allowed to bring the words back until R1b's `forgetHistory`, so the rule is about the current state.
  **Leah, 2026-11-01:** no. A redaction deletes the snapshots of each page it changes, after asking, and undo
  doesn't bring them back (FRD §23). Not built yet; today `History.removeAll` clears them only at `forgetHistory`.
  Once built, add (f): after a redaction step, the pages it changed have no snapshots, and undoing it brings none
  back. The monkey answers the question with "Delete Snapshots and Redact", and sometimes with "Cancel" (then
  nothing may change).

### R1b. After Forget History, nothing can bring the old picture back · **High**

- **Missing:** No checks after `forgetHistory` (C12).
- **How:** On every page: `history.canUndo == false`, `canRedo == false`, no snapshots, no spilled files left
  (`spillStore`, `snapshotStore`), `pages.restorablePages` empty, and each page's "As Opened" equals the page now
  (`asOpened` for the shown one, `pageMemory[...].opened` for the others).
- **Tricky:** Disk spill files are written in the background (`evictsInBackground`); wait for the eviction queue
  before checking the folder is empty.

### R1c. Auto-Redact actually finds something sometimes · **Medium**

- **Missing:** The monkey's words ("Hi", "API key", "OK"…) probably match none of the built-in patterns, and the text
  is small, so `.autoRedact` is likely nearly always a no-op.
- **How:** Add text that a built-in pattern catches (an email address, a phone number), large enough for Vision, and
  count in the report how many Auto-Redacts found something. Then R1 applies to it.
- **Tricky:** Custom patterns and turned-off built-ins are Leah's settings; the monkey must use the built-ins only and
  never change which are on.

### R2. Every page, not just the one shown · **High**

- **Missing:** When the shown page changes, `UndoTracker.restart` forgets everything. So nothing checks that a page
  you leave and come back to has exactly its pixels and layers (parking compresses it, `Page.park`); that Undo after
  Delete Page brings the page back exactly; or, on save and reopen, any page but the shown one (`checkSame` only
  compares the page count).
- **Why risky:** Lost work. Pages are where STATUS says lost work would hurt most.
- **How:** Keep `documentState` per page id when leaving it; on showing it again, compare. On reopen, unpark each
  page in the copy and compare each. When a page is deleted, keep its state; when an undo brings it back, compare.
  At the end, across pages, compare each page's state at each undo step rather than only "it did something".
- **Tricky:** Auto-Redact (every page), `forgetHistory`, and undoing across pages legitimately change other pages;
  those steps must refresh the stored states rather than be blamed.

### R3. The floating piece and the selection are part of undo · **High**

- **Missing:** `documentState` holds layers only. A floating piece's pixels and position, and the marquee, aren't
  compared, though every history entry captures the selection before and after (CLAUDE.md).
- **Why risky:** Lost work. A floating piece's source pixels are cut from the layer and live only in the selection
  until it's placed; if undo or redo loses it, the pixels are gone and the current rules can't see it.
- **How:** Add to `documentState`: the floating piece's source hash, its rect and layer id, and the marquee's mask
  hash.
- **Tricky:** Drawing a marquee isn't a history step, so the "changed without an undo step" rule must ignore marquee
  changes, and when the monkey sees a marquee change with no step, it should update the current line entry's selection
  part (the next step's "selection before" will be that marquee).

### R4. Real exports match the screen · **High**

- **Missing:** The end check compares the thumbnail with `flattened()`, and skips it when a blur or Posterize is shown.
  No real export is ever encoded and read back, no other page is exported, and PDF is never written.
- **Why risky:** Exports that don't match the screen. The export path (`saveSnapshot` → encode in the background)
  is different code from `flattened()`, and `SaveSnapshot` places pending objects and floating pieces itself.
- **How:** At the end, and now and then mid-way: `editor.saveSnapshot()`, encode PNG with `editor.encoded(as: .png)`
  (or the snapshot's own encoder), decode, compare with `canvas.flattened()` exactly, and check the color profile is
  the document's. Same for each page, and for the PDF writer per page with a looser match.
- **Tricky:** Never create export option objects (they save to `UserDefaults`); pass formats and quality directly.
  JPEG and HEIC are lossy, so compare PNG and TIFF exactly and leave lossy formats to a "decodes and is the right
  size" check.

### R5. Saving in the background while editing goes on · **High**

- **Missing:** The app encodes a `SaveSnapshot` copy in the background while you keep editing. The monkey encodes
  at once, on the main thread, so a snapshot sharing a buffer with an edit that follows is never caught.
- **Why risky:** Lost work and corrupt files (autosave).
- **How:** Take `saveSnapshot()`, note `documentState`, do several more steps, then encode the snapshot in a detached
  task, await it, reopen and compare with the noted state.
- **Tricky:** Must truly await the task. Steps that free memory (spilled history, `discardContents`) are the
  interesting ones to do in between; see R6.

### R6. Undo after history spills to disk · **High**

- **Missing:** On pictures of at most 160 × 120, history never comes near its byte budget, so spilling to disk,
  LZ4, and `PixelBuffer.discardContents` for merged-away or deleted layers never happen. The "over budget" rule can't
  fire.
- **Why risky:** Lost work. Undo after a spill must bring back the very same buffers; anything wrapping buffer memory
  must check `generation`.
- **How:** Give the monkey's pages a tiny budget (say 256 KB). The first page can be made with
  `Editor(pages: PageStack(pages: [Page(canvas:, history: History(byteBudget:))]))`; new pages need a test seam in
  `Editor.makeHistory()`.
- **Tricky:** `evictsInBackground` means eviction finishes later; wait on the history's eviction queue before each
  check. Spill files go to a temp folder; clean up after each episode.

### R7. History Snapshots go back exactly · **High**

- **Missing:** `goToSnapshot` is tracked only as an undoable step. Nothing checks that the picture then equals the
  picture when the snapshot was taken.
- **Why risky:** Lost work. A snapshot is a deliberate safe point.
- **How:** On `.takeSnapshot`, keep `documentState` (with the floating piece placed, as the code does) by snapshot id;
  after `.goToSnapshot`, compare. Add rename and delete snapshot steps (`renameSnapshot`, `deleteSnapshot`) so the
  lookup by id is exercised.
- **Tricky:** A crop or resize after the snapshot means going back changes the picture's size too; that's expected.

### R8. Merges and Flatten keep the look · **Medium**

- **Missing:** Nothing compares `flattened()` before and after Merge Down, Merge Visible, Flatten, Stamp Visible,
  Group, Ungroup, Apply Mask, Rasterize Text or Merge Adjustment.
- **Why risky:** Exports and screen: a merge that changes the picture is a silent edit.
- **How:** Hash `flattened()` before and after; allow a rounding tolerance like the thumbnail check's.
- **Tricky:** Not every case promises the same look: Flatten drops hidden layers (by design); Stamp Visible over
  see-through areas stacks the picture on itself, so check its new layer equals the old composite instead; Merge Down
  of a layer onto one with its own blend mode, opacity or mask, and Merge Adjustment with several layers below, may
  change the look by design. **Needs Leah** for which cases must match; the FRD doesn't say for each.

### R9. The document is marked edited exactly when history changes · **High**

- **Missing:** CLAUDE.md: "Mark the document edited only when `history.revision` changed (`Editor.recordingChanges`)".
  Nothing checks that every recorded step calls `onDocumentChange`, or that nothing else does.
- **Why risky:** Lost work: a change that never marks the window edited isn't autosaved and closes without asking.
- **How:** Set `editor.onDocumentChange` to count calls; after each step, the count went up exactly when the
  revision did. Page changes go through `changePages`, which has its own path; check that too.
- **Tricky:** Effects that preview as a step mark edited only at Apply (`decorationPreviewed`), so the check belongs
  after Apply, not after `beginEffect`.

### R10. Locked layers stay as they were · **Medium**

- **Missing:** Lock and Lock Transparent Pixels are toggled, but nothing checks that a locked layer's pixels didn't
  change, or that see-through pixels on a transparency-locked layer stayed see-through.
- **Why risky:** Lost work: the lock is how Leah protects a layer.
- **How:** After each step, compare locked layers' hashes with before. Exceptions: redaction (which ignores the
  transparency lock by design) and whole-picture changes (crop, resize, rotate).

### R11. Text layers after crops and turns · **Medium**

- **Missing:** The text rule only checks upright text with its font. FRD §23: a crop or canvas change that cuts
  through a text layer's box makes it pixels "so cut-off words can't come back"; a stretched resize or skew makes it
  pixels; after Rotate or Flip it stays text but can't be edited until turned back.
- **Why risky:** Secrets (cut-off words coming back) and lost work.
- **How:** After crop, canvas size and resize steps: every remaining text layer's box lies inside the canvas, and
  after a non-uniform resize or skew there are none. After Rotate or Flip, `editText(layerAt:)` on a turned layer
  refuses.

### R12. Internal references stay valid · **Medium**

- **Missing:** No checks that the selection mask is the canvas's size after crops and resizes, that a floating piece
  names a layer that exists, that chosen layer ids (`otherChosenLayerIDs`) all exist, or that nothing is left pending
  after a save.
- **Why risky:** Crashes, usually much later than the step that caused them, which makes them hard to find by hand.
- **How:** Add to `checkDocument`.

### R13. Saved and reopened projects keep everything · **Low**

- **Missing:** `checkSame` and `checkSaving` don't compare the color space, `hasTransparentBackground` or
  `pastedFrom`.
- **Why risky:** CLAUDE.md: "Never silently convert to sRGB." `pastedFrom` is what lets the redaction cleanup offer
  survive a relaunch (review AA, finding 4).
- **How:** Compare them. Also start some episodes in sRGB or another profile instead of always Display P3, and some
  with a transparent background (the known gap), so there's something to keep.

### R14. Page and history thumbnails match · **Low**

- **Missing:** Only the canvas thumbnail is checked, once, at the end. The Page sidebar's thumbnails (`pageThumbnail`,
  parked pages keep theirs) and History step thumbnails are never compared.
- **Why risky:** A wrong thumbnail misleads but loses nothing; a stale parked-page thumbnail could hide a redaction
  that didn't happen, which is why it isn't lower.
- **How:** Compare `pageThumbnail(at:)` for each page with that page's flattened picture, scaled.

---

## Counts

| Priority | Commands | Rules | Total |
|---|---|---|---|
| High | 4 (C1, C2, C3, C12) | 9 (R1, R1b, R2, R3, R4, R5, R6, R7, R9) | 13 |
| Medium | 7 (C4, C5, C6, C7, C9, C10, C11) | 5 (R1c, R8, R10, R11, R12) | 12 |
| Low | 3 (C8, C13, C14) | 2 (R13, R14) | 5 |
| **All** | 14 | 16 | **30** |

C15 lists what can't be covered safely and isn't counted.

---

## The five I'd add first

1. **R1 and R1b with C12 and C11: redaction leaves nothing behind.** Secrets are the worst failure for what Colorbee
   is for, the rules are cheap (search names, text layers and the saved project for words the monkey wrote itself),
   and `forgetHistory` is one direct call. Needs one answer from Leah on snapshots.
2. **R2: every page, not just the one shown.** Pages are where lost work would hurt most, and today the tracker
   forgets everything at each page switch. Keeping a state per page is a small change to `UndoTracker`.
3. **R3: the floating piece and the selection in `documentState`.** A floating piece is the one place pixels live
   outside a layer; adding three fields to the state closes a blind spot in every undo, redo and save check the monkey
   already makes.
4. **R6 with R5: a tiny history budget, and saving in the background while editing.** Disk spill and
   `discardContents` are the most intricate memory code in the app, and today the monkey can't reach them at all.
   Both are lost-work bugs that only show up long after the step that caused them, which is exactly what a monkey is
   good at.
5. **C1: the Retouch tool, with its background landings.** It's a whole tool family the monkey never touches, and its
   Remove, Spot Heal and Match Tone landings are the kind of background-meets-edit timing that earlier reviews found
   bugs in. It also pushes the monkey to learn to wait for, and race, background work properly, which C2 and C10
   then reuse.
