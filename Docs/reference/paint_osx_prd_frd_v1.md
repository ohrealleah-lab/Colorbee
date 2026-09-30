# Product Requirements Document (PRD) & Functional Requirements Document (FRD)
## Project Codename: Paint for macOS (macPaint / MS Paint Clone)

**Document Version:** 1.0.0  
**Target Platform:** macOS 12.0+ (Monterey, Ventura, Sonoma, Sequoia, and later)  
**Status:** Approved Feature Specification  
**Focus:** Pure Functional & Product Requirements (Technology-Agnostic)

---

## 1. Executive Summary & Product Vision

### 1.1 Problem Statement
macOS provides Apple Preview for basic PDF and image viewing/annotation and Apple Photos for photographic library management. However, macOS lacks an immediate, lightweight, pixel-precise raster graphics scratchpad equivalent to Microsoft Paint. Mac users seeking to make quick sketches, crop screenshots with pixel precision, edit pixel art, redact sensitive data, or perform simple raster compositions are forced to either endure complex pro-tier applications (Photoshop, GIMP, Affinity Photo) with steep learning curves and heavy startup latency, or rely on clunky browser-based tools.

### 1.2 Product Vision
To deliver a desktop-class, zero-latency, lightweight raster drawing and image editing application for macOS that captures the immediate simplicity, accessibility, and iconic toolset of Windows 7 / Classic MS Paint, modernized with high-utility features inspired by Paint.NET (Magic Wand, two-color gradients, blur/pixelate redactions, alpha transparency, and an optional multi-layer mode), while feeling completely at home on macOS.

### 1.3 Guiding Design Principles
1. **Zero-Friction Immediacy:** Cold startup must take under 300ms. A blank canvas is presented immediately upon launch with zero onboarding wizards, splash screens, or template modals.
2. **Connected, Single-Window Architecture:** All toolbars, properties, and color palettes are rigidly docked into a single, cohesive window frame—no detached or floating utility panels.
3. **Single-Layer Simplicity with Optional Depth:** By default, the application operates as an authentic single-layer destructive raster canvas. Multi-layer capabilities remain strictly optional and out of the way until activated.
4. **Authentic MS Paint Dual-Color Parity:** Left-click maps to Primary Color (Color 1) and Right-click maps to Secondary Color (Color 2) and secondary tool behaviors (e.g., Color Eraser), integrated harmoniously with macOS inputs.
5. **Modern Retina Precision:** Sharp, pixel-perfect raster rendering that embraces modern high-DPI displays without blurring or unwanted smoothing.

---

## 2. Target Personas & Primary Use Cases

| Persona | Description | Primary Needs |
| :--- | :--- | :--- |
| **The Quick Redactor & Communicator** | Casual and enterprise Mac users who frequently take screenshots and need to annotate, circle, crop, or blur sensitive text before pasting into Slack, email, or tickets. | Instant startup, clipboard paste (`Cmd+V`), crop, Gaussian Blur / Pixelate filters, arrows/callouts, copy back to clipboard (`Cmd+C`). |
| **The Pixel Artist & Indie Developer** | Creators producing 2D retro sprites, tiles, or icons at $16\times16$, $32\times32$, or $64\times64$ resolutions. | 1px Pencil tool, crisp nearest-neighbor zoom up to $1600\%$, pixel grid toggle, color eraser, exact color palette keying. |
| **The Casual Doodler / Retro Fan** | Users who want the nostalgic, immediate joy of MS Paint for casual digital drawing, meme creation, or quick visual mockups. | Brush varieties, fill bucket, spray can (airbrush), classic shape outlines, iconic Shift-drag smear trail. |
| **The Pragmatic Power User** | Users who need slightly more than classic MS Paint—such as transparent PNG creation or gradient backdrops—without launching a heavy DAW-equivalent photo suite. | Magic Wand background cutout, alpha transparency slider, two-color gradients, optional layer stacking. |

---

## 3. High-Level System Scope & Feature Tiers

