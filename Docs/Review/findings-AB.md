# Review AB: the Editor
Reviewed at commit: 08094b72da6bb45f122b342dd285728849008e7b
Checked:
- `Sources/Colorbee/Editor.swift`, all 5,613 lines, every `// MARK:` section
- `Sources/Colorbee/CanvasView.swift`: how drags reach the Editor (`beginDrag`, `continueDrag`, `endDrag`, lines 560 to 800)
- `Sources/Colorbee/DocumentWindow.swift`: `validateMenuItem` and its command lists (lines 405 to 630)
- `Sources/Colorbee/DocumentView.swift`, `ImageDocument.swift`: what they read from the Editor (spot checks)
- Core pieces the Editor leans on: `PageStack` (`noteEdit`, `undoName`), `LayerID`, `SelectionHandle.point(on:)`, `Geometry`
- Which app tests reach which Editor paths (names in `Tests/ColorbeeTests`)

## Copies that already differ

**A. "A step was recorded" bookkeeping: two hand-written copies of `recordingChanges` leave out parts.**
`recordingChanges` (`Editor.swift:2617`) does five things when `history.revision` moves: `stopFillForChange()`,
`pages.noteEdit()`, `undone = []`, `onDocumentChange(.done)`, `layersRevision += 1`. Two places do it by hand:
- `applyEffect`, the Drop Shadow / Border / Straighten branch (`Editor.swift:4237-4239`): only `onDocumentChange(.done)`
  and `layersRevision += 1`. The preview step was committed by `Decorations`/`ImageActions` outside `recordingChanges`,
  so `pages.noteEdit()` never runs. Reading `PageStack.undoName` (`PageStack.swift:150`), after **Page ▸ Delete Page,
  then Image ▸ Drop Shadow… ▸ Apply, then ⌘Z**, `undo()` (`Editor.swift:5062`) sees "Delete Page" as still the newest
  change and undoes the page delete instead of the shadow. `undone` isn't cleared either, so Redo's order can be stale.
  This may be a bug; Leah decides. No app test opens Drop Shadow, Border or Apply on Straighten after a page change
  (`StraightenPreviewTests` covers the preview, not this).
- `applyAutoRedact`, the other-pages branch (`Editor.swift:5386-5391`): everything but `stopFillForChange()`. Likely
  harmless (a fill runs on the page shown, whose redaction does go through `recordingChanges`).

**B. "Has the image changed while we worked?" checks: six copies, each checking a different set.**
| Where | revision | same history / page | paint layer id | layer takes edits | edit in progress |
|---|---|---|---|---|---|
| `land(_:)` Match Tone, `:1971` | yes | page id | yes | – | `isEditInProgress` (all 11) |
| `endRetouchStroke`, `:2054` | yes | page id | yes | yes | – |
| `copyText`, `:3403` | yes | `history ===` | – | – | – |
| `removeRedEye`, `:3441` | yes | – | yes | yes | – |
| `findSubject`, `:3488` | yes | – | yes | – | stroke and gradient only, plus `activeEffect` |
| `applySameAsLastPhoto`, `:3988` | yes | page id | yes | – | – |

Most gaps are covered by something else (layer ids are UUIDs, so another page's layer never matches; locking is a
step, so the revision moves). The one that looks real: `findSubject` checks `activeStroke` and `gradientDrag` but not
the other in-progress edits that `isEditInProgress` (`:1982`) lists, such as a Clone Stamp stroke (`retouchBrush`) or a
Redact Brush stroke. Leah decides whether that matters.

**C. Effect slider values read with two different fallbacks.** `EffectKind.effect` (`:247`), `renderDecorationPreview`
(`:3561`) and `straightenSettings` (`:3583`) fall back to the parameter's default; `rangeSettings` (`:2777`) and
`rangeCombineMode` (`:2788`) fall back to 0. Harmless today because `beginEffect` always fills `effectValues`
(`:3083`), but the next copy will pick one of the two at random.

