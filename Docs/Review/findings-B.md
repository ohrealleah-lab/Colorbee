# Review B: background work and the app's editing sessions
Reviewed at commit: d67a8626cc8f975618ca03a10a8cf722cece4b5d
Checked:
- `Editor.swift`, the effect session: `beginEffect`, `previewEffect`, `startBackgroundPreview`, `showBackgroundPreview`, `renderEffectPreview`, `applyEffect`, `cancelEffect`, `endEffectSession`, `withoutEffectPreview`, `saveSnapshot`, `markSaved`
- `Editor.swift`, step-based previews (`renderDecorationPreview`) and how Apply and Cancel leave history, canvas size, selection and the edited state. Left out on purpose: the stale redo step after a tick that draws nothing (review A #5, already being fixed).
- `Editor.swift`, canvas tools (crop, perspective and straighten drags), `findSubject`, `perform`, `pickSubject`, `saveFilter`, `saveFilterFromLayers`
- `EffectPreview.swift`: reads only its own copy of the layer; the scratch canvas's color space and background aren't read by any effect, so background previews match Apply
- `ClipboardImage.swift`: no deadlock found. A paste inside Colorbee waits on the main thread, but the encoder never needs the main thread (it posts to Clipboard History only after `finish`). A failed encode ends the wait with no data.
- `PasteboardImages.swift`: `hasImage` only looks at types, so validating menus never waits for a promised PNG
- `SaveSnapshot.swift`, `ImageDocument.swift` (`save(to:…)`, `pendingSnapshot` and its lock, `canAsynchronouslyWrite`, `data(ofType:)`, export): a save always writes one whole snapshot copy, never mixed content; see #8 for overlapping saves
- `DocumentWindow.swift`: copy, cut, paste, Copy Merged, menu validation while an effect is open
- `CanvasView.swift`: the `.canvasTool` drag (begin, continue, end) and the Ctrl-click context menu (validated like the menu bar, so it's disabled during effects)
- `Subjects.swift`: `SubjectScan.find`, `subject(at:)`, `SubjectActions`. `makeCGImage` copies the layer, so Vision never reads live layer memory.

## 1. A cancelled Drop Shadow, Border or Straighten preview can stay in the file on disk
- **Severity:** High (the file holds something the user cancelled)
- **Confidence:** Medium (depends on an autosave landing during the preview; see how to confirm)
- **Where:** `Sources/Colorbee/Editor.swift:2225-2231` (`cancelEffect`), `:2709-2714` (`withoutEffectPreview` only handles `effectEdit`, which is nil for these previews), `:1932-1955`; `Sources/Colorbee/ImageDocument.swift:74-90`
- **What happens:** These previews are real history steps in the canvas, so an autosave in place during the preview writes the shadow, border or turn into the document's own file (§23 accepts this). Cancel then undoes the step in memory but never tells the document anything changed. If the autosave cleared the unsaved-changes state, the document now looks fully saved, so it's never written again. Closing the window leaves the file with the cancelled preview in it.
- **How to trigger it:**
  1. Open a saved PNG and draw a stroke, so there's an unsaved change.
  2. Within a few seconds open Effects ▸ Drop Shadow…, then switch to another app (switching away autosaves documents with unsaved changes).
  3. Come back and press Esc to cancel.
  4. Close the window, then reopen the PNG: it has the drop shadow.
  - To confirm: after step 3, `isDocumentEdited` / `hasUnautosavedChanges` is false while the file contains the shadow.
- **Why:** Preview steps are committed outside `recordingChanges`, so no `updateChangeCount` happens until Apply (`onDocumentChange(.done)`). Cancel calls `history.undo` and `forgetRedo` with no `onDocumentChange`. `saveSnapshot()` → `withoutEffectPreview` does nothing when `effectEdit == nil`.
- **Test that would catch it:** Editor-level, with an `onDocumentChange` spy: begin `.dropShadow`, render a preview, take `saveSnapshot()` (as autosave would) and record that a save happened, then `cancelEffect()`. Expect a `.done` change, or expect the snapshot to equal the canvas without the preview. Simplest fix to check: leave the preview step out of the snapshot (undo, copy, redo), the same way tile previews are left out.

## 2. Subject finding applies a mask from before an edit made while Vision was working
- **Severity:** High (wrong pixels: the wrong part of the image is removed or selected)
- **Confidence:** High that the check misses it; Medium that it's easy to hit (it needs an edit during the Vision call, which takes a noticeable moment on large photos)
- **Where:** `Sources/Colorbee/Editor.swift:1883-1909`, especially the guard at `:1897`
- **What happens:** After the scan, the only checks are that the canvas size, the active layer's ID and "no effect open" haven't changed. Any change that keeps those the same gets a mask that no longer matches the pixels: Flip Horizontal or Vertical, Rotate 180°, ⌘Z or ⌘⇧Z, a brush stroke, a paste, Merge Down into the active layer. Remove Background then makes the wrong area transparent.
- **How to trigger it:** Open `TestImages/Stage 9 Practice Photo.png` (or any large photo). Choose Image ▸ Remove Background and straight away Image ▸ Flip ▸ Horizontal. When the scan finishes, the unflipped mask is applied to the flipped image, so the subject is partly cut away and part of the background kept. ⌘Z of an earlier flip during the scan does the same.
- **Why:**
  ```swift
  guard self.canvas.size == size, self.canvas.activeLayer.id == layer.id, self.activeEffect == nil else { return }
  ```
  Neither `history.revision` nor the layer's pixels are compared. Menus stay enabled while `isFindingSubject` is true.
- **Test that would catch it:** Hard to test headless because of Vision. Make the comparison testable instead: record `history.revision` when the scan starts, and check that a guard helper rejects the result once a flip has been committed. Or by hand: the steps above.

## 3. An autosave during a slider effect works out the whole effect again on the main thread
- **Severity:** Medium (NFR-6: the main thread blocks for more than a frame)
- **Confidence:** High
- **Where:** `Sources/Colorbee/Editor.swift:2709-2714` (`withoutEffectPreview`), called from `saveSnapshot()` (`:2694-2696`), which `ImageDocument.save(to:…)` calls on the main thread (`ImageDocument.swift:78`)
- **What happens:** For Gaussian Blur, Adjust Photo, Levels, Curves, Motion Blur and the other background-previewed effects, every autosave while the bar is open runs `restoreOriginals()`, copies the canvas, then `defer { renderEffectPreview() }`. That last call recomputes the full effect synchronously on the main thread. Moving the effect into the background was meant to avoid exactly this. On an 8000 × 8000 image with a large blur or Adjust Photo's Definition, that's a long main-thread stall each time an autosave lands. The effect is also computed twice, since a background render may be running too.
- **How to trigger it:** An 8000 × 8000 photo with an unsaved edit. Open Effects ▸ Gaussian Blur…, set a large radius, then switch to another app and back (that triggers an autosave). The window freezes for the length of a full synchronous blur. `make bench`'s longest-main-thread-pause metric would show it if run with an effect open.
- **Why:** `renderEffectPreview()` → `Effects.apply(effect, to: canvas.activeLayer, …)` on the main thread. The pixels on screen before the save were already correct and could be put back as they were.
- **Test that would catch it:** Editor-level timing or a call-count spy: with an effect open and a preview shown, `saveSnapshot()` should not call `Effects.apply`. For example, keep the shown preview's pixels (an `EffectPreview`) and write them back after the copy.

## 4. Straighten, Perspective Correction and Crop… beep when the active layer is locked or is an adjustment layer
- **Severity:** Medium (broken behavior against the FRD)
- **Confidence:** High
- **Where:** `Sources/Colorbee/Editor.swift:1681` (`guard !refusedBecauseLocked()` at the top of `beginEffect`), with `:119` (`appliesToWholeImage`)
- **What happens:** These three apply to every layer (the bar even says "Applies to every layer"). FRD §23 says whole-image rotating, flipping, cropping and resizing apply to every layer, locked or not, and `apply(_ orientation:)` follows that by checking the lock only for a selection. But `beginEffect` refuses all effects on a locked or adjustment layer, these three included.
- **How to trigger it:** Lock the active layer (Layer ▸ Lock Layer), or select an adjustment layer. Choose Image ▸ Straighten…, Perspective Correction… or Crop…: it beeps and nothing opens.
- **Why:** `beginEffect` runs `refusedBecauseLocked()` before it looks at `kind.appliesToWholeImage`.
- **Test that would catch it:** Editor-level: active layer locked, `beginEffect(.crop)`, expect `activeEffect == .crop`. Same with an adjustment layer active.

## 5. Select Subject on a locked layer with several subjects beeps instead of asking which one
- **Severity:** Low (broken behavior on a locked layer)
- **Confidence:** High
- **Where:** `Sources/Colorbee/Editor.swift:1885` (Select is allowed on a locked layer), `:1904-1906`, `:1681`
- **What happens:** `findSubject` deliberately lets Select Subject run on a locked layer, since selecting doesn't change pixels. With several subjects, though, it opens the pick step through `beginEffect(.pickSubject)`, whose lock check beeps and returns. Nothing is selected. `subjectPick` stays set, so its masks stay in memory until the next Cancel.
- **How to trigger it:** Open `TestImages/Stage 9 Practice Cutout.png` (Vision finds the circle and the star) and lock its layer. Edit ▸ Select Subject: a beep and no selection. With one subject it works.
- **Why:** The pick step reuses `beginEffect`, which refuses every kind on a locked layer.
- **Test that would catch it:** Editor-level with a fake two-subject `SubjectScan`: locked layer, run the multi-subject branch, expect `activeEffect == .pickSubject`.

## 6. A late result from a closed effect lets two background previews run at once in the next effect
- **Severity:** Low (the screen can briefly show older settings; extra CPU)
- **Confidence:** High
- **Where:** `Sources/Colorbee/Editor.swift:1984-1986` (`previewRunning = false` before the generation check), `:2216-2223`
- **What happens:** Effect A's render is still running when A is cancelled and effect B opens and starts its own render. When A's render finishes, it sets `previewRunning = false` even though its result is thrown away, and B's render is still going. The next slider move in B then starts a second render alongside it. If the older one finishes last, its settings are shown (`shownEffect` set to them) until the slider moves again. Apply still commits the right settings, because it compares against `shownEffect`.
- **How to trigger it:** A large image. Open Gaussian Blur…, drag the radius high, press Esc at once, open Motion Blur… and keep dragging. Two renders overlap: CPU use doubles, and the preview can jump back briefly.
- **Why:** `showBackgroundPreview` clears `previewRunning` unconditionally, before `guard generation == previewGeneration`.
- **Test that would catch it:** Move the `previewRunning = false` inside the generation check. An Editor-level test with a stub render can check that a stale completion leaves `previewRunning` unchanged.

## 7. Two quick copies can leave the older image at the top of Clipboard History
- **Severity:** Low
- **Confidence:** High
- **Where:** `Sources/Colorbee/ClipboardImage.swift:27-33`
- **What happens:** Each copy encodes in the background and adds to Clipboard History when it finishes. If a large copy is followed by a small one, the small one finishes first, then the large one's PNG is added on top. Clipboard History then shows the old image as the newest, while the clipboard holds the new one.
- **How to trigger it:** An 8000 × 8000 image: ⌘C with nothing selected, then quickly select a small area and ⌘C. Open Clipboard History: the whole image is on top.
- **Why:** `DispatchQueue.main.async { ClipboardHistory.shared.add(png) }` runs in finishing order, not copy order. Nothing checks that `image === current`.
- **Test that would catch it:** Only add to history when the image is still `ClipboardImage.current`, or carry a sequence number. A unit test with two stubbed encoders finishing in reverse order would check it.

## 8. Overlapping saves: the save that finishes may have written a newer snapshot than the one marked "Last Saved"
- **Severity:** Low (Revert Layer and Before/After's "Last Saved" can be a few edits older than the file)
- **Confidence:** Low (depends on whether AppKit can start an autosave between an explicit save's `save(to:…)` and its background `data(ofType:)`)
- **Where:** `Sources/Colorbee/ImageDocument.swift:78-89`, `:133-147`; `Sources/Colorbee/Editor.swift:2673-2678`
- **What happens:** `pendingSnapshot` is shared by every save. If ⌘S stores snapshot A and an autosave then stores B before A's write reads it, A's file gets B (newer, so no data loss). The completion still calls `markSaved(A)`, so Revert Layer and "Last Saved" use A while the file holds B. Content is never mixed, because each write encodes one whole copy.
- **How to trigger it:** Hard to do on purpose: ⌘S on a large image and an autosave at almost the same moment. To confirm, log which snapshot `data(ofType:)` encoded alongside which one `markSaved` received.
- **Why:** `data(ofType:)` reads whatever `pendingSnapshot` holds now, not the snapshot its own `save(to:…)` took.
- **Test that would catch it:** Hand each save its own snapshot (for example, keyed by the save's URL and operation, or pass it through `writeSafely`), and assert that the snapshot encoded is the one marked saved.
