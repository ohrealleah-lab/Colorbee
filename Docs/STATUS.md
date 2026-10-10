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
| 10a. Pages | ✅ Done | High |
| 10b. PDF output, Auto-Redact on every page | ✅ Done | High |
| 11. Import from iPhone or iPad | Decided, to build later | High (trial build), then medium |
| 12. RAW photos | ✅ Done | High |
| Help (FR-14.6) | Phases 1 and 2 built: the help book, ⌘?, search, screenshots, Getting started and Redact a screenshot | Medium (phase 6 high) |

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
- Beta 0.9.0 (2) built, notarized and stapled on 2026-10-05 (`build/Beta/Colorbee-0.9.0-2.zip`, 2.7 MB): pages and PDFs, RAW photos, review round 4, Appearance, scrubbing. "Start Here.txt" updated.
- GitHub Actions (`.github/workflows/build-release.yml`, like Honeycomb's): every push builds and runs the tests on a macOS 26 runner. A tag `vX.Y.Z-beta.N` also signs, notarizes and publishes the zip as a pre-release (version X.Y.Z, build N). Needs five repo secrets, the same as Honeycomb's: `APPLE_CERT_P12`, `APPLE_CERT_P12_PASSWORD`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`, `APPLE_API_KEY_P8` (all set 2026-10-05). On GitHub's runner the tests run one at a time; side by side they stalled. First release: v0.9.0-beta.2, published 2026-10-05, checked as "Notarized Developer ID". Next beta: push the tag `v0.9.0-beta.3`.
- Polish done 2026-10-03: effect previews in the background (`EffectPreview`), Copy in the background (`ClipboardImage`). Tested by hand 2026-10-03.

**Later, from review round 4:** switching pages compresses the old page and expands the new one on the main thread
(L15); on very large pages (8000 × 8000 with layers and a long history) a switch can pause for a second.

**12 RAW photos (FR-11.8)** — done; tested by hand 2026-10-05. Built: `RawDeveloper` (macOS's RAW engine, CIRAWFilter), the Develop
window (`DevelopWindow`), `DocumentController` (sends RAW files to it), `CameraDetails` (core, kept in .colorproj),
and Include camera details in Export…. Test file: `TestImages/Stage 12/Test Camera.dng`, a synthetic DNG with
made-up camera details, serial number, owner and GPS location (made by a small script, not a real photo).

**11 Import from iPhone or iPad (FR-11.7)** — decided 2026-10-04, to build later (Leah). Start with the trial
build in `Docs/Proposals/Import from iPhone.md`; Leah scans on her iPhone.

**10 Pages and PDF documents (FR-11.6)** — done; tested by hand 2026-10-04. Decisions in §23.
- 10a built 2026-10-04: pages in core (`Page`, `PageStack`, project format 2, `PDFPages`), the page sidebar (`PageSidebar`), the Page menu, and PDFs, multi-page TIFFs and animated GIFs opening with every page. The frame bar is gone.
- 10b built 2026-10-04: File ▸ Export as PDF… (`PDFWriter`, hand-written so it has no metadata), Auto-Redact on every page (`AutoRedactSession.pages`), and the PDF resolution setting (now in Settings ▸ General).

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

## AC-27: done (2026-10-04)

Five 30-minute 8000×8000 soaks. The fifth ran 108 rounds with no crash and exact undo and redo; 13 of about
6,500 steps went a little over a second (whole-image Flatten, Sharpen, Blur; worst 1.7 s). Leah accepted that
(§23). Fixed along the way: redo after spilled crops, flips and rotations giving layers new buffers, slow undo
(parallel fingerprints), Flatten compositing, and replaced layers written out in the background on one core.
Logs in `build/soak-results*.txt` (not committed).

**Done 2026-10-04 (agreed with Leah): all 7 steps passed Leah's hand test on 2026-10-04.**
1. **API key.** Open `~/Downloads/colorbee tests/E1 Screenshot.png`, Effects ▸ Auto-Redact…: the list has the `sk test _FAKE…` key, and its orange box covers the whole key. Solid Fill, Apply: all of it is black.
2. **Batch Redact preview.** Open E1 Screenshot.png, Layer ▸ New Layer, marquee around the email, Effects ▸ Batch Redact ▸ Blur…: the email blurs as you drag the Radius slider. Apply: it stays as previewed. Cancel instead: everything comes back.
3. **Batch Redact on a locked layer.** Lock Background, marquee the email, Batch Redact ▸ Pixelate…: a message names "Background" and the bar doesn't open.
4. **Clipboard cleared too.** Open E1 Screenshot.png in Preview, ⌘A, ⌘C. In Colorbee, ⇧⌘V, Auto-Redact, Solid Fill, Apply, then choose Remove. Press ⌘V in TextEdit or Colorbee: nothing is pasted. Repeat, but copy some text in TextEdit before choosing Remove: that text is still on the clipboard.
5. **Undo history cleared.** Duplicate E1 Screenshot.png in Finder and open the copy. Auto-Redact, Solid Fill, Apply, ⌘S. Choose "Remove Earlier Versions and Undo History". Edit ▸ Undo is greyed out, the History panel (⌘Y) shows only "Opened", and View ▸ Before/After with As Opened shows the redacted image.

6. **Warning on close.** Duplicate E1 Screenshot.png and open the copy. Auto-Redact, Solid Fill, Apply, then press ⌘W (no ⌘S). Expect the earlier-versions message before the window closes; either button closes it. Reopen the file: the redaction is there.
7. **Warning on quit.** Open two duplicated copies of E1 Screenshot.png, Auto-Redact each (Solid Fill, Apply), then ⌘Q. Expect the message on each window in turn; after the second answer, Colorbee quits. Reopen both: the redactions are there.

## Not yet checked by hand

**Help, phase 2 (2026-10-09): all 5 steps passed Leah's hand test on 2026-10-09.** Rebuild and run with the script first, then follow each guide exactly as
written on a clean launch, using `TestImages/Help/Sample Screenshot.png` (made-up details). Every step should work and
every menu name and key should match; note anything unclear.
1. Help ▸ Colorbee Help: the contents page lists **Getting started** and **Redact a screenshot**.
2. **Getting started:** read it with Colorbee open beside it. Check the toolbar, palette bar, key table, undo, sidebar and Settings descriptions against the app. Try the Magic Wand Option-click tip.
3. **Redact a screenshot:** open the sample in Preview, ⌘A ⌘C, then follow the guide from step 2 (File ▸ Paste into New Image) through Auto-Redact, Batch Redact, Before/After and the Clipboard History offer.
4. In the Help menu's search field type "redact": Redact a screenshot is listed. Type "keys": Getting started is listed.
5. Switch Colorbee to Dark (Settings ▸ General): both pages and their pictures read well.

**Help, phase 1 (2026-10-09): screenshots taken by Leah on 2026-10-09 (step 5); steps 1–4 not yet tested.** Plan: `Docs/HELP-PLAN.md`. Rebuild and run with the script first.
1. Help ▸ Colorbee Help: Apple's help viewer opens on a "Colorbee Help" page saying the guide is coming soon.
2. Press ⌘? from anywhere in Colorbee: the same page opens.
3. Click the Help menu and type "colorbee" in its search field: "Colorbee Help" is listed under Help Topics.
4. Turn on dark mode (Colorbee ▸ Settings ▸ General ▸ Dark, or your Mac's): the help page is readable, light text on dark.
5. **Screenshots (when the Mac is free, about five minutes).** In Terminal, in the Colorbee folder, run `make help-shots`. For each of the 9 scenes, Colorbee opens set up for it: take the picture as Terminal says (⌃⇧4, then Space, then Option-click the window; or ⌃⇧4 and drag a box for the toolbar and palette bar), then press Return. The script takes the picture from the clipboard. At the end, `Help/Colorbee.help/Contents/Resources/en.lproj/images/` has window.png, toolbar.png and the others, in light mode, with only made-up content.

**Toolbar: Brushes and Shapes with the drawing tools (2026-10-05): passed Leah's hand test on 2026-10-05.** Any image.
1. The toolbar's second group reads Pencil, Brushes, Shapes, Fill, Text, Eraser, Eyedropper, Magnifier, Gradient, Measure, and the Size box sits in its own group next to it.
2. Click Brushes and Shapes: their galleries open as before, and choosing one picks that tool.

**Palette bar tidy-up (2026-10-05): passed Leah's hand test on 2026-10-05.** Any image.
1. The palette bar has no Edit Colors… button and no palette menu: after the Alpha percentage comes a divider and the tool's own settings.
2. Double-click Color 1: the Mac color picker opens, and choosing a color changes Color 1. The same for Color 2.
3. Double-click an empty custom-color slot: the picker opens for that slot.

**Review round 4, batch C (2026-10-05): all 4 steps passed Leah's hand test on 2026-10-05.** Files: `TestImages/Stage 10/Three Page Test.pdf`,
`TestImages/Stage 6b Practice.colorproj`, `TestImages/Stage 12/Test Camera.dng`, `TestImages/Stage 5a Practice.png`,
and one of your own large RAW files (the Nikon NEF in Downloads).
1. **Drops open like File ▸ Open (L8).** Open Stage 5a Practice.png. From Finder, drag Three Page Test.pdf onto the **image itself**: a new window opens with 3 pages (nothing is pasted). Drag Stage 6b Practice.colorproj onto the window: it opens. Drag Test Camera.dng onto the image: the Develop window appears. Drag any PNG onto the image: it's still pasted as a floating selection; onto the gray area: it opens as a new image.
2. **Services (L8).** In Finder, right-click Three Page Test.pdf ▸ Services: "Open in Colorbee" is listed (macOS may need it switched on once in System Settings ▸ Keyboard ▸ Keyboard Shortcuts ▸ Services).
3. **Develop's Cancel (L9).** Open your large RAW file, press Open, and while "Developing…" shows press Esc (or click Cancel): the window closes and no photo opens.
4. **Reorder a long document (L13).** Make a PDF of 20 or more pages (as in batch B's step 5). Drag the thumbnail of page 15 up to the top of the sidebar and hold it there: the list scrolls up. Let go near the top: it becomes page 1 (or wherever you let go).

**Review round 4, batch B (2026-10-05): all 5 steps passed Leah's hand test on 2026-10-05 (4 and 5 after a second fix).** Use `TestImages/Stage 10/Three Page Test.pdf`.
1. **As Opened for pages not yet shown (K4).** Open the PDF and stay on page 1. Effects ▸ Auto-Redact…, Solid Fill, Apply (don't click any row). Click thumbnail 3, then View ▸ Before/After with As Opened: the left side shows the email and phone, the right side the black boxes.
2. **Revert Layer after a save (L12).** Open the PDF and ⌘S it as "Revert Test". Auto-Redact, Solid Fill, Apply. Click thumbnail 2, then Layer ▸ Revert Layer: page 2's email and phone come back as saved.
3. **Undo Delete Page keeps As Opened (L10).** Open the PDF, go to page 2, draw a line. Page ▸ Delete Page, then ⌘Z. View ▸ Before/After, As Opened: the left side has no line.
4. **One page keeps its size (K6; fixed again 2026-10-05: the one-page save path didn't record it).** Open the PDF, delete pages 2 and 3, Layer ▸ New Layer (so it saves as a project), ⌘S as "One Page", close and reopen it. File ▸ Export as PDF…: in Preview, Tools ▸ Show Inspector, the page is 8.5 × 11 in.
5. **Memory with many pages (K3, L4, L5, L7; fixed again 2026-10-05: each visited page kept a second compressed copy).** Make a long PDF: open Three Page Test.pdf in Preview, drag its thumbnails in a few more times until it has about 30 pages, File ▸ Export as PDF. In Colorbee's Settings ▸ General choose 300 DPI, open it, and watch Colorbee in Activity Monitor's Memory tab: opening doesn't spike to gigabytes; clicking through every page grows memory only a little per page; deleting pages (drawing something after each delete) lets memory go back down. Set 200 DPI again afterwards.

**Review round 4, batch A (2026-10-05): all 6 steps passed Leah's hand test on 2026-10-05.** Files: `E1 Screenshot.png` from `~/Downloads/colorbee tests/`,
`TestImages/Stage 10/Three Page Test.pdf`, `TestImages/Stage 12/Test Camera.dng`.
1. **Unplaced shapes are saved (K1).** Open E1 Screenshot.png. Shapes tool, Rectangle, Fill Solid, Color 1 black. Drag a box over the email and don't press Return. File ▸ Export…, PNG, save; open it in Preview: the box is there. Do it again and press ⌘C instead, then in Preview File ▸ New from Clipboard: the box is there.
2. **Unplaced text is saved.** Text tool, click on the image, type SECRET and don't click away. ⌘S (save a copy somewhere): reopen it, SECRET is in it.
3. **Commands wait behind sheets (L2).** Open Three Page Test.pdf, Effects ▸ Auto-Redact…: in the File menu, Save, Export…, Export as PDF… and Share… are greyed out. Cancel: they're back. The same with an effect bar open (Effects ▸ Gaussian Blur…).
4. **History panel stays on the page (L1).** In the PDF, Pencil: draw a red line, then a blue one, on page 1. Page ▸ New Page, then click thumbnail 1. ⌘Y, click "Opened": both lines go, and there are still 4 pages.
5. **Autosave keeps everything (L3, L11).** File ▸ New, Image ▸ Canvas Properties… with a transparent background, draw something. ⌘S, choose JPEG, then Cancel. Wait about 30 seconds, quit and reopen Colorbee: the window comes back with the checkerboard still showing (not white). Then open Test Camera.dng, press Return, quit and reopen: the "Test Camera" window comes back, and File ▸ Export… still offers Include camera details.
6. **Copies are offered for removal (K11).** Open E1 Screenshot.png, ⌘C with nothing selected. Effects ▸ Auto-Redact…, Solid Fill, Apply: Colorbee offers to remove the unredacted image from Clipboard History. Choose Remove: it's gone from the Clipboard History panel (⌥⌘V), and ⌘V in another app pastes nothing.

**Scrubbing number fields (2026-10-05): all steps passed Leah's hand test on 2026-10-05 except 3, fixed again, to test.** Any image, for example `TestImages/Stage 5a Practice.png`.
1. **Size.** Choose the Brush. Hover over the size box in the toolbar (the "px" field): the pointer is an up-down arrow. Press and drag **down**: the number climbs, about 1 for every 3 points; drag up: it falls. It stops at 50 and at 1, and turns around straight away.
2. **Shift.** Drag down holding Shift: it moves 5 times as fast.
3. **Still typeable (fixed again 2026-10-05: the toolbar's Size box now gets the click itself).** Click the size box without dragging: the cursor goes in, and you can type a number and press Return.
4. **Eraser.** Choose the Eraser and drag the size down: it goes to 100.
5. **Alpha.** Drag up on the "100%" box in the palette bar: Alpha goes down, and the slider follows; drag down to bring it back up.
6. **Tolerances.** With Fill, Magic Wand and the Eraser (Color Eraser), drag on the tolerance percentage: it changes 1% at a time, 5% with Shift.
7. **Font size (fixed 2026-10-05).** With the Text tool, click on the image and type a few words. Drag on the font size box: the size changes (6 to 500) and the text updates as you drag. Then keep typing: the words go into the text box. Click the font size box without dragging: you can type a size and press Return.

**Export… panel clicks (fixed 2026-10-05): passed with the stage 12 tests on 2026-10-05.** Its Format menu and the controls below it showed but
only the keyboard reached them. Use `TestImages/Stage 12/Test Camera.dng` (open it, press Return in Develop).
1. File ▸ Export…: click the Format menu with the mouse and choose JPEG. A Quality slider appears; drag it with the mouse.
2. Click Format, choose TIFF: Compression appears; click it and choose None.
3. Click Format, choose PNG: Quality and Compression go away, and **Include camera details** shows; click the box (or its label) to check it, and again to uncheck it.
4. Choose BMP: the camera details box goes away. Back to PNG, check the box, Save. In Preview's Inspector (ⓘ, EXIF) the PNG shows Test Camera and ISO 400.

**Remembered file formats (2026-10-05): all 5 steps passed Leah's hand test on 2026-10-05.** Any images will do, for example `TestImages/Stage 5a Practice.png`.
1. **Save remembers.** File ▸ New, then ⌘S: choose JPEG in File Format and save it as "Format Test" on the Desktop. File ▸ New again, ⌘S: the panel starts on JPEG. Cancel.
2. **A file keeps its own format.** Open Stage 5a Practice.png, File ▸ Save As…: the panel starts on PNG. Cancel.
3. **Layers still save as a project.** File ▸ New, Layer ▸ New Layer, ⌘S: Colorbee Project. Cancel. File ▸ New (no layers), ⌘S: still JPEG.
4. **Export… remembers separately.** In any image, File ▸ Export…: choose JPEG, Quality 70, export. Export… again: JPEG at 70. Choose TIFF with Compression None, export; Export… again: TIFF, None. A new image's ⌘S still starts on JPEG.
5. **After a relaunch.** Quit and reopen Colorbee: ⌘S on a new image starts on JPEG, and Export… on TIFF, None.

**Stage 12 RAW photos (2026-10-05): all 11 steps passed Leah's hand test on 2026-10-05.** Use `TestImages/Stage 12/Test Camera.dng`, then some of
your own RAW files (CR3, ARW, NEF or RAF) and an iPhone photo (JPEG or HEIC).
1. **Develop window.** File ▸ Open the DNG. A "Develop — Test Camera.dng" window shows the photo (a sky, a white sun, four colored squares) and, along the bottom, "Test Camera · Test Lens 50mm F2.8 · ISO 400 · 1/125 s · f/2.8 · 50 mm · 600 × 400". Temperature reads 6502 K. Noise Reduction, Sharpness and Lens Correction are greyed out for this file, labels included, with "Greyed-out controls aren't available for this photo." under them, and dragging those sliders does nothing (fixed 2026-10-05: the labels looked usable).
2. **Highlights.** Drag Exposure to +1: everything brightens. Drag Highlights to −100: the white sun turns gray again and the sky darkens, as bright detail comes back.
3. **Reset.** Click Reset to Camera: every control goes back, and the button greys out.
4. **Color.** Drag Temperature down to about 3500 K: the photo turns bluer. Tint to +100: it turns pinker. Reset to Camera.
5. **Open.** Set Exposure to +0.5, press Return. A new window "Test Camera", Edited, shows the developed photo (Rectangle Select chosen). ⌘S asks where to save; the DNG is never changed.
6. **Cancel.** Open the DNG again and press Esc (or Cancel, or the close button): nothing opens.
7. **Camera details on export.** In the developed photo, File ▸ Export…, PNG: there's an "Include camera details" switch, off. Turn it on and save. Open the PNG in Preview, Tools ▸ Show Inspector, then the ⓘ tab's EXIF (and TIFF) sections: Test Camera, the lens, ISO 400, f/2.8 and 1/125 s, and no GPS section. Export again with the switch off: no EXIF or TIFF camera details. Choose BMP in Export…: the switch disappears.
8. **Other ways in.** Drag the DNG onto Colorbee's Dock icon, and onto the gray area of a Colorbee window: the Develop window each time. File ▸ Open Recent lists the DNG.
9. **Your own RAW files.** Open a CR3, ARW, NEF or RAF: the Develop window shows your camera and lens, and Noise Reduction and Sharpness work (Lens Correction too, if macOS knows the lens). Open takes a few seconds for a big file. Then try Curves or Adjust Photo on it.
10. **Phone photos.** Open an iPhone JPEG or HEIC (no Develop window), then File ▸ Export…: "Include camera details" is offered.
11. **Kept in projects.** Add a layer to the developed photo, ⌘S as a .colorproj, close and reopen it: File ▸ Export… still offers "Include camera details".

**Appearance setting (2026-10-04): all 7 steps passed Leah's hand test on 2026-10-05.** Use `TestImages/Stage 10/Three Page Test.pdf` or any image.
1. **The General tab.** Colorbee ▸ Settings… (⌘,): the tabs are General, Shortcuts and Export Presets, and it opens on General. Appearance shows System | Light | Dark with System chosen, and "Open PDFs at" is below it.
2. **Dark at once.** With a document open, choose Dark. The document window (toolbar, palette bar, page sidebar, status bar and the gray around the image) and the Settings window turn dark straight away. The image itself doesn't change.
3. **Light at once.** Choose Light: everything turns light straight away, even if your Mac is in Dark mode.
4. **Sheets.** With Dark chosen, open Effects ▸ Auto-Redact…: the sheet is dark too. Cancel.
5. **Remembered, no flash.** With Dark chosen, quit and relaunch Colorbee: the first window opens dark, with no flash of light first.
6. **System follows macOS live.** Choose System. In System Settings ▸ Appearance, switch your Mac between Light and Dark: Colorbee follows each time, without a relaunch.
7. **Last tab remembered.** Click Shortcuts, close Settings, reopen it: it's still on Shortcuts.

**Stage 10b PDF output and Auto-Redact on every page (2026-10-04): all steps (1–9, 9a), and the Rectangle Select starting tool, passed Leah's hand test on 2026-10-04.** Use
`TestImages/Stage 10/Three Page Test.pdf` (each page has a made-up email and phone number), and
`E1 Screenshot.png` from `~/Downloads/colorbee tests/`. Color 1 should be black.
1. **Reads every page.** Open Three Page Test.pdf, Effects ▸ Auto-Redact…. It says "Reading page 1 of 3…" with a progress bar, then lists 6 items under "Page 1 · 2 items", "Page 2 · 2 items" and "Page 3 · 2 items": an Email and a Phone on each.
2. **Click to see.** Click the alex.morgan@example.org row (not its checkbox): the row is highlighted, and the canvas behind the sheet shows page 2 with that email outlined.
3. **Apply to every page.** Uncheck page 3's Phone. Solid Fill, Apply to 5 Items. The sheet closes. Pages 1 and 2 have their email and phone blacked out; page 3 has its email blacked out and its phone still showing. The thumbnails show it too.
4. **Undo is all or nothing (changed 2026-10-04).** On page 2, Edit ▸ Undo reads "Undo Auto-Redact"; ⌘Z takes the redaction off pages 1, 2 and 3 at once (check the thumbnails). ⇧⌘Z puts it back on all three. Then draw a line on page 1 and press ⌘Z twice: the first removes the line, the second removes the redaction from every page. Press ⇧⌘Z twice to get both back. Finally, go to page 2 and press ⌘Z: with page 1's line in the way, only page 2's redaction comes off.
5. **Selection is ignored; clearer summary (changed 2026-10-04).** Open the PDF again (a fresh copy). On page 1, draw a selection box around the email only, then Auto-Redact…: it still says "Read 3 pages. Found 6 items on 3 pages." and lists all 6, and the selection box is still there afterwards. Cancel, then redact pages 2 and 3 only (uncheck page 1's two items, Apply), and run Auto-Redact again: "Read 3 pages. Found 2 items, all on page 1."
6. **Locked layer stops everything.** Fresh copy of the PDF. Go to page 2, lock its layer in the Layers panel (⌘L), go back to page 1, Auto-Redact…, Apply. A message says page 2's layer is locked; nothing is redacted on any page.
7. **Export as PDF.** Redact the PDF (step 3), then File ▸ Export as PDF… and save it. Open it in Preview: 3 letter-size pages in order, redactions black. Text can't be selected. In Preview, Tools ▸ Show Inspector: no title, author, creator or producer.
8. **Images become a PDF.** Open E1 Screenshot.png, Page ▸ New Page, then File ▸ Export as PDF…. In Preview, page 1 is the screenshot and page 2 is blank (Color 2).
9a. **Remove Earlier Versions clears every page (fixed 2026-10-04).** Open Three Page Test.pdf and ⌘S it as "Forget Test" on the Desktop. Delete page 3 (Page ▸ Delete Page). Effects ▸ Auto-Redact…, Solid Fill, Apply, then ⌘S and choose **Remove Earlier Versions and Undo History**. Now Edit ▸ Undo is greyed out on page 1 and on page 2, and the deleted page can't be brought back. On page 2, View ▸ Before/After with As Opened shows the redacted page, not the original.
9. **Resolution setting.** Colorbee ▸ Settings ▸ PDFs, choose 300 DPI, then open Three Page Test.pdf again: the status bar says 2550 × 3300 px. Set it back to 200 DPI afterwards.

**Stage 10a pages (2026-10-04): all 11 steps passed Leah's hand test on 2026-10-04.** Test files: `TestImages/Stage 10/Three Page Test.pdf`
(made up names, emails and phone numbers, one person per page), `TestImages/Round 3/Two Pages.tiff`, and
`catslap.gif` from `~/Downloads/colorbee tests/`.
1. **Open a PDF.** Open Three Page Test.pdf. Expect a window titled "Three Page Test", Edited, with a Pages sidebar on the left showing 3 thumbnails, page 1 outlined in blue. The status bar says 1700 × 2200 px (letter size at 200 DPI).
2. **Change pages.** Click thumbnail 2: the canvas shows "page 2 of 3". Press ⌥⌘↓: page 3. Press ⌥⌘↑ twice: page 1. Page ▸ Previous Page is greyed out on page 1.
3. **Each page keeps its own undo.** On page 1, draw a red line. Go to page 2, draw a blue line. ⌘Z: only the blue line goes. Go back to page 1: the red line is still there; ⌘Z removes it.
4. **Zoom is per page.** On page 1, zoom to 200%. Go to page 2: it fits the window. Back to page 1: 200% again.
5. **New, Duplicate, Delete.** On page 2, Page ▸ New Page: a blank page 3 appears, filled with Color 2, and the old page 3 becomes 4. ⌘Z: it's gone. Page ▸ Duplicate Page: a copy appears just after. Page ▸ Delete Page: it's removed. The + / copy / trash buttons at the bottom of the sidebar do the same.
6. **Reorder.** Drag thumbnail 3 to the top: it becomes page 1. Page ▸ Move Page Down moves the shown page one place later. ⌘Z undoes a move, as long as you haven't drawn on the page since.
7. **Save and reopen.** Draw something on page 2, ⌘S. It asks where to save a .colorproj. Close and reopen it: 3 pages, your drawing on page 2, and the page you were on is shown.
8. **Hide the sidebar.** View ▸ Page Sidebar (⌥⌘2) hides it; again shows it. Quit and relaunch with the window open: it stays as you left it.
9. **Pages in any image.** Open any PNG (Stage 5a Practice.png), Page ▸ New Page. The sidebar appears with 2 pages, and ⌘S asks where to save a project (the PNG is left as it was).
10. **TIFF and GIF.** Open Two Pages.tiff: 2 pages in the sidebar, "Page 1" and "Page 2". Open catslap.gif: every frame is a page. Neither original file changes.
11. **Right-click a thumbnail (fixed 2026-10-04; passed Leah's hand test the same day).** On page 1, right-click thumbnail 3: the blue outline moves to 3 and the canvas shows "page 3 of 3" before you choose anything. Duplicate Page: a 4th page appears, a copy of page 3. Right-click thumbnail 2, Delete Page: "page 2 of 3" is gone. Right-click a thumbnail and press Esc: you stay on that page and nothing else changes. Control-click works the same.

**Round 3 fixes (reviews H, I and J, 2026-10-04): all 33 steps, and 11a, passed Leah's hand test on 2026-10-04.** Details in `Docs/Review/RESULTS.md`.
Test images: the review ones in `~/Downloads/colorbee tests/` (E1 Screenshot.png, E3 Mixed Text Sizes.png,
E5 Tall Scroll.png, E5 Transparent Background.png, catslap.gif), plus three new ones in `TestImages/Round 3/`
(Sideways Photo.jpg, Deep 16-bit.png, Two Pages.tiff).

*Privacy and redaction*: steps 1–6 passed Leah's hand test on 2026-10-04.
1. **Earlier versions warning.** Duplicate E1 Screenshot.png in Finder and open the copy. Effects ▸ Auto-Redact…, Solid Fill, Apply, then ⌘S. Expect a message that earlier versions still show what you redacted, with Keep and Remove buttons. Choose Remove, then File ▸ Revert To: no unredacted version is offered.
2. **Clipboard History offer.** Open E1 Screenshot.png in Preview, ⌘A, ⌘C. In Colorbee, ⇧⌘V. Auto-Redact with Solid Fill, Apply. Expect "Remove the unredacted image from Clipboard History?" with Remove highlighted. Choose Remove: the screenshot is gone from the Clipboard History panel (⌥⌘V).
3. **Remove one item.** In the Clipboard History panel, right-click (or Control-click) a thumbnail ▸ Remove. Only that one goes.
4. **Batch Redact on every layer.** Open E1 Screenshot.png. Layer ▸ New Layer (it's empty and active). Marquee around the email, then Effects ▸ Batch Redact ▸ Solid Fill with Color 1. Expect the email covered. Undo, then try Batch Redact ▸ Pixelate…: the bar says "Redacts every layer in the selection", and Apply pixelates the email.
5. **Locked layer.** Same image, lock the Background layer, then Batch Redact ▸ Solid Fill. Expect a message naming "Background" and nothing changed.
6. **Visible layers note.** With two layers, open Auto-Redact: the sheet says only visible layers were checked.

*Drawing*: steps 7–16 passed Leah's hand test on 2026-10-04 (step 17 too).
7. **Wand with a floating paste.** File ▸ New. Copy E1 Screenshot.png (from Preview) and ⌘V. Press W. Click the white area away from the paste. Expect the white selected with the outline going around the paste. Press Delete: the paste stays.
8. **Tool keys after a paste.** ⌘V any image, then press P, then W, then B: each switches the tool, with no beep.
9. **Symmetry overlap.** File ▸ New, Canvas Properties 20 × 20, zoom to 3200%, Pixel Grid on. Symmetry: Vertical, round brush size 9, black. Click just left of the center line. Expect one solid black blob, the same on both sides.
10. **Symmetry eraser.** Fill the 20 × 20 canvas black. Eraser size 4, Symmetry: Vertical. Click in the middle of column 5. Expect the two erased squares to mirror each other exactly (3 black columns at each edge).
33a. **Discard hidden layers? (new).** Open Stage 6b Practice.colorproj, hide one layer, then Image ▸ Flatten: a question names 1 hidden layer, with Flatten and Cancel. Cancel changes nothing; Flatten keeps only the visible layers. With nothing hidden, Flatten asks nothing.
11a. **Color Eraser switch (new).** Eraser, turn on **Color Eraser** in the palette bar. Type black text and place it, Color 1 black, Color 2 white, tolerance 30%. A plain (left) drag over the text replaces the black and its gray edges with white, and leaves other colors alone. Turn the switch off: a plain drag erases everything again; a right-drag still color-erases.
11. **Color Eraser tolerance.** Choose the Eraser: the palette bar shows "Color Eraser tolerance". Type black text and place it, set the tolerance to 30%, right-drag over the text with Color 1 black and Color 2 white: the gray edges go too.
12. **Sample All Layers.** Open E1 Screenshot.png, Layer ▸ New Layer. Fill tool, turn on Sample All Layers, click inside a box in the screenshot: only that box's shape fills, on the new layer. Same idea with the Magic Wand's Sample All Layers.
13. **Eyedropper as shown.** On a white image, Layer ▸ New Adjustment Layer ▸ Invert. Eyedropper, Option-click: Color 1 becomes black.
14. **Shift marquee.** At 3200%, Rectangle Select with Shift from the corner of a pixel: the status bar always shows N × N.
15. **Huge handle drag.** Open any image, zoom to 12.5%, select 200 × 200 and drag it so it floats. Drag a corner handle to the far screen corner, release, press Return: no long freeze.
16. **[ and ] with Shapes.** Shapes tool, press ] three times: the Size shown goes up by 3.

*Documents*
17. **Revert To Saved.** Open a copy of Stage 5a Practice.png, draw a red line, ⌘S, draw a blue line. File ▸ Revert To Saved: the blue line disappears from the screen. Draw a green line, close (it asks to save), choose Save, reopen: red and green, no blue.
18. **Animated GIF.** Open catslap.gif. Expect an untitled copy ("catslap — Edited") with a bar: "This GIF has N frames · Showing frame 1 · Choose Frame…". Choose Frame…, click frame 5: it shows frame 5. Draw something, then Choose Frame… again and pick another: it asks before discarding. The original file is untouched.
19. **Two-page TIFF.** Open TestImages/Round 3/Two Pages.tiff: the bar says pages, and Choose Page… shows two.
20. **16-bit image.** Open TestImages/Round 3/Deep 16-bit.png: it opens as an untitled copy, so saving asks where.
21. **Sideways photo.** Open TestImages/Round 3/Sideways Photo.jpg: the word "UP" reads upright, and the arrow points up.
22. **Paste into New Image is kept safe.** ⇧⌘V a screenshot, then ⌘W: it asks whether to save.
23. **⌘⌫ while typing.** Layer ▸ New Layer, Text tool, type "hello world", press ⌘⌫: the text is deleted, the layer stays.
24. **Menus behind dialogs.** Select an area, Image ▸ Resize and Skew…; with it open, the Edit menu's Deselect is greyed out.
25. **Panels.** ⌘L to show Layers, ⌘Y to show History, then ⌘L again: History stays open.
26. **⌘Z on a shape.** New document, draw a rectangle without placing it: Edit ▸ Undo reads "Undo Shape", and ⌘Z removes it.
27. **Relaunch.** Open Stage 5a Practice.png, add a layer (it becomes a project), zoom to 200%, open History. Quit and relaunch: same title, zoom and panels.
28. **A damaged file.** Make a copy of any text file and rename it "broken.png". File ▸ Open it: a plain message, not an error code. Drag it onto the gray area: the same message.

*Shortcuts (Settings ▸ Shortcuts)*
29. Click Undo's ⌘Z, press ⌘I: the message says ⌘Z is Undo's standard shortcut and that Invert Colors will lose ⌘I.
30. Click Pencil's P, press Space: refused ("kept by the canvas").
31. Click Undo's ⌘Z, press Delete: it asks before clearing.
32. Change Pencil to Q, then hover over the Pencil in the toolbar: the tooltip says (Q). Reset All afterwards.

*Speed (AC-27)*
33. **Flatten.** Open Stage 6b Practice.colorproj (or any image with several layers), Image ▸ Flatten, then ⌘Z: both are quick, and the undo brings every layer back exactly.

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
