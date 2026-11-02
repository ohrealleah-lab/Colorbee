# Review AG: subjects, untangling, Refine Edge, Object mode
Reviewed at commit: 2a8dab72178d97cd156fd31b7151785b949ec1a5
Checked:
- `Subjects.swift` (`8a6ec72`, `d4e5cc0`): `closerSquares`, `closerSubject`, `untangled`, `isCut`, `prefers`, `placed`,
  `labels`, `mask(for:)`, `SubjectActions.select`; zero, one-pixel, small, square, tall and wide sizes; indexes from sizes.
- `RefineEdge.swift` (`e1a15d2`): radius, tiles and margins (no seams), box means at the edges, the guided filter's
  matrix inverse, the "only near the edge" rule, the 4-of-255 snap, sizes 1 × 1 to 16,384 px. There is no Refine Edge
  dialog or live preview: it always runs on the subject mask before it's taken, so "preview against Apply" doesn't
  apply. Esc while it runs takes nothing (`escWhileRefiningTakesNothing`).
- `Editor+Effects.swift` picking: `findSubject`, `pickSubject`, `take`, `mark`, `endPick`, `cancelEffect`, Return in
  `applyEffect` (`Editor+AdjustPhoto.swift`). Late results: every way to change layer, page, mask editing or undo
  (`makeActive`, `changePages`, `undo`, `undoOnActiveLayer`, `layerCommand`) goes through `finishInteractions` →
  `cancelEffect`, which bumps `closerLook`, so a late closer look or Refine Edge is dropped. No bug found there.
- `Editor+Selection.swift` Object mode: `selectObject`, its cache key, `cancelObjectSearch`, Shift / Option / both, a
  floating piece (placed before the key is taken), clicks off the canvas (beep), hidden, locked, text, adjustment and
  group layers, Sample All Layers.
- The blue tint (`8a9aff0`) and outlines: `RenderScene.subjects` is set only in `CanvasView.renderScene`, so it can't
  reach a save, export, Copy, Copy Merged, a History thumbnail, Before/After (it's off while comparing) or a PDF. It
  clears on Cancel, on Return, on a failed search and with the window.
- `Renderer.swift`: the label texture is made once per label map (not per frame), is the scan's size (never over
  16,384, the editing limit), and is dropped on the first frame without subjects. A crop or resize can't happen while
  picking (it ends the pick first).
- Select Subject, Remove Background and Lift Subject: unchanged apart from untangling and Refine Edge, both intended
  (FRD §23, 2026-11-01 and 2026-11-02).
- `LayerActions+Text.swift` (`be9e080`): Rasterize Text's own buffer copy; undo puts back the old buffer, settings (text,
  name, turns) and mask from `LayerStackState`; groups regroup through `changeLayers`. No finding.
- Already known and not repeated: Pick Subject's "still current" check missing Clone Stamp strokes (RANKED-12, D10).