```
+---------------------------------------------------------------------------------+
|                                 macOS Menu Bar                                  |
|     File    Edit    View    Image    Adjustments    Effects    Window    Help   |
+---------------------------------------------------------------------------------+
| [Connected Top Toolbar & Properties]                                            |
| Tools | Shapes | Line Width | Outline/Fill Styles | Color 1 [ ] Color 2 [ ]     |
| [Docked 28-Color Swatches Bar + Alpha Slider + macOS Color Picker Trigger]     |
+---------------------------------------+-----------------------------------------+
|                                       | [Optional Collapsible Right Inspector]  |
|                                       | +-------------------------------------+ |
|                                       | | Layers Tab (Hidden by default)      | |
|                 CANVAS                | | [ + Layer ] [ Duplicate ] [ Merge ] | |
|       (Pixel-Perfect Raster Area      | | [ ] Layer 2 (100% | Normal)         | |
|        with Interactive Drag Handles) | | [x] Layer 1 (Background)            | |
|                                       | +-------------------------------------+ |
|                                       | | History Tab (Undo Stack)            | |
+---------------------------------------+-----------------------------------------+
| [Status Bar] Cursor: 142, 388px | Selection: 240x180px | Canvas: 1920x1080px | Zoom 100% |
+---------------------------------------------------------------------------------+
```

---

## 4. Functional Requirements Document (FRD)

### FR-1: Window Chrome, Canvas & Connected UI Layout
* **FR-1.1 Connected Header Dock:** The top of the window shall contain a permanently docked ribbon/toolbar dividing controls into clear logical sections:
  * *Clipboard & Selection:* Paste, Cut, Copy, Selection Mode dropdown.
  * *Tools:* Pencil, Fill Bucket, Text, Eraser, Eyedropper, Magnifier, Gradient, Magic Wand.
  * *Brushes Gallery:* Dropdown or carousel containing 9 brush media types.
  * *Shapes Gallery:* Grid of 23 vector-to-raster primitive shapes.
  * *Stroke & Line Size:* Line thickness selectors ($1\text{px}, 2\text{px}, 3\text{px}, 4\text{px}, 5\text{px}$, and custom pixel input).
  * *Dual Color Wells:* Interactive color chips displaying Color 1 (Foreground) and Color 2 (Background), with an active selection ring indicating which color is currently targeted by palette clicks.
  * *Connected Palette Bar:* A horizontal grid of 28 classic swatches, an Alpha/Opacity slider ($0\text{--}100\%$), and an "Edit Colors" button opening the native macOS `NSColorPanel`.
* **FR-1.2 Canvas Viewport:**
  * Centered within the window, surrounded by a neutral dark/light gray matte.
  * Bounded by three interactive resize grab handles (Right-Center, Bottom-Center, Bottom-Right Corner).
  * Smooth infinite pan via two-finger trackpad drag or Spacebar + Click-drag.
  * Smooth zoom from $12.5\%$ up to $3200\%$ centered on the cursor position (pinch-to-zoom or `Cmd +` / `Cmd -`).
* **FR-1.3 Status Bar (Bottom Dock):**
  * *Pointer Position:* Displays live pixel coordinates relative to top-left of canvas (`X: {x}px, Y: {y}px`).
  * *Selection Bounds:* Displays width and height of active selection marquee (`{w} x {h}px`).
  * *Canvas Size:* Displays total dimensions of the canvas in pixels (`{w} x {h}px`).
  * *Zoom Level:* Interactive slider and percentage label with quick-reset button to $100\%$.

---

### FR-2: Color Architecture & Transparency Engine
* **FR-2.1 Dual-Color Model (Color 1 & Color 2):**
  * *Color 1 (Foreground):* Used when drawing with Left-Click.
  * *Color 2 (Background):* Used when drawing with Right-Click, filling canvas when resized, erasing with primary eraser, and serving as the transparent key color in selections.
* **FR-2.2 Modern Alpha Transparency (RGBA):**
  * The canvas engine shall support a full 32-bit RGBA color buffer.
  * Transparent pixels shall render using an industry-standard light-gray and white checkerboard pattern ($8\times8\text{px}$ squares).
  * The application shall allow an explicit transparency toggle in Canvas Properties (`Cmd+E`), allowing the background to be transparent instead of default white.
  * Both Color 1 and Color 2 shall feature independent Alpha channels ($0\text{ to }255$), controlled by the docked Alpha slider.
