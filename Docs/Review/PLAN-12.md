# Code review round 11: refactoring and reuse (sessions AB, AC, AD, AE)

Every round so far looked for bugs. This one asks a different question (Leah, 2026-10-31): **where would the code be
safer to change if it were organized differently, and where does code redo something that already exists?** It covers
the whole app at commit `08094b72da6bb45f122b342dd285728849008e7b`, about 35,000 lines.

Leah's answers: the whole app; what matters most is **making later changes safe** (one place to fix, nothing to drift
apart), not looks; any size of change is open **if it's worth it**, including restructuring the Editor.

## Rules

- Run locally in Leah's Colorbee folder. **Don't touch git. Don't change any file except your findings file,**
  `Docs/Review/findings-<letters>.md`. Don't build, run the app or run tests: reason from the code. Quick throwaway
  scripts in the scratch folder are fine (a search for repeated lines, say).
- Never open Leah's personal files (Downloads, Desktop, Documents, Pictures).
- Read `CLAUDE.md` first. Its "Architecture (locked)" section is deliberate: the core has no AppKit, SwiftUI or Metal;
  the CPU owns the pixels; all document changes go through `History`; selections live in `SelectionActions`. Suggest
  changing one of those only with a strong reason, and say plainly that you are.
- FRD §23 decisions are intended behavior. Don't suggest features or behavior changes. A refactor must leave every
  picture, file and step exactly as it is.
- **Don't re-report bugs.** If two copies of the same logic already disagree, that's worth reporting: say so first,
  under "Copies that already differ", since one of them may be a bug. Leah decides.

## What to look for

1. **Already there:** code that rebuilds something the codebase already has (a core helper, an extension, a type), or
   something macOS already does (Accelerate/vImage, Core Graphics, Foundation). Name the existing one, with its file and
   line.
2. **Copies:** the same logic written two or more times (pixel loops, luma and HSL math, blur passes, undo/commit
   patterns, settings stores, panel rows, Codable boilerplate), where a fix to one would have to be remembered in the
   others. Most dangerous: a rule that the core and the shader, or the export and the screen, must both follow.
3. **Hard to change safely:** functions too long to hold in your head, state spread over many properties that must
   change together, a file doing several unrelated jobs, hidden order dependencies, and code paths no test reaches
   (`Docs/STATUS.md` lists the test files).
4. **Dead or leftover code:** unused functions, settings or branches; code from removed features (stage 11, Import
   from iPhone, was deleted on 2026-10-19).

Skip style nits (naming, spacing, comment wording) unless they hide a real problem.

## Findings file format

```markdown
# Review <letters>: <area>
Reviewed at commit: 08094b72da6bb45f122b342dd285728849008e7b
Checked: <one line per file or topic you covered>

## Copies that already differ
(Any copies that disagree today, each with both places and what differs. "None found" if none.)

## <n>. <one-line summary>
- **Worth:** High (removes a real risk of a later fix being missed, or makes a big file workable) · Medium · Low
- **Kind:** Already there · Copies · Hard to change · Dead code
- **Size:** Small (under an hour) · Medium (a few hours) · Large (a day or more)
- **Risk:** what could break while doing it, and which existing tests would catch it (name them) or what new test would
  be needed first.
- **Where:** `path/to/File.swift:123` and every other place involved.
- **What:** the problem, plainly, with the code quoted briefly.
- **Suggested change:** the shape of the refactor, in a few lines. Not the full code.
```

Order findings by Worth, then smallest Size first. Keep it to what's genuinely worth doing: ten strong findings are
better than forty weak ones.

---

## Session AB: the Editor

`Sources/Colorbee/Editor.swift` (5,600 lines), and how `CanvasView.swift`, `DocumentView.swift` and
`DocumentWindow.swift` call it.

- Whether and how to split it: by its `// MARK:` sections into extensions in their own files, or into smaller objects
  (the pending-objects state, the effect session, Auto-Redact, Before/After, pages). Say what each piece would own and
  which properties cross between them; weigh Swift's rule that stored properties can't live in extensions.
- Session state that must be reset together (for example `beginEffect`, `finishInteractions`, the effect preview's
  generation counters and flags): could it be one value that's replaced whole?
- Logic in the Editor that belongs in the core, where it could be unit-tested headless (the architecture asks for
  this), or that the core already has (`SelectionActions`, `LayerActions`, `ImageActions`, `Canvas`).
- Repeated command shapes (`layerCommand`, `chosenLayerSetting`, `performSelectionCommand`, `recordingChanges`,
  refusal messages): one pattern or several near-copies?

