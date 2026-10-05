# Colorbee — Functional Requirements Document

**Version:** 2.2.0 · **Date:** 2026-10-02 · **Owner:** Leah (PM)  
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
│ Menu bar: Colorbee File Edit View Image Layer Adjustments Effects Window Help │
├───────────────────────────────────────────────────────────────────────────────┤
│ Toolbar: Clipboard │ Selection │ Tools │ Brushes │ Shapes │ Size │ Outline/Fill │
│          Color 1/2 wells │ [Layers ▣]                                          │
│ Palette: 28 swatches │ Alpha slider │ Edit Colors…                              │
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
- **Tools:** Pencil, Fill Bucket, Text, Eraser, Eyedropper, Magnifier, Gradient, Measure.
- **Brushes:** a gallery of 9 brush types (FR-4.2).
- **Shapes:** a gallery of 23 shapes (FR-5.1).
- **Size:** presets of 1, 2, 3, 4 and 5px plus a custom value (1–50px for brushes).
- **Outline / Fill:** style pickers (FR-5.1).
- **Layers toggle:** shows or hides the Layers panel. It shows the layer count when there's more than one layer.

### FR-1.2 Palette bar (docked under the toolbar)
- **Color wells** at the left end: Color 1 and Color 2, with a ring showing which one a swatch click will set. Double-click a well to choose its color.
- 28 swatches in 2 rows of 14.
- **12 custom-color slots** (2 rows of 6) next to the swatches, for your own colors:
  - A color picked with Edit Colors… or the eyedropper's "Add to Custom Colors" goes into the next empty slot. When all are full, the oldest is replaced.
  - Left-click sets Color 1, right-click sets Color 2, exactly like the swatches. Ctrl-click → Remove clears a slot.
  - Double-click an empty slot to pick a color for it with the color picker; the color goes into that slot.
  - The custom colors are kept between launches and saved as part of a palette (FR-15.1).
- An Alpha slider (0–100%) for the active color.
- An **Edit Colors…** button that opens the system Color Panel (Display P3, hex, sliders, screen eyedropper).
- A palette menu: choose, save, import, export or reset palettes (FR-15.1).

### FR-1.3 Right sidebar
One collapsible sidebar holds these panels. Each panel can be shown or hidden on its own:
- **Layers** (FR-8)
- **History** (FR-13.2)
- **Clipboard History** (FR-10.2)
- **Adjustments** (FR-8.4)

