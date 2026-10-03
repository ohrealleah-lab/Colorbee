# Colorbee — Build Status

**Read this first in a new session.** It's the running record of what's built, what isn't, and what's next.
Update it at the end of every stage or significant change, and commit it with that work.

- **What to build:** [FRD.md](FRD.md) (behavior), decision log in FRD §23.
- **How to build it:** [../CLAUDE.md](../CLAUDE.md).
- **What it looks like:** [Design/](Design/) mockups.

_Last updated: 2026-10-02 · 203 core tests passing_

---

## Working agreements with Leah

- Leah is the PM and only user; Claude is the only engineer. Functional decisions are hers: ask, then record the answer in FRD §23.
- **Full scope.** Never propose cutting features to save time. Colorbee is a paint program first; no mind-mapping or structured-diagram features.
- **Say the recommended model and effort before each stage** (Opus throughout; high for design-heavy work, medium for routine UI).
- Log any behavior choices Claude makes on its own in FRD §23, phrased "veto any".
- Prefer plain explanations. Leah tests features by hand and reports back; give her a short "please try" list after each stage.
- Work locally (no cloud sessions: the build needs macOS and Xcode). The repo is public on GitHub at github.com/ohrealleah-lab/Colorbee so employers can see it: keep commits and docs presentable, never commit secrets or personal data, and push after each commit.

## Build order progress (FRD §20)

| Stage | Status | Notes |
|---|---|---|
| 1. Walking skeleton | ✅ Done | Canvas, brush, undo, paste, PNG, benchmark |
| 2. Core model | ✅ Done | Selections, floating selection, history with disk spill, pixel grid |
| 3a. Everyday tools | ✅ Done | Pencil, marker, eraser and color eraser, fill, eyedropper, lasso, blur, pixelate, formats |
| 3b. Editable objects | ✅ Done | Crop, resize handles, 5 shapes plus arrow, text tool |
| 4. Redaction | ✅ Done | Magic wand, batch redact, Auto-Redact, Before/After, export presets |
| 5a. Full toolset (routine) | ✅ Done | All 23 shapes plus rotation, gradient, rotate/flip, symmetry, measure, adjustments, sharpen, D key |
| 5b. Full toolset (hard) | ✅ Done | 6 brushes, pressure, textured shape styles, Resize/Skew |
| **5c. Interface (mockup look)** | ⏭ **Next** | **Opus · high** · toolbar, palette bar, status bar |
| 6. Layers | Planned | **Opus · high** · includes the right sidebar |
| 7. Integration | Planned | Mostly medium; shortcut editor high |
| 8. Hardening | Planned | Medium |
| 9. Photo editing (later phase) | Planned | Mostly medium; Curves and Straighten high |

## What's built

**Document and files**
- NSDocument app: autosave and restore, versions, Open Recent.
- Opens PNG, JPEG, HEIC, TIFF, GIF, BMP and WebP. Saves all of them except WebP (open-only by decision).
- Export… (format and quality), Export As ▸ presets that show exact pixel sizes.
- Color profiles are kept; new documents use Display P3.

