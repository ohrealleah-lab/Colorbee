# Review O: correctness, threads and the speed fixes
Reviewed at commit: eccf0c1571ac06e5470b598048ab6c2e3309093b
Checked:
- `ColorMemory.swift`: the 64 MB table bound to `Atomic<UInt32>`, relaxed loads and stores, results for see-through pixels. Safe: every entry is written whole, and two cores working out the same color write the same value. Same results as without it (the color step never looks at alpha).
- `Effects.swift`, `Effects+Photo.swift`: the loops made parallel (blur scratch copy, coverage, alpha fix-up, Sharpen, the copy-back) write only their own rows and give the same pixels as the serial loops; `weight`/`mixed` for soft selections (see finding 3).
- `ResizeSkew.swift`: the parallel Skew gives the same pixels as the old loop in both directions and both samplings.
- `Warp.swift`: `Warp.rotated` (center and direction pinned by the 90°/180° test on odd sizes; premultiplied fill with alpha; edge extend for Crop to fit) and `StraightenPlan` (see finding 2).
- `MatchSurroundings.swift`: the job copies its pixels on the main thread; PatchMatch bands write only their own pixels and read other bands from the pass before, so it's repeatable; every source index stays inside the picture; cancellation; memory (finding 8); thin surroundings (finding 14).
- `RetouchStroke.swift`, `CoveragePainter.swift`: Clone Stamp, local brushes, Smudge, Match Tone (findings 3, 9, 13).
- `RedEye.swift`, `Subjects.swift`, `SelectionMask.swift` (`feathered`, `combine`, `inverted`, `hardened`), `FloodFill.swift`, `Gradient.swift`, `ParallelRows.swift`.
- `Canvas.swift` (`clipBaseIndex`, `canClip`, `clippedAdjustments`, `clipped(_:)`, `composite`, thumbnails, `copy()`, `pixelAsShown`), `Layer.swift`, `LayerActions.swift` (Merge Adjustment, Merge Down, New Layer, Duplicate), against `Renderer.swift` and `Shaders.metal` (findings 1, 5, 6, 7, 10).
- `RawDeveloper.swift`, `DevelopWindow.swift`: the shared preview filter under its `Mutex` is used one preview at a time and is let go when the window closes (the session is freed once a running preview finishes). No problem found.
- `Editor.swift`: Straighten's background preview, Apply and Cancel; Remove and Spot Heal fills and their cancel flag; retouch brushes; Feather; Remove Red-Eye. `CancelFlag.swift`.

Earlier rounds' fixes I re-checked and found still in place: review A5 (an undone preview step is forgotten), B1 (autosave takes the preview step back), F1 (unplaced objects drawn into their layer before blending).

---