* **FR-2.3 Palette & Swatch Management:**
  * Displays the classic 28 preset swatches in two rows of 14.
  * Left-clicking a swatch sets Color 1; Right-clicking a swatch sets Color 2.
  * The "Edit Colors" button triggers the native macOS Color Panel (supporting Wide Gamut Display P3, Hex codes, RGB sliders, and the system magnifier/eyedropper).

---

### FR-3: Selection Tools & Manipulation Engine
* **FR-3.1 Selection Toolset:**
  * *Rectangular Selection:* Marquee bounding box with 8 resize handles.
  * *Free-Form Selection:* Lasso-style arbitrary contour that automatically closes on mouse-up.
  * *Elliptical Selection:* Elliptical marquee tool (Paint.NET addition).
  * *Magic Wand Selection:* Flood-selection tool based on color similarity (Paint.NET addition), featuring a contiguous toggle and an interactive Tolerance slider ($0\%\text{ to }100\%$).
* **FR-3.2 Selection Manipulation:**
  * *Move:* Dragging inside a selection moves the selected pixel data. The vacated area is filled with Color 2 (or transparent if the layer supports alpha).
  * *Copy-Drag:* Holding `Option` (`Alt`) while dragging creates an inline duplicated stamp of the selection.
  * *Transparent Selection Mode:* When toggled on, all pixels in the selection matching Color 2 are treated as $100\%$ transparent when dragged or pasted.
  * *Shift-Drag Smear (Iconic MS Paint Easter Egg):* Holding `Shift` while dragging an active selection leaves a continuous extruded trail of stamps along the mouse path.
  * *Invert Selection:* Reverses selected/unselected regions (`Cmd+Shift+I`).
  * *Crop to Selection:* Truncates the canvas bounding box to exactly match the active selection (`Cmd+Shift+X`).

---

### FR-4: Freehand Drawing, Brushes & Media Dynamics
* **FR-4.1 Pencil Tool:**
  * Strictly 1-pixel aliased line tool. Zero anti-aliasing, perfect for pixel art.
  * Left-click draws with Color 1; Right-click draws with Color 2.
  * Holding `Shift` constrains drawing to strictly horizontal or vertical straight lines.
* **FR-4.2 Brushes Subsystem:**
  * *Brushes Suite:* 
    1. Standard Round Brush (Anti-aliased)
    2. Calligraphy Brush 1 (Diagonal forward slash nib)
    3. Calligraphy Brush 2 (Diagonal backslash nib)
    4. Airbrush / Spray Can (Randomized droplet dispersion; density increases on hover/hold)
    5. Oil Brush (Textured bristles with soft tapering)
    6. Crayon (Textured wax grain)
    7. Marker (Semi-translucent flat stroke)
    8. Natural Pencil (Grainy graphite texture)
    9. Watercolor Brush (Soft translucent bleeds with edge accumulation)
  * Each brush dynamically respects line width settings ($1\text{px}\text{ to }50\text{px}$) and the Alpha slider.
* **FR-4.3 Eraser & Color Eraser:**
  * Square eraser tool with adjustable sizes ($4\text{px}, 6\text{px}, 8\text{px}, 10\text{px}$, adjustable dynamically with `[` and `]`).
  * *Standard Erase (Left-Click):* Replaces active pixels with Color 2 (or transparent if on a transparent layer).
  * *Color Eraser (Right-Click - Iconic MS Paint Parity):* Replaces *only* pixels matching Color 1 with Color 2, leaving all other colors on the canvas completely untouched.

---

### FR-5: Vector-to-Raster Shapes & Gradient Engine
* **FR-5.1 Pre-Defined Shapes:**
  * Supported shapes: Line, 3-Point Bézier Curve, Rectangle, Rounded Rectangle, Ellipse, Triangle, Right Triangle, Diamond, Pentagon, Hexagon, Right Arrow, Left Arrow, Up Arrow, Down Arrow, 4-Point Star, 5-Point Star, 6-Point Star, Rounded Rectangular Callout, Oval Callout, Cloud Callout, Heart, Lightning Bolt.
  * *Draw Mechanics:* Click and drag defines the shape bounding box. Holding `Shift` constrains proportions (1:1 circles, squares, or $45^\circ$ line snaps).
  * *Outline Styles:* No Outline, Solid Color, Crayon, Marker, Oil, Watercolor, Natural Pencil.
  * *Fill Styles:* No Fill, Solid Color, Crayon, Marker, Oil, Watercolor, Natural Pencil.
  * Left-click uses Color 1 for Outline and Color 2 for Fill. Right-click inverts this assignment.
  * Shapes remain interactive (editable bounding box, rotate handle) until the user clicks outside the shape bounding box, presses `Enter`, or switches tools, at which point the shape is immediately baked into the active layer raster buffer.
