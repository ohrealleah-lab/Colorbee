# GPU acceleration audit

_Written 2026-10-10 for Leah. **A proposal for Leah to decide, not a plan.** No code was changed and nothing heavy was run._

**Read this before acting on it:**
- The audit was read at commit `7c85d0c`. Since then `Effects.swift`, `Canvas.swift`, `SelectionMask.swift`, `Subjects.swift` and `Editor.swift` changed (stage 13: soft-edged selections, Redact Brush). Line numbers below are from the old state; re-find each loop by name, and check that the soft-edge selection work didn't already change it.
- "Measured" means the `PerformanceTests` limits (set at about 2× the real time) and the soak logs in `build/soak-results*.txt`, at 8000 × 8000 (64 megapixels) on Leah's M2 Max. "Est." means a guess from reading the code, not timed.
- CLAUDE.md's architecture (the CPU owns the pixels; Metal is for display only) is locked. Nothing here needs it changed except where a row says so.

## The main finding

The cost of copying pixels to the GPU is mostly not the problem. On Apple Silicon memory is shared, and Colorbee already gives layer buffers to Metal without copying (`Renderer.texture(for:)`, `bytesNoCopy`). The real obstacles to a GPU path:

- **Exactness.** Metal has no `Double`. The CPU effects use `Double`, so a GPU result would differ in the last bit.
- **The screen and export already differ slightly.** The screen composites in half floats, export in Float32. A GPU flatten would change some exported bytes.
- **Size limits.** Apple GPUs cap textures at 16,384 px; Colorbee allows 30,000.
- **Memory.** A GPU path needs extra temporary buffers, a worry after the 30-minute soak crashed the Mac (STATUS.md).
- **Upkeep.** Every GPU path is a second copy of an algorithm to keep in step with the CPU one.

## Table

| Area | Uses now | How slow | GPU worth it? | Why |
|---|---|---|---|---|
| Display (`Renderer`, `Shaders.metal`) | Metal already, MPS blur | Real time | Already GPU | Nothing to add. |
| Flatten / `Canvas.composite` (export, merge, Copy Merged) | `ParallelRows`, Float32 SIMD | ~0.4 s (limit 0.8 s); worst 2.3 s in the soak | No | A GPU version would change some exported bytes. |
| Adjustment layers baked in (`Compositing.adjust`) | Copy plus `ParallelRows` | Adds to the effect's time | No | The screen already does this on the GPU. |
| Gaussian blur | vImage box blur ×3, plus serial copy loops | 0.45–0.95 s | No | A GPU Gaussian would look different from today's box blur. The serial loops are the cheap fix. |
| Sharpen | Blur plus a serial `Double` loop | 0.4–1.4 s (slowest effect in the soak) | No | Cheap CPU fix. |
| Invert, Brightness/Contrast, Hue/Sat, Levels, Curves, Sepia, Posterize | `ParallelRows`, closure per pixel | ~0.3 s (limit 0.6 s); tens of ms at 12 MP (est.) | No | `Double` math can't match bit for bit. Already fast. |
| Adjust Photo (apply) | `ParallelRows`, many `pow()` calls, 1–2 blurs | Not measured; est. 1–2 s at 64 MP, 0.2–0.4 s at 12 MP | Maybe | Heaviest per-pixel code, and it has no perf test. |
| Live slider previews (blur, Adjust Photo, Levels…) | CPU in a background task, copying the whole layer every tick (`EffectPreview.render`) | Est. 50–400 ms per tick at 12 MP | Yes, preview only | The adjustment-layer shaders already exist. Apply stays on the CPU. |
| Straighten / Drop Shadow / Border previews | A real history step, undone and redone every tick, on the main thread (`Editor.renderDecorationPreview`) | Not measured; likely laggy with several layers (est.) | Maybe, preview only | Needs fixing either way. |
| Straighten / Perspective apply (`Warp`) | `ParallelRows`, bilinear | Est. 0.1–0.3 s per 12 MP layer | No | GPU bilinear uses coarser weights, so it wouldn't match. |
| Resize (smooth) | vImage Lanczos | Fast | No | Already Accelerate. |
| Resize (sharp / nearest) | Serial loop, two divides per pixel | Est. 0.2–0.3 s at 64 MP | No | Cheap CPU fix. |
| Skew (`ResizeSkew.skewed`) | Serial `Double` loop, divide per pixel | Est. 1–3 s at 64 MP | No | The biggest unparallelized loop. |
| Remove Background / Select Subject | Vision, plus a serial mask conversion | Mostly Vision (a second or more); conversion est. 50–200 ms | Already accelerated | Vision uses the Neural Engine and GPU. |
| Auto-Redact | Vision text recognition, one tile at a time | Mostly Vision | Already accelerated | Tiles could possibly run side by side. Unsure it helps. |
| PDF export | `ParallelRows` flatten, Apple zlib per page, pages in parallel | Est. 0.2–0.5 s per page at 200–300 DPI | No | Compression isn't GPU work. |
| RAW develop | Core Image, Metal-backed | A few seconds for a big file | Already GPU | A fresh `CIRAWFilter` per preview may repeat work. Measure first. |
| Fill, Magic Wand, undo, history spill | Scanline fill, LZ4 on all cores | 0.3–0.4 s; worst undo 0.33 s | No | Sequential or compression work. |

