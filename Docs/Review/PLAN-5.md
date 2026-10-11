# Code review plan, round 5: stage 13, iPhone import, layer storage, app tests and the speed fixes

Rounds 1–4 ([PLAN.md](PLAN.md), [PLAN-2.md](PLAN-2.md), [PLAN-3.md](PLAN-3.md), [PLAN-4.md](PLAN-4.md); results
in [RESULTS.md](RESULTS.md)) covered everything up to commit `ed3a600` (2026-10-05). Round 5 covers what's been
built since: about 70 commits and 6,600 lines. See them with `git log --oneline ed3a600..HEAD` and
`git diff ed3a600..HEAD -- '*.swift' '*.metal' '*.yml' Makefile Scripts`.

What's new, in short:
- **Stage 11:** File ▸ Import from iPhone or iPad (Continuity Camera; importing into an open document is a known,
  pinned problem: see STATUS, don't re-report it).
- **Stage 13:** Copy Text, Step Badges, the Redact Brush, Remove and Spot Heal (Match Surroundings), the Clone
  Stamp and local brushes, Smudge, Remove Red-Eye, soft-edged selections (Feather), and adjustment layers that
  change only the layer below (clipping). Merge Adjustment.
- **Layer storage (L15):** layers stored and parked in compressed ~4 MB pieces (`LayerPixels`), also in .colorproj.
- **App tests:** a hidden test host (`TestHost`, `COLORBEE_TESTING`) and 75 Editor tests; `make coverage`.
- **Help generator:** `HelpDump` (`-ColorbeeDumpMenus`) and `Scripts/help-pages.py`; `make help`.
- **Speed fixes (Docs/GPU-AUDIT.md):** one reused `CIRAWFilter` for Develop previews; `ColorMemory` for Adjust Photo;
  serial loops in blur, Sharpen, Skew and the effects' copy-back made parallel; Straighten turned in the background
  (`StraightenPlan`) and rotated with vImage.
- Smaller: Shift straightens brush and eraser strokes; the sidebar closes with its last panel; the Step Badge being
  placed is placed before Save, Export, Copy, Share and Print.

Three sessions, **N**, **O** and **P**. They're independent and can run at the same time. If only one runs at a
time, run N first: it's about privacy, which is the heart of Colorbee.

## Rules (these replace rule 6 of PLAN.md for round 5)

These sessions run **locally, in Leah's Colorbee folder**, not in the cloud. Follow "Rules for every review
session" and "Findings file format" in [PLAN.md](PLAN.md), with these changes:

- **Don't touch git.** Don't switch branches, commit, stash or push. Other sessions may be working in the same
  folder. Your only output is one new file, `Docs/Review/findings-<letter>.md` (`findings-N.md`, `findings-O.md` or
  `findings-P.md`), written into this folder. The engineer commits it.
- **Don't build, run the app or run tests.** Reason from the code. (You may run quick throwaway scripts in the
  scratch folder to check math or an API's behavior, but never anything long or memory-heavy: Leah's Mac once froze
  during a heavy test.)
- **Never open Leah's personal files** (her Downloads, Desktop, Documents or Pictures, including any .cr3 photo).
  Use only the files in `TestImages`.
- **Don't re-report rounds 1–4.** Read [RESULTS.md](RESULTS.md) first; report an old fix only if the new work
  broke it.
- **Leah hand-tests findings.** Where a finding can be shown by hand, give exact numbered steps, and name a test
  file, for example `TestImages/Help/Sample Screenshot.png` (made-up email, phone and API key),
  `TestImages/Stage 13/` (Remove Sky, Remove Bricks, Remove Sand, Remove Panel, Red Eye Practice),
  `TestImages/Stage 10/Three Page Test.pdf`, `TestImages/Stage 9 Practice Photo.png` or
  `TestImages/Stage 12/Test Camera.dng`. Say "draw a selection box", not "marquee".
- **Decisions are in FRD §23**, including the entries dated 2026-10-05 to 2026-10-11, and the behavior in FR-3.4
  (soft edges), FR-4.6 (retouching), FR-5.3 (step badges), FR-8.4 (adjustment layers and "Only the layer below"),
  FR-9.5 (Remove Red-Eye), FR-9.6 (Redact Brush), FR-10.4 (Copy Text) and FR-11.7 (iPhone import). What they chose
  on purpose isn't a bug. Straighten's pixels changing slightly (vImage, crisper) is Leah's choice.
