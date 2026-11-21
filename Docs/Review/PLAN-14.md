# Code review round 13: stage 34, the usability review fixes (sessions AI, AJ, AK)

Stage 34 (Leah's usability review, 2026-11-20) was built in three parts and passed Leah's hand test on 2026-11-21. No
reviewer has read it yet. This round covers everything stage 34 changed on top of
`b2f1e27e` (Allow for steep Adjust Photo settings in the monkey's screen check): about 290 lines changed in 26 files,
plus ten new files. It's three commits: `52e93b1` (34a), `cedd39b` (34b) and `a94da79` (34c). See it with:

```
git log --oneline b2f1e27..HEAD
git diff b2f1e27 -- 'Sources/*.swift' 'Packages/ColorbeeCore/Sources/*.swift' 'Tests/*.swift' 'Packages/ColorbeeCore/Tests/*.swift'
```

New files (read them whole): `Sources/Colorbee/ToolSettings.swift`, `Sources/Colorbee/Editor+ToolSettings.swift`,
`Sources/Colorbee/OriginalFile.swift`, `Packages/ColorbeeCore/Sources/ColorbeeCore/PhotoPanelSteps.swift`, and the tests
`CancelFloatingTests.swift`, `PlacedTextAndHiddenLayerTests.swift`, `PhotoPanelStepsTests.swift` (core) and
`SelectionsAndLayersTests.swift`, `FilesAndWindowsTests.swift`, `PhotoPanelUndoTests.swift` (app).

What was asked for: FRD §23, the four rows dated 2026-11-20 ("Usability review answers", "Stage 34 details", "Stage 34b
built", "Stage 34c built"), and `Docs/Development-Plan.md`, stage 34. The FRD sections it touched: FR-3.3 (Esc on
floating pixels), FR-6.3 (placed text), FR-8.2 (hidden layers), FR-9.4 (Batch Redact), FR-12 (back to its file), FR-15.4
(tool settings carry over), and Adjust Photo's "Undo inside the panel".

Three sessions, one per part, all independent and able to run at the same time. **AI** is the one that could cost Leah
a file, so start it first.

## Rules

The same as round 12 ([PLAN-13.md](PLAN-13.md), "Rules"): run locally in Leah's Colorbee folder; **don't touch git**
(reading it with `git log`, `git show` and `git diff` is fine); your only output is your findings file,
`Docs/Review/findings-<letter>.md`; **don't build, run the app or run tests**, reason from the code (quick throwaway
scripts in the scratch folder are fine, nothing long or memory-heavy); never open Leah's personal files (Downloads,
Desktop, Documents, Pictures), use only `TestImages`; don't re-report earlier rounds ([RESULTS.md](RESULTS.md),
[RANKED-12.md](RANKED-12.md)); decisions in FRD §23 are intended, including every "veto any" choice, unless the code
doesn't do what the entry says; don't suggest features. Read `CLAUDE.md` first: its "Architecture (locked)" section is
deliberate.

Follow "Findings file format" in [PLAN.md](PLAN.md). On the "Reviewed at commit" line write the full hash from
`git rev-parse HEAD`, and add "plus uncommitted changes" if `git status` shows stage 34 files not yet committed. Give
Leah exact numbered steps (one action per line, "Menu ▸ Item", then "Expected:" and "Actual:") and a `TestImages` file
for anything she can see by hand. Rank by how much it would hurt Leah: a file overwritten or lost, lost work, a crash, a
freeze, a secret left visible, or a wrong exported picture first.

Leah has tested all of stage 34 by hand, so look for what hand testing misses: undo and redo that isn't exact, edge
cases, races, old files and old settings, big images, several windows at once, and relaunching.

**Already known, don't re-report:**
- Round 11's tier 3 and "leave it" items, as listed in PLAN-13.
- Round 12's set-aside findings AG 3 to 7 and AH 6.
- Anything in the commits between `2a8dab7` and `b2f1e27` that isn't part of stage 34 (they're for a later round).

---

## Session AI: files and windows (34c, highest risk)

`ImageDocument.swift` (`followLayers`, which replaced `becomeProjectIfLayered`, and the restorable state),
`OriginalFile.swift`, `ToolSettings.swift`, `Editor+ToolSettings.swift`, `AppDelegate.swift` (save on quit),
`Editor.swift` (`retouchSizes`), and `FilesAndWindowsTests.swift`.

**Back to its file.** A picture that gains a layer becomes an untitled project; once it's one plain layer again it
points at its original file, and ⌘S writes there.
- Can this ever write over a file it shouldn't? Think about: a file renamed, moved, replaced by a different picture or
  a different type at the same path, or on a volume that's gone; a picture opened as a copy (PDF, RAW, animated GIF,
  multi-page TIFF, `opensAsCopy`), which must never get an `originalFile`; a project Save As'd somewhere and then
  flattened; Duplicate; Revert to Saved; the Versions browser; and a document restored after a relaunch whose original
  is now different.
