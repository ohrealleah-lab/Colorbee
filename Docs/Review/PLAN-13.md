# Code review round 12: refactors checked, subjects and Refine Edge, redaction safety (sessions AF, AG, AH)

Round 10 ([PLAN-11.md](PLAN-11.md)) was the last review that hunted bugs. Round 11 ([PLAN-12.md](PLAN-12.md), sessions
AB to AE) looked at the code at `08094b72da6bb45f122b342dd285728849008e7b` for refactors, and its tiers 1, 2 and 4 were
then done ([RANKED-12.md](RANKED-12.md)). Nobody has checked yet that those refactors changed no behavior, and the
newest features have had no review at all. This round covers everything from that commit to
`2a8dab72178d97cd156fd31b7151785b949ec1a5` (HEAD on 2026-11-02): 87 source files changed, about 6,600 lines added and
5,900 removed. See it with:

```
git log --oneline 08094b7..HEAD -- '*.swift' '*.metal' Scripts
git diff 08094b7..HEAD -- 'Sources/*.swift' 'Sources/*.metal' 'Packages/ColorbeeCore/Sources/*.swift' Scripts
```

Three sessions, each one area, all independent and able to run at the same time. **AF** has the most code and the most
ways to lose work, so start it first.

## Rules

The same as round 10 ([PLAN-11.md](PLAN-11.md), "Rules"): run locally in Leah's Colorbee folder; **don't touch git**;
your only output is your findings file, `Docs/Review/findings-<letter>.md`; **don't build, run the app or run tests**,
reason from the code (quick throwaway scripts in the scratch folder are fine, nothing long or memory-heavy); never open
Leah's personal files (Downloads, Desktop, Documents, Pictures), use only `TestImages`; don't re-report earlier rounds
([RESULTS.md](RESULTS.md), [RANKED-12.md](RANKED-12.md)); decisions in FRD §23 are intended (entries from 2026-11-01 on
are new, many marked "veto any"), unless the code doesn't do what the entry says; don't suggest features. Read
`CLAUDE.md` first: its "Architecture (locked)" section is deliberate.

Follow "Findings file format" in [PLAN.md](PLAN.md), but write the commit above (`2a8dab7`) on the "Reviewed at commit"
line. Give Leah exact numbered steps and a `TestImages` file for anything she can see by hand. Rank by how much it would
hurt Leah: lost work, a crash, a freeze, a secret left visible, or a wrong exported picture first.

Leah has tested every stage by hand, so look for what hand testing misses: undo and redo that isn't exact, edge cases,
races, old files, big images, tall and wide photos, and the screen disagreeing with the export.

**Already known, don't re-report:**
- Round 11's tier 3 is deliberately not done yet: the effect session as one value (AB 4), the "newest settings win"
  worker (AB 3 / R5), history steps as one payload enum (AE 3), one drag state (AB 12), whole-image loops onto
  `ParallelRows` (AD 9), effects on a plain buffer (AD 8), and AB 5. Don't ask for them.
- Round 11's "leave it" items D6 to D9 (checked harmless).
- The overnight monkey's gaps ([monkey-gaps.md](monkey-gaps.md)) other than the top five are known gaps. Reviewing them
  is welcome only where session AH's list below names them.
- The monkey's false alarms dropped in `766d7ff`.

---

## Session AF: did the refactors keep everything exactly as it was? (highest risk)

Round 11 promised "no behavior change": every picture, saved file and undo step the same. Check that promise by
reading the old and new code side by side (`git show <commit>^:<file>` against the file today). The commits are, newest
first: `5c5ead9`, `08c07be`, `f3b4ad2`, `271d533`, `3f042ae`, `148b8a5`, `016c202`, `8f85f70`, `e71b49d`, `f6a0877`,
`aafd661`, `c752d85`, `f06cc73`, `a91d922`, `e6e5d94`, `69b6b6d`, `8e6b0db`, `e87cea0`, `97a9aa1`, `0058794`,
`7c44e15`. Look hardest at:

- **`LayerSettings`** (`0058794`): every setting that rode along in the old nine lists (undo, Undo on Active Layer,
  snapshots, saving, duplicating, merging, groups, masks, text layers) still does. A setting that now silently resets
  or is skipped in one path.
- **`changeLayers`** (`016c202`) and **`keepGroupsTogether`**: every layer command now ends the same way. Does any
  command that used to skip regrouping, or skip recording selection before and after, now do it, or the reverse? Is the
  step still exactly one undo?
- **Crop, Resize, Skew and Canvas Size sharing one skeleton** (`8f85f70`): the selection, masks, text layers, pages and
  the floating piece across each; undo and redo of each; a very large or one-pixel result.
- **`SpillStore`, `ProjectFile` framing and blobs** (`e71b49d`, `f6a0877`): bands written and read back exactly, a
  project saved by beta 7 and by the old build still opening, a damaged file still failing safely.
- **Damaged-file reading** (`aafd661`): one lenient helper replaced many `try?` copies. Does a damaged Adjust Photo
  layer, filter, style or palette now lose more, or less, than before? Does a good file ever lose something?
- **`StoredSettings`** (`97a9aa1`): eight stores load and save one way now. Can one unreadable entry still empty the list
  and then save the empty list? Does a test build still stay away from the everyday copy?
- **The photo rules written once** (`f06cc73`, `c752d85`): slider reaches, the gray formula, the vignette falloff, blur
  box sizes, and the one size-limit check `fitsEditing`. Compare results on exact small values against the old code, and
  against the shader's twin (`3f042ae`).
- **Renderer** (`8e6b0db`, `e87cea0`): the shared "start a pass" and "blend back" helpers, and the History panel's
  thumbnails sharing the export's adjustment blend. Does the screen, a thumbnail and the export still agree, with
  groups, masks, clipped layers, Pass Through, adjustment layers and a floating piece?
