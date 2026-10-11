# GPU acceleration audit

_Written 2026-10-10 for Leah; updated the same day with her answers, real timings and a timing of her CR3._ **A proposal for Leah to decide, not a plan.** No Colorbee code was changed._

## Bottom line

**Nothing needs the GPU, and Leah's answers rule it out anyway.** Measured on her M2 Max, every everyday edit on a 12 MP phone photo takes 10–330 ms. The slowest edits on a 45 MP photo take 1.2–1.3 s. Leah also said previews must match the applied result, and a GPU can't give that for most of this code (Metal has no `Double`).

**The one real lag is the RAW Develop window's sliders**, as Leah reported. It is not a missing-GPU problem: Core Image already uses the GPU. Each slider tick builds a brand-new `CIRAWFilter` and so re-reads the RAW file (about 0.4–1.3 s per tick on her 45 MP CR3). Reusing one filter for previews cut every Develop slider to about 35–100 ms, with identical pixels (recommendation 1). It is a small change in the app target.

**Leah's later answers add two more real pain points:** Straighten lags on big or multi-layer photos, and Adjust Photo's 1.2 s on a 45 MP photo is not acceptable. Both have CPU-only fixes with identical previews (recommendations 2 and 3). The Adjust Photo one is the best find of the audit: remembering each color's result made the color part **25× faster (653 → 25 ms) with byte-identical output** on her real photo.

After that, a small CPU-only cleanup of serial loops (recommendation 4). None of this needs an architecture change.

## Leah's answers (2026-10-10)

1. Sliders aren't laggy, except **on a big RAW photo in the Develop window**, where they lag. She supplied a 45 MP Canon CR3 (`7762545337.cr3`, 8192 × 5464) to time.
2. Straighten **is** laggy (on big or multi-layer photos).
3. About 1.2 s per Adjust Photo update on a 45 MP photo is **not** acceptable.
4. Her normal photo is a 12 MP iPhone shot; 45 MP RAW photos will happen.
5. A preview must be the same as the applied result. This rules out GPU previews, since the GPU would give slightly different pixels. The adjustment-layer shaders already differ slightly from the CPU code.
6. Timing runs approved (including her CR3).
7. **Straighten: do both option A (background) and option B (vImage rotation).** Leah chose B because it's significantly faster. (Decision 2026-10-10; log it in FRD §23.)

## How the timings were made (two throwaway scripts)

- [GPU-AUDIT-timing.txt](GPU-AUDIT-timing.txt): synthetic 12 MP and 45 MP photos for effects, flatten, Straighten, Skew, PDF and more.
- [GPU-AUDIT-raw-timing.txt](GPU-AUDIT-raw-timing.txt): the Develop window's previews on Leah's CR3, today's way against one reused filter.
- [GPU-AUDIT-photo-timing.txt](GPU-AUDIT-photo-timing.txt): Adjust Photo on the same photo developed to 45 MP, the remember-each-color prototype, and the Straighten rotation comparison.
- Details of the synthetic-photo script:

- It ran in Release on Leah's M2 Max. It is not part of the test suite.
- To run it, copy it to `Packages/ColorbeeCore/Tests/ColorbeeCoreTests/ScratchTiming.swift` and run `swift test -c release --no-parallel --filter ScratchTiming` in `Packages/ColorbeeCore`. It takes about 30 seconds. Don't commit it: it would run in `make test` in Debug and take minutes.
- The test image is a noisy gradient, which is photo-like and doesn't compress trivially. Each number is the fastest of 3 runs (12 MP, 4000 × 3000) or 2 runs (45 MP, 8256 × 5504).
- Effects include the history before-image recording. The live preview numbers use `EffectPreview.render`, the path the sliders use.
- The code was read at commit `7c85d0c`; `main` has since changed `Effects.swift`, `Canvas.swift`, `SelectionMask.swift`, `Subjects.swift` and `Editor.swift` (stage 13). Line numbers are not given; find each loop by function name and check that the soft-edge selection work didn't already change it.

## Why copying to the GPU is not the problem

On Apple Silicon memory is shared, and Colorbee already gives layer buffers to Metal without copying (`Renderer.texture(for:)`, `bytesNoCopy`). The real obstacles are:
- **Exactness.** Metal has no `Double`; the CPU effects use `Double`.
- **Screen vs export.** The screen composites in half floats, export in Float32. A GPU flatten would change some exported bytes.
- **Size limits.** Apple GPUs cap textures at 16,384 px; Colorbee allows 30,000.
- **Memory.** Extra temporary buffers are a worry after the 30-minute soak crashed the Mac.
- **Upkeep.** Each GPU path is a second copy of an algorithm to keep in step.

