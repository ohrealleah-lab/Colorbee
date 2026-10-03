<p align="center">
  <img src="Docs/Design/App%20Icon%20(as%20macOS%20shows%20it).png" width="128" alt="Colorbee app icon">
</p>

# Colorbee

A native macOS paint program with the immediacy of classic MS Paint, plus the editing tools a product manager reaches for every day: redacting screenshots, annotating, cropping, comparing and exporting.

Colorbee is a personal tool, built as a product exercise. I'm the product manager: I wrote the requirements, made every functional decision, directed the visual design and tested each stage by hand. The engineering was done by [Claude Code](https://claude.com/claude-code) working to those requirements. The whole process is in the repo: the requirements, the decision log, the build plan and the engineering rules.

## What it does

**Paint and draw.** Pencil, nine brushes (round, calligraphy, airbrush, oil, crayon, marker, natural pencil, watercolor) with pressure from a Force Touch trackpad or pen, eraser and color eraser, flood fill, eyedropper, 24 shapes that stay editable (move, resize, rotate) until placed, gradients (linear, radial, reflected, diamond, conical), text with styles, symmetry drawing and a measure tool. Left-click paints with Color 1 and right-click with Color 2, as in Paint.

**Layers.** Blend modes (17, with the W3C math on screen and in exports), opacity, locking, merge and flatten, and non-destructive adjustment layers. Undo on Active Layer takes back one layer's last change while leaving the others alone. Layered images save as a `.colorproj` project.

**Select and transform.** Rectangle, ellipse, lasso and magic wand selections that add, subtract and intersect. Floating selections can be moved, duplicated, resized with handles and placed. Crop, rotate and flip apply to the selection or the whole image.

**Redact.** Gaussian blur, pixelate and solid fill, applied to each selected region separately. **Auto-Redact** uses on-device text recognition (Apple Vision) to find email addresses, phone numbers, credit card numbers (checksum-verified), API keys, IP addresses and URLs, then lets you review and hide them. Nothing leaves the Mac; the app has no networking at all.

**Adjust and compare.** Brightness/contrast, hue/saturation, invert, desaturate and sharpen with live previews. Before/After compares the image with how it was opened or last saved, as a split view or side by side.

**Files.** Opens PNG, JPEG, HEIC, TIFF, GIF, BMP and WebP. Keeps each image's color profile (Display P3 screenshots stay P3). Autosave, versions and window restoration come from the standard macOS document model. Export presets show the exact output size.

**History.** Unlimited undo, with a History panel to jump to any step. It stores only the changed 256-pixel tiles, works within a memory budget, and compresses older steps (and layers only undo can bring back) to disk.

**Photo editing.** Levels, Curves, an Adjust Photo panel modeled on the iPhone Photos editor (fifteen sliders, Auto, nine filters plus your own), Straighten, Perspective Correction, Crop with aspect and pixel-size presets, Drop Shadow and Border that follow an object's shape, and Remove Background and Select Subject using on-device Vision.

**Make it yours.** Palettes, custom colors, text styles, export presets, and a keyboard shortcut editor that knows which shortcuts macOS has already taken on this Mac.

## How it's built

- **Swift 6 and macOS 26**, Apple Silicon only. AppKit for the app's structure and menus, SwiftUI for toolbars and dialogs.
- **Two layers of code.** `ColorbeeCore` is a pure Swift package with no UI imports. It holds the pixel model, history, selections and every tool and effect algorithm, and it runs its tests headless. The app target handles input, display and the operating system.
- **The CPU owns the pixels.** Each layer is one page-aligned BGRA buffer with straight alpha. Metal is used only for display: zero-copy textures, compositing, nearest-neighbor zoom up to 3200%, the pixel grid and overlays.
- **Every edit goes through history**, using the command pattern with tile-level before-images, so undo is exact.
- **Performance targets:** under 16 ms from input to frame, scanline fill and magic wand algorithms instead of recursion, whole-image work on all cores, and saving in the background. In the 8000 × 8000 soak test (up to five layers), no step takes a second.
- **Tests:** 335 unit tests in Swift Testing, including exact pixel values on small images and property tests that run random edits, undo them all and check the image is unchanged. A separate Release-only suite (`make perf`) sets time limits and runs an 8000 × 8000 soak test.

About 15,000 lines of Swift, plus 3,000 lines of tests.

## Status

Built in stages, each working end to end before the next starts. All nine stages are built and tested by hand, including hardening (performance, memory, accessibility, a signed and notarized beta) and photo editing. See [Docs/STATUS.md](Docs/STATUS.md).

## The product docs

| Document | What it is |
|---|---|
| [Docs/FRD.md](Docs/FRD.md) | Functional requirements: the single source of truth, including a dated decision log (§23) |
| [Docs/STATUS.md](Docs/STATUS.md) | What's built, what's next, and how we work |
| [CLAUDE.md](CLAUDE.md) | Engineering rules: architecture, performance and code conventions |
| [Docs/Design/](Docs/Design/) | Visual mockups for the interface |
| [Docs/reference/](Docs/reference/) | The original v1 spec the FRD grew from |

## Building

Requires macOS 26, Xcode 26 (with the Metal Toolchain component) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
make run      # Release build, then launch
make test     # unit tests plus a full app build
```
