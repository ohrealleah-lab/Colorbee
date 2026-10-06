<p align="center">
  <img src="Docs/Design/App%20Icon%20(as%20macOS%20shows%20it).png" width="128" alt="Colorbee app icon">
</p>

# Colorbee

A native macOS paint program with the immediacy of classic MS Paint, plus the editing tools a product manager reaches for every day: redacting screenshots and PDFs, annotating, cropping, comparing and exporting, and developing camera RAW photos.

Colorbee is a personal tool, built as a product exercise. I'm the product manager: I wrote the requirements, made every functional decision, directed the visual design and tested each stage by hand. The engineering was done by [Claude Code](https://claude.com/claude-code) working to those requirements. The whole process is in the repo: the requirements, the decision log, the build plan and the engineering rules.

## What it does

**Paint and draw.** Pencil, nine brushes (round, two calligraphy pens, airbrush, oil, crayon, marker, natural pencil, watercolor) with pressure from a Force Touch trackpad or pen, eraser and color eraser, flood fill, eyedropper, 24 shapes that stay editable (move, resize, rotate) until placed, gradients (linear, radial, reflected, diamond, conical), text with styles, symmetry drawing and a measure tool. Left-click paints with Color 1 and right-click with Color 2, as in Paint.

**Layers.** Blend modes (17, with the W3C math on screen and in exports), opacity, locking, merge and flatten, and non-destructive adjustment layers. Undo on Active Layer takes back one layer's last change while leaving the others alone. Layered images save as a `.colorproj` project.

**Select and transform.** Rectangle, ellipse, lasso and magic wand selections that add, subtract and intersect. Floating selections can be moved, duplicated, resized with handles and placed. Crop, rotate and flip apply to the selection or the whole image.

**Redact.** Gaussian blur, pixelate and solid fill, applied to each selected region separately, on every layer under it. **Auto-Redact** uses on-device text recognition (Apple Vision) to find email addresses, phone numbers, credit card numbers (checksum-verified), API keys, IP addresses and URLs on every page, then lets you review and hide them, undone as one step. Colorbee also looks after the copies a redaction can leave behind: after saving it offers to remove the file's earlier versions and the undo history, and to clear the unredacted image from Clipboard History. Nothing leaves the Mac; the app has no networking at all.

**Pages and PDFs.** Open a PDF and every page appears in a sidebar, rendered at 150, 200 or 300 DPI; multi-page TIFFs and animated GIFs open the same way. Add, duplicate, delete and reorder pages; each page keeps its own layers and undo. Pages you're not looking at are kept compressed, so a long document stays light. **Export as PDF** writes every page losslessly with no metadata at all (no title, author, app name or dates), and as pixels only, so no hidden text survives under a redaction. Any document can have pages, so screenshots can become a PDF.

**RAW photos.** Opens camera RAW files (Canon CR3, Sony ARW, Nikon NEF, Fujifilm RAF, DNG) with macOS's own RAW engine, through a **Develop** window: exposure, highlight recovery, shadows, contrast, white balance, noise reduction, sharpness and lens correction, at RAW precision, before the photo becomes an editable Display P3 image. Export can include the camera details (camera, lens, ISO, shutter, aperture), off at first, and never location, serial numbers or the owner's name.

**Adjust and compare.** Brightness/contrast, hue/saturation, invert, desaturate and sharpen with live previews. Before/After compares the image with how it was opened or last saved, as a split view or side by side.

**Files.** Opens PNG, JPEG, HEIC, TIFF, GIF, BMP, WebP, PDF and camera RAW. Keeps each image's color profile (Display P3 screenshots stay P3). Autosave, versions and window restoration come from the standard macOS document model; Save and Export each remember the format you last chose. Export presets show the exact output size.

**History.** Unlimited undo, with a History panel to jump to any step. It stores only the changed 256-pixel tiles, works within a memory budget, and compresses older steps (and layers only undo can bring back) to disk.

**Photo editing.** Levels, Curves, an Adjust Photo panel modeled on the iPhone Photos editor (fifteen sliders, Auto, nine filters plus your own), Straighten, Perspective Correction, Crop with aspect and pixel-size presets, Drop Shadow and Border that follow an object's shape, and Remove Background and Select Subject using on-device Vision.

**Make it yours.** Light, Dark or System appearance, custom colors, text styles, export presets, number fields you can drag to change, and a keyboard shortcut editor that knows which shortcuts macOS has already taken on this Mac.

## How it's built

- **Swift 6 and macOS 26**, Apple Silicon only. AppKit for the app's structure and menus, SwiftUI for toolbars and dialogs.
- **Two layers of code.** `ColorbeeCore` is a pure Swift package with no UI imports. It holds the pixel model, history, selections and every tool and effect algorithm, and it runs its tests headless. The app target handles input, display and the operating system.
- **The CPU owns the pixels.** Each layer is one page-aligned BGRA buffer with straight alpha. Metal is used only for display: zero-copy textures, compositing, nearest-neighbor zoom up to 3200%, the pixel grid and overlays.
- **Every edit goes through history**, using the command pattern with tile-level before-images, so undo is exact.
- **Performance targets:** under 16 ms from input to frame, scanline fill and magic wand algorithms instead of recursion, whole-image work on all cores, and saving in the background. In the 8000 × 8000 soak test (up to five layers), no step takes a second.
- **Tests:** 434 unit tests in Swift Testing, including exact pixel values on small images and property tests that run random edits, undo them all and check the image is unchanged. A separate Release-only suite (`make perf`) sets time limits and runs an 8000 × 8000 soak test.
- **Continuous integration:** GitHub Actions builds and tests every push on a macOS 26 runner. A version tag also signs Colorbee with a Developer ID, has Apple notarize it, and publishes it as a GitHub Release.

About 22,000 lines of Swift and Metal, plus 5,600 lines of tests.

## Status

Built in stages, each working end to end before the next starts, and tested by hand at every stage. Built so far: the core editor and tools, layers, redaction, integration, hardening (performance, memory, accessibility), photo editing, pages and PDFs (stage 10) and RAW photos (stage 12). Next: importing scans and photos straight from an iPhone (stage 11, planned). Between stages, independent code reviews (four rounds so far) look for bugs, with every finding verified and its fix tested. Betas are signed and notarized. See [Docs/STATUS.md](Docs/STATUS.md).

## Download

Betas are published as [GitHub Releases](https://github.com/ohrealleah-lab/Colorbee/releases), marked as pre-releases. Download the zip and read "Start Here.txt". Colorbee needs a Mac with Apple silicon and macOS 26.

## The product docs

| Document | What it is |
|---|---|
| [Docs/FRD.md](Docs/FRD.md) | Functional requirements: the single source of truth, including a dated decision log (§23) |
| [Docs/STATUS.md](Docs/STATUS.md) | What's built, what's next, and how we work |
| [CLAUDE.md](CLAUDE.md) | Engineering rules: architecture, performance and code conventions |
| [Docs/Design/](Docs/Design/) | Visual mockups for the interface |
| [Docs/Review/](Docs/Review/) | Code review plans, findings and what was done about each |
| [Docs/Proposals/](Docs/Proposals/) | Feature proposals written up for decisions |
| [Docs/reference/](Docs/reference/) | The original v1 spec the FRD grew from |

## Building

Requires macOS 26, Xcode 26 (with the Metal Toolchain component) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
make run      # Release build, then launch
make test     # unit tests plus a full app build
make beta     # signed, notarized beta zip (needs a Developer ID certificate)
```
