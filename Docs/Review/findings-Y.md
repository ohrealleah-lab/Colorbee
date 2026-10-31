# Review Y: text layers and redaction safety
Reviewed at commit: 079bee95d41f6a27c4bf7bc6590288dc28d764b8
Checked: `TextLayer.swift`, `LayerActions+Text.swift`, `TextRenderer.swift`, `History.swift` (`Edit.willModify`, `willChangeText`, `record`, `swapPixels`, `undoOnLayer`, `candidate`), `History+Snapshots.swift`, `HistorySnapshot.swift`, `Canvas.swift` (`copy`, `transform`, `restore`, `layerBuffersAsSaved`), `ProjectFile.swift` (text entries), `LayerActions.swift` (merges, duplicate, flatten), `LayerActions+Several.swift`, `LayerActions+Masks.swift` (bake), `LayerAlign.swift`, `ImageActions.swift`, `Warp.swift`, `Decorations.swift`, `AutoRedact+Apply.swift`, `Effects.apply`, Editor (Text section, Redact Brush, Batch Redact and effect previews, `refusedBecauseLocked`, `activeLayerTakesEdits`, Revert Layer, undo), `CanvasView` text editing and double-click, `Renderer` overlay and `replacedLayer`, `LayerMenu`, `LayersPanel` text badge and double-click, `DocumentWindow` menu validation.

Also checked: `CanvasTextView.swift`, and that every other Editor pixel command (strokes, shapes, fill, gradient, Retouch, Match Tone, Paste, Delete, Remove Red-Eye, Auto Contrast, Same as Last) refuses a text layer; they do. The help pages weren't checked. Snapshots, the spill file, autosave and Remove Earlier Versions looked safe for text: words stay in undo steps and snapshots only until `History.removeAll`, as the pixels do.

## 1. A duplicated text layer keeps its words in its name after a redaction
- **Severity:** High (a secret left visible)
- **Confidence:** High
- **Where:** `LayerActions.swift:122` (`copy(of:)` names it "\(source.name) copy"), `History.swift:78`, `LayerActions+Text.swift:33`
- **What happens:** Duplicate Layer on a text layer named "Card 4111 2222" makes a text layer named "Card 4111 2222 copy". When you redact it, the words turn into pixels, but the name stays, because redaction renames only when the name exactly matches the words. The name is shown in the Layers panel and saved in the project. Editing the copy's words doesn't update its name either, so even fixing the words by hand leaves the old ones in the name.
- **How to trigger it:**
  1. Open `TestImages/Stage 9 Practice Photo.png`. Choose the Text tool and turn on Editable.
  2. Click the picture, type `Card 4111 2222`, then press Esc.
  3. Choose Layer ▸ Duplicate Layer.
  4. Hide the original text layer. With the Redact Brush (Solid Fill), paint over the copy's words.
  5. Look at the Layers panel: the copy is still named "Card 4111 2222 copy". Save it as a project, close it and reopen it: the name is still there.
- **Why:** `willModify` only renames when `layer.name == text.name`, and "… copy" never matches. `setText` has the same check, so the copy's name never follows its words.
- **Recommended fix:** Keep a flag on the layer saying "my name came from my words" (copied when the layer is duplicated, cleared when the user renames it). Redaction and rasterizing use that flag instead of comparing strings.
- **Test that would catch it:** Add a text layer, duplicate it, redact the copy through `AutoRedact.apply`, and check the copy's name doesn't contain the words.

## 2. A text layer turned into pixels some other way keeps its words in its name, and a later redaction doesn't rename it
- **Severity:** High (a secret left visible)
- **Confidence:** High
- **Where:** `LayerActions+Text.swift:51` (Rasterize Text), `LayerActions+Masks.swift:96` (Apply Mask), `TextLayer.swift:95` and `:102` (skew, uneven resize, Straighten, Perspective, crop or resize while turned), `Decorations.swift:149` (Border/Drop Shadow), merges whose result is the text layer (`LayerActions.swift:177`, `:205`, `:262`; `LayerActions+Several.swift:26`); `History.swift:74–79`
- **What happens:** Each of these sets `text = nil` and keeps the name made from the words. After that the layer is a plain layer, so a redaction doesn't rename it (decision 5 applies only while it's still a text layer). The most common path is the one the app itself suggests: "Rasterize Text first", then paint, then redact.
- **How to trigger it:**
  1. Open `TestImages/Stage 9 Practice Photo.png`. With Editable on, type `PIN 4321` and press Esc.
  2. Choose Layer ▸ Rasterize Text.
  3. With the Redact Brush, paint over the words.
  4. The layer is still named "PIN 4321". Save as a project and reopen it: the name is still there.
