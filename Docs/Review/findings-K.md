# Review K: privacy with pages, PDFs and camera details
Reviewed at commit: 9cf0fc594bf100248b6868e06a6faa8dceec4c7e

Checked (by reading only; nothing built, run or committed):
- Core: `Page.swift`, `PageStack.swift`, `ProjectFile.swift` (format 2: page list, stored thumbnails, `decodeParked`, `restore`), `PDFWriter.swift`, `PDFPages.swift`, `CameraDetails.swift`, `ImageCodec.swift` (what each export writes), `AutoRedact+Apply.swift`, `AutoRedact.swift` (`TextScan`), `Canvas.swift` (`copy`, `flattened`, `thumbnail`, `layerBuffersAsSaved`), `History.swift` (`removeAll`, budgets, eviction, spill file).
- App: `Editor.swift` (`beginAutoRedact`, `applyAutoRedact`, `lockedLayer(under:on:)`, `redactionGroups`, `stepPages`, undo and redo, `forgetHistory`, `pageMemory`, `asOpened`, `changePages`, `pageDidChange`, `snapshot(of:)`, `markSaved`), `SaveSnapshot.swift` (`encoded`, `encodedProject`, `encodedPDF`), `ImageDocument.swift` (save, the earlier-versions warning, Export…, Export as PDF, Share, Print, Desktop Picture, Revert), `AutoRedactSheet.swift`, `PageSidebar.swift`, `ClipboardImage.swift`, `ClipboardHistory.swift`, `RawDeveloper.swift` (camera details).
- Round 1–3 fixes in RESULTS.md that this work could have broken: Auto-Redact on every layer, locked-layer refusal, the earlier-versions warning and Remove Earlier Versions, Clipboard History cleanup. They still hold for pages, except where noted below.

