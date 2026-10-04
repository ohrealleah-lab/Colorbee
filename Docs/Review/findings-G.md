# Review G: undo restoring the wrong layer copies, and history edge cases
Reviewed at commit: 37959d238e7a1e8159577f1ae2440b53903f31b8
Checked:
- `LayerActions.swift`: add, add adjustment, duplicate, delete, merge down, merge visible, flatten, move, apply adjustment, `update`. Each makes a new buffer (`copy`, `composite`, `Compositing.adjust`) rather than sharing one between layers, and places a floating selection first through `change`.
- `Canvas.swift`: `restore`, `layerStackState`, `replaceContents`, `copy` (adjustment layers share their never-written buffer with the copy; pixel layers are copied)
- `History.swift`: `undoOnLayer` and `candidate(for:)` for tile steps, layer steps (settings, buffer, reorder, add and remove), geometry, rotations and flips, selection-only steps, multi-layer steps such as the new Auto-Redact; `Edit.restoreOriginals`; the review A merge fix (holds)
- `SelectionActions.swift`: placing, lift, move, nudge, transform and resize-and-skew of a selection, delete, paste, select/invert/deselect. Undo restores the floating selection's original pixels and destination exactly.
- `Layer.swift`, `ImageActions.swift` (geometry, as far as layer copies go; history internals were review A)
- `Editor.swift`: Revert Layer (`savedLayers`, `savedSize`, `rememberLayersAsSaved`, `markSaved`), Before/After (`asOpened`, `lastSaved`), `recordingChanges`, `finishInteractions`, the layer-settings previews (`previewLayerSettings`, `finishLayerSettings`), `jump(toStep:)`, `undoOnActiveLayer`. Every direct change to layers or pixels in the app target goes through history, except the live previews, which are committed by `finishInteractions`.
- `HistoryPanels.swift`, and `LayersPanel.swift` for the drag-to-reorder problem Leah found while testing review F

Not re-reported: round-1 findings and review E in `RESULTS.md`.

**Hand-tested by Leah on 2026-10-04:** findings 1–4 confirmed; each behaved as described. Finding 5 (memory) wasn't hand-tested.