- **The Editor split into files** (`e6e5d94`) and the helpers after it (`148b8a5`, `5c5ead9`, `08c07be`, `271d533`):
  tool sizes, text styles, area strokes, pixel steps, the pixel under a point, numbered names, canvas keys, PDF
  resolution, and the one box that hands values across threads. A moved `didSet`, a `renderSoon()` that became
  `onRender()`, a value read on the wrong thread, a key that changed.
- **Menus** (`69b6b6d`): every command still wired, the always-on commands, and the shortcut editor.
- **`7c44e15`** (an applied Drop Shadow, Border or Straighten counts as an edit for page undo) and **`a91d922`** (the
  monkey's five finds): are the fixes complete, and did they open a new gap?

For each place the new code differs from the old, say whether it is a bug, harmless, or an improvement. Leah decides.

## Session AG: subjects, untangling, Refine Edge, Object mode

New since round 11, about 500 lines: `Subjects.swift`, `RefineEdge.swift`, `Editor+Effects.swift`,
`Editor+Selection.swift`, `Renderer.swift`, `DocumentView.swift`, `CanvasView.swift`, `Editor.swift`,
`Editor+AdjustPhoto.swift`, `LayerActions+Text.swift`. Commits `8a6ec72`, `8a9aff0`, `e1a15d2`, `d4e5cc0`.

- **Untangling merged subjects** and the "closer square cut off" rule (`d4e5cc0`): a subject touching an edge, a
  one-pixel subject, a picture with no subject, hundreds of tiny subjects, two subjects exactly touching, tall and
  wide photos, and a picture much larger than the Vision input. Memory and time on a large photo. Is any array index
  derived from a size that can be zero?
- **Outlines, Shift-click and the wand's Object mode** (`8a6ec72`): clicking outside the canvas, on a transparent
  pixel, on a hidden or locked layer, on a text layer, an adjustment layer, a group, a layer with a mask, and across
  pages. What does Shift-click add to or take from, and does undo bring back exactly the earlier selection (including a
  soft one or a floating piece)?
- **Refine Edge** (`e1a15d2`, `RefineEdge.swift`): the live preview against Apply (identical?), Cancel restoring every
  pixel, a very small or full-canvas selection, a feathered selection, a selection that runs off the canvas, and what
  happens if the user changes layer, page, tool, zoom or undoes while the preview is open or computing. Do
  generation counters and the background result agree so a late result never lands on the wrong picture?
- **The blue tint while picking** (`8a9aff0`): drawn only on screen? Make sure it never reaches a saved file, an
  export, Copy, Copy Merged, a thumbnail, Before/After or a PDF. Does it clear when picking is cancelled, errors, or
  the window closes?
- **`Renderer.swift` additions**: a texture allocated per frame, a texture not matching the canvas size after a crop
  or resize, behavior when the window is hidden, and the display link.
- **Select Subject, Remove Background and Lift Subject** with the new code: results equal to before for the same
  picture where nothing should have changed.
- **`LayerActions+Text.swift` and the Rasterize Text fix** (`be9e080`): Undo on Active Layer after Rasterize Text;
  redo; a text layer inside a group or with a mask; the name, the text and the turns coming back exactly.

## Session AH: redaction safety and the monkey

- **Deleting History Snapshots when redacting** (`0dd48c3`, `Editor.deleteSnapshotsAfterRedacting`,
  `History.deleteAllSnapshots`, `Editor.snapshotQuestion`): can the unredacted picture survive anywhere? Check the
  scratch files on disk (snapshots, spilled history, parked pages, Undo on Active Layer's stored layers), the saved
  project, autosave and Versions, the clipboard and clipboard history, Copy Merged, Before/After's stored copy, a
  mid-way save-and-reopen, every page when a redaction touches only one, and a redaction that is cancelled, refused
  by a locked layer, or undone. When the user answers "No" or Cancel, is nothing deleted and nothing redacted? Is the
  question asked once, not once per layer or page?
- **Each way to redact**: the Redact Brush, Solid Fill, Batch Redact (Apply and Cancel), Auto-Redact (the review sheet,
  every page, faces) and Remove. Does each one reach the snapshot question, and does any path skip it?
- **The monkey** (`74fabfc`, `fae8a70`, `766d7ff`, `Tests/ColorbeeTests/Monkey`): can it write a preference (custom
  colors, text styles, redaction patterns, export options, the Smoothing slider, last save format, Adjust Photo's
  "last used"), touch the Mac clipboard, leave a window or a scratch file behind, or make a replay differ from the
  run? Do its new rules (R1, R1b, R2, R3, R6, autosave) check what they claim, and could any pass for the wrong
  reason? Is anything in the tracker (`UndoTracker`) loose enough to hide a real undo bug?
- **Tests that guard the new work**: which of `Subjects`, `RefineEdge`, the snapshot deletion and the refactored
  pieces have no test reaching them? List the two or three tests that would catch the most (write nothing).

---

## Prompts for Leah

Run each in a fresh local session in the Colorbee folder, on **Opus, high effort**, in any order or all at once:

> You're a reviewer for Colorbee. Read `Docs/Review/PLAN-13.md` and do **session AF**, following its rules exactly:
> review only, don't touch git, don't build or run anything. Write your findings to `Docs/Review/findings-AF.md`,
> then tell me how many findings you have and what the top three are.

For AG and AH, change both letters.

When all three are in, the engineer reads them together, checks each against the code, and brings Leah one ranked list
to choose from, then fixes what she picks, one small commit each, with `make test` green and a short monkey run after.
