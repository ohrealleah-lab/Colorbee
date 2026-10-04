# Review F: the screen versus the saved file
Reviewed at commit: 4df0688a13fec06f1b76403bd5f4993544cc9c6c
Checked:
- `Shaders.metal` against `BlendMode.swift` and `Compositing.blend`, line by line: all 17 blend modes (formulas, the overlay argument swap, soft light's two branches, `lum` weights 0.3/0.59/0.11, `clipColor`, `setSat`), straight versus premultiplied alpha, how source alpha and layer opacity combine, and the empty-backdrop case. They match.
- `Renderer.swift` layer loop against `Canvas.composite`/`compositePixels`/`flattened`: hidden and zero-opacity layers skipped on both sides, adjustment layers composited in stack order, the floating selection drawn just above its layer with the layer's opacity and blend mode on both sides, canvas scissoring, checkerboard (display only)
- `AdjustmentCompositing.swift` against `fadeIn`; the round-1 `ChannelTable` fix (`adjust_channel_fragment` reads exact table entries; correct)
- `FloatingSelection.swift` (`rendered`, `stamp`, the transparent key: exact RGB on both sides), `SelectionActions.placeFloating`, `Compositing.draw`
- Pending shapes (`renderedPendingShape` and the overlay pass; preview and placing use the same `ShapeRenderer` pixels) and pending text (`CanvasTextView` against `TextRenderer`)
- `ImageCodec.encode`: JPEG over Color 2, embedded profile through `makeCGImage`, lossy quality for JPEG/HEIC, TIFF compression; `SaveSnapshot`, `ExportPreset` sizes and resampling; the metal layer's `colorspace` is the document's, so 100% on screen and the file use the same color space
- `TextRenderer.swift` and `Shapes.swift`, as far as preview versus placed output goes

Apart from the findings below, what's exported matches what the screen shows at 100%, up to rounding of a level (half floats on screen, 8-bit steps on export).

**Hand-tested by Leah on 2026-10-04:** all three findings confirmed. While setting up finding 3 she also found that dragging layers to reorder them in the Layers panel doesn't work. That's outside this session's area and will be covered in session G.

## 1. Pending shapes, pending text and floating selections look different once placed on a layer that isn't Normal at 100%
- **Severity:** High (the result changes the moment it's placed; what the user approved isn't what they get)
- **Confidence:** High. Confirmed by hand with the Multiply steps below: the yellow rectangle was plain yellow while pending and turned dark on Return.
- **Where:**
  - Pending shape: `Sources/Colorbee/Renderer.swift:313-319`. The overlay is drawn after the active layer with `blendMode = 0` but at the layer's opacity, since `uniforms.opacity` is still the layer's from `:228`.
  - Floating selection: `Renderer.swift:301-312` and `Packages/ColorbeeCore/Sources/ColorbeeCore/Canvas.swift:224-231`. It's blended separately above its layer, with the layer's mode and opacity applied a second time.
  - Placing all three: `FloatingSelection.stamp` (`FloatingSelection.swift:76-83`) and `Compositing.draw` (`Compositing.swift:26-39`), as used by `Editor.commitPendingShape`/`commitPendingText` (`Editor.swift:1237`, `:1384`). These composite Normal over the layer's own pixels, and only then is the layer blended with its mode and opacity.
  - Pending text: `Sources/Colorbee/CanvasTextView.swift`. It's an `NSTextView` laid over the whole canvas view, so it shows on top of every layer, at full opacity, in Normal.
- **What happens:**
  - **Layer below 100% opacity:** before placing, the layer's own pixels under the object still show through; after placing, they're replaced. Example: a 50% layer with a blue area, a red shape over it, on white. Before placing it's ½ red + ¼ blue + ¼ white (purple-tinted). After, it's ½ red + ½ white.
  - **Blend mode:** a shape is previewed in Normal, but once placed it takes the layer's mode. On a Multiply layer, a red arrow is drawn plain red while being edited and darkens to red × what's below once placed. A floating selection gets the mode applied twice before placing and once after.
  - **Text:** while typing, text is shown above layers that will cover it, and at full strength on a faded layer. After placing, it can disappear under an opaque upper layer or turn faint.
  - **Projects:** `ProjectFile.encode` stamps a floating selection into its layer the same way (`ProjectFile.swift:56-65`), so a project saved with a floating selection reopens looking different from the screen.
- **How to trigger it:**
  1. File ▸ New, then fill the Background with strong blue (Fill tool).
  2. Layer ▸ New Layer, and set its blend mode to Multiply (opacity 100%).
  3. Set Color 2 to yellow, choose Shapes ▸ Rectangle with Fill set to Solid, and drag out a rectangle. While pending it's plain yellow.
  4. Press Return: it turns dark at once (yellow × blue is black).
  - The color under the shape has to be on a layer below. Color on the same layer is simply replaced by the placed shape, so both versions look alike.
  - For the opacity case, the shape must be filled: a thin outline hides the difference.
- **Why:** The previews add the object above the layer's blended result. Placing puts the object inside the layer, then blends the layer. The two agree only for Normal at 100%.
- **Test that would catch it:** Core test: canvas with a 50% Multiply layer, a floating selection on it, and `flattened()` before and after `SelectionActions.placeFloating`; expect equal pixels. The fix belongs in the display/export side or the placing side. For example, preview by compositing the object into a temporary copy of the layer's tile area, or place by blending at the layer's settings. Which behavior is right is Leah's call; log it in §23. The same comparison for a pending shape needs the Editor, or a core helper that both the overlay and placing use.

## 2. Saving or exporting while a resized paste is still floating writes it blocky, though the screen and placing show it smooth
- **Severity:** Medium (wrong pixels in the file)
- **Confidence:** High. Confirmed by hand: the exported PNG was blocky.
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/Canvas.swift:202-204` (`floating.rendered(using: .nearestNeighbor, …)` always), `ProjectFile.swift:58` (also always nearest); against `Renderer.swift:303-304` (linear when stretched and Smooth is on) and `SelectionActions`/`FloatingSelection.stamp` (uses `context.resampling`, Smooth by default per §23 2026-10-01)
- **What happens:** A floating selection that's been resized is drawn smooth on screen and placed smooth, but every file made while it's still floating draws it nearest-neighbor. That includes ⌘S, autosave, File ▸ Export…, Export As presets, Share, Print, Copy of the whole image, and saving a project. A 4× enlarged paste comes out as 4 × 4 blocks.
- **How to trigger it:** Paste a small image (say 100 × 100). Drag a corner handle to make it 400 × 400 (Smooth is the default). Without pressing Return, choose File ▸ Export… and save a PNG. The PNG shows blocky pixels where the screen shows smooth ones. Press Return: the canvas is smooth again.
- **Why:** `compositePixels` and `ProjectFile.encode` hard-code `.nearestNeighbor` instead of the resampling the selection uses (`SelectionContext.resampling`). The canvas doesn't know the setting, since it's the Editor's `smoothResize`.
- **Test that would catch it:** Core test: a 2 × 2 checker floating selection stretched to 8 × 8. `flattened()` should equal what `placeFloating` with `.smooth` produces. That means passing the resampling into `flattened`/`composite`/`ProjectFile.encode`, or storing it on `FloatingSelection`.

## 3. Zoomed out, and when a stretched paste is shown smooth, transparent edges get dark or colored fringes that aren't in the image
- **Severity:** Medium (the screen shows halos that the export doesn't have)
- **Confidence:** High. Confirmed by hand: a thin grey outline along the top of the green waves at 50%, with black on the layer underneath (the 100% view wasn't reported).
- **Where:** `Sources/Colorbee/Shaders.metal:55` and `:167` (`layer.sample(...)` on straight-alpha texels, premultiplied only afterwards); `Renderer.swift:225` (linear sampling below 100%), `:304` (linear for a stretched floating selection)
- **What happens:** Layer textures hold straight alpha, and linear filtering mixes neighboring texels *before* premultiplying. So the color stored in fully transparent pixels bleeds into the visible edge.
  - **Erased pixels** are transparent black, so the edges of erased areas or of pasted PNGs show a dark fringe when zoomed out.
  - **Remove Background** keeps the original colors in the pixels it makes transparent (it only lowers alpha), so a cut-out shows a halo in the old background's color, such as a green fringe around a subject removed from grass.
  - The export, export presets and placing all scale in premultiplied color (`Resampling.smooth` premultiplies first), so none of them has the fringe. At 100% and above, nearest sampling avoids it.
- **How to trigger it:**
  1. Open `TestImages/Stage 9 Practice Photo.png` and choose Image ▸ Lift Subject to New Layer.
  2. Make the bottom layer active, set Color 1 to black, choose Edit ▸ Select All, then Effects ▸ Batch Redact ▸ Solid Fill with Color 1. Press ⌘D.
  3. Zoom to 50%: a thin light outline (the removed sky's color) runs along the top edge of the green waves. At 100% it's gone.
  - Black underneath is needed: on the checkerboard, a light fringe is hard to see.
- **Why:** Bilinear filtering of straight-alpha data. The standard fix is to filter premultiplied colors: either sample four texels with `read`, premultiply, then interpolate by hand in the shader, or keep a premultiplied copy for the zoomed-out view.
- **Test that would catch it:** No headless test for the shader. By hand: the steps above. A small check: a 2-pixel texture `[opaque white, transparent black]` sampled halfway should give premultiplied (0.5, 0.5, 0.5, 0.5) (white at half alpha), not (0.25, 0.25, 0.25, 0.5).