Things I checked that are fine:
- **Camera details never leak by field.** Only the eight fields in `CameraDetails` are ever read (`init?(properties:)`) or written (`properties`). GPS, serial numbers and the owner's name aren't read from any file, so they can't reach `.colorproj`, Export…, or anything else. `SaveSnapshot.encoded(as:)` defaults to no details; ⌘S (`data(ofType:)`), Export As presets, Share, Print, Copy and Set as Desktop Picture never pass them. Export… passes them only when the photo has them, the switch is on, and the format holds them (`writesCameraDetails`). The switch is off at first (`UserDefaults.bool` is false when unset). The only other caller is the `-ColorbeeSnapshot` testing hook (`Snapshot.swift:52`), which is session L's.
- **Export as PDF writes no text or metadata.** `PDFWriter.document` writes a catalog, a page tree, and per page one image, a content stream and an ICC profile: no `/Info`, no `/ID`, no `/Producer`, no dates, no text. Transparent pixels are composited over white, and partly clear ones too, so nothing hides in alpha (the formula can't overflow a `UInt8`). The shown page is flattened with hidden layers out, adjustment layers applied and a floating selection included (`Canvas.flattened`). Other pages are flattened from their parked bytes, which `park()` writes fresh from the live canvas, so a page edited and then parked comes out current.
- **Opening a PDF keeps nothing from it.** `PDFPages.render` draws into a bitmap; only pixels and the file name (for the title) survive. Hidden text, annotations and metadata are dropped. A PDF that draws a black box over text just draws the box.
- **Auto-Redact's pre-checks are complete.** The page-changed check and the locked-layer check both run over every target page before any page is redacted (`applyAutoRedact`), and a parked page is brought back just to look and parked again (`lockedLayer(under:on:)`). Matches are keyed by page id, so reordering pages can't send a box to the wrong page. The sheet is a window-modal sheet and menus are greyed while it's open, so page changes, deletes and edits can't happen between reading and Apply.
- **Multi-page undo and redo** (`redactionGroup`, `stepPages`) follow the §23 entry of 2026-10-04 in every order I traced (shown page last-changed, another page changed since, a page deleted since, and redo).
- **`forgetHistory` clears what it says it clears**: every page's undo stack and spill, the page-change steps (so deleted pages are released), `redactionGroups`, and the shown page's "As Opened". Thumbnails are regenerated every time a page is parked (`park()` calls `canvas.thumbnail`), so a redaction done while a page was parked updates both the sidebar and the thumbnail stored in `.colorproj`.

---

## 1. Shapes and text that aren't placed yet are left out of every saved or exported file
- **Severity:** High
- **Confidence:** Medium-High (I searched for a hook that places pending objects before saving and found none; only a run can fully confirm)
- **Where:** `Sources/Colorbee/Editor.swift:3229-3231` (`saveSnapshot()`), `Editor.swift:3219`, `3224`, `3271` (`encoded`, `encodedProject`, `flattenedPNG`), `ImageDocument.swift:158` (save), `340` (Share, Desktop Picture), `399`, `424`, `438` (Export As, Export…, Export as PDF), `DocumentWindow.swift:87` (Copy of the whole image). `finishInteractions()` (`Editor.swift:913`) is `private` and none of these call it.
- **What happens:** A shape (FR-5.1) or text (FR-6) stays an overlay in `pendingShape` / `pendingText` until it's placed, and is drawn on screen by the renderer only. `saveSnapshot()` copies the canvas, which doesn't contain it. So the file, PNG, PDF, copy, printout or shared image is written **without** the shape or text, while the window shows it and the document says "Saved". A filled box drawn over a secret is the most common way to redact by hand, and if it hasn't been placed (Return, a click outside it, or a tool change) the secret goes out uncovered. `Auto-Redact`, page changes and every Edit command do place first (`finishInteractions`), so this only hits saving and output.
- **How to trigger it:**
  1. Open `TestImages/Round 3/E1 Screenshot.png`.
  2. Choose the Shapes tool, Rectangle, with Fill set to Solid and Color 1 black. Drag a box over the email address. Don't press Return or click elsewhere. The box shows on screen.
  3. File ▸ Export… (⌥⌘S), PNG, save to the Desktop. Open the PNG in Preview: the email is visible, no box. (Same with ⌘S, File ▸ Export as PDF…, Share…, or ⌘C then paste in another app.)
  4. Same with text: Text tool, type "SECRET" over the email, don't click away, ⌘S. The saved file has no text. (The text box's first responder doesn't stop the document's Save command: `DocumentWindow.validateMenuItem` only filters the window's own actions, not `saveDocument:`.)
- **Why:** `finishInteractions()` is called at the start of Edit/Layer/Page/Auto-Redact commands, but `ImageDocument.save`, `export`, `shareDocument`, `copyToClipboard` and `printOperation` go straight to `editor.saveSnapshot()` / `flattenedPNG()`. `NSDocument` would call `commitEditing` before a save, but neither `ImageDocument` nor the window controller implements it.
- **Test that would catch it:** needs the app target (no test target exists). Make `saveSnapshot()` and `encoded…` place pending objects first (a public `settleForOutput()` that calls `finishInteractions()`), and check by hand as above. In core, a test can't reach it.

## 2. After a read failure partway, Auto-Redact still offers Apply and redacts only the pages it read
- **Severity:** Medium
- **Confidence:** High (the logic); Low on how often a page fails to read
- **Where:** `Editor.swift:2977-2995` (the reading task), `Editor.swift:280` (`isReading`), `AutoRedactSheet.swift:~148` (Apply's `.disabled`), `Editor.swift:3057` (`applyAutoRedact`'s guard)
- **What happens:** If page *k* of a multi-page document fails to read (the decode of its parked bytes, `makeCGImage`, or Vision throws, for example on a very large page under memory pressure), the task stores `failure` and stops, so pages *k…n* are never scanned. `isReading` is `failure == nil && …`, so with a failure it's false, and Apply's disabled condition (`count == 0 || busy || isReading != false || problem != nil`) is satisfied for pages 1…k-1 that did produce matches. Apply then redacts those pages and leaves the rest untouched. The header line does say "Couldn't read the text: …", but the list below still shows the matches, the button still says "Apply to N Items", and nothing says which pages weren't read. The FR says Auto-Redact covers every page and that a problem on any page redacts nothing.
- **How to trigger it:** can't be done by hand with the test files. Code check: make `TextScan.read` throw for page 2 of `Three Page Test.pdf` (for example by passing an unreadable source in a test build). Page 1's items stay listed and Apply is enabled.
- **Why:** the failure branch (`catch { … failure = …; return }`) doesn't clear `pages[i].matches` for already-read pages or disable Apply. The single-page case is safe only because it has no matches to apply.
- **Test that would catch it:** app target. Simplest fix with a core-testable part: put "which pages weren't read" in `AutoRedactSession` (a `var unreadPages: [Int]` computed from `scan == nil && failure != nil`) and refuse Apply (or say "pages 2–3 weren't read") when it's non-empty; test the property in core.

## 3. Hidden pages keep full-size unredacted copies in memory, and "Remove Earlier Versions" doesn't let go of them
- **Severity:** Medium (memory growth, against FR-11.6's "pages not on screen are kept compressed"; and a smaller privacy part)
- **Confidence:** High
- **Where:** `Editor.swift:605-615` (`PageMemory`), `691-718` (`pageDidChange`), `2508-2519` (`forgetHistory`)
- **What happens:**
  - *Memory:* when a page is left, `PageMemory` keeps `asOpened` (a flattened full-size copy; for a one-layer page `flattened()` makes a real copy) and `savedLayers` (shares it for one layer). These stay for every page ever visited until the document closes or the page is deleted. A 50-page 300 DPI PDF, all pages visited, holds about 50 × 34 MB = 1.7 GB of uncompressed pixels on top of the compressed pages. This is independent of the parked-history budget and looks like what stage 10's parking was meant to avoid.
  - *Privacy:* `forgetHistory()` only sets `asOpenedIsStale = true` on hidden pages' entries. The unredacted `asOpened` and `savedLayers` buffers stay resident until that page is next shown (`pageDidChange` then replaces them). Nothing writes them to a file, but they're the "before" image of every redacted page, held after the user chose Remove Earlier Versions and Undo History.
- **How to trigger it:** (memory) Settings ▸ General ▸ PDFs at 300 DPI, open a PDF with 20 or more pages, click through every page, and watch Colorbee's memory in Activity Monitor: it grows by one full page each, and doesn't shrink. (privacy) Not visible by hand; a unit test on `PageMemory` after `forgetHistory` shows the old buffers.
- **Why:** `PageMemory` stores buffers, not a "recompute when shown" flag; the stale flags only cover correctness.
- **Test that would catch it:** app target. Fix idea: keep nothing for hidden pages but a flag, and rebuild "As Opened" from `Page.history`'s first step or drop Before/After for hidden pages; in `forgetHistory`, replace each entry's buffers (set them to the page's current flattened-on-demand) or remove the entry.

## 4. Auto-Redact on pages that were never shown makes "As Opened" and Revert Layer start from the redacted page
- **Severity:** Medium (wrong baseline; not a leak)
- **Confidence:** High
- **Where:** `Editor.swift:585-591` (`init(pages:)` sets `asOpened` for the first page only), `Editor.swift:707-711` (`pageDidChange`, the `else` branch for a page with no memory entry)
- **What happens:** "As Opened" and Revert Layer's saved copies for a page are created the first time the page is shown, from whatever it holds then. If Auto-Redact redacts a page while it's parked and never visited (`applyAutoRedact` unparks, redacts, parks), showing it later sets `asOpened` to the already-redacted page, so Before/After's "As Opened" shows the redaction on both sides, and Layer ▸ Revert Layer reverts to the redacted state. FR-11.3 says "As Opened". (Visited pages keep the true original, which is why the stage 10b tests passed.) The same applies to a project opened and redacted before its other pages are viewed, and to "Last Saved".
- **How to trigger it:**
  1. Open `TestImages/Stage 10/Three Page Test.pdf` and stay on page 1.
  2. Effects ▸ Auto-Redact…, Solid Fill, Apply to all items (don't click any row: clicking one shows its page).
  3. Click thumbnail 3, then View ▸ Before/After with As Opened. Expected: page 3 as opened, email and phone showing, next to the redacted one. Actual: black boxes on both sides.
- **Why:** nothing records a page's opened state when the document opens; `asOpened` is computed lazily at first show.
- **Test that would catch it:** app target. Fix idea: make `asOpened` per page, created when the document is opened (flattened from the parked bytes on demand and cached before the page is first changed), or when the page is first parked/edited.

## 5. A page that can't be brought back leaves the Editor on the wrong page, and the next save can blank a page
- **Severity:** Medium
- **Confidence:** Medium (needs a page whose pixels fail to decode, such as a partly damaged project)
- **Where:** `PageStack.swift:43-48` (`show`), `76-89` (`remove`), `66-73` (`insert`), `130-172` (apply, undo); `Editor.swift:677-687` (`changePages`); `ProjectFile.swift:226-248` (`decodeParked` doesn't touch the pixel data) and `96-106` (`restore`)
- **What happens:** `PageStack.show(_:)` parks the shown page, sets `currentIndex`, then unparks the new page. If that unpark throws (the page's compressed pixels are damaged), `currentIndex` already points at the new page, which is still parked (empty buffers), and nothing is rolled back. `Editor.changePages` catches the error, beeps (`onRefused`) and returns **without** calling `pageDidChange()`, so `Editor.page` is still the old page, now parked with its memory freed. The window keeps drawing the old page (blank or stale), edits go into it, and the next save writes `canvas.copy()` of it as "the shown page". Saving skips a parked page equal to `Editor.page` among the others, so the old page 1 is written from its freed buffers (blank, or garbage if the memory wasn't reclaimed yet). A project with a damaged page opens fine (`decodeParked` reads only the manifest), so this appears only on clicking the damaged page. `remove` and `insert` have the same shape.
- **How to trigger it:**
  1. Open `TestImages/Stage 10/Three Page Test.pdf`, ⌘S as "Damage Test" on the Desktop (a `.colorproj`), close it.
  2. In Terminal, damage the last page's pixels without changing the file size:
     ```bash
     python3 -c "
     p='/Users/leah/Desktop/Damage Test.colorproj'
     b=bytearray(open(p,'rb').read()); i=int(len(b)*0.9)
     b[i:i+300]=b'\xff'*300
     open(p,'wb').write(b)"
     ```
  3. Open it (it opens). Click thumbnail 3: it should refuse with a message. Then draw a line on what's shown, ⌘S, close and reopen. Expected: page 1 as it was, plus the line. Actual (if the decode fails as expected): page 1 may come back blank.
- **Why:** `show` mutates `currentIndex` before the step that can fail, and `changePages` doesn't resync the Editor on failure.
- **Test that would catch it:** core test: build a `PageStack` of three pages where page 3's parked data is damaged; `show(2)` must throw and leave `currentIndex` and the old page's parked state unchanged. Make `show`, `insert`, `remove` and the undo/redo applies unpark first (or restore on failure).

## 6. A one-page project forgets the page's PDF resolution, so Export as PDF changes the page size
- **Severity:** Medium (wrong result, silently)
- **Confidence:** High
- **Where:** `ProjectFile.swift:164-165` (`encode(stored:currentIndex:)` returns `pages[0].project` for one page), `ProjectFile.swift:202` (reading it back uses `Page.defaultResolution`), `SaveSnapshot.swift:30-31` (`encodedProject` returns the shown page's project when there are no other pages)
- **What happens:** `resolution` is stored only in the multi-page manifest (`PageEntry`). A document with one page is written as a bare one-page project, so its resolution is lost, and reopening it gives 144 DPI. FR-11.6 says a PDF's pages keep the resolution they were opened at. This happens for a one-page PDF saved as a project, a longer PDF reduced to one page, and every restore of an untitled PDF copy after a relaunch (autosave writes the same one-page form).
- **How to trigger it:** with the PDF setting at its default of 200 DPI, open `Three Page Test.pdf` and delete pages 2 and 3. File ▸ Export as PDF… and note the page size in Preview (8.5 × 11 in). Then ⌘S it as a project, close it, reopen it, and File ▸ Export as PDF… again: the page is now 11.8 × 15.3 in, because 144 DPI is assumed (1700 ÷ 144).
- **Why:** the one-page shortcut writes the old one-page format, which has nowhere for it.
- **Test that would catch it:** core test: `ProjectFile.encode(pages:[page with resolution 300], …)` then `storedPages(_:)` returns resolution 300. (Write format 2 whenever the resolution isn't the default, or add it to the one-page manifest as an optional field.)

## 7. If a page fails partway through Apply, the message is wrong and the page can drop out of saves
- **Severity:** Low-Medium
- **Confidence:** Medium
- **Where:** `Editor.swift:3095-3107` (`applyAutoRedact`'s catch), `Editor.swift:3235-3238` (`snapshot(of:)`'s `guard … let parked = other.parked`), `Editor.swift:2869-2885` (`stepPages`)
- **What happens:**
  - If `unpark()` works and `apply()` redacts the page but `park()` then throws, the catch says "Couldn't redact page N" (it was redacted) and `break`s: later pages are left unredacted, the page that threw stays **unparked**. Nothing tells the person that earlier pages (and this one) are already redacted, and because Apply then reports a problem the sheet stays open with the original list. Pressing Apply again is refused ("changed after it was read"), so the person must cancel, with no clear picture of what's redacted.
  - `snapshot(of:)` builds `otherPages` only from pages that are `parked`. A non-shown page left unparked (as above, or after a failed `park()` in `PageStack`) is silently omitted from `.colorproj` saves and from Export as PDF: the saved file has fewer pages with no error.
  - `stepPages` (group undo/redo) returns `false` midway after some pages were already stepped, leaving the Auto-Redact undone on some pages and not on others, while `undone` and the change count aren't updated.
- **How to trigger it:** no way by hand (needs a park or unpark failure).
- **Why:** none of these paths rolls back, reports what was done, or keeps the "every page but the shown one is parked" invariant.
- **Test that would catch it:** core: a `PageStack` where `park()` fails for one page. App-level fix: say "Redacted pages 1–2; page 3 failed", keep the invariant in `snapshot(of:)` by using `projectData()` for unparked pages instead of dropping them.

## 8. Export as PDF embeds the source image's ICC profile unchanged
- **Severity:** Low
- **Confidence:** Medium
- **Where:** `PDFWriter.swift:44` (`profile: colorSpace.copyICCData()`), `PDFWriter.swift:73-79`
- **What happens:** the FR and the menu's help say the PDF holds "no details about who made it" and no dates. It embeds the document's whole ICC profile as read from the source image. macOS's built-in profiles say nothing personal (the creation date and the Apple copyright text are in the profile header, the same on every Mac). But a screenshot taken on a calibrated display, or a photo with a custom camera profile, carries that profile's description, creation date and device manufacturer and model, which can name the display or the person's calibration software.
- **How to trigger it:** open a screenshot or photo that has a custom profile (for example from a calibrated Mac display), File ▸ Export as PDF…, open it in Preview, Tools ▸ Show Inspector (the General tab shows the profile name). A built-in profile shows "Display P3" or "sRGB IEC61966-2.1", so the standard test files won't show this.
- **Why:** the profile is copied verbatim.
- **Test that would catch it:** core: encode a page whose color space comes from a profile with a custom description, and check the PDF doesn't contain it (or that only a named built-in space, `/ICCBased` with a canonical profile, is written for anything that isn't Display P3 or sRGB).

## 9. A damaged project can crash Colorbee when it reads a page thumbnail
- **Severity:** Low
- **Confidence:** High
- **Where:** `ProjectFile.swift:217` (`stored.width * stored.height * 4 == stored.pixels.count`)
- **What happens:** `ThumbnailEntry.width` and `.height` come from the file as `Int`. If both are large (for example 2^40 each), the multiplication overflows and Swift traps, so a damaged or edited `.colorproj` crashes on open. Round 2's "damaged files can't crash" check was about format 1; the page manifest is new.
- **How to trigger it:** edit a multi-page `.colorproj`'s page manifest so a thumbnail has `"width":1099511627776,"height":1099511627776`; opening it crashes.
- **Why:** the check multiplies before bounding the sizes (the page projects' own sizes are bounded in `decodeParked`).
- **Test that would catch it:** core: `storedPages(_:)` of a manifest with huge thumbnail dimensions returns no thumbnail (or fails) instead of trapping. Use `multipliedReportingOverflow`, or check `width <= maxSide`.

## 10. The PDF writer fails silently in two corner cases
- **Severity:** Low
- **Confidence:** Medium
- **Where:** `PDFWriter.swift:112` (`(try? …compressed(using: .zlib)) ?? Data()`), `PDFWriter.swift:94` (`String(format: "%010d", offset)` with an `Int`)
- **What happens:** (a) If compression fails, the page's stream is an empty deflate body with a good header and checksum of the real data: a PDF with a corrupt page and no error. (b) `%010d` reads 32 bits, so offsets past 2 GiB (about 20 pages of 8000 × 8000 photo content, which doesn't compress) print wrong values and the xref table is broken, again with no error.
- **How to trigger it:** (b) Export as PDF of a document with many very large, noisy pages. Not hand-testable reasonably.
- **Why:** `try?` plus `%d`.
- **Test that would catch it:** core: `zlib` throws on failure; `document` uses `%010ld` with an `Int` (or builds the number with `String(offset)` padded), tested with a fake large offset.

## 11. Copies made from a document before it is redacted aren't covered by the Clipboard History offer
- **Severity:** Low (may be as Leah decided in round 3, so confirm)
- **Confidence:** High
- **Where:** `Editor.swift:2499-2535` (`clipboardSources`, `noteRedaction`), `ClipboardImage.swift:30-34`, `DocumentWindow.swift:81-90`
- **What happens:** after a redaction, Colorbee offers to remove the Clipboard History items the document was **pasted from**. A copy made **from** the document before the redaction (⌘C of the whole page, which is what a person does to send a page elsewhere first) is added to Clipboard History as a PNG file in Application Support and isn't tracked, so the unredacted page stays there for good (up to 10 items) and on the Mac clipboard.
- **How to trigger it:** open `Three Page Test.pdf`, ⌘C (nothing selected), Auto-Redact page 1, Apply. The offer doesn't appear (or doesn't list that copy). ⌥⌘V shows the unredacted page 1 in Clipboard History.
- **Why:** `clipboardSources` only gets the item id from `noteClipboardSource` when a document is created from a paste.
- **Test that would catch it:** app target. If Leah wants it covered: remember the item ids of copies made from the document too.