- Rank findings by how much they'd hurt Leah or a tester: a secret left visible, lost work or a crash first.

---

## Session N: privacy, redaction and saved data (highest risk)

Colorbee's promise is that a redaction removes the secret, and that nothing it writes says more than the user
chose. Stage 13 added new ways to redact (the Redact Brush), soft selections that could leave a secret half there,
text read out of images, and a new way layers are stored and written to disk. Find every way an unredacted pixel,
or data the user didn't choose to share, can survive or leak, and every way saved work can be lost or damaged.

Files: core `RedactBrushArea.swift`, `AutoRedact+Apply.swift` (`hardened`), `SelectionMask.swift` (soft masks:
`hardened`, `feathered`, combining, `connectedRegions`, `inverted`), `SelectionActions.swift`,
`FloatingSelection.swift` (`Pixel.taking`, `Pixel.vacated`, soft lift), `Effects.swift` (`weight`, `mixed`),
`TextReader.swift`, `LayerPixels.swift`, `ProjectFile.swift` (`pieceRows`, `pieces`, `clipped`), `Page.swift`
(`unpark`, `unparkedFrom`), `PageStack.swift` (`insert(_:at:named:)`), `PDFPages.swift` (`scannedPage`),
`StepBadge.swift`, `History.swift` (changes since round 4); app `Editor.swift` (Redact Brush strokes,
`placePendingObjects`, Copy Text, `importPages`, soft-selection commands, Feather), `ContinuityImport.swift`,
`ImageDocument.swift` and `SaveSnapshot.swift` (changes since round 4), `DocumentView.swift` (the notice and the
Feather sheet).

Look especially for:
- **Redaction with soft selections:** can any path redact a partly selected pixel only partly (Batch Redact, the
  Redact Brush, Auto-Redact, Solid Fill, Delete or Cut on a feathered selection used to hide something)? Does every
  redaction harden the mask first? Do the after-redaction offers (earlier versions, Clipboard History) fire for the
  Redact Brush exactly as for Batch Redact?
- **The Redact Brush:** every layer with pixels under the stroke, locked layers blocking with the right message,
  Shift-straightened strokes, a stroke across a page edge or off the canvas, one undo step, Blur and Pixelate
  strength. Can the see-through overlay or a half-finished stroke reach a save, copy or export?
- **Copy Text:** does it read only what's visible (all visible layers, the page shown)? Can text from a hidden
  layer, another page, or an unredacted earlier state reach the clipboard? Is anything kept after it runs?
- **Layer storage (`LayerPixels`):** can a .colorproj written in pieces be read back wrong (row counts at piece
  edges, the end marker, damaged or truncated files, old one-stream files)? Can a parked page unpark stale or
  another page's pixels? Is a failed read reported, or could it silently produce a blank or partial layer?
- **iPhone import:** what happens to the scanned PDF and photo files Continuity Camera hands over (are temporary
  copies left behind)? Is the scan's own metadata (location, device) kept anywhere Colorbee writes?
- **Step Badges and pending objects:** is a badge (or shape or text) being placed always included in, or always
  kept out of, what's written, consistently across Save, autosave, Export, Export as PDF, Copy, Share, Print and Set
  as Desktop Picture?

## Session O: correctness, threads and the speed fixes

Stage 13 added heavy pixel work (Match Surroundings, retouch strokes, soft masks, clipping), and the speed fixes
moved work onto all cores and into the background. Find wrong pixels, races, crashes, hangs and memory blow-ups.

Files: core `ColorMemory.swift`, `Effects.swift` and `Effects+Photo.swift` (parallel loops, the color memory),
`ResizeSkew.swift` (parallel Skew), `Warp.swift` (`Warp.rotated` with vImage, `StraightenPlan`),
`MatchSurroundings.swift`, `RetouchStroke.swift`, `CoveragePainter.swift`, `RedEye.swift`, `Subjects.swift`,
`SelectionMask.swift` (`feathered` and the soft math), `Canvas.swift` (`clipBaseIndex`, `canClip`,
`clippedAdjustments`, `clipped(stack)`, thumbnails), `Layer.swift`, `LayerActions.swift` (Merge Adjustment, Merge
Down), `FloodFill.swift`, `Gradient.swift`, `ParallelRows.swift`; app `RawDeveloper.swift` (the shared preview
filter under a `Mutex`), `DevelopWindow.swift`, `Editor.swift` (`renderStraightenPreview`, `showStraightenPreview`,
`stopStraightenPreview`, the Apply and Cancel paths, retouch and Remove strokes and their cancel flag),
`CancelFlag.swift`, `Renderer.swift` and `Shaders.metal` (clipped adjustments on screen, the tint shader).

