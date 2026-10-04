# Code review plan, round 2: bug kinds across the whole app

Round 1 ([PLAN.md](PLAN.md), results in [RESULTS.md](RESULTS.md)) reviewed only stages 8 and 9, by area. Its
26 findings were all real, and most fell into a few kinds of bug. Round 2 looks for those kinds across the
**whole app**, stages 1–9, at commit `81f8cfb` or later on `main`.

- **Cloud sessions:** E, F and G (below). Run E first: Auto-Redact is the privacy feature, so a missed
  redaction is the worst thing Colorbee could do.
- **Local sweeps (no cloud credits):** the mechanical checks at the end, done by the local engineer.
- **The rules are the same as round 1.** Every session reads and follows "Rules for every review session" and
  "Findings file format" in [PLAN.md](PLAN.md): review only, no builds, concrete findings, one findings file on
  its own `review/<letter>` branch.
- **Don't re-report round 1.** Read [RESULTS.md](RESULTS.md) first; those findings are fixed. Report a
  round-1 fix only if it's wrong or incomplete.

---

## Session E: stale results, and Auto-Redact first (highest risk)

Background work that finishes after the document changed and applies a result that no longer fits. Round 1
found this in Remove Background (a mask applied after a flip), effect previews and Clipboard History.

Files: `Sources/Colorbee/Editor.swift` (Auto-Redact: `beginAutoRedact`, `refreshAutoRedactMatches`,
`applyAutoRedact`, `cancelAutoRedact`; the textured shape previews, `RenderedShape`; every `Task`,
`Task.detached` and `DispatchQueue` in the file), `AutoRedactSheet.swift`, `DocumentWindow.swift` (what stays
enabled while the Auto-Redact sheet is open), `CanvasView.swift`, `ImageDocument.swift`,
`ClipboardHistory.swift`, `HistoryPanels.swift`; in core, `AutoRedact.swift`, `TextRenderer.swift`,
`Shapes.swift`, `PaintStyle.swift`.

Look especially for:
- **Auto-Redact leaving text readable.** Two leads, unconfirmed:
  1. It scans the flattened image (every layer) but applies the redaction only to `canvas.activeLayer`.
     Can text on another layer stay visible after Apply? Also check hidden layers, layers with low opacity,
     adjustment layers, a locked active layer, and a floating selection.
  2. Nothing checks that the image is unchanged between the scan and Apply. Can a flip, rotate, crop, resize,
     undo, layer switch or new stroke during the scan or while the sheet is open move the text out from under
     the boxes?
  Also: boxes that don't cover the whole glyphs (descenders, rotated or italic text, the box rounding), the
  selection clipping, Blur and Pixelate strong enough to hide the text, and anything else that could leave
  matched text readable while the user believes it's redacted.
- **Any async result applied without checking** the document, the active layer and history's revision are
  still what they were when the work started.
- **Main-thread work on the whole image** (a flatten or composite of every layer on the main thread), against
  NFR-6.

## Session F: the screen versus the saved file

The display and export draw the same image with different code (Metal for the screen, Swift for files).
Round 1 found Posterize looking different on screen from the export.

Files: `Sources/Colorbee/Shaders.metal` and `Renderer.swift` (layer compositing, blend modes, opacity, the
floating selection, pending shapes and text, the checkerboard), `CanvasTextView.swift`; in core,
`Compositing.swift`, `BlendMode.swift`, `AdjustmentCompositing.swift`, `Canvas.swift` (`flattened`,
`composited(through:)`), `FloatingSelection.swift`, `SelectionActions.swift` (placing), `Shapes.swift`,
`TextRenderer.swift`, `ImageCodec.swift`, `ExportPreset.swift`, `SaveSnapshot` (`Sources/Colorbee/SaveSnapshot.swift`).

Look especially for:
- **All 17 blend modes:** compare the shader against `Compositing` line by line: formulas, straight versus
  premultiplied alpha, how transparent pixels and opacity enter, clamping.
- **Layer opacity and hidden layers**, including under and over adjustment layers.
- **Before and after placing:** a pending shape, pending text or floating selection should look the same once
  placed (position to the pixel, anti-aliasing, color, opacity, rotation, resizing).
- **Export:** transparency (formats without alpha, the transparent key, Color 2 as the matte), the embedded
  color profile, JPEG/HEIC quality, export presets' sizes, and whether what's exported is what the screen shows
  at 100%.

## Session G: undo restoring the wrong layer copies, and history edge cases

Round 1 found steps that kept stale copies of a layer (the overnight redo bug) and steps that merged
wrongly. Review A covered `History.swift` itself; this session covers the **commands** that put layer copies
in and out of the document.

Files: `Packages/ColorbeeCore/Sources/ColorbeeCore/` `LayerActions.swift` (add, delete, duplicate, merge down,
merge visible, flatten, reorder, apply adjustment), `SelectionActions.swift`, `ImageActions.swift`,
`Layer.swift`, `Canvas.swift` (`restore`, `layerStackState`, `replaceContents`), `History.swift` (only
`undoOnLayer`, `candidate(for:)` and `restoreOriginals`); in the app, `Editor.swift` (Revert Layer,
`markSaved` and `savedLayers`, Before/After, `recordingChanges`, `finishInteractions`, layer settings
previews), `HistoryPanels.swift`.

Look especially for:
- **One buffer in two places:** a layer's buffer that's also held by the saved snapshot (Revert Layer,
  "Last Saved"), by Before/After, by a duplicate, or by another layer, so editing one changes the other.
- **Undo on Active Layer** (FR-8.3) on every kind of step: layer changes, merges, geometry, rotations,
  selections. Does it ever undo something on another layer, or leave a step that redoes wrongly?
- **Steps that aren't exact:** any command whose undo doesn't bring back exactly the image, layers, layer
  settings and selection from before.
- **Commands that change the document outside history**, or mark it edited when nothing changed (or not when
  something did).

---

## Local sweeps (the local engineer, on the Mac)

1. **Damaged and unusual files:** every place that reads an outside file or the clipboard (images, projects,
   palettes, filters, redaction patterns, shortcuts, settings). Check limits on size, unchecked number
   conversions and anything that can trap, with a unit test per reader where it's in core.
2. **Traps:** search the code for `Int(` conversions of `Double` or `Float` values, `UInt8(` conversions,
   unchecked arithmetic on sizes, and force-unwraps. Each must be safe for any input that can reach it.
3. **Menus against commands:** for every menu item, compare `validateMenuItem` with the command's own checks
   (locked layer, adjustment layer, selection, effect open, search running) so nothing is enabled and then
   refuses, or disabled when it would work.

## After each session

As in round 1: Leah says "review E is done"; the engineer fetches the branch, checks every finding against
the code, fixes real bugs test-first on `main`, records the outcomes in `RESULTS.md` and deletes the branch.
