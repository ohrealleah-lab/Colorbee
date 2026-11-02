# Review AH: redaction safety and the monkey
Reviewed at commit: 2a8dab72178d97cd156fd31b7151785b949ec1a5
Checked:
- `0dd48c3`: `History.deleteAllSnapshots`, `Editor.deleteSnapshotsAfterRedacting`, `deleteSnapshotsAndRedact`, `SnapshotQuestion`, the `snapshotQuestion` alert (`DocumentView.swift`, `AutoRedactSheet.swift`)
- Each way to redact: Redact Brush (`Editor+Retouching.swift` `endRedactStroke`), Solid Fill (`applySolidFill`), Batch Redact Apply and Cancel (`Editor+AdjustPhoto.swift` `applyEffect`, `Editor+Effects.swift` `beginEffect`), Auto-Redact on every page and faces (`Editor+AutoRedact.swift` `applyAutoRedact`), and Remove (not a redaction in the FRD, so it rightly never asks)
- `AutoRedact+Apply.swift` (`layersWithPixels`, both `apply`s), `History+Snapshots.swift`, `HistorySnapshot.swift`, `SpillStore` (unlinked at creation), `Page.park`/`unpark`, `PageStack.forgetHistory`, `Editor+Undo.swift` (undo, redo, `stepShownPage`, redaction groups), `Editor+Pages.swift` (snapshots, Duplicate Page), `blocksDocumentCommands`
- Where the unredacted picture could survive: snapshots and their scratch file, spilled history, parked pages, Undo on Active Layer, the saved project, autosave and Versions, Clipboard History, Before/After, every page, cancelled, refused and undone redactions
- The monkey: `MonkeyEpisode.swift`, `MonkeyRules.swift`, `MonkeyStep.swift`, `MonkeyGenerator.swift`, `MonkeyTests.swift`, `HistoryBudget` (`74fabfc`, `fae8a70`, `766d7ff`), against `monkey-gaps.md` R1, R1b, R2, R3, R5, R6
- Preference and clipboard writes across the app (`UserDefaults`, `StoredSettings`, `SettingsFolder`, `PhotoSettingsStore.shared.last`, `NSPasteboard`, `ClipboardHistory`)
- Tests reaching the new work: `RedactionSnapshotTests`, `HistorySnapshotTests`, `AutoRedactEditorTests`, `SubjectTests`, `SubjectPickTests`, `RefineEdgeTests`

## 1. Redo of a redaction leaves a snapshot that still shows the secret
- **Severity:** High (a secret left visible)
- **Confidence:** High
- **Where:** `Sources/Colorbee/Editor+Undo.swift:38` (`redo`) and `:54` (`stepShownPage`); `Sources/Colorbee/Editor+Pages.swift:148` (`takeSnapshot`); the deletion only happens in `Editor+AutoRedact.swift:84`, `:286`, `:299` and `Editor+AdjustPhoto.swift:454`
- **What happens:** Snapshots are deleted only when a redaction is first done. Redo puts the redaction back without asking and without deleting anything. New Snapshot doesn't clear the redo steps, so a snapshot taken after Undo survives the Redo. The page then looks redacted, but its History panel holds a snapshot that brings the secret back with one click. Jumping forward in the History panel (`jump(toStep:)`) is the same as Redo, and so is a multi-page Auto-Redact redone across pages (`stepPages`).
- **How to trigger it:** Use `TestImages/Help/Sample Screenshot.png`.
  1. Open the picture in Colorbee.
  2. Choose the Redact Brush and paint over the email address.
     Expected: it's covered at once (no snapshots yet, so no question).
  3. Edit > Undo.
     Expected: the email shows again.
  4. Edit > New Snapshot…, then click Take Snapshot.
  5. Edit > Redo.
     Expected (per FRD §23, 2026-11-01): the question "Delete 1 History Snapshot?", or no snapshot left afterwards.
     Actual: the email is covered, no question appears, and ⌘Y's History panel still lists Snapshot 1.
  6. Click Snapshot 1 in the History panel.
     Actual: the email shows again.