- **Why:** `willModify` only renames when `layer.text` isn't nil; every conversion above clears `text` first.
- **Recommended fix:** The same flag as finding 1, so redaction renames a layer whose name came from words even after it became pixels. Or rename to "Text" at conversion time (that changes visible behavior, so it's Leah's call).
- **Test that would catch it:** Add a text layer, rasterize it, redact it, and check its name is "Text". Do the same for a skewed resize and for Apply Mask.

## 3. Cancelling Batch Redact ▸ Blur… or Pixelate… turns a text layer into pixels for good, with no undo step
- **Severity:** High (lost work)
- **Confidence:** High
- **Where:** `Editor.swift:3686–3697` (`renderEffectPreview`), `Editor.swift:4352` (`cancelEffect`), `History.swift:74–79`, `Editor.swift:5560–5570` (`withoutEffectPreview`)
- **What happens:** The preview goes through the step's `Edit`, and `willModify` immediately clears the text layer's `text` and renames it "Text". Cancel's `restoreOriginals()` puts the pixels back but not the text or the name, and no step is recorded, so Undo can't bring them back. The layer stays plain pixels named "Text" and can no longer be edited. An autosave during the preview saves it that way too.
- **How to trigger it:**
  1. Open `TestImages/Stage 9 Practice Photo.png`. With Editable on, type `Hello` and press Esc.
  2. Draw a rectangle selection over the word.
  3. Choose Batch Redact ▸ Blur…, then click Cancel.
  4. The layer is now named "Text", has no "Aa" badge, and double-clicking it doesn't open the words. Undo doesn't fix it.
- **Why:** `restoreOriginals` only puts back tiles; `textsBefore` is never applied when a preview is thrown away.
- **Recommended fix:** Give `Edit` a way to put back `textsBefore` in `restoreOriginals`, or turn the text layers into pixels only at Apply.
- **Test that would catch it:** App test: start a Batch Redact Blur over a text layer, cancel it, and check `text` and `name` are unchanged.

## 4. Align and Distribute move a text layer's pixels but not its words, so the text jumps back later
- **Severity:** High (wrong result)
- **Confidence:** High
- **Where:** `LayerAlign.swift:120–127`
- **What happens:** `move` gives the layer a shifted buffer but leaves `layer.text.spec.origin` where it was. The layer is no longer "its words drawn". Then:
  - Double-clicking the text where you can see it misses, because the hit test uses the old box.
  - Edit Text opens the box at the old place, and placing it draws the words back there.
  - Any crop, uniform resize or canvas resize redraws the text from the spec, so it jumps back to where it was before the Align.
  - The project saves the moved pixels together with the old position.
- **How to trigger it:**
  1. Open `TestImages/Stage 9 Practice Photo.png`. With Editable on, type `Title` near the left and press Esc.
  2. Choose Layer ▸ Align ▸ Centers. The title moves to the middle.
  3. Choose Image ▸ Canvas Size and add 10 px of width (or crop a little off the bottom).
  4. The title jumps back to the left.
- **Why:** Align isn't greyed out on text layers (`isPixelLayer` is true), and `move` never touches `text`.
- **Recommended fix:** In `move`, shift each text layer's spec by its offset (`fitted(scale: 1, dx:, dy:)`), and redraw it if part of it was past the canvas edge.
- **Test that would catch it:** Align a text layer, then crop; check the pixels match `text.drawn` at the moved position.

## 5. Turning Editable off while a text box is open places the text on a layer that should refuse it
- **Severity:** Medium
- **Confidence:** High
- **Where:** `Editor.swift:2169` (the check happens only when the box opens), `Editor.swift:2328–2331`, `DocumentView.swift:261`
- **What happens:** With Editable on, a box can be opened while the active layer is locked, a text layer, an adjustment layer or a group. Unticking Editable before placing draws the text with `Compositing.draw` onto `paintLayer` with no check:
  - A locked layer gets changed.
  - A text layer is silently rasterized and renamed "Text", which decision 7 says should be refused.
  - An adjustment layer or group gets pixels in its buffer that never show, but still makes an undo step.
- **How to trigger it:**
  1. Open `TestImages/Stage 9 Practice Photo.png`. Lock the Background layer.
  2. Choose the Text tool with Editable on, click the picture and type `Hi`.
  3. Untick Editable and press Esc.
  4. The words are now in the locked Background layer.