At 1080p everything meets NFR-6 (100 ms), so nothing there needs help.

## Cheap wins without touching the architecture

Each should give identical results, so the existing tests would catch any difference.

- **Sharpen's loop** (`Effects.sharpened`): serial, so parallelize it.
- **Blur and effect copy loops** (`Effects.applyToRegion` copy-back; `Effects.blurred` copy-in and coverage fill): serial, checking the selection pixel by pixel. With no selection a plain row copy would do.
- **Skew** (`PixelBuffer.skewed`): each row or column is independent, so `ParallelRows` fits.
- **Sharp resize** (`PixelBuffer.resampled`, nearest-neighbor case): precompute the column lookups and parallelize.
- **Subject mask conversion** (`SubjectScan.bytes(of:)`, `mask(for:)`, `SubjectActions.select`): serial full-image loops.
- **Pointwise effects** (`Effects.applyToRegion`): hoist the "is this pixel selected" check out of the loop when there's no selection.
- **Levels, Curves, Posterize, Invert**: `vImageTableLookUp` is bit-exact, but only about 2–3× on code that's already fast.
- **Flatten** (`Canvas.compositePixels`): a fast path for fully opaque Normal pixels, which round-trip exactly.
- **`PixelBuffer.hasTransparency`**: a serial full scan on every open. Minor.

## Top 3 recommendations

1. **Parallelize the serial loops (Sharpen, Skew, blur copies, sharp resize, subject mask).**
   - Speedup: Sharpen ~2–3×, whole-layer blur 20–35% faster, Skew ~6–8×, sharp resize ~5× (est.).
   - Risk: low, since results are identical.
   - Architecture change: none.
2. **Preview on the GPU, apply on the CPU.**
   - What: live slider previews use the existing adjustment-layer shaders. Straighten could preview as a rotated quad. Apply still runs the exact CPU code through history.
   - Speedup: a slider tick goes from hundreds of milliseconds (est.) to one frame.
   - Risk: medium. The preview would differ slightly from the applied result (blur softness, tiny color steps). Straighten also needs its main-thread problem fixed.
   - Architecture change: probably none, since the CPU still owns the pixels. It is a behavior change, so it needs Leah's decision and a note in FRD §23. Time the current previews before building anything.
3. **Flatten fast paths for opaque pixels.**
   - Speedup: ~1.5–2× on typical photo stacks (est.). Flatten is the most common slowest step in the soak logs.
   - Risk: low, with exact-match tests.
   - Architecture change: none.

Not recommended: a GPU rewrite of blur, flatten or export. It would need an architecture change for little gain and would break exact-match output.

## Open questions for Leah

1. Do slider previews feel laggy today on real photos? Which ones: Adjust Photo, Levels, blur or Straighten? That decides whether #2 is worth doing.
2. What sizes does Leah usually edit, 12 MP phone shots or 45 MP RAW? 8000 × 8000 is a stress case.
3. May a preview differ slightly from the applied result? If it must be pixel-identical, GPU previews are out.
4. May Claude time Adjust Photo, Straighten, Skew and Sharpen in Release at 12 MP (about 30 seconds, under 1 GB, not `make perf`)? A throwaway timing script, no repo changes.
