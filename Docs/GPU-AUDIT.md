# GPU acceleration audit

_Written 2026-10-10 for Leah; updated the same day with her answers, real timings and a timing of her CR3._ **A proposal for Leah to decide, not a plan.** No Colorbee code was changed._

## Bottom line

**Nothing needs the GPU, and Leah's answers rule it out anyway.** Measured on her M2 Max, every everyday edit on a 12 MP phone photo takes 10–330 ms. The slowest edits on a 45 MP photo take 1.2–1.3 s. Leah also said previews must match the applied result, and a GPU can't give that for most of this code (Metal has no `Double`).

**The one real lag is the RAW Develop window's sliders**, as Leah reported. It is not a missing-GPU problem: Core Image already uses the GPU. Each slider tick builds a brand-new `CIRAWFilter` and so re-reads the RAW file (about 0.4–1.3 s per tick on her 45 MP CR3). Reusing one filter for previews cut every Develop slider to about 35–100 ms, with identical pixels (recommendation 1). It is a small change in the app target.

After that, a small CPU-only cleanup of serial loops (recommendation 2). Neither needs an architecture change.

## Leah's answers (2026-10-10)

1. Sliders aren't laggy, except **on a big RAW photo in the Develop window**, where they lag. She supplied a 45 MP Canon CR3 (`7762545337.cr3`, 8192 × 5464) to time.
2. Her normal photo is a 12 MP iPhone shot; 45 MP RAW photos will happen.
3. A preview must be the same as the applied result. This rules out GPU previews, since the GPU would give slightly different pixels. The adjustment-layer shaders already differ slightly from the CPU code.
4. Timing runs approved.

## How the timings were made

- A throwaway Swift Testing file ran in Release on Leah's M2 Max. It is saved as [GPU-AUDIT-timing.txt](GPU-AUDIT-timing.txt) so it can be re-run after any speedup. It is not part of the test suite.
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

## Serial loops worth fixing (CPU only, same results)

The serial copy loops cost 15 ms (12 MP) and 66 ms (45 MP) each, against 2 ms and 5 ms for a plain row copy. The blur uses two of them, plus another in Sharpen and Adjust Photo, so they're about half of a blur's time.

- **`Effects.blurred`** (copy-in and coverage fill) **and `Effects.applyToRegion`** (copy-back): parallelize, or with no selection use a row copy. This helps blur, Sharpen and Adjust Photo (both its blurs).
- **`Effects.sharpened`**: serial `Double` loop; parallelize.
- **Skew** (`PixelBuffer.skewed`): each row (or column) is independent. Parallelize, vertical pass especially.
- **`SubjectScan.bytes(of:)`, `mask(for:)`, `SubjectActions.select`**: serial full-image loops, small next to Vision (25 / 97 ms per subject).
- **Pointwise effects**: hoist the per-pixel "is this selected" check when there's no selection. Small.
- Not worth doing now: sharp resize (33 ms), a Flatten fast path for opaque pixels (Flatten is already 189 ms at 45 MP), and `vImageTableLookUp` for Levels/Curves (already 9–36 ms).

## Recommendations (revised again)

1. **Develop window: reuse one `CIRAWFilter` for previews.**
   - Measured speedup: about 10× per slider tick (0.42–1.3 s down to about 35–100 ms on the 45 MP CR3); pixels identical.
   - Risk: low. It's contained in `RawDeveloper` (app target). Care points: one preview at a time under a lock, and the final develop still makes its own filter.
   - Architecture change: none. Core Image already does this on the GPU.
   - This is the one thing Leah has actually felt, so do this first.
2. **Fix the serial loops (blur copies, Sharpen, Skew), results unchanged.**
   - Estimated speedup (from the replica loop timings; not yet built): blur 58 → ~30 ms (12 MP), 202 → ~80 ms (45 MP); Sharpen about 3× (107 → ~35 ms, 399 → ~120 ms); Adjust Photo about 15–20% (1,200 → ~1,000 ms at 45 MP); Skew with both directions about 4–5× (1,250 → ~300 ms at 45 MP).
   - Risk: low. Existing exact-value tests cover the pixels.
   - Architecture change: none.
   - Honest value: small at 12 MP, where nothing is slow. It matters for 45 MP photos. Low priority.
3. **Straighten's slider preview runs on the main thread.** About 110–330 ms per tick at 12 MP and 0.4–1.3 s at 45 MP, against the rule that the main thread never blocks for more than a frame. The fix would be to run it in the background with updates merged, as effect previews do, which keeps the preview identical. Only worth doing if Leah finds it laggy on a big or multi-layer photo (question 1).
4. **Adjust Photo at 45 MP** takes about 1.2 s per slider update. Leave it unless it bothers Leah. A faster option is the `Float` change, explained below; it needs Leah's decision and the audit does not recommend it by default.

**What "switch to Float" means, in plain words.** Adjust Photo works out each pixel's new color with very precise numbers (`Double`, about 15–16 digits). The Mac's chip can do the same sums on less precise numbers (`Float`, about 7 digits) roughly twice as fast. The end result is rounded to a whole number from 0 to 255, so almost every pixel comes out exactly the same. A few pixels sitting right on a rounding edge would land one step (1 out of 255) different, which nobody can see. The preview and the applied result would both use the same new math, so they would still match each other. The catches: a photo edited in an older version would come out one step different in a few pixels if re-applied, and the screen shader for adjustment layers would match the CPU a little less closely or more closely than now, which would have to be checked. The expected gain is small (Adjust Photo would drop by perhaps a third at most), so it is not worth doing unless 1.2 s on 45 MP bothers Leah.

Not recommended: any GPU rewrite of blur, flatten, effects or export.

## Open questions for Leah

1. Have you tried Straighten on a 45 MP photo, or on a 12 MP photo with several layers? That is the one canvas slider path measured at more than a frame on the main thread.
2. Is about 1.2 s per Adjust Photo update on a 45 MP photo acceptable? If not, are you open to the one-step `Float` change?
3. Do you want recommendation 2 (the serial loops) done now, or left until a 45 MP photo actually feels slow? I'd lean toward waiting.
4. Open on a quiet Mac: the CR3 numbers above were taken while other things were running. Re-run [GPU-AUDIT-raw-timing.txt](GPU-AUDIT-raw-timing.txt) after fix 1 to confirm the gain.
