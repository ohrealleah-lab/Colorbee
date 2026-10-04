# Colorbee — Build Status

**Read this first in a new session.** It's the running record of what's built, what isn't, and what's next.
Update it at the end of every stage or significant change, and commit it with that work.

- **What to build:** [FRD.md](FRD.md) (behavior), decision log in FRD §23.
- **How to build it:** [../CLAUDE.md](../CLAUDE.md).
- **What it looks like:** [Design/](Design/) mockups.

_Last updated: 2026-10-03 · 272 core tests passing, plus `make perf`_

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
| 5c. Interface (mockup look) | ✅ Done | Glass toolbar, palette bar with wells and custom colors, status bar with zoom slider, Magnifier |
| 6a. Layers | ✅ Done | Layers panel, Layer menu, 17 blend modes, lock, opacity, merges, Copy Merged |
| 6b. Adjustment layers, per-layer undo, .colorproj | ✅ Done | Adjustments panel, Undo on Active Layer, Revert Layer, .colorproj |
| 7a. Integration: canvas, clipboard, history, sharing | ✅ Done | Medium |
| 7b. Palettes, text styles, Settings, Finder | ✅ Done | Medium |
| 7c. Shortcut editor | ✅ Done | **High** |
| 8. Hardening | ✅ Done | Medium |
| 9. Photo editing | ✅ Done | High |

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