### FR-1.4 Canvas
- Centered on a neutral gray surround that adapts to Light/Dark mode.
- Three resize handles: right edge, bottom edge, bottom-right corner. New area is filled with Color 2, or left transparent if the canvas has a transparent background.
- **Pan:** two-finger trackpad scroll, or hold Space and drag.
- **Zoom:** 12.5% to 3200%, centered on the pointer. Use pinch, ⌘-scroll, Cmd+= / Cmd+-, Cmd+0 for 100%, or the status-bar slider.
- **Rulers:** optional, in pixels (Cmd+R).
- **Pixel grid:** optional at 400% zoom and above (Cmd+'), drawn in a color that contrasts with the pixels underneath.

### FR-1.5 Status bar
- Pointer position as `X, Y px`, always whole pixels.
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

### FR-4.3 Eraser
- Square eraser. Sizes every 2px from 2 to 20px, plus 30 and 40px, or custom. **[** and **]** change the size.
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
- **Apply Adjustment** turns it into pixels on the layer below.

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
- Each of these also comes as an adjustment layer (FR-8.4), from "as Adjustment Layer" versions of the menu items.
- White Balance and Vibrance are sliders in the Adjust Photo panel, not separate menu items.

**Adjust Photo panel** (Adjustments ▸ Adjust Photo…)
- One docked panel with all the photo sliders, like the iPhone Photos editor: Exposure, Brilliance, Highlights, Shadows, Contrast, Brightness, Black Point, Saturation, Vibrance, Warmth, Tint, Sharpness, Definition, Noise Reduction, Vignette.
  - **Vibrance** boosts muted colors more than already-vivid ones, so skin tones don't go orange.
  - **Warmth** and **Tint** are the white balance: cooler to warmer, and green to magenta.
- Applies to the selection if there is one, otherwise the active layer. Live preview. One undo step.
- Also available as an adjustment layer, with every slider still editable.
- **Auto:** analyzes the photo and sets Exposure, Brilliance, Highlights, Shadows, Contrast, White Balance (Warmth and Tint) and Vibrance. The panel marks the sliders Auto moved, and any of them can be adjusted afterwards. One undo step together with the rest of the panel.

**Filters** (in the Adjust Photo panel)
- Built in: Vivid, Vivid Warm, Vivid Cool, Dramatic, Dramatic Warm, Dramatic Cool, Mono, Silvertone, Noir. Each has an intensity slider.
- A filter is a named recipe of the panel's color and tone slider values only. Filters never crop or straighten.
- Intensity scales every value (50% is half of each).
- **Save as Filter…** saves the current slider settings under a name.
- **Save Filter from Layers** turns a stack of adjustment layers into one filter.
- Rename, Delete, Import and Export work like palettes. Filters are stored in Application Support; a `.colorbeefilter` file is for sharing.
- Any filter can be applied as an adjustment layer.

**Subject (Apple Vision, on this Mac; nothing leaves it)**
- **Remove Background:** writes Vision's soft edges directly into transparency. Option: put the subject on a new layer instead of erasing in place.
- **Select Subject:** makes a selection from the subject. Its edges are hard for now, since selections are all-or-nothing; soft selections can come later.
- With several subjects, clicking one picks just that subject.
- Shows "No subject found" when Vision finds nothing (screenshots, text).
- **Clean Up** (removing an object and filling in the background) is out of scope.

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
- **Crop…** (next to Crop to Selection): a crop box with handles over the image.
  - Aspect presets: Free, Original, Square, 4:3, 3:2, 16:9, 9:16, and a custom W:H, with a button that swaps portrait and landscape.
  - Pixel-size presets, such as 1200 × 630 for link previews: the box keeps that shape, and the result is resized to exactly that size.
  - A rule-of-thirds grid shows while dragging.
  - Return applies, Esc cancels. Applies to every layer as one undo step.

---

## 13. FR-10 — Clipboard

### FR-10.1 Paste
- **Cmd+V** pastes the image as a floating selection at full resolution with its alpha. It's placed at the top-left of the visible area.
- If the pasted image is bigger than the canvas, Colorbee offers to enlarge the canvas (like Paint).
- **Paste into New Image:** Cmd+Shift+V.

### FR-10.2 Clipboard History
- A sidebar panel with thumbnails of the last 10 images that were copied or pasted.
- Clicking a thumbnail pastes it as a floating selection. The system clipboard is not changed.
- Hovering shows when it was captured and its size.
- A **Clear** button. The history is kept between launches.

### FR-10.3 Copy
- **Cmd+C** copies the selection, or the whole combined image if nothing is selected, as a PNG with transparency.
- **Cmd+X** cuts.
- **Copy Merged (Cmd+Shift+C)** copies the combined image of all visible layers inside the selection.

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
- Presets can be edited in Settings.

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

### FR-11.7 Import from iPhone or iPad (stage 11, planned)
Scan with the phone, finish on the Mac: book pages (open-source ones), forms to redact, quick photos. Uses macOS
Continuity Camera; details and reasoning in `Docs/Proposals/Import from iPhone.md`.

- **File ▸ Import from iPhone or iPad**, the system's submenu (devices, each with Take Photo, Scan Documents and
  Add Sketch), as in Preview. Also on the page sidebar's right-click menu.
- With a document open, what arrives is added as **new pages just after the page being viewed**, in the order
  scanned, showing the first; one undo step. With no document open, it becomes a new untitled document.
- Each page keeps the phone's own pixels (no resampling), paper size and color profile; a photo counts as 144 DPI.
  The phone decides the scan's resolution.
