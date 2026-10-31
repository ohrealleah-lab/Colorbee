# Code review round 10 (stage 33): groups, masks, text layers, smoothing, and a risk pass (sessions X, Y, Z, AA)

Round 9 ([PLAN-10.md](PLAN-10.md), sessions U, V, W) ended with its fixes in `c181bdf`. Everything since is stages 25
to 32 of [Development-Plan.md](../Development-Plan.md) (layer groups, layer masks and clipped pixel layers, text
layers, stroke smoothing, the monkey test) and fixes from Leah's hand tests (shape fill color, the toolbar's empty
space, the text box's keyboard): about 2,500 lines in 45 source files. See them with
`git log --oneline c181bdf..HEAD -- '*.swift' '*.metal'` and
`git diff c181bdf..HEAD -- 'Sources/*.swift' 'Sources/*.metal' 'Packages/ColorbeeCore/Sources/*.swift'`.

This is the last review before the beta (Leah, 2026-10-31: "new work + risk pass"). Sessions X, Y and Z cover the new
work; session AA reads the whole app again for the worst risks only. All four are independent and can run at the same
time.

## Rules

The same as round 9 ([PLAN-10.md](PLAN-10.md), "Rules"): run locally in Leah's Colorbee folder; **don't touch git**;
your only output is your findings file, `Docs/Review/findings-<letters>.md`; **don't build, run the app or run tests**,
reason from the code (quick throwaway scripts in the scratch folder are fine, nothing long or memory-heavy); never open
Leah's personal files (Downloads, Desktop, Documents, Pictures), use only `TestImages`; don't re-report earlier rounds
([RESULTS.md](RESULTS.md)); decisions in FRD §23 are intended (entries from 2026-10-30 on are new, many marked "veto
any"), unless the code doesn't do what the entry says; don't suggest features. Follow "Findings file format" in
[PLAN.md](PLAN.md). Give Leah exact numbered steps and a `TestImages` file for anything she can see by hand. Rank by how
much it would hurt Leah: lost work, a crash, a freeze, a secret left visible, or a wrong exported picture first.

Leah has tested every stage by hand, so look for what hand testing misses: undo and redo that isn't exact, edge cases,
old files, big images, and the screen disagreeing with the export.

**Already known, don't re-report:** the monkey test's first trial (2026-10-31) found a crash in Merge Down on a group
that holds every layer (`LayerActions.mergeGroup` removes the canvas's last layer), four cases of a layer thumbnail not
matching the export, and one undo that wasn't exact after a paste, fill, masks, a resize and a crop. The engineer is
looking into those. Explaining a cause is welcome if you find it.

---

## Session X: groups and masks in the model (highest risk)

- **Groups** (`Canvas+Groups.swift`, `LayerActions+Groups.swift`, `Layer.isGroup`/`groupID`/`passesThrough`,
  `keepGroupsTogether`): every command that moves, deletes, duplicates or merges layers keeping each group's layers
  just below it; nested groups; locking and hiding through ancestors; Pass Through versus Normal compositing
  (`Compositing.mixed`, stand-in layers) agreeing with `Canvas.flattened`, thumbnails and patches.
- **Masks** (`LayerActions+Masks.swift`, `Layer.mask`/`activeMask`, `Canvas.paintLayer`/`editsMask`/`allLayers`,
  `Compositing.reveal`): every geometry change, merge, duplicate, snapshot and undo carrying the mask along; Apply and
  Invert being exact; masks on adjustment layers and groups; "Only the layer below" for pixel layers
  (`Compositing.blendAtop`, `clippedLayers(onLayerAt:)`).
- **History** (`History.swift`: `undoOnLayer` and its `candidate`, `LayerStackState.Record`, `GeometryChange`,
  snapshots' `StoredLayer`): anything a layer now holds (group, mask, text) that a step, a snapshot or a spill could
  lose or mix up.
- **Projects** (`ProjectFile.swift`: `Manifest.groups`, `masks`, `LayerEntry.text`, `clipped`): saving and reopening
  exactly, and beta 7 opening them as documented (flat layers, no masks, text as pixels).

## Session Y: text layers and redaction safety

- **The model** (`TextLayer.swift`, `LayerActions+Text.swift`, `Edit.willModify`/`willChangeText`,
  `HistoryEntry.texts`, `Canvas.fitText`, `TextRenderer.hasFont`): a text layer's pixels always being its words drawn;
  every pixel change, geometry change, merge and flatten turning it into pixels or redrawing it as FR-6.3 says; undo,
  redo and Undo on Active Layer putting text and name back exactly; turns (`quarterTurns`, `mirrored`).
- **Redaction safety (highest priority here):** can the words of a redacted text layer survive anywhere: in the saved
  project, a History Snapshot, the spill file, the layer's name, the undo history saved with a document, autosave, or
  an older version? Check every redaction path (Redact Brush, Batch Redact, Auto-Redact, Solid Fill) against
  `Edit.willModify`.
- **The app** (`Editor` "Text", `editText`, `commitPendingText`, `refusedBecauseLocked`, `activeLayerTakesEdits`,
  `CanvasView` double-click and `syncTextEditor`, `CanvasTextView`, the renderer's `replacedLayer`, `LayersPanel` and
  `LayerMenu`): commands that should refuse a text layer but don't, or refuse one they shouldn't; the Editable switch;
  missing fonts.

## Session Z: the app side of stages 25 to 32, and smoothing

- **Renderer and shaders** (`Renderer.swift` `drawNodes`/`drawGroup`/masking, `Shaders.metal` `mask_reveal`,
  `mask_alone_fragment`, `QuadUniforms`): the screen agreeing with `Canvas.flattened` for groups, masks and clipped
  layers at every blend mode and opacity; textures kept or freed correctly.
- **Layers panel and menus** (`LayersPanel.swift` rows, folding, drop targets, mask thumbnails, the Editable checkbox,
  `LayerMenu.swift`, `MainMenu.swift`, `DocumentWindow` validation): commands enabled when they'd do nothing or be
  refused.
- **Smoothing** (`StrokePath.swift`, the stroke, Redact Brush and Retouch sections of `Editor.swift`, `DocumentView`
  `SmoothingControl`): strokes ending exactly where you let go; Shift, Symmetry and pressure with smoothing.
- **Today's fixes:** `Editor.shapeFillColor` and the toolbar's Fill swatch; `WindowDragArea` over hidden toolbar
  controls.
- **The monkey itself** (`Tests/ColorbeeTests/Monkey`): rules that could pass when they shouldn't, steps that aren't
  legal, anything that could save Leah's preferences, touch the clipboard, or leave files behind on an 8-hour run.

## Session AA: the whole app, worst risks only

Read the app with fresh eyes for only these: **lost work** (saving, autosave, versions, reopening, crash recovery,
history spills), **crashes** (preconditions, force unwraps and index math reachable from the interface), **freezes**
(main-thread work on big images), and **a secret left visible after redaction** (anywhere the original pixels or words
could survive: layers, masks, snapshots, history, spill files, thumbnails, clipboard history, exports, PDF pages). Skip
anything slow or cosmetic. Earlier rounds covered a lot, so check [RESULTS.md](RESULTS.md) first and report only what's
still there.

## Prompts for Leah

Run each in a fresh local session in the Colorbee folder, on **Opus, high effort**, in any order or all at once:

> You're a reviewer for Colorbee. Read `Docs/Review/PLAN-11.md` and do **session X**, following its rules exactly:
> review only, don't touch git, don't build or run anything. Write your findings to `Docs/Review/findings-X.md`, then
> tell me how many findings you have at each severity.

For Y, Z and AA, change both letters.
