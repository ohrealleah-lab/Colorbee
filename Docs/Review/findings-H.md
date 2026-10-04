# Review H: where the original pixels survive after redaction
Reviewed at commit: fc427a185d70d559a8e27f11b456ceed5833f65c
Checked:
- `ImageDocument.swift`: `autosavesInPlace` (on; `preservesVersions` left at its default, on), saving through `SaveSnapshot`, `canAsynchronouslyWrite`, export and export presets, Share, Print, Set as Desktop Picture
- `SaveSnapshot.swift`, core `ImageCodec.swift`: exports build a fresh `CGImage` from the pixels and write no source metadata, text chunks or thumbnails. The original file's EXIF isn't carried over. Clean.
- `ProjectFile.swift`: stores every pixel layer's rows (LZ4) and settings. No undo data, no thumbnail, no As Opened copy. Hidden layers and layers under adjustment layers are stored in full (finding 4).
- `ClipboardHistory.swift`, `ClipboardImage.swift`, `PasteboardImages.swift`, `DocumentWindow.swift` (copy, cut, paste, Copy Merged, Paste into New Image)
- `Editor.swift`: Auto-Redact (`beginAutoRedact`, apply), Batch Redact (`applySolidFill` and the Blur/Pixelate effects), Before/After (`asOpened`, `lastSaved`), Revert Layer (`savedLayers`). The last three are memory only; they go when the window closes.
- `HistoryPanels.swift`: step thumbnails, including "Opened", are memory only.
- Core `History.swift`: the spill file (finding 5)
- Core `AutoRedact.swift`, `AutoRedact+Apply.swift`, `Effects.swift`: strengths. Blur at sigma `max(6, height/3)` and Pixelate at the same cell size turn a line of text into a smear or about three cells per line height. I don't see a way to read that back by sharpening. Pixelate is partly reconstructable for short known strings, and the sheet already warns about this (§23). Solid Fill replaces pixels outright, with alpha included, on every pixel layer with anything under the box. A layer below 100% opacity or in a blend mode still shows the fill color mixed, but none of the original pixels.
- `Subjects.swift` (Remove Background), `RoundBrushStroke.swift` and `CoveragePainter.swift` (the eraser writes `.clear` or Color 2 outright), `FloatingSelection.swift` (Delete and Cut leave `.clear`)
- `Diagnostics.swift`: timings only, no image content or text
- `Info.plist` (from `project.yml`): no sandbox, so every file below is readable by any app the user runs

Not re-reported: rounds 1 and 2 in `RESULTS.md`.

