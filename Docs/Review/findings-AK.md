# Review AK: Adjust Photo's own undo, and Esc (stage 34a)
Reviewed at commit: f3f5623c02034eea0153b11f095fee7dd4d3ae4a
Checked: `PhotoPanelSteps.swift` (whole) and its core tests
Checked: `Editor+AdjustPhoto.swift`: `settlePhotoStep`, `photoUndoName`, `photoRedoName`, `undoPhotoStep`, `redoPhotoStep`, `showPhotoState`, `photoPanelHasChanges`, `escapeEffect`, `endPictureDrag`, `cancelPicturePick`, `pickFromPicture`, `pastePhotoSettings`, `photoAsAdjustmentLayer`, `applyEffect`
Checked: `Editor+Effects.swift` (`beginEffect`, `previewEffect`, background preview, `setPhotoEdit`, `autoPhoto`), `Editor+AutoRedact.swift` (`endEffectSession`, `cancelEffect`), `Editor+Canvas.swift` (`finishInteractions`), `Editor+Pages.swift` (page switch, History jump)
Checked: every way the panel's settings change: `AdjustPhotoPanel.swift` (rows, Intensity, filters and the filter menu, Auto, Copy, Paste, Reset, the per-row Reset menu), `PhotoControls+ColorMixer/PointColor/ColorGrading.swift`, `ColorWheel.swift` (click delay, double-click, accessibility), `ToneViews.swift` (SplitSlider; ToneCurveGraph is display only), `ScrubArea.swift` (`slides`)
Checked: `DocumentWindow.swift` (Undo and Redo routing and their menu names, `validateMenuItem` order), `DocumentView.swift` (the question, EffectBar's Cancel key check), `CanvasView.swift` (Esc order, picture drag), `LayersPanel.swift` (the sidebar while the panel is open), `DocumentToolbar.swift` (what's disabled during an effect)
Checked: `PhotoPanelUndoTests.swift`, FRD §23 (the four 2026-11-20 rows), FR-9.5's "Undo inside the panel", Development Plan stage 34a, the help line in `fix-up-a-photo.html`

Looked at and found right, so not reported: each slider, its name-line drag, the per-row Reset, Intensity, every filter chip and filter-menu change, Auto, Paste Settings, Reset, Black & White, Point Color's remove and Range (its view is cleared before the step), Color Grading's wheel (a click waits out the double-click, then settles; a late settle after ⌘Z is a no-op), SplitSlider, the white-balance and Point Color picks, and a finished hand drag all end in a step. Views (Masking's edge mask, Point Color's Range) are stripped in `State.init`, so they never become a step and Apply strips them too. Apply re-renders if the shown preview isn't the settings, so it applies exactly what undo/redo left on screen, as one document step. Steps are cleared in `beginEffect` and `endEffectSession`, and every close (Apply, Cancel, Discard, As Adjustment Layer, page switch, window close and quit through `finishInteractions`) goes through `endEffectSession`, which also drops the question. The panel always opens at `PhotoEdit()` (Paste Settings opens it and then makes its first step), so comparing against a fresh `PhotoEdit` is right, and Undo back to the start leaves nothing to ask about (`PhotoEdit`'s sections fall back to nil when untouched). While the panel is open the History panel isn't shown, Undo on Active Layer is blocked by `blocksDocumentCommands`, the toolbar has no Undo, and a remapped Undo keeps the same selector, so the document's history can't step back under the preview.

## 1. Esc during a hand drag on the picture leaves that change out of the undo steps
- **Severity:** Medium (edge case: two changes come back as one undo, under the wrong name)
- **Confidence:** High
- **Where:** `Sources/Colorbee/Editor+AdjustPhoto.swift:35-40` (`cancelPicturePick`), with `Sources/Colorbee/CanvasView.swift:940-942` and `Editor+AdjustPhoto.swift:120-127` (`endPictureDrag`)
- **What happens:** Pressing Esc while still dragging with the hand (Tone Curve or Color Mixer) turns the hand off and keeps the change, but never makes it a step. When the mouse is let go, nothing settles it either. The change then merges into whatever finishes next: Edit ▸ Undo says "Undo Changes" (or "Undo Auto", "Undo White Balance" and so on), and one ⌘Z takes back both.
- **How to trigger it** (`TestImages/Stage 9 Practice Photo.png`):
  1. Open the picture.
  2. Adjustments ▸ Adjust Photo…
  3. In Tone Curve, click the hand button.
  4. Press on the picture and drag up. Keep holding the mouse button.
  5. Press Esc, then let go of the mouse.
  6. Drag the Exposure slider and let go.
  7. Open the Edit menu.
  - Expected: "Undo Exposure"; ⌘Z puts back only Exposure.
  - Actual: "Undo Changes"; ⌘Z puts back Exposure and the Tone Curve together.