## 1. Untangling never works on a square picture, and hardly ever on a nearly square one
- **Severity:** High (wrong result the user sees)
- **Confidence:** High
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/Subjects.swift:98` (the first square), `:43-49` (stops at the
  first square with a subject under the click), `:55-58`
- **What happens:** on a square picture, clicking a subject that Vision's first look merged with its neighbor (the
  catgirl and the doll) always takes both. The closer look's first square is the whole picture again, so Vision sees
  exactly what it saw the first time and finds the same merged subject. That subject isn't "clearly smaller", so the
  click keeps the merged one, and the smaller squares, which might have separated them, are never tried, because
  `closerSubject` returns at the first square that has any subject under the click. The same happens for Lift Subject,
  Remove Background and the wand's Object mode. On a nearly square picture (4:3 and closer) the first square is most
  of the picture, so untangling rarely helps there either. On a square picture, a click that misses every subject
  also wastes one Vision call repeating the first look before the smaller squares start.
- **How to trigger it:** no picture in `TestImages` has two neighbors Vision merges, so use the picture from your
  untangling test (`test.jpeg` or `nin.png`, from STATUS; I didn't open it):
  1. Open the picture. Choose Image > Canvas Properties…
  2. Make the height the same as the width (keep the width), with the anchor in the middle. Click OK.
  3. Choose Edit > Select Subject. Click the catgirl's vest.
  Expected: just the catgirl, as on the original picture.
  What I think you'll see: the catgirl and the doll together.
- **Why:** `closerSquares` starts at `var side = Double(shorter)`, which for a square picture is the whole picture
  (x = 0, y = 0). `isCut` then counts nothing (no side lies inside the picture), and `prefers` needs
  `closerArea * 10 <= area * 9`, which the very same mask fails, so `untangled` returns the first look's mask. The
  2026-11-01 decision was to *start* at the full shorter side so tall subjects aren't cut off; it didn't decide that
  only the first square counts.
- **Test that would catch it:** for a square size, the squares used for untangling don't include one equal to the
  whole picture (or: `closerSubject` keeps going to the next square when the closer subject isn't preferred and
  isn't cut). A pure test on `closerSquares(around:in:)` with 1,000 × 1,000 is enough to show the first square is the
  whole picture.

## 2. Object mode can reuse a deleted page's subjects, and then crash if the sizes differ
- **Severity:** Medium (rare, but a crash when it happens)
- **Confidence:** Medium (depends on the Mac reusing the memory address of a freed page)
- **Where:** `Sources/Colorbee/Editor+Selection.swift:594-595` (the cache key), `:617`;
  `Packages/ColorbeeCore/Sources/ColorbeeCore/Subjects.swift:223`; `SelectionMask.swift:27` (the precondition)
- **What happens:** the cache key names the page by `ObjectIdentifier(canvas)`, which is just a memory address. Once a
  page is deleted and its undo is gone, a new page's canvas can land at the same address. With Sample All Layers on
  (the key then has no layer ID) and the new page's history at the same revision (a new page starts at 0, like an
  unedited one), an Object click on the new page uses the deleted page's picture and subjects. Same size: it selects
  an outline from the deleted page. Different size: `SubjectActions.select` builds a `SelectionMask` from a mask of the
  wrong length, and the precondition stops the app. Unlike `removeBackground` and `liftToNewLayer`, `select` doesn't
  check the mask's size.
- **How to trigger it:** not reliably by hand, since it needs the address to be reused. Roughly: open a two-page PDF,
  turn on Sample All Layers, press W, choose Object and click on page 2 before editing it; delete page 2, make another
  change, then Page > New Page and Object-click it.
- **Why:** `WandSubjectsKey(canvas: ObjectIdentifier(canvas), layer: wandSamplesAllLayers ? nil : layer.id, revision:
  history.revision)`. Each page's `Page.id` is a UUID and would be a safe name for it.
- **Test that would catch it:** a core test that `SubjectActions.select` with a mask of the wrong size does nothing
  (as `aMaskOfTheWrongSizeIsRefusedWithoutAStep` does for Remove Background); an app test that a cached first look
  isn't used after the shown page changes, even when the key's address and revision match.

## 3. Very large photos hold several full-size copies at once, and Object mode keeps one for the window's life
- **Severity:** Medium (memory; your Mac once crashed from memory in the soak test)
- **Confidence:** Medium (the Vision buffers are estimates)
- **Where:** `Sources/Colorbee/Editor.swift:115` (`wandSubjects`); `Subjects.swift:41-49`, `:98`;
  `RefineEdge.swift:34`; `Renderer.swift:981-993`
- **What happens:** on a 160 MP picture (16,000 × 10,000), one click on a found subject now holds about: the picture's
  copy (640 MB), the first look's masks (160 MB each), the outline labels and their texture (320 MB), the closer look at
  the full shorter side (Vision's float mask of 10,000 × 10,000, about 400 MB, plus 100 MB per subject and a 160 MB
  placed mask), then Refine Edge's RGBA copy (640 MB) and result. That's roughly 2 GB more than the picture itself, at
  the same moment. Before round 12 the closer look was a quarter of that size and only ran on a miss. Separately,
  Object mode's cache keeps a full copy of the picture and every first-look mask until the next Object click or the
  window closes, even after switching back to Color or another tool. History's byte budget doesn't count any of it.
- **How to trigger it:** only if you want to, since it's memory-heavy: open `TestImages/Stage 9 Practice Photo.png`,
  choose Image > Resize and Skew… and resize to 1000%, then Edit > Select Subject and click the moon, with Activity Monitor's Memory tab
  open on Colorbee. Then press W, choose Object, click the moon, choose Color, and watch that the memory doesn't drop.
- **Why:** `vImageCreateCGImageFromBuffer` copies the pixels; `wandSubjects` keeps `(key, scan, image)` with no end;
  `closerSquares` now starts at the full shorter side, and `untangled` runs on every click on a found subject.
- **Test that would catch it:** an app test that leaving Object mode (or changing tool) clears `wandSubjects`; a
  Release performance test of a pick on a large picture with a peak-memory limit.

## 4. Shift-click and Return do whole-picture work on the main thread
- **Severity:** Low (a short freeze on big photos)
- **Confidence:** Medium
- **Where:** `Sources/Colorbee/Editor+Effects.swift:488` and `:495` (`mark`), `:465` (`take`'s combine);
  `Sources/Colorbee/Editor+AdjustPhoto.swift:398` (Return)
- **What happens:** marking a subject a closer look found recomputes every pixel's label (`pick.scan.labels()`) and
  compares the new mask with every existing one (`firstIndex(of:)`) on the main thread; a plain click or Return
  combines the masks (`mask(for:)`) one pixel at a time on the main thread too. On a 48 MP photo that's tens of
  milliseconds; on the largest pictures, a few tenths of a second with the app frozen. `findSubject` already works out
  the labels in the background for this reason.
- **How to trigger it:** open a large photo, Edit > Select Subject, Shift-click a small subject the first look missed;
  the pointer and the outline stop for a moment when the new outline appears.
- **Why:** CLAUDE.md: "The main thread never blocks for more than a frame."
- **Test that would catch it:** a Release performance test that `mark` and Return on a 48 MP pick return within a frame.

## 5. Object mode searches an adjustment layer or a group, which has no picture, before beeping
- **Severity:** Low
- **Confidence:** High
- **Where:** `Sources/Colorbee/Editor+Selection.swift:592-597`
- **What happens:** with Sample All Layers off, an Object click on an adjustment layer or a group looks for a subject in
  its empty, all-clear buffer: the first look, then every closer square (5 Vision calls on a 1,600 × 1,000 picture,
  8 on a 12 MP photo), with "Looking closer… Esc stops" showing, and only then beeps. Select Subject and friends are
  greyed out on an adjustment layer for this reason (review D, finding 6).
- **How to trigger it:**
  1. Open `TestImages/Stage 9 Practice Photo.png`. Add an adjustment layer (Layer > New Adjustment Layer > any) and
     leave it active.
  2. Press W, choose Object, and make sure Sample All Layers is off. Click the moon.
  Expected: a beep at once.
  What I think you'll see: "Looking closer… Esc stops" for a second or more, then a beep.
- **Why:** `selectObject` uses `canvas.paintLayer` without checking `isPixelLayer`, unlike `findSubject`.
- **Test that would catch it:** an app test that Object mode on an adjustment layer beeps without setting
  `isFindingSubject`.

## 6. Marking edge cases: overlapping marked subjects, and marks past 24 or labels past 32
- **Severity:** Low
- **Confidence:** Medium
- **Where:** `Sources/Colorbee/Editor+Effects.swift:441` and `:404`; `Sources/Colorbee/Shaders.metal:185-186`
- **What happens:** (a) when two marked subjects overlap under the click (a subject and one untangled inside it), which
  one Shift-click unmarks is chance: `pickMarked` is a `Set`, and its order changes from launch to launch. Shift-
  clicking a smaller subject tinted inside a marked bigger one unmarks the bigger one instead of marking the smaller.
  (b) Marks past the 24th still count for Return but never turn blue. (c) With more than 32 subjects, the shader
  shifts a 32-bit value by 32 or more, which Metal leaves undefined; on Apple GPUs a subject past the 32nd would likely
  turn blue when an early one is marked.
- **How to trigger it:** (a) needs a picture Vision merges; not easy by hand. (b), (c) need dozens of subjects.
- **Why:** `pickMarked.first(where: { pick.scan.masks[$0][index] >= 128 })`; `$1 < 24 ? ... : $0`;
  `marked >> uint(here - 1)`.
- **Test that would catch it:** an app test with two overlapping marked masks that Shift-click unmarks the one whose
  label is shown under the click.

## 7. Two "same layer" checks compare the pick with itself
- **Severity:** Low (no harm today)
- **Confidence:** High
- **Where:** `Sources/Colorbee/Editor+Effects.swift:453` and `:478`
- **What happens:** `current.layer == pick.layer` and `self.subjectPick?.layer == pick.layer` compare the pick's own
  stored layer with itself, so they never notice a different active layer. Today that's safe only because every way to
  change the layer, page or picture ends the pick first. A new command that changes the active layer without
  `finishInteractions` would let a late subject land on the wrong layer.
- **How to trigger it:** nothing reaches it today.
- **Why:** both sides come from `subjectPick`; neither reads `canvas.paintLayer.id`, as `findSubject` does.
- **Test that would catch it:** an app test that changes `canvas.activeLayerIndex` directly during a closer look and
  expects nothing to be taken.