- `autosavesInPlace` is on. When the document points back at the file, what happens to the untitled autosave it had
  as a project (`autosavedContentsFileURL`)? Is anything left behind, or read back on the next launch instead of the
  file? Can an autosave write into the PNG at a moment Leah wouldn't expect, such as the instant Undo brings it back?
- The change count and `fileModificationDate`: after the switch back, is the window's "Edited" mark right? Does macOS
  ask exactly when another app changed the file meanwhile, and never when it didn't?
- `editor.isLayered`: does every way back to one plain layer get there (Undo, Redo, Flatten, Merge Down, Merge
  Visible, Delete Layer, Delete Page, removing a mask, Rasterize Text, the History panel jump, Undo on Active Layer)?
  Does any way leave it pointing at the file while it still has pages, a mask, text or an adjustment layer, so a save
  would flatten them?
- The redaction warnings (`redactedSinceSave`, "earlier versions still show it"): still right when a redacted
  picture goes back to a file whose earlier Versions hold the secret?
- `restoreState`: the order it runs in against `makeWindowControllers` and `followLayers`; a restorable state written
  by the build before stage 34, with none of the new keys.

**Tool settings carry over.** `ToolSettingsStore` follows each window's settings with `withObservationTracking`,
starts new windows with the last ones, and keeps them in `Tool Settings.json`.
- A hand-edited, damaged or old `Tool Settings.json`: decoding keeps whatever number it finds. What does a brush size
  of 0, -5, 1e9 or NaN, an eraser size of 0, a tolerance of 7, an empty or missing font, a text size of 0, or a badge
  size of 1e6 do to a new window? Is there a crash, a huge allocation or a freeze? Compare with how
  `StoredSettings` and the other damaged-file paths (round 11, `aafd661`) handle it.
- Setting `editor.toolSettings` writes about thirty observed properties one after another. Any `didSet` that reads
  another setting mid-change (the Swift exclusivity crash CLAUDE.md warns about), restyles a pending shape, text or
  badge, or records a history step?
- The observation loop: does it stop when a window closes, or keep a Task or a closure alive per window forever? Can
  two windows changing settings at once lose one or leave the file out of date? Is the file written on quit even when
  a 1-second save is pending, and never half written?
- Mask grays (`note` while `canvas.editsMask`): can a mask gray still reach the store or the file by any path, such
  as a window that opens while another has a mask chosen?
- Tests and the monkey must never write `Tool Settings.json` or read Leah's. Check `SettingsFolder.current` under
  TestHost and every call to `ToolSettingsStore.shared`.

## Session AJ: selections and layers (34b)

`SelectionActions.cancelFloating`, `History.undoStepLeaves`, `Canvas.isHidden`, `LayerActions+Text.swift` (`addText`
keeps the active layer), `Editor+Selection.swift` (`pressEscape`, `cancelFloating`), `Editor+Layers.swift`
(`activeLayerTakesEdits`, `activeLayerIsHidden`, `refusedBecauseLocked`), `Editor+Effects.swift` (`beginBatchRedact`),
`CanvasView.swift` (Esc and the "not allowed" pointer), `DocumentWindow.swift` (menu checks, Cut), `MainMenu.swift`,
the monkey's new Esc step and rules, and the new tests.

**Esc on floating pixels** undoes every step since the lift or paste and forgets Redo.
- The loop stops when the newest step no longer leaves the same floating piece. Can it stop too early (a step merged
  into another with `commit(_:mergingIntoPrevious:)`, a redaction group, Undo on Active Layer's steps, steps on
  another page, a step spilled to disk) or go too far (a step that left the same `id` but wasn't part of this float,
  such as one restored by an earlier Undo or Redo, or a page parked and brought back)?
- History's byte budget can drop the oldest steps. If the lift or paste step itself was dropped, what does Esc do? Is
  any pixel lost, or the piece left floating with its source gone?
- The document's change count: Esc reports one `.undone` per step taken back. Is that right when some of those steps
  were already merged, or when the document was saved partway through the float?
- Esc while something else owns the key: a text field in the palette or a sheet, the effect bar, the Auto-Redact
  review, a drag in progress, magnify, an open text box (text keeps Esc), a shape or badge, the fill progress, and
  object search. Is the order in `pressEscape` right for each?

**Hidden layers refuse pixel changes.**
- Which commands now refuse or grey out on a hidden layer that shouldn't (Copy, Select All, the wand sampling all
  layers, mask editing, Clear, layer settings, whole-image commands, redaction), and which still change a hidden
  layer's pixels that should refuse? Check every user of `activeLayerTakesEdits` and `refusedBecauseLocked`.