- **Why:** `cancelPicturePick` finishes an Adjust Photo *layer's* drag but not the panel's:
  `if case .layer = pictureDrag?.target { finishLayerSettings() }` then `pictureDrag = nil`. With `pictureDrag` gone, the
  mouse-up's `endPictureDrag` returns at `guard let drag = pictureDrag`, so `settlePhotoStep()` is never called for
  this drag. Review V finding 6 fixed exactly this for the layer case ("Esc keeps that as its step"); the panel case
  added in 34a didn't get the matching line.
- **Test that would catch it:** In `PhotoPanelUndoTests`: begin Adjust Photo, turn on the Tone Curve hand, `beginPictureDrag` / `continuePictureDrag` to change a region, call `cancelPicturePick()`, then `endPictureDrag()`; expect `photoUndoName == "Tone Curve"` and `photoSteps.settled == photoPanelState`. Then drag Exposure and expect `photoUndoName == "Exposure"`.

## 2. A slider moved with the keyboard or VoiceOver never becomes a step of its own
- **Severity:** Medium (edge case: an undo takes back more than its name says)
- **Confidence:** Medium (depends on SwiftUI not calling `onEditingChanged` for keyboard and VoiceOver changes on macOS, which is how its NSSlider-backed slider has behaved)
- **Where:** `Sources/Colorbee/AdjustPhotoPanel.swift:353-356` (the row's `SwiftUI.Slider`), compared with `Sources/Colorbee/ColorWheel.swift:84-90`
- **What happens:** Each row settles a step only when the slider's editing ends (`onEditing(false)`) or the name-line drag ends. Arrow keys on a focused slider (System Settings ▸ Keyboard ▸ Keyboard navigation) and VoiceOver's increment and decrement change the value without either. The change stays "unfinished" until the next finished change, which then swallows it. With a named step (Auto, White Balance, Point Color, Paste Settings) the menu says "Undo White Balance" but ⌘Z also takes back the keyboard change. If the next thing is ⌘Z, it's fine: undo finishes the pending change first and takes it back alone.
- **How to trigger it** (`TestImages/Stage 9 Practice Photo.png`):
  1. Turn on System Settings ▸ Keyboard ▸ Keyboard navigation.
  2. Open the picture.
  3. Adjustments ▸ Adjust Photo…
  4. Press Tab until the Exposure slider has the focus ring.
  5. Press → five times.
  6. Drag the Contrast slider and let go.
  7. Open the Edit menu.
  - Expected: "Undo Contrast"; ⌘Z puts back only Contrast.
  - Actual: "Undo Changes"; ⌘Z puts back Contrast and Exposure together.
- **Why:** `SwiftUI.Slider(value:in:) { editing in onEditingChanged?(editing); if !editing { (end ?? onFinish)() } }` is the only finish for the slider itself. The color wheel shows the intent: its `accessibilityAdjustableAction` and hue actions call `onChange` then `onFinish()` explicitly. The rows have no such path.
- **Test that would catch it:** Not unit-testable through SwiftUI. A hand check (the steps above, and the same with VoiceOver's VO-→ / VO-← on a slider) after any fix.

## 3. ⌘Z while still holding a drag seems to do nothing and drops Redo
- **Severity:** Low
- **Confidence:** High
- **Where:** `Sources/Colorbee/Editor+AdjustPhoto.swift:98-116` (`continuePictureDrag`), `:292-295` (`undoPhotoStep`); `Sources/Colorbee/ScrubArea.swift:114-135` (the name-line drag)
- **What happens:** The hand drag and the name-line drag are driven by `mouseDragged` events, so ⌘Z arrives mid-drag. Undo finishes the partial drag as a step and takes it back, but the drag carries on from its start value, so the next mouse move puts the change straight back, and the mouse-up records it again and clears Redo. To Leah, ⌘Z flickers and does nothing. (A plain slider drag isn't affected: AppKit's slider tracking holds keys until the mouse is let go.)
- **How to trigger it** (`TestImages/Stage 9 Practice Photo.png`):
  1. Open the picture.
  2. Adjustments ▸ Adjust Photo…
  3. In Tone Curve, click the hand button.
  4. Press on the picture and drag up. Keep holding the mouse button.
  5. Press ⌘Z, move the mouse a little more, then let go.
  - Expected: the curve drag is taken back and stays back.
  - Actual: the curve snaps back for a moment, then follows the mouse again; the Edit menu then says "Undo Tone Curve", as if ⌘Z hadn't been pressed.
- **Why:** `continuePictureDrag` computes `drag.startValue + (drag.startY - viewY) * rate` and writes it into the current (undone) `photoEdit`; nothing ends `pictureDrag` when the panel undoes. `endPictureDrag` then calls `settlePhotoStep()`, and `settle` empties `redoSteps`.
- **Test that would catch it:** Begin a panel hand drag, `continuePictureDrag` once, `undoPhotoStep()`, `continuePictureDrag` again, `endPictureDrag()`; expect the undone state to hold (or whatever behavior Leah picks), not the dragged value with an empty Redo.

## 4. The Edit menu can keep showing a closed panel's step name
- **Severity:** Low (cosmetic: a greyed item with the wrong name)
- **Confidence:** Medium
- **Where:** `Sources/Colorbee/DocumentWindow.swift:422-427` (sets the title) against `:428-441` (the early returns that don't)
- **What happens:** While the panel is open, validation retitles Undo and Redo ("Undo Exposure", "Redo Contrast"). The early returns for other effect bars, Auto-Redact, sheets and the text box return `false` without touching the title. So if the panel closes and one of those states starts before the Edit menu is looked at again, Undo shows "Undo Exposure" (greyed) for a step that no longer exists. Before 34a the stale title was at least the document's own last step.
- **How to trigger it** (`TestImages/Stage 9 Practice Photo.png`):
  1. Open the picture.
  2. Adjustments ▸ Adjust Photo…
  3. Drag Exposure and let go.
  4. Open the Edit menu (it says "Undo Exposure"), then close it.
  5. Click Cancel in the panel.
  6. Press T, click the picture and type "hi".
  7. Open the Edit menu.
  - Expected: "Undo" (greyed).
  - Actual: "Undo Exposure" (greyed).
- **Why:** The new branch is the only one that retitles before the `blocksDocumentCommands` and `firstResponder is CanvasTextView` returns; the plain `undo`/`redo` cases that reset the title are below those returns.
- **Test that would catch it:** A `DocumentWindow` menu-validation test isn't practical under TestHost; a hand check (above) after any fix.

## 5. The bar's Cancel button asks when pressed from the keyboard
- **Severity:** Low
- **Confidence:** Medium
- **Where:** `Sources/Colorbee/DocumentView.swift:506-510`
- **What happens:** The top bar's Cancel decides "Esc or click" by `NSApp.currentEvent?.type == .keyDown`. With Keyboard navigation on, Tab to that Cancel and press Space: that's a key press too, so it asks "Discard your Adjust Photo changes?", though Leah's decision is that the Cancel button never asks. (⌘. also asks; that's Esc's twin, so it's arguably right.) An accessibility press (VoiceOver) runs with whatever event came last, so it may ask or not depending on the previous key or click. The panel's own Cancel button in the sidebar has no check and always just cancels.
- **How to trigger it** (`TestImages/Stage 9 Practice Photo.png`):
  1. Turn on System Settings ▸ Keyboard ▸ Keyboard navigation.
  2. Open the picture.
  3. Adjustments ▸ Adjust Photo…
  4. Drag Exposure and let go.
  5. Press Tab until Cancel in the top bar has the focus ring.
  6. Press Space.
  - Expected: Adjust Photo closes without asking.
  - Actual: "Discard your Adjust Photo changes?"
- **Why:** The key check can't tell Esc from any other key that presses a focused button.
- **Test that would catch it:** Not unit-testable (SwiftUI button and `NSApp.currentEvent`); a hand check after any fix.

## 6. Undo's menu check and Undo itself disagree about a focused text field
- **Severity:** Low
- **Confidence:** Low (I found no text field that can hold focus while the panel is open; the palette bar and the toolbar's Size field are disabled during an effect)
- **Where:** `Sources/Colorbee/DocumentWindow.swift:422-427` against `:87-104` and `:470-475`
- **What happens:** `undo(_:)` asks "is a text field focused?" first, then "is Adjust Photo open?". `validateMenuItem` asks them the other way round. If an `NSTextView` were first responder while the panel is open, the menu would say "Undo Exposure" (or be greyed with no panel steps) while ⌘Z did a text undo instead, and a field's own ⌘Z would be blocked when the panel has nothing to undo. The plan's risk list for 34a names "typing in a value field keeps its own ⌘Z".
- **How to trigger it:** No hand steps found today. It would show if a text field is ever added to the panel or stays focused when the panel opens.
- **Why:** The new branch sits above the existing `case #selector(undo(_:)) where textUndoManager != nil`.
- **Test that would catch it:** None practical; keeping both checks in the same order removes it.

## 7. Esc on the question: please check it closes the question
- **Severity:** Low
- **Confidence:** Low (needs a hand check; I can't run SwiftUI's alert)
- **Where:** `Sources/Colorbee/DocumentView.swift:122-129`
- **What happens:** Keep Editing is given both `role: .cancel` (Esc) and `.keyboardShortcut(.defaultAction)` (Return). The alert is an `NSAlert` underneath, and one button holds one key equivalent, so one of the two keys may not reach it. Return to Keep Editing is the important one and SwiftUI documents `defaultAction` for choosing the default button, so that should be fine; Esc may then do nothing. Discard has neither key, so nothing here can discard by accident.
- **How to trigger it** (`TestImages/Stage 9 Practice Photo.png`):
  1. Open the picture.
  2. Adjustments ▸ Adjust Photo…
  3. Drag Exposure and let go.
  4. Press Esc.
  5. Press Esc again.
  - Expected: the question closes; the panel stays open with Exposure still set.
  - Possible actual: nothing happens on the second Esc.
  6. Press Esc, then Return.
  - Expected: the question closes; the panel stays open with Exposure still set.
- **Why:** As above. Leah's stage 34a hand test clicked Keep Editing, so neither key has been tried.
- **Test that would catch it:** Hand check only.
