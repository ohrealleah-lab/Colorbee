# Review AF: did round 11's refactors keep everything exactly as it was?
Reviewed at commit: 2a8dab72178d97cd156fd31b7151785b949ec1a5
Checked (each commit read old against new with `git show <commit>^:<file>`):
- `0058794` LayerSettings: undo's layer records, Undo on Active Layer (`History.undoOnLayer`, `candidate`), History Snapshots (take and go back), `Layer.copy` (duplicate, masks, text layers), the setter's name-before-`nameFromWords` order
- `016c202` changeLayers and `keepGroupsTogether`: `update(layerAt:)`, `update(layersWithIDs:)`, `setVisibility`; every app caller of `history.commit`
- `8f85f70` Crop, Resize and Skew, Canvas Size: placing the floating piece, buffers for layers and masks, `fitText`, the selection, values worked out before versus after placing
- `e71b49d` SpillStore bands (undo spilling, eviction, reading back, snapshots); `f6a0877` project framing, blob ranges, parked pages, page lists
- `aafd661` lenient Adjust Photo reading (`PhotoEdit`, `PhotoAdjustments` name/number list, `PhotoDetail`, `PhotoEffects`, `LenientEffect` for layers and filters)
- `97a9aa1` StoredSettings: filters, text styles, palettes, export presets, redaction patterns, custom colors, shortcuts, Clipboard History; test isolation (`SettingsFolder`, `TestHost`)
- `c752d85` `fitsEditing` and the skew size; `f06cc73` slider reaches, gray, vignette falloff, blur and Feather box sizes (worked through exact values); `3f042ae` shader twins and adjustment kinds
- `8e6b0db` render passes (`startPass`, `resume`, `blendBack`); `e87cea0` and `a91d922` History thumbnails, clipped layers with a floating piece on screen, export and thumbnail
- `e6e5d94` the Editor split (every line of the old file compared as a multiset against the new files: identical apart from `private` and section headings)
- `148b8a5`, `5c5ead9`, `08c07be`, `271d533`, `f3b4ad2`, `69b6b6d`, `7c44e15` line by line

## Answers in short

- **The promise holds almost everywhere.** 19 of the 21 commits change no picture, file or step. The two that change
  something on purpose (`aafd661` damaged Adjust Photo layers, `e87cea0` floating piece in thumbnails) do what FRD §23
  says, but the thumbnail change costs too much on big pictures (finding 1) and doesn't match the screen with
  Transparent Selection on (finding 2).
- **LayerSettings:** every setting still rides along in undo, Undo on Active Layer, snapshots and copies. The setter's
  order (name, then `nameFromWords`) is kept. Saving, merging and the project file still list settings by hand, as before,
  and weren't changed.
- **changeLayers:** still exactly one step, and selection before and after are recorded as before. Only new: a dangling
  group id gets cleared on a settings step. Layer-settings slider drags (`layerSettingsEdit`, `Editor+Layers.swift:501`)
  still commit on their own without `keepGroupsTogether`. That's harmless today because they only change opacity and
  blend mode.
- **StoredSettings:** one unreadable entry no longer empties filters, text styles, palettes, export presets or
  redaction patterns. Shortcuts and custom colors are still read all or nothing. That's harmless in practice, since a
  `KeyShortcut` only fails to read if its key isn't text. Test runs no longer write any setting, except Clipboard
  History's image files (finding 3).
- **Damaged files:** a good file never loses anything (a JSON number never reads as a name, and every
  well-formed name/value pair is kept). A damaged slider list, filter or intensity now loses just that part, as D4
  chose.

## Differences between old and new code, classified