**D. Redact Brush and Remove/Spot Heal overlays differ by one number.** The two twin strokes (finding 7) tint their
area `Pixel(r: 230, g: 40, b: 60, a: 120)` (`:1803`) and `a: 110` (`:2005`). Probably deliberate; worth a name if so.

---

## 1. One helper for "a step was recorded", used by every place that records one
- **Worth:** High
- **Kind:** Copies
- **Size:** Small
- **Risk:** If Leah calls copy A a bug, routing the decoration branch through the helper changes ⌘Z after a page
  change; that must be decided first and needs a new app test (Delete Page, Drop Shadow, Apply, ⌘Z undoes the shadow).
  If not, keep the branch's behavior with a parameter. `EditorCommandTests`, `CanvasToolAndPageTests`,
  `AutoRedactEditorTests` and `StraightenPreviewTests` cover the other callers.
- **Where:** `Editor.swift:2617` (`recordingChanges`), `:4237-4239` (`applyEffect`), `:5386-5391` (`applyAutoRedact`),
  and `:831-834` (`changePages`, which is meant to be different: a page change, not an edit).
- **What:** Five pieces of bookkeeping must happen together whenever a step lands. The rule is written once and copied
  twice, and the copies already differ (see A).
- **Suggested change:** a private `noteEdited()` that does the five things. `recordingChanges` calls it when the
  revision moved; the two hand-written branches call it instead of their own lines. A comment on `changePages` says why
  it doesn't.

## 2. Split Editor.swift into one file per `// MARK:` section
- **Worth:** High (makes a 5,600-line file workable)
- **Kind:** Hard to change
- **Size:** Medium
- **Risk:** Very low: moving methods and computed properties into `extension Editor` in other files changes no
  behavior. `private` members used from another section's file must become `internal` (or stay in the main file), which
  widens access inside the app target only. `make test` as a whole catches a slip; nothing new needed.
- **Where:** `Editor.swift` sections at `:746` (Pages), `:875`/`:892` (History), `:940` (Canvas), `:1062` (Tools),
  `:1194`–`:2164` (Painting, Gradient, Measure, Shapes, Redact Brush, Retouching, Step badges), `:2164` (Text),
  `:2410`–`:2966` (Selection), `:3044`–`:3745` (Image, Effects, Straighten/Crop, Messages, Red-Eye, Subjects),
  `:3745`–`:4262` (Adjust Photo picks, drags, histogram), `:4262` (After a redaction), `:4375`–`:5043` (Layers, masks,
  groups, align), `:5043` (Undo), `:5212` (Auto-Redact), `:5434` (Before/After), `:5507` (Files). Also the types at the
  top (`:6-421`: `Tool`, `EffectKind`, `AutoRedactSession`, `PendingShape` and the rest).
- **What:** One file holds ~120 stored properties and ~300 methods for a dozen unrelated jobs. Swift won't let stored
  properties live in extensions, which is why everything is in one file; but the methods don't need to be.
- **Suggested change:** step one of a gradual split. Move the top-level types to their own files (`EffectKind.swift`,
  `PendingObjects.swift`, `AutoRedactSession.swift`). Then `Editor+Shapes.swift`, `Editor+Text.swift`,
  `Editor+Selection.swift`, `Editor+Effects.swift`, `Editor+AdjustPhoto.swift`, `Editor+Layers.swift`,
  `Editor+Pages.swift`, `Editor+AutoRedact.swift`, `Editor+Files.swift`, each holding that section's methods. The stored
  properties stay in `Editor.swift`, regrouped under the same section names so each extension's state is in one block.
  Findings 4, 7 and 12 then move state out of `Editor.swift` piece by piece, into small objects that own it. Pieces and
  what crosses between them:

  | Piece | Would own | Reads from the Editor |
  |---|---|---|
  | Effect session (finding 4) | `activeEffect`, values, curves, photo edit, edit, source, regions, preview workers, crop, perspective, Straighten, ranges, subject pick | canvas, history, `selectionContext`, colors, viewport (hit tests), `recordingChanges`, `selectionDidChange`, `zoomToFit`, sidebar flags |
  | Pending objects | `pendingShape/Text/Badge`, render caches, `shapeDrag`, `badgeDrag`, `textBoxDrag`, `badgeSteps`, `nextBadges` | colors, shape and text settings, viewport zoom, canvas, history; undo reads `badgeSteps` |
  | Auto-Redact | `autoRedact`, `redactionPatterns`, clipboard cleanup, `copiedTextClipboardCount`, `redactedSinceSave` | pages, `color1`, `recordingChanges`; **undo reads `redactionGroups`** (keep that with Undo) |
  | Page baselines | `opened`, `saved`, `savedGeometrySteps`, `pageMemory`, `lastSavedSnapshot/Image` | pages, viewport (saved per page), history's geometry steps |
  | Before/After | `comparison` | baselines above, viewport |

