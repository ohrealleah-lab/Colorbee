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
- **Clipboard:** Paste, Cut, Copy.
- **Selection:** Rectangle, Ellipse, Free-Form (lasso), Magic Wand; a Transparent Selection toggle.
- **Tools:** Pencil, Fill Bucket, Text, Eraser, Eyedropper, Magnifier, Gradient, Measure.
- **Brushes:** a gallery of 9 brush types (FR-4.2).
- **Shapes:** a gallery of 23 shapes (FR-5.1).
- **Size:** presets of 1, 2, 3, 4 and 5px plus a custom value (1–50px for brushes).
- **Outline / Fill:** style pickers (FR-5.1).
- **Color wells:** Color 1 and Color 2, with a ring showing which one a swatch click will set.
- **Layers toggle:** shows or hides the Layers panel. It shows the layer count when there's more than one layer.

### FR-1.2 Palette bar (docked under the toolbar)
- 28 swatches in 2 rows of 14.
- **12 custom-color slots** (2 rows of 6) next to the swatches, for your own colors:
  - A color picked with Edit Colors… or the eyedropper's "Add to Custom Colors" goes into the next empty slot. When all are full, the oldest is replaced.
  - Left-click sets Color 1, right-click sets Color 2, exactly like the swatches. Ctrl-click → Remove clears a slot.
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
- **Zoom:** 12.5% to 3200%, centered on the pointer. Use pinch, Cmd+= / Cmd+-, Cmd+0 for 100%, or the status-bar slider.
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
- Types: Brightness/Contrast, Hue/Saturation/Lightness, Desaturate, Invert, Gaussian Blur, Sharpen.
- Stage 9 adds Levels, Curves, White Balance, Vibrance, Sepia and Posterize (FR-9.5). Auto Contrast as an adjustment layer is a Levels layer with its points set automatically.
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
- **Brightness/Contrast** (live preview)
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
- Works on the selection, or on the whole image if nothing is selected.
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
- **White Balance:** Temperature (cooler to warmer) and Tint (green to magenta) sliders.
- **Vibrance:** boosts muted colors more than already-vivid ones, so skin tones don't go orange.
- **Sepia:** a warm brown-tone version of the image, with an amount slider.
- **Posterize:** reduces each channel to 2–32 levels.
- Each of these also comes as an adjustment layer (FR-8.4), from "as Adjustment Layer" versions of the menu items.

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
| TIFF | ✓ | ✓ | No compression or LZW. |
| WebP | ✓ | — | Opens only: macOS can't write WebP, and no third-party encoder is used. |
| HEIC | ✓ | ✓ | |
| .colorproj | ✓ | ✓ | Native format with layers (FR-8.5). |

### FR-11.2 Export presets
- **File → Export As ▸** a preset exports a PNG scaled to a set width. The aspect ratio is kept, and the image is never made larger than its original size unless you allow it.
- Presets: Slack (760px), 1280px, 1920px, Mobile (750px), Square 1024.
- Resampling is chosen automatically: Nearest Neighbor for pixel-art-sized images, Smooth otherwise. You can override it.
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
- **Ctrl-click** opens the canvas context menu.
- Trackpad: two-finger pan, pinch to zoom (sharp nearest-neighbor during the gesture).
- **Pressure** from a Force Touch trackpad or a pen tablet (FR-4.2).

### FR-14.2 Display
- At 100%, one image pixel equals one screen point. Above 100%, pixels are drawn as sharp squares with no smoothing.
- Full Light and Dark mode for all interface elements. The image itself is never tinted.

### FR-14.3 Finder
- Colorbee is registered for every format in FR-11.1, so it appears in **Open With**.
- An **Open in Colorbee** item in the Finder right-click menu (Services / Quick Actions).

### FR-14.4 Screenshot capture
- **Settings → "Open new screenshots in Colorbee"** (off by default).
- When it's on, Colorbee watches the folder where macOS saves screenshots and opens each new screenshot as it appears.
- The first time, macOS asks for permission to access that folder.
- **Limitation:** screenshots sent only to the clipboard (Cmd+Ctrl+Shift+4) can't be caught automatically. Paste them with Cmd+V, and they appear in Clipboard History.

