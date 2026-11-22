# Review AI: files and windows (stage 34c)
Reviewed at commit: f3f5623c02034eea0153b11f095fee7dd4d3ae4a
Checked:
- `Sources/Colorbee/ImageDocument.swift`: `followLayers`, `makeWindowControllers` (copies, tool settings), `save(to:…)`, `autosavingFileType`, `writableTypes`, the redaction checks, `revert`, `encodeRestorableState` / `restoreState`
- `Sources/Colorbee/OriginalFile.swift`
- `Sources/Colorbee/ToolSettings.swift` (decoding, `ToolSettingsStore`: start, follow, note, save) and `Editor+ToolSettings.swift`
- `Sources/Colorbee/AppDelegate.swift` (save on quit, the redaction check on quit)
- `Sources/Colorbee/Editor.swift` (`retouchSizes` and every carried setting's `didSet`), `Editor+Files.swift` (`isLayered`), `Editor+Undo.swift`, `Editor+Pages.swift` (page changes, History jump), `Editor+Canvas.swift` (`toolSize`, Undo on Active Layer), `Editor+Selection.swift` (`recordingChanges`, `cancelFloating`'s change reports), `Editor+Layers.swift` (masks and colors)
- `SettingsFolder.swift`, `TestHost.swift`, `HelpShots.swift`, the Makefile's tool runs, and every use of `ToolSettingsStore.shared`
- `Tests/ColorbeeTests/FilesAndWindowsTests.swift`
- FRD FR-12 "Back to its file", FR-15.4, and the four §23 rows dated 2026-11-20

Everything I couldn't run is reasoned from the code and from how `NSDocument` documents its behavior. Where a finding
depends on `NSDocument` internals, it says so, with a test that settles it.

