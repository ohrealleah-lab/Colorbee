# Round 11 (refactoring and reuse): one ranked list

From [findings-AB](findings-AB.md), [AC](findings-AC.md), [AD](findings-AD.md) and [AE](findings-AE.md) (plan:
[PLAN-12.md](PLAN-12.md)), at commit `08094b7`. 57 findings and 15 "copies that already differ", merged where two
sessions found the same thing. Items marked **checked** were confirmed against the code by the engineer; the rest are as
the reviewer reported them.

## Part 1: copies that already differ (Leah decides each)

| # | What | Verdict | Recommendation |
|---|---|---|---|
| D1 | After Page ▸ Delete (or Add, Move) Page, then Drop Shadow, Border or Straighten ▸ Apply, ⌘Z undoes the **page change** instead of the shadow. Apply skips `pages.noteEdit()` (AB A) | **Checked: a real bug** | Fix (with R3) |
| D2 | Match Surroundings (Remove, Spot Heal) still blends tone the old ring-by-ring way that left hard lines in the Clone Stamp, fixed there 2026-10-22 (AD 1) | Plausible; changes pictures | Try it, then you compare before/after |
| D3 | Text styles, palettes and export presets: one entry Colorbee can't read empties the whole list, and the next change saves the empty list. A test build shares them with the everyday copy (AC 1) | Latent (no type has changed shape yet) | Fix (with R4) |
| D4 | A damaged Adjust Photo layer: one bad slider value loses the whole layer, while a damaged color mixer or grading is just dropped (AE C) | Damaged files only | Keep what's readable |
| D5 | The History panel's thumbnails leave out a pasted or moved piece that hasn't been placed yet (AE B) | Looks only | Fix (with R6) |
| D6 | Align on a text layer doesn't check the text box against the canvas as Crop does (AE A) | **Checked: harmless.** Align refuses any move that takes visible words off the canvas, so nothing is newly hidden | Leave |
| D7 | Feather rounds box blur sizes down, Gaussian Blur rounds them (AD 3) | **Checked: harmless.** Feather is whole pixels only | Leave, add a comment |
| D8 | The Desaturate brush uses a slightly different gray formula (Rec. 601) than Effects ▸ Desaturate (Rec. 709) (AD 2) | Invisible in practice | Leave, add a comment |
| D9 | Paste into New Image and a dropped picture don't carry camera details (AC 3) | Clipboard pictures rarely have them | Leave |
| D10 | Smaller ones: Pick Subject's "still current" check misses Clone Stamp strokes (AB B); two slider-text formats (AC 4); Redact Brush tint 120 vs Remove 110 (AB D); two pixel lerps (AD 4); slider fallbacks (AB C) | No visible effect today | Fold into the refactors below |

## Part 2: refactors, no behavior change

Ordered by worth, then size. S = under an hour, M = a few hours, L = a day or more.

### Tier 1: worth doing (High)

| # | What | Size | From |
|---|---|---|---|
| R1 | Every layer setting in one `LayerSettings` value, instead of nine hand-kept lists that must agree (undo, snapshots, saving, duplicating). Write the "every setting survives" test first | M | AE 1 (+ AE 9) |
| R2 | Split `Editor.swift` (5,600 lines) into one file per section; stored properties stay put | M | AB 2 |
| R3 | One "a step was recorded" helper (fixes D1) | S | AB 1 |
| R4 | One shared way for the eight settings stores to load and save (fixes D3) | M | AC 1 (+ AC 12, AC 14 folders) |
| ~~R5~~ | Moved to tier 3 (Leah, 2026-10-31): it belongs with the effect session, and the five copies differ in ways a shared helper would special-case | M | AB 3 |
| R6 | The History thumbnail and the export share their per-pixel compositing steps (fixes D5); compositing moves to `Canvas+Compositing.swift` | M | AE 2 |
| R7 | `Renderer.encode`: one "start a pass" and one "blend back" helper | M | AC 2 |
| R8 | Menu commands checked by the compiler (`#selector`), and the `return true` cases in one list | S–M | AC 3 (a, b) |

### Tier 2: small and safe (Medium, mostly S)

- **Photo rules in one place:** Warmth, Tint and Whites constants shared by the sliders, the eyedropper and Auto (AD 2);
  explicit cases instead of `default:` in six `Effect` switches (AD 3); one gray formula (AD 4); one vignette falloff
  (AD 5); one box-blur size rule (AD 6); one size-limit check, `fitsEditing`, used everywhere (AD 7 + AE 13).
- **Core model:** the project file's header and blob handling once (AE 4); spilling in bands once (AE 5); one skeleton
  for Crop, Resize and Canvas Size (AE 6); every layer step through `LayerActions.change` (AE 7); lenient decoding
  helpers (AE 8, with D4).
- **Editor:** text style ↔ text spec both ways in one place (AB 6); Redact Brush and Remove strokes as one (AB 7); a
  `pixelStep` helper (AB 8); tool sizes in one table (AB 9); one "image unchanged" stamp (AB 5).
- **App:** the shader's twins marked both ways, kinds named (AC 4); three shader helpers (AC 6); canvas keys in one
  table (AC 5); preference keys in one place (AC 7); `SaveSnapshot.flattened` (AC 8); `Canvas(decoded:)` (AC 9).
- **Effects on a plain buffer** without a throwaway canvas (AD 8).

### Tier 3: large, later or never

- The effect session as one value (AB 4, L): the biggest win for the Editor, and the riskiest. Only after R2 and R5.
- One "newest settings win" background worker (AB 3, M), moved here from tier 1: do it with the effect session.
- History steps as one payload enum (AE 3, M): the heart of undo; a 30-minute monkey run after.
- One drag state for the Editor and the view (AB 12, L).
- Whole-image loops onto `ParallelRows` (AD 9): speed only; needs `make perf`.
- Moving Editor geometry into the core (AB 11); a redaction pattern store (AB 10, which changes what two open windows
  see, so it's a behavior question).

### Tier 4: tidy-ups (Low), one commit

Dead code and misplaced comments (AB 14, AC 14, AD 15, AE 14); one `UnsafeTransfer` box (AC 13, AD 13); small helpers
(AB 13, AC 10–12, AD 10–14, AE 10–13).

## How each is done

One small commit per item: no picture, file or step changes unless a Part 1 answer says so; `make test` green; a
`make monkey MINUTES=30` run after R1, R5, R6 and anything in Tier 3. Part 1 fixes get a test and hand-test steps.
