# Review C: pixel math, and screen versus export
Reviewed at commit: d67a8626cc8f975618ca03a10a8cf722cece4b5d
Checked:
- `Effects.swift`: every pointwise effect (Invert, Desaturate, Hue/Saturation, Levels, Curves, Sepia, Posterize), the box-blur Gaussian, Sharpen, Pixelate; `UInt8` conversions are all clamped first
- `Effects+Texture.swift`: Add Noise (position-based, so preview equals result), Motion Blur (angle, spacing, premultiplied average), Emboss, Vignette (`Vignette.strength` and `apply`)
- `Effects+Photo.swift`, `PhotoAdjustments.swift`: order of operations (detail, then color and tone, then vignette), clamping, Vibrance, Warmth and Tint
- `PhotoAuto.swift`, `Histogram.swift`, `Levels.swift` (table, gamma direction, Auto), `Curves.swift` (Fritsch–Carlson tangents, flat ends, no division by zero with repeated x)
- `PhotoFilter.swift`: intensity scaling, the Desaturate-to-saturation substitution, import
- `Effect+Codable.swift`, `ProjectFile.swift`: round trips of every effect kind, unknown kinds, damaged files
- `ColorLookup.swift`, `AdjustmentCompositing.swift`
- `Warp.swift`: Straighten sizes (Crop to Fit is the exact largest same-shaped rectangle, minus a pixel), the inverse rotation's direction, `straighteningAngle`, the homography (Heckbert square-to-quad), bilinear sampling, `CropBox`
- `Decorations.swift`: Drop Shadow pad (3σ) and opacity, Border coverage, the Felzenszwalb–Huttenlocher transform
- `Shaders.metal` against the Swift code, line by line: `fadeIn` against `Compositing.adjust` (blend, opacity, straight versus premultiplied), `adjust_point_fragment`, `adjust_lookup_fragment`, `adjust_photo_fragment` (detail weights 1.5 and 0.6, noise-reduction smoothstep, clamp, vignette constants), `adjust_blur_fragment`; `Renderer.swift`'s photo and lookup paths

Apart from the findings below, the screen and export math match: same order, same constants and ranges, straight colors on both sides, and the vignette is measured the same way. Small known differences remain (8-bit rounding between steps on export, box blurs on export against MPS Gaussians on screen).

## 1. Perspective Correction crashes when the bottom corners are swapped
- **Severity:** Critical (crash)
- **Confidence:** High (worked through numerically); also a general problem with crossed or non-convex corners
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/Warp.swift:118-121` (`Homography.apply` divides by `w`), `:71`, `:81` (`Int(x.rounded(.down))`); nothing checks the corners (`Sources/Colorbee/Editor.swift:1828-1830`, `:2182`)
- **What happens:** For a crossed quad, the homography's divisor `w = g·u + h·v + 1` passes through zero inside the image. When a pixel lands exactly on that line, `apply` returns ±infinity, and `sample` traps on `Int(-inf)`. Crossed quads that don't hit an exact zero don't crash, but they produce a mirrored, folded image with no warning.
- **How to trigger it:** A 1000 × 801 image, Image ▸ Perspective Correction…. Drag the top-left and top-right corners past the image's top corners (they snap to (0, 0) and (1000, 0)). Drag the bottom-right corner past the bottom-left image corner (0, 801), and the bottom-left corner past the bottom-right (1000, 801). Press Return. The result is 1000 × 1281; on row 640, v = 640.5 / 1281 = 0.5 exactly, so `w = 1 + (−2)(0.5) = 0` → `y = −inf` → crash.
- **Why:** For those corners, `g = 0` and `h = −2.0` exactly, so `w = 0` along a whole row. `Homography.init` handles a degenerate denominator but not a quad whose `w` changes sign.
- **Test that would catch it:** Core test: `ImageActions.correctPerspective(corners: [(0,0), (1000,0), (0,801), (1000,801)], …)` on a 1000 × 801 canvas must not crash. It should return false, or the Editor should refuse non-convex quads. Add a check that the four corners make a convex quad in order: the cross products of consecutive edges all have the same sign.

## 2. On screen, Posterize (and steep Levels or Curves) adjustment layers look very different from the export
- **Severity:** High (the screen shows something export doesn't)
- **Confidence:** High (measured with the exact table code)
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/Effects.swift:59-65` (`usesColorLookup` includes `.posterize`), `ColorLookup.swift:9-27` (33-point table), `Sources/Colorbee/Shaders.metal:250-260` (linear sampling)
- **What happens:** §23 says color adjustment layers on screen "can differ from the export by about one level". That holds for smooth adjustments, but a 33-point table, sampled with linear interpolation, can't show a step. Posterize is all steps, so the screen shows smooth ramps where the export has hard bands. Worst cases:
  - Posterize 2: input 127 exports as 0 but shows as 239.
  - Posterize 4: input 127 exports as 85, shows as 165.
  - Posterize 8: off by 35.
  - Levels with black 100 and white 140: off by 14.
  - Curves with a steep segment behave the same way.
