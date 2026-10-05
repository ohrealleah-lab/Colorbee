# Review L: RAW photos, opening files, and the new background work
Reviewed at commit: 9cf0fc594bf100248b6868e06a6faa8dceec4c7e
Checked:
- `DocumentController.swift`, `AppDelegate.swift`, `Settings.swift` (`ServicesProvider`), `CanvasView.swift` (drop), `Info.plist` document types and Services: every way into a document for RAW files, PDFs, projects and plain images.
- `RawDeveloper.swift`, `DevelopWindow.swift`: closing, cancelling and re-opening during previews and full develops, the memory check, `Sendable` and `nonisolated(unsafe)` use, the shared `CIContext`, default settings round trip, portrait size.
- `ImageDocument.swift`: `read(from:ofType:)` for projects, PDFs, frames, RAW and images; `open(_:showing:)`; the remembered save format (`runModalSavePanel`, `save(to:)`); the Export panel (accessory, resizing, remembered options); Export as PDF; Revert; menu validation.
- `Editor.swift` pages: `changePages`, `pageDidChange`, `showPage`, `newPage`, `duplicatePage`, `deletePage`, `movePage`, `undo`/`redo` with `undone`, `redactionGroups`, `stepPages`, `jump(toStep:)`, `pageMemory`, `markSaved`, `snapshot(of:)`, Auto-Redact's background reading and `applyAutoRedact`.
- Core `Page.swift`, `PageStack.swift`, `PDFPages.swift`, `ProjectFile.swift` (`storedPages`, `decodeParked`, `restore`), `PDFWriter.swift`, `Canvas.swift` (`cameraDetails` through `copy()` and every place a canvas is made), `History.swift` (`removeAll`, budgets, eviction when a page is parked).
- `PageSidebar.swift`, `RightClickWatcher.swift`, `AppearanceSetting.swift`, `Snapshot.swift`, `SaveSnapshot.swift`, `ParallelRows.swift`, `Renderer.swift` (texture generation across park and unpark).
- Checked and found no problem: Appearance is applied in `applicationWillFinishLaunching` before any window and again live from the General tab; the shared `CIContext` is safe to share (`CIRAWFilter` is made per render); `RawDeveloper`, `UncheckedImage` and `UncheckedCanvas` hand over values nothing else touches; every RAW way in (File ▸ Open, Open Recent, Dock, Finder, Services, drop on the gray area) goes through `DocumentController`, and a RAW file that reached `read(from:)` anyway would open as an untitled copy; `RightClickWatcher` removes its monitor whenever its view leaves a window; Snapshot's hooks only read launch arguments (a normal user can't trigger one); `Page.park`/`unpark` give back exact pixels, and the Metal texture cache rewraps a buffer after a park (generation changes); camera details survive `Canvas.copy()`, `duplicatePage` and project round trips, and a new page rightly has none.

## 1. Clicking a row in the History panel can undo or redo a page change
- **Severity:** High
- **Confidence:** High
- **Where:** `Sources/Colorbee/Editor.swift:728` (`jump(toStep:)`), calling `undo()` and `redo()` at `Editor.swift:2812` and `:2838`
- **What happens:** `jump(toStep:)` loops on `undo()` and `redo()`, which are the ⌘Z commands. They first undo or redo a *page change* (New, Duplicate, Delete, Move Page) whenever one is the newest thing done in the document. So a History-panel click, which should only walk the shown page's own steps, deletes or restores pages as a side effect.
- **How to trigger it:** open a document, edit page 1 (two steps), then use Page ▸ New Page, then go back to page 1. The Add Page step is still the newest thing done, so `pages.undoName` is non-nil even though page 1 is shown. Clicking an earlier History row calls `undo()`, which undoes "Add Page" first (the new page vanishes), then undoes page 1's steps. Redo rows do the mirror image.
- **Why:** `while history.undoCount > count, history.canUndo { undo() }` uses `Editor.undo()`, whose first branch is `if pages.undoName != nil { changePages { try pages.undo() } ... return }`. The loop condition only watches `history.undoCount`, so the page undo costs an iteration and the loop carries on.
- **Hand test (Three Page Test.pdf):**
  1. Open `TestImages/Stage 10/Three Page Test.pdf`. Press P, draw a red line, then a blue line, on page 1.
  2. Page ▸ New Page. A blank page 2 appears (4 pages). Click thumbnail 1.
  3. ⌘Y for the History panel. Click the "Opened" row.
  4. Expected: both lines go and there are still 4 pages. Actual: the lines go and the sidebar shows 3 pages (the new blank page is gone).