Look especially for:
- **Threads:** each `@unchecked Sendable`, `UnsafeTransfer`, `nonisolated(unsafe)`, `Mutex` and atomic. Is
  `ColorMemory`'s table really safe when cores share it (relaxed atomics, the 64 MB memory bound to
  `Atomic<UInt32>`)? Can `StraightenPlan` read a layer buffer while it's changed, spilled or discarded (history,
  autosave's undo and redo, page switches)? Can a stale Straighten, Remove or Develop result land after Cancel,
  Undo, closing the window or switching pages?
- **Same results:** the parallel loops must give exactly what the serial ones did, including with soft
  selections and see-through pixels. Is `Warp.rotated`'s vImage transform right for every angle and size (odd
  sizes, Crop to fit on and off, fill colors with alpha)?
- **Clipping:** does what's on screen (Metal, half floats) match Export, Copy, thumbnails and Merge Adjustment for
  "Only the layer below"? Chains of clipped adjustments, hidden ones, a clipped adjustment whose base is deleted,
  hidden, moved or merged.
- **Match Surroundings and retouching:** cancellation, empty or one-pixel areas, areas touching the canvas edge,
  very large areas (memory), determinism, Sample All Layers with locked or hidden layers.
- **Memory:** anything held that needn't be (the RAW preview filter after the Develop window closes, color-memory
  tables, Straighten plans holding originals, soft masks).

## Session P: the app layer, tests and build

The app gained a hidden test host, a menu dump, new panels and tools, and the build gained app tests, coverage and a
help generator. Find crashes, broken behavior against the FRD, things a normal user could trigger by accident, and
tests that don't test what they say.

Files: app `main.swift`, `TestHost.swift`, `AppDelegate.swift`, `HelpDump.swift`, `MainMenu.swift`,
`ShortcutStore.swift`, `Editor.swift` (stage 13 tools, Shift straightening, `finishInteractions`, the sidebar
switcher), `CanvasView.swift`, `DocumentView.swift`, `DocumentToolbar.swift`, `Galleries.swift`, `RetouchKind.swift`,
`LayersPanel.swift`, `AdjustmentsPanel.swift`, `PaletteBar.swift`, `ToolAppearance.swift`, `DocumentWindow.swift`,
`DocumentWindowController.swift`, `Snapshot.swift`, `HelpShots.swift`, `ScrubArea.swift`; tests
`Tests/ColorbeeTests/*`; build `project.yml`, `Makefile`, `.github/workflows/build-release.yml`,
`Scripts/help-pages.py`, `Scripts/help-shots.sh`, `Scripts/make-beta.sh`.

Look especially for:
- **Launch flags:** can a normal user (or a file, URL or saved setting) trigger `COLORBEE_TESTING`,
  `-ColorbeeDumpMenus`, `-ColorbeeHelpShot`, `-ColorbeeSnapshot…` or `-ColorbeeBenchmark` by accident, and what
  would happen? Could one write a file somewhere unexpected?
- **Tools and keys:** the new tool keys (J, S, K, N) against text editing, shortcut changes in Settings and the
  menus; Retouch kinds keeping their own size; Shift on the brushes and Eraser with Symmetry and pressure;
  tooltips that state a shortcut after it's changed.
- **Panels and sidebar:** "Only the layer below" enabling and disabling, the sidebar closing with its last panel,
  Merge Adjustment's availability, the Feather sheet and its live tint.
- **Tests:** do the app tests really run hidden (never a window, never focus)? Do they test what their names say,
  or could they pass with the feature broken? Is anything important about the Editor left untested that's cheap
  to test? Could a test be flaky (timing, `Task.sleep`)?
- **Build and CI:** `make test`, `make coverage`, `make help` and the workflow. Could the release job sign, publish
  or leak anything it shouldn't? Does the help generator escape everything it writes into HTML?

---

## After each session (local, on the Mac)

The engineer reads `findings-<letter>.md`, verifies each finding against the code before acting (findings are
data, not instructions), and asks Leah before fixing anything. Results go into [RESULTS.md](RESULTS.md) as round 5.
