# Review N: privacy, redaction and saved data (round 5)
Reviewed at commit: eccf0c1571ac06e5470b598048ab6c2e3309093b
Checked:
- Soft selections and every redaction path: Batch Redact (Blur…, Pixelate…, Solid Fill), the Redact Brush, Auto-Redact; `SelectionMask` (`hardened`, `feathered`, `combine`, `connectedRegions`, `inverted`); `Effects.weight` and `mixed`; `Pixel.taking` and `vacated`; Delete and Cut on soft selections (they follow the soft edge on purpose, FR-3.4, so not reported).
- Redact Brush (`RedactBrushArea`, `beginRedactStroke` … `endRedactStroke`): hard edge, every layer with pixels (hidden ones too), locked layers and the message, Shift, strokes starting off the canvas or crossing its edge, one undo step, Blur/Pixelate strength, the after-redaction offers (same as Batch Redact), and the overlay (never in the canvas; `finishInteractions` applies a stroke before Copy, Save, Export and page changes).
- Copy Text (`copyText`, `TextReader`): reads visible layers of the page shown only, nothing kept afterwards.
- Layer storage (`LayerPixels`, `ProjectFile` pieces, `Page.park`/`unpark` and `unparkedFrom`): size checks before use, end marker, the spare byte, truncated and damaged pieces, old one-stream files, reuse of parked bytes only when the page's history revision, active layer and floating selection are unchanged. No problem found.
- `PageStack.insert(_:at:named:)` and its undo; `importPages`; `ContinuityImport` and `PDFPages.scannedPage`: no camera details, location or device data are carried into the canvas; Colorbee writes no temporary files for imports.
- Pending objects (shape, text, Step Badge) across Save, autosave, Export, Export As presets, Export as PDF, Copy, Copy Merged, Copy Text, Share, Print and Set as Desktop Picture: consistent (placed first; autosave leaves them alone, as decided).
- `History` changes since round 4, `ImageDocument`/`SaveSnapshot` changes, `DocumentView` notice and Feather sheet.

Two serious problems: Batch Redact's Blur and Pixelate soften the redaction on a feathered selection, and every save, autosave and export drops "Only the layer below".

**Leah confirmed findings 1 and 2 by hand (2026-10-11).**

## 1. Batch Redact ▸ Blur… and Pixelate… only half-redact a feathered (soft) selection
- **Severity:** Critical (a secret left partly visible)
- **Confidence:** High
- **Where:** `Sources/Colorbee/Editor.swift:2441` (`effectRegions = canvas.selection.marquee?.connectedRegions()`), used at `Editor.swift:2896–2899` (`renderEffectPreview`) and committed by `applyEffect` (`Editor.swift:3111–3116`); `Packages/ColorbeeCore/Sources/ColorbeeCore/Effects.swift:200` (`mixed(…, weight(selection, x, y))`).
- **What happens:** FR-3.4 says "Redaction is never softened. Batch Redact and the Redact Brush treat any partly selected pixel as fully selected." Batch Redact ▸ Solid Fill does this (it goes through `AutoRedact.apply`, which calls `soft.hardened()` at `AutoRedact+Apply.swift:30`). But Batch Redact ▸ Blur… and Pixelate… go through the ordinary effect session (`beginBatchRedact` → `beginEffect(…, coveringAllLayers: true)`), which never hardens the mask. Each pixel is mixed between its original and its redacted value by how selected it is. Inside a feathered box, within about the feather radius of the outline, the text shows through at roughly half strength or more; just outside the outline (still faintly selected) it's almost untouched. With a soft selection from Select Subject or Invert Selection the same happens along the soft edge.
- **How to trigger it:** Any feathered selection (palette bar Feather, Edit ▸ Feather…, Select Subject), then Effects ▸ Batch Redact ▸ Blur… or Pixelate…, Apply.
- **Why:** `connectedRegions()` keeps the soft values ("Each region keeps its soft edge", tested in `SoftSelectionTests`), and `applyToRegion` writes `mixed(destination[x], source[…], weight(selection, x, y))`. The core test `batchRedactHidesEveryPartlySelectedPixelCompletely` only covers `AutoRedact.apply`, which the Blur and Pixelate menu items don't use.
- **Test that would catch it:** An app test: feathered rectangle selection over a patterned area, `beginBatchRedact(.pixelate)`, `applyEffect()`; every pixel with mask value > 0 must equal the result of the same Pixelate with the hardened mask (and the same for Blur).
- **Steps for Leah** (test file: `TestImages/Help/Sample Screenshot.png`):
  1. Open `TestImages/Help/Sample Screenshot.png`.
  2. Pick the Rectangle Select tool. In the palette bar, set **Feather** to 20 px.
  3. Draw a selection box snugly around the made-up email address.
  4. Choose Effects ▸ Batch Redact ▸ Pixelate…, then click Apply.
  5. Zoom in (400%) on the email. **Expected:** the whole address is solid blocks. **Bug:** the letters show through the blocks all along the address (a box only a little taller than the text is never fully selected anywhere with a 20 px feather), most strongly near the box's edges; the first and last letters may still be readable.
  6. Undo (⌘Z) and try Effects ▸ Batch Redact ▸ Blur… instead: the same ghosting. For comparison, Effects ▸ Batch Redact ▸ Solid Fill with Color 1 on the same selection hides it all.