## 1. Saving, exporting, sharing and Duplicate Page forget "Only the layer below"
- **Severity:** Critical (the saved project loses a setting, and exports look different from the screen)
- **Confidence:** High
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/Canvas.swift:52-67` (`copy()` copies name, visibility, opacity, blend mode, lock and adjustment, but not `clipsToLayerBelow`). It's used by `Sources/Colorbee/Editor.swift:3941` (`saveSnapshot`, which every save and export goes through), `Editor.swift:746` (`duplicatePage`), `Editor.swift:670, 814, 3147` (the "As Opened" baseline), `Editor.swift:3656` (Auto-Redact's text reading).
- **What happens:** the copy every save and export is made from has each clipped adjustment turned back into an ordinary one. So:
  - A saved .colorproj doesn't record the switch (`ProjectFile.swift:84` writes `clipped` only when the layer it's given has it). Reopen the project, or relaunch after an autosave, and the adjustment changes everything below it.
  - Export, Export As presets, Export as PDF, Share, Set as Desktop Picture, and ⌘C with nothing selected (`DocumentWindow.swift:94`) all flatten the copy, so the adjustment changes the whole picture instead of one layer.
  - Page ▸ Duplicate Page makes a page where the adjustment changes everything.
  - Copy Merged, Print and the screen are right, because they use the live canvas. That's likely why Leah's test on 2026-10-10 passed, and why the core test (`ClippedAdjustmentTests`, which encodes the live canvas directly) passes.
- **How to trigger it (Leah can test by hand):** test file `TestImages/Stage 9 Practice Photo.png`.
  1. Open the file.
  2. Layer ▸ New Layer. With the Brush, paint a thick scribble in the middle of the photo.
  3. Layer ▸ New Adjustment Layer ▸ Invert Colors. The whole picture inverts.
  4. In the Layers panel, turn on **Only the layer below**. Now only the scribble is inverted; the photo looks normal.
  5. File ▸ Export… as a PNG, and open the PNG in Preview. **Expected:** normal photo, inverted scribble. **If this finding is right:** the whole photo is inverted.
  6. File ▸ Save as a Colorbee project, close it, and open it again. **Expected:** the switch is still on and the photo looks normal. **If this finding is right:** the switch is off and the whole photo is inverted.
  7. (Before step 6) Page ▸ Duplicate Page. **If this finding is right:** the new page shows the whole photo inverted.
- **Why:** `Canvas.copy()` predates the clipping feature and was never given the new setting:
  ```swift
  copy.blendMode = layer.blendMode
  copy.isLocked = layer.isLocked
  copy.adjustment = layer.adjustment
  return copy
  ```
- **Test that would catch it:** a core test that clips an adjustment, takes `canvas.copy()`, and expects `copy.layers[i].clipsToLayerBelow` to match and `copy.flattened()` to equal `canvas.flattened()`; and an app test that encodes through `Editor.saveSnapshot().encodedProject()`, decodes, and expects the switch to survive.

## 2. A Straighten turn still running after Cancel can crash Colorbee if the image is then rotated or flipped
- **Severity:** Critical (crash)
- **Confidence:** Medium (the race is real in the code; hitting it depends on timing)
- **Where:** `Sources/Colorbee/Editor.swift:2797-2818` (`renderStraightenPreview` starts `plan.render()` in a detached task), `Editor.swift:2840-2844` (`stopStraightenPreview` only changes a token; the task keeps running), `Packages/ColorbeeCore/Sources/ColorbeeCore/Warp.swift:261-291` (`StraightenPlan` holds the live layer buffers, and `render()` reads them layer after layer), `Warp.swift:50` (`buffer.copy()`), `Canvas.swift:92-101` (`transform` calls `swapContents`), `PixelBuffer.swift:39-41, 70-81`.
- **What happens:** Cancel puts the original layer buffers back in the canvas, but the background turn is still reading them, one layer at a time (about 0.15 s per layer on a big photo, per the code's own comment). Image ▸ Rotate or Image ▸ Flip right after Cancel calls `layer.buffer.swapContents(with: layer.buffer.transformed(...))` on those same buffer objects. The swap hands the old memory to a temporary buffer, which is freed (`munmap`) at the end of that line, while the background thread may be copying from it, or reads `width`, `height` and `baseAddress` from different sides of the swap. Either way it reads freed or out-of-range memory, which crashes. The comment on `StraightenPlan` ("must not change while it renders: during the Straighten session they're in the canvas or in the newest undo step") holds during the session, but not after Cancel, because the render outlives the session.
  Painting or filling right after Cancel races the same way, but only gives the discarded result torn pixels, which is harmless.
- **How to trigger it:** not practical by hand. It needs a large photo with several layers and a quick hand, and very large images are what froze Leah's Mac before, so please don't try it with big pictures. The engineer can show it with a test.
  For reference only: a photo of about 6000 × 4000 with 4 layers; Image ▸ Straighten…, drag the slider, press Esc at once and immediately choose Image ▸ Rotate ▸ 90° Right.
- **Why:** nothing makes the render wait for, or stop reading, the buffers once the session ends, and rotation is the one edit that frees a buffer's memory in place instead of replacing the buffer object.
- **Test that would catch it:** an app test with Thread Sanitizer on: a multi-layer canvas, start a Straighten preview, cancel, apply a rotation at once, and wait for the task. TSan reports the race. A fix could have `render()` copy each layer's pixels on the main thread when the plan is made (the plan is already made there), or make Cancel wait for, or stop, the running render.

## 3. Soft edges go dark next to see-through pixels: Clone Stamp, Fill in a feathered selection, Smudge, and the Blur and Sharpen brushes
- **Severity:** High (wrong pixels in a main workflow)
- **Confidence:** High
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/CoveragePainter.swift:107-110` and `182-185` (`Compositing.lerp`), `FloodFill.swift:27`, `Effects.swift:302-305` (`mixed`), `RetouchStroke.swift:117-123` (Blur and Sharpen), `RetouchStroke.swift:192-195` (Smudge).
- **What happens:** pixels are stored with straight (not premultiplied) alpha, but these places mix two pixels channel by channel, alpha included, as if the colors were premultiplied. When one of the two pixels is see-through, its hidden color (black on a new layer) is mixed in. Half of opaque white mixed with transparent gives (128, 128, 128, alpha 128): a half-transparent **gray**, where it should be half-transparent white. Every soft edge laid onto, or next to, transparency comes out darker.
  - **Clone Stamp on an empty layer** (the workflow FR-4.6 suggests: "retouch on an empty layer above the photo"): every soft brush edge leaves a dark ring.
  - **Fill** inside a feathered selection on a transparent layer: a dark band all along the soft edge. Gradient doesn't have this problem: it uses `Compositing.over(…, coverage:)`.
  - **Smudge** dragging color out into a transparent area: dark streaks.
  - **Blur and Sharpen brushes** at the edge of a shape on a transparent layer: the shape's edge darkens (black from the transparent neighbors is averaged in), and the edge doesn't actually soften, because alpha is kept.
  - The same mixing in `Effects.mixed` affects effects on a feathered selection where the effect changes alpha (Gaussian Blur near transparency), less visibly.
  - `Pixel.vacated` already handles the transparent case correctly (`FloatingSelection.swift:162-167`), which shows the intent.
