# Review AE: the core's model, history and files
Reviewed at commit: 08094b72da6bb45f122b342dd285728849008e7b
Checked:
- `History.swift`, `History+Snapshots.swift`, `HistorySnapshot.swift` (Edit, HistoryEntry, record, undo on layer, spilling, SpillStore)
- `Canvas.swift`, `Canvas+Groups.swift`, `CanvasAnchor.swift`, `Layer.swift`, `LayerPixels.swift`, `LayerAlign.swift`
- `LayerActions.swift` and `+Groups`, `+Masks`, `+Several`, `+Text`
- `SelectionActions.swift`, `FloatingSelection.swift`, `ImageActions.swift`, `Orientation.swift`, `Geometry.swift`, `Trim.swift`
- `Page.swift`, `PageStack.swift`, `PDFPages.swift`, `PDFWriter.swift`, `ProjectFile.swift`, `ImageCodec.swift`, `ExportPreset.swift`, `ExportColor.swift`, `DocumentInfo.swift`, `CameraDetails.swift`
- `AutoRedact.swift`, `AutoRedact+Apply.swift`, `FaceFinder.swift`, `RectangleFinder.swift`, `TextReader.swift`
- `TextLayer.swift`, `TextRenderer.swift`, `Shapes.swift` (render path), `StepBadge.swift`, `Decorations.swift` (entry point), `Shortcuts.swift`
- `Effect+Codable.swift` and every hand-written `init(from:)`: `ColorLook`, `ColorGrading`, `ColorMixer`, `Curves`, `Levels`, `PhotoDetail`, `PhotoEffects`, `ToneCurve`, `PhotoAdjustments` (two), `PointColors` (two), `PhotoFilter`, `ProjectFile.AdjustmentEntry`, `KeyShortcut`
- Test files that guard these areas (names in each finding's Risk line)

Answers to the plan's four questions, in short:
- **Edit pattern:** one `Edit` type, but the kind of step is decided by which `will…` call comes first and is policed by four
  runtime preconditions; `HistoryEntry` holds that kind as four optionals that many places test by hand. Finding 3.
- **Lenient decoders:** three different strictness styles and two copies of each small helper. Finding 8, plus a
  difference under "Copies that already differ".
- **Keeping layers valid:** groups are kept together in one place (`LayerActions.change` → `keepGroupsTogether`). Masks
  can't drift because they're stored on their layer. Clipping is worked out each time (`clipBaseIndex`), not stored, so
  it can't go stale. The gap is the handful of layer steps that skip `change`. Finding 7.
- **ProjectFile and the save snapshot:** the file header is written three times and read twice; blob slicing is written
  three times. Finding 4. The bigger "must agree" risk is the layer settings list. Finding 1.

## Copies that already differ

**A. A text layer moved by Align keeps its words where a geometry change would turn it into pixels.**
`Canvas.fitText` (`TextLayer.swift:90-113`) and `LayerAlign.move` (`LayerAlign.swift:138-146`) both move a text layer's
words with its pixels and draw them again. `fitText` also checks that the moved text box is still wholly on the canvas,
and if it isn't, turns the layer into plain pixels. Its comment gives the reason: words cut off at the edge "would stay
in the layer and come back later, out of Auto-Redact's sight" (Leah, 2026-10-31; review Y, finding 6). `LayerAlign.move`
has no such check: it refuses a move only when the layer's *visible pixels* would leave the canvas. So a text layer whose
box reaches past the edge (a wrap width or minimum height wider than the ink, or words already cut off) stays editable
text after Align. Leah decides whether Align should follow the same rule; if so, Align could call `fitText(.moved(…))`
for each moved layer, and the copy goes away (see finding 6).

**B. The History panel's pictures leave out a floating selection; everything else shows it.**
`Canvas.thumbnail` (`Canvas.swift:246-321`) works out each pixel by its own copy of the compositing rules and never looks
at `selection`. `flattened`, `composite`, `patch` and `layerBuffersAsSaved` all draw a floating piece into its layer
(`Canvas.swift:431-436`, `573-576`, `587-598`). The History panel's thumbnail is made right after each step
(`History.commit`, `History.swift:388-390`; `Editor.swift:740`), so after Paste, Move Selection or Duplicate Selection
its picture shows the image without the piece that's on screen. Page thumbnails aren't affected: a page is parked only
after its floating piece is placed. Finding 2 covers the wider copy.

**C. Damaged parts of an Adjust Photo layer are treated two ways.**
`PhotoEdit.init(from:)` (`PhotoAdjustments.swift:370-382`) reads the mixer, grading, point colors, detail, effects and
tone curve with `try?`: a damaged one is dropped and the rest of the layer survives. But a damaged `filter`,
`adjustments` or `filterIntensity` throws, and `ProjectFile.AdjustmentEntry` (`ProjectFile.swift:152-158`) then turns
the *whole* adjustment into nil, so the layer opens as an empty pixel layer and every other setting is lost. Inside
`PhotoAdjustments` itself one damaged name/value pair throws (`PhotoAdjustments.swift:332-336`), while `PointColors`
skips a damaged swatch and keeps the rest (`PointColors.swift:169-181`). These may be deliberate (the filter and
sliders are the core of the edit), but they're one rule written differently in neighboring lines. Leah decides.

## 1. Every layer setting is listed by hand in about nine places that must all agree
- **Worth:** High
- **Kind:** Copies
- **Size:** Medium
- **Risk:** Undo, Undo on Active Layer, snapshots, saving and duplicating all lean on these lists. A field dropped in
  one place loses that setting silently, with no crash. No test today sets *every* setting to a non-default value and
  checks that each path brings it back. Write that test first: one layer with every setting changed (name from words,
  locked transparency, clipped, group, Pass Through off, mask off, text, adjustment, blend mode, opacity, hidden), then
  check it survives (a) a layer step and its undo, (b) Undo on Active Layer, (c) a snapshot and Go to Snapshot,
  (d) a project save and reopen, (e) `Layer.copy`. Existing guards: `LayerTests`, `HistorySnapshotTests`,
  `ProjectFileTests`, `LayerGroupTests`, `LayerMaskTests`, `TextLayerTests`, `HistoryTests.randomEditsUndoBackToTheOriginal`.
- **Where:**
  - `Layer.swift:14-55` (the stored properties), `Layer.swift:92-99` (`copy`), `Layer.swift:109-120` (`takeSettings`)
  - `Canvas.swift:633-687`: `LayerStackState.Record` fields, `init(_:)`, the memberwise init, and `matches`
  - `Canvas.swift:337-356` (`Canvas.restore`)
  - `History.swift:585-603` (`undoOnLayer` copies a record back field by field)
  - `HistorySnapshot.swift:19-46` (`StoredLayer`), `History+Snapshots.swift:31-37` (taking one) and `86-96` (going back)
  - `ProjectFile.swift:174-185` (writing) and `466-481` (`layer(from:)`, reading)
  - Partial lists: `History.swift:220-242` (`TextChange`), `Canvas.swift:413-417` (a group's stand-in)
- **What:** Adding one layer setting (say a fill opacity) means remembering roughly fifteen edits across six files. A
  missed one compiles and loses the setting on undo or snapshot. There's also a hidden order rule in every list:
  `Layer.name`'s `didSet` clears `nameFromWords`, so each copy must set `name` before `nameFromWords`
  (`Canvas.swift:340` then `353`; `History.swift:588` then `598`; `History.swift:238-239`;
  `LayerActions+Several.swift:28-29`). The lists already differ on purpose in one place: `undoOnLayer` leaves `groupID`
  alone because `candidate` has already checked it's unchanged (`History.swift:637`). That's correct today, but nothing
  says so where the fields are copied.
- **Suggested change:** Add `struct LayerSettings: Equatable` holding every setting except id, kind, buffer and mask
  (name, nameFromWords, visible, opacity, blend mode, both locks, adjustment, clipped, group, Pass Through,
  maskEnabled, text). Give `Layer` a computed `settings { get set }` whose setter assigns `name` before `nameFromWords`,
  so the order rule lives in one place. Then `Record` becomes `(layer, settings, buffer, mask)`, `matches` becomes
  `settings == other.settings && buffer === other.buffer && mask === other.mask`, `restore` and `undoOnLayer` each
  become one assignment, `takeSettings` becomes `settings` with the name kept, and `StoredLayer` holds a `LayerSettings`.
  `ProjectFile.LayerEntry` stays spelled out (it's the file format) but reads and writes one `LayerSettings`. The
  layer's stored properties can stay as they are, so no caller changes.

## 2. The History thumbnail redoes the compositing rules pixel by pixel, and has already drifted once
- **Worth:** High
- **Kind:** Copies
- **Size:** Medium
- **Risk:** Thumbnails must stay exactly as they look now (unless Leah wants difference B fixed). The shared per-pixel
  helpers below would be used by the export's row loops too, so a slip would change exports. Guards: `CompositingTests`,
  `ClippedAdjustmentTests`, `AdjustmentTests`, `LayerGroupTests`, `ColorAsShownTests`. There's no thumbnail test that
  compares against `flattened()` on a stack with groups, clipped layers, masks and a blended adjustment. Add one first,
  using a canvas small enough that the thumbnail is full size, so the two should match pixel for pixel apart from the
  documented skips (blur, sharpen, detail, vignette).
- **Where:** `Canvas.swift:246-321` (`thumbnail`). The rules it copies: `AdjustmentCompositing.swift:14-34`
  (`Compositing.mixed`), `Canvas.swift:218-240` (`clipped`), `Canvas.swift:396-428` (groups in `composite`).
- **What:** `thumbnail` has its own nested `shade` function that re-derives Pass Through groups, isolated groups,
  clipped pixel layers, clipped adjustments, adjustment blend modes and masks. Its adjustment branch
  (`Canvas.swift:286-293`) is a line-for-line copy of the inside of `Compositing.mixed`, and the comment says it was
  copied after the two disagreed ("the monkey test, 2026-10-31"). The clipped-adjustment branch (`303-310`) blends in
  straight color and rounds to bytes before fading, while the export path goes through `Compositing.adjust` → `mixed`
  in premultiplied floats, so the two can disagree by a step of rounding. It also ignores floating selections
  (difference B). Every future compositing fix has to be made here too, and nobody will think to.
- **Suggested change:** Keep the cheap per-pixel thumbnail, but give `Compositing` the per-pixel steps as small
  `@inline(__always)` functions (`mixedPixel(backdrop:adjusted:fade:mode:)`, the clipped-adjustment step) and build
  both `mixed`'s row loop and `thumbnail`'s `shade` on them. Move the compositing half of `Canvas.swift` (`clipped`,
  `composite`, `compositePixels`, `patch`, `flattened`, `thumbnail`: about 400 of its 708 lines) into
  `Canvas+Compositing.swift`, so the model and the drawing rules are in different files.

## 3. A history step's kind is four optionals checked by hand in many places
- **Worth:** Medium
- **Kind:** Hard to change
- **Size:** Medium
- **Risk:** This is the heart of undo. Guards: `HistoryTests` (including `randomEditsUndoBackToTheOriginal`),
  `GeometrySpillTests`, `ReviewATests`, `HistorySnapshotTests`, `LayerTests` (Undo on Active Layer), `SoakTests`,
  `LockTransparencyTests`. Run `make monkey MINUTES=30` after it.
- **Where:**
  - `History.swift:244-272` (`HistoryEntry`: `changes`, `geometry`, `transform`, `layers`, all optional or empty)
  - `History.swift:51-53` and the preconditions at `75`, `144`, `150`, `159` (`Edit`'s kind is whichever `will…` came first)
  - `History.swift:409-460` (`record`: four branches, each repeating `discardRedo()`, `HistoryEntry(…)`,
    `undoStack.append`, `revision += 1` and, all but one, `spillToBudget`)
  - The hand-written kind tests: `History.swift:443-444` (merge), `504-530` (`swapPixels`), `573-575` (`geometrySteps`),
    `628-629` (`candidate`), `661-663` (spilling)
- **What:** Exactly one of four payloads is set in each entry (plus `texts`, which can go along with pixels or
  geometry), but the type doesn't say so. Each check spells out its own list, for example
  `previous.layers == nil, previous.geometry == nil, previous.transform == nil` or
  `entry.geometry != nil || entry.transform != nil || entry.replacesPicture`. A fifth kind of step, or a change to which
  kinds count as "whole picture", has to find every such line. The four near-copies in `record` mean a new piece of
  bookkeeping (as `tileBytes` once was) must be added four times; the transform branch already skips
  `spillToBudget` (harmless today, since a transform holds no pixels).
- **Suggested change:** Give `HistoryEntry` one `enum Payload { case tiles([TileChange]), layers(LayerStackState),
  geometry(GeometryChange), transform(Orientation) }` with small computed helpers (`isWholePicture`, `canTakeTiles`),
  so each check becomes an exhaustive `switch` or a named property. `Edit` can keep its `will…` calls and preconditions.
  Fold the four tails of `record` into one `push(_ entry:)` that does redo, append, revision and budget.

## 4. The project file's header and blob handling are written several times
- **Worth:** Medium
- **Kind:** Copies
- **Size:** Small
- **Risk:** File format. Every project ever saved must still open, and new saves must open in beta 7. Guards:
  `ProjectFileTests`, `DamagedFileTests`, `FileFuzzTests`, `LayerPixelsTests`, `PageTests`, `ReviewHIJTests`.
- **Where:**
  - Header writes (magic, little-endian length, JSON, blobs): `ProjectFile.swift:224-230` (`encode`), `322-328`
    (`encode(stored:)`), `352-358` (`settingResolution`)
  - Header reads with the same bounds checks: `ProjectFile.swift:253-261` (`manifestAndBlobs`), `368-374` (`storedPages`)
  - Blob range check plus `LayerPixels.Stored`: `ProjectFile.swift:244-246` (`restore`), `409-414` and `420-424` (`decode`)
  - Blob append plus `pieceRows`/`pieces`: `ProjectFile.swift:190-195` and `202-207`
- **What:** `settingResolution` rewrites a project that `encode` wrote, so the two must produce the same layout. The
  overflow-safe length and range checks (review J, findings 19 and 20; review K, finding 9) live in some copies and
  must be remembered in any new one. `restore` checks the range but `decode`'s two copies do it slightly differently
  (`blobs[(blobs.startIndex + range.lowerBound)..<…]` against a `start`/`end` pair), so a reader has to check three
  places to see they agree.
- **Suggested change:** `private static func framed(_ magic: Data, json: Data, body: Data) -> Data` and
  `private static func unframe(_ data: Data, magic: Data) throws -> (json: Data, body: Data)`, used by all five sites.
  `private static func storedPixels(_ entry: LayerEntry, in blobs: Data, into buffer: PixelBuffer) throws -> LayerPixels.Stored?`
  for the three slicing sites, and `appendPixels(_:to:&entry, &blobs)` for the two append sites.

## 5. Compressing a buffer in bands to the scratch file is written five times
- **Worth:** Medium
- **Kind:** Copies
- **Size:** Small
- **Risk:** Spilled undo steps and snapshots coming back wrong. Guards: `GeometrySpillTests`, `ReviewATests`
  (spill-file growth), `HistorySnapshotTests`, `HistoryTests.stepsOverTheMemoryBudgetSpillToDiskAndStillUndo`,
  `SoakTests`, `make perf`.
- **Where:**
  - Writing: `History.swift:754-766` (`evict`), `History.swift:718-728` (`evictInBackground`, one core),
    `History+Snapshots.swift:19-28` (`takeSnapshot`)
  - Reading back into a buffer: `History.swift:774-803` (`restore`), `History+Snapshots.swift:54-70` (`goToSnapshot`)
  - Making the store lazily: `History.swift:703`, `738`, `806`; `History+Snapshots.swift:13`
- **What:** Each copy computes `GeometryChange.bands(of:)`, compresses every band with `SpillStore.compress`, appends
  them in order, and fails if any is nil. Each reader checks the band count, reads every location, decompresses on all
  cores and writes rows back. A change to the band size, or a fix to the failure handling, has to be made in each.
  `GeometryChange.bands` is also an odd home for a SpillStore detail.
- **Suggested change:** Move the band rule into `SpillStore`: `compressBands(of: PixelBuffer, parallel: Bool) -> [Data]?`,
  `appendAll(_ data: [Data]) throws -> [Location]`, and `readBands(_ locations: [Location], into buffer: PixelBuffer) -> Bool`
  (with a variant that returns the band hashes `restore` needs for `diskCopies`). Keep `LayerPixels` (the project
  format) separate: its joined-stream layout is deliberate.

## 6. The three canvas-geometry commands share one skeleton, written three times
- **Worth:** Medium
- **Kind:** Copies
- **Size:** Small
- **Risk:** Guards: `ImageActionsTests`, `GeometrySpillTests`, `ResizeSkewTests`, `CanvasPropertiesTests`,
  `CanvasAnchorTests`, `TextLayerTests` (text following a crop or resize).
- **Where:** `ImageActions.swift:6-24` (crop), `40-69` (resize and skew), `74-102` (canvas size). A fourth hand-made
  pixel shift: `LayerAlign.swift:123-128`.
- **What:** Each does: place the floating piece, begin an edit, `willChangeGeometry`, build a new buffer for every layer
  *and mask* (`allLayers`), `replaceContents`, `fitText`, set the selection, commit. The "give layers with no pixels an
  empty buffer" rule is written three ways (`holdsNoPixels`, `!isPixelLayer`, `holdsNoPixels && fill == .clear`). The
  next geometry command (or a fix like the masks-in-`allLayers` change) has to repeat all of it.
- **Suggested change:** `private static func changeGeometry(_ name:, to size:, fit: TextFit?, canvas:, history:,
  context:, selection: (SelectionState) -> SelectionState, buffer: (Layer) -> PixelBuffer) -> Bool`, with each command
  supplying only its buffer and selection rules. If Leah answers difference A, `LayerAlign.move` could use `fitText`
  too, with a small `PixelBuffer.shifted(by:)` shared with `resizeCanvas`'s copy.

## 7. Some layer steps skip `LayerActions.change`, the one place that keeps groups whole
- **Worth:** Medium
- **Kind:** Hard to change
- **Size:** Small
- **Risk:** Placing the floating piece must stay exactly where it is today (it's behavior), so the shared path needs a
  switch for it. Guards: `LayerTests`, `LayerGroupTests`, `SeveralLayerActionTests`, `LayerMaskTests`,
  `CanvasPropertiesTests`.
- **Where:** `LayerActions.swift:338-345` (`change`: place, begin, `willChangeLayers`, body, `keepGroupsTogether`,
  commit). Steps that build their own edit instead: `LayerActions.swift:261-268` (`setVisibility`), `321-327`
  (`update(layerAt:)`), `LayerActions+Several.swift:180-187` (`update(layersWithIDs:)`), `ImageActions.swift:107-113`
  (`setTransparentBackground`), and `LayerActions+Masks.swift:113-126` (`invertMask`, a pixel step that places the
  floating piece by hand). `LayerActions+Groups.swift:25` calls `keepGroupsTogether` inside a `change` body, which then
  calls it again.
- **What:** The two `update` functions take any closure from the app, so the Editor can change `groupID` or
  `clipsToLayerBelow` through them without `keepGroupsTogether` ever running. That's safe today only because of what
  the current callers happen to change. The three near-identical "begin, willChangeLayers, body, commit" functions
  (`update`, `update(layersWithIDs:)`, `setVisibility`) are one function written three times.
- **Suggested change:** Give `change` a `placesFloating: Bool = true` parameter. Make `update(layerAt:)` and
  `setVisibility` thin calls to `update(layersWithIDs:)`, and have that go through `change(placesFloating: false)`, so
  every layer step ends in `keepGroupsTogether`. Drop the inner call in `group`.

## 8. Lenient decoding is hand-rolled in each type, with two exact twin helpers
- **Worth:** Medium
- **Kind:** Copies
- **Size:** Small
- **Risk:** Old projects and `.colorbeefilter` files must read exactly as before. Guards: `PhotoCompatibilityTests`,
  `DamagedFileTests`, `FileFuzzTests`, `PhotoDetailTests`, `PhotoEffectsTests`, `ColorGradingTests`, `ColorMixerTests`,
  `ToneCurveTests`, `PointColorsTests`, `AdjustPhotoTests`.
- **Where:**
  - The same "an effect, or nil if this version doesn't know it" wrapper twice: `ProjectFile.swift:152-158`
    (`AdjustmentEntry`) and `PhotoFilter.swift:65-71` (`LenientStep`)
  - The same `clamp(value, range, start)` local function twice: `PhotoDetail.swift:30-32`, `PhotoEffects.swift:26-28`
  - The same `read(_ key, into:)` local function twice: `PhotoDetail.swift:54-56`, `PhotoEffects.swift:49-51`
  - "Finite, clamped, or a default" written inline again: `ColorGrading.swift:141-144`, `Levels.swift:26-29`,
    `PhotoAdjustments.swift:375`, `ColorMixer.swift:34` and `43`, `ToneCurve.swift:96-97`
  - `try? container.decodeIfPresent(…) ?? default`: `ColorGrading.swift:137-143`, `ColorMixer.swift:174-177`,
    `PointColors.swift:148`, `PhotoAdjustments.swift:376-381`
- **What:** Each type decides on its own how a damaged value is treated (throw, skip, default, clamp), which is how
  difference C came about. A fix to the rule (for example, how NaN is handled) has to be found in about ten places.
- **Suggested change:** One `LenientEffect` type in `Effect+Codable.swift` for both wrappers. A small
  `KeyedDecodingContainer` extension, `lenient(_ type:, forKey:, default:)`, and a
  `Double.clamped(to:orIfNotFinite:)`, used by every decoder above. Each type's choice of strict or lenient fields stays
  as it is; it just becomes visible at a glance.

## 9. "Make the merged layer plain" is written four times
- **Worth:** Medium
- **Kind:** Copies
- **Size:** Small
- **Risk:** Guards: `LayerTests` (Merge Down, Merge Visible, Flatten), `AdjustmentTests` / `ClippedAdjustmentTests`
  (Merge Adjustment), `SeveralLayerActionTests` (Merge Layers), `StampVisibleTests`, `LayerMaskTests`.
- **Where:** `LayerActions.swift:36-43` (Merge Adjustment), `229-236` (Merge Visible), `286-294` (Flatten),
  `LayerActions+Several.swift:26-35` (Merge Layers)
- **What:** Each sets text nil, opacity 1, Normal, no adjustment, not clipped, no mask, and usually no group. The
  differences are deliberate (Flatten and Merge Layers also set visible; Merge Layers keeps its group and takes a new
  name), but nothing says which ones are deliberate. A new layer setting (finding 1) would have to be reset in four
  places. None of them reset Lock Transparent Pixels, Pass Through or `maskEnabled`, and it isn't obvious from the code
  whether that's intended.
- **Suggested change:** `Layer.becomeMergeResult(buffer:, keepsGroup: Bool)` (or a `LayerSettings.plain` value from
  finding 1), called by all four, with Merge Layers then setting its name.

## 10. Drawing into a layer-sized patch with Core Graphics is set up three times
- **Worth:** Low
- **Kind:** Copies
- **Size:** Small
- **Risk:** Exact pixels of text, shapes and badges. Guards: `TextRendererTests`, `ShapeTests`, `StepBadgeTests`.
- **Where:** `TextRenderer.swift:62-67`, `88-89`, `182-184`; `StepBadge.swift:91-101`, `113-114`;
  `Shapes.swift:358-366`, `384-385`, `390-401`
- **What:** Each makes a premultiplied BGRA context on a `PixelBuffer`, flips it to top-left coordinates (StepBadge
  copies `Shapes.imageContext` line for line), draws, then unpremultiplies with vImage. `cgColor(Pixel)` is written
  three times. The straight-alpha rule (CLAUDE.md: premultiply only for display) depends on every copy remembering
  the unpremultiply.
- **Suggested change:** `PixelBuffer.drawing(area:, colorSpace:, flipped: Bool, _ draw: (CGContext) -> Void) -> PixelBuffer?`
  that owns the context, the flip and the unpremultiply, plus `Pixel.cgColor(in:)`. TextRenderer passes
  `flipped: false`, since it maps Core Text's y-up space itself.

## 11. Small copies in the on-device readers (Vision) and redaction
- **Worth:** Low
- **Kind:** Copies
- **Size:** Small
- **Risk:** Copy Text and Auto-Redact results. Guards: `AutoRedactTests`, `TextReaderTests`, `FaceFinderTests`,
  `RectangleFinderTests`.
- **Where:**
  - "Draw over white before reading" twice: `TextReader.swift:28-40` and `AutoRedact.swift:181-193` (identical)
  - Vision's bottom-left box turned into top-left pixels four times: `FaceFinder.swift:20`, `RectangleFinder.swift:22`,
    `AutoRedact.swift:242` and `283`
  - Gray copy of an image twice: `AutoRedact.swift:350-360`, `RectangleFinder.swift:45-57`
  - "Does this layer have pixels here" twice: `AutoRedact+Apply.swift:14-20` and `80-86`
- **What:** The over-white rule exists because dark text on a transparent background was misread (review E,
  finding 5). A fix to it, such as a color space choice, has to be made in both readers.
- **Suggested change:** A small internal `VisionImage` helper with `opaque(_:)`, `topLeftRect(_ normalized:, in tile:)`
  and `gray(_:, maxSide:)`, and one `hasPixels(_ layer:, in rect:, mask:)` in `AutoRedact+Apply`.

## 12. Selection near-copies: reshaping a floating piece, and clipping a marquee to the canvas
- **Worth:** Low
- **Kind:** Copies
- **Size:** Small
- **Risk:** Guards: `SelectionActionsTests`, `ResizeSkewTests`, `SelectionHandleTests`, `LockTransparencyTests`.
- **Where:**
  - `SelectionActions.swift:155-170` (`transformSelection`) and `175-190` (`resizeAndSkewSelection`): lift, bake the
    stretch, transform pixels and mask, center on the old box, rebuild the `FloatingSelection`, commit
  - The "clip a mask to the canvas" expression three times: `SelectionActions.swift:62`, `148`; `ImageActions.swift:99`
  - `FloatingSelection.swift:83`, `96`, `113`: the same "rendered pixels at their destination, clipped to the layer"
    setup in `stamp`, `placedCopy` and `placedPatch`. `placedCopy`'s unlocked branch (`100-103`) repeats
    `Compositing.draw` (`Compositing.swift:26-39`) without the edit.
- **What:** Small, but the floating-piece rules ("source pixels never change", "a locked layer uses `placedOnLocked`")
  are each spread over two or three copies.
- **Suggested change:** `private static func reshapeFloating(named:, …, _ change: (PixelBuffer, SelectionMask) -> (PixelBuffer, SelectionMask))`;
  `SelectionMask.clipped(to: IntRect)`; and a private `FloatingSelection.placement(on bounds:) -> (pixels, origin, area)`
  used by its three functions.

## 13. Rules that already have a home, rewritten in place
- **Worth:** Low
- **Kind:** Already there
- **Size:** Small
- **Risk:** Guards: `ImageCodecTests`, `PDFWriterTests`, `TrimTests`, `LayerAlignTests`, `ColorAsShownTests`,
  `CanvasPropertiesTests`, `WarpTests`, `DecorationTests`.
- **Where / What:**
  - "Fits what Colorbee edits" exists as `ImageCodec.fitsEditing` (`ImageCodec.swift:117-119`) but is written out
    again at `ImageActions.swift:76-77`, `ProjectFile.swift:461-462`, `Decorations.swift:82`, `Warp.swift:221` and
    `274`, and in the app at `Sources/Colorbee/CanvasPropertiesSheet.swift:22`. (Keep the sides-before-area order,
    which stops a damaged file overflowing the multiply.)
  - `PDFWriter.encodePage` converts colors with `ImageCodec.decode(ImageCodec.makeCGImage(…), convertingTo:)`
    (`PDFWriter.swift:27`), which is exactly `ImageCodec.converted(_:from:to:)` (`ImageCodec.swift:134-137`).
  - `Trim.keptBounds`'s row-span box search (`Trim.swift:21-31`) is a copy of `PixelBuffer.visibleBounds`
    (`LayerAlign.swift:156-166`) with a different "is this pixel empty" test.
  - `Canvas.patch` copies a sub-rectangle row by row twice (`Canvas.swift:551-553`, `557-560`), which
    `PixelBuffer.pixels(in:)` and `setPixels(_:in:)` already do (as `ImageActions.swift:16` uses them).
  - `LayerActions.nextName` (`LayerActions.swift:330-336`) and `Canvas.nextGroupName` (`Canvas+Groups.swift:98-104`)
    are the same function with a different prefix.
- **Suggested change:** Move `fitsEditing` onto `IntSize` (or `ResizeSkew`) and call it everywhere; use `converted` in
  PDFWriter; give `PixelBuffer` a `bounds(where isContent: (Pixel) -> Bool)` used by both box searches; use
  `pixels(in:)`/`setPixels` in `patch`; one `nextNumberedName(prefix:, in:)`.

## 14. Dead or leftover code
- **Worth:** Low
- **Kind:** Dead code
- **Size:** Small
- **Risk:** None to the app. `ReviewHIJTests.swift:12-14` uses the first item and would move to `append` and `readCompressed`.
- **Where / What:**
  - `SpillStore.write`, `read` and `path` (`History.swift:892`, `899-905`) are used only by one test; history and
    snapshots call `compress`/`append` and `readCompressed`/`decompress` directly.
  - `HistorySnapshot.StoredLayer.maskID` (`HistorySnapshot.swift:37`) is stored but only ever checked for nil
    (`History+Snapshots.swift:75`); going back to a snapshot always makes a mask with a new id. A `hasMask: Bool`
    would say what it means, or the id could be used.
  - The second `keepGroupsTogether` in `group` (`LayerActions+Groups.swift:25`); see finding 7.
- **Suggested change:** Remove or rename as above. No other leftovers from Import from iPhone (stage 11) were found in
  these files.