* **FR-5.2 Two-Color Gradient Tool (Paint.NET Integration):**
  * Allows click-and-drag gradient rendering between Color 1 and Color 2.
  * Modes: Linear, Radial, Reflected, Diamond, Conical.
  * Respects the Alpha channel of both Color 1 and Color 2 (enabling gradients that fade to full transparency).

---

### FR-6: Text Tool
* **FR-6.1 In-Place Text Editing:**
  * Clicking the canvas creates an interactive text bounding box with font family dropdown, font size ($6\text{pt}\text{ to }72\text{pt}+$ custom), Bold, Italic, Underline, and Strikethrough.
  * *Background Mode:* Toggleable between Opaque (draws a background rectangle filled with Color 2 behind the text) and Transparent (renders only text glyphs).
* **FR-6.2 Rasterization on Commit:**
  * Text remains vector and editable while the text box is active.
  * Clicking outside the text box or pressing `Esc` immediately bakes the glyphs into the active layer raster buffer. No persistent vector text layers exist in standard mode, maintaining true MS Paint parity.

---

### FR-7: Measurement, Zoom & Canvas Geometry
* **FR-7.1 Magnifier & Pixel Grid:**
  * Magnifier tool allows left-click to zoom in ($2\times, 4\times, 6\times, 8\times$) and right-click to zoom out.
  * *Pixel Grid:* When zoom level reaches or exceeds $400\%$, an optional 1-pixel grid overlay aligns with individual pixel borders. Grid lines render using inverted contrasting luminance.
* **FR-7.2 Canvas Resize & Skew Dialog (`Cmd+E` / `Cmd+W`):**
  * *Resize Options:* By Percentage ($1\text{--}500\%$) or by Pixels (Absolute Width $\times$ Height).
  * Aspect ratio lock toggle.
  * Interpolation selector: Nearest Neighbor (sharp pixels for pixel art) or Bilinear/Bicubic (smooth scaling for photos).
  * *Skew Options:* Horizontal and Vertical skew by degrees ($-89^\circ\text{ to }+89^\circ$).

---

### FR-8: Optional Multi-Layer Subsystem
* **FR-8.1 Operational Model:**
  * Single-layer mode is active by default. The Layer Panel is collapsed and takes zero UI real estate.
  * Triggered via `View -> Layers` (`Cmd+L`) or clicking the "+ Layer" icon in the window header.
* **FR-8.2 Layer Capabilities:**
  * Unlimited layer stacking (constrained only by available system RAM).
  * Layer list controls: Add New Layer, Duplicate Active Layer, Delete Layer, Merge Down, Flatten All Layers.
  * Drag-and-drop layer reordering.
  * Per-layer visibility toggle (Eye icon) and opacity slider ($0\%\text{ to }100\%$).
  * *Layer Blend Modes:* Normal, Multiply, Screen, Overlay, Darken, Lighten, Difference, Additive.
* **FR-8.3 Flattening & Save Logic:**
  * When exporting or saving to standard flat formats (PNG, JPG, BMP), the application flattens all visible layers automatically into a single composite bitmap buffer.

---

### FR-9: Image Adjustments & Redaction Effects
* **FR-9.1 Color Adjustments (`Adjustments` Menu):**
  * *Invert Colors (`Cmd+I`):* Inverts RGB values of the active selection or entire layer ($255 - C$).
  * *Brightness & Contrast:* Real-time dual slider modal with live canvas preview.
  * *Hue, Saturation & Lightness:* Dual HSL sliders with preview.
  * *Black & White / Desaturate (`Cmd+Shift+U`):* Instantly converts pixels to luminance grayscale.