- **Why:** `redo()` → `stepShownPage(undoing: false)` → `history.redo(on:)`. Nothing on this path looks at whether the step is a redaction, so `deleteSnapshotsAfterRedacting` never runs. `History.takeSnapshot` leaves the redo stack alone (`History+Snapshots.swift:11–38`). Leah's hand test (STATUS, "Redaction deletes History Snapshots") takes its second snapshot after an Undo, but then makes a new step, which drops the redo, so it never reaches this. A related gap from the same cause: Redo doesn't call `noteRedaction()`, so `redactedSinceSave` stays false. The "earlier versions still show it" warning after saving, and the Clipboard History offer, don't come for a redaction brought back by Redo. Example: redact, Undo, save (the file now holds the secret), Redo, save again: no warning about the earlier version.
- **Test that would catch it:** In `RedactionSnapshotTests`: Redact Brush stroke with no snapshots, `undo()`, `takeSnapshot(named:)`, `redo()`. Expect `historySnapshots` to be empty, or a `snapshotQuestion` to be asked (whichever Leah picks), and `redactedSinceSave == true`.

## 2. Monkey: since pages were added, most episodes no longer check undo and redo exactly at the end
- **Severity:** Medium (a test gap that can hide an inexact undo, which is lost work)
- **Confidence:** High
- **Where:** `Tests/ColorbeeTests/Monkey/MonkeyEpisode.swift:376–381` (`restart`), `:385–386` (`undoAndRedoEverything`), `:418–432` (`undoAndRedoAcrossPages`); restart calls at `:213` and `:255`
- **What happens:** Once any step shows another page or reopens the project, `pagesTouched` stays true for the whole episode. The end-of-run walk then only checks that each undo and redo "did something" (`undoAndRedoAcrossPages`), not that it gave back the exact picture. Each restart also sets every earlier place in the line to nil (`Array(repeating: nil, count: undoCount)`), so undoing past a restart is never compared, even between steps. New Page (roll 100), Duplicate Page (101) and Save and Reopen (108) switch the page on at least 3 rolls in 120, plus Show Page and Delete Page once there are two pages. So about 4 in 5 overnight episodes (60 steps: 0.975^60 ≈ 22% have none) and 2 in 3 `make test` episodes (40 steps: ≈ 36%) lose the exact check. That walk is the main place where old, spilled history steps (R6's tiny budget) get undone and compared, so R6 is weaker than it looks.
- **How to trigger it:** Not visible by hand. Count how many overnight episodes end in `undoAndRedoAcrossPages`.
- **Why:** `restart(on:pagesTouched: true)` was added in `74fabfc` together with the page and reopen steps. Before that, the end check was always exact.
- **Test that would catch it:** A monkey self-test: an episode of known steps with one New Page partway, then a deliberately broken undo on the first page (for example a test-only hook that skips restoring one tile). Today it passes; it should fail. (The fix is for the engineer: keep a line per page id instead of one line.)

## 3. Monkey: the "History went over its memory budget" rule can never fire
- **Severity:** Medium (the R6 rule passes whatever happens)
- **Confidence:** High
- **Where:** `Tests/ColorbeeTests/Monkey/MonkeyRules.swift:39`
- **What happens:** The rule allows the budget plus 64 MB. Monkey pictures are at most 160 × 160 (about 100 KB a layer), so history can never get 64 MB over, with the real budget or the tiny 256 KB one. If spilling stopped working altogether, this rule would stay green. I found no other check that a spill happened at all in a tiny-budget episode.
- **How to trigger it:** Not visible by hand.
- **Why:** `history.byteCount > history.byteBudget + 64 << 20`. In Swift `<<` binds tighter than `+`, so this is `budget + 64 MB`. (If `(budget + 64) << 20` was meant, that's worse: it multiplies the budget by about a million.) The slack made sense for real pictures before `HistoryBudget.forTests` existed. With a 256 KB budget, it hides everything.
- **Test that would catch it:** A monkey self-test: a tiny-budget episode of 20 strokes on a 140 × 100 picture. Expect `history.byteCount` to stay within the budget plus one step's worth, and expect something to have been spilled (a test-visible count of spilled entries or evicted buffers, greater than 0).

## 4. Monkey: the "background save while editing" rule never edits during the save
- **Severity:** Low (the rule checks less than the commit says)
- **Confidence:** High
- **Where:** `Tests/ColorbeeTests/Monkey/MonkeyEpisode.swift:155–180` (`checkPendingSave`), `:216–220`
- **What happens:** The commit says autosaves "are encoded in the background while editing goes on". In fact the snapshot is taken, three more steps are done, and only then is the snapshot encoded. The driver waits for that encode (`await Task.detached { … }.value`), so no edit runs while it's encoding. The rule does catch a save copy that shares a buffer with later edits, which is worth having. It can't catch a save reading a buffer while an edit, a merge or `discardContents` changes it, which is the race R5 was about. Only background eviction (`evictsInBackground`) can overlap, and only by chance.
- **How to trigger it:** Not visible by hand.
- **Why:** The `while let step = next(editor)` loop is suspended at `checkPendingSave` until the detached task returns.
- **Test that would catch it:** Start the encode without awaiting it, do the next one to three steps (including a Flatten or Merge on a tiny budget), then await it and compare, as the rule already does.

## 5. Monkey: the snapshot rule after a redaction checks only the page shown, and only one answer
- **Severity:** Low (rule coverage)
- **Confidence:** High
- **Where:** `Tests/ColorbeeTests/Monkey/MonkeyEpisode.swift:234–240`; `MonkeyRules.swift:46–51`; `MonkeyStep.swift:84–91`, `:235`, `:331`, `:343`; `MonkeyGenerator.swift:30`
- **What happens:** Three gaps against R1(f) in `monkey-gaps.md`:
  1. `checkRedacted` looks only at `editor.history`, so the other pages an Auto-Redact changed are never checked for snapshots.
  2. The monkey always answers "Delete Snapshots and Redact". The gaps review asked for "Cancel" sometimes, where nothing may change and the snapshots must stay. That's never exercised.
  3. Auto-Redact with the monkey's words ("Hi", "Step 2", "Look here", "API key", "OK", "x") matches no built-in pattern. The "API key" built-in looks for key formats such as `sk_live_…` or `ghp_…`, not the phrase. The pictures have no faces either. So Auto-Redact's snapshot question, and its every-page deletion, effectively never run in the monkey. (R1c itself is a known gap. This is about R1's claim that it covers Auto-Redact.)
- **How to trigger it:** Not visible by hand.
- **Why:** Quoted above. `redacted` also requires `editor.canvas === canvas`, which is right for the page shown but leaves out the rest.
- **Test that would catch it:** No new test needed. Extend `checkRedacted` to every page whose `history.revision` changed during the step, and answer Cancel on some seeds, then check that the snapshot counts and the picture are unchanged.

## 6. Monkey: a replay can differ from the run
- **Severity:** Low (a report that can't be replayed, or a shrink that goes wrong)
- **Confidence:** Medium
- **Where:** `Tests/ColorbeeTests/Monkey/MonkeyStep.swift:338–346` (Auto-Redact waits), `:365–367` (Remove, Spot Heal and tone waits); `Sources/Colorbee/Editor.swift:282` (`redactionPatterns = Editor.loadRedactionPatterns()`)
- **What happens:**
  1. The waits for background work are fixed at 400 × 25 ms (10 s). On a busy Mac (an 8-hour run, or the shrinker re-running an episode up to 150 times), Vision or a fill can take longer in one run than another. Then Auto-Redact is cancelled instead of applied, or a fill lands during the next step. The shrinker would then keep or drop steps for the wrong reason.
  2. Auto-Redact uses Leah's own saved redaction patterns, and which built-ins she has turned on. They're read from her settings when each Editor is made, because tests share Colorbee's settings. A custom pattern of hers can change what the monkey redacts, and a replay after she edits her patterns can differ from the night's run. Nothing is written, so her settings stay safe.
- **How to trigger it:** Not by hand. Add a custom pattern matching "Look here", then run `make monkey SEED=n EPISODES=1` on a seed whose episode has Auto-Redact after a "Look here" text: the steps differ from a run without the pattern.
- **Why:** The `for _ in 0..<400 where …` loops give up silently. `loadRedactionPatterns` reads `StoredSettings.data(forKey:)`, which is `UserDefaults.standard` even under `TestHost` (only writes are refused).
- **Test that would catch it:** In `MonkeyEpisode.makeEditor` and `reopened`, set `editor.redactionPatterns` to the built-ins, all on, assigned so it doesn't save (the `didSet` saves, but `StoredSettings.save` refuses under the test host). Also record a failure "Background work didn't finish" when a wait runs out, instead of carrying on.

## 7. Monkey: the Forget History rule doesn't check page undo or "As Opened"
- **Severity:** Low (a rule that would miss a regression; today's code is right)
- **Confidence:** High
- **Where:** `Tests/ColorbeeTests/Monkey/MonkeyRules.swift:79–90`
- **What happens:** The commit says "Forget History leaves nothing to go back to". The rule checks each page's `undoCount`, `redoActionName` and snapshots. It doesn't check `editor.undoActionName` / `pages.undoName` (Undo bringing back a deleted page, with whatever it held). It doesn't check that Before/After's "As Opened" is the picture now (`opened`, and `pageMemory[…].opened` for other pages), which R1b asked for. `PageStack.forgetHistory` and `Editor.forgetHistory` do clear both today. The rule just wouldn't notice if that stopped.
- **How to trigger it:** Not visible by hand.
- **Why:** `guard history.undoCount == 0, history.redoActionName == nil, history.snapshots.isEmpty`, per page only.
- **Test that would catch it:** Add `editor.undoActionName == nil && editor.redoActionName == nil` and `editor.pages.restorablePages.isEmpty` to `checkForgotten`. Also compare `editor.asOpened` with `canvas.flattened()`.

## 8. "Delete Snapshots and Redact" silently does nothing if the picture changed while the question was up
- **Severity:** Low (nothing is lost; the person thinks they redacted)
- **Confidence:** Medium
- **Where:** `Sources/Colorbee/Editor+AutoRedact.swift:66–70`
- **What happens:** For the Redact Brush and Solid Fill, the answer is dropped if `history.revision` changed after the question was asked. No beep, no message, and the question just closes. The snapshots stay, so nothing is lost, but the secret stays uncovered and the person may not notice on a busy screenshot. The way it can happen: a Remove or Spot Heal fill still working in the background lands while the question is up. `finishInteractions()` doesn't stop a running fill, and the alert doesn't block the fill from committing.
- **How to trigger it:** Hard by hand (it needs a slow fill). In code: start a Remove stroke on a large picture, then a Redact Brush stroke on a page with a snapshot, let the fill land, then answer.
- **Why:** `guard let self, self.history.revision == revision, self.page.id == pageID else { return }`. The Auto-Redact path, by contrast, re-runs its checks and says "changed after it was read".
- **Test that would catch it:** In `RedactionSnapshotTests`: take a snapshot, do a Redact Brush stroke, make any step (for example `addLayer()`) before `deleteSnapshotsAndRedact()`. Expect `onRefused` or a `redactionMessage`, not silence.

---

## Checked, no problem found
- **One question per redaction:** the Redact Brush, Solid Fill and Batch Redact ask once per page shown. Auto-Redact asks once with the total over every page it will redact, then re-checks every page on the answer.
- **Cancel:** nothing is redacted and nothing is deleted on every path. Batch Redact's bar stays open. (Solid Fill and the Redact Brush place a floating piece first, but that merges into the step that made it, as everywhere else.)
- **A locked layer** refuses before any question (`redactEveryLayer`, `beginEffect`, `applyAutoRedact`), and nothing is deleted.
- **Scratch files:** the snapshot and history `SpillStore` files are unlinked as soon as they're made, so a crash or quit leaves no file. `deleteAllSnapshots` drops the only reference, so the space goes too.
- **Elsewhere:** snapshots aren't in the project, autosave or Versions. Parked pages keep only their layers. Duplicate Page starts a fresh history, so snapshots aren't copied. New Snapshot is blocked while a Batch Redact bar or the Auto-Redact review is open. Undo history, Undo on Active Layer and Before/After still hold the unredacted picture until Remove Earlier Versions and Undo History, as the FRD intends.
- **The monkey's preferences and clipboard:** it sets Smoothing and Editable on the Editor, never through the controls. Adjust Photo layers are made with `addAdjustmentLayer`, which doesn't set "last used". Batch Redact's Apply isn't Adjust Photo, so `PhotoSettingsStore.shared.last` isn't touched. `paste` takes a buffer, not the clipboard. `ClipboardHistory.shared` is only read. Scratch files are unlinked, and the report goes to `build/Monkey`. I found nothing it writes to Leah's settings or the Mac clipboard, and no window it opens.

## Tests that would guard the new work best (none written)
1. **Redo after a redaction** (finding 1): undo, New Snapshot, redo; no snapshot may be left, and `redactedSinceSave` is set.
2. **A late Refine Edge result in the wand's Object mode:** `SubjectPickTests` reaches Refine Edge through Select Subject's Return and Esc, but no test covers Object mode's result arriving after the picture changed (`Editor+Selection.swift:608–613`, "The image changed while Colorbee was looking"). Click in Object mode, make a step (or switch page or layer) before the background look and refine finish, then expect the notice, the selection unchanged, and no history step.
3. **The monkey's own strength** (findings 2 and 3): a self-test that plants a broken undo after a page switch, and one that checks a tiny-budget episode really spills. Today both rules would pass for the wrong reason.

Also: `HistorySnapshotTests.deletingAllSnapshotsKeepsTheUndoSteps` checks `!FileManager.default.fileExists(atPath: file)`. That's always true, because `SpillStore.init` removes the name at once. Its `snapshotStore == nil` check is the one doing the work.