**Layers** (stage 6a)
- Right sidebar with the Layers panel (⌘L or the toolbar's Layers button, which shows the count): blend mode, opacity, eye, padlock, thumbnails, drag to reorder, double-click to rename, add/duplicate/delete/merge down.
- Layer menu: New ⇧⌘N, Duplicate ⌘J, Delete ⌘⌫, Merge Down ⇧⌘E, Merge Visible ⌥⇧⌘E, Flatten, Hide/Show, Lock/Unlock, Layer Properties…. Edit ▸ Copy Merged ⇧⌘C.
- 17 blend modes (W3C math in `BlendMode.swift`, mirrored in `Shaders.metal`); layers composite off screen in half floats. Exports use the same math.
- Locked layers refuse pixel changes (beep, 'not allowed' pointer). All layer changes are undo steps (whole-stack snapshots, buffers swapped not copied).
- Adjustment layers (stage 6b): Brightness/Contrast, Hue/Saturation, Desaturate, Invert, Gaussian Blur, Sharpen; edited in the Adjustments panel; Apply Adjustment. Display: point adjustments in the blend shader, Blur/Sharpen via MPS mid-pass with edge renormalization.
- Undo on Active Layer ⌥⌘Z (`History.undoOnLayer`), Revert Layer (pixel copies kept at each explicit save).
- `.colorproj` (`ProjectFile`): JSON manifest + LZ4 exact pixels + ICC. Layered images save as projects; Save As offers only .colorproj for them; Export makes flat copies.

**Integration** (stage 7a)
- Canvas Properties ⌥⌘E (size, transparent background) and edge handles on the canvas; Paste into New Image ⇧⌘V; big pastes offer to enlarge the canvas.
- Sidebar panels: History ⌘Y (steps with thumbnails, click to jump) and Clipboard History ⌥⌘V (last 10, persistent, click to paste).
- Drag and drop images onto the canvas or the window; File ▸ Share…, Set as Desktop Picture, Page Setup, Print ⌘P; View ▸ Show Rulers ⌘R, Hide Status Bar.

**Integration** (stage 7b)
- Palettes (palette bar menu: switch, save, rename, delete, import/export `.colorpalette`, reset); text styles (text tool's Styles menu).
- Settings window ⌘, : editable Export As presets (screenshot folder watching was built, then removed at Leah's request).
- Finder: Services ▸ Open in Colorbee. Auto-Redact numbers on the canvas.

**Shortcuts** (stage 7c)
- Settings ▸ Shortcuts: every menu command and canvas key, grouped, searchable; click to record; Esc cancels, Delete clears; reset one or all; `.colorbeekeys` import/export.
- `ShortcutBook` (core) holds the rules; `ShortcutStore` (app) reads the menu bar, applies changes to it live, routes canvas keys, and reads System Settings shortcuts (`SystemShortcuts`).

**Interface** (mockup look, stage 5c)
- Window toolbar in Liquid Glass capsules: selection tools + Transparent Selection; Pencil, Fill, Text, Eraser, Eyedropper, Magnifier, Gradient, Measure; Brushes ▾ and Shapes ▾ galleries; Size (5 presets + px field); Outline/Fill.
- Palette bar: color wells (ring = which one swatch clicks set; double-click to pick), 28 classic swatches, 12 custom slots (double-click empty to pick, Control-click to remove, kept between launches), Alpha, Edit Colors…, Paint Classic menu (palettes come in stage 7), then the tool's own settings.
- Status bar: pointer, selection, measurement, canvas size, Pixel Grid and Symmetry switches, log-scale zoom slider, − % +.

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
- Unlimited undo with tile deltas and a byte budget; older steps compressed to disk on all cores.
- Restores the selection with the pixels; geometry changes swap whole buffers; rotations and flips undo by turning back.
- Layers only history holds (merged, flattened, deleted) count against the budget and are written to disk, then read back into the same buffer objects (`PixelBuffer.discardContents`, `generation`).

**Hardening** (stage 8)
- Whole-image work on all cores (`ParallelRows`): compositing, adjustment layers, point effects, pixelate, spill compression; vImage for rotate and flip; word-skipping scanline fill.
- Save and Export encode a `SaveSnapshot` in the background (`ImageDocument.canAsynchronouslyWrite`).
- `make perf`: Release-only time limits at 1080p (NFR-6) and 8000 × 8000, and the soak test (AC-27; `COLORBEE_SOAK_MINUTES=30` for NFR-7).
- `-ColorbeeSaveCheck YES [-BenchmarkCanvas N]`: background launch that saves a PNG and reports time, the longest main-thread pause and memory.
- VoiceOver labels for the canvas, color wells, swatch grid and icon buttons.
- `make beta` (`Scripts/make-beta.sh`): Developer ID signing, hardened runtime, notarization, stapling, zip with `Docs/Beta/Start Here.txt`. Version 0.9.0.

## Not built yet (by stage)

**8 Hardening**
- The 30-minute soak (NFR-7) and a fresh `make perf`, **only when Leah says the Mac is free**: on 2026-10-03 the 30-minute soak drove the Mac into heavy swap and its test process set off a macOS kernel panic. Freeing history's layer memory now uses `madvise` (as the system allocator does) instead of remapping it; the heavy runs re-check that.
- Beta 0.9.0 (1) built, notarized and stapled on 2026-10-03 (`build/Beta/Colorbee-0.9.0-1.zip`, 1.8 MB); Gatekeeper accepts it as "Notarized Developer ID". Leah's `colorbee-notary` keychain profile is set up. Bump `CURRENT_PROJECT_VERSION` in project.yml for each new beta.
- Polish done 2026-10-03: effect previews in the background (`EffectPreview`), Copy in the background (`ClipboardImage`). Tested by hand 2026-10-03.

**9 Photo editing and presentation (FR-9.5)** — done; tested by hand 2026-10-03.
- 9a tone adjustments and effects (`Levels`, `Curves`, `Histogram`, `ColorLookup`, `Effects+Texture`); 9b Adjust Photo, Auto and filters (`PhotoAdjustments`, `PhotoAuto`, `PhotoFilter`, `FilterStore`, `adjust_photo_fragment`); 9c Drop Shadow, Border, Spotlight (`Decorations`); 9d Straighten, Perspective Correction, Crop… (`Warp`, `CropBox`, `CropOptions`, canvas-tool drags in `CanvasView`); 9e Remove Background, Lift Subject, Select Subject (`Subjects`, Vision instance masks).
- Practice images: `TestImages/Stage 9 Practice Photo.png`, `Stage 9 Practice Cutout.png` (Vision finds the circle and the star).
- The original stage 9 plan, now built:
- Adjustments: Levels (with Auto), Auto Contrast, Curves, Sepia, Posterize.
- Adjust Photo panel: 15 iPhone-style sliders (White Balance and Vibrance live here), Auto, and filters (9 built in, custom ones saved, shared as .colorbeefilter, intensity).
- Effects: Add Noise, Motion Blur, Emboss, Vignette, Drop Shadow, Border, Spotlight (shadow and border follow the object's shape).
- Image ▸ Straighten… (any angle, or draw along the horizon; Crop to Fit), Perspective Correction…, Crop… with aspect and pixel-size presets.
- Subject (on-device Vision): Remove Background, Select Subject.
- The photo adjustments, Adjust Photo and filters also come as adjustment layers. Clean Up is out of scope.

## Soak re-run pending (AC-27)

Second 30-minute soak (2026-10-04, 78 rounds, log in `build/soak-results.txt`): undo and redo were never over a
second (206 times before), but it failed two ways, both fixed the same day:

1. **Undo or redo not exact in 6 rounds.** A flip or rotation gave every layer a new buffer object, so a
   layer-settings step made before it (a blend mode change, say) put back a buffer that later edits had
   changed. Rotations and flips now turn the pixels inside the same buffer (`PixelBuffer.swapContents`).
   Reproduced at 256 × 256 (19 of 400 rounds failed, with or without spilling); now 0 of 1,000 at three
   budgets. `TransformIdentityTests`.
2. **98 editing steps just over a second** (Flatten 31, Brush 47). Round 2's floating-selection compositing
   checked every pixel of every layer; split into plain loops, a 4000 × 4000 five-layer flatten went from
   0.26 s to 0.09 s. Brush steps were already over a second 17 times in the first soak; check them in the re-run.

Needs one more soak (with Leah's OK, about 35 minutes) before AC-27 is ticked.

## Not yet checked by hand

**Round 3 fixes (reviews H, I and J, 2026-10-04), not yet tried by hand.** See `Docs/Review/RESULTS.md`. Most worth trying:
- Save a redacted file: the earlier-versions warning. Paste a screenshot (⇧⌘V), Auto-Redact: the offer to remove it from Clipboard History. Right-click a Clipboard History item: Remove.
- Batch Redact with an empty layer active: the layer below is redacted.
- File ▸ Revert To Saved: the window shows and keeps editing the reverted image.
- Open an animated GIF: an untitled copy with the frame bar; Choose Frame…. An iPhone portrait photo opens upright.
- Symmetry with the round brush and the eraser near the center line; the Color Eraser tolerance; Sample All Layers.
- ⌘V, then W or P from the keyboard: the tool changes. ⌘⌫ while typing text deletes text.
- Settings ▸ Shortcuts: give Undo ⌘I, give Pencil Space, clear ⌘Z.
- Quit and relaunch with a zoomed-in window and History open: they come back.

Earlier: the cloud review fixes (rounds 1 and 2, `Docs/Review/RESULTS.md`), the greyed-out
pixel commands, the shape colour swatches and layer dragging were tested by hand by Leah on 2026-10-04.

Leah tested everything through stage 5a by hand on 2026-10-01, and the 2026-10-02 fixes the same day: Shift-pencil axis lock, eraser outline and sizes, zoom menu and ⌘-scroll, docked effect bar, slider tick marks, cancelling a half-drawn selection, and mid-drag edge cases. 
Stage 5b tested by hand on 2026-10-02, including trackpad pressure. Stage 6a tested by hand on 2026-10-03. Stage 6b tested by hand on 2026-10-03. Stage 7a tested by hand on 2026-10-03. Stage 7b tested by hand on 2026-10-03, including the Auto-Redact box fix. Stage 7c tested by hand on 2026-10-03. Stage 8 tested by hand on 2026-10-03. Stage 9 tested by hand on 2026-10-03 (fixes: saved filters applied twice, Spotlight without a selection, clipboard screenshots, zoom after geometry tools). Stage 5c tested by hand on 2026-10-03 with `TestImages/Stage 5c Practice.png`, plus text box fixes (handles, opaque background width, italic overhang, selection highlight).

## Practical notes for the next session

- Use `make run` (Release) for anything Leah tries; Debug pixel loops are about 50× slower.
- `make bench` brings windows to the front. Ask Leah first.
- Computer-use can't drive Colorbee while another app is frontmost (menus are disabled, canvas clicks are ignored). Don't take over the screen; ask Leah instead.
- A Colorbee launched from Xcode (DerivedData) shares the bundle ID with ours, so the computer-use tool may attach to that copy. Never kill Leah's copy.
- Launch test copies with `-ApplePersistenceIgnoreState YES` so they don't restore old windows.
- To check layout without taking over the screen: `open -g -n -W -a "$PWD/build/Build/Products/Release/Colorbee.app" --args -ApplePersistenceIgnoreState YES -ColorbeeSnapshot /path/out.png` (options: `-ColorbeeSnapshotDark YES`, `-ColorbeeSnapshotTool shape`, `-ColorbeeSnapshotEdited YES`). It can't draw Liquid Glass or the Metal canvas, so ask Leah for screenshots of those. Screen capture of other windows needs Screen Recording permission; don't ask for it.
- Commit only after `make test` and the Release build both succeed. Run `make perf` after touching pixel loops, history or effects.
- `make beta` uses Leah's signing key and notary profile: ask her before running it (macOS may ask for her keychain password).
- Xcode 26 needs the Metal Toolchain component (already installed on this Mac).
- Trackpad pressure arrives only in `pressureChange` events (drag events always say 1.0), and only when System Settings ▸ Trackpad ▸ Force Click and haptic feedback is on. Leah turned it on 2026-10-02. Each brush stroke logs its pressure range: `/usr/bin/log show --last 10m --predicate 'subsystem == "com.leah.Colorbee"' | grep pressure` (plain `log` is a zsh builtin).