- **How to trigger it (Leah can test by hand):**
  Clone Stamp, test file `TestImages/Stage 13/Remove Sky.png`:
  1. Open the file. Layer ▸ New Layer (an empty layer above the photo stays selected).
  2. Choose Retouch (J) ▸ Clone Stamp. In the Retouch gallery, turn on **Sample All Layers**.
  3. In the palette bar, set the size to about 80 and Hardness to 0.
  4. Option-click on the sky, then paint a short stroke on another part of the sky.
  5. **Expected:** the copied sky blends in with no seam. **If this finding is right:** a darker ring follows the edge of the stroke. (For comparison: undo, select the photo layer, turn off Sample All Layers, and do it again. No ring.)

  Fill, no test file needed:
  1. File ▸ New (a white image). Layer ▸ New Layer.
  2. Draw a selection box in the middle. Edit ▸ Feather…, 30 px, Apply.
  3. Make Color 1 white. Choose the Fill tool and click inside the box.
  4. **Expected:** nothing visible changes (white on white). **If this finding is right:** a gray frame appears along the soft edge.

  Blur brush:
  1. File ▸ New. Layer ▸ New Layer. With the Brush and a bright yellow Color 1, paint a thick line.
  2. Retouch ▸ Blur, Strength 100%, size about 60. Brush along the line's edge a few times.
  3. **Expected:** a softer yellow edge. **If this finding is right:** the edge turns brownish-dark and stays just as hard.
- **Why:**
  ```swift
  static func lerp(_ a: Pixel, _ b: Pixel, _ t: Float) -> Pixel {
      func mix(_ x: UInt8, _ y: UInt8) -> UInt8 { UInt8((Float(x) + (Float(y) - Float(x)) * t).rounded()) }
      return Pixel(r: mix(a.r, b.r), g: mix(a.g, b.g), b: mix(a.b, b.b), a: mix(a.a, b.a))
  }
  ```
  Mixing straight-alpha pixels needs the colors weighted by alpha (premultiply, mix, unpremultiply), as `Warp` and `Compositing.adjust` already do. The local Blur needs the same: average premultiplied, and blur alpha too, or leave edges with transparency alone.
- **Test that would catch it:** core tests: `Compositing.lerp(.clear, white, 0.5)` (or its replacement) is white at alpha 128; a feathered fill of white on an empty layer has r = g = b = 255 wherever alpha > 0; a Clone Stamp stroke on an empty layer from an all-white source has no pixel with r < 255.

