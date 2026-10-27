# Colorbee Feature Gap Analysis: Photoshop and Lightroom

_Written 2026-10-27 for Leah (PM). Research only: nothing in the FRD or the code was changed, and nothing is committed. Every decision here is yours; the rankings are my suggestions, and you can veto any of them._

**How to read this.** Section 1 is the short version. Sections 2 and 3 are the full comparison tables (every feature I could find, grouped by category). Section 4 explains why each gap is or isn't a good fit, and Section 5 shows the workflows the best ones help. Section 6 is the questions I need you to answer. Section 7 lists my sources, including what I could and couldn't read.

**Where Colorbee stands.** The FRD says the feature set has been complete since 2026-10-19 (§23), and multi-select layers and the right-click layer menu (FR-8.6) are a named exception. So anything below that you like would be another exception, and that's your call. The FRD also says there are no AI models in Colorbee "for now, not a hard no", and no network access (NFR-8). Both rules shape which Adobe features can fit.

**Words used in the tables**

| Colorbee column | Meaning |
|---|---|
| Have | Colorbee does this, or something equivalent |
| Partial | Colorbee does part of it (the note says which part) |
| Missing | Colorbee has nothing like it |

| Fit column | Meaning |
|---|---|
| Good fit | Matches immediacy and simplicity, or solves a real workflow pain point. Size in brackets: S = small, M = medium, L = large, compared with work already done in Colorbee |
| Maybe | Plausible, but I'd want your say first |
| No | Doesn't fit (the reason is one line in the note) |
| n/a | Colorbee already has it |

---

## 1. Summary

### Top 10 recommended additions, ranked

| # | Addition | Size | Why |
|---|---|---|---|
| 1 | **Auto-redact faces** (find faces on this Mac and blur, pixelate or cover them) | M | Redaction is the primary use case, and Auto-Redact only finds text today. Lightroom detects faces to sort people; Colorbee would use the same kind of detection to hide them. Apple's on-device Vision can find faces, so no AI model needs shipping. |
| 2 | **Layer follow-ups to multi-select:** Align and Distribute chosen layers, Select All Layers, Option-click the eye to show only that layer | S to M | They're the natural next step now that layers can be chosen together. They fix pain points when lining up annotations. |
| 3 | **Layer groups (folders)**, including "Group chosen layers" | M | Photoshop users reach for groups as soon as there are more than a handful of layers. Builds on the new multi-select. |
| 4 | **Guides, smart guides and snapping** | M | Rulers exist but nothing to drag out from them. Aligning callouts, badges and text is a daily annotation job. |
| 5 | **Selection refinements:** Expand, Contract, Smooth, Border, and **Color Range** | S to M | The magic wand misses edges and stray pixels. Color Range handles "select everything this blue" in one step. |
| 6 | **Export upgrades:** Convert to sRGB (or pick the color space) and Limit file size | S to M | Display P3 screenshots can look dull in other apps. A size limit solves "too big for Slack or email" without trial and error. |
| 7 | **Adjust Photo upgrades from Lightroom:** white-balance eyedropper (click something gray), Texture, Dehaze, and a per-color HSL mixer | S to M | These are Lightroom's most-used Basic and Color controls. Adjust Photo already has the sliders' look; these extend it. |
| 8 | **Color readout under the pointer** (RGB and hex in the status bar) and **eyedropper sample size** (average a 3x3 or 5x5 area) | S | Checking a design color is a PM habit. Single-pixel sampling is noisy on anti-aliased text and photos. |
| 9 | **Quick wins bundle:** Paste in Place, Trim (crop away empty or same-color borders), Canvas Size anchor (grow from the center), History Snapshots | S each | Each one is a small, well-known time-saver. |
| 10 | **Layer masks**, plus "clip to the layer below" for pixel layers | L | The biggest non-destructive upgrade to layers. Large, so it's last for effort, not for value. |

**Next tier** (also good fits): stroke smoothing for the pencil and brushes, free-angle rotate for selections and layers, a multi-stop gradient editor, Polygonal Lasso, Magic Eraser, Stroke a selection's outline, text outline and shadow, letter and line spacing, auto-detected corners for Perspective Correction, and batch-apply to a folder. Details in Section 4.

### Where Colorbee already beats both Adobe apps
Auto-Redact (text patterns, on-device, every page of a PDF), Batch Redact and the Redact Brush, Copy Text from an image, numbered Step Badges, Before/After built in, Clipboard History, "Undo on Active Layer", the Info panel's "Location: Removed", a full keyboard-shortcut editor that protects macOS shortcuts, and instant start. Photoshop and Lightroom don't aim at these jobs.

### What the Adobe apps are doing lately (last year)
Most big new features in both apps are **AI and cloud features** (Generative Fill, Expand, Remove, Upscale, Harmonize, AI Assistant, Assisted Culling). Those don't fit Colorbee's no-AI, no-network rules. The non-AI new items worth noting are Photoshop's **Clarity, Dehaze and Grain adjustment layers** and **Temperature/Tint in Color & Vibrance**, and Lightroom's **Feather and Edge sliders on masks** and **Point Color Variance**. Items tagged NEW in the tables below came from the last year of release notes.

---

## 2. Photoshop vs Colorbee

_Photoshop = the desktop app, 2026 line (27.x). "NEW" = added in roughly the last year, per Adobe's release notes and announcements. "(beta)" = not yet in the regular release._

### 2.1 Selection