## 3. One "newest settings win" background worker instead of five hand-rolled ones
- **Worth:** High
- **Kind:** Copies
- **Size:** Medium
- **Risk:** Each copy has its own edge: Straighten must stop and *wait* (`stopStraightenPreview`, semaphore) before
  anything else touches the layers; Feather's OK waits for the newest radius (`appliesSelectionChangeWhenShown`); the
  effect preview refreshes the histogram after showing. Keep those outside the helper. Covered by
  `StraightenPreviewTests`, `FeatherTests`, `SelectionRangeBarTests`, `PhotoHistogramTests`, `ShapeAndTextEditingTests`
  (textured shapes). The helper itself needs a new app test (request twice while running: only the newest is shown; a
  result after `cancel()` is dropped).
- **Where:**
  - Effect preview: `previewRunning`, `previewWanted`, `previewGeneration`, `shownEffect` (`:657-666`), `:3654-3693`
  - Straighten: `straightenRunning`, `straightenWanted`, `straightenShown`, `straightenToken`, `straightenWork`
    (`:3137-3142`), `:3590-3650`
  - Feather / Modify Selection: `selectionChangeShown/Running/Session`, `appliesSelectionChangeWhenShown`
    (`:2670-2673`), `:2686-2747`
  - Color/Luminance Range and Graduated Selection: `rangeShown`, `rangeRunning`, `rangeSession`, `rangeMask`
    (`:2756-2760`), `:2847-2863`, `:2814-2824`
  - Textured shapes: `shapeRenderInFlight`, `shapeRenderWanted`, `shapeRenderGeneration` (`:683-686`), `:1513-1541`
  - Single searches with their own counters: `cornerSearch` (`:3154`), `closerLook` (`:3469`)
- **What:** The same small machine (running? something newer waiting? which settings are shown? a counter so a late
  result from a closed session is ignored) is written five times, with three to five properties each that must be
  reset together. Review B, finding 6 was a bug in exactly one of these copies.
- **Suggested change:** a `@MainActor final class LatestWork<Settings: Equatable, Output>`: `request(_ settings:)`,
  `shown: Settings?`, `isRunning`, `cancel()` (bumps its generation), and a `show` closure called on the main actor
  with the newest result. Each piece holds one `LatestWork` instead of its flags. Lives in the app (it's about
  scheduling, not pixels), in its own file.

## 4. The effect session as one value, created whole and ended in one place
- **Worth:** High
- **Kind:** Hard to change
- **Size:** Large
- **Risk:** Highest of these. `cancelEffect`, `applyEffect` and `withoutEffectPreview` touch history (undoing a
  decoration preview step, restoring originals), and autosave runs in the middle of a session. Do finding 3 first. App
  tests that reach the session: `EditorCommandTests`, `StraightenPreviewTests`, `CanvasToolAndPageTests`,
  `SubjectPickTests`, `SelectionRangeBarTests`, `PhotoSettingsTests`, `PhotoHistogramTests`, `WhiteBalancePickTests`,
  `PictureDragTests`, `PhotoGeometryTests`, `AutoRedactEditorTests` (Batch Redact). Missing first: a test that applies
  Drop Shadow and Border (none open them today), and one that autosaves (`saveSnapshot`) during Crop and Perspective.
