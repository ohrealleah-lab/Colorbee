# Code review round 7: the fixes since round 6 (session S)

Round 6 ([PLAN-7.md](PLAN-7.md), session R) reviewed commit `12020b4`. Everything since is the fixes that followed it:
about 370 lines in 9 source files. See them with `git log --oneline 12020b4..HEAD -- '*.swift'` and
`git diff 12020b4..HEAD -- 'Sources/*.swift' 'Packages/ColorbeeCore/Sources/*.swift' Scripts`.

One session, **S**. Colorbee is feature-complete; this checks that the last fixes are right before the betas carry on.

## Rules

The same as round 6 ([PLAN-7.md](PLAN-7.md), "Rules"): run locally in Leah's Colorbee folder; **don't touch git**;
your only output is `Docs/Review/findings-S.md`; **don't build, run the app or run tests**, reason from the code (quick
throwaway scripts in the scratch folder are fine, nothing long or memory-heavy); never open Leah's personal files; don't
re-report earlier rounds ([RESULTS.md](RESULTS.md)); decisions in FRD §23 (entries 2026-10-19 to 2026-10-22 are new) are
intended; don't suggest features. Give Leah exact numbered steps and a `TestImages` file for anything she can see by
hand. Rank by how much it would hurt Leah or a tester: a freeze, a crash, lost work or a secret left visible first.

## What changed, and what to look for

- **Match Tone waits before the next edit** (`Sources/Colorbee/Editor.swift`: `matchTone`, `PendingTone`,
  `finishPendingTone`, `land`, `isEditInProgress`; called from `finishInteractions` and `placePendingObjects`). A big
  stroke's tone is worked out on a background queue; anything that starts a new edit **blocks the main thread on a
  semaphore** until it's done, then lands it. Look hard for a **deadlock or long freeze**: can the background work ever
  wait on the main thread, or never signal (a crash or early return in `ToneMatch.plan`)? Can `finishPendingTone` run
  re-entrantly, or from inside `land`? Is every path that changes the image, the page or the layers covered (undo and
  redo, page switches, closing the window or the document, saving, autosave, Auto-Redact, layer commands, paste)? Can a
  tone land on the wrong page, layer or step, or merge into a step it doesn't belong to?
- **Match Tone's edge-only reference and opacity weighting** (`Packages/ColorbeeCore/Sources/ColorbeeCore/RetouchStroke.swift`:
  `toneReference(over:mask:)`, `ToneMatch.edge`, `Reference`, `plan`, `apply`; the `copyable` rectangle and `coverage`).
  Does `edge` agree exactly with the edge `plan` uses? Are indices right for a read area clipped at the canvas edge?
  Is `weight = coverage / alpha` right for partly transparent pixels on every kind of layer, and can it divide badly?
- **The smooth blend** (`ToneMatch.smoothFill`): correctness (every stroke pixel gets a value; nothing outside the
  stroke changes; areas with no edge information), and **time and memory on a huge stroke** (an 8000 × 8000 image, a
  300 px brush across the whole image): the coarse grid, the first-guess loop (`pending.filter` each ring), the
  relaxation count and the full-size passes. It runs off the main thread for big strokes but on it for small ones.
- **Levels read from files** (`Levels.init(from:)`): every field kept in range; old projects and filters still read.
- **Help** (`Sources/Colorbee/HelpBook.swift`: `openHelp(at:)`, `HelpPage`; `MainMenu.swift` quick links;
  `AppDelegate.openHelpPage`): tags and order, the Help menu built before shortcuts are registered, `Scripts/help-pages.py`
  `page-` anchors.
- **View menu checkmarks** (`DocumentWindow.isOn` and `validateMenuItem`).
- **Removed code:** `ImageDocument.open(_ stored:)`; nothing else refers to it.

Also read these small files, which no review plan has named: `Packages/ColorbeeCore/Sources/ColorbeeCore/Resampling.swift`,
`ChannelTable.swift`, `RedactionTreatment.swift`, and `Sources/Colorbee/PageBaseline.swift` (Revert Layer and "Last Saved"
baselines), `Pixel+AppKit.swift`, `Theme.swift`.

## Prompt for Leah

Run in a fresh local session in the Colorbee folder, on **Opus, high effort**:

> You're a reviewer for Colorbee. Read `Docs/Review/PLAN-8.md` and do **session S**, following its rules exactly:
> review only, don't touch git, don't build or run anything. Write your findings to `Docs/Review/findings-S.md`, then
> tell me how many findings you have at each severity.