## Session AC: the rest of the app

Everything in `Sources/Colorbee/` except `Editor.swift`: the canvas view, `Renderer.swift` and `Shaders.metal`, the
document and window classes, menus and shortcuts, the panels and sheets (Adjust Photo, Layers, Adjustments, History,
Develop, Settings), and the stores that save things (`FilterStore`, `PhotoSettingsStore`, `CustomColors`,
`ClipboardHistory`, `ShortcutStore`, `TextStyles`, `Palettes`, `SettingsFolder`).

- The stores: one shared way to load and save, or several near-copies with different error handling?
- `Renderer.encode`: the "end the pass, blur, resume" and "isolate, draw, blend back" steps appear several times.
- SwiftUI rows, sliders and section headings repeated across panels.
- The shader against the core: each rule both must follow (blend modes, Adjust Photo, masks, vignette and grain).
  Is each written once per side with a comment pointing at its twin? List any that aren't.

## Session AD: the core's pixels and effects

`Packages/ColorbeeCore/Sources/ColorbeeCore/`: `Effects*.swift`, `Photo*.swift`, `ColorMixer`, `ColorGrading`,
`PointColors`, `ToneCurve`, `Curves`, `Levels`, `ColorLook`, `ColorLookup`, `CubeFile`, `WhiteBalance`, `Histogram`,
`Compositing`, `AdjustmentCompositing`, `BlendMode`, `Resampling`, `Warp`, `ResizeSkew`, the brushes and strokes
(`Brush`, `BrushStroke`, `RoundBrushStroke`, `RetouchStroke`, `DabWalker`, `CoveragePainter`, `StrokePath`),
`FloodFill`, `MatchSurroundings`, `RedEye`, `SelectionMask*`, `ColorRange`, `LuminanceRange`, `GraduatedSelection`,
`ParallelRows`, `Pixel`, `PixelBuffer`.

- Color math written more than once: luma, HSL conversions, smoothstep, premultiply and unpremultiply, straight-alpha
  blending, rounding and clamping to `UInt8`.
- Whole-image loops that don't use `ParallelRows` or vImage where they could, or that each hand-roll the same band
  setup.
- Blurs: how many separate Gaussian or box blur implementations exist, and could they be one?
- The several stroke types: what they share and whether a common base would make a fix land everywhere.

## Session AE: the core's model, history and files

`Packages/ColorbeeCore/Sources/ColorbeeCore/`: `Canvas*.swift`, `Layer*.swift`, `LayerActions*.swift`, `LayerAlign`,
`LayerPixels`, `History*.swift`, `HistorySnapshot`, `SelectionActions`, `FloatingSelection`, `ImageActions`,
`Orientation`, `Geometry`, `Trim`, `CanvasAnchor`, `Page`, `PageStack`, `PDFPages`, `PDFWriter`, `ProjectFile`,
`ImageCodec`, `ExportPreset`, `ExportColor`, `DocumentInfo`, `CameraDetails`, `AutoRedact*`, `FaceFinder`,
`RectangleFinder`, `TextReader`, `TextLayer`, `TextRenderer`, `Shapes`, `StepBadge`, `Decorations`, `Shortcuts`,
`Effect+Codable`, and every hand-written `Codable`.

- The edit pattern (`beginEdit`, `willModify`, `commit`, `willChangeGeometry`, `willTransform`, selection before and
  after): how many slightly different versions exist, and could one helper carry them?
- Hand-written `init(from:)` decoders that skip unknown or damaged values: one shared helper, or many copies of the
  same `try?` dance?
- `LayerActions` and its four extension files: one place that keeps groups together, masks with their layers and
  clipping valid after every change, or each command doing it itself?
- `ProjectFile` and the save snapshot: anything written and read in two places that must agree.

---

## Prompts for Leah

Run each in a fresh local session in the Colorbee folder, on **Opus, high effort**, in any order or all at once:

> You're a reviewer for Colorbee. Read `Docs/Review/PLAN-12.md` and do **session AB**, following its rules exactly:
> review only, don't touch git, don't build or run anything. Write your findings to `Docs/Review/findings-AB.md`, then
> tell me how many findings you have at each Worth.

For AC, AD and AE, change both letters.

When all four are in, the engineer reads them together, checks each against the code, and brings Leah one ranked list
to choose from. Each chosen refactor is then its own small commit: no behavior change, `make test` green, and a short
`make monkey` run (MINUTES=30) after the larger ones.
