# Code review plan, round 3: privacy, drawing tools, and the older stages

Rounds 1 and 2 ([PLAN.md](PLAN.md), [PLAN-2.md](PLAN-2.md); results in [RESULTS.md](RESULTS.md)) covered
stages 8 and 9 by area, then three kinds of bug across the app. Round 3 covers what's left: where redacted
content can survive, the drawing tools and selections (stages 1–5), and stages 1–7 against the FRD. Review
at the newest commit on `main`.

- **Order:** run H first. Auto-Redact is the privacy feature, and a secret that survives somewhere the user
  can't see is the worst thing Colorbee could do. I and J are independent and can run at the same time.
- **The rules are the same as before.** Every session reads and follows "Rules for every review session" and
  "Findings file format" in [PLAN.md](PLAN.md): review only, no builds, concrete findings, one findings file on
  its own `review/<letter>` branch.
- **Don't re-report rounds 1 and 2.** Read [RESULTS.md](RESULTS.md) first; those findings are fixed. Report a
  fix only if it's wrong or incomplete.
- **Leah hand-tests findings.** Where a finding can be shown by hand, give exact steps she can follow, and say
  what test image would show it.

---

## Session H: where the original pixels survive after redaction (highest risk)

Auto-Redact, Solid Fill, Blur and Pixelate are meant to remove secrets. Find every place the unredacted pixels
can still be found afterwards, by the user, or by anyone they send a file to or who uses their Mac.