## 1. Going back to the file leaves the untitled project's autosave attached; after a crash or force quit the PNG can be written over with project data
- **Severity:** Critical (file overwritten)
- **Confidence:** Low to Medium (depends on `NSDocument` keeping `autosavedContentsFileURL` when `fileURL` is set by hand, which I believe it does; the test below settles it)
- **Where:** `Sources/Colorbee/ImageDocument.swift:305-313` (the return branch of `followLayers`), `:286-288` (`autosavingFileType`), `:368-373` (`writableTypes`)
- **What happens:** while the picture is an untitled project, macOS autosaves it to a separate file in Autosave
  Information, as a .colorproj, and remembers it in `autosavedContentsFileURL`. When `followLayers` points the document
  back at `photo.png`, it sets `fileURL`, `fileType` and `fileModificationDate`, but nothing clears that old autosave.
  The document now has a file **and** a stale autosave of an earlier, layered state. When macOS brings windows back
  after a relaunch, it reopens a document from its file plus its autosaved contents if it has any
  (`reopenDocument(for:withContentsOf:)`): the window comes back titled `photo.png`, showing the old layered project,
  with `fileType` = .colorproj (the autosave's type) and marked Edited. From there:
  - `followLayers` can't fix it: it's layered and a project, so neither branch runs.
  - `autosavingFileType` returns `super`, which is the document's type, .colorproj, since `fileURL` isn't nil.
  - So the next autosave in place (or ⌘S) writes **.colorproj data into `photo.png`**. Colorbee then can't open
    `photo.png` (it decodes by extension), and the picture is gone except from Versions.
  I can't tell whether a normal ⌘Q clears the stale autosave first (an autosave in place might), but a crash or force
  quit between the return and the next save leaves it in place. So does an autosave elsewhere that was still being
  written when Undo brought the file back, since it sets `autosavedContentsFileURL` when it finishes. Even if relaunch
  turns out to be safe, the old autosave file is left in Autosave Information. (`isDraft`, which macOS sets on some
  untitled documents, is another piece of untitled state that setting `fileURL` by hand doesn't reset; worth checking
  in the same test.)
- **How to trigger it:** use a copy, since this may damage the file.
  1. In Finder, select `TestImages/Stage 9 Practice Photo.png` and choose File ▸ Duplicate.
  2. Open the copy in Colorbee.
  3. Layer ▸ New Layer.
  4. Choose the Brush and paint one stroke.
  5. Wait 30 seconds.
  6. Edit ▸ Undo.
  7. Edit ▸ Undo.
  8. Wait 10 seconds.
  9. Press ⌥⌘Esc, choose Colorbee, click Force Quit.
  10. Start Colorbee again.
  11. In Finder, select the copy and press Space.
  - Expected: the copy's window comes back with one layer and isn't marked Edited. Quick Look shows the photo.
  - Actual (if this finding is right): the window shows two layers and the stroke, marked Edited. A few seconds later
    Quick Look shows no picture, and File ▸ Open on the copy fails.
  - Also try it with ⌘Q in place of step 9.
- **Why:** the return branch only does
  `projectName = nil; sourceFolder = nil; self.fileURL = original.url; self.fileType = original.type; fileModificationDate = original.modified`.
  `NSDocument` deletes the autosaved contents and clears `autosavedContentsFileURL` only as part of its own save
  operations, never from the `fileURL` setter. The return needs the same cleanup as a real Save: remove the file at
  `autosavedContentsFileURL` and set it to nil.
- **Test that would catch it:** an app test that gives an opened PNG document an `autosavedContentsFileURL` (a temp
  .colorproj written with `encodedProject()`), adds a layer, undoes it, calls `followLayers`, and expects
  `autosavedContentsFileURL == nil` and the temp file gone. Also: a document reopened with `fileURL` = a .png and
  layered contents must never autosave as .colorproj to that URL (`autosavingFileType` should conform to the file's
  extension, or the document should go back to being an untitled project).

## 2. Fading or hiding the last layer still counts as "one plain layer", so the original file is overwritten with a faded or blank picture
- **Severity:** High (wrong picture written into her file)
- **Confidence:** High
- **Where:** `Sources/Colorbee/Editor+Files.swift:63-66` (`isLayered`), `Sources/Colorbee/ImageDocument.swift:305-307`; `Packages/ColorbeeCore/Sources/ColorbeeCore/Canvas+Groups.swift:32-33` (`isShown`)
- **What happens:** `isLayered` asks only about pages, layer count, kind, mask and text. A single pixel layer at 20%
  opacity, hidden, or with a blend mode is "plain", so the picture goes back to `photo.png` and the next autosave
  (seconds later, no ⌘S) writes the flattened result: the photo at 20% opacity, or, with the layer hidden, a fully
  transparent PNG (a JPEG original becomes a solid Color 2 rectangle, since a hidden layer isn't drawn and the
  picture is flattened over the matte). The layer's opacity, visibility and blend mode aren't kept anywhere, so
  reopening the file can't undo it.
- **How to trigger it:**
  1. In Finder, duplicate `TestImages/Stage 9 Practice Photo.png` and open the copy.
  2. Layer ▸ New Layer.
  3. In the Layers panel, click the bottom (photo) layer.
  4. Set its Opacity to 20%.
  5. Click the top (empty) layer.
  6. Layer ▸ Delete Layer.
  7. Wait 10 seconds.
  8. In Finder, select the copy and press Space.
  - Expected: the copy still shows the photo at full strength (the faded layer keeps it a project), or Leah decides
    this should write the faded picture.
  - Actual: the title goes back to the PNG's name at step 6, and Quick Look shows the photo faded to 20%. With
    Layer ▸ Hide Layer at step 4 instead, Quick Look shows an empty, see-through picture.
- **Why:** `pages.pages.count > 1 || canvas.layers.count > 1 || canvas.layers.contains { !$0.isPixelLayer || $0.mask != nil || $0.text != nil }`.
  Opacity, `isVisible` and `blendMode` aren't in it, and `flattened` drops hidden layers and applies opacity. As far
  as I can see, a plain opened picture whose only layer is faded or hidden has always saved this way; stage 34 adds
  the new route (a project with these settings on its last layer goes back to the file). So it's Leah's call
  whether a faded, hidden or blended last layer should stay a project in both cases, or neither.
- **Test that would catch it:** core or app test: one pixel layer with `opacity = 0.5`, with `isVisible = false`, or
  with a non-Normal blend mode → `isLayered` is true (or whatever Leah decides), and a document in that state doesn't
  go back to its `originalFile`.

## 3. A redaction made before a relaunch is never warned about once the picture goes back to its file
- **Severity:** High (secret left visible in Versions)
- **Confidence:** Medium
- **Where:** `Sources/Colorbee/ImageDocument.swift:233-236` (`warnAboutEarlierVersions`), `:256-258` (`wantsRedactionCheckBeforeClosing`), `Sources/Colorbee/AppDelegate.swift:55-58`, `Sources/Colorbee/Editor.swift:759` (`redactedSinceSave`)
- **What happens:** `redactedSinceSave` lives only in memory. Quitting checks redactions only for windows that have a
  file (`fileURL != nil`), so an untitled project with a fresh redaction quits with no check, and after the relaunch
  the flag is false. Choice (5) of "Stage 34c built" then lets the restored project go back to `photo.png`: Flatten,
  and the next save writes the redacted picture into `photo.png`, while macOS keeps the unredacted original as an
  earlier version. ⌘S calls `warnAboutEarlierVersions`, sees `redactedSinceSave == false`, and says nothing. Before
  stage 34 an untitled project never wrote into the original file, so the original visibly still held the words.
  Now the file looks redacted while File ▸ Revert To still shows the secret.
- **How to trigger it:**
  1. In Finder, duplicate `TestImages/Auto-Redact Practice.png` and open the copy.
  2. Layer ▸ New Layer.
  3. Choose the Redact Brush and paint over a line of words.
  4. Quit Colorbee with ⌘Q. (No warning: it's a project.)
  5. Start Colorbee again. The project window comes back.
  6. Layer ▸ Flatten. The title goes back to the PNG's name.
  7. File ▸ Save.
  - Expected: "Earlier versions of this file still show what you redacted."
  - Actual: no warning. File ▸ Revert To ▸ Browse All Versions shows the words unredacted.
- **Why:** `guard let editor, editor.redactedSinceSave else { return done() }`, and nothing sets the flag again after
  a relaunch. The quit check filters on `wantsRedactionCheckBeforeClosing`, which needs `fileURL != nil`. One way to
  fix it: keep "redacted since the original was last saved" in the restorable state next to `originalFile`, and set
  `redactedSinceSave` when the document goes back to the file with it set.
- **Test that would catch it:** an app test that redacts in a document that is an untitled project with an
  `originalFile`, encodes and restores its state into a fresh `ImageDocument`, flattens, calls `followLayers`, and
  expects `wantsRedactionCheckBeforeClosing` to be true.

## 4. An autosave still being written when the picture gains a layer can put the file back and flatten the layers into it
- **Severity:** High (file flattened)
- **Confidence:** Low (depends on `NSDocument` setting `fileURL` and `fileType` again when an asynchronous in-place autosave finishes, as its documentation describes for saves)
- **Where:** `Sources/Colorbee/ImageDocument.swift:192-228` (`save(to:…)`), `:294-304` (`followLayers`), `:381-395` (`canAsynchronouslyWrite`, `unblockUserInteraction`)
- **What happens:** saves run in the background, and `data(ofType:)` calls `unblockUserInteraction()` before it
  encodes, so editing carries on while a big PNG is encoded. If the picture gains a layer then, `followLayers` makes
  it an untitled project (`fileURL = nil`, type .colorproj). When the background write finishes, `NSDocument` records
  the save it just made: `fileURL = photo.png`, `fileType = png`, new `fileModificationDate`. Nothing runs
  `followLayers` again until the next edit, so the document is layered but points at a PNG. An autosave in that gap,
  or ⌘S, writes the layers flattened into `photo.png`, the thing "the file is never flattened" rules out. Two
  smaller effects: the title flips back to the file, and `originalFile.modified` keeps the date from before
  Colorbee's own write, so going back later makes macOS falsely report that "another application" changed the file.
  The core of this predates stage 34 (`becomeProjectIfLayered` had the same shape), but stage 34 adds quick back
  and forth across the boundary (Undo brings the file back, an autosave starts, Redo makes it a project again).
- **How to trigger it:** timing-dependent, hard by hand. It needs a big PNG, so the save takes a second or two to
  encode: a copy of `TestImages/Photo Editing/Texture Practice.png` resized to about 8000 px wide and saved. Copy
  something to the clipboard first.
  1. Open the big copy and paint a stroke.
  2. Wait about 5 seconds (until the autosave starts).
  3. Immediately Layer ▸ New Layer, and paste something on it with Edit ▸ Paste.
  4. Without editing further, wait 30 seconds.
  - Expected: the title shows the project name, and the PNG on disk still shows the picture without the pasted layer.
  - Actual (if this finding is right): the title shows the PNG's name again, and the file shows the pasted pixels flattened in.
- **Why:** `followLayers` runs only from `onDocumentChange`. The save's completion handler (`super.save(to:…) { … }`)
  calls `noteFileSoon()`, but not `followLayers()`, after `NSDocument` has updated the file and type. Running
  `followLayers()` on the main thread at the end of every save's completion would put it right whichever came first.
- **Test that would catch it:** an app test that starts a save of a PNG document, adds a layer before the completion
  runs (or calls the completion path after `followLayers` by hand), then expects `fileURL == nil` and type .colorproj
  after the completion.

## 5. Every edit in a project made from a file checks the disk for the original, which can freeze on a network volume that's gone
- **Severity:** Medium (freeze)
- **Confidence:** Medium (the check on every edit is certain; how long it blocks depends on the volume)
- **Where:** `Sources/Colorbee/ImageDocument.swift:305-307`, `Sources/Colorbee/OriginalFile.swift:12-14`
- **What happens:** `canReturn(isLayered:savedAsProject:exists:)` takes `exists` as an argument, so
  `FileManager.default.fileExists(atPath:)` runs on the main thread on **every** document change (every stroke, every
  undo) for as long as the document is a project with an `originalFile`. That includes projects still layered, and
  projects already saved as a .colorproj, since `originalFile` is never cleared and is restored after a relaunch. On
  a disconnected network share (SMB), or a disk that's spinning up, a `stat` can block for seconds, and the window
  stalls after each stroke. That breaks "the main thread never blocks for more than a frame".
- **How to trigger it:** needs a shared folder on another Mac or a NAS.
  1. Copy `TestImages/Stage 9 Practice Photo.png` to the shared folder and open it from there.
  2. Layer ▸ New Layer.
  3. Turn off Wi-Fi (the share is now unreachable, not ejected).
  4. Paint a few strokes.
  - Expected: painting stays smooth.
  - Actual: Colorbee pauses after each stroke (beach ball), possibly for many seconds.
- **Why:** `original.canReturn(isLayered: editor.isLayered, savedAsProject: fileURL != nil, exists: FileManager.default.fileExists(atPath: original.url.path))`:
  all three arguments are worked out before `canReturn` runs. Checking `isLayered` and `fileURL` first, and the disk
  only when the picture is plain and unsaved, and clearing `originalFile` once the project is saved somewhere, keeps
  the check to the rare moment it matters.
- **Test that would catch it:** make `exists` lazy (a closure) and test that it isn't called while `isLayered` is true
  or `savedAsProject` is true; or count calls through an injected file checker across 100 strokes on a layered
  project.

## 6. A damaged or hand-edited `Tool Settings.json` isn't range-checked; a huge size crashes Colorbee whenever that tool is chosen
- **Severity:** Medium (crash, needs a damaged file)
- **Confidence:** High
- **Where:** `Sources/Colorbee/ToolSettings.swift:66-110` (`init(from:)`), `Sources/Colorbee/Editor+Canvas.swift:108-118` (`toolSize`)
- **What happens:** decoding keeps whatever number it finds. Every new window then starts with it, at every launch,
  until the file is fixed by hand:
  - `brushDiameter`, `shapeLineWidth`, `badgeDiameter`, `redactBrushSize` or a `retouchSizes` value above about 9.2e18
    (`1e20` is valid JSON): `toolSize` does `Int(brushDiameter.rounded())`, which traps. Choosing that tool (the
    toolbar's Size control reads `toolSize`) crashes Colorbee, every time, in every window.
  - `eraserSize` near `Int.max`: the hover square's `x + width` overflows.
  - Out-of-range but finite values (brush 1e9, badge 1e6, tolerance 7, eyedropper Sample Size 7 or -5, text size 0
    or -5, an empty font): no crash that I found, but sizes far outside the control's range (1...50, 16...128 and so
    on), a Sample Size the picker can't show, and a font field that's blank.
  - NaN or Infinity can't appear: they aren't valid JSON, so the whole file is ignored and the defaults are used.
    That's fine.
  Damaged project files read through `KeyedDecodingContainer.lenient` and `Double.clamped(to:orIfNotFinite:)` (review
  round 11, `aafd661`). This file doesn't use them.
- **How to trigger it:**
  1. Quit Colorbee.
  2. In Finder, Go ▸ Go to Folder…, type `~/Library/Application Support/Colorbee Test Builds`, press Return.
  3. Make a copy of `Tool Settings.json` (to put back after).
  4. Open `Tool Settings.json` in TextEdit, change the number after `"brushDiameter":` to `1e20`, and save.
  5. Start Colorbee.
  6. Click the Brush tool.
  - Expected: the Brush is chosen, size 50 at most.
  - Actual: Colorbee crashes, and does so again each time the Brush is chosen.
  7. Put the copy back.
- **Why:** `brushDiameter = value(.brushDiameter, brushDiameter)`, and `value` is just
  `(try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback`. `Editor` has no clamps of its own; only the Size
  control and `[`/`]` clamp, through `sizeRange(for:)`.
- **Test that would catch it:** decode `{"brushDiameter":1e20,"eraserSize":0,"badgeDiameter":1e6,"fillTolerance":7,"eyedropperSampleSize":-5,"retouchSizes":{"cloneStamp":-3}}`
  and expect every value inside its tool's range (`Editor.sizeRange(for:)`, 0...1, {1, 3, 5}), then read `toolSize`
  for every tool on an editor started with it.

## 7. Mask grays still reach new windows: leaving the mask keeps them, and Undo of Add Mask leaves `canvas.editsMask` set
- **Severity:** Low (wrong starting colors)
- **Confidence:** High for the code
- **Leah's decision (2026-11-21):** after leaving a mask, new windows get the colors from before the mask, not the
  leftover grays. The window that had the mask keeps its grays as today. Record in FRD §23 when fixing.
- **Where:** `Sources/Colorbee/ToolSettings.swift:190-200` (`note`), `Sources/Colorbee/Editor+Layers.swift:236-249` (`paint(onMask:at:)`), `Sources/Colorbee/Editor.swift:97-108` (the color `didSet`s)
- **What happens:**
  - Choosing a mask turns Color 1 and 2 into grays, and choosing the layer again (its thumbnail, or another layer)
    leaves them gray: nothing puts the real colors back. From then on `note` sees `canvas.editsMask == false` and
    carries the grays. So the next change to any carried setting (a size, say) gives every new window gray colors.
    §23 says "While a mask is chosen, the real colors are what's carried". Leah has decided this covers the grays
    left behind afterwards too (see her decision above).
  - Undo of Add Mask (or deleting the masked layer) removes the mask but leaves `canvas.editsMask` true: only
    `LayerActions` and the Layers panel ever set it, and history doesn't. While it's stale, the color `didSet`s keep
    turning any color Leah picks into a gray in that window (this predates stage 34), and `note` keeps carrying the
    older colors from `last`. `note` checks `canvas.editsMask`, not `Editor.editsMask`, which also checks
    `activeLayer.mask != nil`.
- **How to trigger it:**
  1. File ▸ New.
  2. Click red in the palette (Color 1).
  3. Layer ▸ Layer Mask ▸ Add Mask. Color 1 turns gray.
  4. In the Layers panel, click the layer's own thumbnail (left of the mask).
  5. Press `]` once.
  6. File ▸ New.
  - Expected: the new window's Color 1 is red.
  - Actual: it's gray.
  Second case:
  1. File ▸ New.
  2. Layer ▸ Layer Mask ▸ Add Mask.
  3. Edit ▸ Undo.
  4. Click blue in the palette.
  - Expected: Color 1 is blue.
  - Actual: Color 1 is a gray.
- **Why:** `paint(onMask:)` converts colors on the way in (`color1 = color1.maskGray`) but does nothing on the way
  out. `note` uses `if editor.canvas.editsMask { … }`. History doesn't restore `canvas.editsMask`.
- **Test that would catch it:** app test: add a mask, undo, expect `canvas.editsMask == false` (or `editsMask` used
  everywhere); then pick blue and expect Color 1 blue and `store.last?.color1` blue after `note`.

## 8. Going back to the file can leave two windows on the same file
- **Severity:** Low (confusing "changed by another application" questions; a wrong answer writes over the other window's work)
- **Confidence:** Medium
- **Where:** `Sources/Colorbee/ImageDocument.swift:305-313`
- **What happens:** while window A is an untitled project made from `photo.png`, macOS doesn't know A came from
  that file, so opening `photo.png` again opens a second window B on it. When A goes back to its file, both documents
  have `fileURL == photo.png`. A's next autosave meets B's writes: macOS asks whether to Save Anyway or Revert, and
  Save Anyway writes A's picture over B's changes. If A has no changes, it may quietly revert to B's version when B
  saves, losing A's undo history (Revert rebuilds the editor). FRD FR-12 only says "if another app changed the file,
  macOS asks"; here the other "app" is Colorbee itself.
- **How to trigger it:**
  1. In Finder, duplicate `TestImages/Stage 9 Practice Photo.png` and open the copy (window A).
  2. Layer ▸ New Layer.
  3. In Finder, double-click the same copy again. Window B opens.
  4. In B, paint a stroke.
  5. Wait 10 seconds.
  6. In A, Edit ▸ Undo.
  7. In A, paint a stroke.
  8. Wait 10 seconds.
  - Expected: A stays a project because the file is already open in B (or Colorbee just brings B forward at step 3).
  - Actual: both windows are titled with the copy's name, and A shows "The file has been changed by another application".
- **Why:** the return checks only `FileManager.default.fileExists`, not
  `NSDocumentController.shared.document(for: original.url)`.
- **Test that would catch it:** an app test with two documents: B registered for the URL, A a project with that
  `originalFile`. Undo in A → A's `fileURL` stays nil.

## 9. `make help-shots` windows start with Leah's own carried tool settings
- **Severity:** Low (help screenshots not reproducible)
- **Confidence:** High
- **Where:** `Sources/Colorbee/ImageDocument.swift:104-105`, `Sources/Colorbee/HelpShots.swift`
- **What happens:** choice (6) keeps `make bench` windows on the defaults, but help-shot runs (and `make help`'s menu
  dump, which opens a blank window) go through the same `start`. The screenshots' palette shows whatever Color 1 and
  2 Leah last used in a test build, and the toolbar shows her last sizes, so two runs can produce different pictures
  for the help book. They also write the file again on quit (harmless; the same values).
- **How to trigger it:**
  1. In a `make run` window, pick red as Color 1.
  2. Quit.
  3. Run `make help-shots`.
  - Expected: screenshots show the default black and white.
  - Actual: the palette in each screenshot shows red as Color 1.
- **Why:** `if !Benchmark.isEnabled { ToolSettingsStore.shared.start(editor) }` doesn't check `HelpShots.scene`.
- **Test that would catch it:** a unit test on the condition: `start` isn't called when `HelpShots.scene > 0` or
  `Benchmark.isEnabled` (pull the check into one `ToolSettingsStore.isEnabled`).

## 10. The text style is all or nothing in the settings file, against the file's own rule
- **Severity:** Low (font and size reset once, after an update)
- **Confidence:** High
- **Where:** `Sources/Colorbee/ToolSettings.swift:46-47` (the comment), `:95`; `Sources/Colorbee/PendingObjects.swift:39-50`
- **What happens:** the comment says a setting added later "falls back to its default rather than losing the rest".
  But `textStyle` is decoded with `TextStyle`'s synthesized `Codable`, which needs every key. When a later version
  adds a text option, Leah's carried font, size, bold and alignment all fall back to
  Helvetica Neue 24 on the first launch of the new build. An unknown `alignment` value does the same.
- **How to trigger it:** only after a future change to `TextStyle`. By hand now: edit `Tool Settings.json` (as in
  finding 6) to remove `"underline":false` from inside `textStyle`, start Colorbee, and choose the Text tool.
  - Expected: the saved font and size, with Underline off.
  - Actual: Helvetica Neue 24.
- **Why:** `textStyle = value(.textStyle, textStyle)` decodes the whole struct at once.
- **Test that would catch it:** decode a `textStyle` missing one key and holding an unknown one; expect the other
  fields kept.