## Table (measured)

| Area | Uses now | 12 MP | 45 MP | GPU? | Why |
|---|---|---|---|---|---|
| Display (`Renderer`, `Shaders.metal`) | Metal, MPS blur | real time | real time | Already GPU | Nothing to add. |
| Flatten, 2 layers + adjustment | `ParallelRows`, Float32 | 47 ms | 189 ms | No | Opaque Normal layers only: 16 / 60 ms. A GPU flatten would change exported bytes. |
| Gaussian blur r8 | vImage box blur ×3, serial copy loops | 58 ms | 202 ms | No | A GPU Gaussian would look different. About half the time is the serial copy loops (below). |
| Sharpen | Blur plus a serial `Double` loop | 107 ms | 399 ms | No | About twice the blur's time; the serial loop is the difference. |
| Hue/Saturation | `ParallelRows`, `Double` closure | 39 ms | 167 ms | No | `Double` can't match on a GPU. Fast already. |
| Invert / Pixelate | `ParallelRows` | 9 / 25 ms | 36 / 97 ms | No | Fast already. |
| Adjust Photo, color sliders only | `ParallelRows`, `Double`, many `pow()` | 168 ms | 682 ms | No | Can't match bit for bit. |
| Adjust Photo, all sliders (sharpness, definition, noise, vignette too) | Same plus two blurs | 308 ms | 1,200 ms | No | The slowest effect. Its two blurs include the serial copy loops. |
| Live slider preview (same code) | `EffectPreview.render`, background, coalesced | blur 63 ms, Adjust Photo 307 ms | blur 227 ms, Adjust Photo 1,188 ms | No (previews must match) | Fine at 12 MP, as Leah found. About 1.2 s per Adjust Photo update on 45 MP. |
| Straighten, 1 layer | `ParallelRows`, bilinear | 109 ms | 431 ms | No | Hardware bilinear uses coarser weights; wouldn't match. |
| Straighten, 3 layers | same | 333 ms | 1,315 ms | No | The slider preview does this **on the main thread** every tick (`Editor.renderDecorationPreview`). |
| Perspective Correction, 1 layer | same | 109 ms | 421 ms | No | One-shot. |
| Resize smooth (80%) | vImage Lanczos | 50 ms | 216 ms | No | Already Accelerate. |
| Resize sharp (80%) | Serial loop | 9 ms | 33 ms | No | Not a problem (my first guess was far too high). |
| Skew, horizontal only (smooth) | Serial `Double` loop | 106 ms | 401 ms | No | One-shot. |
| Skew, horizontal + vertical (smooth) | Serial; the vertical pass is cache-unfriendly | 323 ms | 1,250 ms | No | The slowest unparallelized loop. |
| Remove Background / Select Subject | Vision (Neural Engine / GPU), serial mask expand | expand 25 ms per subject | expand 97 ms per subject | Already accelerated | Vision's own time was not timed. |
| Auto-Redact | Vision, one tile at a time | not timed | not timed | Already accelerated | Vision-dominated. |
| PDF export, one Letter page | `ParallelRows` flatten, Apple zlib | 310 ms (200 DPI page, 3.7 MP) | 690 ms (300 DPI page, 8.4 MP) | No | Pages encode in parallel. Compression isn't GPU work. |
| RAW Develop window preview (1600 px) | Core Image (Metal-backed); a **new `CIRAWFilter` every slider tick** | — | 0.42–1.3 s per tick (CR3, 45 MP) | Already GPU | The lag is the repeated file read and decode, not missing GPU. Reusing one filter: 32–98 ms per tick, same pixels. See below. |
| RAW open / final develop | Same | — | open 3.9 s, develop 0.9–1.7 s | Already GPU | One-shot; peak memory about 1.9 GB. |
| Fill, Magic Wand, undo, history | Scanline fill, LZ4 on all cores | — | — | No | From the earlier 64 MP logs: fill and wand 0.3–0.4 s, worst undo 0.33 s. Sequential or compression work. |

At 1080p everything meets NFR-6 (100 ms). For scale, the earlier 64 MP (8000 × 8000) numbers were: Flatten ~0.4 s, blur ~0.5 s, Sharpen up to 1.4 s in the soak.

## RAW Develop timings (Leah's CR3, 8192 × 5464)