- **Where:** state spread over `:632-666`, `:2752-2760`, `:2896-2898`, `:3134-3217`, `:3464-3469`, `:652`; set up in
  `beginEffect` (`:3074-3131`, about 25 assignments); reset in `endEffectSession` (`:4338-4351`) and `cancelEffect`
  (`:4353-4373`). `activeEffect = nil` is written in eight places: `:2889`, `:3527`, `:3543`, `:4200`, `:4209`, `:4235`,
  `:4255`, `:4371`. Only some of them call `endEffectSession()` first: the Crop/Perspective (`:4209`), decoration
  (`:4235`) and Pick Subject (`:3527`, `:3543`, `:4200`) exits leave `effectRegions`, `effectHistogram`,
  `effectValues`, `perspectiveCorners` and so on behind. That's harmless only because `beginEffect` resets them next
  time.
- **What:** About 45 properties make up "the effect whose bar is open". Each exit has to remember its own subset to
  clear, and each background job has its own counter to tell a closed session's late result apart.
- **Suggested change:** `private(set) var effect: EffectSession?` (an `@Observable` class), made whole by
  `beginEffect` and set to nil only by one `endEffect(applying:)`, which does what all eight exits do today: stop
  Straighten and wait, undo a decoration preview step if cancelling, restore originals. `activeEffect` stays as a
  computed `effect?.kind` so the views and `DocumentWindow` don't change. Background jobs capture the session object and
  check `self.effect === session` instead of `previewGeneration`, `straightenToken`, `rangeSession`, `cornerSearch`,
  `closerLook`. Kind-specific state (crop box, perspective corners, range colors, graduated line, subject pick) goes in
  an enum payload on the session, so a Crop session can't carry a stale Straighten line.

## 5. One "image is still as it was" stamp for background work
- **Worth:** Medium
- **Kind:** Copies
- **Size:** Small
- **Risk:** Making all six check the same things could change when a notice appears (see B). Agree the set with Leah
  first. Covered by `RedactAndRetouchTests` (Remove), `SubjectPickTests`, `PhotoSettingsTests` (Same as Last),
  `CopyTextTests`, `StrokeTests`/`RedactAndRetouchTests` (Clone Stamp Match Tone); Red-Eye has no app test that changes
  the image mid-search (new test needed).
- **Where:** `Editor.swift:1946`/`:1971`, `:2038`/`:2054`, `:3397`/`:3403`, `:3434`/`:3441`, `:3480`/`:3488`,
  `:3980`/`:3988`.
- **What:** Each async command captures some of revision, page id and layer id, and checks a different mix when it
  lands (table B). A new async command will copy whichever one is nearest.
- **Suggested change:** `private struct EditStamp: Equatable { history: ObjectIdentifier; revision; page: UUID; layer:
  LayerID }`, a `var editStamp` that builds it, and `func isCurrent(_ stamp:) -> Bool` that also checks
  `!isEditInProgress` and `activeLayerTakesEdits` where the caller asks. Each command keeps its own notice text.

## 6. Text style ↔ text spec mapping written twice, field by field
- **Worth:** Medium
- **Kind:** Copies
- **Size:** Small
- **Risk:** Low. `TextLayerAppTests` and `ShapeAndTextEditingTests` cover editing a text layer; add a round-trip test
  (spec → style → spec is the same) in the core if `TextStyle` moves there.
- **Where:** `textSpec(for:)` `Editor.swift:2289-2306` (style → spec) and `editText(layerAt:)` `:2361-2373`
  (spec → style). `TextStyle` is at `:377`.
- **What:** A new text setting (say, letter spacing) has to be added in both, in opposite directions. Missing it in
  `editText` would quietly drop the setting the first time a text layer is reopened.
