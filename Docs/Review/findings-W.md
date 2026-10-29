# Review W: export, Vision, the readout and the menus
Reviewed at commit: b48dadab8be9bcd4a6a6240bb3234bcfc5e830c8
Checked:
- `ExportColor.swift`, `ImageCodec.converted`, `ImageCodec.encode(…limit:)`, `prepared`, `write`: the profile goes in the file for PNG, JPEG, HEIC and TIFF. A quick ImageIO script in the scratch folder showed GIF and BMP can't hold Display P3: ImageIO converts their colors to sRGB as it writes, so they look right, but "Keep" and "Display P3" give an sRGB file in those two formats (a note, not a finding). vImage's conversion keeps straight alpha exactly (checked with a script: a half-clear P3 red came out as a half-clear sRGB red, not darkened). The size search (full quality, lowest, then eight halvings, keeping the best that fits) and its error are right, camera details count, and nothing is written on failure.
- `SaveSnapshot.encoded`, `inColors`, `encoded(using:)`: the matte (Color 2) is converted with the picture; presets convert after scaling.
- `ImageDocument.swift` Export panel and `ExportOptions`; `Settings.swift` `ExportPresetStore.Item` (presets saved before stage 19 decode as Keep; an older Colorbee ignores the new `color` key); `ExportPreset.swift`.
- `Canvas.patchAsShown`, `colorAsShown`, `pixelAsShown`, `Effect.reach`, `Effects.blurReach` (it matches `blurred`'s own margin, so one blur or one Adjust Photo is exact, at canvas edges too), `Effects.Placement` and `photoAdjusted` (vignette and grain use canvas positions), clipped adjustments, `PixelBuffer.averagedPixel`; `Editor.pointerColor`, `readoutColor`, `pickHexToCopy`, `pickColor`, `pictureSample`; `StatusBar.swift`.
- `FaceFinder.swift` (Vision's bottom-left origin is flipped correctly; boxes are 30% bigger and kept on the picture), `RectangleFinder.swift` (corner order and the flip are right; the brightness copy's rows run top-down, as the check expects), Auto-Redact's Faces row (`AutoRedact.matches` skips it, so it can never match text; old saved pattern lists get it on load; an older Colorbee drops it), `Editor.beginAutoRedact`, `refreshAutoRedactMatches`, `findPerspectiveCorners` (a late search is ignored once Perspective Correction closes or the corners have moved), `resetPerspectiveCorners`.
- `CropOverlay.swift` (the golden spiral's arcs join up and stay in the box; the other guides are right), `Editor.nextCropOverlay`, the O key in `CanvasView.handleKey`.
- `CanvasPropertiesSheet.swift`, `CanvasAnchor.offset` (the odd pixel goes right or bottom whether growing or shrinking, as documented).
- `MainMenu.swift` (no two menu commands share a key; ⌥⌘A, ⌃⌘C and ⌥⇧⌘V are free, and a saved shortcut book that already used one is handled by `importChanges`, as review T checked for ⇧S), `DocumentWindow.swift` actions and validation (blocked behind sheets and effect bars except viewing commands; the History panel's New Snapshot button and snapshot clicks end an open effect first, through `finishInteractions`), `HistoryPanels.swift` buttons, `Snapshot.swift` options, `SettingsFolder.swift`, `Scripts/make-beta.sh` (the command-line `SWIFT_ACTIVE_COMPILATION_CONDITIONS` replaces nothing, since `project.yml` sets none).
- Not a finding: Vision can miss very small faces in a big picture (a 40-pixel avatar in a 5K screenshot). The sheet says so, as Q21.5 decided, so I didn't report it. It's worth a hand test with a real screenshot some day.

## 1. The color readout and Copy Color as Hex read what's under a floating paste, not the paste
- **Severity:** High (wrong result the user sees: the hex copied isn't the color on screen)
- **Confidence:** High
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/Canvas.swift:399-427` (`patchAsShown`), used by `colorAsShown` (`:388`), `Sources/Colorbee/Editor.swift:1353-1365` (`pointerColor`, `readoutColor`), `:1340` (`pickHexToCopy`), `Sources/Colorbee/DocumentWindow.swift:230` (`copyColorHex`)
- **What happens:** Right after a paste, while it's still floating (not yet placed), hovering over it shows the color of the picture underneath. ⌃⌘C and the status bar's eyedropper copy that wrong hex too. The Eyedropper's Option-click has the same blind spot (it already did before this round, through `pixelAsShown`). Shapes and text that aren't placed yet are left out the same way.
- **How to trigger it:** paste anything and hover over it before clicking away or pressing Return.
- **Why:** `patchAsShown` builds a fresh `Canvas` from each layer's `buffer` and flattens that. The new canvas has `selection = .none`, so the floating selection, which `composite` draws over its layer (`Canvas.swift:321-357`), is never in the patch. Stage 20's decision says the readout "reads what you see (all layers)". Review E2 had the same kind of problem with the Magic Wand; that was fixed by placing the paste first. The readout can't place it, so the patch needs the floating pixels drawn in, as `flattened` does.
- **Leah's steps:**
  1. Open `TestImages/Photo Editing/Color Chart.png`.
  2. With Rectangle Select, drag a small box inside the Red patch. Press ⌘C, then ⌘V.
  3. Drag the pasted red square onto the middle of the Blue patch. Don't click anywhere else or press Return.
  4. Hover over the red square and look at the status bar's color readout.
  - Expected: `#D92B2B` (red).
  - Bug: `#2B57D9`, the blue underneath.
  5. Press ⌃⌘C with the pointer still on the square, then paste into TextEdit: it's the blue hex too.
  6. Press Return to place the square and hover again: now it says `#D92B2B`.
- **Test that would catch it:** core test: a canvas with a floating selection of a different color over a pixel; `colorAsShown` at that pixel must equal `flattened()` there.

## 2. A size limit typed in Export… may be ignored unless Return or Tab is pressed first
- **Severity:** Medium (the file can come out bigger than the limit Leah typed, which an upload form may reject)
- **Confidence:** Medium (I couldn't run it; the notice gives it away at once, see step 4)
- **Where:** `Sources/Colorbee/ImageDocument.swift:612` (`TextField("Size", value: $options.limitAmount, format: .number)`), read at `:485`
- **What happens:** A SwiftUI number field updates its value only when typing ends: on Return, Tab or a click into another field. Clicking Save in the panel doesn't end the typing, so the export uses the limit from before (200 KB at first, or the last one used). Review P13 found the same thing with the Feather box.
- **How to trigger it:** type a new number in the Limit box and click Save straight away.
- **Why:** the completion handler reads `options.limitAmount`, and nothing ends the field's editing before it runs. The fix used for Feather (P13: the box sets the value as you type) would fit here too.
- **Leah's steps:**
  1. Open `TestImages/Photo Editing/Bright Photo.png`.
  2. Choose File ▸ Export…, set Format to JPEG, tick "Limit file size to" and leave the unit on KB.
  3. Click in the number box, delete what's there and type `60`. Don't press Return or Tab. Click Save.
  4. Watch the note at the bottom of the canvas.
  - Expected: "Fitting the file into 60 KB…", and in Finder (Get Info) the file is at most 60,000 bytes.
  - Bug: the note names the old number (for example 200 KB), and the file is bigger than 60 KB.
  5. Do it again, pressing Tab after typing: this time it should be right.
- **Test that would catch it:** hard to unit-test; check by hand after the fix (the steps above).

## 3. The readout doesn't match the export when two or more blur adjustments are stacked
- **Severity:** Low (a few levels off in the readout, never in the file)
- **Confidence:** High for the cause; Medium for how far off it shows
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/Canvas.swift:401`
- **What happens:** The patch is padded by the largest single reach of the adjustments below, but stacked blurs add up: the second blur reads first-blur results up to its own reach away, and those need the first blur's reach again around them. With two Gaussian Blur layers, or a blur over an Adjust Photo with Texture or Clarity, or a clipped blur under an unclipped one, the patch's outer ring is worked out from made-up (edge-copied) pixels, and that leaks into the middle.
- **How to trigger it:** two or more blur-type adjustment layers (Gaussian Blur, Sharpen, Adjust Photo with detail sliders) over a picture with detail.
- **Why:** `let reach = min(stack.filter(\.isVisible).compactMap { $0.adjustment?.reach }.max() ?? 0, 400)`: it's a max, where a sum of the visible adjustments' reaches is needed (still capped). Two 100 px blurs need about 600 px each way; they get 301.
- **Leah's steps:**
  1. Open `TestImages/Photo Editing/Color Chart.png`.
  2. Layer ▸ New Adjustment Layer ▸ Gaussian Blur, and set its Radius to 100. Do the same again, so there are two.
  3. Put the pointer at the middle of the Gray 255 (white) patch. Note the position and hex in the status bar.
  4. File ▸ Export…, PNG, Color: Keep Document's. Open the exported PNG and put the pointer at the same position.
  - Expected: the same hex both times.
  - Bug: the two hexes differ by a few levels.
- **Test that would catch it:** core test: two `.gaussianBlur(radius: 20)` adjustment layers over a small image with a bright stripe off to one side; `colorAsShown` at a point must equal `flattened()` there.

## 4. With a big blur adjustment, the readout re-renders a large patch of every layer on each mouse move, while drawing too
- **Severity:** Low (lag, not lost work)
- **Confidence:** Medium (worked out from the code, not measured)
- **Where:** `Sources/Colorbee/StatusBar.swift:13`, `Sources/Colorbee/Editor.swift:1353`, `Packages/ColorbeeCore/Sources/ColorbeeCore/Canvas.swift:403-416`, `Sources/Colorbee/CanvasView.swift:475`
- **What happens:** `pointerColor` is worked out inside the status bar's view, so it reruns every time the pointer changes, and `updatePointer` changes it on every drag event as well as every move. With a 100 px Gaussian Blur adjustment the patch is 603 × 603 pixels: every layer, hidden ones too, is copied at that size (about 1.5 MB each), the stack is composited, and the blur makes three more copies and three box passes, all on the main thread. On a document with many layers that can take longer than a frame, so brush strokes lag while the status bar is showing. CLAUDE.md's limit is 16 ms per input event.
- **How to trigger it:** a document with 10 or more layers and a Gaussian Blur adjustment near 100 px; draw with the Brush while the status bar is on.
- **Why:** the patch cost grows with the reach squared times the number of layers. Nothing skips the work while a drag is drawing, or reuses the last patch when the pixels haven't changed.
- **Leah's steps** (only if she wants to feel it):
  1. Open `TestImages/Several Layers/Opacity Test.colorproj`. Press ⌘J on a layer a few times, so there are about 10 layers.
  2. Add a Gaussian Blur adjustment layer at the top with Radius 100.
  3. Choose a pixel layer, then draw quick scribbles with the Brush, first with the status bar showing, then with View ▸ Status Bar off.
  - Bug: strokes trail behind the pointer more with the status bar on.
- **Test that would catch it:** a Release-only performance test (`make perf`): `colorAsShown` on a 10-layer canvas with a 100 px blur adjustment, with a time limit, or an app test that the readout isn't recomputed during a stroke.

## 5. A huge number in Export's size limit crashes Colorbee
- **Severity:** Low (a crash, but only on a number nobody would mean; it's remembered, so every later limited export crashes until it's changed)
- **Confidence:** High
- **Where:** `Sources/Colorbee/ImageDocument.swift:563`
- **What happens:** `Int(limitAmount * …)` traps when the result is bigger than `Int.max`, which takes 10,000,000,000,000 MB (or 10,000,000,000,000,000 KB). The value is saved as soon as it's typed, so the next Export… with the limit on crashes again until the number is changed.
- **How to trigger it:** type a number with 14 or more digits in the MB box and export.
- **Why:** `var limitBytes: Int { max(1, Int(limitAmount * (limitInMegabytes ? 1_000_000 : 1000))) }`. Clamping the Double first (for example to 10 GB) avoids it. Review J22 was the same kind of thing (NaN in Resize and Skew).
- **Leah's steps** (save other work first; this quits Colorbee):
  1. Open `TestImages/Photo Editing/Bright Photo.png`.
  2. File ▸ Export…, Format JPEG, tick "Limit file size to", choose MB.
  3. Type `10000000000000` in the box, press Tab, then click Save.
  - Expected: it saves (the limit is far above the file's size).
  - Bug: Colorbee quits.
  4. Open Export… again and change the number back to `200` KB.
- **Test that would catch it:** move the bytes calculation into a small function the tests can reach and test it with `1e13` MB and `.infinity`.

## 6. Edit ▸ Copy Color as Hex, chosen with the mouse, always beeps
- **Severity:** Low (minor)
- **Confidence:** High
- **Where:** `Sources/Colorbee/DocumentWindow.swift:230-235` and `:494-495` (always enabled), `Sources/Colorbee/CanvasView.swift:839-843`
- **What happens:** The command copies the color under the pointer, but to reach the menu the pointer has left the canvas, and leaving clears `editor.pointer`. So clicking the menu item always beeps and copies nothing. Only ⌃⌘C works. This is the "enabled when it would do nothing" case from the plan.
- **How to trigger it:** click Edit ▸ Copy Color as Hex.
- **Why:** `case #selector(newSnapshot(_:)), #selector(trim(_:)), #selector(copyColorHex(_:)): return true`. Validating on `editor.pointerColorHex != nil` would grey it out when opened with the mouse and still let ⌃⌘C work (macOS validates a key equivalent while the pointer is still on the canvas). That costs one readout per validation, the same as the status bar's.
- **Leah's steps:**
  1. Open `TestImages/Photo Editing/Color Chart.png` and hover over the Red patch.
  2. Move the mouse up to the menu bar and choose Edit ▸ Copy Color as Hex.
  - Expected: greyed out (or it copies `#D92B2B`).
  - Bug: it's enabled, beeps, and nothing is copied.
- **Test that would catch it:** app test: with `editor.pointer = nil`, `validateMenuItem` for `copyColorHex:` returns false.

## 7. Opening Perspective Correction flattens and copies the whole picture on the main thread
- **Severity:** Low (a pause when the tool opens on a big image)
- **Confidence:** High for where the work runs; Medium for how long it takes
- **Where:** `Sources/Colorbee/Editor.swift:3018`
- **What happens:** Before the background rectangle search starts, `canvas.flattened()` and `ImageCodec.makeCGImage` (which copies the pixels) run on the main thread. On an 8000 × 8000 picture with several layers that's a full composite plus a 256 MB copy before the bar can respond. Auto-Redact does the same work in the background because of review E6.
- **How to trigger it:** open Image ▸ Perspective Correction… on a very big, layered image.
- **Why:** `guard let image = try? ImageCodec.makeCGImage(canvas.flattened(), colorSpace: canvas.colorSpace) else { return }` runs before the `Task`. Flattening from `canvas.copy()` inside a detached task, as `beginAutoRedact` does, would move it off the main thread. `cornerSearch` already drops a late result.
- **Leah's steps:** none needed; it only shows on pictures far bigger than the test images (make one with Image ▸ Resize and Skew… to 8000 px wide, duplicate the layer a few times, then open Perspective Correction and see whether the window pauses).
- **Test that would catch it:** a Release-only performance test: opening Perspective Correction on an 8000 × 8000, 4-layer canvas returns within a frame.