| Commit | What differs | Verdict |
|---|---|---|
| `0058794` | Undo on Active Layer now also writes back `groupID`; `candidate` guarantees it's unchanged | Harmless |
| `016c202` | Settings steps and Option-click visibility now run `keepGroupsTogether`, which also clears a group id naming a missing group | Improvement |
| `8f85f70` | Resize's text fit and action name, and Canvas Size's offsets, are worked out before the floating piece is placed rather than after. Placing never changes the size | Harmless |
| `e71b49d` | Snapshot bands are sized from each buffer, not the canvas (always equal); reading a snapshot back also hashes each band | Harmless |
| `f6a0877` | None: the same bytes out, the same checks in | Identical |
| `aafd661` | A missing or damaged `adjustments`, `filter` or `filterIntensity` no longer drops the whole adjustment; an unreadable slider list now gives neutral sliders | Intended (D4) |
| `97a9aa1` | Lists read entry by entry. If every export preset is unreadable, the list is now empty rather than the five defaults. Palettes' `activeName` can name a palette that was skipped | Improvement; the two edge cases are harmless (no type has changed shape) |
| `c752d85` | None: the skew used the same formula before | Identical |
| `f06cc73` | Feather's box now rounds instead of truncating. The two agree for whole radii, and both callers pass whole numbers (`DocumentView.swift:275` and `SelectionMask+Modify.swift:200`). At 1.5 they would differ (box 3 instead of 1) | Harmless today |
| `f06cc73` | Vignette, Desaturate, Whites, Warmth, Tint, Auto and the eyedropper: the same expressions in the same order | Identical |
| `3f042ae` | Shader constants named; `adjustKind` values 0 to 6 unchanged | Identical |
| `8e6b0db` | After a GPU blur the sampler is set before the draw rather than after (the blur shader reads pixels directly). An isolated pass whose texture couldn't be made is now skipped, then the draw fails as before | Harmless |
| `e87cea0` | Thumbnails blend a clipped adjustment in premultiplied space, as the export does, and show a floating piece | Improvement and intended, but see findings 1 and 2 |
| `a91d922` | A piece floating on an "Only the layer below" layer shows on screen, in exports and in thumbnails | Intended; checked on all three |
| `e6e5d94` | Only `private` removed. No `didSet`, `renderSoon()` or `onRender()` moved | Identical |
| `148b8a5` | One `areaStroke` for the Redact Brush and Remove; the `[` and `]` limits come from `sizeRange` (same ranges); `TextStyle(spec)` sets all 8 fields the old code copied | Identical |
| `5c5ead9` | `ImageCodec.converted` returns the same buffer when the spaces match; the PDF writer only calls it when they don't | Identical |
| `08c07be`, `271d533`, `f3b4ad2`, `69b6b6d` | None (the export preset tooltip text is the same string; the always-on menu cases merged into one list that comes before no case naming them) | Identical |
| `7c44e15` | Applying Drop Shadow, Border or Straighten now also stops a running fill and clears the page redo list, as every other edit does. Every `history.commit` in the app now goes through `noteEdited` | Improvement, complete |

## 1. With a piece floating, every History thumbnail copies the whole layer on the main thread
- **Severity:** Medium (a stall on big pictures; breaks "the main thread never blocks for more than a frame")
- **Confidence:** High that the copy happens; Medium on how long it feels
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/Canvas.swift:274-278` (from `e87cea0`); called by
  `History.commit` (`History.swift:388-390`) and by the Page sidebar (`Editor+Pages.swift:20-23`)
- **What happens:** Since `e87cea0`, `Canvas.thumbnail` makes `floating.placedCopy(of: layer, …)` whenever a piece
  floats. That copies the entire layer (`FloatingSelection.swift:93`, `layer.buffer.copy()`), then composites the
  whole piece onto the copy, one pixel at a time on one core (`FloatingSelection.swift:100-103`). It does this just to
  read about 64 × 40 pixels from it. The doc comment above still says it "costs almost nothing even on a huge image".
  `History.commit` makes a thumbnail after every step, on the main thread. So Paste, every arrow-key nudge, every move
  and Duplicate Selection now copies the full layer. A multi-page document pays again for the Page sidebar's picture of
  the current page, which is rebuilt whenever `layersRevision` changes. On an 8000 × 5000 photo with the whole picture
  lifted, that's 160 MB copied and 40 million pixels composited per nudge. The 160 MB is freed again after each one.
- **How to trigger it:** Leah can see it (this uses about 1 GB of memory at most):
  1. Open `TestImages/Stage 9 Practice Photo.png`.
  2. Image ▸ Resize and Skew…, choose Percentage, type 500 in Horizontal (Maintain aspect ratio on), click OK.
     The picture is now 8000 × 5000.
  3. Edit ▸ Select All.
  4. Press the Right Arrow key 10 times, about twice a second.
  Expected: each press moves the picture at once, as the same steps do on the original 1600 × 1000 photo.
  With the bug: each press pauses before the picture moves, and holding the key makes it move in jerks.
- **Why:** `let placed = selection.floating.flatMap { … floating.placedCopy(of: layer, locked: …) }` runs once per
  thumbnail, before the sampling loop, and `placedCopy` is built for exports, which need every pixel.
- **Test that would catch it:** a Release-only perf test (`make perf`): an 8000 × 8000 canvas with a 4000 × 4000
  floating piece; `canvas.thumbnail(maxSide: 64)` must take under a few milliseconds. A fix that reads each sampled
  pixel from the piece at its place, rather than placing it, keeps `ThumbnailTests` passing.

## 2. History thumbnails show a floating piece's Transparent Selection color, which the screen and export hide
- **Severity:** Low (a thumbnail that doesn't match the screen; nothing saved is wrong)
- **Confidence:** High
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/Canvas.swift:277`
- **What happens:** The thumbnail places the piece with `resampling: .nearestNeighbor, transparentKey: nil`. The screen
  leaves out pixels matching Color 2 while Transparent Selection is on (`Renderer.swift`, `keyEnabled`). The export and
  save do too (`SaveSnapshot.flattened` passes `selectionContext.transparentKey`). So the History panel shows a solid
  box where the screen shows the picture through it. FRD §23 (2026-10-31) says thumbnails show the piece "as the screen
  does". A resized piece is also sampled sharp where the screen uses smooth resampling, but at 64 pixels that's hard to
  see.