| Photoshop feature | Colorbee | Fit | Notes |
|---|---|---|---|
| Rectangular and Elliptical Marquee | Have | n/a | Handles, Shift for square/circle |
| Single Row / Single Column Marquee | Missing | Maybe (S) | 1-px selections, mostly pixel art |
| Lasso (freehand) | Have | n/a | |
| Polygonal Lasso (click-to-click straight edges) | Missing | Good fit (S) | Cutting around UI boxes and screenshots |
| Magnetic Lasso | Missing | Maybe (M) | Edge-snapping; Select Subject covers photos |
| Magic Wand (tolerance, contiguous) | Have | n/a | |
| Quick Selection | Missing | Maybe (M) | Click-and-paint selection; Select Subject covers some of it |
| Object Selection | Partial | n/a | Select Subject with a click to choose one subject |
| Select Subject | Have | n/a | On-device Vision |
| Select Sky | Missing | Maybe (M) | Would need a sky detector; engineering check needed |
| Select and Mask / Refine Edge (smooth, feather, shift edge, decontaminate) | Partial | Maybe (M) | Colorbee has Feather only |
| Color Range (by sampled color, highlights, midtones, shadows, skin) | Missing | Good fit (M) | "Select all this blue" |
| Focus Area | Missing | No | Photographer's tool, rare |
| Modify: Expand / Contract | Missing | Good fit (S) | Fix wand selections that miss edges |
| Modify: Smooth | Missing | Good fit (S) | Cleans stray pixels in wand selections |
| Modify: Border | Missing | Maybe (S) | |
| Grow / Similar | Missing | Maybe (S) | |
| Feather | Have | n/a | FR-3.4 |
| Add / Subtract / Intersect | Have | n/a | Shift, Option, Shift+Option |
| Invert, Select All, Deselect | Have | n/a | |
| Reselect (bring back the last selection) | Missing | Maybe (S) | History can jump back, so low need |
| Select All Layers / Similar Layers | Missing | Good fit (S) | Builds on new multi-select |
| Transform Selection (change the outline only) | Partial | Maybe (M) | Cmd+arrows resize the outline in steps |
| Save / Load Selection, Alpha channels | Missing | Maybe (M) | Layer masks would cover most uses |
| Quick Mask mode (paint a selection) | Missing | Maybe (M) | |
| Selection on canvas context menu | Have | n/a | Ctrl-click menu |

### 2.2 Layers

| Photoshop feature | Colorbee | Fit | Notes |
|---|---|---|---|
| Add, duplicate, delete, rename, reorder, hide | Have | n/a | |
| Choose several layers (Shift, Cmd-click) | Have | n/a | FR-8.6, built 2026-10-27 |
| Right-click layer menu | Have | n/a | FR-8.6 |
| Merge Down / Merge Visible / Merge chosen layers / Flatten | Have | n/a | |
| Stamp Visible (merged copy on a new layer, originals kept) | Missing | Good fit (S) | Merge Visible replaces the layers; a copy on top is safer |
| Layer groups and nested groups | Missing | Good fit (M) | Biggest gap after masks |
| Layer masks (pixel) | Missing | Good fit (L) | Hide or reveal without erasing |
| Vector masks | Missing | No | Needs vector paths |
| Clipping masks | Partial | Good fit (M) | "Only the layer below" exists for adjustment layers only |
| Opacity | Have | n/a | |
| Fill opacity (separate from opacity) | Missing | Maybe (S) | |
| Blend modes (27 in Photoshop) | Partial | Maybe (S) | 17 in Colorbee. Missing: Dissolve, Linear Burn, Darker Color, Lighter Color, Vivid Light, Linear Light, Pin Light, Hard Mix, Subtract, Divide |
| Lock: transparent pixels, image pixels, position, all | Partial | Good fit (S) | One padlock locks everything. "Lock transparent pixels" lets you recolor without spilling |
| Layer styles (Stroke, Drop Shadow, Inner Shadow, Glows, Bevel, Overlays) | Partial | Maybe (L) | Drop Shadow and Border exist as one-time effects, not live styles |
| Fill layers (solid, gradient, pattern) | Missing | Maybe (S) | |
| Adjustment layers | Partial | n/a | Colorbee: Adjust Photo, Levels, Curves, Hue/Saturation, Desaturate, Invert, Posterize, Sepia, filters, Blur, Sharpen. Others in 2.5 |
| Smart Objects (non-destructive scale and filters) | Missing | Maybe (L) | Big change to how pixels work |
| Smart Filters | Partial | n/a | Blur and Sharpen adjustment layers act like them |
| Link layers | Missing | Maybe (S) | Chosen layers already move together |
| Align and Distribute layers | Missing | Good fit (S to M) | Lines up chosen layers |
| Auto-Align / Auto-Blend layers | Missing | No | Photo stacking |
| Layer Comps (saved layer states) | Missing | No | Rare outside design work |
| Isolate a layer (Option-click the eye) | Missing | Good fit (S) | |
| Click the canvas to pick a layer (Move tool auto-select) | Missing | Good fit (M) | Handy with many annotations |
| Layer search, color labels | Missing | Maybe (S) | |
| Copy a layer into another document | Missing | Maybe (S) | Copy and Paste covers most of it |
| Export Layers to Files | Missing | Maybe (S to M) | |
| Per-layer undo | Have | n/a | Colorbee extra: Undo on Active Layer |

### 2.3 Transform and image geometry

| Photoshop feature | Colorbee | Fit | Notes |
|---|---|---|---|
| Free Transform: scale | Have | n/a | 8 handles on a selection |
| Free Transform: rotate any angle | Missing | Good fit (M) | Selections and layers rotate only 90 degrees. Shapes have a rotate handle |
| Free Transform: skew | Have | n/a | Resize and Skew |
| Free Transform: distort, perspective, warp | Missing | Maybe (M) | Perspective Correction works on the whole image only |
| Content-Aware Scale | Missing | No | Content-aware; needs AI-like fill |
| Puppet Warp, Perspective Warp | Missing | No | Design/illustration tools |
| Liquify | Missing | No | Big engine, little use for screenshots |
| Crop tool (ratios, presets, thirds grid) | Have | n/a | Crop… with presets |
| Crop with Generative Expand / Content-Aware | Missing | No | AI |
| Straighten (angle slider or draw a line) | Have | n/a | |
| Perspective Crop | Have | n/a | Perspective Correction |
| Image Size with resampling choices | Partial | Maybe (S) | Colorbee has Sharp, Smooth, Nearest Neighbor |
| Canvas Size with an anchor (center, corner) | Partial | Good fit (S) | Canvas grows from top-left only |
| Trim (remove transparent or same-color edges) | Missing | Good fit (S) | Great after cutouts and screenshots |
| Rotate Canvas, Flip | Have | n/a | |
| Ruler / Count tools | Have | n/a | Measure, Step Badges |
| Duplicate document | Have | n/a | |

### 2.4 Painting, drawing and shapes

