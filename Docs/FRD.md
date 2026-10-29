# Colorbee — Functional Requirements Document

**Version:** 2.3.0 · **Date:** 2026-10-10 · **Owner:** Leah (PM)  
**Platform:** macOS 26 or later, Apple Silicon  
**Audience:** Personal tool, with one user (Leah). No App Store, no public distribution.  
**Scope:** Everything in this document ships. The build order in §20 is a sequence, not a list of cuts.

This document is the single source of truth for *what* Colorbee does. Engineering rules for *how* it's built live in [`CLAUDE.md`](../CLAUDE.md). The original v1 spec is kept at [`reference/paint_osx_prd_frd_v1.md`](reference/paint_osx_prd_frd_v1.md).

---

## 1. Vision

Colorbee is a fast, native raster editor for macOS with the immediacy of classic MS Paint. It adds the modern editing features a product manager needs every day: redacting screenshots, annotating, cropping, making quick comparisons and sending images straight to Slack or email.

### 1.1 Design principles
1. **Instant.** The app is ready to draw almost as soon as you launch it. No splash screen, onboarding or template picker.
2. **One window.** Every toolbar, palette and panel is docked in a single window. The only floating UI is the system Color Panel.
3. **Single layer by default, depth when you want it.** Layers are one toolbar click away.
4. **Two colors.** Left-click uses Color 1 and right-click uses Color 2, for every tool.
5. **Exact pixels.** Rendering is sharp at every zoom level, and coordinates are always whole pixels.
6. **Editing first.** Redaction, annotation and export are the fastest paths through the app.
7. **macOS conventions.** Standard Mac shortcuts, document behavior and autosave apply. Where Windows Paint and macOS disagree, macOS wins, except for the deliberate exceptions listed in the decision log (§23).
8. **A paint program first.** Simple diagrams (boxes, arrows, callouts, labels) are in scope. Structured diagramming or mind-mapping (live objects, attached connectors, node trees) is not.

---

## 2. Primary use cases

| Use case | What it needs |
|---|---|
| **Redact and annotate a screenshot** (primary) | Paste with Cmd+V, blur/pixelate, automatic redaction, batch redaction, arrows and callouts, text, crop, before/after check, copy or export for Slack |
| **Pixel art and icons** | 1px pencil, nearest-neighbor zoom up to 3200%, pixel grid, color eraser, symmetry, custom palettes |
| **Casual drawing and memes** | Brushes, fill bucket, airbrush, shapes, Shift-drag smear |
| **Light compositing** | Magic wand cutout, alpha, gradients, layers, blend modes, adjustment layers |
| **Minor photo editing** | Levels and Curves, white balance, vibrance, crop, vignette, quick fixes for dark or washed-out photos |
| **Polished screenshots** | Drop shadow, border, spotlight on one area |

---

## 3. Window layout

```
┌───────────────────────────────────────────────────────────────────────────────┐
│ Menu bar: Colorbee File Edit View Image Layer Page Adjustments Effects Redact │
│           Window Help                                                         │
├───────────────────────────────────────────────────────────────────────────────┤
│ Toolbar: Clipboard │ Selection │ Tools │ Brushes │ Shapes │ Size │ Outline/Fill │
│          Color 1/2 wells │ [Layers ▣]                                          │
│ Palette: 28 swatches │ Alpha slider │ tool settings                             │
├──────────────────────────────────────────────────┬────────────────────────────┤
│                                                  │ Right sidebar (collapsible)│
│                  CANVAS                          │  • Layers                  │
│   (gray surround, 3 resize handles, rulers)      │  • History                 │
│                                                  │  • Clipboard History       │
│                                                  │  • Adjustments             │
├──────────────────────────────────────────────────┴────────────────────────────┤
│ Status: X,Y px │ Selection W×H │ Measure distance │ Canvas W×H │ Zoom ─●─ 100% │
└───────────────────────────────────────────────────────────────────────────────┘
```

---

## 4. FR-1 — Window, toolbar and canvas

### FR-1.1 Toolbar (always docked at the top)
- **Selection:** Rectangle, Ellipse, Free-Form (lasso), Magic Wand; a Transparent Selection toggle.
- **Tools:** Pencil, Brushes, Shapes, Fill Bucket, Text, Eraser, Eyedropper, Magnifier, Gradient, Measure, in one group. Stage 13 adds Retouch, Redact Brush and Step Badge.
  - **Retouch:** a gallery of retouching tools (FR-4.6).
  - **Brushes:** a gallery of 9 brush types (FR-4.2).
  - **Shapes:** a gallery of 23 shapes (FR-5.1).
- **Size:** presets of 1, 2, 3, 4 and 5px plus a custom value (1–50px for brushes). Shown only for tools that have a size; otherwise its space stays blank.
- **Outline / Fill:** style pickers (FR-5.1). Shown only for the Shapes tool; otherwise its space stays blank.
- **Layers toggle:** shows or hides the Layers panel. It shows the layer count when there's more than one layer.

### FR-1.2 Palette bar (docked under the toolbar)
- **Color wells** at the left end: Color 1 and Color 2, with a ring showing which one a swatch click will set. Double-click a well to choose its color. A small grey curved arrow beside them swaps them (X).
- 28 swatches in 2 rows of 14.
- **4 custom-color slots** (2 rows of 2) next to the swatches, for your own colors. Empty slots have a faint dashed outline:
  - A color picked in the color picker (double-click a well) or with the eyedropper's "Add to Custom Colors" goes into the next empty slot. When all are full, the oldest is replaced.
  - Left-click sets Color 1, right-click sets Color 2, exactly like the swatches. Ctrl-click → Remove clears a slot.
  - Double-click an empty slot to pick a color for it with the color picker; the color goes into that slot.
  - The custom colors are kept between launches and saved as part of a palette (FR-15.1).
- An Alpha slider (0–100%) for the active color.
- Double-clicking Color 1 or Color 2 opens the system Color Panel (Display P3, hex, sliders, screen eyedropper) for that well. (An Edit Colors… button did the same; removed 2026-10-05.)
- A palette menu: choose, save, import, export or reset palettes (FR-15.1). **Hidden for now** (Leah, 2026-10-05); it's all still there and comes back with one switch.

### FR-1.3 Right sidebar
One collapsible sidebar holds these panels. Each panel can be shown or hidden on its own, and the whole sidebar
with ⇧S, View ▸ Sidebar (⌃⌘S) or the toolbar's Sidebar button, which bring back the same panels:
- **Layers** (FR-8)
- **History** (FR-13.2)
- **Clipboard History** (FR-10.2)
- **Adjustments** (FR-8.4)
- **Info** (below)

**Info panel** (View ▸ Info, Cmd+Opt+I; Leah, 2026-10-24). Read-only facts about the document, for the page being viewed:
- **File:** name; kind (PNG image, Colorbee project and so on, or "Not saved yet"); size on disk, once saved.
- **Image:** width × height in pixels; color profile (for example Display P3); background (Solid or Transparent);
  number of layers; "Page 3 of 12" when there's more than one page; resolution, only for a page opened from a PDF.
- **Photo**, only when the image has camera details (FR-11.8): camera, lens, ISO, shutter speed, aperture, focal
  length and date taken, each shown only when known. **Location: Removed** when the original file had a GPS
  location, which Colorbee never keeps; this shows even with no other camera details.
- Nothing in it can be edited. It updates as the image changes and after each save.

