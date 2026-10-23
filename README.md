<p align="center">
  <img src="Docs/Design/App%20Icon%20(as%20macOS%20shows%20it).png" width="128" alt="Colorbee app icon">
</p>

# Colorbee

[![Build and test](https://github.com/ohrealleah-lab/Colorbee/actions/workflows/build-release.yml/badge.svg)](https://github.com/ohrealleah-lab/Colorbee/actions/workflows/build-release.yml)
[![Latest release](https://img.shields.io/github/v/release/ohrealleah-lab/Colorbee?include_prereleases&label=release)](https://github.com/ohrealleah-lab/Colorbee/releases)
![macOS 26](https://img.shields.io/badge/macOS-26-blue)
![Swift 6](https://img.shields.io/badge/Swift-6-orange)

**A native macOS paint program with the immediacy of classic MS Paint, plus redaction, annotation, layers, effects and RAW development.** Swift 6, AppKit and Metal, with no networking at all.
<img width="3248" height="2218" alt="image" src="https://github.com/user-attachments/assets/87007747-2a0e-47df-b58e-3629d027536f" />

### [⬇ Download the latest beta](https://github.com/ohrealleah-lab/Colorbee/releases/latest)

Signed with a Developer ID and notarized by Apple. Needs a Mac with Apple silicon and macOS 26. Download the zip and read "Start Here.txt".

Colorbee is a personal tool, built as a product exercise. I'm the product manager: I wrote the requirements, made every functional decision, directed the visual design and tested each stage by hand. The engineering was done by [Claude Code](https://claude.com/claude-code) working to those requirements. The whole process is in the repo: the requirements, the decision log, the build plan and the engineering rules.

## Tech at a glance

| | |
|---|---|
| Platform | macOS 26+, Apple Silicon only |
| Language | Swift 6 (strict concurrency) |
| UI | AppKit app structure and menus, SwiftUI toolbars and dialogs, a Metal-backed canvas view |
| Architecture | `ColorbeeCore`, a pure Swift package with no UI imports, plus the app target |
| Rendering | CPU-owned BGRA pixel buffers; Metal for display only |
| On-device ML | Apple Vision for text recognition, Remove Background and Select Subject |
| Tests | Swift Testing: 540+ unit tests, app tests that drive the editor, property-based undo tests, a Release-only performance suite |
| CI/CD | GitHub Actions: build and test on every push; a version tag signs, notarizes and publishes a GitHub Release |
| Size | About 26,000 lines of Swift and Metal, plus 8,800 lines of tests |

## How it's built

- **Two layers of code.** `ColorbeeCore` holds the pixel model, history, selections and every tool and effect algorithm, and runs its tests headless. The app target handles input, display and the operating system.
- **The CPU owns the pixels.** Each layer is one page-aligned BGRA buffer with straight alpha. Metal is used only for display: zero-copy textures, compositing, nearest-neighbor zoom up to 3200%, the pixel grid and overlays.
- **Every edit goes through history**, using the command pattern with tile-level before-images (256-pixel tiles), so undo is exact. History works within a memory budget and compresses older steps to disk.
- **Performance targets:** under 16 ms from input to frame, scanline fill and magic wand algorithms instead of recursion, whole-image work on all cores, and saving in the background. A separate Release-only suite (`make perf`) sets time limits and runs an 8000 × 8000 soak test.
- **Tested at several levels:** exact pixel values on small images, property tests that run random edits, undo them all and check the image is unchanged, and app tests that drive the editor the way the canvas does.
- **Privacy by construction.** Everything runs on the Mac. Auto-Redact, Remove Background and Select Subject use on-device Vision.

## What it does

- **Paint and draw.** Pencil, nine brushes with pressure support, eraser and color eraser, flood fill, eyedropper, 24 editable shapes, five gradient types, text, symmetry drawing, a measure tool, Clone Stamp and Remove Red-Eye. Left-click paints with Color 1 and right-click with Color 2, as in Paint.
- **Layers.** 17 blend modes, opacity, locking, merge and flatten, non-destructive adjustment layers, and Undo on Active Layer. Layered images save as a `.colorproj` project.
- **Select and transform.** Rectangle, ellipse, lasso and magic wand selections that add, subtract and intersect, with feathered edges. Floating selections move, duplicate and resize before they're placed. Crop, rotate, flip, Straighten and Perspective Correction.
- **Redact.** Blur, pixelate and solid fill per region, plus a Redact Brush. **Auto-Redact** finds email addresses, phone numbers, credit card numbers (checksum-verified), API keys, IP addresses and URLs on every page, then lets you review and hide them as one undo step. After saving, Colorbee offers to remove earlier file versions, the undo history and the unredacted image in Clipboard History.
- **Annotate.** Step Badges, arrows, shapes and text, plus Copy Text to lift text out of a screenshot.
- **Pages and PDFs.** Open a PDF and every page appears in a sidebar, each with its own layers and undo. Multi-page TIFFs and animated GIFs open the same way. **Export as PDF** writes pixels only, with no metadata and no hidden text under a redaction.
- **RAW photos.** Opens camera RAW (Canon CR3, Sony ARW, Nikon NEF, Fujifilm RAF, DNG) through a **Develop** window built on macOS's RAW engine, before the photo becomes an editable Display P3 image.
- **Photo editing.** Levels, Curves, an Adjust Photo panel modeled on the iPhone Photos editor, filters, Remove and Spot Heal, Remove Background and Select Subject, Drop Shadow and Border.
- **Compare.** Before/After shows the image against how it was opened or last saved, as a split view or side by side.
- **Files.** PNG, JPEG, HEIC, TIFF, GIF, BMP, WebP, PDF and camera RAW. Each image keeps its color profile. Autosave, versions and window restoration come from the standard macOS document model.
- **Make it yours.** Light, Dark or System appearance, custom colors, text styles, export presets, and a keyboard shortcut editor that knows which shortcuts macOS has already taken on this Mac. A built-in Help Book works offline.

## Status

Built in stages, each working end to end before the next starts, and tested by hand at every stage. Built so far: the core editor and tools, layers, redaction, integration, hardening, photo editing, pages and PDFs, RAW photos, Copy Text, Step Badges, Match Surroundings, Clone Stamp, soft selections and the Help Book. Between stages, five rounds of independent code review have looked for bugs, and a sixth checked every help page against the code, with every finding verified and its fix tested. The current beta is 0.9.0 (build 7). See [Docs/STATUS.md](Docs/STATUS.md).

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

## Building from source

Requires macOS 26, Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). The `.xcodeproj` is generated from `project.yml` and isn't committed; the make targets below generate it for you.

```bash
make run      # Release build, then launch
make test     # core unit tests plus the app build and app tests
make perf     # Release-only time limits and the 8000 x 8000 soak test (a few minutes)
make beta     # signed, notarized beta zip (needs a Developer ID certificate)
```

## License

[PolyForm Noncommercial 1.0.0](LICENSE). Free to use, copy and modify for noncommercial purposes.
