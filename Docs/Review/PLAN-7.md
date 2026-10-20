# Code review round 6: everything since round 5 (session R)

Round 5 ([PLAN-5.md](PLAN-5.md), sessions N, O and P) reviewed commit `eccf0c1`. Everything since is the round 5 fixes
and the polish before Colorbee was called feature-complete (2026-10-19): about 1,300 lines across 48 files. See it
with `git log --oneline eccf0c1..HEAD` and `git diff eccf0c1..HEAD -- '*.swift' '*.metal' '*.yml' Makefile Scripts`.

One session, **R**. Colorbee is feature-complete, so this is the last code review before the betas carry on: find
what's wrong in the newest code, and anything the fixes broke.

## Rules

Run **locally, in Leah's Colorbee folder**. Follow "Rules for every review session" and "Findings file format" in
[PLAN.md](PLAN.md), with these changes (the same as round 5):

- **Don't touch git** (no branches, commits, stashes or pushes). Your only output is one new file,
  `Docs/Review/findings-R.md`, written into this folder. The engineer commits it.
- **Don't build, run the app or run tests.** Reason from the code. Quick throwaway scripts in the scratch folder are
  fine, but nothing long or memory-heavy: Leah's Mac once froze during a heavy test.
- **Never open Leah's personal files** (Downloads, Desktop, Documents, Pictures). Use only `TestImages`.
- **Don't re-report earlier rounds.** Read [RESULTS.md](RESULTS.md) first; report an old fix only if newer work broke
  it.
- **Decisions are in FRD §23** (entries from 2026-10-12 to 2026-10-19 are new). What Leah chose on purpose isn't a
  bug. Colorbee is feature-complete: don't suggest features.
- **Leah hand-tests findings:** where one can be shown by hand, give exact numbered steps and a test file (for
  example `TestImages/Help/Sample Screenshot.png`, `TestImages/Stage 13/`, `TestImages/Stage 9 Practice Photo.png`,
  `TestImages/Stage 12/Test Camera.dng`, `TestImages/Stage 10/Three Page Test.pdf`). Say "draw a selection box", not
  "marquee".
- Rank findings by how much they'd hurt Leah or a tester: a secret left visible, lost work or a crash first.

## What changed, and what to look for

- **Round 5 fixes** (`8a6f7e8`, `56356e3`, `e25d0ea`, `8a2e424`, `0b8e292`): Straighten planned and rendered in the
  background (`StraightenPlan`, `Warp.swift`, Editor's straighten state); clipped adjustment layers kept with their
  layer on new, duplicate, merge and delete (`LayerActions.swift`, `Canvas.indexAboveActiveLayer`); Sample All Layers
  (`composited(through:)`); Remove's size limit (`MatchSurroundings`); straight-alpha mixing near transparency
  (`Compositing.lerp`, `CoveragePainter`, `RetouchStroke` Blur, Sharpen and Smudge); soft Red-Eye; Feather previewed
  in the background (`featherSession`); Match Tone planned in the background and merged into the stroke's step
  (`ToneMatch`, `Editor.matchTone`); Copy Text's clipboard offer (`ClipboardHistory.clearClipboard(ifUnchangedSince:)`).
  Look for races between background work and edits, undo, page switches or closing the window; steps recorded twice
  or not at all; anything that could leave a redaction incomplete.
- **Menus** (`85822cc`, `MainMenu.swift`, `DocumentWindow.validateMenuItem`, `ShortcutStore`): the new Redact menu,
  moved items, checkmarks instead of Show/Hide. Look for commands that lost their validation, a changed shortcut that
  no longer applies after the move, or the Shortcuts settings losing a saved shortcut.
- **Toolbar and palette bar** (`fca2f47`, `0c0d917`, `c8625b5`; `DocumentToolbar.swift`, `PaletteBar.swift`,
  `CustomColors.swift`, `Renderer.swift` and `Shaders.metal` for the canvas shadow): hidden controls keeping their
  space; 4 custom colors and the migration from 12; the shadow (is it ever drawn into an export, a copy or Before/After?).
- **Help** (`41a6382`, `a537f96`; `HelpBook.swift`, the ? buttons, `NSHelpManager.registerBooks` in `AppDelegate`).
- **Paste into New Image with no window open** (`450502c`; `AppDelegate.pasteIntoNewImage`,
  `DocumentWindow.openClipboardImage`, `AppDelegate`'s `validateMenuItem`).
- **iPhone import removed** (`7b28a33`): check nothing still refers to it and no `validRequestor` path is left half
  there.
- **CI and release** (`.github/workflows/build-release.yml`, `Makefile`, `Scripts/`): the hardened signing steps from
  round 5 (P2). Never handle or print a secret's value.

## Prompt for Leah

Run in a fresh local session in the Colorbee folder, on **Opus, high effort**:

> You're a reviewer for Colorbee. Read `Docs/Review/PLAN-7.md` and do **session R**, following its rules exactly:
> review only, don't touch git, don't build or run anything. Write your findings to `Docs/Review/findings-R.md`,
> then tell me how many findings you have at each severity.
