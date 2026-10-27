# Review T: everything since round 7 (several layers, keys, pointer, save folder, small subjects, sliders, Info, review S's fixes)
Reviewed at commit: db08030c90b45ba8fc646153bab40acd4a911f8f
Checked:
- `LayerActions+Several.swift`: `mergeLayers` (anchor and holder, name, background, clips on chosen and unchosen layers, hidden and locked layers, an adjustment on top, `removeLayer`'s precondition, which can't fire: the holder always stays), `deleteLayers`, `duplicateLayers`, `moveLayers`, `update(_:layersWithIDs:)`; undo and redo (the whole stack, names and buffers are in `LayerStackState`, so they restore exactly).
- `LayerActions.swift`: `insertCopyOfActiveLayer`, `canDelete` and `canMergeDown` with an index.
- `Editor.swift`: choosing several layers, the resets (`layerCommand`, undo, redo, `pageDidChange`), opacity and blend mode on several layers (locked active layers are already blocked by the panel), `findSubject`, `pickSubject`, `applyEffect`, `cancelEffect`, `toggleSidebar`, `saveSnapshot` waiting for a tone, `matchTone`, `land`.
- `LayerMenuArea.swift` (`hitTest` only claims right-clicks and Control-clicks; menu items stay alive; setting `@State` from a menu item is safe), `LayersPanel.swift`, `DocumentWindow.swift` (menu validation, `keyDown`), `DocumentWindowController.swift`.
- `CanvasView.swift`: `viewDidMoveToWindow`, `keyDown`/`handleKey`, `isUncovered`, `updatePointer`, `cursorUpdate`, `pointerLeft`. The hit test per mouse move costs little.
- `ShortcutStore.swift`, `Shortcuts.swift`: ⇧S for a saved or imported book from before `canvas.sidebar` is fine; `importChanges` gives a clashing key to the user's own command and clears Sidebar's.
- `MainMenu.swift`, `main.swift` (tooltip delay in the registration domain only), `DocumentToolbar.swift`, `RetouchKind.swift`, `PageSidebar.swift`, `Galleries.swift`, `Scripts/help-pages.py`.
- `ImageDocument.swift`: `sourceFolder`, `startFolder`, `prepareSavePanel`, the export panels, restorable state (decoding the URL is safe), copies, RAW photos via `DevelopWindow.swift`, untitled images. Nothing wrong found.
- `Subjects.swift`: `findCloser`, `closerSquares`, `placed` (the crop is top-left in pixels and the mask goes back in the right place); `DocumentView.swift` pick bar.
- `ScrubArea.swift` `slides`/`followsWidth`, `AdjustPhotoPanel.swift`, `AdjustmentsPanel.swift`: `finishLayerSettings` with no edit begun does nothing; one undo step per drag.
- `DocumentInfo.swift`, `InfoPanel.swift`, `CameraDetails.hasLocation`, `ProjectFile.swift`, `ImageCodec.swift`, `RawDeveloper.swift`: no location, serial number or owner is ever shown; details update after Save, Save As and page changes. The file size is read with one `stat` on the main thread, which is fine.
- `RetouchStroke.swift` (`ToneMatch.plan`, `smoothFill`, `relax`): the pyramid, the red–black passes on all cores (no two threads write the same value) and the interpolation down are correct. One note, not a finding: `cellAt` is 4 bytes per pixel of the stroke's box, not per stroke pixel, so a thin stroke across 8000 × 8000 uses about 340 MB for a moment. That's well within the Mac's means; RESULTS.md's "everything per stroke pixel" is slightly generous.

