# Review I: drawing tools and selections (stages 1–5)
Reviewed at commit: fc427a185d70d559a8e27f11b456ceed5833f65c
Checked:
- `Pixel.swift`, `Compositing.over`: straight-alpha source-over, including at alpha 0
- `AxisLock.swift`: waits for a 1-pixel move, then stays locked; Pencil only (FR-4.1)
- `DabWalker.swift`: a click with no movement makes one dab; fast moves are evenly spaced with pressure blended; no division by zero
- `RoundBrushStroke.swift`: sizes 1 and 50; pressure 0 draws at a quarter of the size; Marker at half alpha. Pencil and Eraser walk Bresenham lines, so fast moves leave no gaps. Off-canvas points use `rounded(.down)`.
- `BrushStroke.swift`, `Brush.swift`, `BrushTexture.swift`, `PaintStyle.swift`: radius never 0; taper and spacing guards; calligraphy mirroring
- `CoveragePainter.swift`, one stroke on its own: max coverage, edge clipping, and the Eraser's Color 2 (or transparency) per `vacatedFill`
- `FloodFill.swift`:
  - 4-connected scanline, iterative, with no gaps or leaks through diagonal gaps.
  - Tolerance 0 and 100% work, and fill is clipped to the selection.
  - A seed outside the canvas or selection does nothing.
  - 1 × 1 and 1 × N images work.
  - The global (non-contiguous) wand is correct.
- `Gradient.swift`: a zero-length drag draws nothing; premultiplied mixing; clipped to the selection; right-drag reverses
- `Shapes.swift`: tiny drags are dropped; the Shift constraint; arrow, heart and textured bounds (only the cloud is clipped, finding 11)
- `TextRenderer.swift`: clipping at the canvas edges; the opaque background; strikethrough position
- `SelectionMask.swift`:
  - Rectangle and ellipse are clipped to the canvas.
  - Polygon and lasso use even-odd fill at pixel centers. The preview and the result agree.
  - A polygon with under 3 points, or no area, gives nil.
  - `combine` works in every mode; `inverted` and `trimmed` are fine.
- Marquee: includes both end pixels, works in every drag direction, and is clipped; dragging fully outside the canvas deselects
- Add, Subtract and Intersect modifiers (FR-3.2); Invert, Select All and Deselect place a floating selection first
- Move, nudge (arrows, Shift+arrows by 10) and ⌘-arrow resize: pixels past the edge are kept while floating, and clipped when placed
- `SelectionHandle.swift`: never flips and never goes below 1 × 1; no division by zero
- What Delete leaves behind (`vacatedFill`): Color 2 only on the original Background of a solid image, transparent elsewhere (FR-3.3, §23)
- `Viewport.swift`: the conversions are exact inverses; zoom is limited to 12.5–3200%; zooming keeps the point under the pointer fixed
- `CanvasView.swift`: coalescing is off (`AppDelegate.swift:7`); flipped view coordinates; right-click with Color 2 for Pencil, Brush, Eraser, Fill, Eyedropper, Gradient and Shapes; tablet pressure; the airbrush timer
- `Editor.swift`: strokes, fill, gradient, shapes and text are refused on locked and adjustment layers; `finishInteractions` runs before layer switches

Not re-reported: rounds 1 and 2 in `RESULTS.md`. Review G already covered selection undo.

**Hand-tested by Leah on 2026-10-04:**
- **Finding 1:** confirmed, and worse than the right-edge case: Colorbee **crashed** on pressing Delete.
- **Findings 3, 4, 5, 8 and 10:** confirmed.
- **Finding 2:** confirmed. With a ⌘V paste floating and the Magic Wand chosen from the toolbar, a click on the white area away from the paste selected the whole canvas, and Delete then wiped the paste.
  - Separately: pressing **W** while the ⌘V paste floats beeps instead of choosing the Magic Wand. W works when nothing is floating.
  - I couldn't find the cause in the code. `CanvasView.keyDown` → `ShortcutStore.canvasCommand` → `selectTool(.magicWand)` has no floating-selection case, and a beep there means the key didn't reach a canvas command, so it may be keyboard focus after the paste. P beeps too in the same state, so this is general: after a ⌘V paste, tool keys stop reaching the canvas.
    - So most likely the canvas isn't first responder after the paste.
    - Clicking the canvas to get the keys back moves or places the paste, so there's no harmless way back.
    - A fix: `window.makeFirstResponder(canvasView)` after a paste, and check why focus left the canvas.