| Photoshop feature | Colorbee | Fit | Notes |
|---|---|---|---|
| Pencil | Have | n/a | |
| Brush (hundreds of presets) | Partial | n/a | 9 brushes with pressure |
| Brush Settings panel (spacing, scatter, dynamics) | Missing | No | Illustrator territory |
| Custom brushes from a selection | Missing | Maybe (M) | |
| Stroke smoothing / stabilizer | Missing | Good fit (S to M) | Steadier lines on a trackpad |
| Tablet tilt and rotation | Missing | No | Pressure is handled |
| Painting symmetry | Have | n/a | |
| Mixer Brush | Missing | No | |
| Color Replacement Brush | Missing | Maybe (S to M) | Paint to recolor |
| Eraser | Have | n/a | |
| Magic Eraser (click to erase a color) | Missing | Good fit (S) | Quick logo cutouts. Check first whether Fill with a transparent color already does it |
| Background Eraser | Partial | Maybe (M) | Color Eraser covers exact matches |
| Paint Bucket | Have | n/a | Tolerance |
| Gradient tool (linear, radial, reflected, diamond, angle) | Have | n/a | |
| Gradient Editor (many stops, opacity stops, presets) | Missing | Good fit (M) | Colorbee gradients use only two colors |
| Pattern fill, Define Pattern | Missing | Maybe (S) | |
| Stroke a selection's outline | Missing | Good fit (S) | Outline a lasso region for annotation |
| Fill with Color 1 or Color 2 | Partial | Maybe (S) | Delete fills with Color 2; Color 1 needs the bucket or Solid Fill |
| History Brush (paint back from an earlier state) | Missing | Maybe (M) | Revert Layer covers whole layers |
| Eyedropper sample size (3x3, 5x5 and so on) | Missing | Good fit (S) | Single pixel is noisy |
| Color Sampler (pin points, read values) | Missing | Maybe (M) | |
| Shapes: Line, Rectangle, Rounded Rectangle, Ellipse, Triangle, Polygon | Have | n/a | 23 shapes, editable until placed |
| Custom Shape library | Partial | n/a | 23 built in |
| Live shape properties (corner radius after drawing) | Missing | Maybe (M) | Shapes are pixels once placed |
| Pen, Curvature Pen, Freeform Pen, paths | Missing | No | "A paint program first" (FRD 1.1) |
| Shape boolean operations | Missing | No | Vector work |
| Step Badges, Redact Brush | Have | n/a | Colorbee extras |

### 2.5 Text

| Photoshop feature | Colorbee | Fit | Notes |
|---|---|---|---|
| Horizontal Type (click or drag a box) | Have | n/a | Edited in place |
| Editing text after it's placed | Missing | Maybe (L) | Colorbee deliberately matches classic Paint: text becomes pixels. Your call (Question 1) |
| Font, size, B/I/U/S, alignment | Have | n/a | |
| Text styles | Have | n/a | |
| Character panel: tracking, kerning, leading, baseline | Partial | Good fit (S to M) | At least letter and line spacing |
| Paragraph panel: justify, indents, hyphenation | Partial | Maybe (S) | Alignment only |
| Text outline or shadow (readability on busy images) | Missing | Good fit (S to M) | Via layer styles in Photoshop |
| Text on a path, warped text | Missing | Maybe (M) | |
| Vertical Type, Type Mask | Missing | No | |
| Find and Replace, spell check | Missing | No | |
| Copy Text from an image (OCR) | Have | n/a | Colorbee extra |

### 2.6 Retouching

| Photoshop feature | Colorbee | Fit | Notes |
|---|---|---|---|
| Spot Healing Brush | Have | n/a | Spot Heal |
| Healing Brush | Partial | n/a | Clone Stamp with Match Tone |
| Patch Tool | Missing | Maybe (M) | |
| Clone Stamp | Have | n/a | |
| Pattern Stamp | Missing | No | |
| Content-Aware Move / Extend | Missing | No | AI-like |
| Remove tool | Partial | n/a | Non-AI; best on simple backgrounds |
| Generative Remove, remove distractors (NEW; on-device Remove model is beta) | Missing | No | AI model download |
| Red Eye | Have | n/a | Remove Red-Eye |
| Dodge / Burn | Have | n/a | Lighten and Darken |
| Sponge | Have | n/a | Saturate and Desaturate |
| Blur, Sharpen, Smudge tools | Have | n/a | |

### 2.7 Color and tone adjustments

| Photoshop feature | Colorbee | Fit | Notes |
|---|---|---|---|
| Brightness/Contrast | Have | n/a | Adjust Photo |
| Levels (with histogram, Auto) | Have | n/a | |
| Curves (RGB and channels) | Have | n/a | |
| Exposure | Have | n/a | Adjust Photo |
| Vibrance | Have | n/a | |
| Hue/Saturation: master | Have | n/a | |
| Hue/Saturation: per color range | Missing | Good fit (M) | HSL mixer; see Lightroom |
| Color Balance (shadows, midtones, highlights) | Missing | Maybe (M) | |
| Black and White (per-channel mix) | Partial | Maybe (S to M) | Desaturate only |
| Photo Filter | Partial | n/a | Warmth, plus saved Filters |
| Channel Mixer | Missing | No | |
| Color Lookup (LUT files) | Missing | Maybe (M) | Import `.cube` looks |
| Invert, Posterize | Have | n/a | |
| Threshold | Missing | Maybe (S) | Black-and-white cutoff for scans and pixel art |
| Gradient Map | Missing | Maybe (S to M) | |
| Selective Color | Missing | Maybe (M) | |
| Shadows/Highlights | Have | n/a | Adjust Photo |
| Replace Color | Missing | Maybe (S to M) | Color Range plus Hue/Saturation would cover it |
| Match Color, Equalize, HDR Toning | Missing | No | |
| Auto Tone, Auto Contrast, Auto Color | Partial | n/a | Auto Contrast and Adjust Photo Auto; no Auto Color |
| Color & Vibrance with Temperature and Tint (NEW) | Have | n/a | Warmth and Tint in Adjust Photo |
| Clarity adjustment layer (NEW) | Partial | Good fit (S) | Definition may be close; confirm |
| Dehaze adjustment layer (NEW) | Missing | Good fit (S) | Lightroom has it too |
| Grain adjustment layer (NEW) | Partial | Maybe (S) | Add Noise exists, not as a layer |
| Camera Raw filter (open any image in Camera Raw) | Partial | No | Adjust Photo is the in-app equivalent; Develop opens RAW |
| 16-bit and 32-bit color | Missing | No | Colorbee is 8-bit by design |
| CMYK, Lab, Duotone, Multichannel | Missing | No | Print workflows |
| Indexed Color (reduce to N colors) | Missing | Maybe (M) | Pixel art and GIFs |
| Convert to Profile (for example sRGB) | Missing | Good fit (S to M) | Colorbee keeps the profile but can't convert |
| Soft proofing | Missing | No | Print workflows |

