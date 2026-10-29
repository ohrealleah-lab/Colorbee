# Review V: Adjust Photo, its filters and the screen matching the export
Reviewed at commit: b48dadab8be9bcd4a6a6240bb3234bcfc5e830c8
Checked:
- `PhotoAdjustments.swift`: `colorTransform` (Whites, Dehaze, the chain order), the composed closure (`parts.dropFirst().reduce`, right order, never empty), `isNeutral`, `forFilters`, `filterPart`, `partFiltersLeaveOut`, `vignettes` and `grains` (filter's first, at its intensity, then the panel's own), Codable (`values` keeps only beta 7's sliders, the rest under `added`).
- `ColorMixer.swift`, `ColorGrading.swift`, `PointColors.swift`, `ToneCurve.swift` (`Curves.table` is monotone, so the curve always rises), `PhotoAuto.swift`, `ColorLookup.swift`: math, gray staying gray (Mixer and Black & White: luma weights add to 1, and grays get no shift), scaling by Intensity, file leniency.
- `WhiteBalance.swift`: see finding 2. `averageColor` and `averagedPixel` are fine.
- `PhotoDetail.swift`, `PhotoEffects.swift`, `Effects+Photo.swift`: at their defaults `DetailAmounts` and `Vignette.Shape` give exactly the old arithmetic (old `detail` and `strength(size: 50)`), and beta 7 filters could never hold a vignette, so old projects look as before. The mask view is never applied or copied (cleared in `applyEffect`, `photoAsAdjustmentLayer`, `copyPhotoSettings`, `forFilters`) and never saved (not in `CodingKeys`).
- `Shaders.metal` / `Renderer.swift`: `QuadUniforms` matches the Metal struct field for field (192 bytes). `vignette_strength`, `grain_hash` (same operator precedence in Swift and Metal), `grain_noise` and `grain_offset` match the CPU. Vignettes and grains go in the same order as `photoAdjusted`. The effects buffer is capped at 128 + 128 `float4`s = 4096 bytes, which Metal accepts. Positions use the whole canvas on screen and in exports, clipped or not. Clipping warnings are on screen only and off while comparing. See finding 7 for the blur slots.
- `PhotoFilter.swift`, `ColorLook.swift` (tetrahedral weights checked case by case; the binary table round-trips, sizes and amounts are checked), `CubeFile.swift` (a byte-order mark, Windows line ends, comments, domains, `nan`/`inf`, numbers before the size, too many or too few numbers: all handled), `FilterStore.swift`, `Effect+Codable.swift`.
- Beta 7: checked its `PhotoEdit`, `PhotoFilter`, `Effect` and `ProjectFile` decoding at tag `v0.9.0-beta.7`. New sliders and new `PhotoEdit` keys are skipped as intended; see finding 3 for looks.
- `AdjustPhotoPanel.swift`, `PhotoControls+*.swift`, `ToneViews.swift` (histogram throttle is right: the last change is always shown, background previews refresh it), `ColorWheel.swift`, `RangeSlider.swift`, `PhotoSettingsStore.swift`; `Editor` picture picks, hand drags, Copy, Paste, Same as Last, Save as Filter; `CanvasView` `.pictureAdjust`.
- One note, not a finding: Color Grading's and Point Color's per-pixel functions still loop over a captured list (`for … in parts`, `for entry in picked`), the pattern the 2026-10-28 fix says can count a reference per pixel. Worth one timing in Release; I can't measure it without building.

## 1. Point Color's gray "Range" view can get stuck on, and is then applied, exported and copied
- **Severity:** High (wrong picture applied or exported)
- **Confidence:** High (the Reset Range path); Medium (the keyboard path)
- **Where:** `Sources/Colorbee/PhotoControls+PointColor.swift:56-66`, `Sources/Colorbee/AdjustPhotoPanel.swift:357` (the row's context menu), `Sources/Colorbee/Editor.swift:3813`, `:3876-3882`, `:4022` (only `showsSharpeningMask` is cleared)
- **What happens:** While the Range slider is held, Point Color grays out everything the chosen color doesn't touch (`showsRangeOf`). Only the Range row's `end` turns that off. Control-click ▸ Reset Range calls the row's `set` (which turns the gray view on) and then `onFinish`, not `end`, so the picture stays gray. Nothing else clears `showsRangeOf`: Apply commits the gray picture, As Adjustment Layer makes a gray layer, and Copy Settings, Same as Last and Save as Filter all carry it (in memory, until a relaunch). On an Adjust Photo layer, the gray is committed into the layer, so File ▸ Export is gray. But `showsRangeOf` isn't saved, so after saving and reopening the project, the same layer shows in color: the screen and the export disagree across a reopen.
- **How to trigger it:** Reset Range from the slider's context menu. Probably also arrow keys on the focused Range slider with Full Keyboard Access, or VoiceOver's increment, since SwiftUI's `Slider` doesn't report editing for those.
- **Why:** `row(...){ value in ...; changed.showsRangeOf = chosen; change(changed) }` with `.contextMenu { Button("Reset \(title)") { set(resetValue); onFinish() } }`. `applyEffect` clears `photoEdit.showsSharpeningMask` but nothing touches `pointColors.showsRangeOf`.
- **Leah's steps:**
  1. Open `TestImages/Photo Editing/Color Chart.png`.
  2. Choose Adjustments ▸ Adjust Photo…. In Point Color, click the eyedropper, then click the Red patch.
  3. Drag that color's Hue slider to about +50.
  4. Control-click the Range slider and choose Reset Range.
  - Expected: the picture is back in full color.
  - Bug: everything except the red patch stays gray.
  5. Click Apply.
  - Bug: the gray picture is applied. (⌘Z undoes it.)
- **Test that would catch it:** app test: open Adjust Photo, add a swatch, set `photoEdit.pointColors?.showsRangeOf = 0` as the Range row's `set` does, then `applyEffect()`. The layer must equal the same settings applied with `showsRangeOf == nil`. Do the same for `photoAsAdjustmentLayer`, `copyPhotoSettings` and `saveFilter`.

## 2. Beta 7 turns an Adjust Photo layer into an empty layer when its filter is an imported look
- **Severity:** Medium (edge case: work lost in the older version, and for good if saved there)
- **Confidence:** High
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/Effect+Codable.swift:18` (`.look` written as a filter step); beta 7's `PhotoEdit.init(from:)` and `PhotoFilter.init(from:)` (tag `v0.9.0-beta.7`)
- **What happens:** FRD §23 (2026-10-27) says beta 7 "still opens the rest" of an adjustment that uses newer settings. That holds for new sliders and keys, but not for a filter holding a `.look` step. Beta 7 decodes a `PhotoEdit`'s filter with `try`, and the filter's steps as a strict `[Effect]`. Its `Effect` decoding throws "Unknown effect look", so the whole `PhotoEdit` fails. `AdjustmentEntry` then reads the adjustment as none, and the layer opens as an empty, see-through pixel layer: the look, every slider and the layer's purpose are gone. Saving in beta 7 makes that permanent. Leah's everyday copy is beta 7, and no new beta comes until every stage is done.
- **How to trigger it:** any project with an Adjust Photo layer (or a "Save Filter from Layers" filter inside one) whose filter came from a .cube, opened in beta 7.
- **Why:** beta 7: `filter: try container.decodeIfPresent(PhotoFilter.self, forKey: .filter)` → `try container.decode([Effect].self, forKey: .steps)` → `default: throw ... "Unknown effect \(kind)"`. Today's `PhotoFilter.encode` (synthesized) writes the look into `steps` beside the steps beta 7 knows. Whether to keep looks somewhere beta 7 doesn't read (as `added` does for sliders) or accept this is Leah's call.
- **Leah's steps** (in a test build, `make run`):
  1. Open `TestImages/Photo Editing/Color Chart.png`.
  2. Choose Adjustments ▸ Adjust Photo…. In the filters' ⋯ menu choose Import Filter… and pick `TestImages/Photo Editing/Looks/Warm.cube`. It's chosen.
  3. Set Exposure to +30, then click As Adjustment Layer.
  4. Save it as a Colorbee project wherever you like, and quit.
  5. Open that project in your everyday beta 7. **Don't save it there.**
  - Expected (§23): an Adjust Photo layer with Exposure +30 (the look itself missing is fine).
  - Bug: the layer named "Warm" is an empty layer; the picture shows neither the look nor the Exposure.
- **Test that would catch it:** core test with a copy of beta 7's strict decoding (an `Effect` decoder that throws on `look`, `PhotoFilter` steps as `[Effect]`): decode a `PhotoEdit` that has a filter with a look and Exposure +30. It must keep Exposure.

## 3. Importing a large .cube look freezes Colorbee (about 1 second at 65 points, about 7 at 129)
- **Severity:** Medium (freeze)
- **Confidence:** High (timed)
- **Where:** `Sources/Colorbee/FilterStore.swift:95-99` (called on the main thread from `FilterMenu.importFilter`, `AdjustPhotoPanel.swift:467`); `Packages/ColorbeeCore/Sources/ColorbeeCore/CubeFile.swift:38-71`
- **What happens:** `CubeFile.read` runs on the main thread. It trims and splits every line through Foundation and makes a `[Double]` of every number. I timed the unchanged `CubeFile.swift` and `ColorLook.swift`, built with `-O` in a scratch folder: a 65-point look (7 MB, the biggest size the code comment says is in common use) took 0.86 s; a 129-point one (57 MB, the largest allowed) took 6.7 s. Nothing reads in the background meanwhile, and there's no spinner. The filter is then written to `Photo Filters.json` (about 17 MB of base64 for a 129-point look), also on the main thread.
- **How to trigger it:** Import Filter… with a 65- or 129-point .cube.
- **Why:** `for rawLine in text.split(whereSeparator: \.isNewline) { let line = rawLine.trimmingCharacters(in: .whitespaces) ... line.split(...) ... Double(word) }`, roughly 3 µs a line × 2.1 million lines.
- **Leah's steps:** the looks in `TestImages/Photo Editing/Looks/` are 17 and 33 points, which import quickly, so this needs a 65-point look (most film looks from camera makers are). With one: Adjust Photo ▸ ⋯ ▸ Import Filter…, choose it. Expected: no pause. Bug: about a second with the pointer spinning (about seven seconds at 129 points).
- **Test that would catch it:** core performance test (Release, `make perf`): `CubeFile.read` of a generated 65-point file under a set limit (say 0.2 s); and an app check that the import doesn't run on the main actor.

## 4. Adjust Photo: Same as Last works the whole photo out on the main thread
- **Severity:** Medium (freeze on a large photo)
- **Confidence:** High that it's on the main thread; Medium on how long it takes (estimated, not run)
- **Where:** `Sources/Colorbee/Editor.swift:3823-3826` → `applyAdjustment` (`:3952-3960`)
- **What happens:** Same as Last calls `applyAdjustment`, the path Invert and Desaturate use, which runs `Effects.apply` right away on the main thread. That's cheap for Invert. For Adjust Photo with Noise Reduction, Texture, Definition or Sharpness, it's up to four blurred copies of the photo, then the detail and color work on every pixel. On a 20 to 60 MP photo that's likely a half second to a few seconds with Colorbee not responding. CLAUDE.md: "Heavy effects run off the main thread. The main thread never blocks for more than a frame." The panel's Apply doesn't have this problem, because its preview is already worked out in the background.
- **How to trigger it:** Same as Last after applying settings with detail sliders, on a big photo.
- **Why:** `func applySameAsLastPhoto() { ... applyAdjustment(.photo(last)) }` and `applyAdjustment` calls `Effects.apply(effect, to: canvas.activeLayer, ...)` directly.
- **Leah's steps:**
  1. Open `TestImages/Photo Editing/Texture Practice.png` and make it 6400 × 4000 with Image ▸ Resize and Skew… (⌘E).
  2. Choose Adjustments ▸ Adjust Photo…, set Sharpness 50, Definition 50, Texture 50 and Noise Reduction 50, and click Apply. Then Edit ▸ Undo.
  3. Choose Adjustments ▸ Adjust Photo: Same as Last.
  - Expected: no pause, as with Apply in step 2.
  - Bug: Colorbee stops responding for a moment, perhaps with a spinning pointer.
- **Test that would catch it:** app test that Same as Last returns before the work is done (works it out in the background and commits when ready, like Remove or Feather), or a Release time limit on the main-thread part.

## 5. The white-balance eyedropper misses gray when the Tone Curve, Color Mixer, Point Color or Color Grading is set
- **Severity:** Medium (wrong result in an edge case: the opposite color cast)
- **Confidence:** High (the arithmetic); the numbers below are estimates
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/WhiteBalance.swift:11-21`; the order is in `PhotoAdjustments.swift:249-255`
- **What happens:** The eyedropper reads the sample after everything (`neutral.colorTransform(sample)`) and solves Warmth and Tint as if they were applied last ("Warmth and Tint are the last steps"). But since stages 4 to 6, the Tone Curve, Color Mixer, Point Color and Color Grading come after them. A curve steepens the cast it's measured on, so Warmth overshoots and the sample comes out with the opposite cast. With Darks −100 and Lights +100 (slope about 1.9 at the middle), a slightly blue gray needing about +26 Warmth gets about +49, and comes out clearly warm. The Color Mixer's Saturation and Point Color do the same for their colors. Color Grading's tint is added after, so it's only slightly off. The doc comment promises gray "after all of them".
- **How to trigger it:** any curve, Mixer or Point Color setting that changes how strongly the sampled spot's cast shows, then the eyedropper.
- **Why:** `let before = neutral.colorTransform(sample)` includes `curve, mixer?.transform, pointColors?.transform, grading?.transform`. The curve, the Mixer and Point Color all keep grays gray, so solving on the color just before Warmth (the filter steps and the sliders only) would give exact gray at the end. Color Grading tints grays on purpose, so whether the eyedropper should cancel that is Leah's call.
- **Leah's steps:**
  1. Open `TestImages/Photo Editing/Color Chart.png`.
  2. Choose Adjustments ▸ Adjust Photo… and click the Vivid Cool filter. The gray patches turn slightly blue.
  3. In Tone Curve, set Darks to −100 and Lights to +100.
  4. Click the eyedropper beside Warmth, then click the Gray 128 patch.
  - Expected: Gray 128 comes out neutral gray.
  - Bug: it comes out warm, orange-ish, and Warmth reads about +50. For comparison, set Darks and Lights back to 0 and click the patch again: it's gray, with Warmth about +26.
- **Test that would catch it:** core test: a `PhotoEdit` with a blue-ish filter and a steep `ToneCurve` (also one with Mixer Blue saturation +100); `neutralizing(sample)` then `colorTransform(sample)` must give R, G and B within 2 levels.

## 6. Esc during a hand drag on an Adjust Photo layer leaves the change outside History, and closing can lose it
- **Severity:** Low (a small change can be lost)
- **Confidence:** Medium
- **Where:** `Sources/Colorbee/CanvasView.swift` `handleKey` (Esc → `cancelPicturePick`), `Sources/Colorbee/Editor.swift:3658-3661` (`cancelPicturePick` clears `pictureDrag`), `:3753-3757` (`endPictureDrag` returns early)
- **What happens:** Dragging with the hand on an Adjust Photo layer changes the layer through `previewAdjustment`, which opens `layerSettingsEdit`. Pressing Esc before letting go clears `pictureDrag`, so the mouse-up's `endPictureDrag` returns at once and `finishLayerSettings` never runs. The layer keeps the new curve, but there's no History step and the document isn't marked edited (`recordingChanges` only runs on commit). Closing the window doesn't ask to save and the change is gone. The open edit is only committed later, by the next command or Undo, as part of that.
- **How to trigger it:** mouse down with the hand on, drag, Esc, mouse up.
- **Why:** `func cancelPicturePick() { picturePick = nil; pictureDrag = nil }` and `func endPictureDrag() { guard let drag = pictureDrag else { return } ... finishLayerSettings() }`.
- **Leah's steps:**
  1. Open `TestImages/Photo Editing/Dull Photo.png`. Choose Layer ▸ New Adjustment Layer ▸ Adjust Photo, then save it as a project.
  2. In the Adjustments panel's Tone Curve, click the hand.
  3. Press on the picture and drag up so it brightens. While still holding the button, press Esc, then let go.
  - Expected: a new step in the History panel, and the window shows it has unsaved changes.
  - Bug: no new step, and File ▸ Close closes without asking. Open the project again: the brightening is gone.
- **Test that would catch it:** app test: `togglePicturePick(.toneCurve)` on an Adjust Photo layer, `beginPictureDrag`, `continuePictureDrag`, `cancelPicturePick`, `endPictureDrag`. Then `history.revision` must have changed (or the layer must be back as it was).

## 7. With Sharpness's own Radius, the other detail blurs are lost for a frame; on every frame while the window resizes
- **Severity:** Low (a flicker on screen; exports are fine)
- **Confidence:** Medium
- **Where:** `Sources/Colorbee/Renderer.swift:647-658` (`preparedBlurTargets`), `:288-304`
- **What happens:** The Adjust Photo layer blurs into slots 0 to 2 (fine, wide, medium), then slot 3 for Sharpness's own radius. `preparedBlurTargets(count: 4)` remakes all four targets when fewer than four exist or the size changed, which throws away the slot 0 to 2 blurs already made for this frame. The shader then reads new, empty (or leftover) textures. For that frame, Noise Reduction, color noise, Texture, Definition and Masking show as off (or as garbage). This happens the first time, and on every frame of a live window resize, because each new size remakes the targets with three, then with four.
- **How to trigger it:** an Adjust Photo layer with Sharpness Radius changed from 1.2 plus Noise Reduction, Texture or Definition; resize the window.
- **Why:** `let count = max(count, 3); if blurTargets.count >= count, <same size> { return blurTargets }` … `blurTargets = (0..<count).map { ... }`. It's called from `blur(slot: 0)` with 3 and later from `blur(slot: 3)` with 4 in the same frame.
- **Leah's steps:**
  1. Open `TestImages/Photo Editing/Texture Practice.png`. Choose Layer ▸ New Adjustment Layer ▸ Adjust Photo.
  2. Set Texture to −100 and Noise Reduction to 100 (the picture looks smooth), Sharpness to 30, and in Sharpness's finer settings, Radius to 2.5.
  3. Drag the window's corner slowly to resize it.
  - Expected: the picture stays smooth.
  - Bug: while resizing, the texture flickers back (or odd colors flash).
- **Test that would catch it:** hard to test headless; a unit check that `preparedBlurTargets` with a larger count keeps the existing targets (grows the list rather than remaking it) would cover it.

## 8. Double-clicking a Color Grading wheel on an Adjust Photo layer leaves extra undo steps
- **Severity:** Low
- **Confidence:** Medium (depends on SwiftUI delivering the drag on each click, which `minimumDistance: 0` does)
- **Where:** `Sources/Colorbee/ColorWheel.swift:45-67`
- **What happens:** Each click of a double-click is also a zero-length drag. A click away from the point "lands the point where it was clicked" and calls `onFinish`, which on a layer commits a step. Then the double-tap resets and commits another. One double-click makes two or three "Adjustment Settings" steps, and the first Undo after resetting puts the wheel where you double-clicked, a tint you never chose.
- **How to trigger it:** double-click a wheel away from its point, on an Adjust Photo layer.
- **Why:** `DragGesture(minimumDistance: 0).onChanged { ... onChange(Self.wheel(at: point, ...)) }.onEnded { ...; onFinish() }` plus `.simultaneousGesture(TapGesture(count: 2).onEnded { onChange(...reset...); onFinish() })`.
- **Leah's steps:**
  1. Open `TestImages/Photo Editing/Color Chart.png`. Choose Layer ▸ New Adjustment Layer ▸ Adjust Photo.
  2. In Color Grading's Shadows tab, drag the wheel's point out toward blue and let go.
  3. Double-click the wheel near its orange edge. The point goes back to the middle.
  4. Choose Edit ▸ Undo.
  - Expected: the point goes back to blue (step 2).
  - Bug: it goes to the orange edge where you double-clicked. The History panel shows extra steps for the double-click.
- **Test that would catch it:** a by-hand check (SwiftUI gestures aren't driven in app tests); or a wheel model that ignores `onChange` for the first click of a click count of 2.

## 9. The eyedroppers and the hand on an "Only the layer below" Adjust Photo layer read the whole picture, not the layer it changes
- **Severity:** Low
- **Confidence:** High
- **Where:** `Sources/Colorbee/Editor.swift:3671-3682` (`pictureSample`, `.layer` case)
- **What happens:** For an Adjust Photo layer, the white-balance eyedropper, Point Color's eyedropper and the hand sample `canvas.patchAsShown(area, through: activeLayerIndex - 1)`: every layer below, blended. A clipped layer only changes the layer below it, before that layer's opacity and blend mode. So where that layer is see-through, faded, or not Normal, the picked color is a mix that the adjustment never sees. Point Color's Range then misses the layer's real color, and white balance corrects for the background too.
- **How to trigger it:** a clipped Adjust Photo layer over a layer that isn't fully opaque and Normal.
- **Why:** `case .layer: return canvas.patchAsShown(area, through: canvas.activeLayerIndex - 1)...` doesn't look at `clipsToLayerBelow`.
- **Leah's steps:**
  1. Open `TestImages/Several Layers/Opacity Test.colorproj`.
  2. Click the Red layer and set its opacity to 50%: the stripes show through the red block.
  3. Choose Layer ▸ New Adjustment Layer ▸ Adjust Photo, and turn on "Only the layer below".
  4. In Point Color, click the eyedropper, then click the red block.
  - Expected: the new color dot is the red block's own red (what this layer changes).
  - Bug: the dot is a paler, mixed red (red at 50% over the stripes).
- **Test that would catch it:** app test: a clipped Adjust Photo layer above a 50%-opacity red layer over white. `pickFromPicture` with Point Color must add pure red.