- **Findings 7, 9 and 11–16:** not hand-tested.

**Leah's decisions (2026-10-04), for the FRD §23 log:**
- **Question at the end:** yes, the Magic Wand and Fill get a "Sample All Layers" option.
- **Finding 6:** keep the Color Eraser tolerance (FR-4.3, default 0%).

## 1. Delete or Cut on a selection that reaches past the canvas edge writes outside the image's memory
- **Severity:** Critical (pixels nobody selected are overwritten, and Undo doesn't fully restore them; off the top or bottom edge it writes outside the image's memory, likely a crash)
- **Confidence:** High that it writes out of bounds; Medium on which outcome a given case produces
- **Where:**
  - `Packages/ColorbeeCore/Sources/ColorbeeCore/SelectionActions.swift:203-209` (`deleteSelection` loops over `mask.bounds` without clipping to the canvas; `PixelBuffer.row(y)` at `PixelBuffer.swift:79-81` is unchecked).
  - Where such a selection comes from: `Sources/Colorbee/Editor.swift:747-752` (`placeFloatingKeepingOutline` makes the unclipped outline a marquee). It runs when switching to a non-selection tool (`:674-676`), and before Fill, Gradient, effects and Solid Fill. Also `SelectionActions.swift:51-55` (`select` combines with a floating outline in Add mode, which isn't clipped either; `FloatingSelection.outline` and `stretched(to:)` keep off-canvas bounds).
  - Cut: `DocumentWindow.swift:41-47`.
- **What happens:**
  - A moved or pasted selection can hang off the canvas, which is fine while it floats. Choosing a drawing tool places it but keeps its outline as an ordinary selection, still hanging off the canvas. Shift-adding a marquee does the same.
  - Pressing Delete then writes Color 2 (or transparency) into `row[x]` for every selected x and y, including those outside the image:
    - Off the right edge, the extra columns land at the start of the next row: a band down the left edge of the image.
    - Off the bottom or top, it writes before or after the image's memory.
  - `willModify` clips to the canvas, so the undo copy doesn't cover the band once the image is wider than one 256-px tile, and ⌘Z leaves it.
  - Every other user of a selection (effects, Fill, Gradient, Copy, Crop) clips first.
- **How to trigger it:**
  1. File ▸ New, then Image ▸ Canvas Properties: 300 × 300. Fill tool (G): fill it red. Leave Color 2 white.
  2. Rectangle Select (M): select the right third, about x 200 to 299, full height.
  3. Drag inside the selection about 90 px to the right, so most of it hangs off the right edge. Release.
  4. Press P (Pencil). The dashed outline stays.
  5. Press Delete.
  - **Expected:** only the part of the outline still on the canvas turns white.
  - **Actual:** a white band also appears down the left edge, from the second row down, and ⌘Z doesn't take all of it away.
  - **Crash variant** (save your work first): a 1000 × 1000 image, a selection dragged so a few hundred px hang off the *bottom*, then P, then Delete.
- **Why:** `deleteSelection` trusts `mask.bounds` to be inside the canvas, and nothing makes it so.
- **Test that would catch it:** Core: a 300 × 300 canvas with `.marquee` bounds (290, 0, 100, 300). Call `deleteSelection`, then expect pixels (0...69, 1) to be unchanged. Also: `select(_, mode: .add)` with an off-canvas floating selection gives bounds inside `canvas.bounds`. Fix both: clip in `deleteSelection`, and clip an outline to the canvas whenever it becomes a marquee.

## 2. A Magic Wand click while a paste is floating reads the pixels under the paste
- **Severity:** Medium (the wrong area is selected; a following Delete wipes the paste)
- **Confidence:** High
- **Where:** `Sources/Colorbee/Editor.swift:1475-1479` (the mask comes from `canvas.activeLayer.buffer` before `SelectionActions.select` places the floating pixels). The wand is a selection tool, so choosing it doesn't place the paste (`:674`).
- **What happens:** The floating image isn't in the layer yet, so the wand sees what's underneath it. Clicking the background selects through the paste's area as if it weren't there. Shift-clicking a color inside the paste selects by the color underneath instead.
- **How to trigger it:**
  1. File ▸ New (white). Copy any colorful screenshot smaller than the canvas, then ⌘V. It floats at the top-left.
  2. Press W (Magic Wand) and click the white area away from the paste.
  - **Expected:** the white area is selected, with the outline going around the paste.
  - **Actual:** the paste is placed and the whole canvas is selected. Press Delete: the paste is wiped too.
- **Why:** Sampling happens before placing.
- **Test that would catch it:** Move the wand into core (`SelectionActions.magicWand(at:…)`), placing first. Then a 10 × 10 white canvas, a 4 × 4 red paste at (3, 3), the wand at (0, 0) with tolerance 0: expect (4, 4) not selected.

## 3. Fill, Magic Wand and Color Eraser treat transparent pixels as different colors
- **Severity:** Medium
- **Confidence:** High on the cause; Medium on how often it's hit
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/CoveragePainter.swift:134-139` (`Pixel.matches` compares all four channels, even when alpha is 0). It's used by `FloodFill.swift:89` and `:157`, and by `CoveragePainter.swift:118` (Color Eraser). The main source of such pixels is `Subjects.swift:117` (Remove Background and Lift Subject scale alpha only; see review H, finding 7).
- **What happens:**
  - Two fully transparent pixels count as different if their hidden RGB differs.
  - After Remove Background or Lift Subject, filling the empty area at 0% tolerance fills only a speck or scattered pixels. The wand at 10% selects patches shaped like the old background.
- **How to trigger it:**
  1. Open a photo of a person or pet against a busy background.
  2. Image ▸ Lift Subject to New Layer, then hide the bottom layer.
  3. Fill tool, tolerance 0%, Color 1 red: click the empty (checkerboard) area.
  - **Expected:** all of it turns red.
  - **Actual:** only a speck or scattered pixels.
  4. Undo. Magic Wand (W): click the empty area. The selection is patchy.
- **Why:** Nothing treats alpha 0 as one color.
- **Test that would catch it:** A 3 × 1 buffer `(10,20,30,0) (200,0,0,0) (0,0,0,0)`. A fill from x = 0 at tolerance 0 fills all three; the same for `magicWand(contiguous: false)`. Fix: `matches` treats two alpha-0 pixels as equal (or Remove Background writes `.clear`, which also fixes H7).

## 4. With Symmetry on, a stroke and its mirror overwrite each other where they overlap
- **Severity:** Medium (gray specks inside solid paint near the mirror line; the result isn't symmetric)
- **Confidence:** High
- **Where:** `Sources/Colorbee/Editor.swift:783-790` (one stroke, with its own `CoveragePainter`, per mirror); `CoveragePainter.swift:101-103`; `BrushStroke.swift:78` (Oil's tail clean-up)
- **What happens:**
  - Each painter works out a pixel from its *pre-stroke* value and only its own coverage. Where the stroke and its mirror overlap (near the line of symmetry), whichever paints last wins.
  - A soft edge from the mirror replaces solid paint from the original. The guard `value > tileCoverage.values[index]` then stops the original from painting it again.
  - With the Oil brush, the mirror's tail clean-up puts its area back to the pre-stroke pixels, erasing the original's paint where the tails meet.
- **How to trigger it:**
  1. File ▸ New, Canvas Properties 20 × 20, white. Zoom to 3200% with the pixel grid on (⌘').
  2. Symmetry: Vertical. Round brush, press ] until the size is 9, Color 1 black.
  3. Click once just left of the center guide (column 8).
  - **Expected:** one solid black blob, the same on both sides.
  - **Actual:** gray pixels inside the left half (around 3 rows above and below the click) where the right side is black.
- **Why:** Mirrors have separate coverage maps but share one layer.
- **Test that would catch it:** Core: two `RoundBrushStroke`s sharing one `Edit` on a 20 × 20 white layer, dabs at (8.5, 10.5) and (11.5, 10.5), diameter 9. Expect (8, 13) pure black and the image left-right symmetric. Possible fix: mirrored strokes share one coverage map (one painter, several dab positions).

## 5. With Symmetry on, the mirrored Eraser (and sometimes Pencil) lands one pixel off
- **Severity:** Medium (for pixel art, the main use of symmetry)
- **Confidence:** High for the Eraser; Medium for the Pencil
- **Where:** `Sources/Colorbee/Editor.swift:798` (`flipX = width - x`, in continuous coordinates); `RoundBrushStroke.swift:80-84` (`EraserStroke.footprint`: `x - size / 2`) and `:88-91`
- **What happens:**
  - The point is mirrored, then snapped to a pixel, then the square is placed around that pixel. An even-size square isn't centered on its pixel (it reaches `size/2` left and `size/2 - 1` right), so its mirror is off by one. That includes the default size 8.
  - The Pencil is off by one when the pointer is exactly on a pixel boundary: `floor(width - n)` is `width - n`, not `width - 1 - n`. That can happen at 100% zoom on a Retina screen.
- **How to trigger it:**
  1. A 20 × 20 image filled black. Symmetry: Vertical. Zoom 3200%, pixel grid on.
  2. Eraser, size 4: click in the middle of the pixel at column 5.
  - **Expected:** the two erased squares are mirror images: columns 3–6 and 13–16.
  - **Actual:** columns 3–6 and 12–15. There are 3 black columns at the left edge and 4 at the right.
- **Why:** Mirroring happens before snapping and before the square is placed, instead of mirroring the pixel area.
- **Test that would catch it:** Move the mirroring into core and mirror pixel rects: for sizes 1–12 and x in {5.0, 5.5}, the mirrored footprint equals `IntRect(x: W - r.maxX, width: r.width, …)`.

## 6. The Color Eraser has no tolerance setting (FR-4.3)
- **Severity:** Medium (FRD mismatch)
- **Confidence:** High
- **Where:** `Sources/Colorbee/Editor.swift:776-778` (`.replaceMatching(target: color1, tolerance: 0, with: color2)`); the Eraser's palette-bar options (`DocumentView.swift:90-91`) show only a hint
- **What happens:** FR-4.3: "The default tolerance is 0% (exact match); a tolerance setting is available." There's no setting, so anti-aliased edges (text, brush strokes) can't be color-erased: their gray fringes stay.
- **How to trigger it:** Choose the Eraser and look at the palette bar: no Tolerance. Type some black text, place it, then right-drag over it with Color 1 black and Color 2 white. The gray fringe pixels stay.
- **Why:** Hard-coded 0.
- **Test that would catch it:** Core already supports a tolerance: `EraserStroke` with `.replaceMatching(target: .black, tolerance: 10, …)` replaces `(5,5,5,255)`. Add an Editor setting (stored like the Fill tolerance) and pass it through.

## 7. Dragging a selection handle can stretch it to gigabytes, with no size limit
- **Severity:** Medium (a long beachball and a large memory spike, possibly a crash)
- **Confidence:** Medium. The missing limit is certain; how bad it gets depends on the screen.
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/SelectionHandle.swift:31-61` and `SelectionActions.swift:127-131` (no upper limit); `FloatingSelection.swift:60-61` (`rendered` builds the whole stretched image, off-canvas part included), called by placing, and by saving, autosave and export while it floats (`Canvas.swift:204, 254`)
- **What happens:** At 12.5% zoom a handle dragged to the screen corner can make a selection of 27,000 × 18,000 px or more (about 2 GB). Dragging is fine (the GPU stretches it), but placing it, or an autosave while it floats, builds it all on the CPU, and placing runs on the main thread. Resize/Skew and Straighten refuse anything over 30,000 px or 256 megapixels; this path doesn't.
- **How to trigger it:** Open a 2000 × 1500 image, zoom to 12.5%. Marquee a 200 × 200 area and start dragging it (it floats). Drag its bottom-right handle to the bottom-right corner of the screen, release, then press Return. Watch Activity Monitor's memory and the beachball.
- **Why:** No clamp on the destination size, and the off-canvas part is rendered too.
- **Test that would catch it:** `SelectionHandle.resize` with a huge delta is clamped to the Resize/Skew limits; better, `rendered` builds only the part that lands on the canvas.

## 8. Option-click with the Eyedropper doesn't pick the color shown on screen
- **Severity:** Low (FR-4.5: "samples the combined image of all visible layers")
- **Confidence:** High
- **Where:** `Sources/Colorbee/Editor.swift:879-883`
- **What happens:** The layers are stacked with Normal blending and each layer's opacity. Blend modes are ignored, adjustment layers count as transparent, and a floating paste is skipped. With a Multiply layer or any adjustment layer, the color picked isn't the color seen.
- **How to trigger it:** On a white image, Layer ▸ New Adjustment Layer ▸ Invert (the screen turns black). Eyedropper, Option-click: Color 1 becomes white, not black. Or: a red layer in Multiply over blue.
- **Why:** `picked = Compositing.over(picked, layer.buffer[pixel.x, pixel.y], coverage: Float(layer.opacity))`, with no blend mode or adjustment.
- **Test that would catch it:** Move sampling into core, as one pixel of `canvas.flattened()` (or of the same composite code for one point). Then: Invert over white samples black.

## 9. A Force Touch trackpad stroke starts with a full-size dot
- **Severity:** Low
- **Confidence:** Medium (depends on AppKit sending the first pressure event after mouseDown)
- **Where:** `Sources/Colorbee/CanvasView.swift:691` (`trackpadPressure = nil` on mouseDown) and `:663` (`return trackpadPressure ?? 1`)
- **What happens:** No trackpad pressure has arrived at mouseDown, so the first dab is drawn at full pressure. The stroke then quickly shrinks to the real, lighter pressure.
- **How to trigger it:** Round brush, size 50, on a Force Touch trackpad. Press lightly and drag slowly: a big dot at the start, then a thin line.
- **Why:** Defaulting to 1 before the first pressure reading.
- **Test that would catch it:** By hand only. Possible fix: read the mouseDown event's own `pressure`, or hold the first dab until the first pressure event.

## 10. `[` and `]` with the Shapes tool change the brush size, not the line width
- **Severity:** Low
- **Confidence:** High
- **Where:** `Sources/Colorbee/Editor.swift:706-713` (`adjustToolSize` changes `brushDiameter` for every tool but the Eraser); compare `toolSize` at `:682-698`, which uses `shapeLineWidth` for `.shape`
- **How to trigger it:** Shapes tool, draw a rectangle (leave it unplaced), press ] three times. The Size control and the outline don't change. Switch to the Brush: it's 3 px bigger.
- **Test that would catch it:** Editor-level: with `.shape`, `adjustToolSize(larger: true)` raises `shapeLineWidth` by 1. Simplest fix: go through `toolSize`.

