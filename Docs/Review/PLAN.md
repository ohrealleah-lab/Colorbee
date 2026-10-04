# Code review plan: stages 8 and 9

Leah is reviewing the stage 8 and 9 work with **cloud sessions** (Claude Code on the web), one area per
session. Cloud sessions only **read and report**; every fix is made locally, on the Mac, with tests.

- **What's reviewed:** everything since commit `0970a64` ("Mark stage 7c as tested by hand"):
  `git diff 0970a64..HEAD`. About 56 source files and 4,300 changed lines of Swift and Metal.
- **Order:** sessions A and B cover the riskiest code. Run A first, check how many credits it used, then
  decide on the rest. Each session is independent.

---

## Rules for every review session (cloud Claude, read this first)

1. **Review only. Don't change any source file, project file, doc or test.** Your only output is one findings
   file (rule 6). This overrides CLAUDE.md's workflow section, which is for the local engineer.
2. **Don't try to build or run tests.** Colorbee is a macOS app; the code uses AppKit, Metal, Vision,
   Accelerate and Core Graphics, which aren't available in the cloud sandbox. `make`, `xcodebuild` and
   `swift build` won't work, so don't spend time on them. Reason from the code: trace the paths, follow the
   values, check the edge cases. You may write small throwaway scripts in another language to check math,
   but don't add them to the repo.
3. **Read for context before judging:** `CLAUDE.md` (architecture and rules), `Docs/STATUS.md`, and the FRD
   (`Docs/FRD.md`), especially the §23 decision log. Anything a §23 entry chose on purpose (marked "veto any"
   or decided by Leah) is intended behavior, not a bug, unless the code doesn't do what the entry says.
4. **Only real problems.** Report bugs: crashes, data loss or corruption, wrong pixels, undo that isn't
   exact, races, leaks, broken behavior versus the FRD, and performance problems that break the NFRs.
   No style, naming or "consider refactoring" notes. If you're unsure, include it with confidence "Low"
   and say what would confirm it.
5. **Be concrete.** For each finding: the exact file and line (at the commit you reviewed), what goes wrong,
   and the specific input or sequence of steps that triggers it. "This could be a problem" isn't enough.
6. **Output:** create the file `Docs/Review/findings-<letter>.md` (for example `findings-A.md`) on a new
   branch named `review/<letter>` (for example `review/a`), commit it, and push the branch. Don't open a pull
   request and don't touch `main`. If you find nothing, still push the file and say what you checked.

### Findings file format

```markdown
# Review <letter>: <area>
Reviewed at commit: <full hash>
Checked: <one line per file or topic you covered>

## <n>. <one-line summary>
- **Severity:** Critical (crash, data loss, corrupted image or undo) · High (wrong result the user sees)
  · Medium (edge case) · Low (minor)
- **Confidence:** High · Medium · Low
- **Where:** `path/to/File.swift:123` (and any other lines involved)
- **What happens:** the failure, plainly.
- **How to trigger it:** the inputs or steps.
- **Why:** the reasoning, with the relevant code quoted briefly.
- **Test that would catch it:** a short description of a unit test (the local engineer writes it).
```

Order findings most severe first.

---

## Session A: undo history, memory and whole-image changes (highest risk)

Files: `Packages/ColorbeeCore/Sources/ColorbeeCore/` `History.swift`, `PixelBuffer.swift`, `Canvas.swift`,
`ImageActions.swift`, `Orientation.swift`, `Layer.swift`, `Warp.swift` (the `ImageActions` extension at the
end), `Decorations.swift` (how it grows the canvas and records the step), `ParallelRows.swift`,
`FloodFill.swift`; and in the app, `Sources/Colorbee/Renderer.swift` (only `PixelTexture.generation` and the
blur targets).

Look especially for:
- **Undo and redo that aren't exact**, in any order of steps: tile edits, layer-stack changes, geometry
  changes (crop, resize, Drop Shadow growth, straighten, perspective), and rotations and flips, which are
  undone by applying the inverse transform (`Edit.willTransform`).
- **Layer eviction:** layers that only history holds are written to the spill file and their memory released
  with `madvise` (`PixelBuffer.discardContents`), then read back on undo (`History.restore`). Can a buffer be
  read, drawn or written while it's discarded? Can two entries share a buffer so that one restores it and the
  other has stale state? What about `undoOnLayer`, `discardRedo`, `forgetRedo` and failed spill reads?
- **Byte accounting** (`tileBytes`, `layerBytes`, `refreshLayerBytes`) drifting, so history uses far more
  memory than its budget, or spills things it shouldn't.
- **`PixelBuffer.isUntouched`** (uses `mincore`): any way it says "untouched" for a buffer that holds pixels,
  which would lose data in transforms and crops (`Layer.holdsNoPixels`).
- **Thread safety in `ParallelRows`**: bands that write outside their own rows, or shared state written from
  several threads (the region search in `FloodFill`, the distance transform in `Decorations`).

## Session B: background work and the app's editing sessions (highest risk)