### FR-14.5 Menus and shortcuts

| Menu | Items |
|---|---|
| **File** | New (Cmd+N), Open (Cmd+O), Open Recent, Close (Cmd+W), Save (Cmd+S), Save As (Cmd+Shift+S), Duplicate, Revert To, Export… (Cmd+Opt+S), Export As ▸ presets, Share, Set as Desktop Picture, Page Setup, Print (Cmd+P) |
| **Edit** | Undo (Cmd+Z), Redo (Cmd+Shift+Z), Undo on Active Layer (Cmd+Opt+Z), Cut (Cmd+X), Copy (Cmd+C), Copy Merged (Cmd+Shift+C), Paste (Cmd+V), Paste into New Image (Cmd+Shift+V), Delete, Select All (Cmd+A), Deselect (Cmd+D), Invert Selection (Cmd+Shift+I) |
| **View** | Zoom In (Cmd+=), Zoom Out (Cmd+-), Actual Size (Cmd+0), Zoom to Fit (Cmd+9), Pixel Grid (Cmd+'), Rulers (Cmd+R), Status Bar, Layers (Cmd+L), History (Cmd+Y), Clipboard History (Cmd+Opt+V), Adjustments panel, Before/After (Cmd+Opt+B) |
| **Image** | Crop to Selection (Cmd+Shift+X), Resize/Skew (Cmd+E), Canvas Properties (Cmd+Opt+E), Rotate ▸, Flip ▸, Symmetry ▸ |
| **Layer** | New (Cmd+Shift+N), Duplicate (Cmd+J), Delete (Cmd+Delete), Merge Down (Cmd+Shift+E), Merge Visible (Cmd+Opt+Shift+E), Flatten, Hide/Show Layer (no default shortcut), Lock/Unlock Layer, New Adjustment Layer ▸, Revert Layer, Layer Properties |
| **Adjustments** | Invert Colors (Cmd+I), Brightness/Contrast, Hue/Saturation, Desaturate (Cmd+Shift+U) |
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
7. **Integration:** Clipboard History, History panel, palettes, text styles, shortcut editor, Finder, screenshot capture, share, print, desktop picture.
8. **Hardening:** performance, 8000×8000 soak tests, polish.
9. **Photo editing and presentation (later phase):** the FR-9.5 adjustments and effects, with their own performance and soak checks.

---

## 21. Acceptance criteria

- [ ] AC-1 Cold launch shows a drawable canvas on screen in under 500ms.
- [ ] AC-2 Left-click draws with Color 1 and right-click with Color 2 for Pencil, all brushes, Fill, Shapes and Gradient.
- [ ] AC-3 X swaps the colors. D resets them.
- [ ] AC-4 Right-drag with the Eraser changes only Color 1 pixels.
- [ ] AC-5 Magic Wand respects Tolerance and Contiguous.
- [ ] AC-6 Shift, Option and Shift+Option combine selections as FR-3.2 describes.
- [ ] AC-7 Shift-drag of a selection leaves the smear trail.
- [ ] AC-7a Dragging a pasted image's handle stretches it freely. Shift keeps the proportions. Shrinking and then enlarging again before committing looks identical to the original.
- [ ] AC-8 Blur, Pixelate and Fill affect only the selection. Batch redaction handles each separate region on its own, as one undo step.
- [ ] AC-9 Auto-Redact finds emails, phone numbers, card numbers and API keys in a test screenshot, entirely offline.
- [ ] AC-10 Before/After compares the current image with either "As Opened" or "Last Saved", and switching between them works.
- [ ] AC-11 Export presets produce the right width, keep the aspect ratio and never enlarge unless allowed.
- [ ] AC-12 Cmd+V paste keeps full resolution and alpha. Cmd+C puts a PNG with transparency on the system clipboard.
- [ ] AC-13 Clipboard History shows the last 10 images. Clicking one pastes it and leaves the system clipboard unchanged.
- [ ] AC-14 Pixel grid at 400% and above. Pixels stay sharp at every zoom level on Retina screens.
- [ ] AC-15 Every file format in FR-11.1 opens and saves again with no unexpected loss. Color profiles are kept.
- [ ] AC-16 .colorproj saves and reopens layers, opacity, blend modes, visibility and adjustment layers exactly.
- [ ] AC-17 Undo on Active Layer reverts only the active layer.
- [ ] AC-18 Adjustment layers stay editable. Apply Adjustment turns them into pixels.
- [ ] AC-19 Undo history survives a save.
- [ ] AC-20 Quit and relaunch brings back open documents, including untitled ones, with no prompt.
- [ ] AC-21 Symmetry mirrors strokes live in every mode.
- [ ] AC-22 Measure shows the distance, ΔX, ΔY and angle.
- [ ] AC-23 Pressure changes brush size on a Force Touch trackpad.
- [ ] AC-24 "Open in Colorbee" works from Finder.
- [ ] AC-25 With screenshot capture on, a new Cmd+Shift+4 screenshot opens in Colorbee.
- [ ] AC-26 Palettes and text styles are kept between launches.
- [ ] AC-27 8000×8000: draw, blur, undo 50 steps and export with no stall over 1s and no crash.
- [ ] AC-27a A locked layer rejects every pixel edit, move, merge and delete, and can still be hidden and reordered.
- [ ] AC-27b All 17 blend modes render the same on screen and in export.
- [ ] AC-27c Picking a color with Edit Colors… fills the next custom slot. The slots survive a relaunch.
- [ ] AC-28 The shortcut editor changes a command's shortcut, and the menus update immediately.
- [ ] AC-29 The shortcut editor blocks every macOS-owned shortcut (including ones customized in System Settings) and names the owner.
- [ ] AC-30 Assigning a shortcut already used in Colorbee offers Reassign or Cancel. Reset All brings back the defaults.
- [ ] AC-31 Auto Contrast (and Levels → Auto) makes the darkest pixel black and the lightest white, per the image, in one undo step.
- [ ] AC-32 Every FR-9.5 adjustment and effect previews live, applies only inside a selection when there is one, and undoes exactly.
- [ ] AC-33 Drop Shadow and Border grow the canvas to fit, follow a cutout's shape, and undo restores the original size.
- [ ] AC-34 Straighten levels a line drawn along a tilted horizon. With Crop to Fit on, no empty corners remain.

---

## 22. Open questions (for Leah)

None right now.

---

## 23. Decision log

| Date | Decision |
|---|---|
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
| 2026-09-30 | Stage 3a behavior choices (veto any): new documents start with the Pencil. The Marker paints at half the chosen color's opacity. Fill replaces pixels (it doesn't blend). Blur radius is the Gaussian's spread in pixels. Pixelate blocks line up with the canvas grid. Blur and Pixelate treat each separate selected region on its own. WebP opens but can't be saved yet (macOS can't write it; see §22). |
| 2026-09-30 | Stage 2 behavior choices (veto any): drawing a marquee on its own isn't an undo step, as in Paint (moving, placing, deleting and pasting are). Placing a moved selection undoes together with the move. Return and Esc both place the selection and deselect. Delete on a marquee keeps the marquee. Switching to a non-selection tool places moved pixels and keeps the outline selected (changed 2026-10-01: deselecting broke Gradient and Fill inside a selection). Pasting switches to the rectangle select tool. Undo has no step limit; old steps are compressed to disk. |
| 2026-09-30 | Drawing latency accepted: NFR-2 now covers Colorbee's own processing (~5ms). The ~16ms macOS adds to put the window on screen is outside any app's control. |
| 2026-09-30 | Launch time of ~330–400ms accepted. NFR-1 relaxed from 300ms to a 500ms regression limit. |
| 2026-09-30 | Colorbee is a paint program first. Simple diagrams are in scope; mind-mapping and structured diagram features are out. |
| 2026-09-30 | UI mockups adopted as the visual reference (`Docs/Design/`). Where a mockup and the FRD disagree on behavior or shortcuts, the FRD wins. The mockup's Settings screen showed wrong default shortcuts; the FRD's are correct. |
| 2026-09-30 | Blend modes expanded from 8 to 17: the mockup's 16 plus Additive. |
| 2026-09-30 | Added from the mockups: 12 custom-color slots, layer lock, Merge Visible (Cmd+Opt+Shift+E), Hide/Show Layer command, Pixel Grid and Symmetry switches in the status bar. |
