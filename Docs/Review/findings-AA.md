# Review AA: the whole app, worst risks only
Reviewed at commit: 079bee95d41f6a27c4bf7bc6590288dc28d764b8
Checked:
- `ImageDocument.swift` (read, save, autosave, `data(ofType:)`, close and redaction warnings, export, share, print)
- `SaveSnapshot.swift`, `Editor` "Files" (`saveSnapshot`, `snapshot(of:)`, `isLayered`, `withoutEffectPreview`, `markSaved`)
- `ProjectFile.swift` (encode, decode, parked pages, page lists), `Page.swift`, `PageStack.swift`, `PDFPages` page count
- `History.swift` (recording, undo and redo, Undo on Active Layer's `candidate`, spilling, eviction, `removeAll`, `SpillStore`)
- `AutoRedact+Apply.swift`, `Editor` "Redact Brush" and "After a redaction", `Edit.willModify` and `keepLockedTransparency`
- `LayerActions.swift`, `LayerActions+Several.swift`, `LayerActions+Groups.swift`, `LayerActions+Text.swift`, `TextLayer.swift` (crash
  paths: removing layers, index math, history's "can't mix" preconditions)
- Every `precondition`, `fatalError` and `try!` in the app and core
- `AppDelegate.applicationShouldTerminate`, `DocumentWindow.performClose`, `CanvasView.syncTextEditor`, `CanvasTextView`
- `History+Snapshots.swift`, `HistorySnapshot.swift`, `Editor` "History Snapshots" and "Pages" (page changes, Delete Page, memory)
- `Editor` "Auto-Redact" (reading every page, Apply across parked pages, the locked-layer check), `beginEffect` and
  `beginBatchRedact` (Batch Redact's layers and regions), `applyEffect`
- `ClipboardHistory.swift` and every place that records where a document's picture came from
- `Renderer.swift` (texture creation and every `fatalError`), `LayersPanel` thumbnails, force unwraps and index math in the
  panels, `PDFWriter.swift`
- Main-thread work on big images in the new stages (text layers, groups, masks, thumbnails): nothing past what earlier
  rounds already deferred (Print, the Levels histogram, page switches)

The spill file, project format, page parking, save copies, snapshots and Auto-Redact's Apply held up. The four findings
below are what's left.

## 1. Pictures over 16,384 pixels on a side crash Colorbee when they're drawn
- **Severity:** Critical (crash, and any unsaved work since the last autosave is lost)
- **Confidence:** High that the screen can't show such a picture; Medium that it's exactly a crash rather than a blank canvas
  (Metal's behavior past its limit isn't documented, and every failure path here is a `fatalError`)
- **Where:** `Sources/Colorbee/Renderer.swift:868-895` (`texture(for buffer:)`), `:896-921` (`texture(for mask:)`);
  `Packages/ColorbeeCore/Sources/ColorbeeCore/ResizeSkew.swift:14-15` (the 30,000 px limit); `Docs/GPU-AUDIT.md:74`
- **What happens:** every layer is drawn by wrapping its whole buffer as one Metal texture of the canvas's full size. Apple GPUs
  can't make a 2D texture wider or taller than 16,384 px. Colorbee lets a picture be up to 30,000 px on a side (open, Resize,
  Canvas Properties, a PDF page, a developed RAW file). Past 16,384, `makeTexture` fails and the renderer calls `fatalError`
  ("Couldn't create the pixel texture" or "Couldn't wrap the pixel buffer for the GPU"). A selection over such a picture
  hits the same wall (`texture(for mask:)`, "Couldn't create the selection texture"). The GPU audit noted the limit in
  passing (2026-10-10), but nothing in the renderer handles it, and no earlier round reported it.
- **How likely:** full-page screenshots of long web pages and chat threads are often taller than 16,384 px. Leah already redacts
  a 1,200 × 10,000 test image (review E, finding 5). Phone panoramas can be wider than 16,384 px. A long PDF page at 200 or
  300 DPI is too.
- **How to trigger it (by hand; save any other work first, since Colorbee should quit):** test image
  `TestImages/Stage 9 Practice Photo.png` (1,600 × 1,000). This uses little memory (about 70 MB a layer).
  1. Open the picture.
  2. Choose **Image ▸ Canvas Properties…** and set the width to **17,000** px, keeping the height at 1,000. Click OK.
  3. Expected: the wider canvas shows. Actual: Colorbee crashes (or the canvas goes blank) as soon as it draws.
  4. To compare, undo, set the width to **16,000** and try again: that should work.
- **Why:** `texture(for:)` does `device.makeBuffer(bytesNoCopy: buffer.baseAddress, length: buffer.byteCount, …)` and then
  `metalBuffer.makeTexture(descriptor: …(width: buffer.width, height: buffer.height…), …)`, with
  `guard … else { fatalError(…) }`. Nothing anywhere checks the size against the device's limit (no `16384` or texture-size
  check in the app). Every size check in Colorbee uses `ResizeSkew.maxSide` (30,000).
- **Test that would catch it:** this can't be a headless core test. Either an app test that asks the renderer to draw a
  17,000 × 1 canvas and expects no trap, or a core test pinning whichever rule Leah picks: lower the limit to 16,384 px a side
  everywhere (one constant, `ResizeSkew.maxSide`, so opening, Resize, Canvas Properties, PDFs and RAW all refuse with the
  existing "too large" message), or draw big canvases in tiles. Lowering the limit is the small, safe fix for the beta; it's
  a behavior change, so it needs Leah's OK.

## 2. Lock Transparent Pixels keeps redacted text readable
- **Severity:** High (a secret left visible)
- **Confidence:** High
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/History.swift:91` (`willModify` queues the lock), `:101-124`
  (`keepLockedTransparency`), `:362` (run on every commit); `AutoRedact+Apply.swift:34-41` and `:47-64` (every redaction path
  goes through `Effects.apply` with an ordinary `Edit`); `Canvas+Groups.swift:47` (a group's lock counts too)
- **What happens:** on a layer (or in a group) with Lock Transparent Pixels on, every redaction keeps each pixel's opacity and
  puts clear pixels back exactly. Text drawn on a clear layer keeps the exact shape of its letters. Solid Fill turns them one
  color, and Blur and Pixelate change only their color. The words stay readable on screen, in exports and in the project, and
  Colorbee still counts it as a redaction (`noteRedaction`, the earlier-versions warning).
- **How to trigger it (by hand):** test image `TestImages/Stage 9 Practice Photo.png` (any picture with a light background works).
  1. Open the picture. Choose the Text tool with **Editable** on, black color, a large size, and type `4111 1111 1111 1111`.
     Click away to place it. A new text layer appears.
  2. With that text layer active, choose **Layer ▸ Lock Transparent Pixels**.
  3. Choose the **Redact Brush** with Solid Fill and paint over the number. Or select a box around it and choose
     **Batch Redact ▸ Solid Fill**, **Blur…** or **Pixelate…**.
  4. Expected: the number is covered. Actual: the number is still readable, now in the fill color (or with only its color
     changed for Blur and Pixelate).
  5. **File ▸ Export…** as PNG and open the export: the number is readable there too.
  Auto-Redact on the same layer does the same.
- **Why:** `willModify` adds the layer to `lockedPending` whenever `canvas.locksTransparency(layer)`, and `record` calls
  `edit.keepLockedTransparency()` first. That puts back `old` wherever `old.a == 0` and keeps `old.a` everywhere else.
  Nothing exempts a redaction. `AutoRedact.lockedLayer` and `layersWithPixels(...).locked` check only `canvas.isLocked` (the full
  lock), so a transparency lock doesn't stop the redaction either. FR-8.2 says every effect respects the lock. FR-3.4 says
  redaction is never softened. The two clash here, so this needs Leah's call. Possible choices: redaction ignores the
  transparency lock, or it refuses with a message naming the layer, as a full lock does.
- **Test that would catch it:** a core test with a 32 × 32 clear layer holding an opaque 8 × 8 square, `locksTransparency = true`.
  Run `AutoRedact.apply(.solidFill(black), in: rect)` over a box larger than the square, then `.pixelate` and `.gaussianBlur`.
  Expect the box to have no clear pixels left, or `.locked` returned. Today the square's outline survives exactly.

## 3. Closing or quitting with a text box, shape or step badge still open throws it away
- **Severity:** Medium (lost work)
- **Confidence:** Medium-High (from reading; not run)
- **Where:** `Sources/Colorbee/ImageDocument.swift:191-199` (an autosave passes `placingPending: false`), `:251-259`
  (`checkRedactionBeforeClosing` autosaves too); `Sources/Colorbee/DocumentWindow.swift:30-39` (`performClose`);
  `Sources/Colorbee/AppDelegate.swift:54-65`; `Sources/Colorbee/CanvasTextView.swift:45` (only Esc commits)
- **What happens:** nothing places `pendingText`, `pendingShape` or a pending badge when a window closes or Colorbee quits. For a
  document that has a file, closing autosaves in place, which leaves the open object out on purpose (review K, finding 1). Then
  the window and editor go. If the open object was the only change, the document isn't marked edited (it isn't a history step
  yet), so it closes with no save at all. Either way the typed words or the drawn shape are gone, with no prompt. Untitled
  documents are fine: their "Save" button does an explicit save, which places the object first.
- **How to trigger it (by hand):** test image `TestImages/Stage 9 Practice Photo.png`.
  1. Open the picture (it has a file, so it autosaves in place).
  2. Choose the Text tool, click on the picture and type `Hello Bee`. Don't click away or press Esc.
  3. Press ⌘W. The window closes with no question.
  4. Open the picture again. Expected: "Hello Bee" is there. Actual: it isn't.
  5. Repeat with a rectangle drawn with the Rectangle tool and left with its handles showing, then with ⌘Q instead of ⌘W.
- **Why:** `save(to:)` takes `editor?.saveSnapshot(placingPending: !isAutosave)`, and closing an autosaving document is an
  autosave. `performClose` only checks `wantsRedactionCheckBeforeClosing`. `applicationShouldTerminate` only looks for unsaved
  redactions. `CanvasTextView` commits only on Esc (`cancelOperation`), not when it's removed or loses focus.
- **Test that would catch it:** an app test with an editor on a small canvas and an open `pendingText` (or `pendingShape`). Ask
  the document or window to close (the hook the fix adds, for example placing pending objects in `performClose` and in
  `applicationShouldTerminate`). Expect the text to be placed as a history step, and the document marked edited, before the
  autosave copy is taken.

## 4. After a relaunch, redacting no longer offers to remove the original from Clipboard History
- **Severity:** Medium (a secret left on disk and visible in the Clipboard panel)
- **Confidence:** High
- **Where:** `Sources/Colorbee/Editor.swift:4252` (`clipboardSources`, in memory only), `:4284-4295` (`noteClipboardSource`,
  `noteRedaction`); `Sources/Colorbee/ImageDocument.swift:38-51` and `:124-168` (a document read from disk, or restored at
  launch, starts with no sources); `Sources/Colorbee/ClipboardHistory.swift:31-36` (the images themselves are kept between
  launches in Application Support)
- **What happens:** the offer to remove the original from Clipboard History after a redaction (review H, finding 2) only knows
  about pastes made in this run of Colorbee. Clipboard History keeps its images on disk between launches, but the link from
  a document to the items it was pasted from isn't kept anywhere. After Colorbee quits and relaunches (or macOS restores the
  window), or after the picture is saved and opened again, a redaction offers nothing. The unredacted screenshot stays in
  `~/Library/Application Support/Colorbee/Clipboard History` and in the Clipboard panel, one click from being pasted again.
- **How to trigger it (by hand):** test image `TestImages/Auto-Redact Practice.png`.
  1. Open the picture in Preview, choose Edit ▸ Select All, then Edit ▸ Copy.
  2. In Colorbee, choose **File ▸ Paste into New Image** (⇧⌘V). Show the Clipboard panel: the picture is
     at the top.
  3. Quit Colorbee with ⌘Q, then open it again. The untitled picture comes back.
  4. Paint over the email address with the **Redact Brush**.
  5. Expected: Colorbee offers to remove the original from Clipboard History, as it does without the relaunch. Actual: no
     offer, and the Clipboard panel still shows the unredacted picture.
  6. To compare, repeat steps 1, 2 and 4 without quitting: the offer appears.
- **Why:** `clipboardSources` is a plain `Set` on `Editor`, filled only by `noteClipboardSource` while pasting
  (`DocumentWindow.swift:346-387`, `ClipboardImage.swift:41`, `HistoryPanels.swift:201`). Nothing saves it with the document
  or its restorable state, and `noteRedaction` only checks `clipboardSources.filter(ClipboardHistory.shared.contains)`.
- **Test that would catch it:** an app test (it mustn't save real Clipboard History, so give `ClipboardHistory` a test folder or
  use a fake). Paste an image so an item is noted, make a new `Editor` for the same document the way a relaunch does (from its
  autosaved project), redact, and expect `clipboardCleanup` to list the item. Possible fixes, for Leah to choose: save the
  item ids with the document's restorable state and in the project, or match Clipboard History items against the
  document's layers when it's redacted.