## 1. A tool key while an effect's bar is open can loop between the window and the canvas and crash Colorbee
- **Severity:** Critical (crash; unsaved work since the last autosave is lost)
- **Confidence:** Medium (the loop is certain once the conditions hold; how often the canvas lacks the keyboard during an effect depends on the Mac's Keyboard navigation setting and what was clicked last)
- **Where:** `Sources/Colorbee/DocumentWindow.swift:13`, `Sources/Colorbee/CanvasView.swift:873-878`
- **What happens:** When the canvas doesn't have the keyboard (a button or panel took it, or the window itself holds it after a text box closed), a tool or canvas key reaching the window is handed to `canvasView.keyDown`. With an effect's bar open, the canvas passes every key except Return, Esc and Space on with `super.keyDown`, which goes up the responder chain to the window, which hands it to the canvas again, forever. The stack overflows and Colorbee quits.
- **How to trigger it:** see the steps below. Any effect with a bar works (Gaussian Blur, Levels, Crop, Straighten, Pick a Subject, Adjust Photo), and any canvas key (B, E, [, ], ⇧S…).
- **Why:** `DocumentWindow.keyDown` forwards when `firstResponder !== canvasView && !(firstResponder is NSText) && canvasCommand(for: event) != nil`, which is still true when the event comes back up from the canvas. `handleKey` with `editor.activeEffect != nil` ends in `default: super.keyDown(with: event)`. Before `ad007ff` the window just beeped. Two ways the canvas loses the keyboard: when a focused text box disappears (renaming a layer: the name field goes away on Return, and AppKit gives the keyboard to the window), or with System Settings ▸ Keyboard ▸ Keyboard navigation on, where clicking a slider or button gives it the keyboard. Nothing gives it back when an effect opens (`onFocusCanvas` runs only on a tool change or a paste).
- **Leah's steps** (save other work first; this may crash):
  1. Open `TestImages/Help/Sample Screenshot.png`.
  2. In the Layers panel, double-click the layer's name, click in the name box if needed, type `Test` and press Return.
  3. Choose Effects ▸ Gaussian Blur….
  4. Press B.
  - Expected: nothing happens (or a beep); the blur bar stays open.
  - Bug: Colorbee freezes for a moment and quits.
  - If step 4 does nothing, try again with Keyboard navigation turned on in System Settings ▸ Keyboard: open Gaussian Blur, drag its slider, then press B.
- **Test that would catch it:** an app test that opens an effect, makes the window its own first responder, sends a canvas key through `DocumentWindow.keyDown`, and expects it to return (a forwarding guard, so a key the canvas passes on goes to `super.keyDown` rather than back to the canvas).

## 2. Merge Layers changes the picture when a chosen layer uses a blend mode other than Normal
- **Severity:** High (wrong result the user sees)
- **Confidence:** High
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/LayerActions+Several.swift:21` and `:28`
- **What happens:** The chosen layers are combined on an empty, see-through layer, and the result is then set to Normal at 100% over the layers below. A Multiply, Screen, Overlay (and so on) layer has nothing to mix with on an empty layer, so it comes out as its plain colors and covers what it used to darken or lighten. The picture changes even when the merged layers are next to each other. FR-8.6 and §23 say "the merged layer is Normal at 100%, so the picture looks the same".
- **How to trigger it:** a Multiply layer (a highlighter or shadow) merged with the layer just below it, wherever the lower layer is see-through under it, or a lowest chosen layer that itself uses Multiply.
- **Why:** `let merged = canvas.composite(stack)` starts from an empty buffer. `Compositing.blend` with `backdropAlpha <= 0` uses the source color as is. Merge Down doesn't have this problem because it composites onto the lower layer's own pixels (`onto: lower.buffer`) and keeps that layer's settings. Normal layers at any opacity are fine (Normal mixing doesn't care about grouping). How to keep the look for other modes is Leah's call: for example, merge onto the layers below as Merge Down does when the lowest chosen layer is the bottom one, keep the lowest layer's mode when it's the only non-Normal one, or say in FR-8.6 that blend modes are baked as Photoshop does.
- **Leah's steps:**
  1. Open `TestImages/Several Layers/Opacity Test.colorproj`.
  2. Click the Green layer and set its blend mode to Multiply. The stripes now show through the green block, darkened.
  3. ⌘-click the layer just below Green, so both are chosen.
  4. Choose Layer ▸ Merge Layers (⇧⌘E).
  - Expected: the picture doesn't change.
  - Bug: the green block is solid green again; the stripes no longer show through it (except where it sat on the other block).
- **Test that would catch it:** core test: stripes, a half-covered layer, a Multiply layer above it; `mergeLayers` on the top two; `canvas.flattened()` before and after must match.

## 3. Duplicate Layers with a layer and its "Only the layer below" adjustment chosen puts the copied adjustment on the original
- **Severity:** Medium (edge case; the copy looks wrong)
- **Confidence:** High
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/LayerActions+Several.swift:102-110`, `Packages/ColorbeeCore/Sources/ColorbeeCore/LayerActions.swift:106`
- **What happens:** With a pixel layer and its clipped adjustment both chosen, the copy of the adjustment goes straight above the original adjustment (in the original layer's group), and the copy of the layer goes above the whole group with no adjustment. So the original layer gets the adjustment twice, and the plain copy on top hides it. With Invert the block flips back to its own color.
- **How to trigger it:** choose a layer and its clipped adjustment together, then Duplicate Layers.
- **Why:** copies are made top down, each with `insertCopyOfActiveLayer`: the clipped adjustment's copy goes at `activeLayerIndex + 1` (in its group), then the layer's copy goes at `indexAboveActiveLayer`, above the group, which now holds both adjustments. Each rule is right alone (§23, 2026-10-13), but together the copies don't form a group of their own.
- **Leah's steps:**
  1. Open `TestImages/Several Layers/Opacity Test.colorproj`.
  2. Click the Red layer. Choose Layer ▸ New Adjustment Layer ▸ Invert, then turn on "Only the layer below" in the Layers panel. The red block turns cyan.
  3. ⌘-click the Red layer, so Red and Invert are both chosen.
  4. Choose Layer ▸ Duplicate Layers.
  - Expected: the block still looks cyan, and the copies are "Red copy" with its own "Invert copy" on it.
  - Bug: the block is red again. The panel shows Red with two Invert layers on it, and "Red copy" above them with none.
- **Test that would catch it:** core test: pixel layer P with clip C; `duplicateLayers([P, C])`; expect the order P, C, P copy, C copy (C copy clipping P copy) and the flattened picture unchanged.

## 4. The History panel and Lift Subject keep the old choice, so the next command can take in layers you didn't choose
- **Severity:** Medium (edge case; undo puts it back)
- **Confidence:** High
- **Where:** `Sources/Colorbee/Editor.swift:828` (`jump(toStep:)`), `Sources/Colorbee/Editor.swift:2891` with `Packages/ColorbeeCore/Sources/ColorbeeCore/Subjects.swift:138`
- **What happens:** Undo, Redo, page changes and every layer command leave just the active layer chosen (§23), but clicking a step in the History panel and Lift Subject to New Layer don't. Both can make another layer active, and `chosenLayerIDs` always adds the active one to the old choice. Delete Layers, Merge Layers, Hide and the rest then act on the old layers plus the new active one.
- **How to trigger it:** choose two layers, then Lift Subject to New Layer, then Delete: the lifted subject and both chosen layers go.
- **Why:** only `layerCommand`, `undo`, `redo`, `pageDidChange` and `selectLayer` clear `otherChosenLayerIDs`. `jump(toStep:)` undoes and redoes through `stepShownPage`, and `perform(.liftToNewLayer…)` goes through `recordingChanges` directly.
- **Leah's steps:**
  1. Open `TestImages/Several Layers/Opacity Test.colorproj`.
  2. Click the Red layer, then choose Layer ▸ New Layer.
  3. Click the Blue layer, then ⌘-click the Yellow layer (both chosen; Yellow active).
  4. Open View ▸ History and click the step just before "New Layer".
  - Expected: only the active layer (Red, now that New Layer is undone) is chosen.
  - Bug: Red is active and Blue and Yellow are still tinted as chosen; the Layer menu says "Delete Layers", and Delete would remove all three.
- **Test that would catch it:** app test: choose two layers, `jump(toStep:)` (and separately lift a subject), expect `chosenLayerIDs` to hold only the active layer.

## 5. Cancel or Esc during "Looking closer…" leaves "Finding the subject…" showing, and the subject commands greyed, until the look ends
- **Severity:** Low
- **Confidence:** High
- **Where:** `Sources/Colorbee/Editor.swift:2900-2921`, `:3390-3405`; `Sources/Colorbee/DocumentView.swift:38-40`; `Sources/Colorbee/DocumentWindow.swift:378`
- **What happens:** Cancel ends the pick, but `isFindingSubject` stays true until the background look finishes (several Vision passes on a big image). Meanwhile the capsule switches from "Looking closer…" to "Finding the subject…", as if a new search had started, and Select Subject, Remove Background and Lift Subject are greyed out. The result is then thrown away, as it should be.
- **How to trigger it:** click an empty spot in the pick bar's "click the one you want" state, then press Esc at once.
- **Why:** `cancelEffect` clears `subjectPick` and `activeEffect` but not `isFindingSubject`; the overlay shows "Finding the subject…" whenever `isFindingSubject` is true and the effect isn't `.pickSubject`.
- **Leah's steps:**
  1. Open `TestImages/Stage 9 Practice Photo.png` (or any picture where Select Subject asks you to click).
  2. Choose Select Subject. When the bar asks you to click, click an empty corner of the picture.
  3. While "Looking closer…" shows, press Esc.
  - Expected: the bar and the capsule both go away.
  - Bug: the capsule changes to "Finding the subject…" and stays a few seconds; Select Subject is greyed out meanwhile.
- **Test that would catch it:** app test: start a closer look, `cancelEffect()`, expect `isFindingSubject == false` (the look then stops or its result is ignored).

## 6. The "Set by Auto" wand's tooltip no longer shows
- **Severity:** Low
- **Confidence:** Medium (AppKit shows a tooltip only for the frontmost view under the pointer)
- **Where:** `Sources/Colorbee/AdjustPhotoPanel.swift:85-99`
- **What happens:** The new `slides` overlay is an AppKit view laid over the whole name line, including the wand that marks a slider Auto moved. Its `.help("Set by Auto")` sits under the overlay, so it likely never appears, and the pointer there shows left-right arrows.
- **How to trigger it:** Adjust Photo ▸ Auto, then hover a wand.
- **Why:** `.slides(...)` is applied to the `HStack` holding the title, the wand and the value; `ScrubView` has no tooltip of its own.
- **Leah's steps:**
  1. Open `TestImages/Stage 9 Practice Photo.png`.
  2. Open Adjust Photo and click Auto.
  3. Hold the pointer still over one of the small wand icons next to a slider's name for a second.
  - Expected: a "Set by Auto" tooltip.
  - Bug: no tooltip; the pointer is a left-right arrow.
- **Test that would catch it:** hand test only.

## 7. A drag that passes under the sidebar leaves the plain arrow pointer for the rest of the drag
- **Severity:** Low
- **Confidence:** High
- **Where:** `Sources/Colorbee/CanvasView.swift:463-466` and `:473`
- **What happens:** While drawing, moving under the sidebar sets the arrow, as intended. Coming back onto the picture mid-drag doesn't set the tool's pointer again, because that only happens when no drag is running. So the arrow stays until the button is let go; with the Eraser you see the arrow and the eraser square together.
- **How to trigger it:** draw from the picture into the sidebar and back without letting go.
- **Why:** `updatePointer` sets `NSCursor.arrow` whether or not a drag is running, but sets `currentCursor(at:)` only `if drag == nil`.
- **Leah's steps:**
  1. Open `TestImages/Help/Sample Screenshot.png` with the sidebar showing.
  2. Choose the Eraser (E). Press on the picture and, holding the button, drag onto the Layers panel and back onto the picture.
  - Expected: the eraser square alone, as before the drag.
  - Bug: an arrow pointer shows along with the square until you let go.
- **Test that would catch it:** hand test only.

## 8. A quick Shift- or ⌘-click can be read as a plain click
- **Severity:** Low
- **Confidence:** Low (confirm by trying it; SwiftUI may fire the single tap at once)
- **Where:** `Sources/Colorbee/LayersPanel.swift:257-263`
- **What happens:** The row has a double-click gesture as well as the single one, so SwiftUI may wait out the double-click time before running the single-click action. By then `NSApp.currentEvent` can be a later event, such as letting go of Shift, whose flags have no Shift. The click then chooses just that one layer and drops the others.
- **How to trigger it:** Shift-click and let go of Shift right away.
- **Why:** `NSApp.currentEvent?.modifierFlags` is the last event the app took from the queue, not necessarily the click.
- **Leah's steps:**
  1. Open `TestImages/Several Layers/Opacity Test.colorproj`. Click the Red layer.
  2. Tap Shift and click the Yellow layer together, lifting Shift as quickly as you can. Try a few times.
  - Expected: every layer from Red to Yellow is chosen each time.
  - Bug: sometimes only Yellow is chosen.
- **Test that would catch it:** hand test only (it depends on timing).