## 2. Saving, autosave, Export, Copy, Share and Duplicate Page all drop "Only the layer below"
- **Severity:** Critical (saved work changed; exports don't match the screen)
- **Confidence:** High
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/Canvas.swift:52–67` (`Canvas.copy()`); used by `Sources/Colorbee/Editor.swift:3943` (`saveSnapshot`, behind ⌘S, autosave, Export…, Export As presets, Export as PDF, Share, Set as Desktop Picture and Copy with nothing selected at `DocumentWindow.swift:94`), `Editor.swift:746` (`duplicatePage`), `Editor.swift:3656` (Auto-Redact reading the page shown) and the "As Opened" baselines at `Editor.swift:670`, `814` and `3147`.
- **What happens:** `Canvas.copy()` copies each layer's name, visibility, opacity, blend mode, lock and adjustment, but not the new `clipsToLayerBelow`. Every save and export is made from such a copy, so in the file every "Only the layer below" adjustment changes everything below it again:
  - A .colorproj saved with ⌘S, or autosaved, is written without `"clipped"`. Reopening it (or a relaunch, or File ▸ Revert To) shows the adjustment over the whole image, and the switch is off. Since autosave writes in place, just editing and closing the window is enough to lose it.
  - Exports (PNG, JPEG, PDF), Share, Set as Desktop Picture and ⌘C with nothing selected show the wrong look. (Print happens to be right: `flattenedPNG` doesn't copy the canvas.)
  - Duplicate Page makes a page that looks different from the original.
  - Auto-Redact reads the page shown from a copy, so it reads a different picture from the one on screen. A clipped Brightness/Contrast or Levels on one layer becomes a whole-page wash-out, which can hide text from Vision so it isn't offered for redaction. This is the privacy side of the same bug.
  - Other pages keep the setting (they're parked with `ProjectFile.encode` on the page itself), so a multi-page project loses it only on the page that was shown.
- **How to trigger it:** Any document with an adjustment layer set to "Only the layer below", then Save, Export, Copy or Duplicate Page.
- **Why:** `Canvas.copy()` sets `isVisible`, `opacity`, `blendMode`, `isLocked` and `adjustment`, but not `clipsToLayerBelow`. `ProjectFile.encode` writes `entry.clipped` only when `layer.clipsToLayerBelow` is true. `ClippedAdjustmentTests.theSettingIsSavedInAProject` encodes the canvas itself, not the copy the app saves, so it passes.
- **Test that would catch it:** Core: `canvas.copy()` keeps `clipsToLayerBelow` (and, more generally, a copy's layer records `matches` the original's). App: `saveSnapshot().encodedProject()` decoded again has the clipped flag, and `saveSnapshot().canvas.flattened()` equals `canvas.flattened()`.
- **Steps for Leah** (test file: `TestImages/Stage 9 Practice Photo.png`):
  1. Open `TestImages/Stage 9 Practice Photo.png`.
  2. Layer ▸ New Layer. With the Brush, paint a large blob of color in the middle.
  3. Layer ▸ New Adjustment Layer ▸ Invert. The whole photo is inverted.
  4. In the Layers panel, turn on **Only the layer below**. Now only the blob is inverted; the photo looks normal.
  5. Edit ▸ Copy (⌘C) with nothing selected, then Edit ▸ Paste into New Image (⌘⇧V). **Expected:** only the blob inverted. **Bug:** the whole photo is inverted.
  6. Back in the first window, File ▸ Save (it saves as a .colorproj), close the window, then reopen it from File ▸ Open Recent. **Bug:** the whole photo is inverted again, and the switch is off.

## 3. Text from Copy Text stays on the clipboard after a redaction, with no offer to remove it
- **Severity:** Low (Leah's call: it may be fine as it is)
- **Confidence:** Medium (that this is unwanted)
- **Where:** `Sources/Colorbee/Editor.swift:2631–2646` (`copyText`), `Editor.swift:3157` (`noteRedaction`), `DocumentWindow.swift:191` (writes the text to the clipboard).
- **What happens:** After a redaction, Colorbee offers to remove the Clipboard History images this document came from or was copied to (review H2, K11), and clears the clipboard if it holds one. Text from Copy Text isn't part of this. Copy Text, then redact the email: the email is still on the clipboard as text, and Universal Clipboard can hand it to Leah's iPhone or iPad. Also, Copy Text runs in the background: if a redaction is applied while "Reading text…" shows, the unredacted text lands on the clipboard *after* the redaction.
- **How to trigger it:** Copy Text on an image with a secret, then any redaction.
- **Why:** `noteRedaction` looks only at `clipboardSources` (Clipboard History image ids); `copyText` records nothing, and its task doesn't check whether the image changed while it read (Remove Red-Eye's task does, with `history.revision`).
- **Test that would catch it:** An app test that Copy Text followed by a redaction reports the copied text in the cleanup offer (if Leah wants that), and that a read finishing after `history.revision` changed doesn't copy (or says the image changed).
- **Steps for Leah** (test file: `TestImages/Help/Sample Screenshot.png`):
  1. Open `TestImages/Help/Sample Screenshot.png`.
  2. Edit ▸ Copy Text (⌘⌥C). Wait for "Copied … words".
  3. Effects ▸ Auto-Redact…, keep everything ticked, Solid Fill, Apply.
  4. Open TextEdit and paste (⌘V). **What you'll see:** the made-up email, phone number and API key paste as text. No message mentioned them.

## 4. Once importing into an open document works: imported pages can miss Auto-Redact, and their "As Opened" can be wrong
- **Severity:** Low (only reachable after the pinned stage 11 problem is fixed)
- **Confidence:** Medium
- **Where:** `Sources/Colorbee/Editor.swift:751–759` (`importPages`), `Editor.swift:812–817` (a page shown for the first time gets "As Opened" = as it is now).
- **What happens:** STATUS pins importing into an open document as not working yet, so this can't be tried by hand today. These are for when it's fixed:
  - `importPages` refuses only while Auto-Redact is *applying* (`isRedacting`). A scan that arrives while the Auto-Redact review is open (the phone can take a minute, so the request can be made before the sheet opens) is added as new pages the session never read. Apply checks only the pages it read, so it redacts those and closes, and the scanned pages keep their secrets though the sheet said every page was checked. Batch Redact's or any effect's bar would simply be cancelled by `changePages`.
  - Imported pages after the first get no `pageMemory`, so if Auto-Redact redacts one before it's ever shown, its "As Opened" (Before/After) becomes the redacted page, as in review K, finding 4.
- **How to trigger it:** Import from iPhone into an open document while the Auto-Redact review is open; or import several scans, run Auto-Redact on every page, then view a scan page that wasn't shown and use Before/After ▸ As Opened.
- **Why:** `guard !stored.isEmpty, !isRedacting` rather than `autoRedact == nil`; `PageMemory` is made only in `init(pages:)`.
- **Test that would catch it:** App tests: `importPages` with `autoRedact` set is refused (or the session is cancelled with a message); an imported page redacted before it's shown keeps its imported pixels as "As Opened".
- **Steps for Leah:** None yet (blocked by the pinned import problem).