* **FR-9.2 Redaction & Utility Effects (`Effects` Menu):**
  * *Gaussian Blur:* Adjustable radius ($1\text{px}\text{ to }100\text{px}$) with instant preview. Ideal for blurring passwords, email addresses, and faces.
  * *Pixelate / Mosaic:* Adjustable cell block size ($2\text{px}\text{ to }100\text{px}$). Converts text and image regions into discrete pixelated mosaic blocks.
  * *Sharpen:* Basic high-pass edge crisping filter.
  * All effects apply strictly to the active selection marquee, or to the entire active layer if no selection is active.

---

### FR-10: File Formats, I/O & Clipboard Integration
* **FR-10.1 File Format Support Matrix:**

| Format | Read Support | Write / Export Support | Notes |
| :--- | :---: | :---: | :--- |
| **PNG** | Yes | Yes (Default) | Full 32-bit RGBA alpha channel transparency support. |
| **JPEG / JPG** | Yes | Yes | Quality compression slider ($1\text{--}100\%$). Canvas auto-flattens over Color 2. |
| **BMP** | Yes | Yes | 24-bit RGB and 32-bit RGBA uncompressed Windows Bitmap parity. |
| **GIF** | Yes | Yes | 8-bit indexed color with 1-bit transparency mask support. |
| **TIFF** | Yes | Yes | Uncompressed / LZW compressed. |
| **WebP** | Yes | Yes | Modern web asset export with alpha support. |
| **HEIC** | Yes | Yes | macOS native camera format read/write. |
| **.paintproj** | Yes | Yes | Native multi-layer bundle package (preserves layers, opacity, and blend modes). |

* **FR-10.2 Clipboard & Drag-and-Drop:**
  * System clipboard paste (`Cmd+V`) automatically pastes images as an active floating selection on the current layer.
  * Dragging an image file from Finder onto the canvas:
    * *Into Canvas:* Drops as an active selection.
    * *Into Tab Bar / Empty Space:* Opens as a new document window/tab.
  * Copying a selection (`Cmd+C`) places a standard 32-bit PNG with transparency onto the macOS system pasteboard, ready for instant paste into Slack, Discord, Mail, Keynote, etc.

---

### FR-11: History & Action Engine
* **FR-11.1 Linear Undo/Redo:**
  * Unlimited undo history steps (default 100 steps in memory cache, backed by scratch disk swap if needed).
  * `Cmd+Z` for Undo; `Cmd+Shift+Z` / `Cmd+Y` for Redo.
* **FR-11.2 Visual History Panel (Collapsible):**
  * Displays a chronological list of actions ("Pencil", "Flood Fill", "Gaussian Blur", "Move Selection", "Resize Canvas").
  * Clicking any previous history row jumps the canvas state directly back to that step.

---

## 5. macOS Platform & Hardware Integration

### 5.1 Input & Dual-Button Ergonomics
* **Right-Click Parity:**
  * Secondary click (two-finger tap or right-click on mouse) executes Color 2 drawing or the secondary tool function (such as Color Eraser or Eyedropper Color 2 sampling).
  * Context menus are invoked via `Control + Click` or accessible via the top Menu Bar, preventing right-click from hijacking secondary drawing actions.
* **Trackpad Gestures:**
  * Smooth two-finger panning across the canvas viewport.
  * Smooth pinch-to-zoom with immediate nearest-neighbor scaling during the gesture.

### 5.2 High-DPI Retina Rendering Pipeline
* Canvas pixels must map 1:1 to virtual points at $100\%$ scale.
* When zoomed in above $100\%$, the renderer shall use strict Nearest-Neighbor sampling to ensure pixel boundaries remain razor-sharp without bilinear blurring.