## 11. Tall Cloud Callouts have one puff cut flat at the top
- **Severity:** Low
- **Confidence:** High
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/Shapes.swift:285-288` (the puff at 280° reaches about 1.6% of the height above the box) against `:150` (`paintedBounds` adds only `lineWidth + 2`)
- **How to trigger it:** An 800 × 800 image. Shapes ▸ Cloud Callout, drag from about (100, 100) to (700, 700). The top puff just right of center has a flat top.
- **Test that would catch it:** For every `ShapeKind` at a 1000-px box, `paintedBounds` contains the path's bounding box grown by half the line width.

## 12. Each Gradient drag repaints the whole layer on the main thread, on one core
- **Severity:** Low (CLAUDE.md performance rules: `ParallelRows` for whole-image loops; the main thread never blocks for more than a frame)
- **Confidence:** Medium (not measured)
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/Gradient.swift:44-58`, called from `Sources/Colorbee/Editor.swift:912-926` on every drag event
- **How to trigger it:** A 6000 × 6000 image, Gradient tool, Conical, drag around: the gradient lags behind the pointer.
- **Test that would catch it:** A `make perf` test: `Gradients.draw(.conical…)` on the 8000² fixture under a time limit.

## 13. Shift-constrained square or circle marquees can come out one pixel off
- **Severity:** Low
- **Confidence:** High
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/SelectionActions.swift:32-42` (the side is taken from continuous positions, then each axis is rounded down separately)
- **What happens:** From (0.9, 0.1) to (3.0, 2.0), constrained, gives 4 × 3. The existing test `constrainedMarqueeIsSquare` only starts from whole numbers.
- **How to trigger it:** Zoom 3200%, pixel grid on. Rectangle Select: start near the right side and the top of a pixel, hold Shift and drag diagonally. Watch the status bar: sometimes N × (N±1).
- **Test that would catch it:** `marquee(.rectangle, from: (0.9, 0.1), to: (3.0, 2.0), constrain: true)` gives equal width and height. Fix: make the pixel rect square after rounding.

## 14. "Click or drag" for the marquee is measured in image pixels, not on screen
- **Severity:** Low
- **Confidence:** High
- **Where:** `Sources/Colorbee/Editor.swift:1539` (`abs($0.x - start.x) < 1 && abs($0.y - start.y) < 1`)
- **What happens:**
  - Zoomed in, a drag inside one image pixel (up to about 31 points at 3200%) counts as a click and deselects, so a 1 × 1 selection can't be made.
  - Zoomed out to 12.5%, a 1-point wobble during a click makes a small selection instead of deselecting.
  - The Text tool already uses a screen-point threshold (`CanvasView.swift:638`).
- **How to trigger it:** At 3200%, Rectangle Select, drag slowly within one pixel and release: the selection disappears.
- **Test that would catch it:** A helper taking the zoom, tested at zoom 32 and 0.125.

## 15. On a small selection, the resize handles cover all of it, so it can't be moved
- **Severity:** Low
- **Confidence:** High
- **Where:** `Sources/Colorbee/Editor.swift:1432-1447` (6-point handle hit area); `CanvasView.swift:524` (handles are checked before moving)
- **How to trigger it:** A screenshot at about 25% zoom. Marquee a 40 × 20 px area, then drag from its middle: it stretches instead of moving.
- **Test that would catch it:** App-side. Fix: when the selection is small on screen, a press inside it moves rather than resizes (or shrink the hit areas).

## 16. Select Subject's "pick one" click rounds off-canvas positions toward the canvas
- **Severity:** Low
- **Confidence:** High
- **Where:** `Sources/Colorbee/Editor.swift:1961` (`IntPoint(x: Int(point.x), y: Int(point.y))`; `Int()` truncates toward zero, so -0.9 becomes 0. Everywhere else uses `rounded(.down)`)
- **How to trigger it:** With several subjects, Edit ▸ Select Subject, then click in the gray just left of the image's left edge (at high zoom): the subject in column 0 is picked instead of a beep.
- **Test that would catch it:** One helper for "point to pixel", tested with (-0.5, -0.5) → (-1, -1).

## Question for Leah (not a bug)
The Magic Wand and Fill look at the active layer only. On an empty or adjustment layer, the wand selects the whole canvas. A "Sample All Layers" option might be worth a decision.