- Add Sketch stays in the menu.
- **Not in the first version:** searchable text in exported PDFs (later, as an opt-in that's off and refused on
  any redacted page) and splitting a two-page spread (later, "Split Page in Half").

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
| **File** | New (Cmd+N), Open (Cmd+O), Open Recent, Close (Cmd+W), Save (Cmd+S), Save As (Cmd+Shift+S), Duplicate, Revert To, Export… (Cmd+Opt+S), Export As ▸ presets, Share, Set as Desktop Picture, Page Setup, Print (Cmd+P) |
| **Edit** | Undo (Cmd+Z), Redo (Cmd+Shift+Z), Undo on Active Layer (Cmd+Opt+Z), Cut (Cmd+X), Copy (Cmd+C), Copy Merged (Cmd+Shift+C), Paste (Cmd+V), Paste into New Image (Cmd+Shift+V), Delete, Select All (Cmd+A), Deselect (Cmd+D), Invert Selection (Cmd+Shift+I) |
| **View** | Zoom In (Cmd+=), Zoom Out (Cmd+-), Actual Size (Cmd+0), Zoom to Fit (Cmd+9), Pixel Grid (Cmd+'), Rulers (Cmd+R), Status Bar, Layers (Cmd+L), History (Cmd+Y), Clipboard History (Cmd+Opt+V), Adjustments panel, Before/After (Cmd+Opt+B) |
| **Image** | Crop to Selection (Cmd+Shift+X), Resize/Skew (Cmd+E), Canvas Properties (Cmd+Opt+E), Rotate ▸, Flip ▸, Symmetry ▸ |
| **Layer** | New (Cmd+Shift+N), Duplicate (Cmd+J), Delete (Cmd+Delete), Merge Down (Cmd+Shift+E), Merge Visible (Cmd+Opt+Shift+E), Flatten, Hide/Show Layer (no default shortcut), Lock/Unlock Layer, New Adjustment Layer ▸, Revert Layer, Layer Properties |
| **Adjustments** | Invert Colors (Cmd+I), Hue/Saturation, Desaturate (Cmd+Shift+U), Adjust Photo…, Levels…, Auto Contrast, Curves…, Sepia…, Posterize… |
| **Effects** | Gaussian Blur…, Pixelate…, Sharpen…, Auto-Redact…, Batch Redact ▸ |
| **Window / Help** | Standard |

**Single-key shortcuts** (active only when you're not typing text): X swap colors, D default colors, [ and ] change size, Space (hold) pan. One key per tool: P pencil, B brush, E eraser, G fill, T text, I eyedropper, Z magnifier, M rectangle select, L lasso, W magic wand, U shapes, R measure.

Every shortcut above is a default. All of them can be changed in the shortcut editor (FR-15.3).

---

## 18. FR-15 — Presets and customization

### FR-15.1 Palettes
- Save the current 28 swatches and 12 custom colors as a named palette. Load, rename, delete, import or export palettes (`.colorpalette`). Reset to the classic palette.
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
11. **Import from iPhone or iPad (planned):** FR-11.7. A short trial build first, with Leah scanning on her iPhone, to see what arrives; then the rest.
12. **RAW photos:** FR-11.8. Develop window, RAW as another way in, camera details on export.

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
- [x] AC-18 Adjustment layers stay editable. Apply Adjustment turns them into pixels.
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
- [x] AC-35 Adjust Photo's Auto moves only the sliders it lists and shows which; the whole panel is one undo step and also works as an adjustment layer.
- [x] AC-36 A filter at 50% intensity gives the same result as its slider values halved. A saved filter survives a relaunch and round-trips through a .colorbeefilter file.
- [x] AC-37 Remove Background leaves soft edges in transparency; Select Subject picks only the clicked subject; an image with no subject says "No subject found" and changes nothing.
- [x] AC-38 Crop with a pixel-size preset produces exactly that size; Perspective Correction turns a photographed rectangle into a rectangle.

---

## 22. Open questions (for Leah)

None right now.

---

## 23. Decision log

| Date | Decision |
|---|---|
| 2026-10-05 | Scrubbing number fields (Leah): drag up or down on a small number field to change it, up for bigger, Shift for 5× faster: the toolbar's Size, the Alpha percentage, the Fill, Magic Wand and Color Eraser tolerances, and the Text tool's font size. Size limits stay (Brush and outlines 50 px, Eraser 100 px). (Veto any, Claude's choices: one step per 3 points of movement; a press only becomes a drag after 3 points, so a click still puts the cursor in a field to type; the pointer is an up-down arrow over these fields; dragging past a limit stops there, and dragging back changes the value at once.) |
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