### 2.8 Filters

| Photoshop feature | Colorbee | Fit | Notes |
|---|---|---|---|
| Gaussian Blur, Motion Blur | Have | n/a | |
| Radial, Surface, Box, Shape, Smart Blur | Missing | No | |
| Blur Gallery: Tilt-Shift, Iris, Field, Path, Spin | Missing | Maybe (M) | Spotlight already blurs everything outside a selection |
| Lens Blur (depth) | Missing | No | Needs depth data or AI |
| Unsharp Mask, Smart Sharpen (radius, threshold) | Partial | Good fit (S) | Colorbee Sharpen has one amount |
| Shake Reduction | Missing | No | |
| Add Noise | Have | n/a | |
| Reduce Noise, Despeckle, Median, Dust and Scratches | Partial | Maybe (S) | One Noise Reduction slider only |
| Pixelate: Mosaic | Have | n/a | Pixelate |
| Pixelate: Crystallize, Pointillize, Facet and others | Missing | No | |
| Stylize: Emboss | Have | n/a | |
| Stylize: Find Edges, Glowing Edges, Oil Paint and others | Missing | No | |
| Distort: Ripple, Wave, Twirl, Spherize, Pinch and others | Missing | No | |
| Render: Clouds, Lens Flare, Lighting Effects | Missing | No | |
| High Pass, Offset | Missing | Maybe (S) | Offset helps seamless pixel-art tiles |
| Lens Correction | Partial | Maybe (M) | RAW only, via macOS |
| Vignette | Have | n/a | |
| Neural Filters (skin smoothing, colorize, style transfer, super zoom) | Missing | No | AI and cloud |
| Filter Gallery | Missing | No | |

### 2.9 AI and generative (mostly NEW)

| Photoshop feature | Colorbee | Fit | Notes |
|---|---|---|---|
| Generative Fill (Firefly Image 4, partner models) NEW | Missing | No | AI and network |
| Reference Image, Generate Similar NEW | Missing | No | AI |
| Generative Expand (via Crop) NEW | Missing | No | AI |
| Generative Upscale (Topaz, Firefly) NEW | Missing | No | AI. Resize and Skew does plain scaling |
| Harmonize NEW | Missing | No | AI |
| Enhance Edge NEW (beta) | Missing | No | AI, costs credits |
| Relight NEW (beta) | Missing | No | AI |
| AI Assistant, Prompt to Edit, AI Markup NEW (beta) | Missing | No | AI |
| Firefly Custom Models NEW (beta) | Missing | No | AI |
| Select Subject / Remove Background, on device NEW | Have | n/a | Colorbee uses Apple Vision |
| Content Credentials | Missing | No | Signing infrastructure |

### 2.10 Automation, files and workflow

| Photoshop feature | Colorbee | Fit | Notes |
|---|---|---|---|
| Actions (record and replay steps) | Missing | Maybe (L) | Powerful, but a big design |
| Batch (run on a folder) | Missing | Good fit (L) | Needs care: Auto-Redact has a review step by design |
| Droplets, Image Processor, Contact Sheet | Missing | No | |
| Scripting, plug-ins, extensions | Missing | No | |
| Shortcuts app / App Intents (macOS) | Missing | Maybe (M) | Not in Photoshop; the Mac way to automate |
| Export As (format, quality, size) | Have | n/a | Export… |
| Quick Export, Export presets | Have | n/a | Export As presets |
| Save for Web: limit file size | Missing | Good fit (M) | |
| Export color space choice | Missing | Good fit (S to M) | |
| Save as PSD / layered TIFF / open PSD with layers | Missing | Maybe (L) | Coworkers' PSDs open flat? Check with Question 5 |
| SVG, AVIF, JPEG XL, WebP save | Missing | Maybe (S to M) | WebP save was deliberately skipped (FRD 11.1) |
| Animated GIF / video timeline | Partial | No | GIF frames open as pages; saving animations is out of scope |
| 3D | Missing | No | |
| Artboards | Partial | n/a | Pages cover multi-size work |
| Rulers | Have | n/a | Pixels only |
| Guides, Smart Guides, Snap, Grid | Partial | Good fit (M) | Only rulers and the pixel grid exist |
| Slices | Missing | No | |
| Navigator panel | Missing | Maybe (S to M) | |
| Histogram panel (live) | Partial | Maybe (S) | Shown inside Levels |
| Pointer color readout (RGB or hex under the cursor) | Missing | Good fit (S) | Status bar |
| Info panel (document details) | Have | n/a | |
| History panel | Have | n/a | |
| History Snapshots (named save points) | Missing | Good fit (S) | |
| Paste in Place | Missing | Good fit (S) | Colorbee pastes at top-left of the view |
| Paste Into (paste inside a selection) | Missing | Maybe (S) | |
| Fade last operation | Missing | No | |
| Compare view (second window of one document) | Partial | Maybe (S) | Before/After exists |
| Photomerge / panorama (stitch scrolling screenshots) | Missing | Maybe (L) | |
| Merge to HDR, Focus Stacking | Missing | No | |
| Libraries, Stock panel NEW, cloud documents, Firefly Boards NEW | Missing | No | Accounts and network |
| Share for review | Partial | n/a | System Share sheet |
| Print | Have | n/a | |
| Keyboard shortcut editor | Have | n/a | Colorbee's is stronger |
| Pages, PDF open, Export as PDF | Have | n/a | |

---

## 3. Lightroom vs Colorbee

_"Where": **Classic** = Lightroom Classic (15.x), **Cloud** = the newer Lightroom (desktop, mobile, web), **Both** = either. Lightroom is mostly photo library management plus photo editing; Colorbee is a single-document editor, so the library half is mostly a "No"._

### 3.1 Library, organizing and importing

