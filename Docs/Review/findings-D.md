# Review D: interface behavior against the FRD
Reviewed at commit: d67a8626cc8f975618ca03a10a8cf722cece4b5d
Checked:
- FRD FR-9.5, FR-11, FR-14 and the §23 entries dated 2026-10-03, item by item, against the code below
- `MainMenu.swift`: every FR-14.5 item and shortcut; stage 9 placement (Straighten and Perspective next to Rotate, Crop… next to Crop to Selection, Select Subject in Edit, the adjustment-layer submenu at the bottom of Adjustments); `ExportPresetMenuTitles`
- `DocumentWindow.swift` menu validation (Spotlight needs a selection, everything except viewing is disabled while an effect is open)
- `DocumentView.swift`: the effect bar (parameters, ranges and defaults for every effect kind against §23, formatting, option pickers, the "Applies to…" text), the subject overlay and alert, the Before/After bar
- `AdjustPhotoPanel.swift`: groups, Auto marks, Reset, Control-click reset, filter chips, Intensity, Save as Filter, Save Filter from Layers, rename, delete, import, export
- `ToneViews.swift`: histogram; Curves editor (neighbors can't be passed, points stay on the graph, the end points can't be removed, removal by dragging out or double-clicking)
- `AdjustmentsPanel.swift`, `LayersPanel.swift`, `CropOptions.swift` (shapes, custom ratio guarded at 1 or more, swap, pixel-size presets against §23), `FilterStore.swift` (numbering of duplicate and built-in names on add and import), `Settings.swift` (Scaling picker, remembered tab), `StatusBar.swift`, `PaletteBar.swift` and `DocumentToolbar.swift` (stage 8 VoiceOver work)

Not repeated here: review B #4 (Straighten, Perspective and Crop… refused on a locked layer) and review B #5 (Select Subject on a locked layer with several subjects).

## 1. Several sliders have no VoiceOver name, and the Curves graph can't be used with VoiceOver
- **Severity:** Medium (accessibility)
- **Confidence:** High
- **Where:** `Sources/Colorbee/DocumentView.swift:191` (every slider in the effect bar), `Sources/Colorbee/AdjustmentsPanel.swift:246` (every slider for an adjustment layer), `Sources/Colorbee/LayersPanel.swift:298` (the opacity slider in its popover), `Sources/Colorbee/ToneViews.swift:53-90` (Curves)
- **What happens:** These use `Slider(value:in:)` with no label and no `.accessibilityLabel`. The visible name is a separate `Text` beside the slider, so VoiceOver reads just "slider, 8" with no name: Gaussian Blur's radius, Levels' Black, Midtones and White, Drop Shadow's six settings, Straighten's angle, and so on. Adjust Photo's sliders do have labels (`AdjustPhotoPanel.swift:103`), so this is inconsistent. The Curves graph has only `.accessibilityLabel("Curve")`, with no value and no adjustable actions, so it can't be used without a pointer.
- **How to trigger it:** Turn on VoiceOver, open Effects ▸ Gaussian Blur…, and move to the slider: it has no name. The same with a Levels adjustment layer's sliders and the layer opacity popover.
- **Why:** In SwiftUI, `Slider(value:in:)` has no label to read; `labelsHidden()` patterns need a real label, or `.accessibilityLabel`.
- **Test that would catch it:** UI tests or an accessibility audit (`XCUIApplication().performAccessibilityAudit()`) on the effect bar, the Adjustments panel and the opacity popover. Fix: `Slider(value:in:) { Text(parameter.label) }.labelsHidden()`, or `.accessibilityLabel(parameter.label)` plus `.accessibilityValue(formatted)`. For Curves, add a VoiceOver action per point (for example `accessibilityAdjustableAction` on a chosen point), or say in §23 that Curves isn't covered.