## 4. Sample All Layers copies the adjustment layers' look in, so it's applied twice
- **Severity:** High (wrong pixels)
- **Confidence:** High
- **Where:** `Sources/Colorbee/Editor.swift:1693` (Clone Stamp source) and `Editor.swift:1769` (Remove and Spot Heal), both `canvas.flattened()`.
- **What happens:** `flattened()` is the whole picture as shown, including adjustment layers, even ones above the active layer. The retouched pixels are written into the active layer, and any adjustment layer above it then changes them again. With the suggested set-up (photo, empty retouch layer, an Adjust Photo or other adjustment layer on top), every Clone Stamp or Remove result comes out adjusted twice: brighter, more saturated, or (with Invert) back to the original colors. Pixel layers above the active layer are copied in too, so text or a logo above can be cloned into the photo layer. Photoshop has "Current & Below" and "Ignore Adjustment Layers" options for exactly this.
- **How to trigger it (Leah can test by hand):** test file `TestImages/Stage 13/Remove Sky.png`.
  1. Open the file. Layer ▸ New Layer.
  2. Layer ▸ New Adjustment Layer ▸ Invert Colors. The picture inverts.
  3. In the Layers panel, click the empty layer (Layer 1) to make it active.
  4. Retouch (J) ▸ Clone Stamp, with **Sample All Layers** on. Option-click a spot and paint somewhere else.
  5. **Expected:** the copied area looks inverted like everything else. **If this finding is right:** it shows the original, un-inverted colors.
  6. Same with Retouch ▸ Remove: paint over something; the filled area comes out un-inverted.