- **Test that would catch it:** `jump` should call history directly (`history.undo(on:)` and the redaction-group step), not `undo()`. App target, so check by building and the hand test above.

## 2. Save, Export, Export as PDF, Share and Revert stay enabled while Auto-Redact is open, including while it is applying
- **Severity:** High
- **Confidence:** Medium (the menu part is certain from the code; the timing part needs a long document)
- **Where:** `Sources/Colorbee/ImageDocument.swift:227` (`validateUserInterfaceItem` checks only `activeEffect`), against `Sources/Colorbee/DocumentWindow.swift:317` (the window's check that does include `autoRedact`)
- **What happens:** review E (finding 2) made menus grey out while the Auto-Redact sheet is open, and §23 says so. That check lives in `DocumentWindow.validateMenuItem`, which only sees the window's own commands. File ▸ Save, Save As, Export…, Export As presets, Export as PDF…, Share…, Print, Set as Desktop Picture and Revert To are handled by `ImageDocument`, whose validation ignores `autoRedact`. They stay enabled behind the sheet.
- **How it goes wrong:** `applyAutoRedact` redacts one page at a time and yields to the run loop between pages (`Task.sleep(.milliseconds(1))`), with the sheet still showing "Redacting page 3 of 50…". A File ▸ Export as PDF…, Share or ⌘S chosen in that window writes a document with some pages redacted and the rest not. The user may send that file. A close (⌘W is deliberately allowed) or Revert at that moment leaves the loop running on an orphaned editor. Autosave can also fire mid-loop, writing a half-redacted file in place.
- **How to trigger it (the gap itself):** open `Three Page Test.pdf`, Effects ▸ Auto-Redact…, and with the sheet open look at the File menu: Save…, Export…, Export as PDF…, Share… are all enabled. Edit's commands are greyed. (To see the damage, use a PDF of 30 or more pages and choose Export as PDF… while "Redacting page N of M…" is showing.)
- **Why:** `override func validateUserInterfaceItem(_ item:) -> Bool { if editor?.activeEffect != nil { return false }; return super... }`. `autoRedact`, `isResizeSkewOpen` and `isCanvasPropertiesOpen` aren't checked.
- **Test that would catch it:** in `validateUserInterfaceItem`, return false for the document's commands while `editor.autoRedact != nil` (at least while `applying != nil`) and while the other sheets are open. App target, so check by hand as above.

## 3. A cancelled Save panel leaves the document set to the remembered format, so autosave then writes that format
- **Severity:** Medium
- **Confidence:** Medium (depends on `NSDocument` using `fileType` for the autosave file and for restoring it; the hand test settles it)
- **Where:** `Sources/Colorbee/ImageDocument.swift:269-276` (`runModalSavePanel`, `fileType = remembered`)
- **What happens:** `runModalSavePanel` sets `fileType = remembered` before the panel opens, and nothing puts it back on Cancel. The document is then typed, for example, JPEG. `data(ofType:)` (line 296) encodes `snapshot.encoded(as: format)` in whatever type AppKit asks for, and for an untitled document an autosave uses `fileType`. So every later autosave of that untitled image is a quality-0.9 JPEG, flattened over Color 2 with its transparency gone. After a quit and relaunch (or a crash) the restored window is that degraded copy.
- **How to trigger it:**
  1. File ▸ New. ⌘S, choose JPEG in File Format, save as "Format Test" on the Desktop (this remembers JPEG).
  2. File ▸ New. ⌘⌥E (Canvas Properties), turn on a transparent background. Draw a red shape with the Pencil.
  3. ⌘S, then Cancel. Wait about 10 seconds (autosave), then ⌘Q and reopen Colorbee.
  4. Expected: the transparent area still shows as the checkerboard. Actual (if the guess is right): it comes back white with JPEG softness around the shape.
- **Why:** the property is changed for the preview of the panel and never restored (`defer`/completion), and only a successful Save As later corrects it.
- **Test that would catch it:** restore `fileType` after the panel returns when the user cancelled, or choose the panel's starting type without storing it on the document (an `NSSavePanel` delegate, or set it back in the completion selector). Core can't test it; check by hand.

## 4. Every page you visit keeps a full-size, uncompressed copy of itself, so a long PDF can't stay small
- **Severity:** Medium
- **Confidence:** High
- **Where:** `Sources/Colorbee/Editor.swift:605-617` (`PageMemory`), `:690-715` (`pageDidChange`), `:785-794` (`rememberLayersAsSaved`); `Packages/ColorbeeCore/Sources/ColorbeeCore/Page.swift:24` (`parkedHistoryBudget`)
- **What happens:** FR-11.6 says pages not on screen are kept compressed. The pixels are, but the Editor keeps three more things per page it has shown, all uncompressed: `asOpened` (the whole flattened page), `savedLayers` (a copy of every layer for Revert Layer; for a one-layer page it shares `asOpened`), and a history of up to 16 MB in memory.
- **Numbers:** a letter page is 15 MB at 200 DPI and 34 MB at 300 DPI. Clicking through a 50-page PDF holds about 750 MB (200 DPI) or 1.7 GB (300 DPI) of `asOpened` alone, plus up to 49 × 16 MB (about 780 MB) of parked histories, plus a full extra copy per layer on any page with layers. Auto-Redact's item clicks (`focusRedactionMatch` shows each page) visit pages the same way.
- **How to trigger it:** open a 30–50 page PDF (combine `Three Page Test.pdf` with itself in Preview, or any long PDF), set Settings ▸ General ▸ Open PDFs at 300 DPI first. Note Colorbee's memory in Activity Monitor, then click every thumbnail in turn: it grows by about 34 MB per page and never goes back down.
- **Why:** `pageMemory[page.id] = PageMemory(viewport:..., asOpened: asOpened, savedLayers: savedLayers, ...)` holds `PixelBuffer`s; nothing parks, compresses or drops them (they could be rebuilt from the page's own parked bytes plus the page's history, or stored compressed like the page).
- **Test that would catch it:** a unit test can't see the app; measure resident size after showing every page of a generated 50-page document. A fix would keep `asOpened` and `savedLayers` for parked pages as compressed bytes (the same LZ4 form the page uses).

## 5. Deleted pages are never freed, along with their memory, history and spill file
- **Severity:** Medium
- **Confidence:** High
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/PageStack.swift:28` (`undoSteps`), `:58-63` (`noteEdit`), `:88` (`record(.remove(page, at:))`)
- **What happens:** Delete Page records `.remove(page, at:)`, which holds the whole `Page` (parked pixels, thumbnails, `History` with its in-memory steps and open spill file). `noteEdit()` only moves `lastEdit` so the step can't be undone, but the step stays in `undoSteps` for the life of the document. Only `forgetHistory()` empties the array.
- **Why it matters:** the usual workflow with a long PDF is to delete most pages and keep a few. Each deleted page keeps its compressed pixels (a few MB for text, up to 15 MB or more for scans), up to 16 MB of history in memory and an unlinked spill file still holding disk space. They stay in memory too, though the user can no longer get them back. (The Editor's own `pageMemory` for deleted pages is dropped, so this is only `PageStack`.)
- **How to trigger it:** open a long PDF, delete 30 pages one at a time (Page ▸ Delete Page), edit the page shown after each delete (so each delete becomes un-undoable). Memory doesn't fall. ⌘S, close and reopen: it does.
- **Test that would catch it:** in core, delete a page, call `noteEdit()`, and check the page is released (a weak reference to the `Page` goes nil). A fix drops `undoSteps` entries (and `redoSteps`) that `lastEdit` has made un-undoable, whenever `noteEdit()` runs.

## 6. A damaged multi-page project can crash on open: thumbnail size multiplied without overflow checks
- **Severity:** Medium
- **Confidence:** High
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/ProjectFile.swift:217`
- **What happens:** `guard stored.width > 0, stored.height > 0, stored.width * stored.height * 4 == stored.pixels.count` multiplies two numbers read from the file as `Int`, with the default overflow-trapping `*`. A manifest with a thumbnail `width` and `height` of about 3 billion each (or one of 2^62) traps, so opening the file crashes Colorbee instead of showing "damaged". Round 2's sweep covered the formats that existed then; project format 2 is new.
- **How to trigger it:** edit a two-page `.colorproj` so one `thumbnail` has `"width": 3037000500, "height": 3037000500`, and open it. (Not a thing to hand-test; it needs a hand-made file.)
- **Why:** unchecked `Int` arithmetic on file data. Other values in the function are checked or clamped (`entry.resolution`, `currentIndex`, the ranges).
- **Test that would catch it:** a core test that feeds `storedPages` a manifest with absurd thumbnail sizes and expects a thrown error or a nil thumbnail, not a trap. Use `multipliedReportingOverflow`, or compare against `stored.pixels.count` divided by 4 first.

## 7. Opening a PDF (or a multi-frame TIFF or GIF) freezes the window and has no memory limit
- **Severity:** Medium
- **Confidence:** High for the freeze; Medium for the memory numbers
- **Where:** `Sources/Colorbee/ImageDocument.swift:98-108` and `:111-124` (`read(from:ofType:)`), `Packages/ColorbeeCore/Sources/ColorbeeCore/ProjectFile.swift:188-196` (`storedPages(count:make:)`), `ParallelRows.map`
- **What happens:** `NSDocument` reads on the main thread (`canConcurrentlyReadDocuments` isn't overridden, as the comment at line 124 says). `read(from:)` renders every PDF page, on all cores at once, before returning. The main thread waits for all of it: a 50-page PDF at 300 DPI is a beach ball with no progress and no cancel. A PDF with 2,000 pages is accepted too, with no page limit.
- **Memory:** each task holds the CGContext's bitmap, the decoded `PixelBuffer` and the uncompressed rows for `encode` at once (three copies of a page), for as many pages as there are cores. A letter page at 300 DPI is about 100 MB per core (1 GB on 10 cores). A poster page (36 × 48 in) at 200 DPI is 69 MP, so about 830 MB per core, over 8 GB at once: enough to push the Mac into swap, as the soak did. `PDFPages.render` allows pages up to 256 MP, so the worst case is 3 GB per core.
- **How to trigger it:** Settings ▸ General ▸ Open PDFs at 300 DPI, then open a long PDF, or a PDF with large pages. Activity Monitor shows the spike; the window doesn't respond until it's done.
- **Test that would catch it:** time and measure peak memory of `ProjectFile.storedPages(count:make:)` over 50 generated large pages; limit the lanes (as `encodedPDF` limits to four), or render with a memory-based cap, and consider doing the whole open in the background with a progress bar (the pages are independent of the document until `open(_:showing:)`).

## 8. Dropping a PDF or a project on the window, or a RAW file on the canvas, doesn't behave like opening it
- **Severity:** Medium
- **Confidence:** Low (it depends on what `NSPasteboard` reads from a Finder file drag; the hand test settles it)
- **Where:** `Sources/Colorbee/CanvasView.swift:940-983` (`draggingEntered`, `performDragOperation`, `imageData(from:)`); `Sources/Colorbee/Info.plist` (`NSSendFileTypes`)
- **What happens:**
  1. `draggingEntered` accepts a drag only when `imageData(from:)` finds something, and that first looks for file URLs that conform to `public.image`. A PDF and a `.colorproj` don't conform, so they depend on the fallback (`NSImage` reading the pasteboard). A `.colorproj` has no such fallback: the drop is refused. For a PDF the fallback may accept it, then a drop **on the canvas** (not the gray area) pastes page 1 only, at 72 DPI, as a floating selection, instead of opening the PDF. FR-11.6 promises "File ▸ Open or drag-and-drop" for PDFs.
  2. A RAW file dropped on the canvas is read with `Data(contentsOf:)` and decoded by ImageIO's default RAW render, synchronously on the main thread (seconds for a big file), and pasted with no Develop window. (Dropped on the gray area it correctly goes to Develop.)
  3. `draggingEntered` itself calls `imageData(from:)`, which reads the **whole file** into memory just to decide whether to accept, and `performDragOperation` reads it again. A 60 MP RAW or a 200 MB TIFF stalls the window the moment the drag enters it.
  4. The Services entry "Open in Colorbee" lists `public.image` and the project type but not PDFs, so it isn't offered for a PDF.
- **How to trigger it:**
  1. Open any image so a window shows gray around the canvas. Drag `TestImages/Stage 10/Three Page Test.pdf` from Finder onto the **gray area**. Expected: a new window with 3 pages. Then drag it onto the **canvas**: see whether page 1 pastes in.
  2. Drag `TestImages/Stage 6b Practice.colorproj` onto the gray area. Expected: it opens; likely nothing happens.
  3. Drag `TestImages/Stage 12/Test Camera.dng` onto the canvas (not the gray area): it pastes with no Develop window.
  4. In Finder, right-click the PDF ▸ Services: is "Open in Colorbee" there?
- **Why:** `Self.imageData(from: sender.draggingPasteboard) == nil ? [] : .copy`, with the `public.image` filter in `imageData(from:)`.
- **Test that would catch it:** decide acceptance from the file's type (URL and content type) without reading the data, send PDFs, projects and RAW files to `NSDocumentController.openDocument` wherever they land, and add PDF to the Services file types. App target, so check by hand.

## 9. Develop: Cancel and Esc are dead while "Developing…", and closing the window doesn't stop the work
- **Severity:** Low
- **Confidence:** High
- **Where:** `Sources/Colorbee/DevelopWindow.swift:155` (`.disabled(session.isDeveloping)` on the whole view), `:104-129` (`open()`, `cancel()`)
- **What happens:** `.disabled` covers the footer, so the Cancel button and its Esc shortcut stop working during the full-size develop (which can take many seconds for a 60 MP file). The only way out is the window's close button, and that only sets `cancelled`: the detached task keeps rendering at full size (several times the photo's size in memory, per the check in `RawDeveloper.develop`) and throws the result away. Opening the same file again then starts a second full render alongside it, and each passes the memory check on its own, so two or three together can exceed memory. The preview render in flight is also not stopped, so closing the window leaves up to two renders running.
- **How to trigger it:** with one of your own large RAW files (the test DNG is too small to see it), press Open and watch "Developing…". Press Esc or click Cancel: nothing happens. Close the window with the red button and watch Activity Monitor: CPU and memory stay up for several seconds. Open the file again straight away: memory roughly doubles.
- **Why:** `Task.detached { try developer.develop(settings) }` has no cancellation point, and nothing stops a second `open()` on a new session for the same file.
- **Test that would catch it:** leave Cancel enabled and have it close the window; check `Task.isCancelled` around the render (render in tiles or check before and after), and count full develops in flight across windows. App target; check by hand.

## 10. Delete Page then Undo loses the page's "As Opened" and Revert Layer baseline
- **Severity:** Low
- **Confidence:** High
- **Where:** `Sources/Colorbee/Editor.swift:690-715` (`pageDidChange`), `:714` (`pageMemory` filter)
- **What happens:** when a page is deleted, its `PageMemory` (As Opened, saved layers) is removed at once by the `pageMemory.filter { ... pages.contains ... }`. Undoing the delete brings the page back, but with no memory entry, so the `else` branch runs and sets `asOpened = canvas.flattened()` and the saved layers from the page's *current* pixels. Before/After's "As Opened" then shows the edited page against itself, and Revert Layer can't undo the earlier edits.
- **How to trigger it:**
  1. Open `Three Page Test.pdf`, go to page 2, draw a line.
  2. Page ▸ Delete Page, then ⌘Z ("Undo Delete Page"). Page 2 returns with its line.
  3. View ▸ Before/After, As Opened. Expected: the left side has no line. Actual: both sides have it.
- **Why:** deleted pages' memory is dropped even though the page can come back; `PageStack` keeps the page, the Editor forgets what it knew about it.
- **Test that would catch it:** keep a deleted page's `PageMemory` for as long as `PageStack` can bring the page back (and drop it with `forgetHistory`).

## 11. A developed photo loses its camera details after a quit and relaunch
- **Severity:** Low
- **Confidence:** Medium
- **Where:** `Sources/Colorbee/ImageDocument.swift:27-41` (`open(_:...)` makes a PNG-typed untitled document), `:296-310` (`data(ofType:)` writes `snapshot.encoded(as: format)`, never with camera details)
- **What happens:** a developed RAW photo (or any untitled document that holds camera details) is autosaved as a PNG with no EXIF, because only File ▸ Export… ever writes details. After a quit and relaunch the restored window reads that PNG, so `canvas.cameraDetails` is nil and File ▸ Export… no longer offers "Include camera details". FR-11.8 says details are kept (in .colorproj files, and while the document is open), so for an untitled one, the details exist only until the window closes or the app quits.
- **How to trigger it:** open `TestImages/Stage 12/Test Camera.dng`, press Return in Develop. File ▸ Export…: the "Include camera details" box shows (Cancel). ⌘Q, relaunch: the "Test Camera" window comes back. File ▸ Export…: the box is gone.
- **Why:** `fileType = png` for these documents, and autosave never carries `cameraDetails`.
- **Test that would catch it:** make untitled documents with camera details autosave as a project (or add the details to the autosaved PNG; only ⌘S and presets must stay detail-free, per §23).

## 12. Revert Layer and "saved" state of other pages are taken from the page as it is now
- **Severity:** Low
- **Confidence:** Medium
- **Where:** `Sources/Colorbee/Editor.swift:3194-3197` (`markSaved` sets `savedIsStale`), `:699-704` (`pageDidChange` uses the page's current pixels when stale)
- **What happens:** after a save, every other page is marked "saved state is what it holds now", on the assumption that a hidden page can't change before it's shown. Auto-Redact on every page, and undoing or redoing one, do change hidden pages. So after ⌘S, an Auto-Redact, then showing page 2, page 2's "saved" layers are its redacted pixels, and Revert Layer can't bring back the saved page (page 1, the one shown at the save, works).
  A save that finishes after the user has moved to another page has the same effect on the page that was saved: `markSaved` returns early when `snapshot.pageID != page.id`, after marking that page stale, so its post-save edits count as saved.
- **How to trigger it:** open `Three Page Test.pdf`, ⌘S it as "Revert Test" (page 1 shown). Effects ▸ Auto-Redact…, Solid Fill, Apply. Click page 2, then Layer ▸ Revert Layer. Expected: page 2 goes back to its saved (unredacted) look. Actual: nothing changes.
- **Why:** `savedIsStale` is a guess that fails once pages can change while parked.
- **Test that would catch it:** per page, keep the saved layers (or the layer hash) taken at save time rather than recomputing on show.

## 13. Reordering by dragging stops at one window's height, so a long document can't be reordered
- **Severity:** Low
- **Confidence:** High
- **Where:** `Sources/Colorbee/PageSidebar.swift:32-39` (`DragGesture` with `rowPitch` 150)
- **What happens:** the drag has no auto-scroll, and the destination is `index + round(translation / 150)`. A drag can't go further than the pointer can travel (about six rows on a normal screen), and the sidebar only shows about five. Moving page 40 to the top of a 50-page PDF takes about 39 trips to Page ▸ Move Page Up (no shortcut), though FR-11.6 names dragging as the way to move pages for 10–50 page documents.
- **How to trigger it:** open a PDF with 20 or more pages, drag the thumbnail of page 15 upward as far as the pointer goes. It lands at about page 9.
- **Why:** SwiftUI's `DragGesture` doesn't scroll the enclosing `ScrollView`.
- **Test that would catch it:** hand test above.

## 14. A failure halfway through a page change leaves the document inconsistent
- **Severity:** Low
- **Confidence:** Low (needs `unpark`, `park` or the LZ4 encode to fail, e.g. out of memory or a damaged project)
- **Where:** `PageStack.swift:43-48` (`show`), `:66-73` (`insert`), `:76-89` (`remove`); `Editor.swift:677-688` (`changePages`), `:2819-2823` (`undo`), `:3056-3125` (`applyAutoRedact`), `:3236` (`snapshot(of:)`)
- **What happens:** `show` parks the old page and sets `currentIndex` before `unpark()` of the new one; if that throws, the new current page is left parked (its buffers freed) while `changePages` swallows the error with a beep and returns without `pageDidChange()`. The Editor keeps drawing on `page`, which is now parked and empty, and an edit there is lost when it's unparked again from its old bytes. `undo()` still appends `.pageChange` to `undone` after a refused page undo, and the step has already been popped. In `applyAutoRedact`, a page whose `park()` fails stays unparked and its change isn't counted (`changedOtherPages` is set after `park()`), so the document isn't marked edited and the "Couldn't redact page N" message doesn't say pages before it were redacted. `snapshot(of:)` drops any non-shown page that isn't parked with `compactMap`, so a save would silently leave out such a page.
- **How to trigger it:** not by hand. Make `ProjectFile.restore` throw in a test (damaged parked bytes) and show that page.
- **Test that would catch it:** a core test with a page whose `parked` data is damaged: `PageStack.show` should leave the old page current and unparked; `snapshot(of:)` should never lose a page (park it, or throw).

## 15. Switching pages does the compression, the decompression, and any history spilling on the main thread
- **Severity:** Low
- **Confidence:** High for the code path; the size of the pause depends on the page
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/Page.swift:60-74` (`park`) and `:77-84` (`unpark`); `PageStack.swift:43-48`
- **What happens:** every page switch, New, Duplicate and Delete Page encodes the old page's layers with LZ4 and decodes the new page's, on the main thread, and `park()` first waits for background eviction (`finishBackgroundWork`) and then spills history down to 16 MB (`keepWithinBudget`), writing up to the active budget (512 MB) to disk, still on the main thread. A letter page is a few dozen milliseconds; an 8000 × 8000 page with layers, or a page with a long history, is a second or more, against the "main thread never blocks for more than a frame" rule.
- **How to trigger it:** open an 8000 × 8000 image, add two layers, make 30 brush strokes, Page ▸ New Page, then Previous Page (⌥⌘↑): each switch pauses.
- **Test that would catch it:** time `PageStack.show` on a large generated page. A fix keeps pages compressed lazily (park in the background after the switch, or keep the last page unparked).

## 16. The Export… panel is never released
- **Severity:** Low
- **Confidence:** Medium
- **Where:** `Sources/Colorbee/ImageDocument.swift:414-416`
- **What happens:** the accessory's `formatChanged` closure captures `panel`, and the panel holds the hosting view (`panel.accessoryView = accessory`) whose `rootView` holds the closure: a retain cycle. Each File ▸ Export… leaves its `NSSavePanel`, hosting view and options object in memory.
- **How to trigger it:** open and cancel File ▸ Export… many times and watch memory with Instruments (Leaks or the Allocations "NSSavePanel" count), or print from `deinit` in `ExportOptions`.
- **Why:** `{ format in panel.allowedContentTypes = [format.type] }` needs `[weak panel]`.
- **Test that would catch it:** a `deinit` log, or the Leaks instrument.

## 17. Develop's final size comes from the camera-default render
- **Severity:** Low
- **Confidence:** Low (it only matters if turning Lens Correction on changes the output's extent for some camera; I couldn't check without a real file)
- **Where:** `Sources/Colorbee/RawDeveloper.swift:66-68` (size from `filter.outputImage?.extent`), `:122` (`bounds` built from that size)
- **What happens:** the size reported in the window, the memory check and the final render's bounds all come from the render with the camera's default settings. If switching Lens Correction on (or any setting) changes the output's extent by even a few pixels, `develop()` renders `bounds` of the old size: the edge is cropped, or a strip is left empty (black or transparent).
- **How to trigger it:** with a RAW from a lens macOS has a correction for, compare the size in the Develop window's footer with the opened document's size after turning Lens Correction on and pressing Open. A different size, or a thin empty edge, confirms it.
- **Test that would catch it:** in `develop`, use the rendered image's own extent for the buffer size (and run the memory check against it).

## 18. Export as PDF holds every page twice, and a failed compression writes a broken page without saying so
- **Severity:** Low
- **Confidence:** Low
- **Where:** `Sources/Colorbee/SaveSnapshot.swift:40-58` (`encodedPDF`), `Packages/ColorbeeCore/Sources/ColorbeeCore/PDFWriter.swift:116` (`zlib`)
- **What happens:** all encoded pages sit in the `encoded` dictionary, and `PDFWriter.document` then copies them into one `file` `Data`, so the compressed document exists twice at its end. Pages of photos or scans, compressed losslessly, run to 15–20 MB each: 50 pages is 1 GB, about 2 GB at the peak. Separately, `zlib` does `try? compressed(using: .zlib) ?? Data()`, so if compression fails (memory pressure on a large page) the page's stream is just a header and checksum around nothing: the PDF opens with a blank or broken page, and the export reports success.
- **How to trigger it:** a 50-page PDF of full-page photos at 300 DPI as the source; watch memory during File ▸ Export as PDF….
- **Test that would catch it:** make `zlib` throw, and have `encodedPDF` surface it; stream pages into the file as they're ready, in order.