## 2. A Levels adjustment layer's histogram and Auto use a stale picture of the layers below
- **Severity:** Low (wrong Auto result; a main-thread pause)
- **Confidence:** High
- **Where:** `Sources/Colorbee/AdjustmentsPanel.swift:185` (`.task(id: editor.canvas.activeLayer.id)`), `:209` (Auto uses `histogramBelow`), `:166` (Adjust Photo layer's Auto); `Sources/Colorbee/Editor.swift:2404-2408`
- **What happens:**
  - **Stale:** The histogram below the layer is worked out only when the active layer's ID changes. Hiding or showing a layer beneath, changing its opacity or blend mode, ⌘Z, or a paste onto a lower layer through Clipboard History doesn't refresh it. Auto then sets black and white points for an image that's no longer there.
  - **Pause:** The histogram composites every layer below on the main thread each time a Levels layer is selected, and so does the Adjust Photo layer's Auto. On a large image with several layers, that blocks for more than a frame (NFR-6).
- **How to trigger it:** A photo, then a Levels adjustment layer above it, made active. Hide the photo's layer with its eye in the Layers panel. The histogram still shows the photo, and Auto still sets points from it.
- **Why:** `task(id:)` keys only on the active layer's ID, not on `layersRevision` or history's revision.
- **Test that would catch it:** Key the task on `editor.layersRevision` together with the active layer's ID, or read the histogram at the moment Auto is pressed. A view-model test can check that `histogramBelowActiveLayer()` changes after a layer below is hidden. For the pause, compute in a `Task.detached` from a snapshot.

## 3. Clicking near a Curves point jumps it to the pointer
- **Severity:** Low
- **Confidence:** High
- **Where:** `Sources/Colorbee/ToneViews.swift:127-151` (`move`), with `DragGesture(minimumDistance: 0)` at `:81`
- **What happens:** A click within 10 pt of a point grabs it, and the first drag event (fired on mouse-down) moves it to where the pointer is, not by how far the mouse moved. Clicking a point to "select" it, or the first click of a double-click to remove it, shifts it by up to 10 pt (about 13 levels on a 200-pt graph), and the shift goes into the preview. A click on the far right edge, beyond the white end point, adds a new end point at x = 255 with the click's height. The old end point becomes an ordinary point that can be removed, so the end point has effectively moved.
- **How to trigger it:** Open Curves…, click 8 pt to the left of the white end point, and release without moving: the curve's top end moves.
- **Why:** `points[index] = value(at: drag.location, …)` uses the pointer's position, not the point plus `drag.translation`.
- **Test that would catch it:** Keep the grab offset (`point = original + translation`) and treat a new point at an end point's x as a move of that end point. A unit test on a small helper that applies a drag to a point list can check both.

## 4. Renaming or deleting the filter that's chosen leaves Adjust Photo pointing at an old copy
- **Severity:** Low
- **Confidence:** High
- **Where:** `Sources/Colorbee/FilterStore.swift:48-57`; `Sources/Colorbee/AdjustPhotoPanel.swift:127` (chips match by name), `:183-189` (Rename and Delete appear only when the name is in the store), `:211-217` (Export uses the copy)
- **What happens:** `PhotoEdit.filter` holds its own copy of the filter. After Rename, no chip is highlighted, the menu's Rename and Delete items disappear (the old name isn't in the store any more), and Export Filter… saves it under the old name. After Delete, the deleted filter is still applied, with its Intensity slider showing, and the "None" chip isn't highlighted. Palettes handle this case: `PaletteStore.rename` updates `activeName`. FR-9.5 says filters are managed "like palettes".
- **How to trigger it:** Adjust Photo…, Save as Filter… "Mine" (it's now chosen), then ⋯ ▸ Rename "Mine"… to "Warm". No chip is highlighted, and the menu no longer offers Rename or Delete.
- **Why:** The store changes, but the panel's `edit.filter` isn't updated.
- **Test that would catch it:** After `rename`, the panel's edit should hold the renamed filter: have `rename` return the new filter and call `onChange` with it. After `delete`, choose None, or keep the look by moving the filter's steps into the sliders. A view-model test on the panel's state would check both.

## 5. While Adjust Photo is open, the toolbar can hide its panel
- **Severity:** Low
- **Confidence:** Medium
- **Where:** `Sources/Colorbee/DocumentToolbar.swift:347-357` (Sidebar button) and the Layers button near `:320`; `Sources/Colorbee/DocumentView.swift:45`, `:199-201`; `Sources/Colorbee/LayersPanel.swift:24-26`
- **What happens:** Adjust Photo's sliders live in the sidebar. The toolbar isn't disabled during an effect (only the palette bar is, `DocumentView.swift:12`), so the Sidebar button, and the Layers button, can close the sidebar. The bar then says "Use the sliders and filters in the panel at the right" with no panel there, and nothing explains how to get it back.
- **How to trigger it:** Adjustments ▸ Adjust Photo…, then click the toolbar's Sidebar button.
- **Why:** `isSidebarOpen` can be toggled freely while `activeEffect == .adjustPhoto`.
- **Test that would catch it:** Disable the Sidebar and Layers buttons while `activeEffect == .adjustPhoto` (or keep the sidebar open for it). A view test can assert the buttons are disabled.

## 6. Subject commands stay enabled while a subject search is running, and do nothing when chosen
- **Severity:** Low
- **Confidence:** High
- **Where:** `Sources/Colorbee/DocumentWindow.swift:90-92` (no validation case, so `super` enables them); `Sources/Colorbee/Editor.swift:1884`
- **What happens:** While "Finding the subject…" shows, Edit ▸ Select Subject, Image ▸ Remove Background and Lift Subject to New Layer are enabled. Choosing one returns silently: no beep, no message. They're also enabled on an adjustment layer, where they beep.
- **How to trigger it:** Image ▸ Remove Background on a large photo, and while the overlay shows, choose Edit ▸ Select Subject: nothing happens.
- **Why:** `findSubject` starts with `guard !isFindingSubject, activeEffect == nil else { return }`, but `validateMenuItem` has no case for these selectors.
- **Test that would catch it:** Add a `validateMenuItem` case that returns false while `editor.isFindingSubject`, or when the active layer is an adjustment layer. A menu-validation unit test with an Editor in that state can check it.