- **Why:** the sample is taken from the very top of the stack, not from the active layer and what's below it, without the adjustments that will apply to the result anyway.
- **Test that would catch it:** a core or app test: photo, empty layer, Invert adjustment layer on top; clone with Sample All Layers on the empty layer; `flattened()` in the cloned area must equal `flattened()` at the source.
- **Decision for Leah:** what "Sample All Layers" should read: the layers at and below the active one, without adjustment layers above it (my suggestion, since that's what keeps the result looking right), or something else.

## 5. A new layer added just above a layer with "Only the layer below" adjustments takes them away from it
- **Severity:** Medium (wrong look; undoable)
- **Confidence:** High
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/LayerActions.swift:9` (New Layer), `:22` (New Adjustment Layer), `:95` (Duplicate Layer), `Subjects.swift:97` (Lift Subject to New Layer), all inserting at `activeLayerIndex + 1`; `Canvas.swift:117-122` (`clipBaseIndex`).
- **What happens:** the clipped adjustments sit directly above their layer. With that layer selected, New Layer, Duplicate Layer and Lift Subject put the new layer between them, and the adjustments now change the new layer (often an empty one) instead of the layer they were on. A new ordinary adjustment layer put there cuts them off completely ("Layer below only: none"). Making a layer and painting on it is the most common next step, so this will surprise.
- **How to trigger it (Leah can test by hand):** test file `TestImages/Stage 9 Practice Photo.png`.
  1. Do steps 1–4 of finding 1 (a scribble layer with Invert set to Only the layer below).
  2. Click the scribble layer (Layer 1) in the Layers panel.
  3. Layer ▸ New Layer.
  4. **Expected:** the scribble stays inverted. **If this finding is right:** the scribble goes back to its normal colors, and the Invert row now points at the new, empty Layer 2.
  5. Undo, then try Layer ▸ Duplicate Layer (⌘J) with Layer 1 selected: only the copy is inverted.
- **Why:** insertion doesn't skip over the active layer's clipped adjustments.
- **Test that would catch it:** core test: pixel layer with a clipped adjustment, `LayerActions.add` with the pixel layer active; `flattened()` before and after must be equal.
- **Decision for Leah:** whether a new layer should go above the layer's clipped adjustments (my suggestion; it's what Photoshop does), or stay where it is.

## 6. Merge Down (and Delete) on a layer with "Only the layer below" adjustments moves them onto the layer below
- **Severity:** Medium (wrong look; undoable)
- **Confidence:** High
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/LayerActions.swift:121-131` (`mergeDown` composites `[upper]` alone, then removes it).
- **What happens:** Merge Down merges the upper layer without its clipped adjustments (they aren't in the stack it composites), then removes it. The adjustments are left directly above the lower layer, so they now change the merged layer: everything that was on the lower layer gets them too. The picture changes, though a merge should keep the look, as Merge Adjustment and Merge Visible do. Deleting the layer, or moving it, does the same by the current rule ("clips to the nearest layer below"); that may be what Leah wants, but she hasn't been asked.
  Smaller, same family: Merge Adjustment leaves *hidden* clipped adjustments of the merged layers in place (`LayerActions.swift:36-44`), so showing one later changes the whole merged layer, not the layer it was on.
- **How to trigger it (Leah can test by hand):** test file `TestImages/Stage 9 Practice Photo.png`.
  1. Do steps 1–4 of finding 1.
  2. Click the scribble layer (Layer 1). Layer ▸ Merge Down.
  3. **Expected:** photo normal, scribble inverted, as before. **If this finding is right:** the whole photo is inverted.
  4. Undo. Select Layer 1 and press ⌘⌫ (Delete Layer). The scribble goes, and the Invert now inverts the whole photo.
- **Why:** `lower.buffer = canvas.composite([upper], onto: lower.buffer)`. `clipped(_:)` only applies clips that are in the stack it's given.
- **Test that would catch it:** core test: Merge Down on a pixel layer with a clipped adjustment keeps `flattened()` unchanged.
- **Decision for Leah:** Merge Down: bake the upper layer's clipped adjustments into it first (keeps the look), or carry them along? Delete: drop its clipped adjustments, keep them unclipped, or let them move down?

## 7. The Eyedropper's Option-click ignores "Only the layer below"
- **Severity:** Medium (wrong color picked)
- **Confidence:** High
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/Canvas.swift:329-343` (`pixelAsShown` builds one-pixel copies of the layers without `clipsToLayerBelow`).
- **What happens:** the picked color treats a clipped adjustment as if it changed every layer below. So Option-click on the photo next to a clipped layer picks the photo's color with the adjustment applied, which isn't what's on screen (review I, finding 8 promised "as shown").
- **How to trigger it (Leah can test by hand):** test file `TestImages/Stage 9 Practice Photo.png`.
  1. Do steps 1–4 of finding 1.
  2. Choose the Eyedropper. Option-click on a plain part of the photo, away from the scribble.
  3. **Expected:** Color 1 becomes the photo's color there, as you see it. **If this finding is right:** Color 1 is the inverted color.
- **Why:** the copies set `opacity`, `blendMode` and `adjustment` only.
- **Test that would catch it:** core test: `pixelAsShown` equals `flattened()` at the same point on a canvas with a clipped adjustment.

## 8. A large Remove uses several gigabytes, and keeps running after its window is closed
- **Severity:** Medium (memory blow-up; can freeze the Mac)
- **Confidence:** Medium (the sizes are worked out from the code, not measured)
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/MatchSurroundings.swift:49-66` (context and per-pixel `SIMD4<Float>`), `:77, :97, :441-445, :494-495` (copies made while running); `Sources/Colorbee/Editor.swift:1764-1800`; cancel only from Esc on the canvas (`CanvasView.swift:913-914`).
- **What happens:**
  - The surroundings searched reach as far again as the area on every side, so an area a third of the picture wide already takes in the whole picture. Every pixel of that is stored as four Floats (16 bytes, four times the image). While the finest level runs there are three such copies (the job's, the level's after `upsampled` writes to it, and `vote`'s `updated`), plus the match field and its `before` copy (8 + 8 bytes a pixel over the whole context, not just the area), the summed table (4) and more. That's about 70 bytes per pixel: roughly 1.7 GB for a 24-megapixel photo and 3 GB for a 45-megapixel one, on top of the document and its history. The brush is at most 300 px, but a stroke can be any length.
  - Nothing stops a fill when its window closes, the page changes, or the image changes: only Esc on the canvas sets the cancel flag. The job runs to the end on all cores, holding that memory, and its result is then thrown away.
  - After Esc, a new Remove can start at once while the old job is still finishing its current pass (cancellation is checked only between passes), so two can briefly run together.
  - The job's set-up (copying the surroundings into Floats) and `canvas.flattened()` run on the main thread.
- **How to trigger it:** best confirmed by the engineer with a measurement. Please don't try it by hand on big photos. For a gentle look: open `TestImages/Stage 9 Practice Photo.png`, Retouch ▸ Remove at size 300, scribble over about half the photo, and watch Colorbee's memory in Activity Monitor while "Filling…" shows. By the numbers above it should rise by about 100 MB for this small photo, against about 6 MB for the photo itself.
- **Why:** the working arrays are sized to the whole context at 16 bytes a pixel, and copied by value.
- **Test that would catch it:** a Release-only test (`make perf`) that runs a Remove over a large area and checks peak memory, plus an app test that closing the editor (or changing the image) sets the fill's cancel flag. Ideas for the fix: limit the context (or work on a reduced copy for large areas), keep Float pixels only for the context actually searched, cancel when the window closes or the image changes, and refuse areas over a size with a message.

## 9. Smudge starting at the canvas edge rubs see-through black into the picture
- **Severity:** Medium (wrong pixels)
- **Confidence:** High
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/RetouchStroke.swift:170-187`.
- **What happens:** the first dab fills the brush's "carried paint" from the pixels under it, but only for the part on the canvas; the part hanging off the edge stays (0, 0, 0, 0). As the brush moves in, that empty paint is laid down: the photo gets dark, half-transparent smears coming in from the edge, even on an opaque background layer.
- **How to trigger it (Leah can test by hand):** test file `TestImages/Stage 13/Remove Sky.png`.
  1. Open the file. Retouch (J) ▸ Smudge. Size about 150, Strength 100%.
  2. Press with the pointer right on the left edge of the picture (half the brush circle outside), and drag to the right into the sky.
  3. **Expected:** the sky's colors smear along. **If this finding is right:** a dark smear that's partly see-through (the checkerboard shows) comes in from the edge.
- **Why:** `carried = [SIMD4<Float>](repeating: .zero, …)`, and only the pixels in `area` (clipped to the canvas) are copied in on the first dab.
- **Test that would catch it:** core test: an opaque layer, a smudge stroke starting with its center on x = 0 and moving right; every pixel stays opaque.
- **Possible fix:** fill the off-canvas part of the carried paint from the nearest edge pixel, or don't lay down paint the brush never picked up.

## 10. The Redact Brush's red stroke doesn't show while painting if the active layer is an adjustment layer or hidden
- **Severity:** Medium (no feedback while redacting)
- **Confidence:** High
- **Where:** `Sources/Colorbee/Renderer.swift:313-323` (the overlay is drawn only inside the visible pixel layer that's active); `Sources/Colorbee/Editor.swift:1610` (the Redact Brush doesn't need a pixel layer, rightly, since it changes every layer).
- **What happens:** the see-through red stroke is drawn into the active layer as part of drawing it. If the active layer is an adjustment layer (they're skipped before the overlay is drawn), or is hidden or at 0% opacity (skipped by the loop), the stroke is painted blind; the redaction appears only on letting go. Smaller: on a layer with clipped adjustments, the red overlay is drawn before them, so it's recolored (Invert turns it cyan; Desaturate turns it gray).
- **How to trigger it (Leah can test by hand):** test file `TestImages/Help/Sample Screenshot.png`.
  1. Open the file. Layer ▸ New Adjustment Layer ▸ Hue/Saturation (leave it at zero; it becomes the active layer).
  2. Choose the Redact Brush (K) and slowly paint over the email address.
  3. **Expected:** the red see-through stroke follows the pointer. **If this finding is right:** nothing shows until you let go; then the redaction appears.
- **Why:** `let overlay = layer.id == canvas.activeLayer.id ? scene.overlay : nil` is reached only for visible pixel layers.
- **Test that would catch it:** hand test above (renderer). A fix could draw an overlay that belongs to no layer (the Redact Brush, Remove's area) above the whole stack.

## 11. Remove Red-Eye ignores a feathered selection's soft edge
- **Severity:** Low
- **Confidence:** High
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/RedEye.swift:69-71`.
- **What happens:** every red pixel the selection touches at all is fixed fully. FR-3.4 says everything that uses a selection follows its soft edge, half-selected pixels changing halfway. Hard to see, since only clearly red pixels change.
- **How to trigger it:** `TestImages/Stage 13/Red Eye Practice.png`: draw a selection box over one eye, Edit ▸ Feather… 30 px, then Adjustments ▸ Remove Red-Eye. The red right out to the soft edge is fixed as fully as in the middle.
- **Why:** `{ x, y in mask[x, y] > 0 }`, then `row[x] = fixed`.
- **Test that would catch it:** core test: a red patch, a mask at 128; the fixed pixel's red is halfway between the original and the fully fixed value.

## 12. The Feather sheet's slider works out the feather on the main thread on every move
- **Severity:** Low (performance)
- **Confidence:** Medium
- **Where:** `Sources/Colorbee/Editor.swift:2287-2293`; `Packages/ColorbeeCore/Sources/ColorbeeCore/SelectionMask.swift:180-206`.
- **What happens:** each slider tick builds the whole feathered mask on the main thread: a per-pixel copy through the bounds-checked subscript, three box blurs, then `trimmed()` scanning it all. With Select All on a large photo, that's well over a frame per tick, so the slider and its tint stutter (the "main thread never blocks for more than a frame" rule).
- **How to trigger it:** `TestImages/Stage 9 Practice Photo.png`, Image ▸ Resize and Skew… to 300%, Select All, Edit ▸ Feather…, and drag the slider. It lags behind the pointer.
- **Why:** `marqueePreview = original.feathered(…)` on every `setFeatherRadius`.
- **Test that would catch it:** a Release-only timing test of `feathered` on a 20-megapixel mask. A fix could work it out in the background and merge slider moves, like the effect previews do, and copy rows in bulk instead of pixel by pixel.

## 13. The Clone Stamp's Match Tone runs on the main thread when the stroke ends
- **Severity:** Low (performance)
- **Confidence:** Medium
- **Where:** `Sources/Colorbee/Editor.swift:1720-1728`; `Packages/ColorbeeCore/Sources/ColorbeeCore/RetouchStroke.swift:206-285`.
- **What happens:** `ToneMatch.apply` spreads the edge differences inward ring by ring, going over every remaining pixel on each ring. For a long, wide stroke (300 px brush across a big photo) that's hundreds of millions of steps on the main thread, so Colorbee pauses after letting go. The same work for Spot Heal runs in the background.
- **How to trigger it:** `TestImages/Stage 9 Practice Photo.png`, Clone Stamp at size 300 with Match Tone on; Option-click a source, then paint one long stroke across the whole photo. After letting go there's a noticeable pause before the result appears.
- **Why:** it's called inline in `endRetouchBrush`.
- **Test that would catch it:** a Release-only timing test of `ToneMatch.apply` on a 300 × 4000 mask.

## 14. Remove can silently do nothing when there's little picture around the area
- **Severity:** Low
- **Confidence:** Low (worked out from the code)
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/MatchSurroundings.swift:96` and `:222-255`; `Sources/Colorbee/Editor.swift:1781-1786`.
- **What happens:** at each coarser level the area grows (a pixel is in the area if any of the four under it is) and a thin ring of picture around it shrinks. If at some level no patch center 3 pixels in from the edge lies outside the area, `sources()` returns nil, the job throws `Cancelled`, `try?` turns that into nil, and the Editor just redraws. No message, nothing changes. Images 6 pixels or less on a side always end this way, unless the surroundings are one flat color.
- **How to trigger it:** hard to show by hand. To confirm: a core test with a 200 × 100 busy image and an area covering all but a 10-pixel border.
- **Why:** `guard let sources = level.sources() else { throw Cancelled() }`, and the Editor treats a nil fill the same as Esc.
- **Test that would catch it:** that core test, expecting either a fill or a distinct error that the Editor reports ("Not enough around this area to fill from").
