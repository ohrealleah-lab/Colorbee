# Colorbee — Build Status

**Read this first in a new session.** It's the running record of what's built, what isn't, and what's next.
Update it at the end of every stage or significant change, and commit it with that work.

- **What to build:** [FRD.md](FRD.md) (behavior), decision log in FRD §23.
- **How to build it:** [../CLAUDE.md](../CLAUDE.md).
- **What it looks like:** [Design/](Design/) mockups.

_Last updated: 2026-10-27 · 568 core tests and 142 app tests passing, plus `make perf`_

## Waiting for Leah's tests

Each link jumps to that test's numbered steps. When a test passes, its line comes off this list.

Nothing waiting right now.

---

## Working agreements with Leah

- Leah is the PM and only user; Claude is the only engineer. Functional decisions are hers: ask, then record the answer in FRD §23.
- **Full scope.** Never propose cutting features to save time. Colorbee is a paint program first; no mind-mapping or structured-diagram features.
- **Say the recommended model and effort before each stage** (Opus throughout; high for design-heavy work, medium for routine UI).
- Log any behavior choices Claude makes on its own in FRD §23, phrased "veto any".
- Prefer plain explanations. Leah tests features by hand and reports back; give her a short "please try" list after each stage.
- **Keep "Waiting for Leah's tests" at the top current:** add each new test there with a link to its steps (a `### Test: …` heading), and remove it when it passes. Also give Leah the steps in chat; the file is long.
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
| 11. Import from iPhone or iPad | ❌ Removed 2026-10-19 (Leah): struck from the FRD, app code deleted | — |
| 12. RAW photos | ✅ Done | High |
| 13a. Copy Text, Step Badges, Redact Brush | ✅ Done; all passed Leah's tests 2026-10-10 | Medium |
| 13b. Match Surroundings: trial build, then Remove and Spot Heal | ✅ Done; passed Leah's tests 2026-10-10 (Remove for simple backgrounds; Clone Stamp for busy spots) | **High** |
| 13c. Clone Stamp, local brushes, Remove Red-Eye | ✅ Done; passed Leah's tests 2026-10-10 | Medium |
| 13d. Soft selections (feather) | ✅ Done; passed Leah's test 2026-10-10 | **High** |
| Only the layer below (adjustment clipping) | ✅ Done; passed Leah's test 2026-10-10 | High |
| Help (FR-14.6) | ✅ Done; Leah read the whole book 2026-10-19. Phases 1–3 passed (all eight task guides; Leah, 2026-10-11). Phase 4 passed (the reference; Leah, 2026-10-11). Phase 5 passed (the ? buttons; Leah, 2026-10-17). Window, toolbar, palette bar and shortcuts pictures retaken 2026-10-16 to 10-17. Phase 6 passed (accuracy review M and Q, all fixed; Leah, 2026-10-19) | Medium (phase 6 high; review plan: `Docs/Review/PLAN-6.md`, sessions M and Q) |

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
- Info panel (View ▸ Info ⌥⌘I, 2026-10-24): read-only file, image and photo details; says Location: Removed when the original had one. Passed Leah's test 2026-10-24.
- Sidebar shortcut (2026-10-27): ⇧S or View ▸ Sidebar (⌃⌘S) hides or shows the whole right sidebar, like the toolbar's Sidebar button. Every button's tooltip shows its key, and tool keys work as soon as a window opens. Passed Leah's tests 2026-10-27.
- Right sidebar with the Layers panel (⌘L or the toolbar's Layers button, which shows the count): blend mode, opacity, eye, padlock, thumbnails, drag to reorder, double-click to rename, add/duplicate/delete/merge down.
- Layer menu: New ⇧⌘N, Duplicate ⌘J, Delete ⌘⌫, Merge Down ⇧⌘E, Merge Visible ⌥⇧⌘E, Flatten, Hide/Show, Lock/Unlock, Layer Properties…. Edit ▸ Copy Merged ⇧⌘C.
- 17 blend modes (W3C math in `BlendMode.swift`, mirrored in `Shaders.metal`); layers composite off screen in half floats. Exports use the same math.
- Locked layers refuse pixel changes (beep, 'not allowed' pointer). All layer changes are undo steps (whole-stack snapshots, buffers swapped not copied).
- Adjustment layers (stage 6b): Brightness/Contrast, Hue/Saturation, Desaturate, Invert, Gaussian Blur, Sharpen; edited in the Adjustments panel; Merge Adjustment (was Apply Adjustment). Display: point adjustments in the blend shader, Blur/Sharpen via MPS mid-pass with edge renormalization.
- Undo on Active Layer ⌥⌘Z (`History.undoOnLayer`), Revert Layer (pixel copies kept at each explicit save).
- `.colorproj` (`ProjectFile`): JSON manifest + LZ4 exact pixels + ICC. Layered images save as projects; Save As offers only .colorproj for them; Export makes flat copies.

**Integration** (stage 7a)
- Canvas Properties ⌥⌘E (size, transparent background) and edge handles on the canvas; Paste into New Image ⇧⌘V; big pastes offer to enlarge the canvas.
- Sidebar panels: History ⌘Y (steps with thumbnails, click to jump) and Clipboard History ⌥⌘V (last 10, persistent, click to paste).
- Drag and drop images onto the canvas or the window; File ▸ Share…, Set as Desktop Picture, Page Setup, Print ⌘P; View ▸ Rulers ⌘R, Status Bar.

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
- App tests (2026-10-11): `Tests/ColorbeeTests`, 71 Swift Testing tests of the `Editor` (strokes and Shift, undo steps, locked and adjustment layers, Step Badges, placing pending shapes, text and badges, FR-3.2 selection drags, Redact Brush, Retouch, repeatability, random actions undone). They run inside Colorbee, which starts hidden for them (`TestHost`: no Dock icon, windows or focus). `make test` runs them after the core tests (about 35 s in all); GitHub runs them on every push. `make coverage` reports line coverage: app 7.3%, `Editor.swift` 33.8%, core 96.5% (2026-10-11; the app was 0% before).
- Coverage pass 2 (2026-10-20): 32 more app tests for the least-covered Editor code: Auto-Redact through the Editor (every layer and page, one undo, refusing on a change or a locked layer, items kept visible), Crop/Straighten/Perspective drags, pages, tool sizes, Canvas Properties, Resize and Skew, Revert Layer, Undo on Active Layer, Auto Contrast and Adjust Photo's Auto, paste, Before/After, every effect's bar applied and undone, shape handles, rotation, polygons, curves and text box editing. `make coverage`: core 96.6%, app 16.9% (was 10.9% today, 7.3% on 2026-10-11), `Editor.swift` 74.9% (was 47.5%). The rest of the app is mostly SwiftUI views and AppKit glue, checked by hand; Remove Red-Eye's eye finding and the subject commands stay hand-tested (Leah's choice).
- Core coverage pass (2026-10-11): 29 more tests for the least-covered files. BlendMode, PaintStyle and SelectionHandle are at 100%, ImageCodec 97.9% (left: two errors macOS never returns). RedEye's eye-circle math moved into `RedEye.eye(outline:pupil:imageHeight:)` and Subjects' mask conversion (`SubjectScan.bytes`) became internal, so both are tested on made-up input. What's left in RedEye (64%) and Subjects (75%) is the Vision calls themselves, which run only in the app by Leah's choice (slow, and Apple's models can change); Remove Red-Eye's automatic eye finding and Select Subject are checked by hand.
- `make beta` (`Scripts/make-beta.sh`): Developer ID signing, hardened runtime, notarization, stapling, zip with `Docs/Beta/Start Here.txt`. Version 0.9.0.

## Not built yet (by stage)

**Feature-complete (Leah, 2026-10-19).** No more new features; the ideas once kept for later (AI fill, searchable PDF text, Split Page in Half) are dropped. From here on: fixes, polish and betas.

**Next up (Leah, 2026-10-11)**
- Help: done 2026-10-19 (phases 1–6). Keep it current: see "Keeping it current" in `Docs/HELP-PLAN.md`.

**8 Hardening**
- (Done again 2026-10-10, see AC-27.) The 30-minute soak (NFR-7) and a fresh `make perf`, **only when Leah says the Mac is free**: on 2026-10-03 the 30-minute soak drove the Mac into heavy swap and its test process set off a macOS kernel panic. Freeing history's layer memory now uses `madvise` (as the system allocator does) instead of remapping it; the heavy runs re-check that.
- Beta 0.9.0 (1) built, notarized and stapled on 2026-10-03 (`build/Beta/Colorbee-0.9.0-1.zip`, 1.8 MB); Gatekeeper accepts it as "Notarized Developer ID". Leah's `colorbee-notary` keychain profile is set up. Bump `CURRENT_PROJECT_VERSION` in project.yml for each new beta.
- Beta 0.9.0 (2) built, notarized and stapled on 2026-10-05 (`build/Beta/Colorbee-0.9.0-2.zip`, 2.7 MB): pages and PDFs, RAW photos, review round 4, Appearance, scrubbing. "Start Here.txt" updated.
- Beta 0.9.0 (3) tagged `v0.9.0-beta.3` on 2026-10-14 (Leah): stage 13, the help book (phases 1–4), the GPU audit speed-ups, code review round 5, Match Tone for soft brushes. The first release with the hardened workflow (key for `codesign` only, deleted before publishing, `gh release create`).
- Beta 0.9.0 (4) tagged `v0.9.0-beta.4` on 2026-10-15 (Leah): the menu reorder with its own Redact menu, the toolbar and palette bar polish, 4 custom colors, the canvas shadow.
- Beta 0.9.0 (5) tagged `v0.9.0-beta.5` on 2026-10-19 (Leah): the finished help book (? buttons, accuracy review fixes, new pictures), the help book registered at launch, Paste into New Image with no window open, iPhone import removed.
- Beta 0.9.0 (6) tagged `v0.9.0-beta.6` on 2026-10-22 (Leah): damaged-file hardening (Levels from a file kept in range), code review round 6 (Match Tone lands before the next edit, measures what's shown, reads only the edge; fresh View checkmarks), Match Tone's smooth blend (only what was copied, no haze on an empty layer), the 2026-10-20 soak and coverage pass 2. Recut the same day (not yet downloaded) to add the Help menu quick links and registering the help book before opening a page.
- Beta 0.9.0 (7) tagged `v0.9.0-beta.7` on 2026-10-23 (Leah): code review round 7 (Match Tone fast and lean on huge strokes; every save, autosave too, waits for a pending tone). Recut the same day (Leah) with the app icon on a white tile with a faint gray fade, replacing the gray tile (the heart is unchanged).
- Leah's everyday Colorbee is the notarized beta in Applications (2026-10-23); build.command builds are for testing fixes. A "Not Opened: Apple could not verify… is free of malware" box on Open With came from old quarantine flags Preview had put on her pictures (`0082;Preview`), not from Colorbee: every app got it. Clearing the flags fixes it only until Preview opens the picture again (it re-adds the flag); right-click ▸ Open in Colorbee (our Services item) opens flagged pictures fine, so that's Leah's way in.
- GitHub Actions (`.github/workflows/build-release.yml`): every push builds and runs the tests on a macOS 26 runner. A tag `vX.Y.Z-beta.N` also signs, notarizes and publishes the zip as a pre-release (version X.Y.Z, build N). Needs five repo secrets: `APPLE_CERT_P12`, `APPLE_CERT_P12_PASSWORD`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`, `APPLE_API_KEY_P8` (all set 2026-10-05). On GitHub's runner the tests run one at a time; side by side they stalled. First release: v0.9.0-beta.2, published 2026-10-05, checked as "Notarized Developer ID". Next beta: push the tag `v0.9.0-beta.3`.
- Polish done 2026-10-03: effect previews in the background (`EffectPreview`), Copy in the background (`ClipboardImage`). Tested by hand 2026-10-03.

**L15, from review round 4: done 2026-10-10.** Switching pages compressed the old page and expanded the new one a
layer at a time on one core. Layers are now stored in pieces of about 4 MB (`LayerPixels`) that compress and expand
on all cores: at 4000 × 4000 with three layers, leaving a page went from 0.24 s to 0.035 s and showing one from
0.17 s to 0.021 s (`PerformanceTests`, `make perf`). Still on the main thread, as Leah chose (2026-10-10: just wait,
much shorter). The first switch away from a page after many edits also writes old undo steps to disk (about 0.06 s
at 4000 × 4000).

**12 RAW photos (FR-11.8)** — done; tested by hand 2026-10-05. Built: `RawDeveloper` (macOS's RAW engine, CIRAWFilter), the Develop
window (`DevelopWindow`), `DocumentController` (sends RAW files to it), `CameraDetails` (core, kept in .colorproj),
and Include camera details in Export…. Test file: `TestImages/Stage 12/Test Camera.dng`, a synthetic DNG with
made-up camera details, serial number, owner and GPS location (made by a small script, not a real photo).

**11 Import from iPhone or iPad (FR-11.7): removed 2026-10-19 (Leah).** It worked only with no window open; with a
document open, SwiftUI's views never passed macOS's Continuity Camera request on. The File menu item and the app
code (`ContinuityImport`, `Editor.importPages` and the `validRequestor` hooks) are deleted; the core's
`PDFPages.scannedPage` and `PageStack.insert(_:at:named:)` stay, with their tests. The trial notes are in git history
and `Docs/Proposals/Import from iPhone.md`.

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
**Re-run 2026-10-10** (after stage 13; Mac free): the 30-minute soak ran 105 rounds with no crash and exact undo and redo; 13 steps went a little over a second (Sharpen, Flatten; worst 1.34 s), the same as accepted. The 10 performance tests all passed.
**Re-run 2026-10-20** (feature-complete, after the GPU-audit speed fixes and layer pieces; Mac free): 127 rounds in 30 minutes with no crash and exact undo and redo; no step over a second (worst 0.87 s, a whole-image Flatten), down from 13 steps over a second (worst 1.34 s) on 2026-10-10. All 10 performance tests passed.
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

**Page switching speed, L15 (2026-10-10): passed Leah's hand test on 2026-10-10.** `TestImages/Stage 9 Practice Photo.png` resized to 400% (6400 × 4000), three layers, three pages: switching feels instant, a stroke survives switching and undoes, the project saves and reopens exactly, and the older `Cant Copy.colorproj` opens as before.

**Adjustment layers: Merge Adjustment and Copy (2026-10-09/10): passed Leah's hand test on 2026-10-10.** Leah's `Cant Copy.colorproj` (four layers, Adjust Photo on top).
1. Adjustments panel ▸ **Merge** (was Apply) on Adjust Photo: the look is unchanged, the layers below become one, ⌘Z brings them back ("Undo Merge Adjustment").
2. ⌘A ⌘C with Adjust Photo active, paste into another app: the whole visible picture, not a transparent one. On Subject: just Subject.
3. A locked visible layer below greys out Merge. Merge Down is greyed out on an adjustment layer (menu, Layers panel ↓, ⇧⌘E) and works as before on a pixel layer.

### Test: Sidebar shortcut (passed 2026-10-27)

Test image: `TestImages/Stage 9 Practice Photo.png` (any picture works). Run `make run` first for a fresh Release copy.
1. Open the test image. If the sidebar on the right is closed, press **⇧S**: it opens.
2. Show **History** and **Info** too (⌘Y, ⌥⌘I), so three panels are showing.
3. Press **⇧S**: the whole sidebar hides and the canvas gets wider. Press **⇧S** again: it comes back with the same three panels.
4. Open the **View** menu: **Sidebar** is just above Layers, shows **⌃⌘S**, and has a checkmark. Choose it: the sidebar hides, and the checkmark is gone next time you open the menu. Press **⌃⌘S**: it's back.
5. Press plain **S**: Clone Stamp is chosen, and the sidebar doesn't move.
6. Choose the Text tool, click the canvas and type a capital **S**: it types the letter, and the sidebar stays.
7. Open **Adjust Photo**. Press **⇧S**: the sidebar stays (its sliders live there). View ▸ Sidebar is greyed out. Cancel Adjust Photo.
8. **Colorbee ▸ Settings ▸ Shortcuts**: **Sidebar** appears under Tools and Canvas Keys as ⇧S, and under View as ⌃⌘S.

### Test: Small subjects (passed 2026-10-27)

Test image: Leah's `Pictures/Final Fantasy/new/ffxiv_09022024_205711_085.png` (not in the repo: it's a personal screenshot). Run `make run` first for a fresh Release copy.
1. Open the picture and choose **Layer ▸ Lift Subject to New Layer**. The bar asks you to click one, and now says "even a small one".
2. Click **Evelyn's yellow raincoat**. "Looking closer…" shows for a second, then a new **Subject** layer appears with just Evelyn, without her shadow. Hide the bottom layer to check. ⌘Z.
3. Choose **Edit ▸ Select Subject** and click her **head**: the marching ants go around her.
4. Choose Select Subject again and click the **stone floor** well away from anyone: "Looking closer…", then a beep, and the bar stays. Press **Esc**.
5. Choose Lift Subject again and press **Return**: the three big things are lifted as before, without Evelyn. ⌘Z.
6. Open `TestImages/Auto-Redact Practice.png` (a screenshot) and choose Select Subject. If no subject is found, the bar now says to click one. **Apply** is greyed out and Return does nothing. Press **Cancel**: nothing changed.

### Test: Save starts in the picture's folder (passed 2026-10-27)

Test images: `TestImages/Stage 9 Practice Photo.png` and `TestImages/Stage 10/Three Page Test.pdf`. Run `make run` first for a fresh Release copy. Press **Cancel** in every panel below, so nothing gets saved into TestImages.
1. ⌘N for a new image, ⌘S, and save it to the **Desktop**, so the last folder used is somewhere else. Close it.
2. Open `Stage 9 Practice Photo.png`. Add a layer (⇧⌘N), then ⌘S. The Save panel is in **TestImages**, named **Stage 9 Practice Photo**, as a Colorbee project. Cancel.
3. **File ▸ Export…**: also in **TestImages**. Cancel. Try an **Export As** preset and **Export as PDF**: both in TestImages. Cancel each.
4. Open `Three Page Test.pdf` and press ⌘S: the panel is in **Stage 10**. Cancel.
5. ⌘N for a new image and ⌘S: the panel is on the **Desktop** (the last folder used), as before. Cancel.
6. Back on the Stage 9 photo, Save As (⇧⌘S) to the Desktop. Then **File ▸ Export…**: it now starts on the **Desktop**, where the project is. Cancel. You can delete the Desktop test files afterwards.

### Test: Tool keys right after opening (passed 2026-10-27)

Test image: `TestImages/Stage 9 Practice Photo.png`. Run `make run` first for a fresh Release copy. Don't click the image during steps 1–4.
1. Open the test image. Right away, press **⇧S**: the sidebar hides. Press it again: it's back.
2. Press **P**: the Pencil is chosen. Press **B**: the Brush.
3. ⌘N for a new image, and press **⇧S** and **P** in it straight away: both work.
4. Click the **Layers** button in the toolbar, then a panel button at the top of the sidebar (History, say). Press **P**, then **⇧S**: both still work.
5. Double-click the size box in the toolbar and type a number: the digits go in the box, and nothing else changes. Press Return.
6. Choose the Text tool, click the image and type **"Pass"** with a capital P: the letters are typed, and neither the tool nor the sidebar changes.

### Test: Buttons show their keys (passed 2026-10-27)

Test image: `TestImages/Stage 9 Practice Photo.png` (any picture works). Run `make run` first for a fresh Release copy. Hover over each thing for a second until its tooltip shows.
1. The **Sidebar** button at the far right of the toolbar: **Sidebar (⇧S)**.
2. Click the **Retouch** button (the wand with rays), then hover **Clone Stamp** in its menu: **Clone Stamp (S): Option-click where to copy from**.
3. Choose the Pencil and hover the **size box**: **Size of the Pencil. [ and ] change it.**
4. Hover a few tools for a spot check: Pencil **(P)**, Fill **(G)**, Magic Wand **(W)**, Step Badge **(N)**. Gradient and Ellipse Select have no key, so they show just their names.
5. **Colorbee ▸ Settings ▸ Shortcuts**: change **Larger Size** to **=**. Hover the size box again: **[ and = change it.** Then click the ↺ next to Larger Size to put it back to **]**.

### Test: Info panel (passed 2026-10-24)

Test image: `TestImages/Info Panel/Photo With Location.jpg` (made-up iPhone details and a made-up location). Run `make run` first for a fresh Release copy.
1. Open the test photo. Choose **View ▸ Info** (⌥⌘I). The sidebar shows **Info** with File, Image and Photo sections: JPEG image, 86 KB, 1600 × 1000 px, Display P3, Apple iPhone 17 Pro, 1/120 s, ƒ/1.8, Oct 5, 2026, and **Location: Removed**.
2. Try to type in a value: nothing changes. Drag across a value and press ⌘C: it copies.
3. Click the ⓘ button at the top of the sidebar: Info hides. If it was the only panel showing, the sidebar closes.
4. Show Info again and add a layer (⇧⌘N): Layers says 2, and Kind says "Not saved yet" (a layered image becomes a new project).
5. ⌘N for a new image: no Photo section. Save it as a PNG: Kind becomes PNG image and a Size appears.
6. Open `TestImages/Stage 10/Three Page Test.pdf`: Page says "1 of 3" and Resolution 200 DPI. Click page 2 in the page sidebar: "2 of 3".
7. Quit and reopen Colorbee: a window that had Info showing still shows it.

### Test: Darker toolbar capsules (passed 2026-10-15)

1. Quit Colorbee and open it again (the Release copy), with any image.
2. Each toolbar group (selection tools, drawing tools, Size, Outline/Fill, Layers and Sidebar) sits in a capsule a shade darker than the window, and the icons stand out more.
3. Press **E**, **U** and **M**: Size and Outline/Fill appear and disappear with their capsules, and no empty capsule is left behind.
4. Switch to dark mode (Settings ▸ Appearance or the Mac's): the capsules are a shade lighter than the dark window.
5. Make the window narrow: groups that don't fit go into the » menu at the right.

### Test: Review S fixes: big Match Tone strokes (passed 2026-10-23)

Code review round 7 (`Docs/Review/RESULTS.md`). Rebuild with the script (option 2), then quit and reopen Colorbee. Use a copy of `TestImages/Stage 9 Practice Photo.png` (Option-drag it to the Desktop, so the original isn't changed).

1. **No freeze:** open the copy. Image ▸ Resize and Skew…, 500%, OK (8000 × 5000). View ▸ Zoom to Fit. Retouch ▸ Clone Stamp, Size 300, Match Tone on. Option-click the photo, then paint one long back-and-forth stroke covering most of it. As soon as you let go, click to paint a dab: Colorbee answers within a second or so (before, up to about 25 seconds of spinning wheel).
2. **The tone is saved on close:** press ⌘S. Paint another big stroke from a bright spot over a darker part, and as soon as you let go press ⌘W. Reopen the copy: the stroke is blended in, not bright.
3. Delete the copy from the Desktop.

### Test: Help menu quick links (passed 2026-10-22)

Every help page in the Help menu (Leah, 2026-10-22). Rebuild with the script (option 2), then **quit and reopen Colorbee**. _First try: the links gave "content unavailable". Help Viewer was reading an old screenshot copy's help book (deleted), and Colorbee's registration at launch didn't always stick; it now registers its help book again right before opening any page._

1. Open the Help menu: Search, Colorbee Help (⌘?), then a "Guides" heading with 8 guides and a "Reference" heading with 7 pages.
2. Hover over a few: each shows its one-line description.
3. Choose **Fix Up a Photo**, then **Keyboard Shortcuts**, then **Troubleshooting**: each opens Help at the top of that page.
4. The Help menu's Search field still finds help topics (try "redact").

### Test: Match Tone blends smoothly (passed 2026-10-22)

From Leah's video (2026-10-22): after a long Clone Stamp stroke with Match Tone, a lavender shape with hard edges appeared. Two causes, both fixed: Match Tone reshaded pixels the Clone Stamp hadn't copied (where its source was off the image), and it spread its correction inward in rings that met in hard lines; it now blends like a stretched membrane, as healing brushes do. The tip and help now say Match Tone is for patching like with like. Rebuild with the script (option 2) first. Use `TestImages/Stage 9 Practice Photo.png` (restored to the original).

1. Retouch ▸ Clone Stamp, size 300, Match Tone on. Option-click the moon, then paint the same long stroke as in your video, from the top left down and to the right, past where the copy runs out.
2. Wait a second after letting go: no lavender shape with hard edges. Where the copy is different from its surroundings you may see a soft glow; that's Match Tone blending, and it fades smoothly.
3. Option-click plain sky, and paint over a part of the hills' top edge: the patch blends in smoothly.
4. Hover over Match Tone in the palette bar: the tip says it's for patching like with like. Turn it off and copy the moon: a plain copy.
5. **No haze on an empty layer** (Leah's screenshot, 2026-10-22): Layer ▸ New Layer. Clone Stamp, size 30, Hardness 50%, Sample All Layers and Match Tone on. Option-click the moon and scribble a copy of it into the sky elsewhere: no light outline around where you painted, just as on the photo layer itself.

### Test: Hardening and review R fixes (passed 2026-10-22)

Damaged-file hardening and code review round 6 (`Docs/Review/RESULTS.md`). Rebuild with the script (option 2) first.

1. **Broken filter file:** Adjustments ▸ Adjust Photo…, then the ⋯ menu in its Filters ▸ Import Filter… and choose `TestImages/Hardening/Broken Levels.colorbeefilter`. Pick the "Broken Levels" filter and drag Intensity down to 50%. Colorbee keeps working (before, it crashed). Cancel, then delete the filter from the same ⋯ menu.
2. **Match Tone and the next edit** (`TestImages/Stage 9 Practice Photo.png`): Retouch ▸ Clone Stamp, size 300, Match Tone on. Option-click the sky, paint one long zigzag over a darker part, and as soon as you let go choose Effects ▸ Gaussian Blur…; wait 3 seconds and Cancel. The stroke keeps its blended tone. Then paint another zigzag, and as soon as you let go scribble across it with the Pencil and press ⌘Z: no square blocks.
3. **Match Tone on an empty layer** (same photo): Layer ▸ New Layer. Clone Stamp, size 60, Sample All Layers and Match Tone on. Option-click a plain area, then click once elsewhere: the copy blends in, not a dark disc.
4. **Checkmarks:** with View ▸ Rulers checked, choose Effects ▸ Gaussian Blur…, press ⌘R, open the View menu: Rulers isn't checked. Cancel.
5. **No pause:** Clone Stamp, size 300, Match Tone on, one diagonal stroke corner to corner; as you let go the app doesn't hitch.

### Test: Help review fixes (passed 2026-10-19)

The help accuracy review (help phase 6, `Docs/Review/RESULTS.md`): one app fix and many help corrections. Rebuild with the script (option 2) first.

1. **Paste into New Image with no window open:** close every Colorbee window (Colorbee keeps running). Copy `TestImages/Help/Sample Screenshot.png` (open it in Preview, ⌘A, ⌘C), then click Colorbee in the Dock and press ⇧⌘V. A new window opens with the screenshot. With something other than an image on the clipboard, File ▸ Paste into New Image is greyed out.
2. **Read the whole help book once** (Help ▸ Colorbee Help), as a tester would. Note anything unclear or wrong.
3. Look at the pictures on Work with layers (Layers panel), Redact a screenshot (Before/After: the email, phone and key show on the left of the divider and are covered on the right) and Settings (Export Presets, with its ?).

### Test: Help ? buttons (passed 2026-10-17)

Small round ? buttons that open the right part of Colorbee Help (help phase 5). _2026-10-17: Leah's first try opened only Auto-Redact and Export Presets (sections that existed before); the rest said "selected content is unavailable", from macOS's cached older copy of the book. Colorbee now registers its own help book at launch (`NSHelpManager.registerBooks`)._ Rebuild with the script (option 2) first. Use `TestImages/Help/Sample Screenshot.png`, and `TestImages/Stage 12/Test Camera.dng` for step 6. Each ? should open Help at the named heading (scrolled to it), not a list of search results.

1. **Auto-Redact:** open the screenshot, Redact ▸ Auto-Redact…. Click the ? at the bottom left: "What Auto-Redact checks".
2. **Resize and Skew:** Image ▸ Resize and Skew… (⌘E), click ?: "Resize and Skew", under Crop and size it in Annotate an image. Read it: does it match the sheet?
3. **Canvas Properties:** Image ▸ Canvas Properties… (⌥⌘E), click ?: "Canvas Properties", just below.
4. **Settings:** Colorbee ▸ Settings… ▸ Shortcuts, click the ? at the bottom right: "Shortcuts" on the Settings page. Then the Export Presets tab's ?: "Export Presets".
5. **Retouch:** press J, choose Remove, click the ? at the end of the palette bar: "Retouch: remove things and touch up spots". Now choose Clone Stamp and click ? again: the new "Using the Clone Stamp" section. Read it: does it make the Clone Stamp clearer?
6. **Develop:** File ▸ Open `Test Camera.dng`. Click the ? at the bottom left of the Develop window: "RAW photos".

### Test: Toolbar and palette bar polish (passed 2026-10-15)

Use a new image (File ▸ New), and any image with your own colors.

1. **Toolbar with Rectangle Select:** no Size controls and no Outline/Fill at the right, and nothing greyed out.
2. Press **E** (Eraser): the Size controls appear. Press **U** (Shapes): Size and Outline/Fill both appear. Press **M**: both go away, leaving blank space. The tool icons never move while this happens.
3. **Custom colors:** 4 boxes in 2 rows of 2 after the swatches, with fainter dashed outlines when empty. If you had custom colors before, the last 4 are there.
4. Double-click Color 1, pick 5 different colors one after another: the 5th replaces the oldest.
5. **Swap arrow:** a small grey curved arrow, top right of the color wells: it points left at one end, curves over the top, and points down at the other, like your drawing. Click it: Color 1 and Color 2 swap. It never shows a blue box.
6. **Canvas shadow:** a soft shadow around the white canvas, a little stronger along the bottom. Try View ▸ Zoom In and Zoom Out, and dark mode: it stays soft and follows the canvas.

### Test: Menu order and the new Redact menu (passed 2026-10-15)

Use any image, such as `~/Downloads/colorbee tests/E1 Screenshot.png`.

1. The menu bar reads Colorbee, File, Edit, View, Image, Layer, Page, Adjustments, Effects, Redact, Window, Help.
2. **Redact:** Auto-Redact… at the top; below a "Batch Redact" heading, Blur…, Pixelate… and Solid Fill with Color 1. With nothing selected, Solid Fill is greyed out (Blur… and Pixelate… still work, on the whole image). Draw a selection over the email and Solid Fill hides it.
3. **Effects** no longer has any redaction items.
4. **Image:** Flip is right under Rotate. Lift Subject to New Layer is gone from here and is in **Layer**, under Delete Layer.
5. **File:** New, Paste into New Image, Open…, Open Recent, then Import from iPhone or iPad on its own.
6. **View:** Pixel Grid, Rulers, Before/After together; then Layers, Adjustments, History, Clipboard History, Page Sidebar, Status Bar. ⌘R puts a checkmark by Rulers; choose Status Bar and its checkmark goes away with the bar.
7. Settings ▸ Shortcuts lists Auto-Redact and the three Batch Redact commands under Redact, with any shortcuts you'd set still there.

### Test: RAW Develop sliders are fast
_2026-10-11: passed Leah's hand test on 2026-10-11._ GPU audit recommendation 1: the Develop window's previews reuse one `CIRAWFilter` instead of re-reading the file on every change. On Leah's 45 MP CR3 a preview went from about 390 ms to 33–47 ms, byte-identical to a fresh decode (checked with a scratch tool). The final develop still makes its own filter. Rebuild with the script (option 2) first. Use Leah's own 45 MP CR3 (or any large RAW photo).
1. File ▸ Open the CR3. The Develop window opens; the first preview takes about as long as before.
2. Drag Exposure back and forth. The preview keeps up with the slider instead of lagging.
3. Try Temperature, Shadows and Noise Reduction: all quick.
4. Click Open. The photo opens looking like the last preview.

### Test: Saving keeps the last Step Badge
_2026-10-11: passed Leah's hand test on 2026-10-11._ Found by the new Editor tests: the badge you clicked last is still being placed (you can drag it) until your next click, and Save, Export, Share, Print and Copy left it out of what they wrote, though it showed on screen. They now place it first, as they already did for shapes and text. Autosave still leaves it movable. Rebuild with the script (option 2) first. Use `TestImages/Help/Sample Screenshot.png`.
1. Open the screenshot, pick Step Badge (N) and click three places: 1, 2, 3. Don't click anything else.
2. File ▸ Export… (⌥⌘S) as a PNG on the Desktop, then open that PNG: all three badges are there, including 3.
3. Back in Colorbee, badge 3 can no longer be dragged (it's placed), and ⌘Z removes only badge 3. The next click makes a new 3.
4. Click to make badge 4, then Edit ▸ Copy (⌘C) with nothing selected and Edit ▸ Paste into New Image (⇧⌘V): the new image has badge 4.

### Test: Review O, batch B: soft edges near transparency
_2026-10-13: passed Leah's hand test on 2026-10-13 (check 5 rewritten first: the first version kept the pupil far from the soft edge, so it was fully fixed, as it should be)._ See `Docs/Review/RESULTS.md`, round 5, session O findings 3, 9 and 11. Rebuild with the script (option 2) first.
1. **Clone Stamp on an empty layer** (`TestImages/Stage 13/Remove Sky.png`): Layer ▸ New Layer. Retouch (J) ▸ Clone Stamp, Sample All Layers on, size about 80, Hardness 0. Option-click the sky and paint elsewhere on the sky: it blends in with no dark ring.
2. **Fill in a soft selection** (File ▸ New): Layer ▸ New Layer. Draw a selection box, Edit ▸ Feather… 30 px, OK. White Color 1, Fill tool, click inside: nothing visible changes (no gray frame).
3. **Blur brush** (File ▸ New): Layer ▸ New Layer, paint a thick bright yellow line with the Brush. Retouch ▸ Blur, Strength 100%, size about 60, brush along its edge a few times: the edge gets softer and stays yellow, not brown.
4. **Smudge from the edge** (`TestImages/Stage 13/Remove Sky.png`): Retouch ▸ Smudge, size about 150, Strength 100%. Press right on the left edge of the picture and drag into the sky: the sky's colors smear along; no dark, see-through smear.
5. **Red-Eye with a soft selection** (`TestImages/Stage 13/Red Eye Practice.png`): draw a selection box over the red eye whose left edge cuts down through the middle of the red pupil. Edit ▸ Feather… 30 px, OK, then Adjustments ▸ Remove Red-Eye. Zoomed in, the pupil fades gradually from fixed (inside) to red (outside), with no sharp line. With Feather 0 instead, there's a hard line at the box's edge.

### Test: Review O and P, batch C
_2026-10-13: passed Leah's hand test on 2026-10-14. Check 4 first found Match Tone doing nothing with a soft brush (since stage 13); fixed 2026-10-14, then checks 4 and 5 passed (Leah's screen recording)._ See `Docs/Review/RESULTS.md`, round 5. The release workflow change is checked when Beta 3 is published. Rebuild with the script (option 2) first.
1. **Sidebar and New Layer** (`TestImages/Help/Sample Screenshot.png`): open the sidebar, switch off every lit panel button at its top (it closes), then Layer ▸ New Layer (⇧⌘N): the sidebar opens showing the Layers panel.
2. **Sidebar during Adjust Photo** (`TestImages/Stage 9 Practice Photo.png`): Adjustments ▸ Adjust Photo…, then switch off every lit panel button at the top of the sidebar: the sliders stay. Cancel.
3. **Feather slider** (same photo, Image ▸ Resize and Skew… to 300% first): Select All, Edit ▸ Feather…, drag the slider quickly back and forth: the slider moves smoothly and the red tint catches up. OK keeps the radius shown.
4. **Match Tone on a long stroke** (same photo): Retouch ▸ Clone Stamp, tick **Match Tone**, size 300, Hardness 50%. Option-click the sky high up (darker), then paint one long stroke across the lower sky: there's no pause when you let go, and a moment later the stroke blends into the sky around it (no darker band). ⌘Z undoes stroke and tone together. Compare with Match Tone unticked: a darker band.
5. **Quick dabs with Match Tone**: size 30, Match Tone ticked. Option-click the sky, then click several spots on the moon quickly: each dab takes on the moon's color at once (texture from the sky, tone from the moon), instead of leaving a sky-colored dot.
6. **Open Recent in the help**: Help ▸ Colorbee Help ▸ Menus ▸ File: Open Recent is listed after Open….

### Test: Review O and P, batch A
_2026-10-13: passed Leah's hand test on 2026-10-13._ See `Docs/Review/RESULTS.md`, round 5. Rebuild with the script (option 2) first.

**A. Layers keep their "Only the layer below" adjustments** (`TestImages/Stage 9 Practice Photo.png`)
1. Layer ▸ New Layer, paint a big blob, then Layer ▸ New Adjustment Layer ▸ Invert and turn on **Only the layer below**.
2. Click the blob layer, then Layer ▸ New Layer: the blob stays inverted, and the new layer is at the top.
3. ⌘Z. Click the blob layer, Layer ▸ Merge Down: the picture looks exactly the same (blob inverted, photo normal).
4. ⌘Z. Click the blob layer, Layer ▸ Delete Layer: the blob and its Invert are both gone; the photo is normal. ⌘Z brings both back.

**B. Sample All Layers under an adjustment** (`TestImages/Stage 13/Remove Sky.png`)
1. Layer ▸ New Layer, then Layer ▸ New Adjustment Layer ▸ Invert. Click the empty Layer 1.
2. Retouch (J) ▸ Clone Stamp, **Sample All Layers** on. Option-click the sky and paint elsewhere: the copied sky looks inverted like the rest.

**C. Remove's limits** (`TestImages/Stage 13/Remove Sand.png`)
1. Retouch ▸ Remove, paint over something and let go, then press ⌘Z while "Filling…" shows: it stops, with "The image changed while filling. Try again."
2. (Only if you like) On a very large photo, a huge Remove area says it's too big instead of filling.

**D. The Redact Brush shows its red trail on an adjustment layer** (`TestImages/Help/Sample Screenshot.png`)
1. Layer ▸ New Adjustment Layer ▸ Hue/Saturation (it becomes the active layer).
2. Redact Brush (K): paint slowly over the email. The red see-through trail follows the pointer, and the email is redacted when you let go.

**E. Batch Redact ▸ Solid Fill on an adjustment layer** (same file, Hue/Saturation still active)
1. Draw a selection box over the phone number. Effects ▸ Batch Redact ▸ Solid Fill with Color 1 is available, and it hides the number.

**F. The Feather sheet** (`TestImages/Stage 9 Practice Photo.png`)
1. Draw a selection box, then Edit ▸ Feather…. While it's open, the Image, Layer and Edit commands are greyed out (try ⇧⌘X: nothing happens).
2. Click in the number box, type 60 and press Return: Delete then fades the hole's edge over about 60 px.

### Test: Review N fixes: redaction, clipping, Copy Text
_2026-10-11: passed Leah's hand test on 2026-10-13._ Code review round 5, session N (`Docs/Review/findings-N.md`, `RESULTS.md`). Rebuild with the script (option 2) first.

**A. Blur and Pixelate redact a soft selection completely** (`TestImages/Help/Sample Screenshot.png`)
1. Pick Rectangle Select and set **Feather** to 20 px in the palette bar.
2. Draw a selection box snugly around the made-up email address.
3. Effects ▸ Batch Redact ▸ Pixelate…, then Apply. Zoom to 400%: every letter is hidden, edges included.
4. ⌘Z, then try Effects ▸ Batch Redact ▸ Blur…: the same, nothing readable.

**B. "Only the layer below" survives saving and copying** (`TestImages/Stage 9 Practice Photo.png`)
1. Layer ▸ New Layer, and paint a big blob with the Brush.
2. Layer ▸ New Adjustment Layer ▸ Invert, then turn on **Only the layer below**: only the blob is inverted.
3. ⌘C with nothing selected, then ⌘⇧V: the new image shows only the blob inverted.
4. Back in the first window, ⌘S (it saves as a project), close it, and reopen it: still only the blob inverted, and the switch is on.
5. With the Eyedropper, Option-click the inverted blob: Color 1 becomes the inverted color you see.

**C. Copy Text and redaction** (`TestImages/Help/Sample Screenshot.png`)
1. Edit ▸ Copy Text (⌥⌘C) and wait for "Copied … words".
2. Effects ▸ Auto-Redact…, keep everything ticked, Solid Fill, Apply. Colorbee asks: "Remove the unredacted text from the clipboard?" Click Remove.
3. Paste into TextEdit (⌘V): nothing pastes.
4. Undo the redaction (⌘Z). Copy Text again, and while "Reading text…" shows at the top, quickly draw a line with the Pencil: "The image changed while reading, so nothing was copied" appears.

### Test: Straighten stays responsive
_2026-10-11: passed Leah's hand test on 2026-10-11; she prefers the crisper rotation._ GPU audit recommendation 3, both parts (Leah's choice). A: the slider's preview is turned in the background (`StraightenPlan`: plan on the main thread, render off it, commit on it) and swapped in when ready; moves made meanwhile are merged; Apply finishes the newest angle right away; Cancel, Undo or any other command drops a turn in progress. B: rotation uses vImage (`Warp.rotated`): 450 → 205 ms at 45 MP; quarter and half turns land exactly (new test); with Crop to fit the edge pixels are repeated. Drop Shadow and Border are unchanged. 4 new app tests (`StraightenPreviewTests`). Rebuild with the script (option 2) first. Use Leah's CR3 (Downloads/7762545337.cr3), developed and opened, ideally with a second layer (Layer ▸ Duplicate Layer).
1. Image ▸ Straighten…, then drag the angle slider back and forth quickly. The slider and the window keep moving smoothly; the photo catches up a moment later instead of the whole app freezing.
2. Let go at about 3°. The preview settles on 3°.
3. Move the slider, and press Apply straight away, before the preview catches up. The result is turned by the angle the slider shows.
4. ⌘Z: the photo is back as it was, in one step. ⌘⇧Z turns it again.
5. Open Straighten again, move the slider, and press Cancel (or Esc) at once. Nothing changes, and there's nothing new to undo.
6. Draw a line along something that should be level: the angle and preview follow, as before.

### Test: Adjust Photo, Sharpen and Skew are faster
_2026-10-11: passed Leah's hand test on 2026-10-11._ GPU audit recommendations 2 and 4. Adjust Photo remembers each color's result on images of 2 MP and up (`ColorMemory`: a 64 MB table shared by all cores with atomic writes, freed after each run). The serial loops in blur (copy-in, coverage, alpha), Effects' copy-back, Sharpen and Skew now run on all cores. Results are byte-identical: 22 outputs (blur, Sharpen, Adjust Photo all and color-only, at 0.06 and 2.2 MP, with and without a soft selection, with see-through pixels; Skew both ways, smooth and sharp) hashed the same with the old and new code. Synthetic 45 MP timings, taken while a game was running: Sharpen 349 → 168 ms, Skew both ways 1,089 → 170 ms, Adjust Photo color only 580 → 230 ms, all sliders 1,006 → 769 ms; blur unchanged (its time is vImage's). Rebuild with the script (option 2) first. Use Leah's CR3 (Downloads/7762545337.cr3) and `TestImages/Stage 9 Practice Photo.png`.
1. Open the CR3 and click Open in the Develop window.
2. Adjustments ▸ Adjust Photo…: drag Exposure and Warmth. The preview follows faster than before (it used to take about a second per change).
3. Turn up Sharpness and Definition too, then Apply. The photo looks the same as the preview. ⌘Z undoes it in one step.
4. Effects ▸ Sharpen… on the photo: quicker than before, and it looks the same as it always has.
5. Image ▸ Resize and Skew… (⌘E) with 20° horizontal and 20° vertical skew: it finishes in a moment.

### Test: Help, phase 4: the reference
_2026-10-11: passed Leah's hand test on 2026-10-11._ Seven reference pages: Tools, Menus, Keyboard shortcuts, Panels, Settings, Privacy and Troubleshooting. Menus and Keyboard shortcuts are generated from the app by `make help` (`HelpDump.swift` writes the menus as JSON with `-ColorbeeDumpMenus`, no window; `Scripts/help-pages.py` writes the pages). Also: tooltips added for Batch Redact ▸ Blur… and Pixelate…, Export As and Import from iPhone or iPad; the brush hint no longer says "Shift has no effect". The Settings ▸ Shortcuts picture is still current. Rebuild with the script (option 2) first.
1. Help ▸ Colorbee Help: the contents page has a Reference list with seven pages.
2. Open any menu, pick three commands, and find each on the **Menus** page with the same name and shortcut.
3. In Settings ▸ Shortcuts, compare five shortcuts with the **Keyboard shortcuts** page.
4. In the Help menu's search box, type "magic wand", then "layer", then "export". Each finds a sensible page.
5. Read **Troubleshooting** and **Privacy**: anything that sounds wrong or unclear, tell Claude.

### Test: Shift straightens the brushes and Eraser
_2026-10-10: passed Leah's hand test on 2026-10-11._ Holding Shift while dragging keeps the stroke on one line, across or up and down from where it started, as the Pencil always did. Rebuild with the script (option 2) first. Use `TestImages/Help/Sample Screenshot.png`.
1. Brushes ▸ Marker, yellow Color 1. Hold Shift and drag along the "Email" row, wobbling the mouse up and down: the highlight stays perfectly level.
2. Hold Shift and drag mostly downward: the stroke goes straight down instead.
3. Without Shift, the stroke follows the mouse as before.
4. Repeat step 1 with the Round brush and with the Eraser (E): both stay level.
5. ⌘Z undoes each stroke in one step.

### Test: Help guides, phase 3
_2026-10-10: passed Leah's hand test on 2026-10-11._ Six new guides: Annotate an image, Work with layers, Fix up a photo, Pages and PDFs, Pixel art, and Save, export and share. Getting started gains the Retouch, Redact Brush and Step Badge tools and their keys (J, S, K, N); Redact a screenshot gains the Redact Brush. Written from the FRD and checked against the code (menu names, labels, keys). Notes: the iPhone import section describes only importing with no document open, since importing into an open document is pinned; Shift now straightens the brushes and Eraser too (Leah, 2026-10-10), so the highlighter tip uses it.
1. **Screenshots: taken by Claude on 2026-10-10** (window, toolbar, layers), with Leah's OK for screen access. The scene window is now 1440 points wide so the whole toolbar shows. Open the three pictures in `Help/Colorbee.help/Contents/Resources/en.lproj/images/` and check they look right.
2. Rebuild with the script (option 2). Help ▸ Colorbee Help: the contents page lists eight guides.
3. Follow each new guide with Colorbee open beside it, one at a time, using `TestImages/Help/Sample Screenshot.png` (Annotate, Pages), `TestImages/Stage 9 Practice Photo.png` (Fix up a photo, Layers), `TestImages/Stage 13/Red Eye Practice.png` (red-eye), `TestImages/Stage 12/Test Camera.dng` (RAW) and a new 32 × 32 image (Pixel art). Every step should work, and every menu name and key should match.
4. In the Help menu's search field type "clone", "PDF" and "pixel": each finds the right guide.
5. Dark mode (Settings ▸ General ▸ Dark): every page reads well.

**Help, phase 2 (2026-10-09): all 5 steps passed Leah's hand test on 2026-10-09.** Rebuild and run with the script first, then follow each guide exactly as
written on a clean launch, using `TestImages/Help/Sample Screenshot.png` (made-up details). Every step should work and
every menu name and key should match; note anything unclear.
1. Help ▸ Colorbee Help: the contents page lists **Getting started** and **Redact a screenshot**.
2. **Getting started:** read it with Colorbee open beside it. Check the toolbar, palette bar, key table, undo, sidebar and Settings descriptions against the app. Try the Magic Wand Option-click tip.
3. **Redact a screenshot:** open the sample in Preview, ⌘A ⌘C, then follow the guide from step 2 (File ▸ Paste into New Image) through Auto-Redact, Batch Redact, Before/After and the Clipboard History offer.
4. In the Help menu's search field type "redact": Redact a screenshot is listed. Type "keys": Getting started is listed.
5. Switch Colorbee to Dark (Settings ▸ General): both pages and their pictures read well.

### Test: Help, phase 1
_2026-10-09: screenshots taken by Leah (step 5); steps 1–4 passed Leah's hand test on 2026-10-11._ Plan: `Docs/HELP-PLAN.md`. Rebuild and run with the script first.
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