### FR-1.4 Canvas
- Centered on a neutral gray surround that adapts to Light/Dark mode.
- Three resize handles: right edge, bottom edge, bottom-right corner. New area is filled with Color 2, or left transparent if the canvas has a transparent background.
- **Pan:** two-finger trackpad scroll, or hold Space and drag.
- **Zoom:** 12.5% to 3200%, centered on the pointer. Use pinch, ⌘-scroll, Cmd+= / Cmd+-, Cmd+0 for 100%, or the status-bar slider.
- **Rulers:** optional, in pixels (Cmd+R).
- **Pixel grid:** optional at 400% zoom and above (Cmd+'), drawn in a color that contrasts with the pixels underneath.

### FR-1.5 Status bar
- Pointer position as `X, Y px`, always whole pixels.
- **Color readout** (FR-9.7 item 9): the color under the pointer as shown (every visible layer, adjustments included), as a swatch, `sRGB R G B` (with its opacity when it isn't solid) and hex. To copy a hex: click the eyedropper before the readout, then click a color in the picture (Esc cancels), or press **Edit ▸ Copy Color as Hex (⌃⌘C)** while pointing at it; "Copied #…" shows for a moment. With the Eyedropper chosen it reads the Sample Size's average. Off the picture it shows a dash. Status bar only.
- Selection size as `W × H px`.
- Distance from the Measure tool (FR-7.1).
- Canvas size as `W × H px`.
- **Pixel Grid switch:** turns the grid on or off. Available at 400% zoom and above; dimmed below that.
- **Symmetry switch:** shows the current mode (Off, Vertical, Horizontal, Both). Click it to choose a mode.
- Zoom slider, plus − and + buttons around the percentage; clicking the percentage lists 25%, 50%, 75% and 100%.

---

## 5. FR-2 — Color and transparency

### FR-2.1 Two-color model
- **Color 1:** left-click drawing, shape outlines, text color.
- **Color 2:** right-click drawing, shape fills, eraser color, new area when the canvas is resized, the transparency key.
- **X** swaps Color 1 and Color 2. This matters because right-click dragging on a trackpad is awkward.
- **D** resets the colors to black and white.

### FR-2.2 Transparency
- Every pixel has full RGBA (8 bits per channel).
- Transparent areas show a light-gray and white checkerboard of 8px squares. The checkerboard stays the same size on screen at every zoom level.
- Canvas Properties (**Cmd+Opt+E**) sets the canvas size and whether the background is white or transparent.
  - **Anchor:** a 3 × 3 grid of squares chooses where the picture stays when the canvas changes size. It starts at Center each time the sheet opens. Growing adds new space (Color 2, or transparency on a transparent image) on the sides away from the anchor; shrinking cuts the edges away from the anchor. With Center and an odd difference, the extra pixel goes on the right or bottom. Every layer and the selection move with the picture, as one undo step (§23, 2026-10-28).
- Color 1 and Color 2 each have their own alpha, set with the Alpha slider.

### FR-2.3 Color accuracy
- Images keep their embedded color profile (for example, Display P3 screenshots). Colors must not shift when an image is opened, edited or exported.
- Exports embed the document's color profile.
- The eyedropper returns the exact stored pixel value.

---

## 6. FR-3 — Selection

### FR-3.1 Selection tools
- **Rectangle:** 8 handles after the selection is drawn (see "Resize by dragging", FR-3.3).
- **Ellipse**
- **Free-Form (lasso):** closes automatically when you release the mouse.
- **Magic Wand:** selects by color similarity. Has a Tolerance slider (0–100%) and a Contiguous toggle.

### FR-3.2 Combining selections
These let you build several separate regions for batch redaction (FR-9.4).

| Modifier (held when the drag starts) | Result |
|---|---|
| none | Replace the selection |
| Shift | Add to the selection |
| Option | Subtract from the selection |
| Shift+Option | Intersect with the selection |

- Holding Shift *after* the drag starts constrains the shape (square or circle).
- **Invert Selection:** Cmd+Shift+I. **Select All:** Cmd+A. **Deselect:** Cmd+D.

### FR-3.3 Moving and editing a selection
- **Move:** dragging inside a selection lifts the pixels as a *floating selection*. The hole left behind is filled with Color 2, or made transparent if the layer is transparent.
- **Duplicate-drag:** Option-drag moves a copy and leaves the original in place.
- **Smear:** Shift-drag stamps a continuous trail of copies along the path (the classic Paint trick).
- **Transparent Selection mode:** pixels that match Color 2 are treated as transparent while moving or pasting.
- **Resize by dragging:** every selection, including a pasted image, has 8 handles (4 corners, 4 sides).
  - Dragging a handle stretches the selected pixels. If they haven't been lifted yet, they're lifted into a floating selection first.
  - **Stretching is free by default. Hold Shift to keep the proportions** (Windows Paint behavior; see §23).
  - Quality doesn't degrade: until you commit, every resize is recalculated from the original pixels, so repeated resizing never blurs.
  - The status bar shows the new size and percentage live while you drag.
  - Smoothing follows the Resize/Skew setting (FR-7.2): Nearest Neighbor for sharp pixels, Smooth for photos and screenshots.
- **Nudge:** arrow keys move a floating selection by 1px, Shift+arrow by 10px.
- **Resize the selection's bounds:** Cmd+arrow grows or shrinks the marquee by 1px, Cmd+Shift+arrow by 10px. The pixels inside are not changed.
- **Commit:** clicking outside the selection, pressing Return or switching tools places the floating pixels. Clicking without dragging never moves any pixels.
- **Crop to Selection:** Cmd+Shift+X.
- **Delete:** Delete/Backspace fills the selection with Color 2, or makes it transparent.

### FR-3.4 Soft edges (stage 13)
- **Edit ▸ Feather…** softens the edge of the current selection by 1–100 px, with a live preview: a red tint over what isn't selected, fading in across the soft edge (Leah, 2026-10-10).
- Rectangle, Ellipse and Free-Form selections have a **Feather** value in the palette bar (0 px by default), applied as each one is drawn.
- **Select Subject** keeps Vision's soft edges (FR-9.5).
- Everything that uses a selection follows its soft edge: Delete, Cut, Copy, moving, Fill, Gradient, the effects and the adjustments. A pixel that's half selected is changed (or lifted) halfway.
- Combining (FR-3.2): Add keeps the stronger of the two at each pixel, Subtract takes away, Intersect keeps the weaker.
- The marching ants run where the selection is at least half on.
- **Redaction is never softened.** Batch Redact and the Redact Brush treat any partly selected pixel as fully selected, so no part of a secret is left half-visible.

---

## 7. FR-4 — Freehand tools

### FR-4.1 Pencil
- 1px hard-edged line with no anti-aliasing.
- Left-click draws with Color 1, right-click with Color 2.
- Shift constrains the line to horizontal or vertical.
- Ignores pressure.

### FR-4.2 Brushes
1. Round (anti-aliased)
2. Calligraphy 1 (`/` nib)
3. Calligraphy 2 (`\` nib)
4. Airbrush (random spray that builds up the longer you hold still)
5. Oil (textured bristles, tapered ends)
6. Crayon (waxy grain)
7. Marker (see-through, flat; overlapping parts of one stroke don't darken)
8. Natural Pencil (graphite grain)
9. Watercolor (soft see-through bleed, darker at the edges)

- Size is 1–50px. Every brush follows the Alpha slider.
- **Pressure:** on a Force Touch trackpad or a pen tablet, pressure changes brush size (and opacity where it makes sense). Other devices draw at full pressure.
- Brushes follow Symmetry (FR-7.3).
- **Shift** keeps the stroke on one horizontal or vertical line from where it started, as for the Pencil, for highlighting a line of text (Leah, 2026-10-10).

### FR-4.3 Eraser
- Square eraser. Sizes every 2px from 2 to 20px, plus 30 and 40px, or custom. **[** and **]** change the size.
- **Shift** keeps the stroke straight across or up and down, as for the Pencil and brushes (Leah, 2026-10-10).
- **Left-drag:** paints Color 2, or transparency on a transparent layer.
- **Right-drag (Color Eraser):** replaces *only* pixels that match Color 1 with Color 2. The default tolerance is 0% (exact match); a tolerance setting is available.

### FR-4.4 Fill Bucket
- Fills the connected area of similar color, with a Tolerance setting.
- Left-click fills with Color 1, right-click with Color 2.
- Never goes past the canvas edges and never wraps around.
- Stays inside the active selection if there is one.

### FR-4.5 Eyedropper
- Left-click sets Color 1, right-click sets Color 2. Alpha is included.
- Option-click samples the combined image of all visible layers instead of only the active layer.
- **Sample Size** (FR-9.7 item 9): 1 px (to start), 3 × 3 or 5 × 5, the average of the pixels around the click, colors weighted by opacity.

### FR-4.6 Retouching (stage 13)
Retouching works only from the real pixels in the image. **No AI model ships in Colorbee**, to keep it small (§23, 2026-10-10, 2026-10-19).

- The **Retouch** gallery in the toolbar (key J) holds Remove, Spot Heal, Clone Stamp, Lighten, Darken, Saturate, Desaturate, Blur, Sharpen and Smudge. J picks the one used last.
- **Size:** 1–300 px, from the Size control; [ and ] change it. A Force Touch trackpad or pen changes the size with pressure, as for the brushes, except for Remove and Spot Heal, which mark an area to fill at a steady width (Leah, 2026-10-13).
- Works on the active layer. Remove, Spot Heal and Clone Stamp have **Sample All Layers**: they read the active layer and the layers below it as shown, and write into the active layer, so you can retouch on an empty layer above the photo and keep the original untouched. Layers and adjustments above the active layer aren't read, so an adjustment above applies once (Leah, 2026-10-13).
- Retouch tools ignore Symmetry, and right-click does the same as left-click (there are no colors involved).
- Each stroke is one undo step. Refused on a locked or adjustment layer, like the brushes.

**Remove**
- Paint over the thing to remove. The painted area shows in a see-through red while you paint.
- When you release, the area is filled from its surroundings: Colorbee copies and blends patches of nearby texture (**Match Surroundings**). It's meant for simple backgrounds: sky, walls, grass, sand, water, and the flat areas of screenshots. In busy spots, where posts, leaves and edges meet, it smears; use the Clone Stamp there (Leah, 2026-10-10, after the trial).
- A large area can take a moment. A progress ring shows on the canvas, panning and zooming still work, and Esc cancels the fill.
- The result is repeatable: the same stroke on the same image always gives the same fill.

**Spot Heal**
- Click a small spot (dust, a blemish, a stray pixel) or brush over a thin scratch. It's filled from the area just around it and blended so the tone matches.
- Meant for small things. For anything much bigger than the brush, use Remove.

**Clone Stamp** (key S)
- Option-click to set the source. Then paint: pixels are copied from the source, keeping the same offset as you move (**Aligned**, on by default). With Aligned off, every stroke starts again from the source.
- A crosshair shows where the source is while you paint.
- **Match Tone** (off by default) blends the copied pixels into the colors around them, like a healing brush.
- **Hardness** 0–100% (50% by default) sets how soft the brush edge is.

**Local brushes:** Lighten, Darken, Saturate, Desaturate, Blur, Sharpen, Smudge
- Paint to change only what's under the brush. **Strength** 1–100% (50% by default) and **Hardness** are in the palette bar.
- Lighten and Darken have a **Range**: Shadows, Midtones (default) or Highlights.
- Within one stroke, going over the same place doesn't add up (as with the brushes, FR-4.2); a new stroke adds more.
- Smudge drags the colors along the stroke, like a finger through wet paint; Strength sets how far they travel.

---

## 8. FR-5 — Shapes and gradients

### FR-5.1 Shapes (23)
Line, Curve (3-point), Rectangle, Rounded Rectangle, Ellipse, Triangle, Right Triangle, Diamond, Pentagon, Hexagon, Right Arrow, Left Arrow, Up Arrow, Down Arrow, 4-Point Star, 5-Point Star, 6-Point Star, Rounded Rectangle Callout, Oval Callout, Cloud Callout, Heart, Lightning, Polygon.

- **Drawing:** drag to set the bounding box. Shift keeps proportions (squares and circles, lines at 45° steps).
- **Outline:** None, Solid, Crayon, Marker, Oil, Watercolor, Natural Pencil.
- **Fill:** None, Solid, Crayon, Marker, Oil, Watercolor, Natural Pencil.
- Left-click: Color 1 for the outline, Color 2 for the fill. Right-click swaps them.
- **Stays editable** after you draw it: move, resize, rotate, change style or colors. The shape is placed into the layer when you click outside it, press Return or switch tools. Esc cancels it.

### FR-5.2 Gradient
- Drag to draw a gradient from Color 1 to Color 2. Right-drag reverses it.
- Modes: Linear, Radial, Reflected, Diamond, Conical.
- Uses each color's alpha, so a gradient can fade to fully transparent.
- Stays inside the selection if there is one.

### FR-5.3 Step badges (stage 13)
- The **Step Badge** tool (key N): click to place a numbered circle. Each click places the next number: 1, 2, 3…
- The circle is filled with Color 1, with a thin outline and a bold number in Color 2 (Leah, 2026-10-10). Right-click swaps them, as for shapes.
- **Size** sets the circle's diameter (16–128 px, 32 by default).
- **Numbers or letters** (1, 2, 3 or A, B, C) in the palette bar, with a **Next** field for what the next badge shows. Numbers and letters count separately: placing a letter badge doesn't move the numbers on, and switching shows that style's own Next (Leah, 2026-10-10). Each starts at 1 (or A) in each document and steps back when one of its badges is undone.
- **Drag** from where you press to draw the badge with an arrow pointing to where you release, in the badge's color.
- Like a shape, a badge stays editable until it's placed: drag to move it, Delete removes it. Placed badges are pixels.

---

## 9. FR-6 — Text

### FR-6.1 Editing text in place
- Click the canvas to start a text box, or drag to set its width.
- Controls: font, size (6–72pt or a custom value), Bold, Italic, Underline, Strikethrough, alignment.
- **Background:** Opaque (a Color 2 rectangle behind the text) or Transparent.
- The text box stays editable, and you can move and resize it, while it's active.

### FR-6.2 Text styles
- Save the current font, size, color, formatting and background as a named style.
- Apply a style from the text toolbar. Styles are kept between launches.

### FR-6.3 Placing the text
- Clicking outside, pressing Esc or switching tools turns the text into pixels on the active layer. After that the text can't be edited again (true to classic Paint).

---

## 10. FR-7 — Measure, zoom, geometry and symmetry

### FR-7.1 Measure and Magnifier
- **Measure:** drag from point A to point B. The status bar shows the distance in pixels, plus ΔX, ΔY and the angle. The line stays on screen until you measure again or switch tools. It is never drawn into the image.
- **Magnifier:** left-click zooms in one step toward the pointer, right-click zooms out.

### FR-7.2 Resize and Skew (Cmd+E)
- Resize by percentage (1–500%) or by exact pixel size, with an aspect-ratio lock.
- Resampling: Nearest Neighbor (sharp, for pixel art) or Smooth (for photos).
- Skew horizontally and vertically, from −89° to +89°.
- Applies to the selection if there is one, otherwise to the whole image.

### FR-7.3 Symmetry
- Modes: Off, Vertical (mirrored across the vertical centerline), Horizontal, Both (4-way).
- Works with Pencil, Brushes and Eraser.
- A faint guide line shows the axis. Toggle it from the Image menu.

### FR-7.4 Rotate and flip
- Rotate 90° clockwise, 90° counter-clockwise or 180°. Flip horizontally or vertically.
- Applies to the selection if there is one, otherwise to the whole image.

---

## 11. FR-8 — Layers

### FR-8.1 Behavior
- A new document has one layer and the Layers panel is hidden.
- Open it with the toolbar Layers toggle, View → Layers (Cmd+L), or Layer → New Layer.

### FR-8.2 What layers can do
- As many layers as memory allows.
- Add, Duplicate, Delete, Merge Down, **Merge Visible** (combines all visible layers into one), Flatten.
- Drag to reorder. Double-click to rename.
- Eye icon to show or hide each layer. **Hide/Show Layer** is also a menu command for the active layer.
- **Lock:** a padlock on each layer. A locked layer can't be painted, erased, filled, moved, filtered, merged into or deleted. It can still be hidden, shown or reordered. Tools show a "not allowed" pointer over a locked layer.
- Opacity slider from 0 to 100%.
- **Blend modes (17),** grouped in the menu like this:
  - Normal
  - Darken, Multiply, Color Burn
  - Lighten, Screen, Color Dodge, Additive
  - Overlay, Soft Light, Hard Light
  - Difference, Exclusion
  - Hue, Saturation, Color, Luminosity
- Every tool, effect and adjustment works on the **active layer** only.

### FR-8.3 Per-layer undo
- **Cmd+Z / Cmd+Shift+Z** undo and redo across the whole document, in order.
- **Undo on Active Layer (Cmd+Opt+Z)** reverts the most recent change *on the active layer* and leaves later changes on other layers in place. It isn't available when the most recent change on that layer also affected other layers (for example a canvas resize or flatten).
- **Revert Layer** returns the active layer to how it was at the last save.

### FR-8.4 Adjustment layers (non-destructive)
- Types: Hue/Saturation/Lightness, Desaturate, Invert, Gaussian Blur, Sharpen. (Brightness/Contrast was replaced by Adjust Photo, FR-9.5.)
- Stage 9 adds Levels, Curves, Sepia and Posterize, plus Adjust Photo (all its sliders in one layer) and any photo filter (FR-9.5). Auto Contrast as an adjustment layer is a Levels layer with its points set automatically.
- An adjustment layer changes how the layers below it look, without changing their pixels.
- Its settings stay editable in the Adjustments panel. It can be hidden, reordered, deleted, or have its opacity changed like any layer.
- **Only the layer below** (a switch in the Layers panel; Leah, 2026-10-10): the adjustment changes just the pixel layer under it, not everything below, like a clipping mask. Several such adjustments can sit on one layer, in order. The layer list shows them with an arrow and "Layer below only". If the layer under it is an adjustment that changes everything below (or there's none), it changes nothing, and says "Layer below only: none". Merge Adjustment on one goes into that layer only. Such adjustments stay with their layer (Leah, 2026-10-13): a new layer added with it selected goes above them, Merge Down bakes them in, and Delete Layer deletes them with it.
- **Merge Adjustment** (the Merge button in the Adjustments panel) merges it and every visible layer below it into one pixel layer, so the picture looks the same. Layers above stay as they are; hidden layers below are kept. ⌘C on an adjustment layer copies what you see (like Copy Merged).

### FR-8.6 Choosing several layers (Leah, 2026-10-27)
- **Choosing:** Shift-click chooses every layer between the active one and the one clicked; ⌘-click adds or
  removes one layer; a plain click chooses just that layer. Drawing, effects and adjustments still go to the layer
  clicked last (the active layer). Choosing layers isn't an undo step and isn't saved in the project.
- **Merge Layers:** with several layers chosen, Layer ▸ Merge Down becomes **Merge Layers**, on the same key
  (⇧⌘E). The merged layer sits where the topmost chosen layer was and keeps its name; unchosen layers in between
  stay where they are. Hidden chosen layers are left as they are. If any chosen layer is locked, Merge Layers is
  greyed out. A chosen adjustment layer is baked into the chosen layers below it, and goes away. The merged layer is
  Normal at 100%: the picture keeps its look for Normal layers at any opacity, but a layer with another blend mode
  (Multiply, Screen…) is baked in, as in Photoshop, and can look different where nothing chosen is under it.
- **On every chosen layer:** Delete, Duplicate (each copy just above its layer), Hide/Show and Lock/Unlock (Layer
  menu and right-click menu), opacity and blend mode in the Layers panel, and dragging to reorder (they move
  together, keeping their order). Each is one undo step.
- **Right-click menu on a layer:** New Layer and New Adjustment Layer ▸ (every kind, as in the Layer menu), each
  added just above that layer; then Merge Down (or Merge Layers), Duplicate, Delete, Hide/Show, Lock/Unlock,
  Rename and Layer Properties. Rename is greyed out while several layers are chosen. Right-clicking (or Control-clicking) a layer that isn't chosen chooses it alone, and
  it turns blue before the menu opens, so it's clear which layer the menu is for. Right-clicking one of several
  chosen layers keeps them all chosen.

### FR-8.5 Saving with layers
- **.colorproj** keeps everything: layers, names, opacity, blend modes, visibility and adjustment layers.
- Exporting to a flat format (PNG, JPEG and so on) combines all visible layers and applies the adjustments. The document itself is not changed.

---

## 12. FR-9 — Adjustments, effects and redaction

### FR-9.1 Adjustments (Adjustments menu; they change the pixels)
- **Invert Colors** (Cmd+I)
- ~~Brightness/Contrast~~: removed 2026-10-03; Adjust Photo's Brightness and Contrast replace it (FR-9.5).
- **Hue/Saturation/Lightness** (live preview)
- **Desaturate** (Cmd+Shift+U)
- Each has an "as Adjustment Layer" version (FR-8.4).

### FR-9.2 Effects (Effects menu)
- **Gaussian Blur:** radius 1–100px, live preview.
- **Pixelate:** block size 2–100px, live preview.
- **Sharpen:** amount slider.
- Effects apply to the selection if there is one, otherwise to the active layer.

### FR-9.3 Auto-Redact
- **Effects → Auto-Redact…** reads the text in the image **entirely on this Mac**. Nothing leaves the machine.
- Built-in types to find: email addresses, phone numbers, credit card numbers, API keys and tokens, IP addresses, URLs.
- **Faces** (FR-9.7 item 10): a built-in row, on to start, found by Apple Vision on this Mac on every page. Each face is listed ("Face 1" and on, through the document) and boxed, 30% bigger than Vision's box to cover hair and chin; even tiny ones are listed, to untick. They take the same treatment as the text, in the same undo step. The sheet says that faces turned away, half hidden, very small or drawn can be missed.
- Custom patterns can be added, named, saved and turned on or off.
- Matches are shown as boxes you can review. Tick or untick each one, choose the treatment (Blur, Pixelate or Solid Fill with Color 1) and apply.
- Always reads the whole image, every page, even when something is selected; Batch Redact is for chosen areas (§23, 2026-10-04).
- The whole redaction is one undo step.

### FR-9.4 Batch redaction
- Build a selection from several separate regions (FR-3.2), then apply Blur, Pixelate or Solid Fill to all of them in one go.
- Each region is redacted on its own. Blur doesn't bleed between regions.
- One undo step.

### FR-9.5 Photo editing and presentation (stage 9)
Minor photo editing: quick fixes, not a replacement for a full photo editor. Like the rest of FR-9, each one applies to the selection if there is one, otherwise to the active layer, shows a live preview in the docked settings bar, and is one undo step.

**Adjustments menu**
- **Levels:** black point, white point and midtones (gamma), with a histogram. An **Auto** button sets the black and white points from the image.
- **Auto Contrast:** one step, no settings. Stretches the darkest and lightest pixels to full black and white.
- **Curves:** a tone curve with draggable points, for the combined RGB and for each channel.
- **Sepia:** a warm brown-tone version of the image, with an amount slider.
- **Posterize:** reduces each channel to 2–32 levels.
- **Remove Red-Eye** (stage 13): finds eyes with Apple Vision, on this Mac, and turns red pupils dark while keeping their highlight. With a selection, it fixes red pixels inside the selection instead, for eyes Vision misses (pets, faces turned away). One undo step. Says "No red-eye found" when nothing changes.
- Each of these also comes as an adjustment layer (FR-8.4), from "as Adjustment Layer" versions of the menu items.
- White Balance and Vibrance are sliders in the Adjust Photo panel, not separate menu items.

**Adjust Photo panel** (Adjustments ▸ Adjust Photo…)
- One docked panel with all the photo sliders, like the iPhone Photos editor: Exposure, Brilliance, Highlights, Shadows, Contrast, Brightness, Black Point, Saturation, Vibrance, Warmth, Tint, Sharpness, Definition, Noise Reduction, Vignette.
  - **Vibrance** boosts muted colors more than already-vivid ones, so skin tones don't go orange.
  - **Warmth** and **Tint** are the white balance: cooler to warmer, and green to magenta.
- **Sharpness** and **Noise Reduction** each have finer settings under a disclosure arrow beside the name (FR-9.7 item 5): Sharpness's Radius (0.5–3 px, 1.2 to start), Detail (0–100, 50 to start: lower holds back halos, higher brings out the finest detail) and Masking (0–100, 0 to start: sharpen only edges; Option-drag shows the edge mask, white where it sharpens, on the picture only). The Noise Reduction slider is luminance noise reduction, with its Detail (50 to start); Color (0–100) smooths colored speckles keeping the brightness, with Color Detail (50 to start). Each starts at the look Colorbee always had, so older photos and projects look the same. Filters leave them out.
- **Histogram** at the top of the panel (FR-9.7 item 6): the picture as it now looks, updated as the sliders move. Its two corner buttons, off to start and with no key, turn on clipping warnings: blown highlights (any channel at white) show red and crushed shadows (every channel at black) blue, on screen only, never in an export or copy. They show while Adjust Photo's controls are showing, in its panel or for an Adjust Photo layer.
- **Tone Curve** section, after Light (FR-9.7 item 6): a parametric curve with Highlights, Lights, Darks and Shadows (each −100 to 100) and three split points (25, 50 and 75 to start) dragged on a line under its graph. It applies after the Light and Color sliders, and keeps rising however it's set. Filters keep it; a filter's Intensity scales only the four amounts.
- **The hand** (FR-9.7 item 6): a hand button on the Tone Curve's graph and beside the Color Mixer's tabs. While it's on, dragging up on the picture raises (and down lowers) the Tone Curve region, or the Color Mixer tab's setting for the color, under the pointer, read from the picture as it was before Adjust Photo so the target doesn't move. Space-drag pans; Esc or the button turns it off. In the panel, Apply is the step; on an Adjust Photo layer, each drag is one step.
- **Effects** section (FR-9.7 item 5): **Vignette** (moved here from Detail) and **Grain** (0–100). Arrows beside them hold the vignette's Midpoint (0–100, 50), Roundness (−100 to 100, 0: the picture's shape) and Feather (0–100, 50), which start at the vignette Colorbee always had, and the grain's Size (0–100, 25) and Roughness (0–100, 50). Grain is fixed to the image's pixels, so the preview matches the export. Filters keep both; a filter's Intensity scales only the vignette's and grain's amounts. Effects ▸ Vignette… stays as it is.
- Applies to the selection if there is one, otherwise the active layer. Live preview. One undo step.
- Also available as an adjustment layer, with every slider still editable.
- **Auto:** analyzes the photo and sets Exposure, Brilliance, Highlights, Shadows, Contrast, White Balance (Warmth and Tint) and Vibrance, and Whites (FR-9.7). The panel marks the sliders Auto moved, and any of them can be adjusted afterwards. One undo step together with the rest of the panel.

**Filters** (in the Adjust Photo panel)
- Built in: Vivid, Vivid Warm, Vivid Cool, Dramatic, Dramatic Warm, Dramatic Cool, Mono, Silvertone, Noir. Each has an intensity slider.
- A filter is a named recipe of the panel's color and tone slider values only. Filters never crop or straighten. FR-9.7 adds Dehaze, Vignette and Grain to what a filter holds; Texture, sharpening and noise reduction stay out (§23, 2026-10-27).
- Intensity scales every value (50% is half of each). For FR-9.7's shape settings (Grain size and roughness, Vignette midpoint, roundness and feather, tone curve split points) it scales only the amounts (§23, 2026-10-27).
- **Save as Filter…** saves the current slider settings under a name.
- **Save Filter from Layers** turns a stack of adjustment layers into one filter.
- Rename, Delete, Import and Export work like palettes. Filters are stored in Application Support; a `.colorbeefilter` file is for sharing.
- Any filter can be applied as an adjustment layer.
- **Looks:** Import Filter… also takes a `.cube` color look (a 3D table, up to 129 points a side), which becomes a filter of its own, named from the file's TITLE line or else the file's name, and is chosen straight away. It applies to the document's own color values, as Photoshop's Color Lookup does. Its Intensity mixes the look with the original. An exported look filter carries its table. One-dimensional `.cube` files and damaged files give a plain message, and nothing is added (FR-9.7 item 4; §23, 2026-10-28).

**Subject (Apple Vision, on this Mac; nothing leaves it)**
- **Remove Background:** writes Vision's soft edges directly into transparency. Option: put the subject on a new layer instead of erasing in place.
- **Select Subject:** makes a selection from the subject. Its edges are hard until soft selections arrive in stage 13 (FR-3.4); then it keeps Vision's soft edges.
- After the first look, Colorbee always waits for a click, even with one subject found: clicking a subject picks
  just that one, and Return takes every subject found. (Vision's first look can miss what's wanted or merge it with
  its neighbors, so taking a lone subject at once could leave the wanted one out of reach.)
- A click where no subject was found looks again, closer: Vision shrinks the whole image to about 512 px, so a
  small subject (a character in a game screenshot) can be missed. Colorbee tries ever smaller squares around the
  click and takes the subject under it, or beeps if there's none.
- When Vision finds nothing at all, the bar asks for a click on the subject instead, looked for the same way;
  Return does nothing and Cancel leaves the image as it was.
- **Lift Subject to New Layer** puts the new Subject layer just above the picture's layer, which stays active, so
  several subjects can be lifted one after another. The Layers panel opens to show the new layer, as after New Layer.
- **Clean Up** with an AI model isn't planned: no AI models ship in Colorbee, to keep it small (§23, 2026-10-10, 2026-10-19). Objects are removed with the Remove tool (FR-4.6), which fills from the image's own pixels.

**Effects menu**
- **Add Noise:** amount, and monochrome or color noise.
- **Motion Blur:** angle and distance.
- **Emboss:** angle and depth; the image becomes a gray relief.
- **Vignette:** darkens (or lightens) toward the edges, with amount and size.
- **Drop Shadow:** a soft shadow behind the image or the selected object, with offset, blur, color and opacity. The canvas grows to fit it.
- **Border:** a solid outline around the image or the selected object, with width and color (Color 1 by default). The canvas grows to fit it.
- Drop Shadow and Border **follow the object's shape**: the outline of its opaque pixels (partly transparent edges cast a lighter shadow), or the selection's outline when there is one. An ordinary opaque screenshot is a rectangle, so it gets a rectangular shadow and border.
- **Spotlight:** keeps the selection as it is and dims, blurs or desaturates everything else. Needs a selection.

**Image menu**
- **Straighten…** (Image menu, next to Rotate): rotates the image by any angle to level a tilted horizon or a crooked scan.
  - An angle slider from −45° to +45° in 0.1° steps, with a live preview and a grid laid over the canvas to line things up against.
  - Or draw a line along something that should be level (or upright), and Colorbee works out the angle.
  - **Crop to fit** (on by default) trims the corners that rotating leaves empty. With it off, the canvas grows and the corners are filled with Color 2, or left transparent on a transparent image.
  - Smooth resampling. Applies to the whole image (every layer) as one undo step.
- **Perspective Correction…** (next to Straighten): squares up a photo of a whiteboard, a document or a building. Drag four corners onto the shape that should be a rectangle; the image is warped so it becomes one.
  - Each time it opens, Apple Vision looks for the rectangle on this Mac ("Finding corners…") and the corners start on it; with none found they start inset from the edges, as before. **Reset** puts them back where they started (FR-9.7 item 7).
- **Crop…** (next to Crop to Selection): a crop box with handles over the image.
  - Aspect presets: Free, Original, Square, 4:3, 3:2, 16:9, 9:16, and a custom W:H, with a button that swaps portrait and landscape.
  - Pixel-size presets, such as 1200 × 630 for link previews: the box keeps that shape, and the result is resized to exactly that size.
  - Guides show while dragging: Thirds, Grid, Diagonal, Triangle, Golden Ratio or Golden Spiral; **O** switches between them, and the chosen one is remembered while Colorbee is open (FR-9.7 item 7). The area cut away stays shaded, as before (Q17.3).
  - Return applies, Esc cancels. Applies to every layer as one undo step.
- **Trim** (Image menu, next to Crop…): one click crops away the picture's border: transparent pixels if the border is transparent, otherwise pixels matching the top-left pixel's color within about 2%, so JPEG edges still trim. It looks at everything shown and crops every layer together, as one undo step; on a page document, it trims the page shown. With nothing to trim, it beeps (§23, 2026-10-28).

### FR-9.6 Redact Brush (stage 13)
**Redact Brush** (key K)
- Paint over anything to hide it. The treatment is chosen in the palette bar: Blur, Pixelate or Solid Fill (Color 1). **Solid Fill** is the default, as in Auto-Redact.
- The painted area shows as a see-through overlay while you paint. The treatment is applied when you release, as one undo step.
- Size 1–300 px. Shift locks the stroke to horizontal or vertical, for a line of text.
- Changes layers like Batch Redact (§23, 2026-10-04): every layer with pixels under the stroke. A locked layer with pixels there blocks it, and a message names the layer.
- Blur and Pixelate strength follows the brush size, as Auto-Redact's follows the text height.
- It's a redaction, so the after-redaction offers apply (earlier Versions, Clipboard History; §23, 2026-10-04).

### FR-9.7 Lightroom-style photo editing (Leah, 2026-10-27; planned, not built yet)
Colorbee's next aim is editing one picture at a time the way Lightroom does, with saved settings to re-apply the same look. There is no library or catalog. Background: `Docs/Feature-Gap-Analysis.md`.

**Rule:** the new controls live inside Adjust Photo (FR-9.5), so adjustment layers include all of them. Saved filters and Save Filter from Layers include the color and tone ones, plus Dehaze, Vignette and Grain; never Texture, sharpening or noise reduction, which depend on each photo's own detail. Filters and projects saved before open unchanged, with the new controls at neutral. Ranges, defaults and keys for each item are settled with Leah when its part starts.

1. **Basic and Color:** a white-balance eyedropper (click something that should be gray; it sets Warmth and Tint), Texture, Dehaze, Whites, and a Color Mixer (hue, saturation and luminance for each of eight color ranges).
   - **Whites** runs from −100 to 100, in Light just above Black Point, and changes only the brightest parts. Auto (FR-9.5) sets it too. There's no separate Blacks slider: Black Point does that job.
   - **The eyedropper** averages a 5 × 5 area, turns off after one click, and Esc cancels it. When the cast is stronger than Warmth and Tint can fix, or the click isn't on anything gray, it goes as far as it can, with no message.
   - Adjust Photo's sections fold, and Colorbee remembers which are folded, for the whole app.
2. **Color Grading:** color wheels for shadows, midtones and highlights (hue, saturation, luminance), with Blending and Balance; and Point Color (choose a color in the picture and shift just that color).
3. **Local edits:** Color Range (select by the colors you click, with a fuzziness setting) and Luminance Range (select shadows, midtones or highlights); a graduated selection (drag a line, soft falloff on one side); and Select ▸ Expand, Contract and Smooth, in pixels. All of them follow the soft-selection rules (FR-3.4).
4. **Saved settings:** re-apply the last Adjust Photo settings; copy the settings and paste them onto another picture; History Snapshots (named save points in the History panel); and importing `.cube` LUT looks as filters, with an intensity slider.
5. **Detail controls:** Sharpening radius, detail and masking; Noise Reduction for luminance and color separately; Vignette midpoint, roundness and feather; Grain size and roughness.
6. **Tone extras:** a parametric tone curve, a Black and White mix, dragging on the picture to adjust the tone or color under the pointer, and clipping warnings on the histogram.
7. **Photo geometry:** Perspective Correction finds the corners itself (on this Mac, with Apple Vision) for you to nudge before applying; more crop overlays (golden ratio and others); and the area a crop cuts out shown dimmed.
8. **Export:** a color-space choice (sRGB, Display P3, or keep the document's, which stays the default) and Limit file size (JPEG and HEIC pick the quality to fit; PNG can't).
9. **Color readout and sampling:** the color under the pointer (RGB and hex) in the status bar, and an Eyedropper sample size that averages a small area.
10. **Auto-redact faces:** found on this Mac with Apple Vision and listed in Auto-Redact's review sheet (FR-9.3), on every page, with the same Blur, Pixelate and Solid Fill choice and one undo step.

---

## 13. FR-10 — Clipboard

### FR-10.1 Paste
- **Cmd+V** pastes the image as a floating selection at full resolution with its alpha. It's placed at the top-left of the visible area.
- If the pasted image is bigger than the canvas, Colorbee offers to enlarge the canvas (like Paint).
- **Paste into New Image:** Cmd+Shift+V.
- **Paste in Place (Cmd+Opt+Shift+V)** pastes copied pixels exactly where they were copied from, as a floating selection. In a different document it lands at the same place if any of it falls on the canvas, otherwise where Cmd+V puts it. A picture copied in another app, or chosen from Clipboard History, pastes as Cmd+V does (Leah, 2026-10-28).

### FR-10.2 Clipboard History
- A sidebar panel with thumbnails of the last 10 images that were copied or pasted.
- Clicking a thumbnail pastes it as a floating selection. The system clipboard is not changed.
- Hovering shows when it was captured and its size.
- A **Clear** button. The history is kept between launches.

### FR-10.3 Copy
- **Cmd+C** copies the selection, or the whole combined image if nothing is selected, as a PNG with transparency.
- **Cmd+X** cuts.
- **Copy Merged (Cmd+Shift+C)** copies the combined image of all visible layers inside the selection.

### FR-10.4 Copy Text (stage 13)
- **Edit ▸ Copy Text (Cmd+Opt+C)** reads the text in the selection, or in the whole image if nothing is selected, and puts it on the clipboard as plain text.
- Reads on this Mac with Apple Vision, like Auto-Redact. Nothing leaves the Mac. Languages are detected automatically.
- Reads what you see (all visible layers). In a document with pages, it reads the page being viewed.
- Text comes out in reading order, one paragraph per line (a paragraph's wrapped lines are joined); columns of running text are read left column first, and short side-by-side items, like a form's labels and values, row by row. Apple's document reader decides the layout.
- A short message at the bottom of the canvas confirms it and fades by itself: "Copied 42 words", or "No text found" (the clipboard is then left as it was). "Reading text…" shows at the top meanwhile.
- It never changes the image and isn't an undo step. Text isn't added to Clipboard History, which holds images.

---

## 14. FR-11 — Files and export

### FR-11.1 Formats

| Format | Open | Save/Export | Notes |
|---|:-:|:-:|---|
| PNG | ✓ | ✓ | Default. Full alpha. |
| JPEG | ✓ | ✓ | Quality 1–100. Transparent areas are placed over Color 2. |
| BMP | ✓ | ✓ | 24-bit and 32-bit. |
| GIF | ✓ | ✓ | 256 colors, 1-bit transparency. Opens the first frame. |
| TIFF | ✓ | ✓ | No compression or LZW (chosen in Export…; LZW by default). |
| WebP | ✓ | — | Opens only: macOS can't write WebP, and no third-party encoder is used. |
| HEIC | ✓ | ✓ | |
| .colorproj | ✓ | ✓ | Native format with layers (FR-8.5). |

### FR-11.2 Export presets
- **File → Export As ▸** a preset exports a PNG scaled to a set width (or to fit a square). The aspect ratio is kept, and the image is never made larger than its original size (Leah, 2026-10-03).
- Presets: Slack (760px), 1280px, 1920px, Mobile (750px), Square 1024.
- Resampling is chosen automatically: Nearest Neighbor for pixel-art-sized images, Smooth otherwise. Settings → Export Presets → Scaling overrides it (Sharp pixels or Smooth).
- Presets can be edited in Settings. Each has a **Color**: keep the document's (to start), sRGB or Display P3 (FR-9.7 item 8).
- **File ▸ Export…** also has **Color** (keep the document's, the default, sRGB or Display P3; the file carries that profile) and, for JPEG and HEIC, **Limit file size to [ ] KB/MB**: the best quality that fits, with camera details counted; a KB is 1,000 bytes. If even the lowest quality is too big, a message gives the smallest size possible and nothing is written. Both are remembered. Copy, Share and Export as PDF keep the document's profile (FR-9.7 item 8).

### FR-11.3 Before/After
- **View → Before/After** (Cmd+Opt+B) shows a "before" image next to the current version.
- **Compare against** (a switch in the Before/After bar):
  - **As Opened** (default): the image when it was opened, or when a new document was created from a paste.
  - **Last Saved:** the image at the most recent save. Not available until the document has been saved.
- Two views: side by side, or a draggable split.
- For viewing only. It never changes the image.

### FR-11.4 Drag and drop
- Drop an image onto the canvas: it becomes a floating selection.
- Drop onto the Dock icon, or onto an empty area of the window outside the canvas: it opens as a new document or tab.

### FR-11.5 Share
- **File → Share** opens the system share sheet (AirDrop, Messages, Mail, Notes and so on) with the combined PNG.

---

### FR-11.6 Pages and PDF documents (stage 10)
Bee edits typical documents (letter or A4, 10–50 pages) and needs to annotate or redact most pages in one session.
Any Colorbee document can have pages, so Colorbee can also make its own PDFs from images.

- **Pages:** a document is a list of pages. Each page is like an image of its own: its own size, layers,
  selection and undo history. A new document has one page.
- **Page sidebar:** on the left, like Preview's: a thumbnail per page, in order. Clicking a page edits it in
  the canvas; the right sidebar (Layers and the rest) shows that page's layers. The sidebar appears once a
  document has more than one page, and View ▸ Page Sidebar shows or hides it.
- **Page commands:** New Page (blank, the size of the current page, filled with Color 2), Duplicate Page,
  Delete Page, and moving pages by dragging thumbnails (or Move Page Up and Down, for VoiceOver).
- **Undo:** ⌘Z undoes the last change on the page being viewed; each page remembers its own edits. Adding,
  duplicating, deleting and moving pages can be undone too: ⌘Z undoes such a change when it's the newest thing
  done in the document.
- **Opening a PDF:** File ▸ Open or drag-and-drop. Every page opens at once, rasterized at the resolution set in
  Settings (200 DPI by default; 150 and 300 offered). Fonts, vectors and form fields aren't kept. A PDF can't be
  saved back without that loss, so it opens as an untitled copy.
- **Multi-page TIFFs and animated GIFs** open the same way, every frame as a page; this replaces the frame bar
  and Choose Frame… (§23, 2026-10-04). They open as untitled copies; saving back as an animated GIF is out of
  scope.
- **Export as PDF…** (File menu): a new PDF with one page per page, in order. Each page is its layers flattened
  (visible layers, as shown), at its resolution: a PDF's pages keep the resolution they were opened at; other
  pages count as 144 DPI (Retina screenshots), so a 1440-pixel-wide screenshot makes a 10-inch-wide page.
  Pixels only, so no hidden text survives under a redaction; the text isn't selectable or searchable.
  Pages are compressed losslessly, and the file holds no metadata: no title, author, app name or dates.
- **Image export** (Export, export presets, Copy, Share, Print) works on the page being viewed.
- **Saving:** `.colorproj` holds every page; projects saved before pages open as one page.
- **Auto-Redact** scans every page, whole, with one review list grouped by page ("Page 3 · 2 items"); clicking
  an item shows its page with the item in view. Apply redacts every checked item on every page. ⌘Z undoes it on
  every page at once, from any page, while it's the newest change on each of them; if a page has changed since,
  ⌘Z on another page undoes just that page's part.
  Batch Redact works on the page being viewed.
- **Memory:** a letter page at 300 DPI is about 34 MB, so pages not on screen are kept compressed, as history
  does with layers it holds.
- **Built in two parts:** 10a pages (the document of pages, the page sidebar, page commands and undo, opening
  PDFs, TIFFs and GIFs, saving projects, memory); 10b output (Export as PDF, Auto-Redact on every page, the
  resolution setting).

### FR-11.7 Import from iPhone or iPad: removed
**Removed (Leah, 2026-10-19).** It worked only with no document open, and adding to an open document never worked
(SwiftUI's views don't pass macOS's Continuity Camera request on). The app code is gone; the core's
`PDFPages.scannedPage` and `PageStack.insert(_:at:named:)` stay, tested, should it come back.

### FR-11.8 RAW photos (stage 12)
Open camera RAW files, develop them, then edit and export like any image.

- **Formats:** whatever macOS's own RAW engine reads (the one Photos and Preview use), which covers Canon CR3,
  Sony ARW, Nikon NEF, Fujifilm RAF and DNG. A camera newer than macOS knows gets a plain message.
- **Opening:** File ▸ Open, drag and drop, Open Recent and Finder, like any image. Every RAW open shows a
  **Develop** window first: a live preview and Exposure, Temperature, Tint, Highlights, Shadows, Contrast, Noise
  Reduction, Sharpness and a Lens Correction switch (when macOS has the lens's profile), each starting at the
  camera's own setting, with **Reset to Camera**. Return opens with what's shown; Cancel opens nothing.
- Developing happens at RAW precision, before the image becomes Colorbee's 8-bit pixels, in **Display P3**. To
  develop differently later, open the RAW file again.
- The result opens as an **untitled copy** (a RAW file is never written to), so ⌘S asks where to save.
- **Camera details:** photos with them (RAW, and JPEG or HEIC from a camera or phone) keep the camera, lens, ISO,
  shutter speed, aperture, focal length and date taken, also in .colorproj files. **File ▸ Export…** has
  **Include camera details**, off at first, for formats that can hold them. Location, serial numbers and the
  owner's name are never kept or written.
- Too large for memory: a plain message, and nothing opens.

## 15. FR-12 — Saving and restoring (standard Mac behavior)

- Documents save themselves automatically, the standard macOS way. Untitled documents are kept safe too.
- When you quit and reopen Colorbee, open windows come back exactly as they were, including untitled ones. There is **no** restore prompt.
- File → Revert To → Browse All Versions works.
- **Undo history survives saves.** Saving never clears the undo stack.
- **Where Save and Export start:** in the folder of the file being worked on. A picture that has to become a new
  file (it gained layers, or opened as a copy such as a PDF or RAW photo) starts in the original picture's folder,
  so `Pictures/photo.jpg` offers `Pictures/photo.colorproj`. Images that never came from a file start in the last
  folder used, as usual on a Mac.
- If nothing needs restoring, launch opens a blank white 1920×1080 canvas.

---

## 16. FR-13 — History

### FR-13.1 Undo and redo
- Cmd+Z undoes, Cmd+Shift+Z redoes.
- There is no fixed step limit. Old steps are kept compactly so memory stays in check.
- Every change to the image or layers is undoable, including shape and text commits, the selection-plus-move steps, layer operations, resizes and effects.

### FR-13.2 History panel (Cmd+Y)
- Lists past actions in order, each with a name and a small thumbnail (for example "Pencil", "Fill", "Gaussian Blur", "Move Selection", "Resize Canvas").
- Clicking a row jumps to that point. Steps after it are dimmed and can be redone until you make a new change.
- **Snapshots** (FR-9.7 item 4) are listed above the steps: Edit ▸ New Snapshot… or the panel's camera button names the image as it is now. A snapshot keeps its own copy of every layer (compressed to disk), so it survives any later edit, crop or undo. Clicking it is a step of its own, "Go to Snapshot", that ⌘Z takes back. Control-click to rename or delete. Each page keeps up to 10; at the cap a message says to delete one first. Snapshots aren't saved in the project, and Remove Earlier Versions and Undo History removes them (§23, 2026-10-28).

---

## 17. FR-14 — macOS integration

### FR-14.1 Input
- **Right-click and two-finger click** are Color 2 / secondary tool actions. They never open a context menu on the canvas.
- **Ctrl-click** opens the canvas context menu: Cut, Copy, Copy Merged, Paste, Delete, Select All, Deselect, Invert Selection, Select Subject, Crop to Selection.
- Trackpad: two-finger pan, pinch to zoom (sharp nearest-neighbor during the gesture).
- **Pressure** from a Force Touch trackpad or a pen tablet (FR-4.2).

### FR-14.2 Display
- At 100%, one image pixel equals one screen point. Above 100%, pixels are drawn as sharp squares with no smoothing.
- Full Light and Dark mode for all interface elements. The image itself is never tinted.
- **Settings ▸ General ▸ Appearance:** System (the default, following macOS live), Light or Dark. It applies at
  once to every window, sheet and panel, and is remembered between launches.

### FR-14.3 Finder
- Colorbee is registered for every format in FR-11.1, so it appears in **Open With**.
- An **Open in Colorbee** item in the Finder right-click menu (Services / Quick Actions).

### FR-14.4 Screenshots
- Colorbee doesn't watch any folder for screenshots. The quick route is the clipboard: **Cmd+Ctrl+Shift+4** (or 3), then **Paste into New Image (Cmd+Shift+V)** for a new document, or **Cmd+V** into an open one. Either way the screenshot also appears in Clipboard History.
- A screenshot saved to a file opens like any image (Open, drag and drop, Open With, or Open in Colorbee).

### FR-14.5 Menus and shortcuts

| Menu | Items |
|---|---|
| **File** | New (Cmd+N), Paste into New Image (Cmd+Shift+V), Open (Cmd+O), Open Recent · Close (Cmd+W), Save (Cmd+S), Save As (Cmd+Shift+S), Duplicate, Revert To · Export… (Cmd+Opt+S), Export as PDF…, Export As ▸ presets · Share, Set as Desktop Picture · Page Setup, Print (Cmd+P) |
| **Edit** | Undo (Cmd+Z), Redo (Cmd+Shift+Z), Undo on Active Layer (Cmd+Opt+Z) · Cut (Cmd+X), Copy (Cmd+C), Copy Merged (Cmd+Shift+C), Copy Text (Cmd+Opt+C), Paste (Cmd+V), Paste in Place (Cmd+Opt+Shift+V), Delete · Select All (Cmd+A), Deselect (Cmd+D), Invert Selection (Cmd+Shift+I), Feather…, Modify Selection ▸ Expand…, Contract…, Smooth…, Select Subject, Color Range…, Luminance Range…, Graduated Selection |
| **View** | Zoom In (Cmd+=), Zoom Out (Cmd+-), Actual Size (Cmd+0), Zoom to Fit (Cmd+9) · Pixel Grid (Cmd+'), Rulers (Cmd+R), Before/After (Cmd+Opt+B) · Sidebar (Ctrl+Cmd+S), Layers (Cmd+L), Adjustments, History (Cmd+Y), Clipboard History (Cmd+Opt+V), Info (Cmd+Opt+I), Page Sidebar (Cmd+Opt+2), Status Bar · Enter Full Screen. Panels and display aids show a checkmark when on. |
| **Image** | Crop to Selection (Cmd+Shift+X), Crop…, Resize and Skew (Cmd+E), Canvas Properties (Cmd+Opt+E) · Rotate ▸, Flip ▸, Straighten…, Perspective Correction… · Remove Background · Symmetry ▸ |
| **Layer** | New (Cmd+Shift+N), Duplicate (Cmd+J), Delete (Cmd+Delete), Lift Subject to New Layer · Merge Down (Cmd+Shift+E), Merge Visible (Cmd+Opt+Shift+E), Flatten · New Adjustment Layer ▸, Merge Adjustment, Revert Layer · Hide/Show Layer (no default shortcut), Lock/Unlock Layer, Layer Properties |
| **Page** | New Page, Duplicate Page, Delete Page · Move Page Up, Move Page Down · Previous Page (Cmd+Opt+Up), Next Page (Cmd+Opt+Down) |
| **Adjustments** | Adjust Photo…, Auto Contrast · Levels…, Curves… · Hue/Saturation…, Desaturate (Cmd+Shift+U), Sepia… · Invert Colors (Cmd+I), Posterize… · Remove Red-Eye · New Adjustment Layer ▸ |
| **Effects** | Gaussian Blur…, Motion Blur…, Sharpen… · Pixelate…, Add Noise…, Emboss… · Vignette…, Spotlight… · Drop Shadow…, Border… |
| **Redact** | Auto-Redact… · Batch Redact: Blur…, Pixelate…, Solid Fill with Color 1 |
| **Window** | Standard |
| **Help** | Colorbee Help (Cmd+?), and macOS's search field (FR-14.6) |

**Single-key shortcuts** (active only when you're not typing text): X swap colors, D default colors, [ and ] change size, Space (hold) pan. One key per tool: P pencil, B brush, E eraser, G fill, T text, I eyedropper, Z magnifier, M rectangle select, L lasso, W magic wand, U shapes, R measure. Stage 13 adds J retouch, S clone stamp, K redact brush and N step badge.

Every shortcut above is a default. All of them can be changed in the shortcut editor (FR-15.3).

### FR-14.6 Help
- **Help ▸ Colorbee Help (Cmd+?)** opens a standard Mac Help Book in Apple's help viewer. Below it, the Help menu lists every guide and reference page as a quick link, under "Guides" and "Reference" headings. It ships inside the app
  and works offline. Cmd+? is reserved (FR-15.3), so it can't be reassigned.
- The Help menu's search field finds help topics as well as menu items.
- **Contents:** task guides first (Getting started, Redact a screenshot, Annotate an image, Work with layers, Fix up
  a photo, Pages and PDFs, Pixel art, Save, export and share), then a reference (Tools, Menus, Panels, Settings,
  Keyboard shortcuts, Privacy, Troubleshooting). The Menus and Keyboard shortcuts pages are generated from the app.
- **About 9 screenshots**, light mode only, made-up content only, taken by a script so they can be retaken. The
  pages themselves follow light and dark mode.
- **Contextual ? buttons** open the matching section: the Auto-Redact sheet, Settings ▸ Shortcuts and Export
  Presets, Resize and Skew, Canvas Properties, the Develop window, and the Retouch tool's options (the Clone Stamp
  opens its own section).
- The help describes what the app actually does, and leaves out hidden features (palettes). Plan:
  `Docs/HELP-PLAN.md`.

---

## 18. FR-15 — Presets and customization

### FR-15.1 Palettes (hidden for now, 2026-10-05)
- Save the current 28 swatches and 4 custom colors as a named palette. Load, rename, delete, import or export palettes (`.colorpalette`). Reset to the classic palette.
- The chosen palette is kept between launches.

### FR-15.2 Text styles
- See FR-6.2.

### FR-15.3 Keyboard shortcut editor
**Settings → Shortcuts** (Colorbee → Settings…, Cmd+,).

**The list**
- Every menu command and every single-key action (tools, X, D, [ and ]) appears, grouped by menu, with a search field.
- Each row shows the command name, its current shortcut, and a mark if it differs from the default.

**Changing a shortcut**
- Click the shortcut cell and press the new key combination to record it. Esc cancels the recording. Delete clears the shortcut (the command then has none).
- **Menu commands** need Cmd or Ctrl in the shortcut. **Tool and canvas keys** can be a single key or Shift + a key, and are never active while you're typing text.
- The new shortcut works immediately and shows in the menus straight away.

**Protecting macOS shortcuts (never stepping on the Mac's toes)**
- **Blocked:** Colorbee refuses shortcuts that belong to macOS or to standard Mac app behavior, and says who owns them. For example: "Cmd+H is used by macOS to Hide Colorbee." These include:
  - App menu standards: Cmd+Q, Cmd+H, Cmd+Opt+H, Cmd+, and Cmd+Opt+Esc.
  - Window standards: Cmd+W, Cmd+M, Cmd+Opt+M, Cmd+` and Ctrl+Cmd+F.
  - Help and input: Cmd+Shift+/, Ctrl+Cmd+Space and Fn/Globe shortcuts.
  - System-wide: Cmd+Tab, Cmd+Space, Cmd+Shift+3/4/5, Ctrl+Cmd+Q.
  - **Any shortcut currently set system-wide in System Settings → Keyboard → Keyboard Shortcuts** (Mission Control, Spaces, Spotlight, Screenshots, input sources and so on). Colorbee reads these from the system, so the list matches this Mac even after they've been customized.
- **Warn, then offer to reassign:** if the shortcut is already used by another Colorbee command, Colorbee names it and offers **Reassign** (the other command loses its shortcut) or **Cancel**.
- **Cmd+Z, Cmd+X, Cmd+C, Cmd+V, Cmd+A and Cmd+S** can be changed, but only after a confirmation, because every Mac app expects them.

**Resetting and backing up**
- Reset one shortcut, or **Reset All** to the defaults.
- Export and import the whole set as a file (`.colorbeekeys`).
- Custom shortcuts are kept between launches.

---

## 19. Non-functional requirements

| ID | Requirement |
|---|---|
| NFR-1 | Cold start to a drawable canvas **on screen** in **under 500ms** on Apple Silicon. Measured at ~330–400ms (Sept 2026); the limit guards against regressions. |
| NFR-2 | Colorbee's processing, from the input event to the frame handed to macOS, **under 16ms**. Strokes must use every input sample, with none skipped. Measured ~5ms; the full input-to-screen figure (~22ms, mostly macOS window compositing) is reported but not a limit. |
| NFR-3 | Memory use is measured, not guessed: record it at 1920×1080 once the core is built, then keep it from growing. Expected range: 100–150MB. |
| NFR-4 | 8000×8000 images open, draw, undo and export without stalls or crashes. |
| NFR-5 | Full Light/Dark mode support. |
| NFR-6 | Blur, pixelate and fill on a 1920×1080 image finish in under 100ms. Any single undo or redo step takes under 100ms. |
| NFR-7 | Crash-free: a 30-minute continuous editing session at 8000×8000 with no crash or data loss. |
| NFR-8 | Everything happens on this Mac. No network access, analytics or accounts. |

---

## 20. Build order

Everything ships. This is only the order work happens in, and each stage builds on the one before.

1. **Walking skeleton:** window → canvas → one brush → undo → paste → PNG export. Measure NFR-1, 2 and 3.
2. **Core model:** document and layers (starting with 1 layer), history, selection and floating selection, zoom/pan/grid.
3. **Everyday editing:** Pencil, Round brush, Marker, Eraser/Color Eraser, Fill, Eyedropper, Rectangle/Ellipse/Lasso select, drag-to-resize selections, crop, blur, pixelate, basic shapes (line, arrow, rectangle, rounded rectangle, ellipse), text, copy, export in all formats.
4. **Redaction:** Magic Wand, combined selections, batch redaction, Auto-Redact, Before/After, export presets.
5. **Full toolset:** the other 6 brushes, pressure, all 23 shapes with every style, gradients, resize/skew/rotate/flip, symmetry, measure, sharpen and adjustments. Built in two parts (5a routine, 5b hard), then **5c Interface:** the mockup look for the toolbar (FR-1.1, including the Magnifier), the palette bar with custom colors, Alpha and Edit Colors (FR-1.2), and the status bar with the zoom slider (FR-1.5). The right sidebar (FR-1.3) arrives in stage 6 with the Layers panel; palette management (FR-15.1) stays in stage 7.
6. **Layers:** layers panel, blend modes, opacity, adjustment layers, per-layer undo, .colorproj.
7. **Integration:** Clipboard History, History panel, palettes, text styles, shortcut editor, Finder, share, print, desktop picture.
8. **Hardening:** performance, 8000×8000 soak tests, polish.
9. **Photo editing and presentation (later phase):** the FR-9.5 adjustments and effects, with their own performance and soak checks.
10. **Pages and PDF documents:** FR-11.6. 10a pages: the document of pages, the page sidebar, page commands and undo, opening PDFs, TIFFs and GIFs, projects, memory. 10b output: Export as PDF, Auto-Redact on every page, the resolution setting.
11. ~~**Import from iPhone or iPad:** FR-11.7.~~ Removed (Leah, 2026-10-19).
12. **RAW photos:** FR-11.8. Develop window, RAW as another way in, camera details on export.
13. **Retouching and annotation extras:** FR-3.4, FR-4.6, FR-5.3, FR-9.5 (Remove Red-Eye), FR-9.6, FR-10.4. In four parts:
    - **13a quick wins:** Copy Text, Step Badges, and the Redact Brush with Blur, Pixelate and Solid Fill.
    - **13b Match Surroundings:** a trial build of the fill engine first, judged by Leah on her own test pictures; then the engine with its own performance and soak checks, Remove and Spot Heal.
    - **13c** Clone Stamp, the local brushes, Remove Red-Eye.
    - **13d Soft selections** (FR-3.4). This touches every command that uses a selection, so it comes last.
14. **Lightroom-style photo editing (Leah, 2026-10-27):** FR-9.7, built in parts that Leah and Claude settle together. After it come the layer follow-ups and the other approved ideas.

---

## 21. Acceptance criteria

Ticked when Leah's hand tests of the stage that built it passed (stages 1–9, all by 2026-10-03), or, for AC-1, when measured.

- [x] AC-1 Cold launch shows a drawable canvas on screen in under 500ms.
- [x] AC-2 Left-click draws with Color 1 and right-click with Color 2 for Pencil, all brushes, Fill, Shapes and Gradient.
- [x] AC-3 X swaps the colors. D resets them.
- [x] AC-4 Right-drag with the Eraser changes only Color 1 pixels.
- [x] AC-5 Magic Wand respects Tolerance and Contiguous.
- [x] AC-6 Shift, Option and Shift+Option combine selections as FR-3.2 describes.
- [x] AC-7 Shift-drag of a selection leaves the smear trail.
- [x] AC-7a Dragging a pasted image's handle stretches it freely. Shift keeps the proportions. Shrinking and then enlarging again before committing looks identical to the original.
- [x] AC-8 Blur, Pixelate and Fill affect only the selection. Batch redaction handles each separate region on its own, as one undo step.
- [x] AC-9 Auto-Redact finds emails, phone numbers, card numbers and API keys in a test screenshot, entirely offline.
- [x] AC-10 Before/After compares the current image with either "As Opened" or "Last Saved", and switching between them works.
- [x] AC-11 Export presets produce the right width, keep the aspect ratio and never enlarge.
- [x] AC-12 Cmd+V paste keeps full resolution and alpha. Cmd+C puts a PNG with transparency on the system clipboard.
- [x] AC-13 Clipboard History shows the last 10 images. Clicking one pastes it and leaves the system clipboard unchanged.
- [x] AC-14 Pixel grid at 400% and above. Pixels stay sharp at every zoom level on Retina screens.
- [x] AC-15 Every file format in FR-11.1 opens and saves again with no unexpected loss. Color profiles are kept.
- [x] AC-16 .colorproj saves and reopens layers, opacity, blend modes, visibility and adjustment layers exactly.
- [x] AC-17 Undo on Active Layer reverts only the active layer.
- [x] AC-18 Adjustment layers stay editable. Merge Adjustment turns them into pixels.
- [x] AC-19 Undo history survives a save.
- [x] AC-20 Quit and relaunch brings back open documents, including untitled ones, with no prompt.
- [x] AC-21 Symmetry mirrors strokes live in every mode.
- [x] AC-22 Measure shows the distance, ΔX, ΔY and angle.
- [x] AC-23 Pressure changes brush size on a Force Touch trackpad.
- [x] AC-24 "Open in Colorbee" works from Finder.
- [x] AC-25 A clipboard screenshot (Cmd+Ctrl+Shift+4) opens with Paste into New Image at its full size, and appears in Clipboard History.
- [x] AC-26 Palettes and text styles are kept between launches.
- [x] AC-27 8000×8000: draw, blur, undo 50 steps and export with no stall over 1s and no crash. _(Accepted by Leah 2026-10-04: the fifth 30-minute soak ran 108 rounds with no crash, undo and redo exact every time, and 13 of about 6,500 steps a little over a second (whole-image Flatten, Sharpen and Blur at 8000×8000; worst 1.7 s), which Leah judged rare and acceptable.)_
- [x] AC-27a A locked layer rejects every pixel edit, move, merge and delete, and can still be hidden and reordered.
- [x] AC-27b All 17 blend modes render the same on screen and in export.
- [x] AC-27c Picking a color with Edit Colors… fills the next custom slot. The slots survive a relaunch.
- [x] AC-28 The shortcut editor changes a command's shortcut, and the menus update immediately.
- [x] AC-29 The shortcut editor blocks every macOS-owned shortcut (including ones customized in System Settings) and names the owner.
- [x] AC-30 Assigning a shortcut already used in Colorbee offers Reassign or Cancel. Reset All brings back the defaults.
- [x] AC-31 Auto Contrast (and Levels → Auto) makes the darkest pixel black and the lightest white, per the image, in one undo step.
- [x] AC-32 Every FR-9.5 adjustment and effect previews live, applies only inside a selection when there is one, and undoes exactly.
- [x] AC-33 Drop Shadow and Border grow the canvas to fit, follow a cutout's shape, and undo restores the original size.
- [x] AC-34 Straighten levels a line drawn along a tilted horizon. With Crop to Fit on, no empty corners remain.
- [x] AC-35 Adjust Photo's Auto moves only the sliders it lists (from FR-9.7, Whites too) and shows which; the whole panel is one undo step and also works as an adjustment layer.
- [x] AC-36 A filter at 50% intensity gives the same result as its slider values halved. A saved filter survives a relaunch and round-trips through a .colorbeefilter file.
- [x] AC-37 Remove Background leaves soft edges in transparency; Select Subject picks only the clicked subject; an image with no subject asks for a click on one and changes nothing if cancelled; a click on a small subject the first look missed finds it.
- [x] AC-38 Crop with a pixel-size preset produces exactly that size; Perspective Correction turns a photographed rectangle into a rectangle.
- [x] AC-39 Cmd+? opens Colorbee Help (FR-14.6).
- [x] AC-40 Typing "redact" in the Help menu's search lists the Redact a screenshot guide.
- [x] AC-41 Every menu command appears in the Menus reference with its default shortcut.
- [x] AC-42 Each contextual ? button opens the matching section.
- ~~AC-43 Scan Documents from an iPhone adds the scans as pages after the page shown, at the phone's own pixel size, as one undo step; with no window open, they open as a new document.~~ Removed with FR-11.7 (2026-10-19).
- [x] AC-44 Copy Text on a screenshot puts its text on the clipboard in reading order. On an image with no text it says "No text found" and leaves the clipboard unchanged.
- [x] AC-45 Step badges count 1, 2, 3 in order; undoing one steps the next number back; Letters gives A, B, C.
- [x] AC-46 The Redact Brush changes every layer with pixels under the stroke, as one undo step, and is blocked by a locked layer with pixels there.
- [x] AC-47 Remove on an object against sky, a wall or a flat screenshot area leaves no visible trace (judged by Leah on her test images), and the same stroke on the same image gives an identical result.
- [x] AC-49 Clone Stamp copies with a constant offset while Aligned is on; Spot Heal removes a dust spot with the tone matched.
- [x] AC-50 The local brushes don't build up within one stroke; a second stroke adds more.
- [x] AC-51 Remove Red-Eye darkens red pupils in a flash photo and changes nothing in a photo without red-eye.
- [x] AC-52 Delete on a feathered selection leaves a soft edge; a redaction treats every partly selected pixel as fully selected.
- [x] AC-53 The app contains no machine-learning model files; retouching uses only the image's own pixels.
- [x] AC-54 An adjustment layer set to "Only the layer below" changes only that layer, on screen, in exports and in Copy Merged; it's saved in .colorproj, undoes as one step, and Merge Adjustment bakes it into that layer alone.

---

## 22. Open questions (for Leah)

None right now.

---

## 23. Decision log

| Date | Decision |
|---|---|
| 2026-10-28 | **Stages 22 to 24 answers** (Leah: "use your recommendations", Q22.1 to Q24.4 in `Docs/Development-Plan.md`; built one after another, then hand tested together). **Stage 22:** Select All Layers on ⌥⌘A, including hidden and adjustment layers; isolating a layer, and undoing it, are each one undo step; if visibility changes while isolated, the second Option-click shows everything; Stamp Visible goes just above the active layer, named "Stamp", with no default key. **Stage 23:** the padlock becomes a small menu (Lock All, Lock Transparent Pixels) and the row shows which; the Eraser on such a layer paints Color 2 inside the shape, with no holes; every tool, effect, adjustment and Delete respects it. **Stage 24:** Align refuses with a message when it would push pixels off the canvas; it goes by each layer's visible pixels; one chosen layer aligns to the canvas, or to the selection if there is one; greyed out if a chosen layer is locked. |
| 2026-10-28 | **Copying a color's hex** (Leah): the readout clears as the pointer leaves the picture, so its hex couldn't be clicked. Instead, the eyedropper at the start of the readout is a button: click it, then a color in the picture, and its hex is copied (Leah's choice); Edit ▸ Copy Color as Hex (⌃⌘C) copies the hex under the pointer (also Leah's). My choices (veto any): the status bar's eyedropper works whatever the tool, takes one click, beeps off the picture and stays on, and Esc turns it off; ⌃⌘C works while an effect's bar is open, and beeps off the picture. |
| 2026-10-28 | **Stage 21 built** (my choices, veto any): faces come after each page's text in the list, numbered through the whole document in reading order (rows top to bottom, each left to right). The test picture is three made-up shaded faces (`TestImages/Auto-Redact Faces.png`), which Vision finds; flat cartoon faces it didn't, so none of Leah's photos was needed. The "can be missed" note shows whenever the Faces row is on. With nothing found, the sheet says "No sensitive text or faces found." |
| 2026-10-28 | **Stage 20 built** (my choices, veto any): the readout sits after the pointer position, with a small swatch, and says "Copied" for a moment after a click on the hex. A sample's opacity is the average of its pixels', and its color is weighted by their opacity, so a half-transparent edge doesn't darken it. Sample Size isn't remembered between launches. Reading what's shown now works out a patch around the pointer wide enough for blurs, sharpening and Adjust Photo's detail to reach in, placed where it sits so the vignette and grain match: the Eyedropper's Option-click and the white-balance eyedropper on an Adjust Photo layer match an export too. |
| 2026-10-28 | **Stage 19 built** (my choices, veto any): converting to sRGB keeps colors just inside sRGB (the system's relative conversion). The size limit tries full quality first, then the lowest, then halves the range eight times, keeping the best that fits; while it works, the canvas shows "Fitting the file into 200 KB…". While the limit is on, the Quality slider is greyed out, since Colorbee picks the quality. Color 2 behind a JPEG's transparent areas is converted with the picture. In Settings, each preset's Color is a small menu at the end of its row ("Keep", "sRGB", "Display P3"); presets saved before keep the document's. |
| 2026-10-28 | **Stages 19 to 21 answers** (Leah: "use your recommendations", Q19.1 to Q21.5 in `Docs/Development-Plan.md`; built one after another, then hand tested together). **Stage 19:** Export… and each Export As preset get Color (Keep, sRGB, Display P3; no Adobe RGB), while Copy, Share and PDF keep the document's profile; "Limit file size to [ ] KB/MB" is a checkbox in Export… for JPEG and HEIC; if even the lowest quality is too big, a message gives the smallest size possible and nothing is written; both are remembered between launches; 1 KB is 1,000 bytes. **Stage 20:** the status bar's color readout reads what you see (all layers), in sRGB, labeled "sRGB"; the Eyedropper's Sample Size is 1 px (to start), 3 × 3 or 5 × 5; the readout follows the sample size while the Eyedropper is chosen, and a click on the hex copies it; status bar only. **Stage 21:** test with made-up faces first, asking Leah for a photo of her own, kept outside the repo, only if Vision misses them; a Faces row in the pattern list, on to start; boxes 30% bigger than Vision's; the same treatment as the text matches; even tiny faces are listed, to untick. |
| 2026-10-28 | **No betas until it's all done** (Leah): the betas planned after stages 16, 21, 26, 28b and 31 are dropped. The next beta comes only when every stage is built and Leah has tested all of it; internal testing always comes before external. **Also:** Adjust Photo's histogram follows a dragged slider about ten times a second, from a copy 160 pixels across, since working it out on every step made Exposure stutter (Leah's report). |
| 2026-10-28 | **Stage 18b built** (my choices, veto any): the anchor grid sits beside Width and Height, with the chosen square filled. A selection now moves with the picture and keeps only what's still on the canvas, for the canvas's edge handles too (before, resizing cleared it); the edge handles keep the picture at the top-left. |
| 2026-10-28 | **Stage 18a built** (my choices, veto any): Trim treats the border as transparent if any corner is fully transparent; then any pixel that isn't fully transparent counts as picture, so soft edges are kept whole. Otherwise "within about 2%" is 5 levels in each channel, alpha included, from the top-left pixel. The step is named "Trim". A floating selection is placed first, as Crop does. |
| 2026-10-28 | **Stage 17 built** (my choices, veto any): Perspective Correction looks at the picture as shown (every layer). Vision's guess counts only if each of its four sides runs along a clear step in brightness (it also "finds" rectangles in round things); the biggest such rectangle wins, at least a fifth of the picture across. Reset is beside the hint and is greyed out until a corner moves. Crop…'s O shows the new guides for 2 seconds, with their name at the bottom of the canvas, as well as while dragging. Grid is 8 × 8; Diagonal runs 45° in from each corner; Triangle is one diagonal with a square-on line from each other corner; the Golden Spiral is stretched to the box and turned a quarter on an upright one. |
| 2026-10-28 | **Stage 16 built** (my choices, veto any): the hand stays on for drag after drag until it's clicked off or Esc is pressed, unlike the one-click eyedroppers; the pointer shows up-and-down arrows while it's on. A drag of 200 points moves a slider from 0 to its end (half a step a point). It reads the 5 × 5 pixels around where the drag starts. The Color Mixer's hand follows the tab showing (Hue, Saturation or Luminance; the gray mix with Black & White on), and a press on a gray, which has no color range, beeps. The Tone Curve's region is chosen by the pixel's brightness against the split points. |
| 2026-10-28 | **Stage 15 built** (my choices, veto any): the histogram shows the whole picture as it now looks (every layer, worked out from a copy at most 320 pixels across), even when Adjust Photo changes only a selection. Highlight clipping means any channel at white; shadow clipping means every channel at black. The warning buttons are small triangles in the histogram's corners (shadows left, highlights right) and stay on until turned off, for every picture, while Colorbee is open. The Tone Curve section comes after Light, with its graph, the split points' line, then Highlights, Lights, Darks and Shadows, lightest first; each region moves its stretch of the curve by up to 45% of the way to its neighbors, so the curve can't fold back. Moving a split with every amount at 0 is still kept. Small pictures in the History panel now show Adjust Photo layers' color and tone too. |
| 2026-10-28 | **Stages 15 to 18b answers** (Leah: "use your recommendations", Q15.1 to Q18.5 in `Docs/Development-Plan.md`; built one after another, then hand tested together). **Stage 15:** a live histogram at the top of Adjust Photo; clipping warnings as two buttons on it, off by default, with no key; the parametric curve's four regions sit under a "Tone Curve" heading as Highlights, Lights, Darks and Shadows; parametric only, since Curves… does point curves. **Stage 16:** the hand drives the tone curve or the Color Mixer, depending on which section's hand is clicked; dragging up is more. **Stage 17:** Perspective Correction finds corners every time it opens, falling back to today's, with a Reset button; Crop… overlays are Thirds, Grid, Diagonal, Triangle, Golden Ratio and Golden Spiral, switched with O while cropping and shown while dragging; Crop…'s shading of the cut-away area stays as it is (Q17.3). **Stage 18a:** Image ▸ Trim, one click; a 2% tolerance; decided by everything shown, all layers cropped. **Stage 18b:** the anchor starts at Center each time; it also decides which edges a smaller canvas cuts. Leah approved the Trim and anchor FRD lines. |
| 2026-10-28 | **Stage 14 built** (my choices, veto any): Vignette's and Grain's settings sit under arrows, closed to start, like Sharpness's. Roundness 0 is today's shape, which follows the picture's own proportions; +100 is a circle sized to the shorter side; −100 is close to a rectangle with rounded corners. Feather scales the fade's width (50 today's, 0 a hard edge, 100 twice as wide). Grain is the same for every channel (monochrome, like film); Size sets each grain from 1 to 4 pixels across, and Roughness mixes in grain half that size. Each pixel's grain is fixed, so a selection's grain lines up with the rest of the picture. Grain comes after the vignette. Save Filter from Layers now leaves Sharpness's and Noise Reduction's finer settings out of the filter, as Save as Filter does. |
| 2026-10-28 | **Stage 13 built** (my choices, veto any): the Noise Reduction slider itself is the luminance amount, so its finer settings are Detail, Color and Color Detail (no separate "Luminance" slider). Detail settings start at 50, which is today's look; Sharpness Detail below 50 damps strong edges (halos) and above 50 boosts small differences (fine grain); noise Detail scales the edge thresholds (twice as protective every 25 points up). Color noise reduction compares each pixel's color with its 3 px surroundings, the blur Texture uses. Masking compares a pixel with that same blur: 0 sharpens everywhere, 100 only clear edges. The arrows start closed, and which are open is remembered in every window. Copying settings, As Adjustment Layer and Apply never take the Masking view. |
| 2026-10-28 | **Stage 12 built** (my choices, veto any): the panel's New Snapshot button is a camera, beside a "Snapshots" heading above the steps; snapshots are listed oldest first. New Snapshot… suggests "Snapshot 1", "Snapshot 2" and so on, and opens the History panel if it's closed, so you see the new snapshot. A snapshot keeps the marquee selection too; a floating selection is placed first (keeping its outline). Going to a snapshot leaves just the active layer chosen, like Undo. A snapshot is compressed to a scratch file at once (0.07 s at 8000 × 8000), so it takes almost no memory and nothing counts against undo's memory budget. Rename and Delete are in the snapshot's Control-click menu. |
| 2026-10-28 | **Stage 11 built** (my choices, veto any): Import Filter… takes both `.colorbeefilter` and `.cube` files, and the filter you import is chosen straight away, so you see it (before, an imported filter was only added to the strip). Colors between a look's points are blended from the four around them (tetrahedral blending, which keeps grays gray and is what most editors use). Looks of up to 129 points a side are taken (the biggest in common use are 65); a larger one says it's too large. A look with a DOMAIN other than 0 to 1 is accepted. While a look is chosen, the screen uses the finer 65-point color table, as for the Color Mixer. |
| 2026-10-28 | **Stages 11 to 14 answers** (Leah: "use your recommendations", Q11.1 to Q14.4 in `Docs/Development-Plan.md`; built one after another, then hand tested together). **Stage 11:** .cube looks are imported only from the filter strip's menu; they apply to the document's own color values, as Photoshop's Color Lookup does; a look is named from the file's TITLE line, or the file name if there's none; an exported look filter carries its table; one-dimensional .cube files get a plain "not supported" message. **Stage 12:** a snapshot keeps its own copy, capped at about 10 per page with a message at the cap; snapshots aren't saved in the project; Remove Earlier Versions and Undo History deletes them too; New Snapshot… is a History panel button and Edit ▸ New Snapshot…, with no key; going to a snapshot is an undo step ("Go to Snapshot"); each page has its own. **Stage 13:** Sharpness gets Radius (0.5–3 px), Detail and Masking, and Noise Reduction splits into Luminance and Color, each with Detail, starting at today's look; Option-drag on Masking shows the edge mask; the extra settings sit under a disclosure arrow. **Stage 14:** Vignette's Midpoint, Roundness and Feather start at today's shape; Grain has Amount 0–100, Size 0–100 (25 to start) and Roughness 0–100 (50 to start); Effects ▸ Vignette… stays as it is; a new Effects section holds Vignette and Grain, with Vignette moved out of Detail. |
| 2026-10-28 | **Luminance Range presets** (Leah): Shadows, Midtones and Highlights are a segmented control that shows the preset in use, Shadows when the bar opens. Once the handles are dragged off every preset, none is chosen; dragging back onto one chooses it again. |
| 2026-10-28 | **Stage 10 built** (my choices, veto any): the fade is smooth at both ends (an S-curve, not a straight ramp), and runs across the line, so its edges are straight and at right angles to it. Before Return, a drag within 12 points of an end moves that end; a drag anywhere else draws a new line. White guides cross the picture at both ends, as in Lightroom. Return waits until a line is drawn. It isn't an undo step, like the other selections. |
| 2026-10-28 | **Stage 9 built** (my choices, veto any): **Color Range** compares colors as the Magic Wand does, by the largest difference in any channel; Fuzziness 25% is a range of about 64 levels, fully selected up to half of it and fading smoothly to nothing at its edge. A click picks the 5 × 5 average, like the other eyedroppers, and replaces the colors picked; Shift-click adds one; a click on empty pixels beeps. Return waits until a color is clicked (Apply is greyed out). **Luminance Range** opens at Shadows; Shadows is 0–30, Midtones 35–65 and Highlights 70–100 (0 black, 100 white), and Smoothness (50 to start) fades the selection out up to 40 points beyond the bounds. Transparent pixels aren't selected by brightness. Both are effect bars with a red tint like Feather's, aren't undo steps, and share Sample All Layers with the Magic Wand; on an adjustment layer they always read everything shown. |
| 2026-10-28 | **Stage 8 built** (my choices, veto any): Copy, Cut and Copy Merged all record where the pixels came from; copying the whole image (nothing selected) records the top-left. A moved or resized selection records where it is now. When the copy is bigger than the canvas, Paste in Place asks Enlarge Canvas or Keep Canvas Size as ⌘V does; Keep Canvas Size puts it at its place, and Enlarge Canvas at the top-left, as ⌘V does. Paste in Place isn't in the canvas's Control-click menu, which keeps to the everyday commands. |
| 2026-10-28 | **Stage 7 built** (my choices, veto any): Expand and Contract use a round area, so corners come out round when growing; 1 px is a 3 × 3 square, so a hard selection grows diagonally too. At the canvas's edge the selection carries on, as with Feather: Select All then Contract keeps the whole canvas. **Smooth** fills notches and holes narrower than its radius, then removes specks and spurs narrower than it, which rounds corners (a closing, then an opening); soft edges stay soft. When Contract or Smooth would leave nothing selected, the sheet says "Nothing would be left selected" and OK is greyed out. Feather keeps its 10 px start. On a huge selection, OK waits for the result, with "Working…" in the sheet, rather than freezing the window. |
| 2026-10-28 | **Stages 7 to 10 answers** (Leah: "use your recommendations", Q7.1 to Q10.4 in `Docs/Development-Plan.md`; built one after another, then hand tested together, as Leah asked: batch changes for testing where it's sensible). **Stage 7:** Edit ▸ Modify Selection ▸ Expand…, Contract… and Smooth…, next to Feather…; like Feather, not an undo step; 1 to 100 px, starting at 2 px; Expand and Contract keep a soft edge soft. **Stage 8:** Paste in Place (⌥⇧⌘V); a picture from another app pastes as ⌘V would, with no beep; into a different-sized document, the same place if any of it lands on the canvas, otherwise as ⌘V; Clipboard History items don't remember a place. Leah approved its FRD lines (FR-10.1). **Stage 9:** Edit ▸ Color Range… and Luminance Range…, next to Select Subject; they read the active layer, with Sample All Layers to read everything shown; Replace, Add, Subtract and Intersect in the bar, Replace first; Fuzziness 0–100%, starting at 25%; Luminance Range has a two-handle range with Smoothness, plus Shadows, Midtones and Highlights buttons. **Stage 10:** Edit ▸ Graduated Selection opens a canvas tool like Straighten's line; fully selected where the drag starts, fading to nothing where it ends; the same combining choices; Shift keeps the line at 0°, 45° or 90°. |
| 2026-10-28 | **Subjects always wait for a click** (Leah, recommended): Select Subject, Remove Background and Lift Subject no longer act at once when Vision's first look finds exactly one subject; the bar waits for a click, and Return takes the one found. In a photo of three cats, the first look saw only the black and white cats (as one), so the orange cat couldn't be reached; a click on her now looks closer and finds her. The bar says "Click the subject you want, even a small one, or press Return for the one Colorbee found" (Claude's wording, veto any). |
| 2026-10-28 | **Lifting one subject after another** (Leah, recommended): after Lift Subject the picture's layer stays active and is the only one chosen, with the new Subject layer just above it. Before, the Subject layer became active, so a second Lift Subject searched a layer holding only the first subject and couldn't find anything else. Lift Subject also opens the Layers panel, as New Layer does, so the new layer shows though it isn't active (Leah). |
| 2026-10-27 | **Stage 6 built** (my choices, veto any): Point Color sits between the Color Mixer and Color Grading, and applies in that order. Its eyedropper works like the white-balance one (one click, 5 × 5 pixels, Esc cancels, a beep where there's nothing to read); the two now share one pick mode. A pixel counts as a picked color when it's near in hue, colorfulness and lightness; Range widens all three (at 50 the next color range, 30° away, is left alone; at 100 it's taken in), and gray is never touched. The shifts work as the Color Mixer's. The newest picked color is the one shown; clicking a swatch shows another; a minus button removes it; with eight the eyedropper greys out. Holding Range grays out the rest on screen only; it's never saved or applied. A filter at 50% halves the shifts and keeps the colors and Range. Adjust Photo layers with Point Color use the finer color table. |
| 2026-10-27 | **Stage 5 built** (my choices, veto any): Color Grading sits under the Color Mixer. On the wheel, red is at the right and hues go round counterclockwise, as on a color circle; the farther out the point, the stronger (up to a 30% lean toward the hue, which tints without changing brightness much). Clicking the wheel puts the point there; dragging from the point moves it; Option slows it to a quarter; a double-click puts it back in the middle, keeping Luminance. The three tone ranges are soft bumps at black, middle gray and white, wider as Blending rises; Balance bends the brightness first, so to the right more of the picture counts as highlights. Grading comes after the Color Mixer and Black & White, so it tints a black-and-white picture. Blending and Balance on their own are kept (so they can be set before the wheels) but change nothing. Through the 33-point screen table it's within about 6 levels of the export, as the other sliders are, so it doesn't need the finer table. The four tabs use the smallest size to fit the sidebar. VoiceOver: the wheel reads its hue and strength, adjusts strength by 5, and has actions to turn the hue. |
| 2026-10-27 | **Stage 4 built** (my choices, veto any): the Color Mixer sits under Color as a section of its own. Each color range owns its center hue (Red 0°, Orange 30°, Yellow 60°, Green 120°, Aqua 180°, Blue 225°, Purple 270°, Magenta 315°) and hands over to its neighbor with a soft curve, and nearly gray pixels (under about 12% color) don't change. Saturation scales how far a color is from gray, like Adjust Photo's Saturation (+100 doubles it), so nearly gray noise isn't turned into color; Luminance moves the middle tones most and leaves near-black and near-white alone. Black & White starts at each color's brightness, as Mono does; while it's on, the Hue, Saturation and Luminance settings are kept but not used. A filter at 50% makes Black & White half gray. On screen, an Adjust Photo layer with a Color Mixer uses a finer 65-point color table (4.4 MB): measured, it's within about 8 levels of the export near a few colors' edges and 0.5 on average, which is what the color sliders already show at 33 points; a 33-point table was off by up to 17. Stage 2's Copy and Paste in the panel became small icon buttons (Copy Settings, Paste Settings), since the narrow sidebar cut Auto down to "A…". |
| 2026-10-27 | **Stage 3 built** (my choices, veto any): **Dehaze** treats haze as an even veil of light gray over the picture: +100 takes off a 60% veil, bringing back contrast and color (the darks most), and −100 lays one on, so −n undoes +n. It works per pixel, through the color table, so the screen matches the export and filters carry it; the plan's whole-picture "dark channel" estimate was dropped, since my first per-pixel try at it flattened a hazy photo instead of clearing it. It can't tell near haze from far haze, so a scene that's hazier at the back clears evenly. **Texture** brings out or smooths detail up to a few pixels across, against a blur of 3 px (Definition uses 12 px), so it leaves no wide glow; on screen it needs one more blurred copy under an Adjust Photo layer. `make perf` has a first-guess limit for Adjust Photo with every detail slider, to be tightened when it's next run. |
| 2026-10-27 | **Stages 2 to 6 answers** (Leah: "use your recommendations", Q2.1 to Q6.3 in `Docs/Development-Plan.md`; built one after another, then hand tested together). **Stage 2:** Adjustments ▸ Adjust Photo: Same as Last, Copy Photo Settings and Paste Photo Settings, with no default keys, plus Copy and Paste buttons in the panel; "last" is the last settings applied anywhere (Apply or As Adjustment Layer), kept across a relaunch; Paste opens Adjust Photo with the settings in place, so they're seen before Return; everything is copied; Adjust Photo layers can be copied from, and there's Paste as Adjustment Layer. **Stage 3:** Texture in Detail next to Definition, Dehaze in Light after Brilliance, both −100 to 100 (negative Texture softens, negative Dehaze adds haze). **Stage 4:** the eight ranges Red, Orange, Yellow, Green, Aqua, Blue, Purple, Magenta; Hue, Saturation and Luminance tabs of eight sliders; Hue ±100 is about ±30°; Black & White is a switch at the top of the Color Mixer, and Color Grading still tints it; the Black & White mix starts neutral, like Mono. **Stage 5:** Shadows, Midtones, Highlights and a Global wheel; one large wheel with tabs, with small dots for the others; a filter at 50% halves each wheel's strength and keeps its hue; Blending starts at 50 and Balance at 0. **Stage 6:** up to 8 picked colors; per color Hue, Saturation, Luminance and Range; holding the Range slider grays out what it doesn't touch. |
| 2026-10-27 | **Stage 1b built** (Leah): a dropper click where the active layer has nothing to read beeps, and the dropper stays on. My choices (veto any): the dropper is a small button beside Warmth's value, blue while it's on, in the Adjust Photo panel and for an Adjust Photo layer. On an Adjust Photo layer there's no bar, so the dropper takes just the next click, whatever the tool; it reads the layers below as shown, as that layer's Auto does. Esc turns the dropper off first; a second Esc closes Adjust Photo as before. Warmth and Tint set by the dropper lose Auto's mark. Whites moves the white point, as Black Point mirrored (+100 stretches 75% up to white), weighted so the darks don't move and the mids only a little. Auto aims the brightest 0.2% of the photo just under white, at most +50. Vivid Warm and other filters still come out gray, but a filter plus more Saturation can push a cast beyond Warmth's reach, since white balance comes after saturation; the dropper then goes as far as it can. `Color Cast.png` has a cast within reach. |
| 2026-10-27 | **Magic Wand on game screenshots** (Leah, all recommended; planning only, not built; `Docs/Proposals/Magic Wand on Game Screenshots.md`): the wand gets a **Color / Object** choice; in Object mode a click selects the object under it, using Select Subject's search and its closer look (Claude's details, veto any: Shift and Option add and subtract; Tolerance and Contiguous are greyed out; Esc stops the search; nothing found beeps and changes nothing; the mode is remembered, Color by default). If the wand's color matching changes, Fill changes with it, so tolerance means one thing in both. New wand settings would be Sample Size as a small menu, and Fill Pinholes and Soft Edge as toggles that are on by default; perceptual matching may change what a given tolerance selects, and that's accepted. |
| 2026-10-27 | **Stage 1a built** (Leah, all recommended): a filter's vignette applies after all the colors, the filter's first and then the panel's own, and Intensity scales its amount. Only saved filters move to the test builds' own folder; Clipboard History and desktop pictures stay shared. Stage 1a's hand test hides the other layers before Save Filter from Layers, since that command uses every visible adjustment layer. My choices (veto any): filters now live in `Photo Filters.json`; test builds (every build but a signed beta) keep theirs in Application Support ▸ Colorbee Test Builds, and each starts as a copy of the everyday copy's filters (or beta 7's); `Filters.json` stays for older versions and is never written again. Save as Filter takes the vignette into the new filter along with the colors, so the slider goes back to 0; Sharpness, Definition and Noise Reduction stay on the panel. An Adjust Photo step left with nothing a filter may hold is left out. A filter step of a kind this version doesn't know is skipped; a filter file with nothing left is refused, as before. Sliders added from now on are saved beside the old list, where beta 7 doesn't look, so it still opens the rest. The Save as Filter and Save Filter from Layers questions now say what they keep. |
| 2026-10-27 | **Development plan review, round 2** (Leah, `Docs/Development-Plan.md`; both recommended). **History Snapshots** keep their own copy of every layer, so they survive new edits, with a cap of about 10 and a clear message at the cap. They can be renamed and deleted. My choice (veto any): the cap counts per page, like the undo history. **The color readout** (FR-9.7 item 9) is in the status bar only, not the Info panel. |
| 2026-10-27 | **Development plan review answers** (Leah, `Docs/Development-Plan.md`; all recommended except the warning). **Filter Intensity** scales only amounts: Grain size and roughness, Vignette midpoint, roundness and feather, and the tone curve's split points stay as saved. **Test builds** keep their own settings folder, so they never touch the everyday copy's filters or settings. **No warning** when an older Colorbee opens a file from a newer one (Leah is the only user for now). **The white-balance eyedropper** reads the picture before Adjust Photo's other settings; on an Adjust Photo layer, the layers below it. **Undo on Active Layer and Revert Layer** include the layer's mask. **One-dimensional .cube files** get a plain "not supported" message; 3D looks are supported. **Clip to the layer below for pixel layers** is in scope, with layer masks (as in the gap analysis answer 2b). **Stage 1 is built in two parts:** 1a (file format, filters file, settings folder, folding sections, filters that hold more than colors) and 1b (pick from the picture, Whites, the eyedropper, Auto); the beta follows 1a. **Also added:** a Canvas Size anchor (Canvas Properties chooses where the picture stays when the canvas changes size; its FRD lines come with its stage). **Small calls:** Export's Limit file size counts 1 KB as 1,000 bytes, as Finder does. On a layer with transparent pixels locked, Flip, Rotate, Crop, Resize and Straighten work as usual, and a one-layer picture saved as a PNG doesn't keep that lock, like today's padlock. |
| 2026-10-27 | **Development plan answers** (Leah, `Docs/Development-Plan.md`; all recommended except Auto). **Process:** an item not yet in the FRD (Paste in Place, Trim, the layers round 2, layer masks, re-editable text, stroke smoothing) gets its FRD section drafted and approved before its stage is built. Stages are built one at a time, not in parallel sessions. FR-8.6 needs nothing more. A new beta follows stage 1, to protect saved filters from older betas, and then stages 6, 16, 21, 26, 28 and 31. Until the stage 1 beta, don't save or delete filters in beta 7. **Filters** hold Dehaze, Vignette and Grain, but not Texture, sharpening or noise reduction (this changes the 2026-10-03 rule that left Vignette out). **Stage 1:** Whites −100 to 100, above Black Point; no Blacks slider. **Auto sets Whites** (Leah's choice; AC-35's list grows). The white-balance eyedropper averages 5 × 5, turns off after one click, and goes as far as it can on a strong cast, with no message. Folded Adjust Photo sections are remembered app-wide. Claude's choice (veto): Auto raises Whites only on a photo whose brightest parts fall short of white, and leaves it at 0 otherwise; clipped brights stay Highlights' job, as today. |
| 2026-10-27 | **Lightroom-style photo editing is the next aim** (Leah), an exception to "no more new features": editing one picture at a time like Lightroom, with saved settings to re-apply a look. "We have enough stuff to edit already." The ten items are in FR-9.7 and come from the feature comparison in `Docs/Feature-Gap-Analysis.md`. New controls live inside Adjust Photo so saved filters include them. Leah also approved, for after this (not yet written into the FRD): a layers round 2 (Select All Layers, isolate with Option-click on the eye, Align and Distribute, Stamp Visible, Layer Groups, Lock transparent pixels), then layer masks; re-editable text; optional stroke smoothing; and revisiting AI with Apple's built-in models only. Reopened for discussion: vector shapes. Dropped: batch work, PSD import, next/previous picture in a folder. |
| 2026-10-27 | **Adding from the layer menu** (Leah, both recommended): the right-click menu starts with New Layer and New Adjustment Layer ▸ (the same kinds as the Layer menu, with their icons), each added just above the right-clicked layer. |
| 2026-10-27 | **Review T** (Leah, all recommended): a canvas key the canvas hands back to the window (an effect's bar open) is no longer handed to it again, which looped until Colorbee crashed. Merge Layers keeps baking blend modes as Photoshop does (Leah, after "like Merge Down" turned out to change the look of half-transparent layers); FR-8.6 says the look holds for Normal layers only. Duplicate Layers copies a layer and its chosen "Only the layer below" adjustments as a pair of their own. A History click and Lift Subject leave just the active layer chosen. Esc during "Looking closer…" ends it at once. During a drag the tool's pointer stays, also under the sidebar. When Auto moved a slider, its whole name line shows "Set by Auto". Finding 8 (a quick Shift-click read as a plain click) didn't happen in Leah's hand test, so nothing changed. |
| 2026-10-27 | **Pointer over the sidebar** (Leah's bug): over the sidebar, or anything else floating on the canvas, the pointer is the normal arrow, with no brush or eraser outline and no pixel position in the status bar; the tool's pointer is only over the picture itself. |
| 2026-10-27 | **Rename with several layers** (Leah): the right-click menu's Rename… is greyed out while several layers are chosen, since a name belongs to one layer. Double-clicking a layer still renames it. |
| 2026-10-27 | **Right-click chooses the layer** (Leah's test): the right-click menu acted on the layer right-clicked, but the highlight stayed on the old one, so it looked as if the menu was for that one. Now a right-click on a layer that isn't chosen chooses it before the menu opens, so it turns blue first, as in Photoshop. The menu is an AppKit menu, built after the layer is chosen. |
| 2026-10-27 | **Choosing several layers** (Leah, all recommended; built the same day), an exception to "no more new features": Shift-click and ⌘-click choose several layers; Merge Down becomes Merge Layers (⇧⌘E) when several are chosen, the result taking the top chosen layer's place and name; hidden chosen layers are skipped and a locked one greys out the merge; a chosen adjustment layer is baked into the chosen layers below it; Delete, Duplicate, Hide/Show, Lock/Unlock, opacity, blend mode and dragging work on every chosen layer; a right-click menu on layers has Merge, Duplicate, Delete, Hide/Show, Lock/Unlock, Rename and Layer Properties. See FR-8.6. My choices (veto any): right-clicking a layer that isn't chosen chooses it alone first, as in Finder and Photoshop; the merged layer is Normal at 100%, so the picture looks the same; with several chosen, opacity and blend mode show the active layer's, and a change sets every chosen layer to it; Merge Layers needs at least two visible chosen layers; Delete is greyed out if it would leave no layer or a chosen layer is locked; Hide/Show and Lock/Unlock follow the active layer (if it's shown, Hide hides them all); a chosen layer's "Only the layer below" adjustments are baked in when it merges, as Merge Down does; after Duplicate the copies are the chosen layers. While building: the other chosen rows are tinted, the active one solid; Delete, Duplicate, Hide and Lock read "Layers" with several chosen; in the right-click menu, Layer Properties makes that layer the only chosen one, since its properties are at the top of the panel; locked chosen layers keep their opacity and blend mode; a chosen "Only the layer below" adjustment whose layer isn't merged stays as it is, and a merged layer's hidden ones go with it, as in Merge Down; New Layer, Merge and Delete, undo, redo and changing pages leave just the active layer chosen; dragging a layer that isn't chosen moves just it. |
| 2026-10-27 | **Tooltip delay** (Leah): tooltips in Colorbee appear after half a second instead of macOS's usual delay (about a second). Other apps are unchanged. |
| 2026-10-27 | **Easier sliders** (Leah, both recommended): in Adjust Photo and the Adjustments panel, dragging sideways anywhere on a slider's name line moves it, and a click there alone changes nothing; Adjust Photo's sliders are the "small" size, like the Adjustments panel's, rather than "mini". My choices (veto any): the name line moves the value as far as dragging the knob would (the whole range across the row's width), with no Shift speed-up; the pointer shows left-right arrows there; the Develop window, the effect bar and the tool options keep their sliders as they are. |
| 2026-10-27 | **Small subjects** (Leah, both recommended): a click that misses every subject looks closer around the click before beeping, so a small character in a game screenshot can be selected or lifted; Lift All and Return stay as they were. When nothing is found at all, the bar asks for a click instead of "No subject found". My choices (veto any): the closer look tries squares of half the image's shorter side, then 0.7 of the one before, down to about 200 px, largest first, and takes the first subject under the click; "Looking closer…" shows meanwhile and clicks wait; the bar says "even a small one"; a subject found this way is cut off where its square ends (rare, since the largest square that finds it wins). |
| 2026-10-27 | **Save and Export start in the picture's folder** (Leah, all recommended): Save, Save As, Export…, Export As presets and Export as PDF start in the folder of the file being worked on; for a picture that became a new project (or opened as a copy), the original picture's folder. Images that never came from a file (⌘N, Paste into New Image) keep the Mac's last-used folder. My choices (veto any): a developed RAW photo starts in the RAW file's folder; the folder is remembered across a relaunch for an unsaved project. See FR-12. |
| 2026-10-27 | **Tool keys right after opening** (Leah's bug): tool and canvas keys, ⇧S included, didn't work in a new window until the image was clicked. The image now takes the keyboard as soon as its window opens. Leah also chose: when a button or panel has taken the keyboard, a tool or canvas key nothing else uses still reaches the image (never while typing in a text box). |
| 2026-10-27 | **Every button shows its key** (Leah): the toolbar's Sidebar button says "Sidebar (⇧S)", and Clone Stamp in the Retouch menu says "Clone Stamp (S)". The size box, the Adjustments panel button, the page sidebar's New, Duplicate and Delete Page buttons and Before/After's "Last Saved" note now read their keys from Settings ▸ Shortcuts, so a changed key shows there too (the last four have no default key, so they look the same until one is given). |
| 2026-10-27 | **Sidebar shortcut** (Leah): ⇧S hides or shows the whole right sidebar, and so does a new View ▸ Sidebar (⌃⌘S, the usual Mac key), both doing what the toolbar's Sidebar button does. My choices (veto any): ⇧S is listed with the tool and canvas keys in Settings ▸ Shortcuts, so it doesn't work while typing text; View ▸ Sidebar has a checkmark when the sidebar is open and sits just above Layers; both are greyed out or do nothing while Adjust Photo is open, as the toolbar button already is. |
| 2026-10-24 | **Info panel** (Leah): a read-only fifth sidebar panel showing the file, image and photo details (FR-1.3), an exception to "no more new features". When the original had a GPS location it says **Location: Removed**. My choices (veto any): View ▸ Info is Cmd+Opt+I, as Finder's Show Inspector; its switcher button is an ⓘ; it describes the page being viewed; resolution shows only for pages opened from a PDF, since other pictures' DPI is only used by Export as PDF; the camera is shown once when its model already names the maker ("Canon EOS R5", not "Canon Canon EOS R5"); a project saved from a photo whose location was removed still says so. |
| 2026-10-22 | From code review round 7, session S (Leah): Match Tone may leave a faint tinted rim where the Clone Stamp copies see-through pixels onto solid ones (in effect erasing with it); kept as a known edge case, since fixing it would bring back the pause at the end of a stroke. Every save, autosave too, waits for a Match Tone still being worked out. |
| 2026-10-22 | **Help menu quick links** (Leah): every guide and reference page is listed in the Help menu under Colorbee Help, flat, under "Guides" and "Reference" headings, in the contents page's order. My choices (veto any): titles in menu title case (Getting Started); each item's hover text is its line from the contents page; each opens its page in Help Viewer at a `page-` anchor at its top; they have no shortcuts and aren't listed in Settings ▸ Shortcuts, since the Help menu is left out there (macOS manages it). |
| 2026-10-19 | **No more new features** (Leah): Colorbee's feature set is complete. The ideas kept for later are dropped: an AI fill model for Remove, searchable text in exported PDFs, and Split Page in Half. From here on, work is fixes, polish and betas. |
| 2026-10-19 | **Import from iPhone or iPad removed** (Leah): struck from the FRD (FR-11.7, AC-43, stage 11) and the help; the File menu item and the app code that received from the phone are deleted. Review N, finding 4 (an import during the Auto-Redact review) no longer applies. The core helpers it used stay, tested. |
| 2026-10-16 | Help phase 5 (Leah): the Retouch tool's options get a ? button too, since the Clone Stamp is the trickiest tool; Feather and Batch Redact don't (one slider each). My choices (veto any): the ? is at the bottom left of sheets and the Develop window, and at the bottom right of the Shortcuts and Export Presets tabs, after their other buttons; in the palette bar it's last, after the tip, and opens a new "Using the Clone Stamp" section when the Clone Stamp is chosen, or the Retouch section otherwise. Resize and Skew and Canvas Properties had no section of their own, so each gets a short one in Annotate an image, under Crop and size it. Each ? opens an anchor used only once in the book, since Help Viewer lists pages instead of jumping when one is repeated. |
| 2026-10-15 | Toolbar capsules (Leah): each toolbar group sits in a capsule a shade darker than the window (7% black; 10% white in dark mode), drawn by Colorbee instead of the Liquid Glass one, so the icons stand out. My choices (veto any): each group is now one toolbar item, so on a window too narrow for everything a whole group goes into the » menu rather than single buttons. |
| 2026-10-15 | Interface polish (Leah): **Size** shows only for tools that have a size, and **Outline/Fill** only for Shapes, instead of being dimmed. Hidden, they keep their space, so the tool icons never move. **4 custom colors** instead of 12, with fainter empty boxes; from the 12 saved before, the last 4 are kept (colors fill from the left, so those are usually the newest; the exact order wasn't saved), and a palette with more keeps its last 4. The **swap arrow** is a small grey curved arrow with a head at each end, running from the left over the top and down on the right, as Leah drew it. A **soft shadow** around the canvas shows its edge on the gray. My choices (veto any): the shadow reaches 10 points and falls 2 points down, at 22% black, in light and dark mode alike; it isn't drawn around the "before" side of Before/After. |
| 2026-10-15 | Menu order, from a review against Apple's standard menus and Photoshop, Preview, Pixelmator Pro and Acorn (Leah): **Redact** is its own menu, after Effects, with Auto-Redact… and the Batch Redact commands (Blur…, Pixelate…, Solid Fill with Color 1). Flip sits next to Rotate. Import from iPhone or iPad moves below Open. View groups the display aids (Pixel Grid, Rulers, Before/After) apart from the panels, and every on/off item there shows a checkmark instead of switching between Show and Hide; Adjustments Panel is now just Adjustments. Lift Subject to New Layer moves to the Layer menu. Effects and Adjustments are regrouped by kind (see FR-14.5). My choices (veto any): Batch Redact is a heading inside the Redact menu rather than a submenu, so its commands are one click away; shortcuts are kept, including changed ones. |
| 2026-10-13 | From code review round 5, sessions O and P (Leah): **Sample All Layers** (Clone Stamp, Remove, Spot Heal) reads the active layer and the layers below it, as shown, not layers or adjustments above it, so adjustments above apply once. **New Layer, Duplicate Layer and Lift Subject** with a layer selected that has "Only the layer below" adjustments put the new layer above those adjustments. **Merge Down** of such a layer bakes its "Only the layer below" adjustments in first, so the picture looks the same. **Delete Layer** of such a layer deletes its "Only the layer below" adjustments with it (one undo step brings all back). **Remove and Spot Heal keep a fixed width** and don't follow pressure: they mark an area to fill (FR-4.6 updated). |
| 2026-10-11 | Step Badge still being placed (Leah): Save, Export, Share, Print and Copy place it first, as they do a shape or text, so what's written is what's shown; autosave leaves it movable. Found by the new Editor tests. |
| 2026-10-11 | Straighten speed (Leah, 2026-10-10, confirmed 2026-10-11): when it's built, Straighten's preview is computed in the background so the app stays responsive, and rotation uses Apple's vImage, about 2.5× faster. vImage's pixels differ very slightly from today's (mean 0.4 of 255, not visible); the preview and the applied result still match each other. See `Docs/GPU-AUDIT.md`. Built 2026-10-11. Claude's choices (veto any): with Crop to fit, the photo's own edge pixels are repeated just past its edges, so the borders don't pick up a faint line; on fine, sharp texture (a brick wall) vImage keeps detail slightly crisper than before (mean difference about 3.5 of 255), on ordinary photos 0.3. Leah, 2026-10-11: crisper is better. |
| 2026-10-10 | Shift on the brushes and Eraser (Leah): holding Shift keeps the stroke on one horizontal or vertical line from where it started, like the Pencil, so the Marker can highlight a line of text. |
| 2026-10-10 | Soft selections (13d), my choices (veto any): Feather in the selection tools is applied when the drag ends (the outline already sits where pixels are half selected, so it looks the same while dragging) and isn't offered for the Magic Wand; Edit ▸ Feather… starts at 10 px, and like Invert Selection it changes the selection without adding an undo step; feathering is a Gaussian about the radius wide each way, and a selection reaching the canvas edge stays fully selected there; Subtract takes away in proportion; Copy and moving take a partly selected pixel's color with its alpha scaled, and Delete or moving leave the rest (on the background layer, mixed toward Color 2); Fill, Gradient, effects and adjustments mix by how selected each pixel is; Auto-Redact, Batch Redact and the Redact Brush harden the selection first; Select Subject keeps Vision's soft edge (the trial's cut at half is gone). |
| 2026-10-10 | Sidebar (Leah): turning off its last panel with the switcher closes the sidebar, as ⌘L already did; opening it with no panel chosen shows the Layers panel, so it's never an empty shell. A window saved with an open, empty sidebar opens with it closed. |
| 2026-10-10 | **Only the layer below** for adjustment layers (Leah: she cut a character out onto its own layer and wanted to saturate it without touching the background). My choices (veto any): a switch under the blend mode in the Layers panel, shown for adjustment layers; it clips to the nearest layer below that isn't itself a clipped adjustment, and has no effect if that's an ordinary adjustment layer; a hidden layer hides its clipped adjustments too; Merge Adjustment on a clipped one bakes it, with the visible clipped ones beneath it, into that layer; a floating selection on that layer shows its clipped adjustments on screen but not in a copy made while it's floating (it's placed first for exports anyway). |
| 2026-10-10 | Remove Red-Eye (13c), my choices (veto any): only clearly red pixels change (red at least about 1.8 times the other channels; skin and brown irises never are), their red brought down to the other channels, fading in at the pupil's edge; each eye is searched in a circle a little larger than the iris around the pupil Vision finds; "Finding eyes…" shows while it looks; if Vision finds no face, it says "No eyes found. Select the red pupils and try again."; it's in the Adjustments menu after Posterize. |
| 2026-10-10 | Clone Stamp and local brushes (13c), my choices (veto any): one Strength (50%) and one Hardness (50%) shared by the retouching brushes, and one tone Range for Lighten and Darken (Midtones); at full Strength, Lighten and Darken move a tone 60% of the way to white or black, weighted by the Range; Saturate is 1.8 times the color, Desaturate fully gray (Strength mixes); Blur and Sharpen work on a 5 × 5 neighborhood, the same at any brush size (more strokes do more); Smudge spaces its dabs at 8% of its size and, at full Strength, keeps nearly all of its color; the Clone Stamp copies the pixels as they were before the stroke, so copying near where you paint never smears, and its Strength is always full; sizes: Clone Stamp and Smudge 30 px (presets 10–80), the others 40 px (presets 10–160); S picks the Clone Stamp; painting before Option-clicking says "Option-click where to copy from first"; Match Tone works like Spot Heal's tone matching, when the stroke ends, in the same undo step; icons: a seal (Clone Stamp), sun, moon, half-full drop, half circle, haze, triangle and pointing finger. |
| 2026-10-10 | Retouch gallery and Spot Heal (13b), my choices (veto any): the gallery opens from one toolbar button after Brushes, showing the tool in use, with Remove and Spot Heal (13c adds the rest) and Sample All Layers; J selects it; each retouching tool keeps its own size (Remove 40 px, presets 10–160; Spot Heal 16 px, presets 6–40); Spot Heal looks only in a ring about half the spot's size around it, then evens out the tone: the differences at its edge, smoothed along the edge, spread across the spot, so the texture stays and the tone meets the surroundings; Sample All Layers is off by default and shared by the retouching tools; the undo steps are "Remove" and "Spot Heal". A Release speed check: a 400-pixel area in a 4000 × 4000 photo in under 0.4 s (0.17 s when set). |
| 2026-10-10 | Match Surroundings trial passed (Leah): Remove is for simple backgrounds, and the Clone Stamp is the tool for busy spots; its hint says so. Tried on Leah's own photo (an extinguisher and signs on posts): it smeared or went blocky; five standard improvements (more refining, weighted blending, rescoring matches, preferring nearby pieces, an unblended finish) and exemplar-based filling (Criminisi) didn't fix it reliably, so the engine stays as it was. **AI later:** an AI fill model would handle busy spots, at roughly 100–200 MB; it's left for later, in keeping with no AI for now. |
| 2026-10-10 | Match Surroundings trial (13b), built for Leah to judge on her own pictures. The engine is PatchMatch image completion (coarse to fine, 7 × 7 patches), searching only around the area (as far again as the area is big), repeatable, on all cores: about 0.05 s for a small object, about 1 s for a 720-pixel one. My choices (veto any): when everything touching the area is one flat color (within a few levels, as in screenshots; a photo's grain never is), it's filled with that color, blended across a soft gradient, because matching patches there carried in other lines of text; for the trial, Remove is a single toolbar button after Brushes, key J, size 1–300 px (presets 10, 20, 40, 80, 160; 40 by default), on the active layer only (Sample All Layers comes after the trial); progress shows as a ring in a capsule at the top of the canvas, "Filling… Esc stops"; if the image changes while it fills, the fill is dropped with a message. Known weak spot, as expected: an edge or band crossing a wide area can bend or blob. |
| 2026-10-10 | Redact Brush (13a), my choices (veto any): it paints where you paint and ignores any selection, so a redaction is never cut short; the painted area is hard-edged (every pixel whose center is under the brush); while painting it shows see-through red, with a round outline of the brush's size under the pointer; Solid Fill uses Color 1, or Color 2 with a right-drag, like the other brushes; Blur and Pixelate strength is a third of the brush's width (at least 6 px); Size presets 8, 16, 24 (default), 40 and 64 px, and [ ] change it by 4; the undo step is "Redact Brush"; the toolbar button (an eye with a slash) sits after Measure, before Step Badge. |
| 2026-10-10 | Step Badges (13a): a filled circle with a thin outline and a bold number in the other color (Leah). My choices (veto any): the number uses the system's bold font (the rounded one isn't reachable outside AppKit); the Size presets are 24, 32, 48, 64 and 96 px and [ ] change it by 4; letters run A…Z, then AA, AB…; the arrow is the circle's color and shows once the drag leaves the circle; Return places the badge, Delete or Esc removes it, ⌘Z removes it too ("Undo Step Badge"); each placed badge is its own undo step, "Step Badge"; the toolbar button is a ① after Measure. |
| 2026-10-10 | Copy Text (13a): confirmations are a short message at the bottom of the canvas that fades after 2 seconds, not an alert (Leah). My choices (veto any): it uses Apple Vision's document reader (macOS 26), which joins a paragraph's wrapped lines into one and reads forms row by row; "Reading text…" shows while it reads. |
| 2026-10-10 | Stage 13 review (Leah): **Erase to Background is struck**: on a busy background it copies nearby texture, which can carry other nearby text into a redaction. The redaction treatments stay Blur, Pixelate and Solid Fill. "No AI models" is for now, to keep Colorbee small, not a hard no. **13b starts with a trial build** of Match Surroundings, judged on Leah's test pictures. Open questions answered: the Retouch gallery goes next to Brushes, and the Redact Brush and Step Badge after Measure; Remove fills when you let go; Step Badge keeps drag-to-arrow. |
| 2026-10-10 | Retouching and annotation extras, stage 13 (Leah): **no AI models ship in Colorbee.** Object removal comes back into scope, replacing 2026-10-03's "Clean Up is out of scope", as the Remove tool, which fills only from the image's own pixels (Match Surroundings). Also in: Spot Heal, Clone Stamp, local Lighten, Darken, Saturate, Desaturate, Blur, Sharpen and Smudge brushes, Remove Red-Eye, soft-edged selections, the Redact Brush, Erase to Background, numbered Step Badges and Copy Text (FR-3.4, FR-4.6, FR-5.3, FR-9.5, FR-9.6, FR-10.4). Proposals (veto any): keys J Retouch, S Clone Stamp, K Redact Brush, N Step Badge, and Cmd+Opt+C for Copy Text; retouch and Redact Brush sizes up to 300 px; retouch tools ignore Symmetry and treat right-click like left-click; the Redact Brush defaults to Solid Fill and changes layers like Batch Redact; soft selections never soften a redaction; Remove and Spot Heal results are repeatable. |
| 2026-10-10 | Import from iPhone or iPad (stage 11), from Leah's trial scans: scans arrive as a Letter-size PDF with one JPEG per page (about 1,600 × 2,600 px); photos as a 1440 × 1920 JPEG in Display P3. Leah chose each scan's own picture, without the Letter page's white strips. My choices (veto any): the page sidebar's right-click menu doesn't get the item (macOS offers it only in AppKit menus, and that menu is SwiftUI); the undo step is named "Import" and undoing it shows the page you were on; a scan prints as large as fits on Letter, as the phone placed it; pages that aren't one JPEG are drawn like an opened PDF; a photo uses the phone's JPEG rather than the TIFF copy macOS also offers; importing is refused while Auto-Redact is redacting. |
| 2026-10-10 | Switching pages (L15), my choices (veto any): .colorproj layers are stored in pieces of about 4 MB, each compressed on its own and joined into one LZ4 stream, so every core can work on them. Older Colorbee versions still open the new files, and new ones open older files (a layer at a time, as before). A page from an older file is stored in pieces the next time it's parked. Files are 0.1% larger. While a page comes back, Colorbee still just waits, much more briefly (Leah). |
| 2026-10-10 | **Apply Adjustment is renamed Merge Adjustment** (Leah): the Adjustments panel's button is **Merge** and the Layer menu item **Merge Adjustment**, since it combines layers. **Merge Down** is unavailable on an adjustment layer (greyed out in the menu and the Layers panel), so "Down" always means the one layer below; this replaces the 2026-10-03 rule that Merge Down on an adjustment layer applied it. |
| 2026-10-09 | Leah's "Cant Copy" bug: **Apply Adjustment** (now Merge Adjustment) keeps the look everywhere. It merges the adjustment layer and every visible layer below it into one pixel layer, at the lowest of them, as one undo step; layers above are untouched. Before, it baked the adjustment into only the layer just below, so anything showing through from lower layers lost the adjustment. **Copy (⌘C) on an adjustment layer** copies what you see, like Copy Merged; on a pixel layer it still copies just that layer. My choices (veto any): hidden layers below stay as separate hidden layers (like Merge Visible); Apply is unavailable when the adjustment layer is hidden (it changes nothing) or when any visible layer it would merge is locked. Merge Down on an adjustment layer does the same as Apply (changed 2026-10-10: unavailable). |
| 2026-10-06 | Help (Leah): a standard Mac Help Book (Help ▸ Colorbee Help, Cmd+?, offline, found by the Help menu's search); task guides first, then a full reference; a few key screenshots, light mode only, retaken by a script; no "What's new" page (beta notes stay in Start Here.txt). See FR-14.6 and `Docs/HELP-PLAN.md`. (Veto any, Claude's choices: the contextual ? buttons go in the Auto-Redact sheet, Settings ▸ Shortcuts and Export Presets, Resize and Skew, Canvas Properties and the Develop window; the Menus and Keyboard shortcuts pages are generated from the app, so they can't drift.) |
| 2026-10-05 | Toolbar (Leah): Brushes and Shapes join the drawing tools' group, right after the Pencil, instead of a group of their own: they're all drawing tools. |
| 2026-10-05 | Palette bar (Leah): **Edit Colors…** is removed, since double-clicking Color 1 or Color 2 opens the same color picker. **Palettes** are hidden, not removed: too much for the bar's space; the code stays and one switch (`PaletteStore.isShown`) brings the menu back. Colorbee keeps using the palette that was active (Paint Classic). |
| 2026-10-05 | Review round 4 (Leah): Export as PDF converts pages with a non-standard color profile to Display P3, so no device or calibration name goes in (Display P3 and sRGB pages are kept as they are); after a redaction, the Clipboard History offer also covers copies made from the document. (Veto any, Claude's choices: an untitled document autosaves as a .colorproj, so nothing is lost on a relaunch, while the Save panel still starts on an image format; the History panel steps only the page shown, never a page change; Save, Export, Share, Print and Revert are greyed out behind any sheet or effect bar, and autosave waits while Auto-Redact is applying.) |
| 2026-10-05 | Scrubbing number fields (Leah): drag up or down on a small number field to change it, **down for bigger** (changed the same day from up: the fields are at the top of the window, so pulling down feels like more), Shift for 5× faster: the toolbar's Size, the Alpha percentage, the Fill, Magic Wand and Color Eraser tolerances, and the Text tool's font size. Size limits stay (Brush and outlines 50 px, Eraser 100 px). (Veto any, Claude's choices: one step per 3 points of movement; a press only becomes a drag after 3 points, so a click still puts the cursor in a field to type; the pointer is an up-down arrow over these fields; dragging past a limit stops there, and dragging back changes the value at once.) |
| 2026-10-05 | Remembered file formats (Leah): Save and Export… each remember their own last format, also after a relaunch. The Save panel starts on it for a new or untitled image (new images, pastes, developed RAW photos, copies of files Colorbee can't save back); a document with a file keeps its own format in Save As…; a layered or multi-page document still saves as .colorproj and doesn't change what's remembered. (Veto any, Claude's choice: Export… also remembers the JPEG/HEIC quality and the TIFF compression.) |
| 2026-10-05 | RAW photos, Claude's choices (veto any): **Highlights** goes from 0 down to −100 only, since macOS's highlight control can only bring bright areas down (Exposure or Curves brighten). Contrast is Colorbee's own, so it works for every file; Noise Reduction, Sharpness and Lens Correction are greyed out when macOS doesn't offer them for that camera or lens. Exposure is ±3 stops, Temperature 2000–12000 K, Tint ±150. Develop is its own window (not a sheet), so several photos can be developed side by side; it isn't brought back after a relaunch. The developed photo is titled after the file, and the RAW file goes into Open Recent. **Include camera details** remembers its last setting (off at first); ⌘S, Export As presets, Copy and Share never include camera details. |
| 2026-10-05 | RAW photos (Leah): use macOS's built-in RAW engine (CR3, ARW, NEF, RAF and more) rather than a third-party library; open in Display P3; a **Develop** window on every RAW open (Return opens with what's shown) with Exposure, Temperature, Tint, Highlights, Shadows, Contrast, Noise Reduction, Sharpness and Lens Correction, at RAW precision; develop only when opening; **Include camera details** in Export…, off at first, for any photo with them, kept in .colorproj; never location, serial numbers or owner name. Built now, as stage 12. See FR-11.8. |
| 2026-10-04 | Import from iPhone or iPad (Leah, all recommended; not built yet, for later): File ▸ Import from iPhone or iPad and the page sidebar's menu; scans and photos become new pages after the page being viewed (a new document if none is open); the phone's resolution, pixels and paper size are kept; Add Sketch stays; searchable text and splitting book spreads are later. See FR-11.7. |
| 2026-10-04 | Appearance setting (Leah): Settings has a new first tab, **General**, with Appearance (System, Light or Dark, as a segmented control; System is the default and follows macOS live). It applies at once everywhere, is remembered, and is set before the first window shows. The PDF resolution moved into General too; the PDFs tab is gone. (Veto any, Claude's choices: Settings now opens on General the first time, and anyone who last used the old PDFs tab lands on General.) |
| 2026-10-04 | Starting tool (Leah): every new or opened document starts with **Rectangle Select**, not the Pencil, so a first click doesn't draw on the image. |
| 2026-10-04 | Remove Earlier Versions and Undo History, with pages (Leah, fixing a gap from stage 10a): it clears the undo history of **every** page, forgets page adds, deletes and moves (so a deleted page can't come back), and makes Before/After's "As Opened" the current image on every page. |
| 2026-10-04 | Undoing Auto-Redact (Leah): all or nothing. ⌘Z undoes an Auto-Redact on every page at once, from whichever page is shown, and ⇧⌘Z redoes it on every page. After a later edit, ⌘Z undoes that edit first, then the whole Auto-Redact. If another page has changed since, ⌘Z on a page undoes just that page's part, so ⌘Z never gets stuck. |
| 2026-10-04 | Stage 10b (Leah): clicking an Auto-Redact item shows its page with the item in view; Export as PDF is lossless only; the PDF has no metadata at all (no title, author, app name or dates). Auto-Redact ignores the selection and always reads every page, whole: Batch Redact is the tool for chosen areas (changed the same day; it first read just a selection). Its summary says how many pages it read ("Read 3 pages. Found 2 items, all on page 1."), so finding items on fewer pages doesn't look like pages were skipped. |
| 2026-10-04 | Stage 10b choices (veto any): transparent areas come out white in an exported PDF, as PDF viewers show them. Export as PDF has no shortcut. The PDF resolution is a new **PDFs** tab in Settings (moved into General the same day). Auto-Redact reads the pages in order, showing "Reading page 2 of 3…"; Apply waits until every page is read, and Cancel is greyed out while it redacts. Items are numbered within each page. Clicking an item keeps the zoom and only scrolls if its box isn't already in view. If any page changed since it was read, or has a locked layer under a box, nothing is redacted on any page and the message names the page. |
| 2026-10-04 | Right-clicking a page thumbnail (Leah): shows that page first, so New, Duplicate and Delete Page in its menu act on the page clicked, as in Preview. |
| 2026-10-04 | Stage 10a choices (veto any): pages have their own **Page** menu, after Layer. Previous and Next Page are ⌥⌘↑ and ⌥⌘↓ (as in Preview); View ▸ Page Sidebar is ⌥⌘2. The sidebar only appears once a document has two or more pages, and hiding it is remembered with the window. Adding, deleting and moving pages can be undone with ⌘Z until the page shown is edited; after that ⌘Z undoes that page's edits. Before/After's "Last Saved" and Revert Layer compare with the page as it was at the last save. Opening a project shows the page that was shown when it was saved. Opening a PDF makes an untitled copy that saves as a .colorproj. |
| 2026-10-04 | Pages (Leah): the page sidebar is on the left; the PDF resolution is a setting (200 DPI by default); ⌘Z undoes the last change on the page being viewed, each page keeping its own edits; any document can have pages, so Colorbee can make PDFs from images; Auto-Redact on every page has one review list grouped by page. Multi-page TIFFs and animated GIFs open with every frame as a page, replacing the frame bar. See FR-11.6. (Veto any, Claude's choices: New Page is filled with Color 2; non-PDF pages export at 144 DPI; Batch Redact works on the page being viewed.) |
| 2026-10-04 | Flatten with hidden layers (Leah): asks "Discard hidden layers?", naming how many, with Flatten (default) and Cancel. Merge Visible doesn't ask, since it keeps hidden layers. |
| 2026-10-04 | Color Eraser switch (Leah): the Eraser's options have a Color Eraser switch, off by default. When on, a plain drag color-erases (Color 1 to Color 2, within the tolerance); a right-drag always does. Easier on a trackpad. |
| 2026-10-04 | Closing a window (Leah): a redaction not yet saved with ⌘S is saved, and the earlier-versions warning shown, before the window closes (⌘W, File ▸ Close, the close button), and on quitting, one window at a time. |
| 2026-10-04 | (veto any) Remove Earlier Versions and Undo History also makes Before/After's "As Opened" the image as it is then, since it would otherwise still show the unredacted original. A Batch Redact bar doesn't open if a locked layer has pixels under the selection; a message names the layer. |
| 2026-10-04 | AC-27 accepted (Leah): the rare whole-image steps a little over a second at 8000×8000 (13 in about 6,500 in the fifth soak) are acceptable. |
| 2026-10-04 | Batch Redact (Leah): Blur… and Pixelate… preview every layer under the selection, exactly as Apply changes them. This replaces the earlier "preview on the active layer" choice. (To build after the fourth soak.) |
| 2026-10-04 | After a redaction (Leah): Remove in the Clipboard History offer also clears the Mac clipboard when it still holds that same image; anything copied since is left alone. Copies in other clipboard apps, or passed on by Universal Clipboard, are out of reach. (To build after the fourth soak.) |
| 2026-10-04 | Redaction and saving (Leah): choosing Remove Earlier Versions after saving a redaction also clears the undo history up to that save, so the redaction can't be undone and then autosaved back. The button and message say so. (To build after the fourth soak.) |
| 2026-10-04 | PDF documents, stage 10 (Leah): pages are their own thing, not layers, with their own sidebar of thumbnails; each page has its own layers. All pages open at once, at 200 DPI by default (150 or 300 on request). Pages can be added, deleted and reordered. Auto-Redact on all pages is part of the first version. Export as PDF is pixels only. See FR-11.6. |
| 2026-10-04 | AC-27 (Leah): Flatten and Merge hand the writing-out of replaced layers to the background, so the step doesn't wait for it. The soak's Brush step is timed per mouse move (moves at most 24 px apart) and for placing the stroke, as a person experiences it, rather than as one 30-jump stroke. |
| 2026-10-04 | From reviews H, I and J (Leah): after saving a redaction, Colorbee warns that earlier versions still show it and offers to remove them; after a redaction, it offers to remove the Clipboard History items the image was pasted from (Remove is the default), and items can be removed one by one. Batch Redact covers every layer, like Auto-Redact; Auto-Redact checks visible layers only and says so. Fill and the Magic Wand have Sample All Layers. The Color Eraser has a tolerance (0% by default). Files Colorbee can't save back without loss (animated GIFs, multi-page TIFFs, 16-bit images, WebP) open as untitled copies; GIFs and TIFFs show a frame bar with Choose Frame…. Toolbar tools are greyed out while an effect's bar is open. |
| 2026-10-04 | From reviews H, I and J (veto any): Batch Redact ▸ Blur… and Pixelate… preview on the active layer and apply to every layer. Choosing a frame after changing one asks first. Close, Minimize, Zoom and Full Screen work while an effect's bar is open; menus wait behind Resize and Skew and Canvas Properties; while text is typed, menu shortcuts give way to the text box. Tool keys (Space, the arrows, Return, Esc, Delete) and ⌘-arrows can't be assigned. A custom palette named Paint Classic is saved as "Paint Classic 2". Option-click with the Eyedropper picks the color as shown. A Shift marquee is square in pixels; a selection handle drag stops at 30,000 px a side and 256 megapixels. |
| 2026-10-04 | From review G (veto any): Undo on Active Layer is greyed out while a paste, shape or text on the layer isn't placed yet (press Return first). Revert Layer is unavailable while a flip or rotation made since the save is in effect, as it already was after a size change. Layers are reordered by dragging their row; it lands where it's let go. |
| 2026-10-04 | From review F (Leah): a shape, text or paste that isn't placed yet looks exactly as it will once placed, including its layer's blend mode and opacity; placing changes nothing on screen. While typing, the canvas draws the text itself; the text box shows the caret and selection. |
| 2026-10-04 | Auto-Redact, from review E (Leah): it redacts each item's box on **every layer** with pixels under it, as one step, whichever layer is active. If a **locked** layer has pixels under a box, nothing is redacted and the sheet names the layer to unlock. With a **selection**, every item that touches it is listed and redacted **whole**. Blur and Pixelate are as strong as each item's own text needs. While the sheet is open, menus are greyed out, and Apply refuses if the image changed since it was read. |
| 2026-10-04 | Commands that change the active layer's pixels (effects, adjustments, Cut, Delete, Paste, Remove Background) are **greyed out** on a locked or adjustment layer, instead of beeping (Leah). Whole-image commands (crop, resize, rotate, straighten, perspective) stay available. |
| 2026-10-04 | From the local sweeps after review round 1 (veto any): images over 30,000 px a side or 256 megapixels don't open, paste or drop ("too large to edit"), the same limits as Resize and new canvases. Export presets never make an image over 30,000 px a side. A custom crop ratio runs up to 1000:1. Cut on a locked layer beeps without copying anything. |
| 2026-10-03 | From cloud reviews B, C and D (veto any): **Perspective Correction** with crossed or folded corners beeps on Return and stays open so the corners can be fixed. If the image changes while **Select Subject, Remove Background or Lift Subject** is searching (a step, an undo, a stroke in progress), nothing is applied and a message asks to try again; the three commands are greyed out while a search runs and on an adjustment layer. **Straighten, Perspective Correction and Crop…** open on a locked or adjustment layer, since they apply to every layer. **Levels, Curves and Posterize adjustment layers** now look on screen exactly as they export (the "about one level" difference above remains for Sepia and Adjust Photo). **Filters:** renaming the chosen filter keeps it chosen; deleting it takes it off the image (None). While **Adjust Photo** is open, the toolbar's Sidebar and Layers buttons are disabled, since its sliders are in the sidebar. **Curves:** a click on a point no longer moves it (points move by how far they're dragged), and a click at an existing point's x grabs that point instead of adding a second one. VoiceOver reads each slider's name and value, and the curve's points, but moving curve points still needs a pointer. |
| 2026-10-03 | From the spec review (veto any): Ctrl-click on the canvas opens a context menu with the everyday selection and clipboard commands (right-click still paints with Color 2). Export… offers TIFF compression, LZW (default) or None. Settings → Export Presets has a Scaling choice (Automatic, Sharp pixels, Smooth) for Export As presets. Settings reopens on the tab last used. FR-11.2 and AC-11 now say presets never enlarge, matching Leah's earlier decision. |
| 2026-10-03 | Brightness/Contrast removed from the Adjustments menu and the adjustment-layer lists (Leah): Adjust Photo's Brightness (which lifts midtones without clipping) and Contrast replace it. Older projects with a Brightness/Contrast layer needn't keep working; they still open, but the layer has no settings. |
| 2026-10-03 | The Adjustments panel no longer has a grid of buttons for adding adjustment layers (Leah): it repeated the Layers panel's Adjustment ▾ menu. With no adjustment layer selected, it says how to add one. |
| 2026-10-03 | Polish choices (veto any): **effect previews** are worked out in the background from a copy of the layer taken when the bar opens, so sliders stay smooth on large images; while one preview is being worked out, only the newest settings are done next, and Apply always commits exactly the settings shown. Drop Shadow, Border and Straighten previews are still worked out on the spot (they change the canvas's size). **Copy, Cut and Copy Merged** put the image on the clipboard at once and make the PNG in the background; an app that pastes in that moment waits for it. Copy Merged now joins Clipboard History like Copy. |
| 2026-10-03 | Fixes from Leah's stage 9 testing (veto any): after **Save as Filter…** the panel switches to the new filter at 100% and zeroes the color and tone sliders it absorbed (detail sliders stay), so the image looks the same and the look isn't applied twice. **Effects ▸ Spotlight…** is greyed out until something is selected, instead of beeping. |
| 2026-10-03 | Stage 9d–9e behavior choices (veto any): **Straighten** turns clockwise for positive angles, in 0.1° steps; Crop to Fit trims to the largest same-shaped rectangle with no empty corners (a pixel inside the exact fit); a line drawn on the turned preview adds its tilt to the turn already there and levels it, or makes it upright if it's closer to vertical; its preview is a real step with a grid over the image. **Perspective Correction** starts with its corners 6% in from the image's; the result is as wide as the longer of the top and bottom edges and as tall as the longer side; the corners are the preview (the image isn't warped until Apply). **Crop…** starts from the selection's box, or the whole image; dragging outside the box draws a new one; the outside is shaded and a thirds grid shows while dragging; size presets are Link preview 1200 × 630, Square post 1080 × 1080, Portrait post 1080 × 1350, Story 1080 × 1920, HD 1920 × 1080 and Banner 1500 × 500, and resize smoothly to exactly that size; Swap turns portrait to landscape. All three apply to every layer and clear the selection. **Subjects:** Image ▸ Remove Background and Lift Subject to New Layer, Edit ▸ Select Subject; they look at the active layer only; with several subjects a bar asks for a click on one (Return takes all, a click on the background beeps); "No subject found" explains that screenshots and text have none. |
| 2026-10-03 | Stage 9a–9c behavior choices (veto any): **Levels** works on red, green and blue together; Midtones 0.10–9.99 (above 1 lightens); Auto (and Auto Contrast) maps the darkest and lightest channel values of the visible pixels to black and white; the histogram uses a square-root scale. An **Auto Contrast** adjustment layer is a Levels layer set from the layers below when it's added; it doesn't update later. **Curves**: a smooth curve that never overshoots; each color's curve applies before the RGB curve; click adds a point, drag moves it, double-click or drag it off the graph removes it. **Defaults**: Sepia 100%, Posterize 4 levels, Add Noise 20% color (grain fixed to each pixel, so the preview matches), Motion Blur 0° and 20 px (angle counterclockwise from the right), Emboss 135° and depth 3, Vignette 50/50 (negative lightens; measured from the selection's box or the whole layer). **On screen**, color adjustment layers use a 33-point color table, so they can differ from the export by about one level. **Adjust Photo** has the sidebar to itself while open, grouped Light, Color, Detail; Control-click a slider to reset it; Auto marks the sliders it set with a wand; "As Adjustment Layer" turns the settings into a layer. Filters sit in the panel as chips with Intensity; Save as Filter keeps the filter plus the color and tone sliders (not Sharpness, Definition, Noise Reduction or Vignette); Save Filter from Layers keeps visible color and tone adjustment layers; Invert and Posterize steps apply in full at any intensity. Built-in filter recipes are Claude's. **Drop Shadow**: Across/Down offset, Blur, Opacity, black or Color 1; **Border**: width, Color 1 (default), Color 2, black or white; a solid rectangle gets square corners, other shapes a rounded outline. Both are drawn behind the object and grow the canvas only on the sides they need; their live preview is a real step redone as the sliders move (an autosave during the preview may include it). **Spotlight** needs a selection: Dim, Blur or Desaturate outside it, with an amount. |
| 2026-10-03 | Stage 8 behavior choices (veto any): **Saving and exporting** run in the background from a copy of the image, so the window stays usable (about 40 ms of pause at 8000 × 8000); the file holds the image as it was when the save started, and an export error appears when the export finishes. **Copy** (⌘C) of a very large image still pauses for about a second, because macOS needs the PNG at once; left for polish. **History** counts layers that only undo can bring back (merged-away, flattened or deleted layers) against its memory budget and writes them to disk like older steps; rotations and flips are undone by turning back, so they take no memory. **Time limits** live in `make perf` (Release only), set at about twice the measured time; the 8000 × 8000 soak test uses up to five layers, since with many more full-size layers, steps that read every layer (Flatten, or undoing one) take over a second at the Mac's memory speed. **VoiceOver:** the canvas reads its size, layer count and tool; swatches and color wells read a color name and hex value; the wells have a Choose Color action and layer rows have Make Active and Rename. **Beta:** version 0.9.0, a zip of the signed and notarized app with a Start Here note; testers send feedback and crash reports to Leah directly. **Memory (NFR-3),** measured in Release: 63–75 MB idle with a 1920 × 1920 image; 536 MB idle at 8000 × 8000 (the image plus its As Opened copy for Before/After), about 780 MB after saving (plus the Last Saved copy). |
| 2026-10-03 | The beta build for Leah's friend is signed with a Developer ID and notarized (Leah), using her existing Apple Developer account. Signing details stay out of the public repo. Replaces "no distribution" from 2026-09-30 for this one tester. |
| 2026-10-03 | Stage 9 additions (Leah): an **Adjust Photo** panel with the iPhone Photos sliders (Exposure, Brilliance, Highlights, Shadows, Contrast, Brightness, Black Point, Saturation, Vibrance, Warmth, Tint, Sharpness, Definition, Noise Reduction, Vignette), on the selection or active layer, live, one undo step, also as an adjustment layer; White Balance and Vibrance move into it from the Adjustments menu. **Auto** sets Exposure, Brilliance, Highlights, Shadows, Contrast, White Balance and Vibrance and shows what it moved. **Filters:** nine built in (Vivid, Dramatic, each with Warm and Cool, Mono, Silvertone, Noir) with intensity; custom filters from the sliders or from a stack of adjustment layers; managed like palettes, stored in Application Support, shared as .colorbeefilter; color and tone only. **Subject** via on-device Vision: Remove Background (soft edges, or onto a new layer), Select Subject (hard edges for now), click to pick one of several, "No subject found". **Clean Up** is out of scope. |
| 2026-10-03 | Vignette stays in both places (Leah): Effects ▸ Vignette, with its size and lighten options, and the Adjust Photo panel's Vignette slider. |
| 2026-10-03 | Stage 9 crop and perspective details are Claude's proposal (veto any): Image ▸ Crop… is a crop box with aspect presets (Free, Original, Square, 4:3, 3:2, 16:9, 9:16, custom W:H, orientation swap) and pixel-size presets (e.g. 1200 × 630), a rule-of-thirds grid while dragging, Return/Esc, every layer, one undo step. Perspective Correction… sits next to Straighten: drag four corners onto the shape that should be a rectangle. |
| 2026-10-03 | Shortcut Import/Export stays (Leah): a friend who uses editing tools will try Colorbee once it's beta-ready, so sharing shortcut sets is useful. |
| 2026-10-03 | Export presets stay as they are (Leah): a preset is either a width (the height follows) or a square to fit within; no height or W × H box option. Presets never crop, stretch or enlarge. |
| 2026-10-03 | Stage 7c behavior choices (veto any): Settings ▸ Shortcuts is the first tab. The Mac's own app and window commands (About, Settings, Hide, Hide Others, Show All, Quit, Close, Minimize, Zoom, Bring All to Front, Enter Full Screen) are listed with a padlock and can't be changed. Canvas keys are grouped as "Tools and Canvas Keys"; Space (pan), the arrows, Return, Esc and Delete stay fixed. Items in submenus are listed as "Rotate ▸ 90° Clockwise" and so on; Batch Redact's Blur and Pixelate share their shortcuts with the Effects menu items they open. A command whose shortcut macOS takes first on this Mac shows an orange warning. Globe (Fn) shortcuts are refused. Resetting a command whose default another command has since taken leaves it without one. Importing skips commands that no longer exist and shortcuts reserved on this Mac. macOS's screenshot shortcuts ⇧⌘3/4/5 stay blocked even when switched off in System Settings. |
| 2026-10-03 | Auto-Redact boxes (veto): never smaller than what the text recognizer reports for a match, so nothing secret shows. The extra margin stops partway into a space between words, so the neighboring word's letters stay whole; where there's no space ("key=sk_live…", "4242,"), the full margin stays and may cover a sliver of the punctuation. |
| 2026-10-03 | Screenshot folder watching removed (Leah): editors don't do it, it needed folder access and ran in the background. Screenshots come in through the clipboard and Paste into New Image instead (FR-14.4, AC-25 rewritten). Replaces the 2026-09-30 screenshot decision. |
| 2026-10-03 | Stage 7b behavior choices (veto any): **Palettes** live in the palette bar's palette menu. Switching palettes replaces the 28 swatches and the 12 custom colors with the palette's. Paint Classic is built in and can't be renamed or deleted; an imported palette whose name is taken gets a number. `.colorpalette` files are JSON. **Text styles** are in the text tool's Styles menu; a style keeps the font, size, formatting, background and both colors; applying one sets Color 1, and Color 2 only when the style has an opaque background. **Settings** (⌘,) has Export Presets (each a width or a square to fit; add, remove, reset); Export As ends with Edit Presets…. **Open in Colorbee** is a Services item for images and projects; macOS may need it switched on once in System Settings ▸ Keyboard ▸ Keyboard Shortcuts ▸ Services. **Auto-Redact** badges sit at each match's top-right corner, orange when it will be redacted and gray when kept. |
| 2026-10-03 | Paste into New Image moves to the File menu under New (Leah). A paste kept at its own size lands at the canvas's top-left, and pixels past the canvas edge aren't shown; drag it to choose what shows (Leah). Its outline and handles still show the full size. |
| 2026-10-03 | Stage 7a behavior choices (veto any): **Canvas:** resizing (edge handles or Canvas Properties) keeps the image at the top-left and clears the selection; new area is Color 2 on a solid background, transparent elsewhere. Turning on a transparent background changes what erasing and new area leave, not existing pixels; it and the resize are separate undo steps. Dragging an edge handle shows the new size as a dashed outline and in the status bar. **Big pastes:** a paste larger than the canvas asks Enlarge Canvas or Keep Canvas Size; enlarging grows the canvas to fit and puts the paste at the top-left. **Clipboard History** keeps the last 10 images copied, cut or pasted (Paste into New Image and drops too), newest first; the same image again moves to the top. It's stored in Application Support. **History panel:** an "Opened" row, then every step with a small picture of the image after it (Blur and Sharpen adjustments aren't shown in these pictures). **Drag and drop:** an image dropped on the canvas becomes a floating selection centered where it landed; dropped on the gray around the canvas, it opens as a new document. **Desktop picture:** set on every screen, from a PNG copy kept in Application Support. **Print** scales the image to fit the page, centered. **Share** sends a PNG of the combined image. The sidebar switcher now has Layers, Adjustments, History and Clipboard History. View ▸ Hide Status Bar and Show Rulers (⌘R). |
| 2026-10-03 | Saving layered images (Leah): once an image has more than one layer or an adjustment layer, it saves as a .colorproj. An opened PNG/JPEG/etc. is left untouched and the next save asks where to put the project; autosave never flattens layers. Flat copies come from Export. A new image saves as PNG by default, or .colorproj if it has layers by its first save. |
| 2026-10-03 | Stage 6b behavior choices (veto any): **Adjustment layers** start neutral, except Gaussian Blur (8 px) and Sharpen (60%) so adding one shows its effect. They're added from Layer ▸ New Adjustment Layer ▸, the same submenu at the bottom of the Adjustments menu, the Layers panel's Adjustment ▾ menu, or the Adjustments panel. The Adjustments panel has the sliders, Preview (the layer's eye), Reset and Apply. Painting tools refuse an adjustment layer (it has no pixels). Merge Down on an adjustment layer is Apply Adjustment; pixels can't be merged into an adjustment layer. An adjustment layer's blend mode mixes the adjusted image with what's below, and its opacity fades it in. On screen, Blur and Sharpen near the canvas edges stay opaque, as in exports. **Sidebar:** a switcher at the top shows or hides the Layers and Adjustments panels; ⌘L and the toolbar's Layers button toggle the Layers panel; the new Sidebar button toggles the whole sidebar. A project opened with several layers shows the sidebar. **Undo on Active Layer** becomes a step of its own ("Undo Pencil"), so ⌘Z brings the change back. It also takes back a settings change (opacity, blend mode…) made only to that layer. It's unavailable past a whole-canvas change, a step that also changed another layer, or when another layer's settings changed since (it can't tell those apart). **Revert Layer** restores pixels only (not opacity or blend mode), to the last explicit save or as opened; it's unavailable on adjustment layers, locked layers, layers added since, and after the canvas size changed. **.colorproj** is one file: a JSON manifest and LZ4-compressed exact pixels, with the color profile; a floating selection is saved where it sits; undo history isn't stored in the file. New empty layers take no memory until painted on. |
| 2026-10-03 | Stage 6a behavior choices (veto any): **Panel:** the sidebar floats over the gray surround and opens with ⌘L, the toolbar's Layers button or New Layer; it holds only the Layers panel until other panels exist, so the separate Sidebar button comes with them. Drag a row onto another to reorder; double-click to rename. Layer Properties… opens the panel, where the name, blend mode and opacity live. **Layers:** new layers go just above the active one as "Layer N"; a duplicate is "Name copy"; after Delete the layer below becomes active. Merge Down keeps the lower layer's name and settings, and merges the upper layer even if it's hidden. Merge Visible merges into the lowest visible layer (Normal, 100%); hidden layers stay. Flatten drops hidden layers. Showing, hiding, locking, renaming, blend mode and opacity are each undo steps; one opacity drag is one step. **Lock:** painting tools, fills, effects, pasting and moving selected pixels beep and show a 'not allowed' pointer; drawing a selection outline still works. Merge Down, Merge Visible and Flatten refuse when a layer they'd change is locked. Rotating, flipping, cropping and resizing the whole image still apply to every layer, locked or not. **Background:** erasing leaves Color 2 only on the original Background while it's at the bottom of a solid image; anywhere else it leaves transparency. **Display:** layers composite off screen first, so blend modes mix only with the layers below, never the checkerboard; the screen and exports use the same W3C blend math. |
| 2026-10-03 | Stage 5c behavior choices (veto any): the toolbar is the real macOS window toolbar, so its groups get Liquid Glass; on a narrow window, items that don't fit go into its » menu. The active tool's own settings (tolerance, gradient type, text formatting and so on) sit at the right end of the palette bar, since the mockups have no other place for them. A swatch click keeps the well's Alpha. The Size presets are 1–5 px for brushes and shapes and 4, 6, 8, 10, 20 px for the Eraser; Pencil, Text and the other tools dim the Size control. Outline/Fill dims outside the Shapes tool. Edit Colors… changes the ringed well; a color chosen there joins the custom colors when the picker closes. The Eyedropper's settings offer Add Color 1 to Custom Colors. Magnifier: click zooms in, right-click or Option-click zooms out. The zoom slider is logarithmic. The Layers and Sidebar toolbar buttons arrive with stage 6. New windows open at the mockups' 1512 × 982. |
| 2026-10-03 | Color wells move from the toolbar to the left end of the palette bar, and double-clicking an empty custom slot opens the color picker for that slot (Leah). |
| 2026-10-03 | The canvas size isn't shown under the window title (veto): macOS doesn't display a subtitle on document windows and puts its own "— Edited" there. The size stays in the status bar. |
| 2026-10-03 | No Paste/Cut/Copy buttons in the toolbar (Leah): they only repeated ⌘V/⌘X/⌘C and the Edit menu, and the room is needed for the stage 6 panel toggles. The Paint Classic palette menu stays, ready for palettes in stage 7. |
| 2026-10-02 | Text box handles (FR-6.1, reported missing by Leah). Behavior choices (veto any): the open text box has eight handles on its border, like a selection. Dragging the border moves it. Side handles set the width the text wraps at (so a click-to-type box starts wrapping once you drag a side); top and bottom handles set the box's height, which still grows if the text needs more. After a move or resize the cursor stays in the text, so you can keep typing. |
| 2026-10-02 | Trackpad pressure needs macOS's Force Click and haptic feedback setting on; with it off, the trackpad draws at full size like a mouse. |
| 2026-10-02 | Stage 5b behavior choices (veto any): **Pressure:** the lightest touch draws at a quarter of the brush size; a mouse or a tap-to-click reports no pressure and draws full size; a Pressure switch in the brush options turns it off. Crayon and Natural Pencil also get stronger with pressure. **Brushes:** every brush keeps the strongest coverage per pixel, so a stroke crossing itself doesn't darken (as the Marker already did). Grain is fixed to the image, so strokes share one paper texture. Calligraphy nibs are 45° and a fifth of the size thick; Symmetry mirrors a `/` nib into `\`. The airbrush sprays 30 times a second while held. Oil tapers over 1.5× its size at both ends; the tail tapers when you let go. Watercolor is see-through with a darker rim and a ragged edge. **Shape styles:** a textured outline is drawn with the matching brush; an arrow's head stays solid; Oil fill streaks run horizontally; Marker is half strength. Textured previews draw in the background, so a large one can lag the pointer by a frame or two. **Resize and Skew:** a dialog (no live preview), starting from the Smooth/Sharp toolbar setting; positive horizontal skew leans the top right, positive vertical raises the right side; corners the skew exposes get Color 2, or transparency on a transparent image; results over 30,000 px a side or 256 megapixels are refused; the undo step is named Resize, Skew, or Resize and Skew. |
| 2026-10-02 | Mid-stroke changes (Leah): a stroke keeps the color and size it started with; changes apply to the next stroke, and the eraser outline shows the size in use until release. Selections stay outlined after switching to a drawing tool (unchanged). ⌘-scroll zooms around the pointer. |
| 2026-10-02 | Interrupting a selection drag (Leah): switching tools (or any other command) while a marquee or lasso is still being drawn cancels it, and any selection from before the drag stays. A move or resize already under way keeps what's been done. |
| 2026-10-02 | The mockup interface moves up from stage 7 to a new stage 5c, right after 5b (Leah): toolbar, palette bar and status bar. The sidebar comes with Layers in stage 6, since none of its panels exist before then. |
| 2026-10-02 | Stage 9 answers (Leah): the photo adjustments also come as adjustment layers; Drop Shadow and Border follow the object's shape (opaque pixels, or the selection's outline); add Straighten. Straighten details are Claude's proposal (veto any): ±45° in 0.1° steps with a grid, or draw a line along the horizon; Crop to Fit on by default; whole image only. |
| 2026-10-02 | Scope widened to minor photo editing (Leah). New FR-9.5 for a later stage 9: Levels, Auto Contrast, Curves, White Balance, Vibrance, Sepia, Posterize, Add Noise, Motion Blur, Emboss, Vignette, plus Drop Shadow, Border and Spotlight for polished screenshots. Menu placement and the settings listed are Claude's proposal (veto any); open questions are in §22. |
| 2026-09-30 | Minimum macOS 26. Personal use only, no distribution. |
| 2026-09-30 | Full feature scope. Build time is not a constraint. |
| 2026-09-30 | Resize/Skew = Cmd+E. Canvas Properties = Cmd+Opt+E. History panel = Cmd+Opt+H (Cmd+H stays the system Hide shortcut). |
| 2026-09-30 | Undo history is **not** cleared on save. |
| 2026-09-30 | X swaps Color 1 and Color 2. |
| 2026-09-30 | Screenshot capture works by watching the screenshot folder. Clipboard-only screenshots are not caught. |
| 2026-09-30 | The memory target is measured, not fixed at 60MB. Latency is measured from input event to frame shown. |
| 2026-09-30 | Autosave and restore follow the standard macOS model. The custom "Restore Draft?" prompt from v2.0 is removed. |
| 2026-09-30 | Redo is Cmd+Shift+Z only. Cmd+Y (a Windows convention) is removed. |
| 2026-09-30 | Auto-Redact reads text entirely on this Mac. |
| 2026-09-30 | Added Polygon as shape #23. The v1 list named only 22 shapes; Polygon is the missing one from Windows Paint. |
| 2026-09-30 | Export preset widths confirmed (FR-11.2). |
| 2026-09-30 | Merge Down = Cmd+Shift+E. |
| 2026-09-30 | Before/After offers both baselines: As Opened (default) and Last Saved. |
| 2026-09-30 | Added a keyboard shortcut editor (FR-15.3) that blocks every macOS-owned shortcut. |
| 2026-09-30 | Withdrew Cmd+Opt+H for the History panel: it's the system Hide Others shortcut. Replaced with Cmd+Y. |
| 2026-09-30 | The repo stays local only; no remote for now. |
| 2026-09-30 | Added drag-to-resize for selections and pasted images. **Exception to macOS conventions:** free stretch by default, Shift keeps proportions (Windows Paint behavior). |
| 2026-10-02 | Effect settings dock as a bar under the toolbar instead of a dimming sheet (Leah), so the live preview is fully visible. Behavior choices (veto any): while the bar is open the canvas is view-only and any drag pans; pinch, scroll and the zoom commands still work; the tools, editing menus, Save and Export are unavailable until Apply (Return) or Cancel (Esc). Saving in the background during a preview writes the image without the preview. |
| 2026-10-02 | Status-bar zoom (Leah): − and + around the percentage step through the same zoom levels as ⌘- and ⌘=; clicking the percentage lists 25%, 50%, 75% and 100% (this replaces the separate 100% button). |
| 2026-10-02 | Eraser sizes widened (Leah): every 2px from 2 to 20px, plus 30 and 40px (was 4, 6, 8, 10). |
| 2026-10-02 | Eraser pointer (veto any): over the canvas the eraser shows as a square outline of exactly the pixels it will erase, black on the edge and white just inside so it shows on any colors, and the normal pointer is hidden. Zoomed out, a small eraser's square is drawn at least 8 points wide so it stays visible (changed 2026-10-02: showing the crosshair below 6 points meant the default eraser never showed a square at fit-to-window zoom). |
| 2026-10-02 | Shift with the Pencil (veto any): the first clear movement (one pixel) picks horizontal or vertical, and that axis stays locked until the mouse is released, as in MS Paint. Moving back and forth slides along the same line instead of starting new ones. |
| 2026-10-01 | Stage 5a behavior choices (veto any): Textured outline and fill styles moved to 5b with the brushes they reuse. The shape picker is a menu of all 24 shapes for now; the mockup's grid popover comes with the UI work in stage 7. Rotate and Flip apply to the selection when there is one, otherwise to the whole image. Symmetry mirrors around the canvas's center lines. Gradients composite over the layer rather than replacing it. Brightness/Contrast, Hue/Saturation and Sharpen use dialogs with live preview; Invert and Desaturate apply immediately. Effects now keep a floating selection's outline selected, so they apply to that area rather than the whole image. |
| 2026-10-01 | Stage 4 behavior choices (veto any): Auto-Redact defaults to **Solid Fill** (most secure; the sheet says blurred or pixelated text can sometimes be reconstructed) and scales Blur/Pixelate strength to the size of the text found. Matches are outlined on the canvas and numbered in the list (the mockup also numbers them on the canvas; not done yet). "Last Saved" in Before/After means the last explicit save (⌘S or Save As), not background autosaves. Before/After is view-only; dragging moves the divider. The Square 1024 preset fits the longer side in 1024 px without cropping. Editing presets waits for the Settings window (stage 7). With the Magic Wand, Shift or Option always selects (so it can add or subtract inside a selection); a plain drag inside a selection moves it. |
| 2026-10-01 | Stage 3b behavior choices (veto any): Crop to Selection crops to the selection's bounding box, keeps every pixel inside it, and deselects. Resized selections are Smooth by default, with a Sharp-pixels option in the selection toolbar (the Resize/Skew dialog doesn't exist yet). Shapes are anti-aliased. Added **Arrow** (a line with an arrowhead) alongside Line for annotations; it's in addition to the 23 FR-5.1 shapes. Shape rotation (FR-5.1) moves to stage 5, with the rest of the shapes. ⌘Z or Esc on a shape that hasn't been placed discards it. Text size is in image pixels at 100% zoom. Clicking away from a text box places it; the next click starts a new one. |
| 2026-10-01 | WebP stays open-only (no libwebp dependency). |
| 2026-09-30 | Stage 3a behavior choices (veto any): new documents start with the Pencil (changed 2026-10-04: Rectangle Select). The Marker paints at half the chosen color's opacity. Fill replaces pixels (it doesn't blend). Blur radius is the Gaussian's spread in pixels. Pixelate blocks line up with the canvas grid. Blur and Pixelate treat each separate selected region on its own. WebP opens but can't be saved yet (macOS can't write it; see §22). |
| 2026-09-30 | Stage 2 behavior choices (veto any): drawing a marquee on its own isn't an undo step, as in Paint (moving, placing, deleting and pasting are). Placing a moved selection undoes together with the move. Return and Esc both place the selection and deselect. Delete on a marquee keeps the marquee. Switching to a non-selection tool places moved pixels and keeps the outline selected (changed 2026-10-01: deselecting broke Gradient and Fill inside a selection). Pasting switches to the rectangle select tool. Undo has no step limit; old steps are compressed to disk. |
| 2026-09-30 | Drawing latency accepted: NFR-2 now covers Colorbee's own processing (~5ms). The ~16ms macOS adds to put the window on screen is outside any app's control. |
| 2026-09-30 | Launch time of ~330–400ms accepted. NFR-1 relaxed from 300ms to a 500ms regression limit. |
| 2026-09-30 | Colorbee is a paint program first. Simple diagrams are in scope; mind-mapping and structured diagram features are out. |
| 2026-09-30 | UI mockups adopted as the visual reference (`Docs/Design/`). Where a mockup and the FRD disagree on behavior or shortcuts, the FRD wins. The mockup's Settings screen showed wrong default shortcuts; the FRD's are correct. |
| 2026-09-30 | Blend modes expanded from 8 to 17: the mockup's 16 plus Additive. |
| 2026-09-30 | Added from the mockups: 12 custom-color slots, layer lock, Merge Visible (Cmd+Opt+Shift+E), Hide/Show Layer command, Pixel Grid and Symmetry switches in the status bar. |