- **How to trigger it:** Layer ▸ New Adjustment Layer ▸ Posterize, set 2 levels, over a gradient. The screen shows a soft ramp between black and white; File ▸ Export gives hard black and white.
- **Why:** Table points are about 8 input levels apart, and `lookup.sample` interpolates linearly between them, so a jump inside one interval is spread across it.
- **Test that would catch it:** Core test comparing `ColorLookup(effect)` with linear interpolation (as the shader samples it) against `effect.colorTransform` for all 256 gray inputs, for Posterize 2...32, Levels with a 40-level range and a steep Curves. Assert the largest difference is at most 1. Possible fixes: draw Posterize with a dedicated shader case, use per-channel 256-entry 1D tables for Levels, Curves and Posterize (all three are per channel), or use a larger 3D table.

## 3. Borders around very wide shapes get gaps (Float precision in the distance transform)
- **Severity:** Low (wrong pixels for very wide shapes only)
- **Confidence:** Medium (simulated the exact pass in single precision)
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/Decorations.swift:207-266` (`distanceField` and `transform` use `Float`)
- **What happens:** `s = ((f[q] + q²) − (f[p] + p²)) / (2q − 2p)` in `Float` loses precision once `q²` passes about 2²⁴. For shapes wider than about 8,200 px, points one pixel from the shape get a distance of 2.24 instead of 1 (2.83 instead of 2). A 1-px Border then leaves about one pixel in four uncovered along the far side; wider borders aren't affected.
- **How to trigger it:** A 16000 × 2000 canvas with a non-rectangular shape spanning its width (an ellipse or a rounded shape, so the distance field is used rather than the square-corner box field). Effects ▸ Border at 1 px: there are gaps along the top and bottom edges past x ≈ 8,200. In the simulation, 1,953 of 16,000 pixels came out wrong on each of the rows 1 and 2 px above the shape.
- **Why:** Squared column positions above 16,777,216 can't be held exactly in `Float`, so the envelope picks the wrong nearest point.
- **Test that would catch it:** `Shape.distanceField` on a 1-row-tall shape 16,000 px wide: every pixel directly above it should be at distance 1 (±0.01). Using `Double` for the grid and `transform` fixes it.

## 4. A damaged project file can crash instead of reporting an error
- **Severity:** Low (crash on bad input)
- **Confidence:** High
- **Where:** `Packages/ColorbeeCore/Sources/ColorbeeCore/ProjectFile.swift:100-106`; `Effect+Codable.swift:35`, `:39`
- **What happens:** The manifest's `width` and `height` are only checked to be positive. The decoder creates `PixelBuffer(width:height:)` before checking the pixel data, so a huge size hits `fatalError("Out of memory…")` in `mmap`. If `width × height × 4` overflows, it traps even earlier. Separately, `Int(value(0))` for Posterize or Pixelate traps when the stored number is outside `Int`'s range (for example `1e300`). Projects and `.colorbeefilter` files are shared between people, so a corrupted or hand-edited file should give "can't be opened" rather than a crash.
- **How to trigger it:** Edit a `.colorproj`'s JSON so `"width": 4000000000`, or a `.colorbeefilter` so a posterize step has `"values": [1e300]`, then open or import it.
- **Why:** There's no upper bound like `ResizeSkew.maxSide`/`maxArea` in `decode`, and the Double-to-Int conversions are unchecked.
- **Test that would catch it:** `ProjectFile.decode` of a manifest with `width: Int(Int32.max)` throws `Failure.damaged`. `Effect(from:)` with `values: [1e300]` throws, or clamps, rather than trapping. Use `Int(exactly:)` with a range check.