## 1. Undo on Active Layer can undo a different step from the one its menu names
- **Severity:** Medium (the wrong change is taken back: the user's newest paste, shape or text disappears instead of the step named)
- **Confidence:** High. Confirmed by hand: pencil stroke, ⌘V, then "Undo Pencil on Active Layer" removed the paste and left the stroke.
- **Where:** `Sources/Colorbee/DocumentWindow.swift:296-297` (the title comes from `editor.undoOnActiveLayerName`); `Sources/Colorbee/Editor.swift:634-646` (`undoOnActiveLayer` calls `finishInteractions()` and `placeFloatingKeepingOutline()` before `history.undoOnLayer`); `Packages/ColorbeeCore/Sources/ColorbeeCore/History.swift:438-466` (`candidate` takes the newest step that touched the layer)
- **What happens:** The menu title is worked out while a paste is still floating, or a shape or text is still pending. The command then places them first, and placing makes a new step on the active layer (or, for a paste, merges into the Paste step). `candidate` then picks that step, not the one in the menu.
  - **Paste:** with a pencil stroke made, then ⌘V, the menu reads "Undo Pencil on Active Layer". Choosing it leaves the stroke and removes the pasted image.
  - **Pending shape or text:** the same happens. The rectangle or text being edited is placed and immediately taken back, while the named step stays.
  - ⌘Z brings the change back, so nothing is lost for good, but the command does something other than what it says.
- **How to trigger it:**
  1. Draw a pencil stroke.
  2. Paste an image (⌘V) and leave it floating.
  3. Open the Edit menu: it says "Undo Pencil on Active Layer". Choose it: the stroke stays, and the pasted image is gone.
  4. Same with a rectangle drawn but not placed (Shapes), or text being typed.
- **Why:** Placing changes which step is newest on the layer, after the title was computed.
- **Test that would catch it:** Core test: a pencil-like tile step on the layer, then `SelectionActions.paste` (floating, not placed). Record `undoOnLayerActionName`, then run the same sequence as the Editor (`placeFloating`, then `undoOnLayer`). Expect the undone step's name to equal the recorded one. Possible fixes: compute the title as if the pending objects were placed (treat a floating paste or pending shape as part of the newest step), or grey the item out while something is pending or floating.

## 2. Dragging a layer to reorder it doesn't work
- **Severity:** Medium (FR-8.2 and the stage 6a decision: "Drag a row onto another to reorder"; Layer ▸ has no Move Up/Down, so there's no other way to reorder)
- **Confidence:** High that it's broken (Leah, by hand, 2026-10-04); Low on the cause
- **Where:** `Sources/Colorbee/LayersPanel.swift:116-124` (`.draggable(String(index))` and `.dropDestination(for: String.self)` on each row), `:207-221` (the row's `onTapGesture(count: 2)`, `onTapGesture`, `contentShape` and two inner `Button`s); `Sources/Colorbee/Editor.swift:2353` (`moveLayer`, which works: it goes through `LayerActions.move`)
- **What happens:** Dragging a row in the Layers panel doesn't move the layer.
- **How to trigger it:** Two or more layers; in the Layers panel, drag one row onto another. Nothing moves.
- **Why (unconfirmed):** I can't run the app to see which half fails. The canvas view (under the floating sidebar) registers only for image and file drags (`CanvasView.swift:57`), so it shouldn't take the rows' plain-text drag. Likely causes, in order:
  1. The row's tap gestures (single and double) on the same view as `.draggable`. On macOS these can claim the mouse-down so the drag never starts. The usual remedies are `simultaneousGesture`, or moving the taps off the dragged view.
  2. The drag starts, but the drop isn't delivered to the row under the pointer, because the panel is an overlay above an `NSViewRepresentable`.

  Whether a drag image follows the pointer tells the two apart.
- **Test that would catch it:** A UI test that drags the top row onto the bottom one and checks `canvas.layers` order. Or, by hand: watch for the drag image.

## 3. Revert Layer goes back to a layer without the paste that the saved file contains
- **Severity:** Medium (Revert Layer brings back pixels that differ from the last save)
- **Confidence:** High. Confirmed by hand with the steps below: the paste disappeared on Revert Layer.
- **Where:** `Sources/Colorbee/Editor.swift:2708-2722` (`markSaved` keeps the snapshot's layer buffers as `savedLayers`); `Packages/ColorbeeCore/Sources/ColorbeeCore/Canvas.swift:50-64` (`copy` keeps a floating selection as the selection, not in its layer); against `ProjectFile.swift:56-65` and `Canvas.flattened` (what's written includes the floating selection)
- **What happens:** When ⌘S happens while a paste or moved selection is still floating, the file contains it: stamped into its layer in a project, flattened into an image file. The "Last Saved" view in Before/After shows it too. But `savedLayers` holds the layer without it. Revert Layer later puts back the layer as it was *under* the floating selection: the paste vanishes, or a moved area returns to its old place, although the saved file has it.
- **How to trigger it:**
  1. Paste an image (⌘V) and leave it floating.
  2. ⌘S, then press Return to place it.
  3. Paint over it, then Layer ▸ Revert Layer. The pasted image is gone, though the saved file and Before/After's Last Saved both show it.
- **Why:** The snapshot keeps the floating selection apart from the layer, and `markSaved` uses the layer buffers as they are.
- **Test that would catch it:** Core-level helper for "the layers as saved". Stamp the floating selection into a copy of its layer, as `ProjectFile.encode` does, and expect the result to equal the decoded project's layer. In the Editor, build `savedLayers` from those stamped copies.

## 4. Revert Layer after a whole-image flip or 180° rotation puts one layer back unturned
- **Severity:** Low (one layer ends up mirrored or upside down against the others)
- **Confidence:** High on the behavior (confirmed by hand: the top layer flipped back over a mirrored bottom layer); whether it's intended is Leah's call
- **Where:** `Sources/Colorbee/Editor.swift:612-631` (`canRevertLayer` checks only that `canvas.size == savedSize`)
- **What happens:** §23 (stage 6b) makes Revert Layer unavailable "after the canvas size changed", to keep it from mixing geometries. Flip Horizontal, Flip Vertical and Rotate 180° (and Rotate 90° on a square image) turn every layer but keep the size, so Revert Layer stays available. It then restores the saved, unturned pixels into one layer, while every other layer stays turned.
- **How to trigger it:** A two-layer project with something on each layer. ⌘S, then Image ▸ Flip ▸ Horizontal, then Layer ▸ Revert Layer on the top layer. The top layer is back the original way round over a mirrored bottom layer.
- **Why:** The check only compares sizes, not whether a geometry step happened since the save.
- **Test that would catch it:** Record history's count of geometry and transform steps (or a "geometry revision") at save time, and make Revert Layer unavailable once it differs. Editor-level test: save, flip, then expect `canRevertLayer == false`. Ask Leah whether Revert Layer should instead turn the saved pixels too.

## 5. Duplicating an adjustment layer or an empty layer uses full-size memory
- **Severity:** Low (memory, NFR-3)
- **Confidence:** High
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/LayerActions.swift:55` (`source.buffer.copy()`); `PixelBuffer.swift:128-132` (`copy` writes every byte); also `Canvas.copy()` for each save (`Canvas.swift:52`, empty pixel layers)
- **What happens:** An adjustment layer, or a pixel layer never painted on, takes no memory (`isUntouched`; §23 6b: "new empty layers take no memory until painted on"). `copy()` writes the whole destination buffer, so the duplicate commits full-size memory, 256 MB at 8000 × 8000. It also no longer counts as `holdsNoPixels`, so later crops, rotations and resizes copy it in full (and so does history). Each save's snapshot does the same for every empty pixel layer, for as long as the save takes.
- **How to trigger it:** An 8000 × 8000 image. Add a Levels adjustment layer, then Layer ▸ Duplicate Layer a few times. Resident memory grows by about 256 MB per duplicate, with nothing drawn.
- **Why:** `PixelBuffer.copy()` doesn't check `isUntouched`.
- **Test that would catch it:** `copy()` of an untouched buffer returns a buffer that `isUntouched`. A core test: duplicate an adjustment layer, then expect `canvas.activeLayer.buffer.isUntouched`.
