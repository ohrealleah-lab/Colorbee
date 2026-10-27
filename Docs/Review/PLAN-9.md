# Code review round 8: everything since round 7 (session T)

Round 7 ([PLAN-8.md](PLAN-8.md), session S) reviewed up to `146e73c`. Everything since is review S's fixes, the Info
panel, and a day of polish from Leah's hand tests: about 1,050 lines added in 32 files. See them with
`git log --oneline 146e73c..HEAD -- '*.swift' Scripts` and
`git diff 146e73c..HEAD -- 'Sources/*.swift' 'Packages/ColorbeeCore/Sources/*.swift' Scripts`.

One session, **T**. Colorbee is feature-complete apart from Leah's chosen exceptions; this checks the new work before the
next beta.

## Rules

The same as round 7 ([PLAN-8.md](PLAN-8.md), "Rules"): run locally in Leah's Colorbee folder; **don't touch git**;
your only output is `Docs/Review/findings-T.md`; **don't build, run the app or run tests**, reason from the code (quick
throwaway scripts in the scratch folder are fine, nothing long or memory-heavy); never open Leah's personal files
(Downloads, Desktop, Documents, Pictures), use only `TestImages`; don't re-report earlier rounds
([RESULTS.md](RESULTS.md)); decisions in FRD §23 (entries 2026-10-23 to 2026-10-27 are new) are intended; don't
suggest features. Follow "Findings file format" in [PLAN.md](PLAN.md). Give Leah exact numbered steps and a `TestImages`
file for anything she can see by hand. Rank by how much it would hurt Leah or a tester: lost work, a crash, a freeze or
a secret left visible first.

## What changed, and what to look for

- **Choosing several layers** (FR-8.6; `Packages/ColorbeeCore/Sources/ColorbeeCore/LayerActions+Several.swift`,
  `LayerActions.swift`; `Sources/Colorbee/Editor.swift` "Choosing several layers"; `LayersPanel.swift`,
  `LayerMenuArea.swift`, `DocumentWindow.swift` menu validation). The biggest change, so look hardest here.
  - `mergeLayers`: the result's place (the `anchor` and `holder` logic), its name, the background layer staying the
    background, clipped ("Only the layer below") adjustments on chosen and unchosen layers, hidden chosen layers and
    hidden clips, locked layers, a merge whose top is an adjustment layer. Does the picture ever change when the
    merged layers are next to each other? Can `removeLayer`'s "at least one layer" precondition ever fire?
  - `deleteLayers`, `duplicateLayers`, `moveLayers`, `update(_:layersWithIDs:)`: indices after removals and inserts,
    the active layer afterwards, clip groups, one undo step each, and undo and redo restoring exactly.
  - Editor state: `otherChosenLayerIDs`, `chooseAnchor`, `chosenLayerIDs`. Can a stale ID (a layer deleted by undo, a
    page change, crop or resize, a merge) make a command act on the wrong layer? Are all the resets in place
    (`layerCommand(keepingChoice:)`, undo, redo, `pageDidChange`)? Opacity and blend mode on several layers
    (`previewLayerSettings(onChosen:)`, `chosenLayerSetting`) with locked and adjustment layers among them.
  - `LayerMenuView.hitTest` returns a view only when `NSApp.currentEvent` is a right-click or Control-click. Is that
    reliable, or could it swallow left clicks, drags, cursor updates or tooltips, or miss a right-click? Do
    `ClosureMenuItem`s stay alive while the menu is open (`target = self`)? Is setting SwiftUI `@State` from the menu's
    closures (Rename) safe?
  - Layers panel: Shift- and ⌘-click read `NSApp.currentEvent?.modifierFlags` inside `onTapGesture`; dragging chosen
    layers together.
- **The pointer over the sidebar** (`CanvasView.isUncovered`, `updatePointer`, `cursorUpdate`, `pointerLeft`): a
  `hitTest` on every mouse move. Is it right over the rulers, the text box, Before/After's split view, the page sidebar
  and the effect bars? Can a drag that starts on the canvas and moves under the sidebar misbehave? Any cost worth
  worrying about?
- **Canvas keys and focus** (`CanvasView.viewDidMoveToWindow`, `DocumentWindow.keyDown`): the canvas takes the
  keyboard when it joins its window, and canvas keys that reach the window unused are forwarded to it. Look for an
  endless loop between the window and the canvas, keys stolen from a text field, sheet, effect bar, the size box or
  the Settings window, and typing in the canvas text box.
- **The ⇧S Sidebar key and button tooltips** (`ShortcutStore.canvasCommands`, `hint`; `DocumentToolbar.swift`,
  `RetouchKind.tooltip`, `PageSidebar.swift`, `LayersPanel.swift` switcher; `MainMenu.swift` View ▸ Sidebar ⌃⌘S;
  `Editor.toggleSidebar`, `canToggleSidebar`). A saved or imported shortcut book that predates `canvas.sidebar`;
  conflicts with keys Leah may already have assigned.
- **Save and Export start in the picture's folder** (`ImageDocument`: `sourceFolder`, `startFolder`,
  `prepareSavePanel`, the export panels, `encodeRestorableState` and `restoreState`; `DevelopWindow`). Decoding the
  folder URL from restorable state, documents opened as copies, PDFs, RAW photos, and untitled images.
- **Small subjects** (`SubjectScan.findCloser`, `closerSquares`, `placed` in `Subjects.swift`; `Editor.findSubject`,
  `pickSubject`, `applyEffect`, `pickHasSubjects`; the pick bar in `DocumentView.swift`). Crop coordinates (CGImage
  cropping is top-left, in pixels), the mask placed back in the right spot, a click while a closer look is running,
  Cancel or Esc mid-look, Return with no subjects, and the image or layer changing meanwhile.
- **Easier sliders** (`ScrubArea.swift` `slides` and `followsWidth`; `AdjustPhotoPanel.swift`,
  `AdjustmentsPanel.swift`). `onScrubEnd` calling `finishLayerSettings` or Adjust Photo's `onFinish` when no edit was
  begun; one undo step per drag; the overlay covering the "Set by Auto" wand's tooltip.
- **The Info panel** (`43cdd3c`; FR-1.3): it must never show a location, serial number or owner. Look for file reads on
  the main thread, stale details after Save, Save As or a page change, and details that disagree with the file.
- **Review S's fixes** (`596db10`): the Match Tone pyramid in `RetouchStroke.swift` (`ToneMatch.plan`, `smoothFill`)
  and every save waiting for a pending tone (`ImageDocument`). Correctness, and the time and memory limits RESULTS.md
  quotes.
- **Small things:** the tooltip delay registered in `main.swift`; `LayerActions.canMergeDown` and `canDelete` taking a
  layer index.

New test file: `TestImages/Several Layers/Opacity Test.colorproj` (stripes under Red, Green, Blue and Yellow blocks, one
per layer).

## Prompt for Leah

Run in a fresh local session in the Colorbee folder, on **Opus, high effort**:

> You're a reviewer for Colorbee. Read `Docs/Review/PLAN-9.md` and do **session T**, following its rules exactly:
> review only, don't touch git, don't build or run anything. Write your findings to `Docs/Review/findings-T.md`, then
> tell me how many findings you have at each severity.