- A layer in a hidden group, a group itself as the active layer, a layer at 0% opacity (not hidden), and a layer
  hidden or shown by Undo while a tool is mid-stroke.

**Placed text keeps your layer.** `addText` inserts above the active layer and keeps it active. Inside a group, with
a clipped layer, with a group or adjustment layer active, and on another page: is the text where the FRD says, is the
right layer active, and is the step one exact undo?

**Batch Redact needs a selection.** Menu checks and `beginBatchRedact`: a floating piece, a selection made by
`Graduated Selection…`, a selection that's entirely off the canvas, and a selection on another page.

**The monkey's Esc step** (`MonkeyEpisode.note`, `.escape`): does the new check prove what it claims, and could it
pass for the wrong reason or hide an inexact undo?

## Session AK: Adjust Photo's own undo, and Esc (34a)

`PhotoPanelSteps.swift` (core), `Editor+AdjustPhoto.swift` (`settlePhotoStep`, `photoUndoName`, `photoRedoName`,
`undoPhotoStep`, `redoPhotoStep`, `escapeEffect`, `photoPanelHasChanges`, `endPictureDrag`), `Editor.swift`
(`photoSteps`, `asksToDiscardPhoto`), `Editor+AutoRedact.swift` (`endEffectSession`), `AdjustPhotoPanel.swift` and
the controls it uses, `DocumentView.swift` (the alert, the Cancel button's key check), `DocumentWindow.swift` (Undo
and Redo routing and their menu names), and the new tests.

- **Every change a step, and only finished ones.** Find every way the panel's settings change: each slider and its
  number field, typed values, the Tone Curve's points, Color Mixer, Point Color (its picker clicks and Range), Color
  Grading's wheels, Detail and Masking, Effects, filters and Intensity, Auto, Reset, Paste Settings, White Balance,
  the hand drag on the picture, and keyboard arrows in a control. Does each one end in `settlePhotoStep`? Does a missed
  one fold two changes into one undo, or name the step wrongly in Edit ▸ Undo?
- **⌘Z never reaches the document while the panel is open.** Check every way to undo: the menu, ⌘Z with focus in a
  text field (which has its own undo), the History panel, Undo on Active Layer, the toolbar, and the shortcut editor
  remapping Undo. Could the document's history step back under the live preview, so Apply or Cancel lands on the wrong
  picture?
- **Undo and redo are exact.** After any mix of changes, undos and redos, is the preview exactly the settled state
  (the picture and the panel's sliders, including the Auto marks)? Does Apply always apply what's shown, as one
  document step? Do views (`withoutViews`: Masking's edge view, Point Color's Range) ever become a step or get lost?
- **Esc asks only when it should.** The Cancel button checks `NSApp.currentEvent?.type == .keyDown`. What else arrives
  as a key press: Space or Return on a focused Cancel button, Full Keyboard Access, ⌘. (Cancel)? Does Esc in a
  focused number field cancel the field's edit, close the panel or ask? Can the question stay up, or come back, after
  the panel closes, the window closes, the app quits, an autosave runs, or the document is reverted?
  `photoPanelHasChanges` compares against a fresh `PhotoEdit`: is that right when the panel opened on a layer whose
  settings weren't default, and after Undo back to the start?
- **Steps go when the panel closes**, by Apply, Cancel, Discard, As Adjustment Layer, closing the window, switching
  page, and quitting. Can a later Adjust Photo session see an earlier one's steps?

---

## Prompts for Leah

Run each in a fresh local session in the Colorbee folder, on **Opus, high effort**, in any order or all at once (AI
first if one at a time):

> You're a reviewer for Colorbee. Read `Docs/Review/PLAN-14.md` and do **session AI**, following its rules exactly:
> review only, don't touch git, don't build or run anything. Write your findings to `Docs/Review/findings-AI.md`,
> then tell me how many findings you have and what the top three are.

> You're a reviewer for Colorbee. Read `Docs/Review/PLAN-14.md` and do **session AJ**, following its rules exactly:
> review only, don't touch git, don't build or run anything. Write your findings to `Docs/Review/findings-AJ.md`,
> then tell me how many findings you have and what the top three are.

> You're a reviewer for Colorbee. Read `Docs/Review/PLAN-14.md` and do **session AK**, following its rules exactly:
> review only, don't touch git, don't build or run anything. Write your findings to `Docs/Review/findings-AK.md`,
> then tell me how many findings you have and what the top three are.

When all three are in, the engineer reads them together, checks each against the code, and brings Leah one ranked list
to choose from, then fixes what she picks, one small commit each, with `make test` green and a short monkey run after.
