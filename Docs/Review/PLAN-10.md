# Code review round 9: Budget Lightroom and the first layer follow-ups (sessions U, V, W)

Round 8 ([PLAN-9.md](PLAN-9.md), session T) ended with its fixes in `03dcc55`. Everything since is the "Budget
Lightroom" photo plan (stages 1a to 21 of [Development-Plan.md](../Development-Plan.md)), the layer follow-ups 22 to 24,
and fixes from Leah's hand tests: about 5,600 lines added in 71 source files. See them with
`git log --oneline 03dcc55..HEAD -- '*.swift' '*.metal' Scripts` and
`git diff 03dcc55..HEAD -- 'Sources/*.swift' 'Sources/*.metal' 'Packages/ColorbeeCore/Sources/*.swift' Scripts`.

Three sessions, each one area, each independent. Run **U** first: it has the code most able to lose work.

## Rules

The same as round 8 ([PLAN-9.md](PLAN-9.md), "Rules"): run locally in Leah's Colorbee folder; **don't touch git**;
your only output is your findings file, `Docs/Review/findings-<letter>.md`; **don't build, run the app or run tests**,
reason from the code (quick throwaway scripts in the scratch folder are fine, nothing long or memory-heavy); never open
Leah's personal files (Downloads, Desktop, Documents, Pictures), use only `TestImages`; don't re-report earlier rounds
([RESULTS.md](RESULTS.md)); decisions in FRD §23 are intended (entries from 2026-10-27 on are new, many marked "veto
any"), unless the code doesn't do what the entry says; don't suggest features. Follow "Findings file format" in
[PLAN.md](PLAN.md). Give Leah exact numbered steps and a `TestImages` file for anything she can see by hand. Rank by how
much it would hurt Leah: lost work, a crash, a freeze, a secret left visible, or a wrong exported picture first.

Leah has tested every stage by hand, so look for what hand testing misses: undo and redo that isn't exact, edge cases,
races, old files, big images, and the screen disagreeing with the export.

---

## Session U: history, layers and selections (highest risk)

- **History Snapshots** (`HistorySnapshot.swift`, `History+Snapshots.swift`; `History.removeAll`; `Editor` "History
  Snapshots"; `HistoryPanels.swift`). Taking a snapshot compresses every layer to its own scratch file; going to one is
  a layer step whose `LayerStackState` now carries the canvas **size**. Check: going to a snapshot after a crop,
  resize, rotation, merge, layer delete or undo past it, then undoing and redoing that step; the history budget and
  spilling (`heldLayerBuffers`, `evictLayers`) when that step holds buffers of a different size; Layer objects shared
  between a snapshot and the canvas; parked pages; `removeAll` after a redaction leaving nothing behind; the scratch
  file's lifetime.
- **`LayerStackState.size`** (`Canvas.swift`): every layer step now restores the size. Can any existing layer step
  (merge, flatten, delete, move, settings) restore a stale size?
- **Lock Transparent Pixels** (`Layer.locksTransparency`; `Edit.keepLockedTransparency` and `Canvas.keepLockedTransparency`
  in `History.swift` and `Canvas.swift`; the renderer calling it before each frame; `Canvas.erasedFill`;
  `ProjectFile`). Every tool, effect, preview and Delete should keep a locked layer's clear area exactly and each
  pixel's opacity, mid-stroke too. Look for writes that skip `willModify` (or write outside the rect they announce), a
  preview's `restoreOriginals` then re-render, floating selections placed onto such a layer, mirrored (Symmetry)
  strokes, merges, and Undo on Active Layer. Is `lockedEdits` ever left holding work for an edit that's gone? Cost
  per frame?
- **Layer follow-ups**: `LayerActions.stampVisible`, `setVisibility`; `Editor.toggleIsolation` (the `isolation` record
  across undo, page changes and layer deletion); `selectAllLayers`; **Align and Distribute** (`LayerAlign.swift`,
  `PixelBuffer.visibleBounds`; `Editor` "Align and Distribute"): the off-canvas check, rounding, adjustment and empty
  layers among the chosen, one exact undo step.
- **Canvas anchor and Trim** (`CanvasAnchor.swift`, `ImageActions.resizeCanvas(to:anchor:)` now moving the selection
  too; `Trim.swift`, `ImageActions.crop(to:named:)`, `Editor.trim`).
- **Selections** (stages 7 to 10): `SelectionMask+Modify.swift` (Expand, Contract, Smooth; the EDT and the soft path;
  canvas edges), `ColorRange.swift`, `LuminanceRange.swift`, `GraduatedSelection.swift`, the range bars in `Editor`;
  **Paste in Place** (`ClipboardImage.swift`, `Editor.paste(_:inPlaceAt:)`).

## Session V: Adjust Photo, its filters and the screen matching the export

- **The color pipeline** (`PhotoAdjustments.swift` `PhotoEdit.colorTransform`, `ColorMixer.swift`, `ColorGrading.swift`,
  `PointColors.swift`, `ToneCurve.swift`, `WhiteBalance.swift`, `PhotoAuto.swift`; `ColorLookup.swift`): exact
  results, the composed-closure speed fix (per-pixel reference counting), gray staying gray, Black & White.
- **Detail, Effects and grain** (`PhotoDetail.swift` `DetailAmounts` and `PhotoAdjustments.detail`; `PhotoEffects.swift`
  `Vignette.Shape`, `Grain`; `Effects+Photo.swift` `photoAdjusted` with `Placement`): old projects must look exactly
  as before (`TestImages/Photo Editing/Old Adjust Photo.colorproj` against its PNG); the mask view
  (`showsSharpeningMask`) must never be applied, saved or copied.
- **The shader** (`Shaders.metal` `adjust_photo_fragment`, `vignette_strength`, `grain_*`, `composite_fragment`'s
  clipping warnings; `Renderer.swift`'s blur slots, `QuadUniforms`, the effects buffer): does the screen match
  `photoAdjusted` for every setting, at any zoom, on a clipped adjustment layer, with several vignettes and grains,
  and with the 4 KB `setFragmentBytes` limit? The uniform layout against the Metal struct.
- **Filters and looks** (`PhotoFilter.swift` `forFilters`, `scaled`; `ColorLook.swift`, `CubeFile.swift`;
  `FilterStore.swift`): Intensity scaling only amounts; a damaged or huge .cube; the table's binary coding; old filter
  files and beta 7 (projects and `Photo Filters.json` read by an older Colorbee must not lose the rest).
- **The panel** (`AdjustPhotoPanel.swift`, `PhotoControls+*.swift`, `ToneViews.swift` histogram, tone graph and split
  slider, `ColorWheel.swift`, `RangeSlider.swift`): one undo step per drag; the histogram's throttle; the hand
  (`Editor.beginPictureDrag` and on; `CanvasView`'s `.pictureAdjust`) and the eyedroppers on a panel or an Adjust Photo
  layer; Copy and Paste Settings and Same as Last (`PhotoSettingsStore.swift`).

## Session W: export, Vision, the readout and the menus

- **Export** (`ExportColor.swift`, `ImageCodec.converted`, `ImageCodec.encode(…limit:)`, `SaveSnapshot.encoded`; the
  panel in `ImageDocument.swift`; presets in `Settings.swift` and `ExportPreset.swift`): the profile in the file, the
  matte converted with the picture, the size limit's search and its error, old preset data decoding.
- **Reading what's shown** (`Canvas.patchAsShown` padding by `Effect.reach`, `Effects.Placement`, `colorAsShown`,
  `PixelBuffer.averagedPixel`; `Editor.pointerColor`, `readoutColor`, `pickHexToCopy`, `pickColor` with Sample Size;
  `StatusBar.swift`): does a patch always match the export (vignette, grain, every blur, clipped adjustments, canvas
  edges)? Cost on every mouse move.
- **Vision** (`FaceFinder.swift`, `RectangleFinder.swift` and its edge check; Auto-Redact's Faces row in
  `AutoRedact.swift` and `Editor`; Perspective Correction's corner search and Reset): coordinates (Vision's origin is
  bottom-left), a search finishing after the tool closed or the image changed, a Faces row that must never match text,
  and a face missed being a privacy miss.
- **Crop guides** (`CropOverlay.swift`, `Editor.nextCropOverlay`), **the anchor sheet** (`CanvasPropertiesSheet.swift`).
- **Menus and wiring** (`MainMenu.swift`, `DocumentWindow.swift` actions and validation, `Snapshot.swift` options,
  `SettingsFolder.swift`, `Scripts/make-beta.sh`): commands enabled when they'd do nothing or be refused, keys that clash
  (⌥⌘A, ⌃⌘C, ⌥⇧⌘V), commands working while an effect bar or sheet is open.

New test files: `TestImages/Photo Editing/Looks/` (three .cube files), `TestImages/Trim Practice.png`,
`TestImages/Trim Practice Solid.png`, `TestImages/Auto-Redact Faces.png` (made-up faces),
`TestImages/Several Layers/Align Practice.colorproj`.

## Prompts for Leah

Run each in a fresh local session in the Colorbee folder, on **Opus, high effort**. U first; V and W can follow in any
order:

> You're a reviewer for Colorbee. Read `Docs/Review/PLAN-10.md` and do **session U**, following its rules exactly:
> review only, don't touch git, don't build or run anything. Write your findings to `Docs/Review/findings-U.md`, then
> tell me how many findings you have at each severity.

For V and W, change both letters.
