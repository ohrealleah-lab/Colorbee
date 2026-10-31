# Review AD: the core's pixels and effects
Reviewed at commit: 08094b72da6bb45f122b342dd285728849008e7b
Checked:
- `Pixel`, `PixelBuffer`, `ParallelRows`, `Compositing`, `BlendMode`, `AdjustmentCompositing`, `Resampling`
- `Effects`, `Effects+Photo`, `Effects+Texture` (Noise, Vignette), `EffectPreview` (only where it wraps `Effects`)
- `PhotoAdjustments` (with `PhotoEdit`), `PhotoDetail`, `PhotoEffects` (Vignette shape, Grain), `PhotoFilter`, `PhotoAuto`
- `ColorMixer`, `ColorGrading`, `PointColors` (with `HSLColor`), `ToneCurve`, `Curves`, `Levels`, `ColorLook`, `ColorLookup`,
  `CubeFile` (resampling only), `WhiteBalance`, `Histogram`
- `Warp` (with `CropBox`, Straighten, Perspective, Crop), `ResizeSkew`
- `Brush`, `BrushTexture`, `BrushStroke`, `RoundBrushStroke` (with Pencil and Eraser), `RetouchStroke` (with Smudge and
  `ToneMatch`), `DabWalker`, `CoveragePainter`, `StrokePath`
- `FloodFill` (with the magic wand), `MatchSurroundings`, `RedEye`
- `SelectionMask`, `SelectionMask+Modify`, `ColorRange`, `LuminanceRange`, `GraduatedSelection`
- Searches across the core for luma coefficients, smoothstep, clamp-to-`UInt8`, box-blur sizing, vImage premultiply,
  `@unchecked Sendable` wrappers, `maxSide`/`maxArea`, and uses of suspected dead code.
- Left to others: the hand-written `Codable` in `PhotoDetail`, `PhotoEffects`, `ColorMixer`, `ColorGrading`, `PointColors`
  and `ToneCurve` repeat the same "read with a default, clamp, skip what's damaged" pattern (AE covers every
  hand-written `Codable`). The shader twins of these rules are AC's.

## Copies that already differ

