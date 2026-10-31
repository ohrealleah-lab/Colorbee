# Review Z: the app side of stages 25 to 32, and smoothing
Reviewed at commit: 079bee95d41f6a27c4bf7bc6590288dc28d764b8
Checked:
- `Renderer.swift` (`drawNodes`, `drawGroup`, `drawAdjustment`, masking, mask-alone view, texture caches) against `Canvas.composite`, `clipped`, `compositePixels`, `Compositing.mixed`, `blendAtop`, `reveal`. Pass Through (with and without opacity or mask), Normal groups, masked layers and groups, clipped adjustments and clipped pixel layers all agree with the core, except finding 1.
- `Shaders.metal`: `mask_reveal`, `blend_layer_fragment` (including the "Only the layer below" path), `blend_isolated_fragment`, `fade_backdrop_fragment`, `mask_alone_fragment`, `QuadUniforms` layout (matches the Swift struct). The formulas match the CPU's.
- `LayersPanel.swift`, `LayerMenu.swift`, `MainMenu.swift` mask menu, `DocumentWindow.validateMenuItem` and `pixelCommands`.
- `StrokePath.swift`, `AxisLock`, and the stroke, Redact Brush and Retouch sections of `Editor.swift`, `CanvasView` drag handling, `SmoothingControl`. Strokes end where you let go (catch-up on every path, including `finishInteractions`); Shift, Symmetry and pressure combine correctly with smoothing; the Pencil is never smoothed. Clean.
- `Editor.shapeFillColor`, the toolbar's Outline/Fill swatch, `hiddenKeepingSpace`, `WindowDragArea`.
- `Tests/ColorbeeTests/Monkey` (all files except the untracked `ZZMonkeyProbe.swift`, which looks like the engineer's work in progress). It saves no preferences (`textIsEditable` and `smoothing` are set directly), never touches the clipboard, and its project check runs in memory, so it leaves no files of its own behind.
- Not re-reported: the Merge Down crash, thumbnail mismatches and paste/fill/mask/resize/crop undo the monkey already found.

## 1. While a paste floats on a layer with "Only the layer below" layers, the export doesn't match the screen
- **Severity:** Medium
- **Confidence:** Medium (the drawing order is certain; I didn't confirm that Export runs without placing the paste first)
- **Where:** `Sources/Colorbee/Renderer.swift:500-549` versus `Packages/ColorbeeCore/Sources/ColorbeeCore/Canvas.swift` `clipped(_:)` and `compositePixels`
- **What happens:** On screen, the floating paste is drawn into its layer first, and then the clipped adjustments and clipped pixel layers are applied on top, so the paste looks adjusted, as it will once placed. `Canvas.flattened` (Export, Save, Copy Merged, thumbnails) applies the clips to the layer's own pixels first, then draws the paste on top of the stand-in. So the export shows the paste without the adjustment (or, for a clipped pixel layer, on top of it instead of under it).
- **How to trigger it:** Use `TestImages/Stage 9 Practice Photo.png`.
  1. Open the picture. Layer ▸ New Adjustment Layer ▸ Invert. In the Layers panel, turn on "Only the layer below".
  2. Click the bottom layer to make it active.
  3. With the Rectangle Select tool, select a small area, then press ⌘C and ⌘V. Leave the paste floating (don't click away).
  4. The paste looks inverted on screen. Choose File ▸ Export and save a PNG.
  5. Open the PNG: the pasted area is **not** inverted.
- **Why:** The renderer's isolated pass draws `layer.buffer`, then `floating`, then `clips`. The core's `clipped()` builds `layer.copy(buffer: buffer)` with the clips already applied, and `compositePixels` puts `floatingPixels` over that copy (same id), after the clips.
- **Test that would catch it:** Core test: a pixel layer with a clipped Invert adjustment and a floating selection over it. `flattened()` must equal the result of placing the paste and then flattening.

## 2. The monkey's undo and save checks only see the visible picture
- **Severity:** Medium
- **Confidence:** High
- **Where:** `Tests/ColorbeeTests/EditorTestSupport.swift:30` (`imageHash`), `Tests/ColorbeeTests/Monkey/MonkeyEpisode.swift` (`UndoTracker`), `MonkeyRules.checkSaving`
- **What happens:** `imageHash` is `canvas.flattened().contentHash()`. So an undo or redo that puts back the wrong pixels on a hidden layer, under a mask, or in a turned-off mask passes. So does one that gets a layer's opacity, blend mode, lock, clip or mask-enabled setting wrong while it doesn't show. The save check also compares only the flattened picture plus names, text, mask presence and group ids. A project that lost a hidden layer's pixels, a hidden layer's settings, `passesThrough`, `clipsToLayerBelow` or a mask's contents would pass. These are the "lost work" bugs this review is looking for, and the 8-hour run can't see them.
- **How to trigger it:** Not by hand. In code: a step that hides a layer, then any undo bug confined to that layer, passes every rule.
- **Why:** Every comparison goes through `flattened()`, which skips hidden layers and applies masks.
- **Test that would catch it:** Give the monkey a document hash covering every layer and mask buffer and every layer setting (visible, opacity, blend mode, locks, clip, mask enabled, pass-through, group id, text). Use it in `UndoTracker` and in `checkSaving` alongside the picture hash. A planted bug (undo skipping a hidden layer's tile) must be caught.

## 3. The monkey moves layers by a path the app never uses
- **Severity:** Medium
- **Confidence:** High
- **Where:** `Tests/ColorbeeTests/Monkey/MonkeyStep.swift` `.moveLayer` → `Editor.moveLayer(from:to:)` (`Editor.swift:4830`) → `LayerActions.move(from:to:)`
- **What happens:** Nothing in the app calls `Editor.moveLayer(from:to:)` any more. The Layers panel's drag and its Move Up/Down actions use `moveLayer(_:to: LayerDrop)` → `LayerActions.moveLayers(_:to:)` (`plannedMove`), which is the stage-26 code for moving into, out of and beside groups. The monkey never runs it. It does run a single-index move that can pull a group row away from its layers, or a layer away from its clipped layers, which then relies on `keepGroupsTogether` to repair it. The user can't make that move.
- **How to trigger it:** Not by hand; it's a gap in coverage.
- **Why:** See the call sites (`grep moveLayer( Sources/`): only `LayersPanel.swift:161` and `:416`, both the `LayerDrop` form.
- **Test that would catch it:** Have the monkey's move step pick a dragged layer and a `LayerDrop` (`.above`, `.below`, `.into`) the way `LayersPanel.drop(onto:movingDown:folded:)` does.

## 4. Invert Mask is enabled but refused on an adjustment layer, group or text layer unless the mask is chosen
- **Severity:** Low
- **Confidence:** High
- **Where:** `Sources/Colorbee/Editor.swift:4651-4654`; `DocumentWindow.swift:550-551`
- **What happens:** The menu item is enabled whenever the active layer has an unlocked mask. But `invertMask()` first runs `refusedBecauseLocked()`, which checks `paintLayer`. When the layer itself (not its mask) is chosen, that's an adjustment layer or group (beep, nothing happens) or a text layer (a wrong "This is a text layer… Rasterize Text first" notice). The core `LayerActions.invertMask` works on any of them.
- **How to trigger it:** Use `TestImages/Stage 9 Practice Photo.png`.
  1. Layer ▸ New Adjustment Layer ▸ Invert.
  2. Layer ▸ Layer Mask ▸ Add Mask.
  3. In the Layers panel, click the adjustment layer's own icon (left of the mask thumbnail).
  4. Layer ▸ Layer Mask ▸ Invert Mask: it's enabled, but you get a beep and nothing changes.
- **Why:** `guard !refusedBecauseLocked() || editsMask else { return }`: with `editsMask` false, `refusedBecauseLocked` refuses any layer that isn't a pixel layer, and any text layer.
- **Test that would catch it:** App test: an adjustment layer with a mask, the layer itself chosen; `invertMask()` adds one step and inverts the mask.

## 5. A layer inside a locked group can still change opacity and "Only the layer below"; its blend mode silently does nothing
- **Severity:** Low
- **Confidence:** High
- **Where:** `Sources/Colorbee/LayersPanel.swift:127` and `:136` (check `layers[active].isLocked`, the layer's own padlock only); `Editor.previewOpacity` (`Editor.swift:4907`, always includes the active layer); `setClipsToLayerBelow` → `LayerActions.update(layerAt:)` (no lock check); `setBlendMode` → `chosenLayerSetting` (skips `canvas.isLocked` layers, with no beep)
- **What happens:** Q25.4 says locking a group locks everything in it. For a layer inside a locked group, the panel's Opacity and "Only the layer below" controls stay enabled and do change the layer, as undo steps. The Blend Mode menu is enabled too, but choosing a mode does nothing and gives no beep.
- **How to trigger it:** Use `TestImages/Stage 9 Practice Photo.png`.
  1. Add a layer (⇧⌘N or the + button) and paint on it.
  2. Press ⌘G to group it, then lock the group with its padlock (Lock All).
  3. Click the layer inside the group.
  4. Drag Opacity to 50%: it changes. Choose Blend Mode ▸ Multiply: nothing happens.
- **Why:** The panel and these setters use the layer's own `isLocked`, not `canvas.isLocked(_:)`.
- **Test that would catch it:** App test: a layer in a locked group; `previewOpacity`/`finishLayerSettings` and `setClipsToLayerBelow` add no step. A view-model check that the controls are disabled.

## 6. The selection outline's texture is never freed after stage 27
- **Severity:** Low
- **Confidence:** High
- **Where:** `Sources/Colorbee/Renderer.swift:255` and `:647`
- **What happens:** Stage 27 added a local `var maskTexture` inside `render`. The older `else { maskTexture = nil }`, meant to drop the cached selection-outline texture (`self.maskTexture`) when there's no selection, now clears that local instead. The shared renderer keeps the last selection's texture, up to one byte per canvas pixel (64 MB at 8000 × 8000), until the next selection.
- **How to trigger it:** Not visible by hand; it's memory held by Colorbee after Select All and Deselect on a big image.
- **Why:** Name shadowing; `texture(for mask: SelectionMask)` reads `self.maskTexture`.
- **Test that would catch it:** Rename the local (for example `layerMaskTexture`) and write `self.maskTexture = nil` at line 647. It can only be checked by reading or by memory measurement.

## 7. Two monkey steps do things the panel wouldn't allow
- **Severity:** Low
- **Confidence:** High
- **Where:** `Tests/ColorbeeTests/Monkey/MonkeyStep.swift` `.clip` and `.opacity`
- **What happens:** `.clip(true)` calls `setClipsToLayerBelow(true)` even where the panel's toggle is disabled (`!canClip`, or the layer is locked). `.opacity` calls `previewOpacity` on a locked active layer, while the panel disables opacity there. The step list claims each step is "always legal", so a failure found this way could be one Leah can't reach.
- **How to trigger it:** Not by hand.
- **Why:** The steps call the editor directly without the panel's `.disabled` conditions.
- **Test that would catch it:** Skip these steps when the panel would disable them (`canClip`, `canvas.isLocked`). Or, better, have the editor refuse them (see finding 5).

## 8. Double-clicking the toolbar's empty space may not follow "Fill"
- **Severity:** Low
- **Confidence:** Low
- **Where:** `Sources/Colorbee/WindowDragArea.swift:17-21`
- **What happens:** Recent macOS versions offer "Fill" as a title-bar double-click action (I believe it's stored as `AppleActionOnDoubleClick = Fill`). The code knows only "Minimize" and "None"; anything else, Fill included, does Zoom. With Fill chosen, the empty toolbar space would zoom while the rest of the title bar fills.
- **How to trigger it:**
  1. In Terminal, run `defaults read -g AppleActionOnDoubleClick` and note the value.
  2. If it says Fill, open any picture in Colorbee and pick the Pencil (so Size's space is hidden).
  3. Double-click the empty space where Size would be, then double-click the title text. Compare the two.
- **Why:** The `switch` has no "Fill" case.
- **Test that would catch it:** By hand only.

## 9. The right-click menu's Edit Text is enabled on a locked text layer
- **Severity:** Low
- **Confidence:** High (overlaps session Y's area)
- **Where:** `Sources/Colorbee/LayerMenu.swift:35`; `Editor.editText(layerAt:)` (`Editor.swift:2346`)
- **What happens:** Rasterize Text, just below it, is greyed out on a locked text layer, but Edit Text is enabled and just beeps.
- **How to trigger it:** Use `TestImages/Stage 9 Practice Photo.png`.
  1. Choose the Text tool, turn Editable on, type a word and click away.
  2. Lock that layer with its padlock (Lock All).
  3. Right-click it: Edit Text is enabled; choosing it beeps.
- **Why:** The item has no `enabled:` condition.
- **Test that would catch it:** By hand, or a menu-building check that it's disabled when `canvas.isLocked(layer)`.