**Canvas**
- Metal display with zero-copy layer textures, zoom 12.5–3200%, pan, pinch.
- Pixel grid at 400% and above (⌘'), checkerboard for transparency.
- Rendering pauses while the window is hidden.

**Tools** (key)
- Pencil P · Brush B (all 9: Round, Calligraphy 1 and 2, Airbrush, Oil, Crayon, Marker, Natural Pencil, Watercolor; pressure from a Force Touch trackpad or pen, with a Pressure switch) · Eraser E (square outline pointer; right-drag = Color Eraser) · Fill G (tolerance) · Eyedropper I (Option = all layers)
- Shapes U: all 23 FR-5.1 shapes plus Arrow (gallery menu). Editable until placed: move, handles, rotate handle (box shapes, Shift snaps 15°), outline and fill None, Solid, Crayon, Marker, Oil, Watercolor or Natural Pencil (textured previews draw in the background). Polygon: click corners, close on the first one or double-click. Curve: line, then two bends.
- Gradient: linear, radial, reflected, diamond, conical; right-drag reverses; fades to transparent cleanly.
- Measure R: distance, ΔX/ΔY, angle in the status bar.
- Text T: in-place editing; font, size, B/I/U/S, alignment, opaque or transparent background.
- Rectangle M · Ellipse · Lasso L · Magic Wand W (tolerance, contiguous).
- Symmetry (status bar or Image ▸ Symmetry): mirrors pencil, brush and eraser.
- Keys: X swaps colors, D resets to black/white, [ ] change size, Space-drag pans, arrows nudge, ⌘-arrows resize the outline, Return/Esc place, Delete clears.

**Selections**
- Shift adds, Option subtracts, Shift+Option intersects. Select All, Deselect, Invert.
- Floating selection: move, Option-duplicate, Shift-smear, 8 resize handles (Shift keeps proportions; Smooth or Sharp), transparent-selection mode.
- Copy and Cut work on the selection. Paste floats. Crop to Selection.

**Image and adjustments**
- Image ▸ Rotate (90° CW, 90° CCW, 180°) and Flip (horizontal, vertical): the selection around its center, or the whole image.
- Image ▸ Resize and Skew… (⌘E): by percent or pixels with aspect lock, Smooth or Sharp, skew ±89°; the selection or the whole image.
- Adjustments: Invert ⌘I, Brightness/Contrast, Hue/Saturation, Desaturate ⇧⌘U. Effects ▸ Sharpen. All apply to the selection or the whole layer.

**Effects and redaction**
- Gaussian Blur and Pixelate with live preview (each separate region on its own; edges stay opaque).
- Batch Redact ▸ Blur / Pixelate / Solid Fill.
- Auto-Redact: on-device Vision. Patterns for email, phone, card (checksum), API keys and tokens, IP, URL, plus custom ones (saved). Review sheet. Cyrillic look-alikes folded to Latin.
- Before/After: As Opened or Last Saved, split or side by side.

**History**
- Unlimited undo with tile deltas and a byte budget; older steps compressed to disk.
- Restores the selection with the pixels; geometry changes swap whole buffers.

## Not built yet (by stage)

**5c Interface (high)** (moved up from stage 7 on 2026-10-02)
- Mockup look: unified Liquid Glass toolbar with the Magnifier, 28-swatch palette bar with 12 custom slots, an Alpha slider and Edit Colors… (today's toolbar uses plain color pickers), and a status-bar zoom slider. Biggest visual gap versus the mockups.

**6 Layers (high)**
- The right sidebar (FR-1.3), starting with the Layers panel.
- Model supports layers; there's no UI yet. Layers panel, add/duplicate/delete, merge down/visible, flatten, lock, hide, opacity.
- 17 blend modes.
- Adjustment layers. Undo on Active Layer (⌘⌥Z), Revert Layer.
- `.colorproj` format.

**7 Integration**
- Canvas Properties (⌘⌥E: size, transparent background). Paste into New Image (⇧⌘V). Offer to enlarge the canvas for large pastes.
- Clipboard History, History panel (⌘Y), palettes, text styles.
- Settings window: shortcut editor (FR-15.3), editing export presets, screenshot watcher setting.
- Finder "Open in Colorbee", screenshot folder watcher, Share, Print, Set as Desktop Picture, rulers.
- Auto-Redact: numbers on the canvas highlights (the mockup has them).

**8 Hardening**
- 8000×8000 soak tests (AC-27), performance baselines, polish, accessibility labels.

**9 Photo editing and presentation (later phase, FR-9.5)**
- Adjustments: Levels (with Auto), Auto Contrast, Curves, White Balance, Vibrance, Sepia, Posterize.
- Effects: Add Noise, Motion Blur, Emboss, Vignette, Drop Shadow, Border, Spotlight (shadow and border follow the object's shape).
- Image ▸ Straighten… (any angle, or draw along the horizon; Crop to Fit).
- The photo adjustments also come as adjustment layers.

## Not yet checked by hand

Leah tested everything through stage 5a by hand on 2026-10-01, and the 2026-10-02 fixes the same day: Shift-pencil axis lock, eraser outline and sizes, zoom menu and ⌘-scroll, docked effect bar, slider tick marks, cancelling a half-drawn selection, and mid-drag edge cases. 
Stage 5b tested by hand on 2026-10-02, including trackpad pressure. Nothing outstanding.

## Practical notes for the next session

- Use `make run` (Release) for anything Leah tries; Debug pixel loops are about 50× slower.
- `make bench` brings windows to the front. Ask Leah first.
- Computer-use can't drive Colorbee while another app is frontmost (menus are disabled, canvas clicks are ignored). Don't take over the screen; ask Leah instead.
- A Colorbee launched from Xcode (DerivedData) shares the bundle ID with ours, so the computer-use tool may attach to that copy. Never kill Leah's copy.
- Launch test copies with `-ApplePersistenceIgnoreState YES` so they don't restore old windows.
- Xcode 26 needs the Metal Toolchain component (already installed on this Mac).
- Trackpad pressure arrives only in `pressureChange` events (drag events always say 1.0), and only when System Settings ▸ Trackpad ▸ Force Click and haptic feedback is on. Leah turned it on 2026-10-02. Each brush stroke logs its pressure range: `/usr/bin/log show --last 10m --predicate 'subsystem == "com.leah.Colorbee"' | grep pressure` (plain `log` is a zsh builtin).