1. **Match Surroundings' tone blend is the older version of the Clone Stamp's Match Tone.**
   `MatchSurroundings.swift:295` (`Level.matchTone`) and `RetouchStroke.swift:318` (`ToneMatch.plan`, `smoothFill` at
   `:398`) do the same job: take the color difference at the area's edge, smooth it along the edge over ±3 pixels, and
   spread it inward. ToneMatch was rebuilt to solve it as a smooth membrane, because "spreading it inward ring by ring
   left hard lines (Leah's video, 2026-10-22)" (`RetouchStroke.swift:395`). Match Surroundings still spreads ring by
   ring (`MatchSurroundings.swift:330-355`). ToneMatch also weights edge pixels by how opaque they are; Match
   Surroundings doesn't. So the fix for the hard lines landed in one copy only. This may be the same seam bug in Match
   Surroundings, or it may be fine there, since its fill is already a patch-matched texture. Leah's call (finding 1).
2. **Two lumas for "desaturate".** Effects ▸ Desaturate uses Rec. 709 (`0.2126, 0.7152, 0.0722`, `Effects.swift:109`).
   The Desaturate and Saturate local brushes, and Lighten and Darken's tone ranges, use Rec. 601
   (`0.299, 0.587, 0.114`, `RetouchStroke.swift:135`). So the brush makes a slightly different gray than the menu
   command on the same pixel. (The blend modes' `0.3, 0.59, 0.11` in `BlendMode.swift:104` is the W3C spec on purpose,
   and is mirrored in the shader. That one's fine.)
3. **Feather and Gaussian Blur size their boxes differently.** Both approximate a Gaussian with three box blurs, and
   each works out the box width from σ with the same formula, √(4σ² + 1), made odd. Gaussian Blur rounds it
   (`Effects.swift:237`); Feather truncates it (`SelectionMask.swift:184`). They agree for every whole-pixel feather
   radius, because √(r² + 1) is just over r. They differ for some fractional radii: at radius 5.5, Feather uses a 5 px
   box and the same σ in Gaussian Blur would use 7. This only matters if a fractional feather radius can reach
   `feathered`.
4. **Two premultiplied pixel lerps.** `Compositing.lerp` (`CoveragePainter.swift:185`) and `PixelBuffer.blend`
   (`ResizeSkew.swift:114`) have the same formula, but one works in `Float` and the other in `Double`, so they can round
   one level apart. When both pixels are clear, `lerp` keeps the mixed hidden color and `blend` returns `.clear`. You
   can't see either difference today.
5. Not mine to judge, just noting it for AC: the screen draws a Gaussian Blur adjustment layer with a true Gaussian
   (`MPSImageGaussianBlur`, `Renderer.swift:851`), while export uses the three-box version above.

## 1. Give Match Surroundings ToneMatch's edge blend instead of its own older copy
- **Worth:** High
- **Kind:** Copies
- **Size:** Medium (a few hours)
- **Risk:** This **changes Match Surroundings' pictures** (smoother tone, no ring lines), so it's a behavior change, not
  a pure refactor. Leah decides first, from "Copies that already differ" 1. `MatchSurroundingsTests` would need its
  expected values checked again. `RetouchStrokeTests` covers ToneMatch. If Leah wants Match Surroundings left exactly
  as it is, do only the second half (move `ToneMatch` into its own file) and add a comment on `matchTone` pointing at
  its twin and saying why they differ.
- **Where:** `MatchSurroundings.swift:295-362` (`matchTone`) and `:365-392` (`fillFromEdges`, the same ring-by-ring loop
  a second time in that file); `RetouchStroke.swift:259-492` (`ToneMatch`).
- **What:** The healing blend exists twice. A fix to one (the membrane solve, the opacity weighting) didn't reach the
  other. `ToneMatch` is also buried in `RetouchStroke.swift`, next to two unrelated strokes, where nobody fixing Match
  Surroundings would look.
- **Suggested change:** Move `ToneMatch` to `ToneMatch.swift`. Give it an entry point that takes a grid of edge offsets,
  a "known" mask and the hole's cells, which is what `smoothFill` already takes. Have `Level.matchTone` build those
  from its `hole`/`holeIndices` and call it. Then `matchTone`'s own spreading loop goes, and `fillFromEdges` is the
  only ring-by-ring loop left.

## 2. Auto and the white-balance eyedropper undo the slider math by hand
- **Worth:** Medium
- **Kind:** Copies
- **Size:** Small (under an hour)
- **Risk:** Low if the constants are just named; the pictures are unchanged. `WhitesAndWhiteBalanceTests` (eyedropper
  makes gray) and `AdjustPhotoTests`/`PhotoAdjustmentTests` (Auto's values) would catch a slip.
- **Where:** `PhotoAdjustments.swift:98, 102, 128-130, 144-153` (the forward math); `WhiteBalance.swift:22-28`
  (the eyedropper solves Warmth and Tint backwards); `PhotoAuto.swift:32-34` (Auto solves Whites backwards, with
  `smoothstep(0.3, 1, …)` and `0.25`) and `:43-47` (Warmth and Tint, `0.15` and `0.12`).
- **What:** Warmth's `0.15`, Tint's `0.12` and `0.04`, and Whites' `0.25` and its `smoothstep(0.3, 1)` weight are each
  written in two or three places. Retune one in `colorTransform` and the eyedropper stops making gray, and Auto aims at
  the wrong place, with no compile error. The comment in `WhiteBalance.swift:23` even says "See
  `PhotoAdjustments.colorTransform`", which is the sign of a copy.
- **Suggested change:** Name the constants once on `PhotoAdjustments` (`warmthScale`, `tintGreen`, `tintRedBlue`,
  `whitesReach`), and add small static functions for the forward step (`warmed(_:by:)`, `tinted`, `whitesWeight`).
  `colorTransform`, `neutralizing` and `auto` all use them, so each slider's formula lives in one place.

## 3. `default:` in the `Effect` switches lets a new effect slip through silently
- **Worth:** Medium
- **Kind:** Hard to change
- **Size:** Small (under an hour)
- **Risk:** None to pictures: each `default` is spelled out as the cases it covers today. It compiles or it doesn't.
- **Where:** `Effects.swift:63-68` (`usesColorLookup`), `:72-83` (`reach`, `default: return 0`), `:86-91`
  (`usesChannelTable`); `PhotoFilter.swift:130-143` (`forFilters`, `default: return nil`), `:146-173` (`scaled`,
  `default: return self`); `PhotoAdjustments.swift:269-277` (`needsFineColorTable`).
- **What:** `pointwise` and `applyToRegion` list every case, so adding an effect forces you to think about them. These
  six don't. A new neighbor-reading effect would get `reach` 0, so an adjustment-layer patch would show seams. A new
  color effect would be dropped from filters and wouldn't scale with Intensity, and nothing would warn you. The app
  is frozen except for the photo plan, and that plan is exactly where new effects (like `.look`) keep arriving.
- **Suggested change:** Replace each `default:` with the explicit list of cases, so the compiler points at all six
  the next time `Effect` grows.

## 4. Byte luminance is written three times, and `luma` a fourth way
- **Worth:** Medium
- **Kind:** Copies
- **Size:** Small (under an hour)
- **Risk:** The three byte versions are identical (`Double`, same order, `.rounded()`), so sharing them changes
  nothing. `PointColors`' gray works through `luma(rgb / 255) * 255`, which could round differently at exact halves,
  so leave that one alone or check it with `PointColorsTests` first. Also covered by `EffectsTests` (Desaturate)
  and the `Histogram`/Levels Auto tests in `AdjustmentTests`. No test reaches `maskGray` directly; add one exact-value
  test for it first.
- **Where:** `Pixel.swift:22-26` (`maskGray`); `Histogram.swift:54-60` (`Pixel.luminance`, an extension on `Pixel`
  hidden in the Histogram file); `Effects.swift:107-114` (Desaturate). Related: `PhotoAdjustments.swift:171` (`luma`
  in 0...1), `PointColors.swift:118`, `ToneCurve.swift:43`, `LuminanceRange.swift:35`.
- **What:** One rule ("Rec. 709 gray of a pixel, rounded") in three places, in three files, and the one called
  `luminance` lives where nobody would look for it.
- **Suggested change:** Keep `Pixel.luminance` in `Pixel.swift`. Have `maskGray` and `.desaturate` call it. Have
  `luma` name the same three coefficients from one place.

## 5. Two vignette falloffs, one of which is a special case of the other
- **Worth:** Medium
- **Kind:** Copies
- **Size:** Small (under an hour)
- **Risk:** None. `strength(size: s)` gives exactly the same result as
  `strength(shape: Shape(midpoint: s, roundness: 0, feather: 50))`, and the doc comment at `PhotoEffects.swift:79`
  says so. `PhotoEffectsTests` checks it at size 50; add a check at a few other sizes first. `EffectsTests` covers
  Effects ▸ Vignette.
- **Where:** `Effects+Texture.swift:122-129` (`strength(x:y:in:size:)`, its only caller is `:93`);
  `PhotoEffects.swift:82-106` (`strength(x:y:in:shape:)`, twinned in `Shaders.metal:400`).
- **What:** Each copy has its own center, distance and smoothstep code. A fix to the falloff (an off-by-half-pixel
  center, say) has to be made in both, plus the shader.
- **Suggested change:** Have `strength(size:)` build a `Shape` and call `strength(shape:)`, or have `vignetted` call
  that directly and delete the size version.

## 6. Box-blur sizing lives in three places, one of which rounds differently
- **Worth:** Medium
- **Kind:** Copies
- **Size:** Small (under an hour)
- **Risk:** Sharing `blurReach` with `blurred` changes nothing. Feather's truncation is "Copies that already differ"
  3: keep it unless Leah says to match it, since matching changes some fractional feathers. Covered by `EffectsTests`,
  `AdjustPhotoTests` (detail blurs), `SoftSelectionTests` and `SelectionModifyTests`.
- **Where:** `Effects.swift:230-233` (`blurReach`) and `:237-238` (`blurred`: the same two lines again);
  `SelectionMask.swift:181-185` (`feathered`: its own version). The three-pass vImage box loops are at
  `Effects.swift:305-319` (ARGB) and `SelectionMask.swift:205-214` (Planar8).
- **What:** `blurReach` exists so that an adjustment-layer patch reads exactly as far as `blurred` does
  (`Effect.reach`). Right now it only agrees because the two lines were copied. Change the box rule in `blurred` and
  patches start to show seams.
- **Suggested change:** Add a small `BoxBlur` with `width(sigma:)` and `reach(sigma:)`. Have `blurred` use it, have
  `blurReach` forward to it (or go), and have `feathered` call it with its own rounding passed in, or switch to it
  only if Leah agrees. Optionally, one `threePasses` helper per vImage format.

## 7. The size limits are spelled out in five places, and the skew extent twice
- **Worth:** Medium
- **Kind:** Copies
- **Size:** Small (under an hour)
- **Risk:** None: the same comparisons, moved. Covered by `ResizeSkewTests`, `WarpTests` and `CanvasPropertiesTests`.
- **Where:** `ResizeSkew.swift:35-39` (`fits`); `Warp.swift:221` (Perspective) and `:274` (Straighten);
  `Sources/Colorbee/CanvasPropertiesSheet.swift:22` and `:54`. The skew: `ResizeSkew.swift:56-58` (`extent`, which
  `resultSize` and therefore `fits` use) and `:83` (`skewed`, which works out the real size again inline).
- **What:** The comment at `ResizeSkew.swift:13-14` says "every size check uses this", but each check re-types
  `w <= maxSide && h <= maxSide && w * h <= maxArea`. If the limits ever gain a rule (memory, say), some checks will
  miss it. Separately, `fits` approves `resultSize`, but `skewed` makes its own buffer from its own copy of the
  formula. If they ever drift apart, the check approves one size and a different one is made.
- **Suggested change:** Add `ResizeSkew.allows(_ size: IntSize) -> Bool` and use it in all five places. Have `skewed`
  call `ResizeSkew.extent` instead of repeating it.

## 8. Running an effect on a plain buffer means building a throwaway Canvas and Edit, twice
- **Worth:** Medium
- **Kind:** Hard to change
- **Size:** Small (under an hour)
- **Risk:** Low: the same pixels, without the wrapper. Covered by `AdjustmentTests`, `ClippedAdjustmentTests`,
  `ColorAsShownTests` (adjustment layers) and the effect-preview tests in `EffectsTests`.
- **Where:** `AdjustmentCompositing.swift:46-55` (`Effects.adjusted`); `EffectPreview.swift:13-23` (`render`).
- **What:** `Effects.apply` only takes a `Layer` and an `Edit`, so two callers that just want "this buffer with this
  effect" build a `Canvas`, a `Layer` and an `Edit(recordsPixels: false)` to hold it. Any change to what `Canvas` or
  `Edit` need at init has to be made in both. The adjustment-layer path also copies the whole buffer first.
- **Suggested change:** Split `applyToRegion` into a pure part (`rendered(effect, buffer, region, selection) ->
  (PixelBuffer, IntPoint)`, or "changed in place" for `pointwise` effects) and the write-back, which calls
  `edit.willModify`. `Effects.apply` keeps its signature. `adjusted` and `EffectPreview.render` call the pure part
  with no scratch canvas.

## 9. Whole-image loops that skip `ParallelRows`, when `SelectionMask.measured` already exists
- **Worth:** Medium
- **Kind:** Already there
- **Size:** Medium (a few hours)
- **Risk:** Each pixel is worked out on its own, so the results are identical, and only speed changes. Covered by
  `ResamplingTests`, `MagicWandTests`, `SelectionMaskTests`, `SelectionRangeTests`, `SoftSelectionTests` and
  `ResizeSkewTests`. Run `make perf` after.
- **Where:** `FloodFill.swift:162-171` (the non-contiguous magic wand: a serial loop over the whole image that is
  exactly `SelectionMask.measured(buffer) { $0.matches(target, tolerance: limit) ? 255 : 0 }`, `ColorRange.swift:47`).
  `GraduatedSelection.swift:25-40` hand-rolls the same parallel mask loop as `measured`, by position. Serial and whole
  image: `SelectionMask.swift:246-259` (`build`, used by `inverted` over the whole canvas and by `combine`),
  `Resampling.swift:17-24` (nearest-neighbor resize of a whole layer), `Resampling.swift:55-61` (`stretched`) and
  `ResizeSkew.swift:128-140` (mask resize).
- **What:** CLAUDE.md says whole-image loops run on all cores. Some do it by hand, some don't do it at all, and the
  one helper built for it (`measured`) is used by just two callers.
- **Suggested change:** Give `measured` a position-based twin (`measured(in: IntRect) { x, y in UInt8 }`) on
  `ParallelRows`. Use it for the wand, Graduated Selection, `build`, `inverted` and `combine`. Wrap the
  nearest-neighbor resize in `ParallelRows.forEach`.

## 10. General color math lives in `PhotoAdjustments`, with inline copies elsewhere
- **Worth:** Low
- **Kind:** Copies
- **Size:** Medium (a few hours)
- **Risk:** Moving functions changes nothing. A shared "round and clamp to `UInt8`" must keep each caller's rounding:
  most use `.rounded()` (half away from zero), but `RetouchStroke.swift:154, 247, 488` use `.toNearestOrEven`.
  Covered by the exact-value tests of each effect (`EffectsTests`, `PhotoAdjustmentTests`, `ColorMixerTests`,
  `RetouchStrokeTests`, `BrushStrokeTests`).
- **Where:** `PhotoAdjustments.swift:171-184` (`luma`, `smoothstep`, `power`, `clamped`), used by `ColorMixer`,
  `ColorGrading`, `PointColors`, `ToneCurve`, `ColorRange`, `LuminanceRange` and `GraduatedSelection`.
  `smoothstep` is written out inline at `Effects+Texture.swift:128`, `PhotoEffects.swift:105, 134`,
  `BrushTexture.swift:19` and `RetouchStroke.swift:129`. Hue to RGB by sextant: `Effects.swift:429-436` (`HSL.pixel`)
  and `ColorGrading.swift:88-96` (`tint`). "Round and clamp to a byte" is a local function about 15 times:
  `BlendMode.swift:169, 179`, `Effects.swift:120, 137, 295, 438`, `Effects+Texture.swift:16, 79, 136`,
  `PhotoEffects.swift:157`, `ColorMixer.swift:158`, `ColorLook.swift:57`, `BrushStroke.swift:236` and more.
- **What:** A selection tool calling `PhotoAdjustments.smoothstep` is a sign that the helpers have no home of their
  own. Each inline copy is a line, but `UInt8(_:)` traps on NaN or a negative number, and every hand-written clamp is
  a place to get that wrong.
- **Suggested change:** Add a `ColorMath` enum (or put these on `Pixel`/`SIMD3`) holding `luma`, `smoothstep`,
  `clamped`, a `byte(_ value: Double)` that clamps and rounds (with an even-rounding variant), and the hue sextant.
  Leave `PhotoAdjustments.luma` and the others as forwarding names, or replace them. Do the inline copies as they're
  touched.

## 11. Three alpha-weighted "average color" functions
- **Worth:** Low
- **Kind:** Already there
- **Size:** Small (under an hour)
- **Risk:** None: with no selection, all three give identical results today (same order, same rounding).
  `EffectsTests` (Pixelate) and the eyedropper tests in `WhitesAndWhiteBalanceTests` cover them.
- **Where:** `Effects.swift:365-386` (`averageColor(of:in:selection:)`, for Pixelate); `WhiteBalance.swift:36-50`
  (`PixelBuffer.averageColor(in:)`) and `:56-66` (`averagedPixel(in:)`, which also walks the rect a second time just
  for alpha).
- **Suggested change:** One `PixelBuffer.averagedPixel(in:selection:)` that sums color, alpha and count in one pass.
  `averageColor(in:)` becomes that with full opacity, and Pixelate calls it with its selection.

## 12. Feather and Modify Selection share a copied "pad the mask" block
- **Worth:** Low
- **Kind:** Copies
- **Size:** Small (under an hour)
- **Risk:** None. Covered by `SoftSelectionTests` and `SelectionModifyTests`.
- **Where:** `SelectionMask.swift:186-201` and `SelectionMask+Modify.swift:35-50`. Line for line the same: grow the
  bounds by a margin, clip to the canvas, copy the rows in.
- **Suggested change:** Add `SelectionMask.padded(by:clippedTo:) -> (area: IntRect, values: [UInt8])?` and use it in
  both. `modified` wraps the values in its `MaskPlane`.

## 13. `ParallelRows` lacks two small pieces, so callers re-roll them
- **Worth:** Low
- **Kind:** Copies
- **Size:** Small (under an hour)
- **Risk:** None. `PerformanceTests` and the tests for each caller (`RetouchStrokeTests`, `MatchSurroundingsTests`,
  `AdjustmentTests`, `DecorationTests`).
- **Where:** Four `@unchecked Sendable` pointer wrappers: `ParallelRows.swift:41` (private), `RetouchStroke.swift:496`,
  `MatchSurroundings.swift:544-551` and `Decorations.swift:303`. Hand-rolled band ranges inside `ParallelRows.map`:
  `Histogram.swift:22-26`, `RetouchStroke.swift:293-296` and `:325-329`, `MatchSurroundings.swift:190-197`.
- **What:** Each unchecked wrapper is a place where thread safety rests on a comment. Four copies means four places to
  audit. Each band split has its own size (16, 64 rows, `bands`), and each has its own off-by-one risk.
- **Suggested change:** Make `UnsafeSendable` internal and use it everywhere. Add
  `ParallelRows.mapBands(_ range:, rows: Int, _ body: (Range<Int>) -> T) -> [T]` for the collect-per-band cases.

## 14. The strokes: what they share, and why a base class isn't worth it
- **Worth:** Low
- **Kind:** Copies
- **Size:** Small (under an hour)
- **Risk:** None if the helpers return the same rects and distances. `RoundBrushStrokeTests`, `BrushStrokeTests`,
  `ToolStrokeTests` and `RetouchStrokeTests` have exact-value tests.
- **Where:** The size from pressure, `diameter * Brush.sizeFactor(pressure:)`, is at `RoundBrushStroke.swift:47-49`,
  `RetouchStroke.swift:109-111` and (halved) `BrushStroke.swift:87-89`. The dab's square around a center,
  `IntRect(enclosingMinX: c.x - r - 1, …)`, is at `RoundBrushStroke.swift:63`, `BrushStroke.swift:117, 141, 176, 224`,
  `RetouchStroke.swift:115` and `RedEye.swift:56`. The pixel's offset from the center, `Double(x) + 0.5 - center.x`,
  repeats inside each one. `PencilStroke` and `EraserStroke` (`RoundBrushStroke.swift:87-130`) have the same
  Bresenham-plus-mirror `move`.
- **What:** Round, Brush and Retouch already share the parts that matter (`DabWalker`, `CoveragePainter`,
  `Brush.sizeFactor`). Smudge works differently (it carries paint and has no painter). So a common base class would
  mostly be empty, and would tie four different painting models together. What's left over is small geometry,
  repeated.
- **Suggested change:** Add `IntRect(around: Point2D, radius: Double)` and `Point2D.distance(toPixel:)` (or a
  `CoveragePainter.paintRound(center:radius:) { distance in … }`), and give Pencil and Eraser one shared
  `pixelSteps(to:)` helper. No base class.

## 15. Leftovers
- **Worth:** Low
- **Kind:** Dead code
- **Size:** Small (under an hour)
- **Risk:** None. The tests that use `vignetteAmounts` switch to `vignettes.map(\.amount)`.
- **Where:** `PhotoAdjustments.swift:303`: `PhotoEdit.vignetteAmounts` has no caller outside the tests (three uses in
  `AdjustPhotoTests`). `Effects.swift:227-229`: `blurred`'s doc comment ("Blurs `region` plus a margin…") ended up above
  `blurReach`, so `blurred` has none. `Warp.swift:33-34`: `rotated` has two overlapping doc comments, an old one and
  a new one. Also, `Pixel.matches` and `Compositing.lerp` live in `CoveragePainter.swift:167-193`, though Effects,
  FloodFill and selections all use them. `ColorRange.swift:36` repeats `matches`' channel difference rather than
  calling it.
- **Suggested change:** Delete `vignetteAmounts`. Put each comment back on its own function. Move `matches` to
  `Pixel.swift` and `lerp` to `Compositing.swift`. Give `Pixel` a `difference(to:) -> UInt8` that `matches` and
  `ColorRange` both use, since its comment says they "compare as the Magic Wand compares".