Files: `Sources/Colorbee/ImageDocument.swift` (autosave, `canAsynchronouslyWrite`, saving, Versions, window
restoration, export, Share, Print, Set as Desktop Picture), `ClipboardHistory.swift`, `ClipboardImage.swift`,
`PasteboardImages.swift`, `DocumentWindow.swift` (copy, cut, paste, Copy Merged), `Editor.swift` (Auto-Redact,
Before/After: `asOpened`, `lastSaved`; Revert Layer: `savedLayers`), `SaveSnapshot.swift`, `HistoryPanels.swift`,
`Info.plist`; in core, `History.swift` (the spill file: where it lives, when it's deleted, what it holds),
`ProjectFile.swift`, `ImageCodec.swift` (metadata written into exported files), `AutoRedact.swift`,
`AutoRedact+Apply.swift`, `Effects.swift` (Blur and Pixelate at the strengths Auto-Redact uses).

Look especially for:
- **Versions and autosave:** after redacting and saving, can File ▸ Revert To ▸ Browse All Versions bring
  back the unredacted image? Does autosave-in-place keep earlier versions? (Describe what macOS does with an
  `NSDocument` that autosaves in place, and what Colorbee does or doesn't do about it.)
- **Clipboard History:** copied images are kept on disk. Does redacting the document leave the original
  screenshot in Clipboard History, on disk, and for how long? Where is the folder, and is it ever cleared?
- **The undo history's spill file:** old steps go to a temporary file. What's in it, where, is it deleted on
  close, quit and crash, and could another user or app read it?
- **Projects:** can a saved `.colorproj` hold unredacted pixels: a hidden layer, a layer under an adjustment
  layer, pixels outside a redaction box's padding, undo data, or a thumbnail?
- **Image files:** metadata (EXIF, text chunks, thumbnails, the original file's metadata carried over) that
  could hold the original image or its text.
- **Strength:** are Blur and Pixelate at Auto-Redact's strengths strong enough that the text can't be read
  back (by eye, or by sharpening)? Is Solid Fill fully opaque on every layer, including ones below 100%
  opacity or in a blend mode?
- **Anything else** that keeps an unredacted copy: Before/After's "As Opened", Revert Layer's saved layers,
  caches, the Share temp folder, the desktop pictures folder, logs (`Diagnostics.swift`).

## Session I: drawing tools and selections (stages 1–5)

The oldest code, which rounds 1 and 2 only touched indirectly.

Files: `Packages/ColorbeeCore/Sources/ColorbeeCore/` `Brush.swift`, `BrushStroke.swift`, `RoundBrushStroke.swift`,
`BrushTexture.swift`, `DabWalker.swift`, `CoveragePainter.swift`, `AxisLock.swift`, `FloodFill.swift`,
`Gradient.swift`, `Shapes.swift`, `PaintStyle.swift`, `TextRenderer.swift`, `SelectionMask.swift`,
`SelectionActions.swift`, `SelectionHandle.swift`, `FloatingSelection.swift`, `Viewport.swift`, `Geometry.swift`,
`Pixel.swift`, `Compositing.swift`; in the app, `Editor.swift` (painting, eraser, color eraser, fill, eyedropper,
magic wand, gradient, symmetry, measure, the selection drags) and `CanvasView.swift` (mouse, tablet, pressure,
coalescing, keys).

Look especially for:
- **Wrong pixels:** at the canvas edges and corners, on a 1 × 1 or 1 × N image, with brush sizes at both ends
  of their range, with symmetry on (the mirrored stroke on the center line, odd and even sizes).
- **Strokes:** fast mouse movement skipping pixels, the end of a stroke, a click with no movement, pressure 0
  and 1, the Shift axis lock, and right-click painting with Color 2.
- **Eraser and Color Eraser:** exact-match behavior with straight alpha, transparent versus Color 2
  backgrounds, and on layers other than the background.
- **Fill and Magic Wand:** tolerance 0 and 100%, transparent pixels, a fill across the whole canvas, a
  selection limiting the fill, scanline correctness (no gaps, no leaks through diagonal gaps unless intended).
- **Selections:** off-by-one at the marquee's edges, lasso and polygon with crossing or tiny paths, adding and
  subtracting, Invert, selections partly outside the canvas, moving, nudging and resizing a selection past the
  edge, and Delete with a transparent versus opaque layer.
- **Coordinates:** the view-to-image conversion at extreme zoom levels and with the canvas scrolled.

## Session J: stages 1–7 against the FRD, and documents

Round 1's session D checked the interface for stages 8 and 9 only. This one covers the rest.

Files: `Sources/Colorbee/` `MainMenu.swift`, `DocumentWindow.swift`, `DocumentWindowController.swift`,
`AppDelegate.swift`, `ImageDocument.swift` (opening and saving each format, autosave, window restoration, the
project-or-image rule), `DocumentToolbar.swift`, `PaletteBar.swift`, `Palettes.swift`, `CustomColors.swift`,
`StatusBar.swift`, `Settings.swift`, `ShortcutSettings.swift`, `ShortcutStore.swift`, `TextStyles.swift`,
`Galleries.swift`, `CanvasPropertiesSheet.swift`, `ResizeSkewSheet.swift`, `HistoryPanels.swift`,
`ClipboardHistory.swift`, `LayersPanel.swift`, `ToolAppearance.swift`; core `Shortcuts.swift`,
`ExportPreset.swift`, `ImageCodec.swift`; the FRD sections FR-1 to FR-8 and FR-10 to FR-13, with their §23
entries.

Look especially for:
- **Behavior that doesn't match the FRD** or its §23 decisions: missing commands, wrong shortcuts or defaults,
  menu items enabled when they can't work (or greyed out when they can).
- **The shortcut editor (FR-15.3):** conflicts, reserved shortcuts, resetting, importing and exporting, and
  menus that keep an old key equivalent after a change.
- **Documents (FR-12):** opening every supported format (including ones with unusual color profiles, 16-bit,
  grayscale, CMYK, animated or multi-page files), saving back to the same format, what's lost and whether the
  user is warned, autosave and window restoration after a crash or relaunch, and Save As between image and
  project.
- **Palettes, custom colors, text styles and settings:** edge cases in naming, deleting the one in use, and
  values that don't survive a relaunch.
- **Accessibility:** controls in the older panels and sheets with no VoiceOver label or a wrong one.

## After each session

As before: Leah says "review H is done"; the engineer fetches the branch, checks every finding against the
code, fixes real bugs test-first on `main`, records the outcomes in `RESULTS.md` and deletes the branch.
