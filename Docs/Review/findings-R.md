# Review R: everything since round 5 (round 6)
Reviewed at commit: 12020b4f2d956ced1487b153023d6fc8bb351567
Checked:
- Round 5 fixes: `StraightenPlan.render(isCancelled:)` and Editor's `straightenWork` wait; `LayerActions` (New, Duplicate, Delete, Merge Down with clipped adjustments), `Canvas.indexAboveActiveLayer`, `Canvas.copy()`, `pixelAsShown`; Sample All Layers (`composited(through:)`); `MatchSurroundings` size limit and `NothingToFillFrom`; `Compositing.lerp` and its five callers; `RetouchStroke` Blur, Sharpen and the new `toneReference`; `SmudgeStroke` premultiplied paint and edge pickup; soft Red-Eye; `SelectionMask.feathered` row copy; the Feather sheet's background preview, text box and OK; `ToneMatch.plan`/`apply` and `Editor.matchTone`; `stopFillForChange`; Copy Text's revision guard and `ClipboardHistory.clearClipboard(ifUnchangedSince:)`; the after-redaction offer (`ClipboardCleanup`, DocumentView alert); Batch Redact hardened regions.
- Menus: `MainMenu` (Redact menu, section header, moved items), `DocumentWindow.validateMenuItem`, `ShortcutStore` ids (selector based, so moved items keep saved shortcuts; the section header has no action and is skipped), `HelpDump`.
- Toolbar and palette bar: `DocumentToolbar` capsules and `hiddenKeepingSpace`, swap arrow, `PaletteBar` 4-slot layout, `CustomColors.unpacked` migration and palette loading, `Renderer` shadow and `topOverlay`, `shadow_fragment` (display only: never in exports, copies or Before/After's "before" side).
- Help: `HelpBook.swift`, the ? buttons, `NSHelpManager.registerBooks`, `TestHost.application(_:open:)`.
- Paste into New Image with no window: `AppDelegate.pasteIntoNewImage` and its `validateMenuItem`, `DocumentWindow.openClipboardImage`.
- iPhone import removal: no `ContinuityImport`, `validRequestor` or menu item is left; the only leftover is `ImageDocument.open(_ stored:)` (`ImageDocument.swift:43`), now unused, with a comment still citing FR-11.7. Harmless; not listed as a finding.
- CI and release: `build-release.yml` (pinned checkout, `-T /usr/bin/codesign`, early keychain removal, `gh release create`), `make-beta.sh`, `help-pages.py`, `help-shots.sh`. Nothing prints a secret; no third-party action runs after checkout.

## 1. A big Clone Stamp stroke's Match Tone lands in the middle of the next edit: undo and Cancel lose it, and it cancels a Remove
- **Severity:** Critical (undo isn't exact)
- **Confidence:** High
- **Where:** `Sources/Colorbee/Editor.swift:1737-1759` (`matchTone`), with `Editor.swift:2298-2308` (`recordingChanges` → `stopFillForChange`) and `Packages/ColorbeeCore/Sources/ColorbeeCore/History.swift:107` (`Edit.restoreOriginals`)
- **What happens:** For a stroke whose Match Tone reads over 250,000 pixels, the tone is worked out in the background and then written straight into the active layer, folded into the stroke's step. The only check before writing is that `history.revision`, the page and the active layer haven't changed. Starting another edit doesn't change the revision until that edit ends, so the tone can land in the middle of it:
  - **Another stroke** (Pencil, Brush, another Clone Stamp…) started before the tone lands has already saved "before" copies of the 256-px tiles it touched, from before the tone. Undoing that stroke puts those tiles back without the tone, so the tone vanishes in square blocks while it stays everywhere else. Undo and Redo then don't return the image to what it was.
  - **An effect's preview** (Gaussian Blur…, Levels…, Batch Redact ▸ Pixelate…, any effect with a bar) works from the pixels as they were when it opened. The next preview update, **Cancel**, or **Undo** after Apply puts back the pre-tone pixels, so the matched tone silently disappears, though the step is still called "Clone Stamp" and Redo doesn't bring it back.
  - **A Remove (or Spot Heal) fill** that's running is cancelled, because the tone's commit goes through `recordingChanges`, which calls `stopFillForChange()`: "The image changed while filling. Try again." The user didn't change anything.
  Nothing uses `isMatchingTone` to hold off other edits (only the tests read it).
- **How to trigger it:** the tone takes about a second or more on a big stroke, so these are easy by hand. Test file: `TestImages/Stage 9 Practice Photo.png`.
  *Cancel loses the tone:*
  1. Open the photo. Choose the Retouch tool ▸ Clone Stamp. Set Size to 300 and turn on Match Tone.
  2. Option-click somewhere bright (the sky), then paint one long zigzag stroke across a darker part of the photo, covering most of it.
  3. As soon as you let go, choose Effects ▸ Gaussian Blur….
  4. Wait 3 seconds, then click Cancel.
  5. Expected: the stroke keeps its matched (blended) tone. Actual: the stroke shows its unmatched, bright copied tone, as if Match Tone were off. Edit ▸ Undo then Redo: still unmatched.
  *Undo leaves blocks:*
  6. Repeat steps 1–2 on a fresh copy. As soon as you let go, pick the Pencil and scribble slowly across the stroke for 3 seconds.
  7. Edit ▸ Undo (the Pencil). Expected: the stroke as it was, all evenly matched. Actual: square blocks where the stroke has lost its matching, where the Pencil started before the tone landed.
  *Remove is cancelled:*
  8. Repeat steps 1–2. As soon as you let go, choose Retouch ▸ Remove and paint over a small object, then let go.
  9. Expected: the object is removed. Actual: "The image changed while filling. Try again." and nothing is removed.
- **Why:** `matchTone` checks `self.history.revision == revision` and then does `history.beginEdit` → `ToneMatch.apply(plan, to: canvas.activeLayer, …)` → `commit(edit, mergingIntoPrevious: true)` with no regard for `retouchBrush`, `strokes`, `effectEdit` or `fillCancel`. The open edit's snapshots, and `effectEdit.restoreOriginals()`, hold the pre-tone pixels.
- **Fix idea (for the engineer):** when the result arrives, drop it (with the existing "The image changed…" notice) if any edit or session is open (a stroke, an effect or canvas tool, a fill, a pending shape or text), or have `finishInteractions()`/`beginEffect`/`beginRetouchStroke` wait for or cancel a pending tone first. Either way, a tone merge mustn't call `stopFillForChange()`.
- **Test that would catch it:** app test with `backgroundToneArea` lowered: end a Clone Stamp stroke with Match Tone, begin a Pencil stroke over it, let the tone land, end the Pencil stroke, undo once; the image must equal the image right after the tone landed. A second test: open Gaussian Blur before the tone lands, Cancel after; the layer must equal stroke + tone, or stroke alone with the tone not merged into history. A third: start a Remove fill before the tone lands; the fill must finish.

## 2. Match Tone turns the Clone Stamp's copy dark on an empty layer (Sample All Layers) or over see-through pixels
- **Severity:** High (wrong result the user sees)
- **Confidence:** High
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/RetouchStroke.swift:74-87` (`toneReference`) and `:304` (`offsets[index] = before − copied`); applied at `:353-366`
- **What happens:** The help's own advice ("add an empty layer above the photo and turn on Sample All Layers") gives a dark, almost black patch as soon as Match Tone is on. Match Tone measures the difference at the stroke's edge as "what was there before minus what was copied", using only the color numbers. On an empty layer, "before" is see-through black (0, 0, 0), and what was copied is the photo's color, so the correction is "minus the whole color". Adding it back pulls the copy to black, with only the copied texture left. Painting over a see-through part of any layer (a cut-out, a pasted screenshot with a transparent edge) does the same at those pixels. The same mistake was in the measure before the soft-brush change (it averaged the see-through black around the stroke), so this isn't new, but it was never reported, and the new `toneReference` code repeats it.
- **How to trigger it:** `TestImages/Stage 9 Practice Photo.png`.
  1. Open the photo. Layer ▸ New Layer.
  2. Choose Retouch ▸ Clone Stamp, size 60. Turn on Sample All Layers and Match Tone.
  3. Option-click a plain area, then click once somewhere else (one dab).
  4. Expected: a copy that blends into the photo around it. Actual: a dark, nearly black disc.
  5. Turn Match Tone off and click again: the copy looks right, which shows it's Match Tone.
- **Why:** `before.append(painter.original(atX:y:))` reads the active layer (transparent), while `copied.append(transform(x, y, original))` reads `source`, the composite of the layers below. `rgb()` ignores alpha, so `rgb(before) − rgb(copied) = −copied`. With Sample All Layers, "before" should be what was shown there (the same composite the copy came from), and in general a pixel with little or no alpha shouldn't count toward the edge difference.
- **Test that would catch it:** core test: an empty layer above a mid-gray layer, a Clone Stamp stroke with `source` set to the composite and Match Tone on; the painted pixels must stay close to mid-gray (not near 0). Also a stroke over a transparent hole in a layer with no `source`: the pixels must not darken toward black.

## 3. View menu checkmarks go stale while an effect's bar, a sheet or a text box is open
- **Severity:** Low (minor)
- **Confidence:** High
- **Where:** `Sources/Colorbee/DocumentWindow.swift:340-349` (the early returns), with the `.state` lines at `:399-427`
- **What happens:** Rulers, Status Bar, Pixel Grid, Layers, Adjustments, History, Clipboard History and Page Sidebar all still work while an effect's bar (or Auto-Redact, Resize and Skew, Canvas Properties, Feather) is open, or while you're typing text. But validation returns early for these "viewing commands" before it sets their checkmark, so the menu keeps whatever checkmark it had last time. Since the menu reorder, Rulers and Status Bar show a checkmark instead of "Show"/"Hide", so the stale state now shows on those two as well.
- **How to trigger it:** `TestImages/Help/Sample Screenshot.png`.
  1. Open the image. Make sure View ▸ Rulers has a checkmark (rulers showing).
  2. Choose Effects ▸ Gaussian Blur….
  3. Press ⌘R. The rulers disappear.
  4. Open the View menu. Expected: Rulers has no checkmark. Actual: Rulers is still checked.
- **Why:** `if editor.blocksDocumentCommands { return Self.viewingCommands.contains(menuItem.action) || … }` (and the same for `CanvasTextView`) exits before the `switch` that sets `menuItem.state`.
- **Test that would catch it:** app test (no window): with an effect open, toggle rulers, validate the Rulers menu item, and expect `.off`.

## 4. A big Clone Stamp stroke still pauses the app when it ends, before the background Match Tone starts
- **Severity:** Low (minor; performance)
- **Confidence:** Medium
- **Where:** `Sources/Colorbee/Editor.swift:1718` → `Packages/ColorbeeCore/Sources/ColorbeeCore/RetouchStroke.swift:74-87` (`toneReference`), on the main thread
- **What happens:** Review O finding 13 moved Match Tone off the main thread, but the soft-brush fix added `toneReference`, which runs on the main thread when the stroke ends, before the background work begins. It visits every pixel of the stroke's bounding box (the whole photo for a diagonal stroke) and does two tile look-ups per pixel (`painter.original`, once directly and once inside the clone `transform`). On the 1600 × 1000 practice photo that's 1.6 million pixels, likely a few tenths of a second; on a 48 MP photo several seconds, with two extra copies of the area (about 400 MB) held while the tone is worked out. The NFR is a frame at most.
- **How to trigger it:** `TestImages/Stage 9 Practice Photo.png`, Release build (`make run`): Clone Stamp, size 300, Match Tone on, Option-click a source, then paint one diagonal stroke from corner to corner. Let go and immediately try to move the pointer over the toolbar: watch for the spinning wheel or a hitch. To confirm, time `endRetouchBrush` with Match Tone on versus off.
- **Why:** the loop is `for y … for x … { painter.original(atX:y:) … transform(x, y, original) }`, and each `painter.original` is a dictionary look-up into the edit's snapshots that returns a `TileSnapshot` (array retain/release). It could be done on the background task instead: copy the edit's original tiles for the area (or the clone source rows) on the main thread with whole-row copies, and build the reference off it.
- **Test that would catch it:** a Release-only performance test (`make perf`): `toneReference` over a 4000 × 3000 area finishes within 16 ms, or the Editor's end-of-stroke path does no per-pixel work on the main thread.