Files: `Sources/Colorbee/Editor.swift` (the effect session: `beginEffect`, `previewEffect`,
`startBackgroundPreview`, `showBackgroundPreview`, `applyEffect`, `cancelEffect`, `endEffectSession`;
`renderDecorationPreview`; the canvas tools for crop, perspective and straighten; `findSubject` and subject
picking; the filter-saving functions), `Packages/ColorbeeCore/Sources/ColorbeeCore/EffectPreview.swift`,
`Sources/Colorbee/ClipboardImage.swift`, `PasteboardImages.swift`, `SaveSnapshot.swift`,
`ImageDocument.swift` (background saving: `save(to:…)`, `canAsynchronouslyWrite`, `data(ofType:)`),
`DocumentWindow.swift`, `CanvasView.swift` (the `.canvasTool` drag and the context menu),
`Packages/ColorbeeCore/Sources/ColorbeeCore/Subjects.swift`.

Look especially for:
- **Races:** a background preview finishing after Apply, Cancel, another effect opening, or a document
  change; anything that reads or writes a `PixelBuffer` on a background thread while the main thread can
  change it; misuse of `@unchecked Sendable`, `nonisolated` or `MainActor.assumeIsolated`.
- **Apply committing something other than what's on screen**, or a preview left in the image after Cancel.
- **Background saving:** the snapshot taken in `save(to:…)` and used in `data(ofType:)` on another thread.
  Can a save write stale or mixed content, or the wrong snapshot when saves overlap (autosave plus ⌘S)?
- **The step-based previews** (Drop Shadow, Border, Straighten undo the last preview step and redo it): can
  Cancel or Apply leave history, the canvas size, the selection or the document's edited state wrong?
- **Clipboard promises:** can pasting deadlock or hang (the provider waits on a condition until the PNG is
  encoded)? What if the encoding fails, or a second copy happens before the first finishes?
- **Subject finding:** the async Vision call and what happens if the document changes before it returns.

## Session C: pixel math, and screen versus export

Files: `Packages/ColorbeeCore/Sources/ColorbeeCore/` `Effects.swift`, `Effects+Texture.swift`,
`Effects+Photo.swift`, `PhotoAdjustments.swift`, `PhotoAuto.swift`, `PhotoFilter.swift`,
`Effect+Codable.swift`, `ProjectFile.swift`, `Levels.swift`, `Curves.swift`, `Histogram.swift`,
`ColorLookup.swift`, `AdjustmentCompositing.swift`, `Warp.swift`, `Decorations.swift`;
`Sources/Colorbee/Shaders.metal` and `Renderer.swift` (the adjustment-layer paths).

Look especially for:
- **Screen and export disagreeing:** adjustment layers are drawn on screen by `Shaders.metal`
  (`adjust_lookup_fragment`, `adjust_photo_fragment`) and in exports by the Swift code. Compare the math line
  by line: order of operations, ranges, clamping, premultiplied versus straight alpha, the vignette, and the
  detail sliders' blur radii and weights.
- **Out-of-range values:** division by zero, `UInt8` overflow traps (Swift traps on overflow), NaN, a
  negative or zero size, an empty selection, a 1×1 image, angles at ±45°, a perspective quad with crossed or
  coincident corners.
- **Wrong math** in Levels, Curves (monotone cubic), Posterize, Sepia, Vibrance, the homography, the
  straighten sizes (Crop to Fit should leave no empty corners), the distance transform
  (Felzenszwalb–Huttenlocher), and the Drop Shadow blur and opacity.
- **Saving:** effect JSON that doesn't round-trip, and projects that fail to open.

## Session D: interface behavior against the FRD

Files: `Sources/Colorbee/` `AdjustPhotoPanel.swift`, `ToneViews.swift`, `CropOptions.swift`,
`AdjustmentsPanel.swift`, `DocumentView.swift`, `LayersPanel.swift`, `MainMenu.swift`, `DocumentToolbar.swift`,
`PaletteBar.swift`, `Settings.swift`, `StatusBar.swift`, `FilterStore.swift`, plus the FRD sections FR-9.5,
FR-11, FR-14 and the §23 entries dated 2026-10-03.

Look especially for:
- **Behavior that doesn't match the FRD** or its §23 decisions: missing controls, menu items enabled when
  they can't work (or greyed out when they can), wrong defaults, wrong ranges.
- **SwiftUI state bugs:** stale values after switching layers or effects, bindings that write on every
  redraw, and controls that keep old state (`@State`) when the document changes.
- **The Curves editor:** points that can be dragged past their neighbors or off the graph, the end points,
  and removing points.
- **Filters:** rename, delete, import and export edge cases (duplicate names, built-in names, bad files).
- **Accessibility:** controls with no VoiceOver label, or labels that are wrong.

---

## After each session (local, on the Mac)

1. Leah tells the local engineer "review A is done" (or B, C, D).
2. The engineer fetches the branch (`git fetch origin review/a`) and reads the findings.
3. Each finding is checked against the code. Real bugs get a failing test first where possible, then the fix,
   on `main`, with `make test` and the Release build passing.
4. Outcomes go in `Docs/Review/RESULTS.md`: fixed (with the commit), not a bug (and why), or deferred.
5. The `review/<letter>` branch is deleted once its findings are handled.