- **Suggested change:** `TextStyle.init(spec:)` and `TextSpec.init(style:origin:wrapWidth:minimumHeight:color:background:)`
  side by side. `TextStyle` has no AppKit in it, so it can move to the core next to `TextSpec` and get the round-trip
  test there.

## 7. Redact Brush and Remove/Spot Heal strokes are twins
- **Worth:** Medium
- **Kind:** Copies
- **Size:** Small
- **Risk:** Low. `RedactAndRetouchTests` and `SmoothingAppTests` cover both. Keep the overlay alphas as they are (D).
- **Where:** `redactStroke` and `retouchStroke` tuples (`:538`, `:568`), `beginRedactStroke`/`beginRetouchStroke`
  (`:1800`, `:1999`), `continueRedactStroke`/`continueRetouchStroke` (`:1810`, `:2011`, identical apart from the
  property), the catch-up at the start of each `end` (`:1823`, `:2024`), `areaStrokePicture` (`:1835`); in the view,
  the `.redact` and `.retouch` drag cases (`CanvasView.swift:624-631`, `:692-697`, `:740-743`).
- **What:** Two copies of "paint an area with a smoothed path, show it see-through, act on it at the end". A change
  to smoothing or Shift-constrain must be made twice.
- **Suggested change:** one `private var areaStroke: (area: RedactBrushArea, path: StrokePath, purpose: AreaPurpose)?`
  with `enum AreaPurpose { case redact(secondary: Bool), retouch(RetouchKind) }`, one begin/continue, and an `end` that
  switches on the purpose into today's two bodies.

## 8. The command wrappers: one "pixel step" helper, and the five wrappers lined up
- **Worth:** Medium
- **Kind:** Copies
- **Size:** Small
- **Risk:** Low if each wrapper keeps exactly what it does now. `EditorCommandTests`, `ChosenLayersTests`,
  `LayerMenuTests`, `LockTransparencyAppTests`, `PendingObjectTests`, `StepBadgeTests` cover them.
- **Where:**
  - One-shot pixel steps written out each time (lock check, finish, place floating, `beginEdit`, draw, commit,
    render): `fill` `:1317`, `revertLayer` `:1016`, `commitPendingShape` `:1781-1785`, `commitPendingBadge`
    `:2148-2150`, `commitPendingText` `:2334-2338`, `removeRedEye` `:3424-3430`, `autoContrast` `:4103`,
    `applyAdjustment` `:4123`, `land` `:1975-1978`, the async end of `endRetouchStroke` `:2059-2062`.
  - The wrappers: `performSelectionCommand` `:2610`, `recordingChanges` `:2617`, `chosenLayerSetting` `:4576`,
    `layerSetting` `:4996`, `layerCommand` `:5003`, plus `moveChosenLayers` `:4784`.
- **What:** The wrappers are one pattern with small, unexplained differences: `layerCommand` ends with
  `selectionDidChange()`, `layerSetting` only with `onRender()`; `chosenLayerSetting`, `layerCommand` and
  `moveChosenLayers` bump `layersRevision` again after `recordingChanges` already did (and also when nothing changed).
  The pixel-step sequence has about ten copies with no wrapper at all.