### 5.3 macOS Native Menu Bar Integration
* **File:** New (`Cmd+N`), Open (`Cmd+O`), Save (`Cmd+S`), Save As (`Cmd+Shift+S`), Export..., Set as Desktop Picture, Page Setup, Print (`Cmd+P`), Close (`Cmd+W`).
* **Edit:** Undo (`Cmd+Z`), Redo (`Cmd+Shift+Z`), Cut (`Cmd+X`), Copy (`Cmd+C`), Paste (`Cmd+V`), Paste into New Image (`Cmd+Shift+V`), Delete (`Delete` / `Backspace`), Select All (`Cmd+A`), Invert Selection (`Cmd+Shift+I`).
* **View:** Zoom In (`Cmd+=`), Zoom Out (`Cmd+-`), Actual Size (`Cmd+0`), Show Grid (`Cmd+'`), Show Rulers (`Cmd+R`), Show Status Bar, Layers Panel (`Cmd+L`), History Panel (`Cmd+H`).
* **Image:** Crop to Selection (`Cmd+Shift+X`), Resize / Skew (`Cmd+E`), Rotate $90^\circ$ Clockwise, Rotate $90^\circ$ Counter-Clockwise, Rotate $180^\circ$, Flip Horizontal, Flip Vertical, Canvas Properties.
* **Adjustments:** Invert Colors (`Cmd+I`), Brightness/Contrast, Hue/Saturation, Desaturate (`Cmd+Shift+U`).
* **Effects:** Gaussian Blur..., Pixelate / Mosaic..., Sharpen.
* **Share:** Native macOS Share Sheet (AirDrop, Messages, Mail, Notes).

---

## 6. Non-Functional Requirements (NFR)

* **NFR-1 (Cold Start Latency):** Application launch to interactive blank canvas must occur in $< 300\text{ms}$ on Apple Silicon hardware (M1 or later).
* **NFR-2 (Drawing Latency):** Input-to-raster render latency for freehand pencil/brush strokes must remain under $16\text{ms}$ (maintaining fluid 60fps / 120fps ProMotion refresh rates).
* **NFR-3 (Memory Footprint):** Baseline single-layer application idle memory usage must not exceed $60\text{MB}$ for a standard $1920\times1080$ canvas.
* **NFR-4 (Robustness):** Memory management for high-resolution images ($8000\times8000\text{px}$) must utilize tiled backing stores to prevent crashes or beachballs.
* **NFR-5 (Dark Mode):** Complete native support for macOS Light and Dark appearance themes, dynamically adapting window chrome, dividers, tool icons, and panels while maintaining canvas color accuracy.

---

## 7. Edge Cases, Quirks & Authentic Easter Eggs

1. **The Shift-Drag Extrusion Smear:** Dragging an active selection while holding the `Shift` key creates a repeating continuous stamped extrusion along the stroke path, faithfully reproducing the famous MS Paint trick.
2. **Color Eraser Specificity:** Right-click dragging with the Eraser tool must only modify pixels whose RGB values strictly match Color 1 within a $0\%$ tolerance (or user-defined tolerance), replacing them with Color 2 without modifying any adjacent hues.
3. **Canvas Border Spill Guard:** Flood Fill (Paint Bucket) must respect outer canvas boundaries as hard limits, never wrapping around or leaking across edges.
4. **Zero-Area Selection Safety:** Clicking outside an active selection commits the selection immediately to the canvas without moving any pixels.
5. **High-DPI Coordinate Snapping:** Mouse pointer coordinates in the status bar must report exact integer bitmap pixels ($142, 388$), never fractional floating-point coordinates.

---

## 8. Acceptance Criteria & Quality Gates

* [ ] **AC-1:** Cold boot displays a ready-to-draw $100\%$ white canvas within 300ms.
* [ ] **AC-2:** Left-click draws with Color 1; Right-click draws with Color 2 across Pencil, Brushes, and Shapes.
* [ ] **AC-3:** Right-click with Eraser replaces only Color 1 with Color 2.
* [ ] **AC-4:** Magic Wand successfully selects contiguous color regions within defined tolerance slider thresholds.
* [ ] **AC-5:** Two-Color Gradient tool smoothly blends between Color 1 and Color 2 with adjustable alpha.
* [ ] **AC-6:** Gaussian Blur and Pixelate filters properly affect only the active selection marquee.
* [ ] **AC-7:** Multi-Layer panel opens on command; adding layers allows non-destructive drawing; saving single-layer images requires zero project file friction.
* [ ] **AC-8:** Holding `Shift` while dragging a selection produces the iconic extrusion smear effect.
* [ ] **AC-9:** Zooming to $400\%+$ displays the crisp pixel grid with sharp nearest-neighbor pixel boundaries on Retina screens.
* [ ] **AC-10:** Pasting an image from macOS clipboard (`Cmd+V`) creates an active selection without downsampling resolution.