Made with a second throwaway script, saved as [GPU-AUDIT-raw-timing.txt](GPU-AUDIT-raw-timing.txt) (see its header for setup). It uses `RawDeveloper.swift` unchanged, and times the preview at 1600 px the way `DevelopSession` asks for it.

- **Caveat: the Mac was busy** (the engineer session's tests and a game were running, load average about 10–12), so absolute times are probably pessimistic and the first runs jumped around. Each figure below is the fastest of 5, with the slider being tested changing on every run. The ratio is what matters.
- **How the app does it now** (`RawDeveloper.image` makes a new `CIRAWFilter(imageURL:)` per call): exposure 658 ms, temperature 441, tint 653, highlights 459, shadows 463, contrast 470, noise reduction 1,349, sharpness 423.
- **One filter reused** (only its settings change, then render): exposure 39 ms, temperature 39, tint 32, highlights 42, shadows 40, contrast 98, noise reduction 43, sharpness 47. The first render still takes about 0.4 s.
- **Pixels:** in a separate run the two ways gave byte-identical 1600 px previews for every control tried (exposure, temperature, tint, highlights, shadows, contrast, noise reduction, sharpness).
- **To build it:** `RawDeveloper.swift` says "each render makes its own filter, so previews and the final render can run on other threads". Keep that for the final develop. For previews, keep one filter, used one preview at a time under a lock (`DevelopSession` already allows only one preview render at once), and let the final develop keep making its own.

## Adjust Photo and the other per-color effects: remember each color

A pixel's new color depends only on its old color (red, green, blue). A photo has far fewer different colors than pixels, so each different color can be worked out once and remembered. The result is exactly the same as working out every pixel.

Measured on Leah's CR3 developed to 8192 × 5464 (44.8 million pixels), color sliders only (exposure, brilliance, shadows, contrast, saturation, vibrance, warmth):

- Different colors in the photo: **1,216,377, only 2.7% of the pixels**. After the detail sliders have run: 1,395,896 (3.1%).
- The app today: **628–653 ms**.
- A throwaway prototype using the same per-pixel function, with a 64 MB table (one entry per possible color, cleared each run): **25 ms**, including clearing the table.
- **Output byte-identical to the app's** (content hashes equal).
- Detail sliders only (sharpness, definition, noise reduction): 477 ms. All sliders together: 1,233 ms. The colors step is not the cost when the detail sliders are in use, so the expected total with the memory is about **0.5–0.65 s**, and about **0.35–0.45 s** with the serial-loop fix (recommendation 4) as well. These two totals are estimates.
- Limits to design for: the vignette depends on position, not color, so it can't be remembered; a very noisy photo has more distinct colors and gains less (the worst case should cost little extra, so skip the table for small images or fall back when most colors are new); the table needs thread-safe writes in the real version (the prototype wrote without locks); 64 MB of temporary memory.
- Same trick helps the other per-color effects: Hue/Saturation (167 ms at 45 MP), Sepia, and adjustment layers that bake an effect.
- The earlier "switch to Float" idea is no longer needed for speed. Remembering colors is faster and changes nothing.

## Straighten

**Decision (Leah, 2026-10-10): build option A and option B together.**

- Why it lags: the slider preview is a real history step. Each tick undoes the last one and re-straightens every layer **on the main thread**, so the whole app waits.
- Measured on the CR3 at 45 MP, one layer, 3 degrees, Crop to Fit (output 7604 × 5071): today's rotation **386 ms** (fastest of 3). Three layers earlier: 1.3 s at 45 MP, 333 ms at 12 MP.
- **A. Compute in the background, swap in on the main thread.** Same code, identical pixels. The window stays responsive. Updates are merged so they never queue.
- **B. Rotate with vImage (`vImageAffineWarp_ARGB8888`) instead of the hand-written bilinear loop** (`Warp.rotated`). On the CR3, with the premultiply and unpremultiply steps included: **154 ms** against 386 ms, about **2.5×**. (An earlier single, cold run gave 278 vs 898 ms, about 3×; use 2.5×.) The high-quality flag costs a little more (180 ms) and doesn't improve the match, so leave it off.
- **How different B looks,** compared pixel by pixel with today's rotation on the same photo (every third pixel): mean difference **0.4 out of 255**; 1.9% of pixels differ by more than 2; 0.03% by more than 8; the largest difference is 34, found at the frame's edges. Neither a half-pixel shift of the center nor the quality flag changed this. In short: not visible, but not byte-identical to today's.
- A + B together: roughly 150 ms per layer at 45 MP, with the app responsive.

How to build B (notes for the engineer):
- vImage turns the opposite way to `Warp.rotated`: pass the **negated angle**. (A first try with the wrong sign gave a 33/255 mean difference, which is how it was caught.)
- vImage needs premultiplied pixels: `vImagePremultiplyData_RGBA8888`, warp, then `vImageUnpremultiplyData_RGBA8888`, as `Resampling.swift` already does.
- Fill the corners with `.clear` for Crop to Fit off (Color 2 for a solid background is applied by the caller today; check `Canvas.vacatedFill`).
- The preview and the applied result both use the new code, so they still match each other. This changes Straighten's pixels slightly from before, so: any exact-value Straighten tests in `WarpTests.swift` need new expectations (use a tolerance), and the change should be logged in FRD §23.
- Perspective Correction can't use this: it's a projective warp and vImage's affine warp can't do it. It stays on the current code (421 ms at 45 MP, one-shot, not a slider).
- Drop Shadow and Border share the same "preview as a step" path as Straighten (`Editor.renderDecorationPreview`); doing A for Straighten may let them use it too.

## Serial loops worth fixing (CPU only, same results)

The serial copy loops cost 15 ms (12 MP) and 66 ms (45 MP) each, against 2 ms and 5 ms for a plain row copy. The blur uses two of them, plus another in Sharpen and Adjust Photo, so they're about half of a blur's time.

- **`Effects.blurred`** (copy-in and coverage fill) **and `Effects.applyToRegion`** (copy-back): parallelize, or with no selection use a row copy. This helps blur, Sharpen and Adjust Photo (both its blurs).
- **`Effects.sharpened`**: serial `Double` loop; parallelize.
- **Skew** (`PixelBuffer.skewed`): each row (or column) is independent. Parallelize, vertical pass especially.
- **`SubjectScan.bytes(of:)`, `mask(for:)`, `SubjectActions.select`**: serial full-image loops, small next to Vision (25 / 97 ms per subject).
- **Pointwise effects**: hoist the per-pixel "is this selected" check when there's no selection. Small.
- Not worth doing now: sharp resize (33 ms), a Flatten fast path for opaque pixels (Flatten is already 189 ms at 45 MP), and `vImageTableLookUp` for Levels/Curves (already 9–36 ms).

## Recommendations (final, after Leah's answers)

1. **Develop window: reuse one `CIRAWFilter` for previews.**
   - Measured speedup: about 10× per slider tick (0.42–1.3 s down to about 35–100 ms on the 45 MP CR3); pixels identical.
   - Risk: low. Contained in `RawDeveloper` (app target). One preview at a time under a lock; the final develop still makes its own filter.
   - Architecture change: none. Core Image already does this on the GPU.
2. **Adjust Photo (and other per-color effects): remember each color.**
   - Measured: color part 653 → 25 ms on the CR3, identical output. Whole Adjust Photo with all sliders 1.2 s → about 0.5–0.65 s (estimate), because the detail blurs remain.
   - Risk: low to medium. Exact-match tests make it safe; needs thread-safe table writes, a fallback for noisy photos and a size cutoff.
   - Architecture change: none (CPU only, same results).
3. **Straighten: background preview (A) plus a vImage rotation (B). Leah has chosen both.**
   - Result: the app stays responsive, and each update costs about 150 ms per layer at 45 MP instead of 386 ms.
   - Risk: medium. The preview is a history step today, so the background version must not disturb undo (compute from the original layer buffers, swap results in on the main thread). B changes Straighten's pixels very slightly (mean 0.4/255), so update the Warp tests and log it in FRD §23.
   - Architecture change: none, but it touches how "preview as a step" works (`Editor.renderDecorationPreview`); Drop Shadow and Border share it.
4. **Fix the serial loops (blur copies, Sharpen, Skew), results unchanged.**
   - Estimated (from replica loops; not built): blur 58 → ~30 ms (12 MP), 202 → ~80 ms (45 MP); Sharpen about 3×; Adjust Photo detail part down by ~15–20%; Skew with both directions about 4–5×.
   - Risk: low. Architecture change: none.

Not recommended: any GPU rewrite of blur, flatten, effects or export.

## Open questions for Leah

1. Which of recommendations 1–4 should the engineer session build, and in what order? Claude's suggestion: 1, then 2, then 3 (A and B), then 4.
2. Re-run the three timing scripts on a quiet Mac after each fix to confirm the gain.