- **Suggested change:** `private func pixelStep(_ name: String, keepingOutline: Bool = true, _ draw: (Layer, Edit) ->
  Void) -> Bool`, which does the lock check, finish, place, begin, draw, commit, render, and says whether a step was
  made (Red-Eye's "No red-eye found" needs that). For the wrappers, a doc comment table of what each does on top of
  `recordingChanges`, and drop the second `layersRevision += 1` only where it's provably redundant.

## 9. Tool sizes: one table instead of four switches
- **Worth:** Medium
- **Kind:** Copies
- **Size:** Small
- **Risk:** Low. `PanelTests` and `KeyForwardingTests` (`[` and `]`) cover sizes; add one test that `[`/`]` never
  leaves `toolSizeRange` for each tool.
- **Where:** `toolSize` get and set (`Editor.swift:1078-1104`), `toolSizeRange` (`:1107`), `toolSizePresets`
  (`:1117`), `adjustToolSize` (`:1128-1144`).
- **What:** Each tool's size property, range, presets and `[`/`]` step are spread over four switches.
  `adjustToolSize` writes the ranges again by hand (`1...100`, `16...128`, `1...300`, `1...50`) instead of using
  `toolSizeRange`. They agree today; a range change in one place won't reach the other.
- **Suggested change:** a `ToolSizeSpec` per tool (`keyPath` into the Editor, range, presets, step), from one switch.
  All four members read it; `adjustToolSize` clamps with `toolSizeRange`.

## 10. Redaction patterns are a settings store living inside each Editor
- **Worth:** Medium
- **Kind:** Already there
- **Size:** Small
- **Risk:** Low. `AutoRedactEditorTests` reads the patterns. The store must still never be written by a test (CLAUDE.md).
- **Where:** `redactionPatterns` (`Editor.swift:623-628`), `loadRedactionPatterns`/`saveRedactionPatterns`
  (`:5414-5432`); edited from `AutoRedactSheet.swift:32`. The app's other stores are shared objects:
  `FilterStore.shared`, `PhotoSettingsStore.shared` (session AC covers those).
- **What:** Every document loads its own copy from `UserDefaults` when it opens, and writes the whole list on each
  change. With two windows open, a pattern added in one isn't seen in the other, and whichever window changes its list
  last overwrites the other's. That's today's behavior, so Leah should know it before a refactor makes them one list.
  The merge of saved patterns with the built-ins (`:5417-5426`) is pure logic with no test.
- **Suggested change:** a `RedactionPatternStore.shared` shaped like the other stores, which the Editor reads. Move the
  built-in merge to the core (`RedactionPattern.merged(saved:)`) with a unit test.

## 11. Geometry and layer logic in the Editor that belongs in the core
- **Worth:** Medium
- **Kind:** Hard to change (untestable headless today)
- **Size:** Medium
- **Risk:** Moving pure functions changes nothing if each keeps its signature. The core gets exact-value tests;
  `ShapeAndTextEditingTests`, `SelectionRangeBarTests`, `LayerFollowUpTests` and `LayerGroupAppTests` (isolation)
  keep the app side honest.
- **Where:**
  - Rotated-box resize: `resizeBox` `Editor.swift:1735-1752`; rotate with 15° snap `:1717-1725`; a curve's starting
    thirds `:1693-1699`; hit test on a line `:1607-1611`. They belong on `PendingShape`/`ShapeSpec`, which already have
    `rotated`, `unrotated` and `constrained` in the core.
  - `guideAcross` (Liang–Barsky clip) `:2928-2947`: belongs with `GraduatedSelection`.
  - `pendingTextHandles` `:2201-2217` works out the eight handle positions by hand on a `Double` box: the same thing
    `SelectionHandle.point(on:)` (`Packages/ColorbeeCore/Sources/ColorbeeCore/SelectionHandle.swift:6`) does for an
    `IntRect`.
  - Option-click isolation: the visibility rules in `toggleIsolation` `:4816-4841` (what "alone" means with groups,
    when to restore, when to show all) are pure layer logic, and belong in `LayerActions` next to `setVisibility`.
- **What:** The architecture asks for algorithms in the core, unit-tested headless. These are pure maths or layer
  rules in the app target, reachable only through app tests.
- **Suggested change:** move each as a function or method on its core type, with tests; the Editor calls it.
  `SelectionHandle.point(on:)` gets an overload for a box of `Double`s.

## 12. Two parallel drag state machines, in the view and in the Editor
- **Worth:** Medium
- **Kind:** Hard to change
- **Size:** Large
- **Risk:** It touches every tool. Do it after finding 2, one tool at a time. Covered by `StrokeTests`,
  `SelectionDragTests`, `ShapeAndTextEditingTests`, `StepBadgeTests`, `RedactAndRetouchTests`, `PictureDragTests`,
  `PendingObjectTests`, `CanvasToolAndPageTests`, `SmoothingAppTests`, and the monkey test.
- **Where:** `CanvasView.swift:564-782` (`beginDrag`, `continueDrag`, `endDrag`: three switches over its own `drag`
  enum). In the Editor, eleven optional drag states: `redactStroke` `:538`, `retouchBrush` `:565`, `retouchStroke`
  `:568`, `badgeDrag` `:578`, `activeStroke` `:643`, `selectionDrag` `:644`, `shapeDrag` `:667`, `gradientDrag`
  `:668`, `textBoxDrag` `:2234`, `toolDrag` `:3217`, `pictureDrag` `:3845`. Two hand-kept lists of them:
  `isEditInProgress` `:1982-1986` and `finishInteractions` `:1159-1173`.
- **What:** Adding a tool means a case in three view switches, a new optional in the Editor, and remembering both
  lists. Missing `isEditInProgress` is what copy B's `findSubject` row shows. `finishInteractions` also has an order
  that matters but isn't written down (Match Tone lands first; the effect is cancelled after strokes end; layer
  settings last).