- **Recommended fix:** In `commitPendingText`, when the text would become pixels, check `refusedBecauseLocked()` again (keeping the typed words, or placing them as a text layer instead). Or place the box when the switch changes.
- **Test that would catch it:** App test: open a box with Editable on over a locked layer, turn Editable off, commit, and check the layer's pixels are unchanged.

## 6. Words cut off by a crop, or past the canvas edge, stay in the text layer and the project, and come back
- **Severity:** Medium (privacy; Q29.3 keeps text crisp, but this side effect was never decided)
- **Confidence:** High
- **Where:** `TextLayer.swift:90–107`, `ImageActions.swift:21`, `:96`, `ProjectFile.swift:180`
- **What happens:** Cropping keeps the whole spec, so the cropped-away lines stay in the layer, in Edit Text, and in the saved project. Making the canvas bigger again redraws them. Auto-Redact can't find them, because they aren't on the canvas. Cropping is a natural way to "remove" a line of text.
- **How to trigger it:**
  1. Open `TestImages/Stage 9 Practice Photo.png`. With Editable on, type two lines (`Name` / `SSN 123-45-6789`) and press Esc.
  2. Crop so the second line is cut off.
  3. Choose Image ▸ Canvas Size and add height at the bottom.
  4. The SSN line reappears. (Double-clicking the text also shows it.)
- **Recommended fix (Leah's call):** Turn a text layer into pixels when a crop cuts through its box, or at least say so in the help.
- **Test that would catch it:** Crop through a text layer and check its spec doesn't hold words that aren't drawn.

## 7. With Editable on, the text being typed is drawn inside the active layer, so it can look wrong or be invisible
- **Severity:** Medium (the screen disagrees with the result)
- **Confidence:** High
- **Where:** `Renderer.swift:458–463`, `:525–530`, `CanvasView.swift:262`
- **What happens:** The overlay is drawn into the active layer, but the placed text goes on a new layer at Normal 100% with no mask:
  - On an adjustment layer, a group, or a hidden layer, nothing shows while typing; only the caret does.
  - On a masked, faded or blend-mode layer, it shows masked, faded or blended.
  - On a layer with Lock Transparent Pixels, it's clipped to that layer's shape.
  - When editing an existing text layer that has Lock Transparent Pixels, the new words are clipped to the old words' shape, but placing them isn't.
- **How to trigger it:**
  1. Open `TestImages/Stage 9 Practice Photo.png`. Choose Layer ▸ New Adjustment Layer ▸ any, so it's active.
  2. Choose the Text tool with Editable on, click and type. Nothing appears.
  3. Press Esc. The text appears.
- **Recommended fix:** When the box will become a new text layer, draw the overlay as its own Normal layer above the active one. When editing a text layer, skip the locked-patch clipping.
- **Test that would catch it:** By hand, as above.

## 8. Deleting every word of a text layer leaves its "Only the layer below" layers behind, or does nothing when it's the only layer
- **Severity:** Low
- **Confidence:** High
- **Where:** `LayerActions+Text.swift:23–29`
- **What happens:** "Delete Text" removes only the text layer. Delete Layer also removes the layers clipped onto it (`deletedRange`), but this doesn't, so they clip onto the layer below and change the picture. When the text layer is the only layer, the delete is silently refused and the old words come back with no message.
- **How to trigger it:**
  1. Make a text layer and add an adjustment layer set to "Only the layer below" on it.
  2. Double-click the text, delete every word, and press Esc.
  3. The adjustment now changes the layer underneath.
- **Recommended fix:** Use `LayerActions.deletedRange` here, and show a notice when the text layer is the last layer.
- **Test that would catch it:** Core test of `setText` with an empty string on a layer that has a clipped adjustment.

## 9. Revert Layer renames a text layer "Text"
- **Severity:** Low
- **Confidence:** High
- **Where:** `Editor.swift:1025`, `History.swift:78`
- **What happens:** Revert Layer goes through `willModify`, which renames a text layer as if it were redacted. Decision 9 says only that the saved look comes back as pixels; the rename is unexpected (Undo puts it back).
- **How to trigger it:**
  1. Save a project with a text layer named after its words.
  2. Edit the words.
  3. Choose Revert Layer. The layer is now named "Text".
- **Recommended fix:** Rename only for redactions (for example, a flag on the `Edit`).
- **Test that would catch it:** App test: Revert Layer on a text layer keeps its name.