- **How to trigger it:**
  1. Open `TestImages/Help/Sample Screenshot.png` (mostly white).
  2. Edit ▸ Select All, then Edit ▸ Copy.
  3. Open `TestImages/Stage 9 Practice Photo.png`.
  4. Press D so Color 2 is white, then click the Transparent Selection button (the checkerboard) in the toolbar.
  5. Edit ▸ Paste. On the canvas the photo shows through the screenshot's white areas.
  6. View ▸ History.
  Expected: the Paste step's picture shows the photo through the white areas, as the canvas does.
  With the bug: it shows the screenshot as a solid white box over the photo.
- **Why:** `floating.placedCopy(of: layer, locked: …, resampling: .nearestNeighbor, transparentKey: nil)`. The canvas
  doesn't know the key; it lives in the Editor's `selectionContext`.
- **Test that would catch it:** a core test: a canvas with a floating piece that has some Color 2 pixels. The thumbnail
  with that key must equal a downscale of `flattened(transparentKey: key)`. That needs `thumbnail` to take the key the
  way `flattened` does.

## 3. A test that copies or pastes would still write and delete files in Leah's real Clipboard History
- **Severity:** Low (latent: no test reaches it today)
- **Confidence:** High on the code; no current test calls it (checked `Tests/ColorbeeTests`, including the monkey)
- **Where:** `Sources/Colorbee/ClipboardHistory.swift:58` and `:118-121` (from `97a9aa1`, which guarded only `save()` at
  `:123-126`)
- **What happens:** `97a9aa1` says "No store writes while testing", and CLAUDE.md says tests never save clipboard
  history. But `ClipboardHistory` always uses the everyday folder (`SettingsFolder.everyday`, by design), and only its
  index write checks `StoredSettings.canWrite`. During a test run, `add(_:)` still writes the image file into Leah's
  `Application Support/Colorbee/Clipboard History`. Past ten items, `forget` deletes the oldest real item's image. Her
  index is left alone, so the next launch drops that item (`items = stored.filter { fileExists }`) and leaves the test's
  image there as an orphan. `remove` and `clear` delete files the same way. Today only `DocumentWindow.copy`, `paste` and
  `ClipboardImage.copy` call `add`, and no test drives them, so this only matters if the monkey or a later test does.
- **How to trigger it:** not by hand. A test that calls `ClipboardHistory.shared.add` eleven times while
  `TestHost.isActive` would show it.
- **Why:** `guard (try? data.write(to: imageURL(item), options: .atomic)) != nil` and `try? FileManager.default.removeItem`
  have no `StoredSettings.canWrite` check, unlike `save()`.
- **Test that would catch it:** an app test: with `TestHost.isActive`, `add` some PNG data; the everyday Clipboard
  History folder's file list must be unchanged.