- **Suggested change:** an Editor-owned `private var drag: EditorDrag?` enum, one case per kind, replacing the eleven
  optionals (only one drag runs at a time). `isEditInProgress` becomes `drag != nil || fillProgress != nil ||
  pending objects`, and `finishInteractions` ends `drag` with one switch. Later, the view's three switches can shrink to
  forwarding point, pressure and modifiers to `editor.drag(began:)`, `moved:`, `ended:`. Until then, a comment on
  `finishInteractions` gives the order and why.

## 13. Small helpers written out many times
- **Worth:** Low
- **Kind:** Copies
- **Size:** Small
- **Risk:** None beyond typos; `make test` catches them.
- **Where:**
  - `IntPoint(x: Int(point.x.rounded(.down)), y: Int(point.y.rounded(.down)))`, the pixel under a point: 12 times in
    `Editor.swift` (`:1321`, `:1347`, `:1372`, `:1459`, `:1599`, `:2391`, `:2414`, `:2466`, `:2838`, `:3524`, `:3857`,
    `:3929`) and once in `CanvasView.swift:494`.
  - The slider value with its default: `:247`, `:2777`, `:2788`, `:3561`, `:3583` (see C).
  - The 5 × 5 sample box: `:2840` and `:3821` (and `sample(around:size:)` at `:1340` already does this).
- **What:** One rule ("which pixel a point is in") written thirteen times; one fallback written two ways.
- **Suggested change:** `Point2D.pixel` (or `IntPoint(containing:)`) in core `Geometry.swift`; `EffectKind.value(_
  index:, in values:)` used by all five; reuse `sample(around:size:)` for the 5 × 5 boxes.

## 14. Dead code, and a safety comment above the wrong type
- **Worth:** Low
- **Kind:** Dead code
- **Size:** Small
- **Risk:** None.
- **Where:**
  - `Tool.isStrokeTool` (`Editor.swift:47-52`) and `isDraggingOnPicture` (`:3909`): nothing reads them.
  - The comment that explains why `UnsafeTransfer` is safe ("only reads it while nothing else writes to it") sits
    above `ClipboardCleanup` (`:5602-5604`) instead of above `UnsafeTransfer` (`:5610`). On an `@unchecked Sendable`
    type, that comment is the contract.
  - Stacked doc comments where a newer one was added above an older one rather than replacing it: `:748-749`,
    `:2992-2993`, `:4177-4178`, `:4266-4268`, `:4750-4751`, `:4872-4873`, `:4879-4880`, `:5562-5563`.
- **Suggested change:** delete the two members; move the comment to `UnsafeTransfer`; keep the newer of each pair of
  comments.