**Hand-tested by Leah on 2026-10-04:**
- **Finding 1:** confirmed through File ▸ Revert To ▸ Browse All Versions: after Auto-Redact and ⌘S, the earlier version shows the unredacted screenshot. (Her Revert To menu has no "Last Opened" item.)
  - She also noticed that while Browse All Versions is open, the current image can still be drawn on. That makes it easy to change the image by accident without noticing.
  - The current document being editable in the Versions browser is standard macOS behavior. But together with review J finding 1 (restoring a version leaves the window on a copy that's no longer saved), it's riskier in Colorbee. Worth deciding whether the canvas should refuse edits while the Versions browser is open.
- **Finding 2:** Colorbee **crashed** while following the steps. The crash is being fixed in another session. The finding itself (the original stays in Clipboard History) still needs checking once the crash is fixed.
- **Findings 3 and 4:** confirmed.
- **Findings 5–7:** not hand-tested; left to the engineer.

**Leah's decisions (2026-10-04), for the FRD §23 log:**
- **Finding 1 (Versions):** warn. After a redaction is saved, tell the user that earlier versions of the file still show the unredacted image. Don't remove them automatically.
- **Finding 2 (Clipboard History):**
  - Add a per-item Remove.
  - After Auto-Redact (and Batch Redact) is applied, offer to clear the matching Clipboard History items. Clearing is the default, and the user can choose not to.
- **Finding 3 (Batch Redact):** Batch Redact covers all layers, like Auto-Redact.
- **Finding 4 (hidden layers):**
  - Auto-Redact keeps scanning visible layers only, and says so in the sheet ("Only visible layers were checked").
  - Hiding a layer is how a user opts that part out of redaction.

Test image for most findings: **E1 Screenshot.png** from review E (any screenshot with an email address or API key in it works).

## 1. File ▸ Revert To brings back the unredacted image after redacting and saving
- **Severity:** High (the secret is one menu click away on this Mac, for the user or anyone using their account; it doesn't travel with a file that's sent, since Versions stay on the Mac)
- **Confidence:** High on what macOS does. It's standard `NSDocument` behavior, and Colorbee does nothing to change it.
- **Where:** `Sources/Colorbee/ImageDocument.swift:32` (`autosavesInPlace` returns true; `preservesVersions` isn't overridden, so it's true). Nothing anywhere calls `NSFileVersion`.
- **What happens:**
  - A document that autosaves in place gets versions from macOS. A version is kept when the file is opened, on each explicit Save, and periodically while autosaving. They live in the volume's hidden `.DocumentRevisions-V100` store.
  - Opening a screenshot, Auto-Redacting it and saving overwrites the file. But **File ▸ Revert To ▸ Last Opened** (and Browse All Versions) still has the original, readable screenshot, and restores it or lets the user copy from it.
  - The versions stay until the file is deleted or macOS prunes them. FR-12 requires Browse All Versions to work, so this is a conflict between two requirements.
- **How to trigger it:**
  1. Duplicate E1 Screenshot.png in Finder, and open the copy in Colorbee.
  2. Effects ▸ Auto-Redact…, choose Solid Fill, and Apply.
  3. ⌘S, then close the window and reopen the file. The redaction is there.
  4. File ▸ Revert To ▸ Last Opened (or Browse All Versions…). The unredacted screenshot is shown, and can be restored.
- **Why:** Versions are a macOS feature that Colorbee inherits by autosaving in place. Nothing removes old versions after a redaction is saved.
- **Test that would catch it:** By hand only (Versions need a real file on a real volume). Leah's decision; options:
  - (a) After a save that contains an Auto-Redact or Batch Redact step, call `NSFileVersion.removeOtherVersionsOfItem(at:)`.
  - (b) Ask on that save ("Remove earlier versions of this file? They still show the unredacted image.").
  - (c) Keep Versions and mention them in the Auto-Redact sheet.

## 2. Clipboard History keeps the original screenshot after it's redacted
- **Severity:** High (the screenshot stays on disk and one click away in the sidebar, for up to 10 more copies or pastes, across relaunches)
- **Confidence:** High
- **Where:** `Sources/Colorbee/ClipboardHistory.swift:29` (folder `~/Library/Application Support/Colorbee/Clipboard History/`), `:40-56` (`add`, capacity 10), `:77` (`clear`, the only way to remove items; there's no per-item remove)
- **What happens:**
  - The FRD's main workflow is: screenshot to the clipboard, Paste into New Image, redact, share (§499; AC-25).
  - Every paste is added to Clipboard History as a `<uuid>.image` file, so the unredacted screenshot is stored before redaction starts. Redacting the document doesn't touch it.
  - It stays until 10 newer images push it out or the user clicks Clear, which removes everything. It survives quit and relaunch.
  - Copying the redacted result adds a second item, so the redacted and unredacted copies sit side by side.
  - Any app on the Mac can read the folder (no sandbox).
- **How to trigger it:**
  1. Open E1 Screenshot.png in Preview, ⌘A, ⌘C. Or take a screenshot to the clipboard with ⌃⇧⌘4.
  2. In Colorbee, Edit ▸ Paste into New Image (⇧⌘V).
  3. Effects ▸ Auto-Redact…, Solid Fill, Apply.
  4. Open the Clipboard History panel (⌥⌘V). The top thumbnail is the unredacted screenshot. Click it: it pastes back, readable.
  5. Quit and relaunch: it's still there. In Finder, Go ▸ Go to Folder… `~/Library/Application Support/Colorbee/Clipboard History` and the `.image` files are there.
- **Why:** Clipboard History is a separate store that redaction doesn't know about.
- **Test that would catch it:** Leah's decision on behavior. Options:
  - (a) A per-item "Remove" (right-click on a thumbnail).
  - (b) Applying Auto-Redact offers to remove the history items that match the document's As Opened image.
  - (c) A setting to keep Clipboard History in memory only.
  - Whichever is chosen, a test: add an item, remove it, and expect its file to be gone from the folder.

## 3. Batch Redact changes only the active layer, unlike Auto-Redact
- **Severity:** Medium (the user sees the secret blurred on screen only if it's on the active layer; otherwise nothing visible changes, but there's no message, and in other cases a top layer gets redacted while the secret stays on the layer below)
- **Confidence:** High on the behavior; whether it should match Auto-Redact is Leah's call
- **Where:** `Sources/Colorbee/Editor.swift:2197-2206` (`applySolidFill` works on `canvas.activeLayer`); `MainMenu.swift:326-330` (Batch Redact ▸ Blur… and Pixelate… open the ordinary effects, which apply to the active layer, FR-9.2)
- **What happens:**
  - Round 2 (review E) changed Auto-Redact to redact every layer with pixels under each box, because a secret is often on a different layer from the one selected.
  - Batch Redact, the manual route to the same goal, still follows the effects rule: active layer only. With text on the background and an empty or annotation layer active, Batch Redact ▸ Pixelate changes the wrong layer.
  - A semi-transparent annotation layer active (a highlighter over the email): Pixelate scrambles the highlight and leaves the text underneath readable.
- **How to trigger it:**
  1. Open E1 Screenshot.png. Layer ▸ New Layer (the new empty layer is active).
  2. Drag a marquee around the email address.
  3. Effects ▸ Batch Redact ▸ Solid Fill with Color 1. The email is still readable; the fill went on the new layer. With Pixelate…, nothing visible changes at all.
  4. Hide the new layer: the original is untouched below.
- **Why:** Batch Redact reuses the effect commands, which target the active layer.
- **Test that would catch it:** If Leah wants Batch Redact to match Auto-Redact: an Editor-level test with two layers, text on the lower one and the upper one active. Marquee, Batch Solid Fill, then expect the lower layer's pixels in the box to be Color 1. Alternatively, keep it per-layer and show "Batch Redact changes only the active layer" in the bar when other layers have pixels in the selection.

## 4. Text that isn't visible isn't found, and survives in a saved project
- **Severity:** Medium (a `.colorproj` sent to someone carries the secret; image files are safe since they hold only what's visible)
- **Confidence:** High
- **Where:** `Sources/Colorbee/Editor.swift:2609-2639` (`beginAutoRedact` scans `copy.value.flattened()`, which includes only visible layers, `Canvas.swift:274-279`); `ProjectFile.swift:49-65` (stores every pixel layer, hidden or not)
- **What happens:** Auto-Redact reads what's on screen. These are never scanned, and so never redacted:
  - text on a hidden layer
  - text covered by an opaque layer above it
  - text on a layer at 0% opacity
  - text made unreadable on screen by an adjustment layer above it (for example Levels crushed to black)

  A project saved afterwards keeps it all. The sheet's "No matches found" reads as "this image is clean".
- **How to trigger it:**
  1. Open E1 Screenshot.png. Layer ▸ New Layer, then fill the new layer white with the Fill tool (it covers everything).
  2. Effects ▸ Auto-Redact…: nothing is found.
  3. File ▸ Save As…, choose the Colorbee project format, and save.
  4. Reopen the project and hide the white layer: every secret is intact. (A hidden layer is the same: hide the original layer, add a layer with some text, Auto-Redact, save as project.)
- **Why:** Scanning flattens visible layers only. That's right for what the image shows, but a project carries more than that.
- **Test that would catch it:** Leah's decision. Options: scan each pixel layer separately (hidden ones too) and merge the boxes; or, when the document has hidden, covered or adjusted layers, show "Only visible layers were checked" in the sheet. Core test for the first: two layers, text on the lower one, an opaque layer above; expect matches.

## 5. The undo history's spill file is left in the temporary folder after a crash or quit
- **Severity:** Low (only for large edits; the folder is private to the user's account, but readable by any app they run, and it's never cleaned up if Colorbee doesn't exit tidily)
- **Confidence:** Medium. `deinit` doesn't run when the process exits, so whether the file goes on a normal quit depends on whether the History is torn down before exit. It isn't deleted after a crash or force quit.
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/History.swift:655-666` (`SpillStore` makes `$TMPDIR/colorbee-history-<UUID>.bin` and removes it only in `deinit`)
- **What happens:**
  - Once history passes its byte budget (the smaller of 512 MB and 10% of RAM), older steps' before-images go to this file: LZ4-compressed tiles, plus whole layers that were deleted, merged or replaced by a crop or resize.
  - That's exactly where the pre-redaction pixels end up. LZ4 isn't encryption; the tiles decompress to plain BGRA.
  - macOS clears `$TMPDIR` only after about three days without access, or at restart.
- **How to trigger it:**
  1. On a big image (8000 × 8000, or a 4K screenshot), make many large edits: Blur the whole image several times, crop, and so on.
  2. Quit with Activity Monitor ▸ Force Quit (or quit normally).
  3. In Terminal: `ls -la "$TMPDIR" | grep colorbee-history`. A leftover `.bin` file confirms it.
- **Why:** The file is deleted only by `deinit`.
- **Test that would catch it:** Unlink the file right after opening it: `FileHandle` keeps working on macOS, and the file disappears as soon as the process ends, crash or not. Test: create a `SpillStore`, write to it, then expect `FileManager.fileExists(atPath:)` to be false while reads still work.

## 6. Share's temporary PNG and old desktop pictures are never deleted
- **Severity:** Low
- **Confidence:** High
- **Where:** `Sources/Colorbee/ImageDocument.swift:160-170` (`shareDocument` writes `$TMPDIR/Colorbee Share <UUID>/<name>.png`), `:189-199` (`setDesktopPicture` writes `~/Library/Application Support/Colorbee/Desktop Pictures/<name> <stamp>.png`)
- **What happens:**
  - Each Share writes a PNG of the combined image to a new temporary folder and leaves it there. Sharing before redacting (or sharing the unredacted copy by mistake) leaves a readable copy in `$TMPDIR` until macOS clears it.
  - Each Set as Desktop Picture adds a new PNG to Application Support, and none are ever removed. §23 (stage 7a) says the copy is kept there, which is needed while it's the desktop picture, but the older ones pile up with whatever they showed.
- **How to trigger it:**
  1. Open E1 Screenshot.png and choose File ▸ Share… and then cancel (or share to Notes).
  2. In Terminal: `ls "$TMPDIR" | grep "Colorbee Share"`. The folder and PNG are there.
  3. Set as Desktop Picture twice with different images, then in Finder, Go ▸ Go to Folder… `~/Library/Application Support/Colorbee/Desktop Pictures`. Both PNGs are kept.
- **Why:** Neither path cleans up after itself.
- **Test that would catch it:** Remove the Share folder when the share sheet finishes (`NSSharingServicePickerDelegate` / the service's did-share or did-fail callbacks), and delete older files in Desktop Pictures when a new one is set. A unit test on a helper that prunes the Desktop Pictures folder to the newest file.

## 7. Remove Background keeps the background's colors hidden in the transparent pixels
- **Severity:** Low (Remove Background isn't a redaction command, but it's natural to use it to "get rid of" what's behind someone, such as a room or a desk; anyone with an image editor can turn the alpha back up)
- **Confidence:** High for `.colorproj` and for a PNG export of a single-layer image; Medium on exactly what ImageIO writes for the alpha-0 pixels
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/Subjects.swift:110-121` (`apply` scales only `row[x].a`, leaving RGB); `Canvas.swift:276-277` (one visible layer at full opacity: `flattened()` returns a plain copy of the buffer); `ImageCodec.swift:116` (writes straight alpha, `CGImageAlphaInfo.first`); `ProjectFile.swift:123-128` (raw rows)
- **What happens:**
  - Remove Background (and Lift Subject's new layer) set the background's alpha to 0 but keep its red, green and blue values.
  - Saved as a project, or exported as PNG while it's the only layer, the file holds the full original background. Making it opaque again (in any editor that can set alpha, or a few lines of code) brings it back.
  - With several layers, flattening goes through `Compositing.pixel`, which writes `.clear` for alpha 0, so the leak happens only with one layer.
  - The eraser, Delete and Cut write `.clear` or Color 2, so they don't leak.
- **How to trigger it:** Hard to show by hand without a tool that edits alpha directly (Preview premultiplies, which hides it). The engineer can confirm with the test below. By hand, if the Mac has Python with Pillow: Remove Background on a photo, export PNG, then `python3 -c "from PIL import Image; im=Image.open('x.png'); im.putalpha(255); im.save('y.png')"` and open y.png.
- **Why:** Scaling alpha alone is how soft edges are kept, but at alpha 0 there's nothing to keep.
- **Test that would catch it:** Core test: a 2 × 1 buffer, mask `[0, 255]`. After `removeBackground`, expect pixel 0 to equal `Pixel.clear` exactly. Fix: write `.clear` when the new alpha is 0. (Possibly also zero RGB in `ProjectFile.rows` and `ImageCodec.encode` for every alpha-0 pixel, which covers any other path.)