| Lightroom feature | Where | Colorbee | Fit | Notes |
|---|---|---|---|---|
| Catalog and import (copy, move, add; import presets) | Classic | Missing | No | Colorbee opens files; it keeps no catalog |
| Folders, Collections, Smart Collections, Collection Sets | Classic | Missing | No | Library work |
| Albums, shared albums, Discover | Cloud | Missing | No | Cloud and network |
| Grid, Loupe, Survey, Compare views | Both | Missing | Maybe (M) | A "next/previous picture in this folder" might help; see Question 7 |
| Star ratings, flags, color labels | Both | Missing | No | |
| Keywords, metadata editing (IPTC, EXIF), presets | Both | Missing | No | Info is read-only by design; location is stripped |
| Search and filters | Both | Missing | No | |
| Stacks, Auto Stack NEW, duplicate detection NEW | Classic | Missing | No | Library work |
| Assisted Culling NEW, Faces panel NEW | Classic | Missing | No | AI sorting |
| People view, face recognition | Both | Missing | Good fit (M) | As a redaction tool: find faces and blur them (Top 10 #1) |
| Map module (GPS) | Classic | Missing | No | Colorbee removes location on purpose |
| Virtual copies | Classic | Partial | No | Pages and Duplicate cover simple cases |
| Tethered capture (Leica added NEW) | Classic | Missing | No | |
| Publish services, Lightroom sync, keyword sync NEW | Both | Missing | No | Accounts and network |
| Slideshow (4K export NEW), Web gallery, Book modules | Classic | Missing | No | |
| Print module: layouts, contact sheets | Classic | Partial | No | Print exists; layouts don't |
| Background activity manager NEW | Classic | n/a | No | Library work |

### 3.2 Develop: basic tone and color

| Lightroom feature | Where | Colorbee | Fit | Notes |
|---|---|---|---|---|
| Profiles (Adobe Color and others) | Both | Partial | Maybe (M) | Saved Filters are the nearest thing |
| White Balance: Temperature and Tint | Both | Have | n/a | Warmth and Tint |
| White Balance eyedropper (click something gray) | Both | Missing | Good fit (S) | Pairs with Warmth and Tint |
| Exposure, Contrast, Highlights, Shadows | Both | Have | n/a | Adjust Photo |
| Whites, Blacks | Both | Partial | Maybe (S) | Black Point exists; Levels sets the white point |
| Texture | Both | Missing | Good fit (S to M) | Fine-detail contrast |
| Clarity | Both | Partial | n/a | Definition is close; confirm |
| Dehaze | Both | Missing | Good fit (S) | |
| Vibrance, Saturation | Both | Have | n/a | |
| Auto Tone, Auto White Balance | Both | Have | n/a | Adjust Photo Auto |
| Tone Curve: point curve | Both | Have | n/a | Curves |
| Tone Curve: parametric curve | Classic | Missing | Maybe (S) | |
| Targeted Adjustment Tool (drag on the image) | Classic | Missing | Maybe (M) | |
| Color Mixer / HSL (hue, saturation, luminance per color) | Both | Missing | Good fit (M) | Top 10 #7 |
| Black and White mix | Both | Partial | Maybe (S to M) | Desaturate only |
| Color Grading (shadows, midtones, highlights wheels) | Both | Missing | Maybe (M) | |
| Point Color, Variance NEW | Classic | Missing | Maybe (M) | Pairs with HSL |
| Histogram with clipping warnings | Both | Partial | Maybe (S) | Histogram lives in Levels |

### 3.3 Develop: detail, lens, geometry, effects

| Lightroom feature | Where | Colorbee | Fit | Notes |
|---|---|---|---|---|
| Sharpening: amount, radius, detail, masking | Both | Partial | Maybe (S to M) | Colorbee has one amount |
| Noise Reduction: luminance, color | Both | Partial | n/a | One slider |
| Denoise (AI) | Both | Missing | No | AI |
| Raw Details, Super Resolution (AI) | Both | Missing | No | AI |
| Lens Corrections: profile, distortion, defringe | Both | Partial | Maybe (M) | RAW files only, via macOS |
| Upright (auto level, vertical, full) | Both | Missing | Good fit (M) | Auto-detected corners for Perspective Correction |
| Transform: vertical, horizontal, rotate, scale, offset | Both | Partial | n/a | Straighten and Perspective Correction |
| Crop and Straighten, aspect ratios | Both | Have | n/a | |
| Crop overlays (thirds, golden ratio, diagonal and others) | Both | Partial | Maybe (S) | Thirds only |
| Zoom while cropping NEW | Classic | Partial | Maybe (S) | Colorbee can zoom the canvas; not during Crop |
| Dim area being cropped out NEW | Classic | Missing | Maybe (S) | |
| Post-crop Vignette (amount, midpoint, roundness, feather) | Both | Partial | Maybe (S) | Colorbee: amount and size |
| Grain: amount, size, roughness | Both | Partial | Maybe (S) | Add Noise has amount and color/mono |
| Calibration panel | Classic | Missing | No | Camera-specific |
| HDR editing, HDR headroom / limit slider NEW | Both | Missing | No | Colorbee is 8-bit |
| 32-bit HDR sent to Photoshop NEW | Classic | Missing | No | |

### 3.4 Develop: masking, local edits and healing

| Lightroom feature | Where | Colorbee | Fit | Notes |
|---|---|---|---|---|
| Subject mask | Both | Have | n/a | Select Subject, then adjust the selection |
| Background mask | Both | Have | n/a | Select Subject, then invert |
| Sky mask | Both | Missing | Maybe (M) | Same note as Photoshop Select Sky |
| People masks (face, skin, eyes, hair, clothes) | Both | Missing | No | AI and heavy |
| Landscape masks: water, mountains, vegetation, architecture, snow NEW | Both | Missing | No | AI |
| Objects mask | Both | Partial | n/a | Select Subject click |
| Linear gradient mask (graduated filter) | Both | Missing | Maybe (S to M) | Feathered selections already work for rectangles |
| Radial gradient mask | Both | Partial | n/a | Ellipse plus Feather, then Adjust Photo |
| Brush mask | Both | Partial | Maybe (M) | Local brushes exist; no paintable selection |
| Luminance Range mask | Classic | Missing | Good fit (M) | Same family as Color Range |
| Color Range mask | Both | Missing | Good fit (M) | Same as Photoshop Color Range |
| Depth Range mask | Both | Missing | No | Needs depth data |
| Add, subtract, intersect masks | Both | Have | n/a | |
| Feather and Edge sliders on masks NEW | Classic | Partial | n/a | Feather exists; no separate edge control |
| Check All / Check None (landscape and people masks) NEW | Classic | n/a | No | AI mask list |
| Per-mask local sliders (Exposure and so on) | Both | Partial | n/a | Adjust Photo applies to a selection |
| Remove tool: Heal and Clone | Both | Have | n/a | Spot Heal, Clone Stamp |
| Generative Remove, shadow and reflection detection NEW | Both | Missing | No | AI |
| Reflection Removal (improved NEW) | Both | Missing | No | AI |
| Dust Removal (automatic) NEW, Visualize Spots | Classic | Missing | Maybe (S to M) | Useful on scans; Spot Heal is manual |
| Red Eye (and pet eye) | Both | Have | n/a | |
| Lens Blur (AI depth) | Both | Missing | No | AI |

### 3.5 Presets, history and copying edits

| Lightroom feature | Where | Colorbee | Fit | Notes |
|---|---|---|---|---|
| Develop presets, adaptive presets | Both | Partial | n/a | Filters; `.colorbeefilter` files |
| Import presets (`.xmp`, LUT profiles) | Both | Missing | Maybe (M) | `.cube` import |
| History states | Classic | Have | n/a | |
| Snapshots | Classic | Missing | Good fit (S) | Named save points |
| Copy and Paste Settings | Classic | Partial | Maybe (S) | Save as Filter then apply works, in more steps |
| Sync Settings, Auto Sync, Match Total Exposures | Classic | Missing | No | Many-photo workflow |
| Previous (reapply last edit) | Classic | Missing | Maybe (S) | |
| Versions (several edits of one photo) | Cloud | Missing | Maybe (M) | Pages and Duplicate are the nearest |
| Before/After (side by side, split) | Both | Have | n/a | |
| Soft proofing | Classic | Missing | No | |
| Camera raw opening | Both | Have | n/a | Develop window |
| Render to DNG NEW, .acr sidecars NEW | Classic | Missing | No | |
| Panorama, HDR, HDR panorama merge | Classic | Missing | No | |

### 3.6 Export

| Lightroom feature | Where | Colorbee | Fit | Notes |
|---|---|---|---|---|
| Export presets | Both | Have | n/a | Export As, editable |
| Resize to fit: width, height, long edge, percent, megapixels | Both | Partial | n/a | Colorbee: width, or fit a square |
| Quality | Both | Have | n/a | |
| Color space choice (sRGB, Display P3, Adobe RGB, ProPhoto) | Both | Missing | Good fit (S to M) | Top 10 #6 |
| Limit file size | Classic | Missing | Good fit (M) | Top 10 #6 |
| Output sharpening | Classic | Missing | Maybe (S to M) | |
| Metadata choices | Both | Partial | n/a | Camera details off by default; location never kept |
| Watermark | Classic | Missing | Maybe (M) | |
| File naming templates, batch export | Classic | Missing | Maybe (M) | Pairs with batch-apply |
| Formats: JPEG, PNG, TIFF, PSD, DNG, original | Both | Partial | Maybe (L) | No PSD or DNG |
| Video and slideshow export | Classic | Missing | No | |

### 3.7 Lightroom (cloud) specifics

| Lightroom feature | Where | Colorbee | Fit | Notes |
|---|---|---|---|---|
| Cloud storage, sync across devices, web access | Cloud | Missing | No | Colorbee has no network (NFR-8) |
| Guided edits and learning (Quick Actions, Learn) | Cloud | Partial | n/a | The help book |
| Auto Albums, AI search | Cloud | Missing | No | AI and cloud |
| Photo to Video (AI) NEW | Cloud (mobile) | Missing | No | AI |
| Generative expand NEW | Cloud (mobile) | Missing | No | AI |
| Quick blemish removal NEW | Cloud (mobile) | Have | n/a | Spot Heal |
| Large PSB file import NEW | Cloud (web) | Missing | No | |
| Camera capture, HDR capture | Cloud (mobile) | Missing | No | |

---

## 4. Fit analysis

### 4.1 Good fits, with reasons

I ordered these roughly by value, then size. None is more than one idea at a time.

**Redaction and annotation (Colorbee's main job)**
- **Auto-redact faces (M).** Reason: faces in screenshots, video calls and photos are a redaction target as common as emails. Apple's on-device Vision finds faces, which keeps Colorbee's "nothing leaves this Mac" promise. It reuses the Auto-Redact review sheet. _Check at build time:_ how well Vision finds small or turned faces.
- **Guides, smart guides and snapping (M).** Reason: rulers show where things are, but you can't pin an alignment line. Drag-from-the-ruler guides plus snapping make badges, callouts and text line up in a click.
- **Stroke a selection's outline (S).** Reason: outlining a lasso or wand region is a common annotation, and shapes only cover geometric outlines.
- **Text outline or shadow (S to M) and letter/line spacing (S to M).** Reason: annotation text often sits on busy screenshots and needs an edge to stay readable.
- **Polygonal Lasso (S).** Reason: straight-edge cutouts (windows, buttons, cards) are fiddly with the freehand lasso.
- **Pointer color readout (S) and eyedropper sample size (S).** Reason: matching a brand color or checking a design is a daily PM habit.

**Layers (follow-ups to the multi-select you just added)**
- **Align and Distribute (S to M), Select All Layers (S), Option-click the eye to isolate (S).** Reason: they act on the layers you can now choose together.
- **Layer groups (M).** Reason: once there are 10+ annotation layers, folders are how people stay sane. "Group chosen layers" is a natural right-click item.
- **Stamp Visible (S).** Reason: lets you retouch or adjust "on top of everything" without merging away your layers.
- **Click a canvas item to pick its layer (M).** Reason: with many annotation layers, hunting through the panel is slow.
- **Layer masks and clip-to-layer-below (L).** Reason: hide parts of a layer without erasing them. It's the biggest non-destructive upgrade, but it touches the display shader, history, the project file and every tool. Size is large.
- **Lock transparent pixels (S).** Reason: recolor a shape or text layer without spilling outside it.

**Selections**
- **Expand, Contract, Smooth, Border (S each) and Color Range (M).** Reason: Magic Wand selections often have ragged or missed edges, and "select everything this color" is a common first step.

**Photo editing (the Lightroom side)**
- **White-balance eyedropper (S), Dehaze (S), Texture (S to M), per-color HSL mixer (M).** Reason: they're the most-used Basic and Color controls in Lightroom, and Adjust Photo and the Adjustments panel are the natural homes. Each also arrives as an adjustment layer.
- **Snapshots in History (S).** Reason: name a good state, then experiment without losing it.
- **Auto-detected corners for Perspective Correction (M).** Reason: whiteboard and document photos are the main use. Apple's Vision can find rectangles on-device. _Check at build time._
- **Sharpen with radius and threshold (S).** Reason: one amount slider is blunt for photos.

**Output and files**
- **Convert to sRGB / choose the color space on export (S to M).** Reason: Colorbee keeps Display P3, which can look dull when someone opens the file in an app that ignores profiles.
- **Limit file size on export (M).** Reason: "under 1 MB for the ticket" is a common need, and trying quality settings by hand is tedious.
- **Trim, Canvas Size anchor, Paste in Place (S each).** Reason: each saves a handful of steps in everyday work.
- **Batch-apply to a folder (L).** Reason: redacting 30 screenshots one by one is exactly the pain point it solves. _Tension:_ Auto-Redact's review step is a safety feature, so a batch would have to keep a review or skip auto-redact (Question 3).

**Painting**
- **Stroke smoothing (S to M).** Reason: lines drawn on a trackpad wobble.
- **Magic Eraser (S).** Reason: one click to cut a logo off a flat background. Confirm first whether Fill with a transparent color already does this.
- **Gradient editor with several stops (M).** Reason: gradients are two-color today.
- **Free-angle rotate for selections and layers (M).** Reason: only 90-degree steps exist now.

### 4.2 Maybes (I'd want your say before sizing)

Quick Selection, Magnetic Lasso, Select Sky, Select and Mask edge tools, Quick Mask, Save/Load Selection, fill layers, link layers, fill opacity, 10 more blend modes, live layer styles, Smart Objects, Patch tool, History Brush, Color Replacement Brush, custom brushes, Color Sampler, live shape properties, Color Balance, Black and White mix, LUT import, Threshold, Gradient Map, Selective Color, Replace Color, Indexed Color, Blur Gallery (tilt-shift), Offset, lens correction, parametric curve, Targeted Adjustment Tool, Color Grading, Point Color, Visualize Spots, crop overlays, watermark, Shortcuts/App Intents, Photomerge for scrolling screenshots, PSD import, a folder-browser (next/previous picture), Navigator, histogram panel.

### 4.3 Not a fit, with reasons

| Gap | Why not |
|---|---|
| Generative Fill, Expand, Remove, Upscale; Harmonize; Enhance Edge; Relight; AI Assistant; Prompt to Edit; Neural Filters; Denoise; Super Resolution; Lens Blur; people and landscape masks; Photo to Video; Assisted Culling | AI or cloud. FRD §23: no AI models "for now, to keep Colorbee small", and NFR-8 forbids network use |
| Adobe Stock, Libraries, Firefly Boards, cloud documents, Lightroom sync, albums, web access | Accounts and network (NFR-8) |
| Pen tool, vector paths, vector masks, shape boolean operations | FRD 1.1: "A paint program first" |
| CMYK, Lab, Multichannel, 16/32-bit, HDR, soft proofing, Calibration | Print and pro-photo pipelines; Colorbee is 8-bit by design |
| 3D, video timeline, animation | Out of scope |
| Catalog, collections, ratings, keywords, People, Map, Book, Slideshow, Web, publish services, tethering | Library management; Colorbee edits one document at a time |
| Brush Settings panel, Mixer Brush, Pattern Stamp | Illustration tools, not paint-program basics |
| Liquify, Puppet Warp, Content-Aware Scale, Perspective Warp | Heavy engines with little use for screenshots |
| Most artistic filters (Distort, Render, Stylize, Pixelate variants) | Novelty for the job Colorbee does |
| Layer Comps, Auto-Align / Auto-Blend, HDR merge, focus stacking | Specialist workflows |
| Content Credentials | Needs signing infrastructure and accounts |

---

## 5. Workflows the best additions help

1. **Share a screenshot with people in it.** _Today:_ Auto-Redact hides emails and keys; faces need manual marquees and Blur. _With face redaction:_ open the screenshot, Redact, Auto-Redact; the review sheet lists text matches and faces; untick the one face that is you; Apply; one undo step.
2. **Annotate a bug report with many callouts.** _Today:_ drag each badge and text box and eyeball the alignment; ten layers sit in a flat list. _With guides, Align/Distribute, groups:_ drag two guides from the ruler, snap the callouts to them, choose the five badge layers, right-click, Group, Align Left. Hide the whole group with one eye click when you want the clean screenshot.
3. **Cut a logo or button from a screenshot.** _Today:_ wand with tolerance, ragged edge, Delete. _With Smooth and Contract, or Magic Eraser:_ wand, Contract 1 px, Smooth, Delete. Then Trim removes the empty border.
4. **Keep a retouch non-destructive.** _Today:_ edits go straight into a layer; undo is the only safety net. _With layer masks:_ add a mask, paint black to hide, white to bring back; the pixels underneath are untouched.
5. **Send a photo that must stay under 1 MB.** _Today:_ Export, guess a quality, check the size, repeat. _With Limit file size:_ pick a target in Export, and Colorbee picks the quality. Convert to sRGB in the same dialog so colors look right everywhere.
6. **Fix a flat, hazy photo.** _Today:_ Adjust Photo's sliders. _With the Lightroom additions:_ Auto, then Dehaze and Texture, click a gray wall with the white-balance eyedropper, and nudge just the blues with the HSL mixer.
7. **Check a brand color.** _Today:_ eyedropper, then open the color panel to read the value. _With the readout:_ hover and read RGB and hex in the status bar. Set the sample size to 5x5 to average over anti-aliased edges.
8. **Redact 30 screenshots.** _Today:_ open each, Auto-Redact, review, export. _With batch-apply:_ choose the folder and presets, Colorbee queues them, and you review the findings per image before anything is written. The review stays, because a missed secret is worse than a slow batch.
9. **Whiteboard photo to clean image.** _Today:_ Perspective Correction means dragging four corners. _With auto-detected corners:_ the box lands on the board; you nudge it and press Return.
10. **Try a bold edit safely.** _Today:_ History panel steps. _With Snapshots:_ name "Before dramatic", experiment, and jump back from the panel.

---

## 6. Open questions for you

These are your functional calls. I haven't assumed any answer.

### Leah's answers (2026-10-27)

Recorded here only. Nothing has been added to the FRD §23 or built yet.

| # | Question | Answer | Follow-up |
|---|---|---|---|
| 1 | Text after it's placed | **Make text re-editable** (against my recommendation to keep pixels) | Large change, reverses a classic-Paint FRD decision. Needs design questions first: is text its own layer type, what happens on merge, flatten and export, and can old projects still open? |
| 2 | Layers round 2 | **Select All Layers, isolate (Option-click the eye), Align/Distribute, Stamp Visible and Layer Groups** (with "Group chosen layers" in the right-click menu) | Also **Lock transparent pixels** (Question on layer extras). Click-the-canvas-to-pick-a-layer: not included |
| 2b | Layer masks and clip-to-layer-below | **Yes, as its own later stage** | Large; after round 2 |
| 3 | Batch work | **Rarely or never** | Batch-apply stays on the maybe list |
| 4 | Color spaces on export | **Yes**, with "keep document profile" as the default | Export gets a color-space choice, including sRGB |
| 5 | PSD files | **No** | PSD import dropped |
| 6 | AI | **Revisit with Apple's built-in models only** | Research what macOS offers on-device and bring options |
| 7 | Next/previous picture in a folder | **No** | Dropped |
| 8 | Stroke smoothing | **Yes**, as an optional setting, off by default | Smoothing slider in the palette bar |
| 9 | Vector shapes (Pen, paths) | **Reopen it** | Large change to the product's character. Needs its own discussion (what would be vector, how it fits "a paint program first") |
| 10 | Face redaction | **Inside Auto-Redact's review sheet, all pages** | Faces appear as boxes next to text matches, with the same treatments and one undo step |

1. **Editing text after it's placed.** Colorbee turns text into pixels on purpose ("true to classic Paint"). Photoshop keeps text editable. Do you want that decision reopened? (It would be a large change and would reverse an FRD decision.)
2. **Is "feature-complete" still the rule?** Multi-select layers was an exception. Would you want a small "layers round 2" (groups, Align/Distribute, Select All Layers), or do you want to hold the line on fixes and polish?
3. **Batch work.** Do you ever process many images at once? If yes, should a batch still stop for a review of Auto-Redact findings on every image?
4. **Color management.** Should Export offer sRGB conversion (and other spaces), and should the default stay "keep the document's profile"?
5. **PSD files.** Do you ever receive layered PSDs from design colleagues? That decides whether opening PSD with layers matters.
6. **AI, again.** The FRD says "no AI models for now, not a hard no". Do you want to revisit that, for example with Apple's built-in on-device models only, or leave it closed?
7. **Browsing a folder.** Would "next/previous picture in this folder" be useful, or do you open one file at a time?
8. **Drawing with a trackpad.** Do strokes feel wobbly enough that stroke smoothing is worth building?
9. **Vector shapes.** Confirm that Pen tools and paths stay out, matching "a paint program first".
10. **Face redaction scope.** Should it also find faces in photos and PDF pages, and should it be part of Auto-Redact's review sheet or its own command?

---

## 7. Sources

All checked on **2026-10-27**. Adobe's official Help pages (helpx.adobe.com) refused my automated reader (HTTP 403 on every try), so for some pages I only saw the search snippet, not the full page. I've marked what I read in full and what I didn't.

**Read in full (Adobe's own community announcements)**
- Photoshop Release Notes, August 2026: https://community.adobe.com/announcements-698/release-notes-august-2026-1640387 (Enhance Edge, Stock panel, Relight sliders)
- Photoshop Release Notes, July 2026: https://community.adobe.com/announcements-698/release-notes-july-2026-1638019 (Markup in Prompt to Edit, Dynamic Layer, Gemini 4K, Content Credentials)
- Photoshop Release Notes, May 2026: https://community.adobe.com/announcements-698/release-notes-may-2026-1625212 (on-device Remove tool, distractor detection, Send to Firefly Board)
- Lightroom Classic 15.6 announcement: https://community.adobe.com/announcements-673/lightroom-classic-15-6-is-here-improved-reflection-removal-faster-masking-workflows-and-expanded-camera-lens-support-1644250 (reflection removal, Check All / None, new cameras and lenses)

**Read in full (third-party summaries of Adobe releases)**
- PhotoshopCAFE, What's New in Photoshop 2026: https://photoshopcafe.com/whats-new-in-photoshop-2026-full-release-overview/
- PhotoshopNews, What's New in Photoshop 2026: https://www.photoshopnews.com/2026/04/04/whats-new-photoshop-2026-ai-assistant-generative-updates (Clarity, Dehaze, Grain layers; Generative features; Firefly Boards)
- PhotoshopCAFE, Lightroom Classic 2026 (Lightroom 15): https://photoshopcafe.com/lightroom-classic-2026-new-features-lightroom-15/

**Seen only as search results (not opened in full)**
- Adobe Photoshop on desktop release notes: https://helpx.adobe.com/photoshop/desktop/whats-new/photoshop-on-desktop-release-notes.html (blocked; 27.11 / September 2026 items came from the search summary)
- Adobe Lightroom Classic release notes: https://helpx.adobe.com/lightroom-classic/desktop/introduction-to-lightroom-classic/release-notes.html (blocked; 15.3 to 15.5 items came from the search summary)
- Adobe Lightroom desktop release notes: https://helpx.adobe.com/dk/lightroom/desktop/introduction/release-notes.html (a regional copy; the Cloud notes for 2026 came from the search summary)
- Adobe Lightroom on mobile and web release notes (regional copies, same snippet)

**Things to treat carefully**
- **Version numbers disagree** between sources (some say Photoshop 27.4 in March 2026, another 27.11 in September 2026). I used feature names, not version numbers.
- **The long baseline feature lists** (what Photoshop and Lightroom have always had) come from my own knowledge of the apps, not a page-by-page check, because Adobe's feature pages were blocked. The NEW items are the ones tied to the sources above.
- **Unconfirmed:** "Live Filter Layers" and a "Light" adjustment layer were mentioned in the May announcement's text or comments but not confirmed as released, so I left them out.
- **Colorbee's side** comes from `Docs/FRD.md` (v2.3.0, with the 2026-10-27 decisions) and `Docs/STATUS.md`. A few "Partial" or "Missing" marks (Definition vs Clarity, whether Fill with a transparent color works as a Magic Eraser, whether Crop dims the cut-off area) should be confirmed in the app before anyone builds from this.
