# Colorbee Development Plan: after feature-complete

_Written 2026-10-27 by Claude for Leah. Planning only: no code or FRD changes. Functional decisions are Leah's; the questions are at the end._

**Scope:** FR-9.7 (all ten items), multi-select layers (FR-8.6), the approved layer follow-ups, layer masks,
re-editable text, stroke smoothing, Paste in Place and Trim.

**How to read this**
- 31 stages in five parts: **A** photo editing (FR-9.7), **B** layer follow-ups, **C** layer masks, **D** re-editable
  text, **E** stroke smoothing. The two small extras sit inside part A, next to the code they share.
- Each stage works end to end and gets your hand test before the next one starts.
- **Size:** S = a short sitting, M = a full sitting, L = a long sitting. Anything bigger is split into parts.
- **Model:** Opus throughout, as agreed. "High" is for design-heavy stages (new formats, new kinds of control,
  history, compositing). "Medium" is for routine UI on top of code that already exists.
- Questions have numbers like **Q9.2** (stage 9, question 2). Each stage lists its numbers; the full questions,
  each with my recommendation, are in the [last section](#questions-for-you).

---

## 1. What I found before planning

1. **Multi-select layers (FR-8.6) is already built.** It passed your tests on 2026-10-27, including the right-click
   menu with New Layer and New Adjustment Layer. Nothing is left to build, so it has no stage. Its follow-ups are
   part B.
2. **Several items aren't in the FRD yet.** The layer follow-ups, layer masks, re-editable text and stroke
   smoothing appear only as approved ideas in §23 (2026-10-27). Paste in Place and Trim appear only in
   `Feature-Gap-Analysis.md`. Since the FRD is the source of truth, each of those stages starts with me drafting
   its FRD section for your approval (Q0.1).
3. **Not in this plan:** revisiting AI with Apple's built-in models, and vector shapes. §23 has both as "revisit"
   or "reopened", and your scope list doesn't include them.
4. **Your saved filters are at risk while we build.** Your everyday Colorbee (beta 7) and the test builds share one
   filters file. Once a test build saves a filter that uses a new control, beta 7 can't read the file. The next
   filter you save or delete in beta 7 would then write an empty list over all your filters. Projects have a
   smaller version of the same problem: beta 7 opens a project with new controls, but its Adjust Photo layer comes
   back as an empty layer with the same name, and the adjustment is gone. Stage 1 fixes this going forward (Q0.3).
5. **How Adjust Photo works today**, since most of part A builds on it:
   - The 15 sliders are one list of named values. Filters scale those values by their Intensity.
   - **Color and tone** settings use exact math in exports. On screen, an Adjust Photo layer uses a 33-point color
     table, which can differ from the export by about one level (accepted in §23, 2026-10-03).
   - **Sharpness, Definition, Noise Reduction and Vignette** are worked out in the display shader from blurred
     copies of the image.
   - **Saved filters hold color and tone only.** Save as Filter leaves out the detail sliders and Vignette.
   - **While Adjust Photo is open, the picture is view-only:** any drag pans (§23, 2026-10-02). The white-balance
     eyedropper, Point Color, Color Range and drag-to-adjust all need clicks on the picture, so stage 1 adds a
     "pick from the picture" mode for them to share.

### Things that look unclear or conflict

I haven't guessed at any of these. Each one is a question at the end.

| # | Where | What doesn't fit | Question |
|---|---|---|---|
| 1 | FR-9.7 rule vs FR-9.5 | FR-9.7 says new controls live in Adjust Photo "so saved Filters include them". FR-9.5 says a filter holds color and tone only, and today's Save as Filter leaves out Sharpness, Definition, Noise Reduction and Vignette. Should Texture, Dehaze, sharpening, noise reduction, vignette and grain be saved in filters? | Q0.4 (answered) |
| 2 | FR-9.7 item 7 vs §23 2026-10-03 | "The area a crop cuts out shown dimmed": Crop… already shades the outside. What more is wanted? | Q17.3 |
| 3 | FR-9.7 item 3 vs FR-14.5 | It says "Select ▸ Expand…", but Colorbee has no Select menu. Selection commands are in Edit. | Q7.1 |
| 4 | FR-9.7 item 6 | "Clipping warnings on the histogram": only Levels has a histogram. Adjust Photo has none. | Q15.1 |
| 5 | FR-9.5 Auto, AC-35 | AC-35 says Auto moves only the sliders it lists. Should Auto also set the new ones (Whites, Dehaze)? | Q1.3 (answered) |
| 6 | FR-6.3 vs re-editable text | FR-6.3 says placed text can't be edited again, "true to classic Paint". Also, a layered image saves as .colorproj (§23, 2026-10-03), so if every text became a layer, an annotated PNG would stop saving as a PNG. | Q29.1 |
| 7 | §23 vs gap analysis answer 2b | §23 says "then layer masks". The gap analysis answer also says "clip-to-layer-below" for pixel layers. Is that included? | Q28.4 |
| 8 | Paste in Place shortcut | Photoshop's ⇧⌘V is Colorbee's Paste into New Image. | Q8.1 |
| 9 | Stamp Visible shortcut | Photoshop's ⌥⇧⌘E is Colorbee's Merge Visible. | Q22.5 |
| 10 | Adjust Photo slider names | Adjust Photo already has Highlights and Shadows sliders. A Lightroom tone curve's regions use the same names. | Q15.3 |
| 11 | History Snapshots vs §23 2026-10-03 (6b) | Undo history isn't saved in the project. Are snapshots? And must "Remove Earlier Versions and Undo History" after a redaction delete them too? | Q12.2, Q12.3 |

---

## 2. Shared checklists

### Every new Adjust Photo control goes through these

1. **Panel:** the control appears in Adjust Photo and in the Adjustments panel for an Adjust Photo layer. Both use
   the same `PhotoControls` view. Reset, Control-click to reset, sliding on the name and "Set by Auto" all work.
2. **Saved:** it's stored in `PhotoEdit`, read back safely, and a missing value means neutral. Projects and
   filters from before open unchanged (the FR-9.7 rule).
3. **Exports:** exact math in the core (`PhotoAdjustments`, `Effects.photoAdjusted`).
4. **Screen:** the live preview and an Adjust Photo layer match the export. Color-only controls go through the
   color table. Controls that look at neighboring pixels go in `adjust_photo_fragment` with `Renderer`.
5. **Filters:** Intensity scales it by the agreed rule. It's in or out of filters by category (Q0.4). Save as
   Filter and Save Filter from Layers handle it.
6. **Selections:** soft edges are respected (FR-3.4).
7. **Tests:** exact values on small images; save and reopen; the old fixture files open unchanged; a filter at 50%
   equals half; screen versus export; a time limit at 8000 × 8000 in `make perf` for controls that look at
   neighboring pixels.
8. **Help:** `fix-up-a-photo.html` and `panels.html`. The Adjust Photo picture is retaken if the panel layout
   changes.

### Every stage is done when

- `make test` is green. `make perf` has run if the stage touched pixel loops, effects or history (I'll ask you
  first, since it's heavy).
- The help pages are updated in the same commit. `make help` has run if a menu command or key changed.
- STATUS.md is updated: what's built, plus a "Waiting for Leah's tests" entry linking to its `### Test:` steps. The
  steps are also in chat.
- FRD §23 records your answers and my own choices, phrased "veto any".
- It's committed and pushed after the tests pass, and noted as passed once your hand test passes.

### New test files

Each is made by a small script and kept in `TestImages/Photo Editing/` unless noted. None shows a real person.

| File | Made from | For |
|---|---|---|
| `Old Adjust Photo.colorproj`, `Old Filter.colorbeefilter` | Saved from **today's** build, before stage 1 changes anything | Proving old files open unchanged |
| `Color Cast.png` | The Stage 9 practice photo with a blue cast and a gray card | White-balance eyedropper |
| `Dull Photo.png`, `Bright Photo.png` | The Stage 9 practice photo with its brightest parts dimmed to light gray, and with a patch of pure white | Auto's Whites |
| `Hazy.png` | The practice photo with haze added | Dehaze |
| `Color Chart.png` | Patches of the eight color ranges, skin tones and a gray ramp | Color Mixer, Grading, Point Color, Color Range, curve, readout |
| `Noisy.png` | The practice photo with noise added | Noise reduction, sharpening |
| `Looks/Warm.cube`, `Looks/Identity.cube` | Written by a script | .cube looks |
| `Trim Practice.png`, `Trim Practice Solid.png` | A picture with a transparent border; one with a white border | Trim |
| `Align Practice.colorproj` (in `TestImages/Several Layers/`) | Three badges on their own layers, out of line | Align and Distribute |
| Faces picture | Your choice (Q21.1) | Auto-redact faces |

---

## 3. Part A: Lightroom-style photo editing (FR-9.7)

The order follows FR-9.7's numbering, with two moves. "Same as Last" and copy/paste settings (item 4) come second:
they work on all of Adjust Photo's settings, so every later control is included automatically, and they deliver
your main aim of re-applying a look early. Black and White mix (item 6) is built with the Color Mixer (item 1),
since both use the same eight color ranges.

### Stage 1. Adjust Photo groundwork, Whites and the white-balance eyedropper

1. **What gets built**
   - Room in Adjust Photo's saved settings for controls that aren't a single slider (tables, colors, curves).
     Each starts at neutral, so filters and projects from before open unchanged.
   - Reading that skips a setting it doesn't know, instead of dropping the whole adjustment. Every beta from this
     one on can then open newer files with only the unknown controls missing.
   - Saved filters move to a new file, copied from the old one, so an older Colorbee can't wipe them (Q0.3).
   - Panel sections you can fold: Light, Color and Detail now, with more sections in later stages.
   - **Pick from the picture:** while Adjust Photo is open, or an Adjust Photo layer is being edited, a dropper
     button lets one click sample the picture. Space-drag and scrolling still pan.
   - A **Whites** slider, and the **white-balance eyedropper**: click something that should be gray, and it sets
     Warmth and Tint.
   - **Auto sets Whites** too (Q1.3): it raises Whites on a photo whose brightest parts fall short of white, and
     leaves it at 0 otherwise.
   - Covers the FR-9.7 rule, and item 1's eyedropper and Whites.
2. **Depends on:** nothing. **Touches:**
   - Core: `PhotoAdjustments.swift` (sliders, reading and writing), `PhotoFilter.swift`, `Effect+Codable.swift`,
     `Effects+Photo.swift`.
   - App: `AdjustPhotoPanel.swift`, `AdjustmentsPanel.swift`, `FilterStore.swift`, `Editor.swift` (the Adjust Photo
     session, pick mode), `CanvasView.swift` (clicks while a bar is open).
3. **Risks**
   - **Old projects:** proven by the fixture files, which are saved from today's build before anything changes.
   - **Older betas:** beta 7 still reads files the old way. A new beta right after this stage protects your
     everyday copy and your friend's (Q0.3).
   - **Strong color casts:** Warmth and Tint are gentle channel multipliers, so a very strong cast may need more
     than ±100 can give. The eyedropper then stops at the limit (Q1.5).
   - **Pick mode:** while the dropper is on, it suspends "the canvas is view-only while a bar is open".
   - **Performance:** none. Whites is color-only, so it goes in the color table.
   - Questions: Q1.1 to Q1.6.
4. **Size:** M. **Opus, high:** every later stage builds on this format and panel structure.
5. **Hand test** (`Old Adjust Photo.colorproj`, `TestImages/Stage 6b Practice.colorproj`, `Color Cast.png`,
   `Dull Photo.png`, `Bright Photo.png`)
   1. Open both projects. Each looks exactly as in beta 7, and the Adjust Photo layer's sliders show the same
      numbers.
   2. Open `Color Cast.png` and choose Adjustments ▸ Adjust Photo…. Fold and unfold Light, Color and Detail.
   3. Click the dropper by Warmth, then click the gray card. The blue cast goes, and Warmth and Tint have moved.
      Apply, then ⌘Z: it's all undone in one step.
   4. Open Adjust Photo again and drag Whites to the right. Only the brightest parts get brighter. Cancel.
   5. Open `Dull Photo.png`, Adjust Photo ▸ Auto: Whites moves up and shows "Set by Auto". On `Bright Photo.png`,
      whose brights already reach white, Auto leaves Whites at 0.
   6. Import `Old Filter.colorbeefilter` from the filter strip's menu. It looks the same as in beta 7.
   7. Choose As Adjustment Layer, then use the dropper in the Adjustments panel. Save, close and reopen: the same.
6. **Done when:** tests cover saving and reopening, the fixtures, an eyedropper click on a made-up gray patch
   coming out neutral within one level, Auto's Whites on a dull and a bright image, and filter scaling. Help and STATUS are updated, and a beta is cut if you
   agree (Q0.3).

### Stage 2. Same as Last, and copy and paste settings

1. **What gets built:** re-apply the last Adjust Photo settings to the selection or active layer. Copy Settings
   and Paste Settings put one picture's look on another, in the same or another document. Covers FR-9.7 item 4
   (first two parts).
2. **Depends on:** stage 1. **Touches:** `Editor.swift` (the Adjust Photo session), `AdjustPhotoPanel.swift`,
   `MainMenu.swift` (Adjustments menu), and a small new store for the last-used and copied settings (app side).
3. **Risks**
   - What counts as "last", and whether it survives a relaunch (Q2.2).
   - Copied settings stay out of the Mac clipboard, so the image you copied isn't replaced.
   - **History:** one undo step, the same as Apply today.
   - Questions: Q2.1 to Q2.5.
4. **Size:** S–M. **Opus, medium.**
5. **Hand test** (`TestImages/Stage 9 Practice Photo.png`, `Color Cast.png`)
   1. On the practice photo, Adjust Photo: Vivid filter, Exposure +20. Apply.
   2. Open `Color Cast.png` and choose Same as Last. It gets Vivid and Exposure +20, as one undo step.
   3. Back on the practice photo, open Adjust Photo and click Copy Settings. Cancel.
   4. On `Color Cast.png`, choose Paste Settings: the same look. ⌘Z.
   5. Quit and reopen Colorbee, then Same as Last again (if you chose that it's kept, Q2.2).
6. **Done when:** app tests check that last and pasted settings equal the source. Help is updated, and `make help`
   has run for the new menu items.

### Stage 3. Texture and Dehaze

1. **What gets built:** **Texture** brings out or softens fine detail without Definition's wider halos (a negative
   value smooths skin). **Dehaze** removes haze (a negative value adds it). Covers FR-9.7 item 1.
2. **Depends on:** stage 1. **Touches:**
   - Core: `PhotoAdjustments.swift` (math), `Effects+Photo.swift`.
   - App: `Shaders.metal` (`adjust_photo_fragment`), `Renderer.swift` (one more blurred copy, and a haze
     estimate passed in).
   - Tests: `PerformanceTests.swift`.
3. **Risks**
   - **Dehaze looks at the whole picture** to estimate the haze color (the standard "dark channel" method). On an
     adjustment layer, painting below changes that estimate. It's refreshed in the background at a reduced size,
     and exports use the same numbers, so the screen and the file agree.
   - **Performance:** one more blur per frame under an Adjust Photo layer; strokes beneath it must stay under 16 ms.
   - **Filters:** Dehaze is saved in filters; Texture isn't (Q0.4). **Look:** Definition is already close to Lightroom's Clarity, so I'll show you Texture next
     to Definition to make sure they feel different.
   - Questions: Q3.1, Q3.2.
4. **Size:** M–L. **Opus, high.**
5. **Hand test** (`Hazy.png`, `Stage 9 Practice Photo.png`)
   1. Open `Hazy.png`, Adjust Photo, Dehaze +50: the haze lifts and colors return. Apply. ⌘Z.
   2. Dehaze −50: haze is added. Cancel.
   3. Open the practice photo, zoom to 200%, Texture +60: the hills' fine detail sharpens with no glow around
      edges. Try −60: it softens.
   4. As Adjustment Layer, then paint with the Brush on the layer below: it stays smooth, and the look follows.
   5. Export a PNG and compare it with the screen: the same.
6. **Done when:** exact-value tests, a screen-versus-export test, and a time limit at 8000 × 8000 all pass. Help is
   updated.

### Stage 4. Color Mixer and Black & White

1. **What gets built**
   - **Color Mixer:** hue, saturation and luminance for each of eight color ranges, blended so there are no hard
     edges between colors.
   - **Black & White:** a switch that makes the picture black and white. The same eight sliders then set how light
     each color becomes.
   - Covers FR-9.7 item 1 (Color Mixer) and item 6 (Black and White mix).
2. **Depends on:** stage 1. **Touches:** the core (a new `ColorMixer.swift`, plus `PhotoAdjustments`,
   `ColorLookup.swift`), `AdjustPhotoPanel.swift` (a new section).
3. **Risks**
   - **Screen versus export:** narrow color changes through a 33-point table can differ from the export by more than
     today's one level. Adjust Photo layers may need a 65-point table (about 4 MB each); I'll measure first and tell
     you.
   - **Space:** 24 sliders need a compact layout (Q4.2).
   - **Filters:** hue shifts scale toward zero with Intensity.
   - Questions: Q4.1 to Q4.5.
4. **Size:** M. **Opus, high.**
5. **Hand test** (`Color Chart.png`, `Stage 9 Practice Photo.png`)
   1. Open `Color Chart.png`, Adjust Photo, Color Mixer ▸ Saturation, Blue −100. Only the blue patches turn gray;
      skin tones and the others stay.
   2. Hue tab, Green +100: the greens lean toward aqua, and nothing else moves.
   3. Turn on Black & White, then drag Red +60: the red patch gets lighter in gray, and the others don't.
   4. On the practice photo, darken the sky with Blue luminance −40. Apply, then ⌘Z.
   5. Save as Filter "Blue Sky", then try it at 50% Intensity: half the change.
6. **Done when:** an exact-value test on each patch passes, and the screen-versus-export test is within the agreed
   limit. Help is updated.

### Stage 5. Color Grading

1. **What gets built:** color wheels for shadows, midtones and highlights. Each sets a hue and a strength, with a
   luminance slider, plus Blending and Balance. Covers FR-9.7 item 2 (color grading).
2. **Depends on:** stage 1. **Touches:** the core (a new `ColorGrading.swift`, the color table), a new
   `ColorWheel.swift` control (app), `AdjustPhotoPanel.swift`.
3. **Risks**
   - **A new kind of control:** a wheel you drag a point around. Fine moves, double-click to reset, VoiceOver.
   - **Intensity** must scale the strength, never the hue (Q5.3).
   - Color-only, so it goes in the color table.
   - Questions: Q5.1 to Q5.4.
4. **Size:** M. **Opus, high** (design-heavy control).
5. **Hand test** (`Stage 9 Practice Photo.png`, the gray ramp in `Color Chart.png`)
   1. Adjust Photo ▸ Color Grading: drag Shadows toward teal and Highlights toward orange. The ramp's dark end turns
      teal and its light end orange.
   2. Drag Balance right: more of the ramp goes orange.
   3. Double-click a wheel: it resets.
   4. Save as Filter, then use it at 50%: the same hues, half as strong.
6. **Done when:** exact-value tests on the ramp pass. Help is updated.

### Stage 6. Point Color

1. **What gets built:** pick a color in the picture, then shift just that color's hue, saturation and luminance,
   with a Range setting for how wide "that color" is. You can pick several colors. Covers FR-9.7 item 2 (Point
   Color).
2. **Depends on:** stage 1 (pick mode) and stage 4 (shared color-range math). **Touches:** the core
   (`ColorMixer.swift` or a new `PointColor.swift`), `AdjustPhotoPanel.swift` (a swatch list), `Editor.swift` (pick
   mode).
3. **Risks**
   - **Saved in a filter,** a picked color still applies to whatever matches it in another picture; Intensity
     scales the shifts, not the picked color.
   - Narrow ranges have the same color-table precision issue as stage 4.
   - Questions: Q6.1 to Q6.3.
4. **Size:** M. **Opus, high.**
5. **Hand test** (`Color Chart.png`, `Stage 9 Practice Photo.png`)
   1. Adjust Photo ▸ Point Color ▸ dropper, then click the orange patch. A swatch appears.
   2. Hue +50: only the orange patch (and close oranges) shifts.
   3. Widen Range: the yellow patch starts to shift too.
   4. Pick a second color (a skin patch) and lower its saturation. Both changes show.
   5. Apply, then ⌘Z.
6. **Done when:** exact-value tests pass. Help is updated.

### Stage 7. Expand, Contract and Smooth

1. **What gets built:** grow, shrink or smooth the selection by a number of pixels, with a live preview like
   Feather's. Covers FR-9.7 item 3 (selection modify).
2. **Depends on:** nothing. **Touches:** the core (a new `SelectionMask+Modify.swift`, `SelectionActions.swift`),
   `Editor.swift` (a bar like Feather's), `MainMenu.swift`.
3. **Risks**
   - **Soft selections:** expanding and contracting keep the soft edge soft (FR-3.4).
   - **Large selections:** a big radius at 8000 × 8000 uses vImage's fast grow and shrink.
   - **History:** whether it's an undo step (Feather isn't, §23).
   - Questions: Q7.1 to Q7.4.
4. **Size:** S. **Opus, medium.**
5. **Hand test** (`TestImages/Magic Wand Practice.png`)
   1. Magic Wand a shape, then Expand 4 px: the ants move out evenly.
   2. Contract 8 px: they move in. Smooth 6 px: the ragged edge rounds off and stray specks go.
   3. Feather 10 px, then Expand 5 px, then Delete: the soft edge stays soft.
6. **Done when:** exact-value tests on small masks pass. Help is updated, and `make help` has run.

### Stage 8. Paste in Place (small extra)

1. **What gets built:** paste the copied pixels exactly where they were copied from, in the same document or
   another one, instead of at the top-left of the view. It fits here because it uses the same selection code as
   stage 7.
2. **Depends on:** nothing. **Touches:** `Editor.swift` (copy remembers where; `paste(_:at:)` already takes a
   place), `ClipboardImage.swift` and `PasteboardImages.swift` (the place travels with the copy), `MainMenu.swift`.
3. **Risks**
   - A picture copied in another app has no place (Q8.2).
   - The key Photoshop uses is taken (Q8.1).
   - Questions: Q8.1 to Q8.4.
4. **Size:** S. **Opus, medium.** First I'll draft its FRD lines for your approval (Q0.1).
5. **Hand test** (`TestImages/Help/Sample Screenshot.png`)
   1. Marquee a button near the bottom right, then ⌘C.
   2. Scroll so the top-left of the image shows, then Paste in Place. The copy lands exactly over the original.
   3. ⌘N, then Paste in Place: the same position in the new image.
   4. Copy something in Preview, then Paste in Place in Colorbee: it pastes as ⌘V would.
6. **Done when:** an app test pastes at the copied place. Help is updated, and `make help` has run.

### Stage 9. Color Range and Luminance Range

1. **What gets built**
   - **Color Range:** click colors in the picture (Shift-click adds more), set Fuzziness, and watch a live red-tint
     preview. Return makes it a soft selection.
   - **Luminance Range:** select by brightness, from shadows to highlights, with a soft falloff.
   - Both follow the soft-selection rules (FR-3.4). Covers FR-9.7 item 3.
2. **Depends on:** stage 1 (pick mode), stage 7 (its menu). **Touches:** the core (a new `ColorRange.swift`,
   `SelectionActions.swift`), `Editor.swift`, `CanvasView.swift`, `MainMenu.swift`, and Feather's red-tint preview
   (reused).
3. **Risks**
   - **What it reads:** the active layer or everything shown (Q9.2).
   - **Combining** with an existing selection (Q9.3).
   - **Redaction** hardens soft selections, as today.
   - Questions: Q9.1 to Q9.5.
4. **Size:** M. **Opus, high.**
5. **Hand test** (`Stage 9 Practice Photo.png`, `Color Chart.png`)
   1. Color Range…, then click the sky. It tints everything but the sky; raise Fuzziness to take in more blue.
      Return.
   2. Adjust Photo, Saturation +40: only the sky changes, with a soft edge at the hills. Apply.
   3. Luminance Range…, then choose Shadows. On the chart's gray ramp, only the dark end is selected, fading in.
   4. ⌘Z returns everything as it was.
6. **Done when:** exact-value tests on the chart's colors pass. Help is updated, and `make help` has run.

### Stage 10. Graduated selection

1. **What gets built:** drag a line on the picture. The start is fully selected, fading to nothing at the end, like
   Lightroom's linear gradient. Move the ends before applying; Return applies. Covers FR-9.7 item 3.
2. **Depends on:** stage 9 (shared bar and combine choices). **Touches:** the core (a mask from a line,
   `SelectionActions.swift`), `Editor.swift` (a canvas tool like Straighten's line), `CanvasView.swift`,
   `Renderer.swift` (guide lines).
3. **Risks:** where it lives (Q10.1). Questions: Q10.1 to Q10.4.
4. **Size:** S–M. **Opus, high** (a new canvas interaction).
5. **Hand test** (`Stage 9 Practice Photo.png`)
   1. Graduated Selection, then drag from the top of the sky down to the hills. Return.
   2. Adjust Photo, Exposure −40: the top of the sky darkens most, fading smoothly to none at the hills.
   3. Hold Shift while dragging: the line snaps to straight down.
6. **Done when:** exact-value tests of the fade pass. Help is updated.

### Stage 11. .cube looks

1. **What gets built:** import a `.cube` file (the standard format for color "looks") as a filter. It appears in
   the filter strip with Intensity, can be an adjustment layer, and exports as a `.colorbeefilter`. Covers FR-9.7
   item 4.
2. **Depends on:** stage 1. **Touches:**
   - Core: a new kind of adjustment that holds a color table (`Effects.swift`, `Effect+Codable.swift`,
     `PhotoFilter.swift`), a new `CubeFile.swift` reader, `ColorLookup.swift`.
   - App: `FilterStore.swift` (import).
3. **Risks**
   - **Size:** a big look holds about 800,000 numbers, so it's stored compactly in projects and filter files, not as
     text.
   - **Color:** looks are usually made for sRGB pictures (Q11.2).
   - **Damaged files:** a damaged `.cube` gives a plain message; added to the damaged-file tests.
   - **Older betas:** older Colorbee versions show such a layer with no settings, as before.
   - Questions: Q11.1 to Q11.4.
4. **Size:** M. **Opus, high.**
5. **Hand test** (`Looks/Warm.cube`, `Looks/Identity.cube`, `Stage 9 Practice Photo.png`)
   1. Adjust Photo ▸ filter menu ▸ Import…, then choose `Warm.cube`. A "Warm" filter appears; the photo warms.
   2. Intensity 50%: half as warm.
   3. Import `Identity.cube`: no visible change.
   4. As Adjustment Layer, then save, close and reopen: still warm.
   5. Rename a text file to `.cube` and import it: a plain message, and nothing is added.
6. **Done when:** reader tests, including damaged files, pass, and the exact result matches a reference. Help is
   updated.

### Stage 12. History Snapshots

1. **What gets built:** name the current state (for example "Before dramatic"). It shows in the History panel, and
   a click goes back to it. Covers FR-9.7 item 4.
2. **Depends on:** nothing. **Touches:** the core (`History.swift`, `Canvas.swift` layer-stack state, the disk
   spill), `HistoryPanels.swift`, `Editor.swift`, `MainMenu.swift`.
3. **Risks**
   - **The main one:** Colorbee's history is one straight line, so going back and making a change throws away
     what came after. A snapshot that only marks a step would vanish then. A snapshot that keeps its own copy
     survives anything, but costs memory, which counts against history's budget and spills to disk (Q12.1).
   - **Redaction safety:** a snapshot from before a redaction would bring the secret back, so clearing history
     after a redaction must clear snapshots too (Q12.3).
   - **Pages:** each page has its own.
   - Questions: Q12.1 to Q12.6.
4. **Size:** M. **Opus, high** (history).
5. **Hand test** (`Stage 9 Practice Photo.png`, `TestImages/Auto-Redact Practice.png`)
   1. History panel ▸ New Snapshot…, and name it "Start".
   2. Paint, apply Noir, then crop. Click "Start": the photo is back as it began.
   3. ⌘Z: you're back at the cropped Noir version.
   4. Click "Start", paint a stroke, then click "Start" again: it still works.
   5. On a copy of `Auto-Redact Practice.png`: take a snapshot, Auto-Redact, ⌘S, then choose Remove Earlier
      Versions and Undo History. The snapshot is gone.
6. **Done when:** history tests cover going back, undoing a jump, the memory budget and spilling, and clearing on
   redaction. The soak test includes snapshots. Help is updated.

### Stage 13. Sharpening and Noise Reduction in detail

1. **What gets built:** Sharpness gets Radius, Detail and Masking (sharpen only edges). Noise Reduction splits into
   Luminance and Color, each with Detail. Covers FR-9.7 item 5.
2. **Depends on:** stage 1. **Touches:** the core (`PhotoAdjustments.detail`, `Effects+Photo.swift`),
   `Shaders.metal`, `Renderer.swift` (radius-dependent blurs, an edge map for Masking), tests.
3. **Risks**
   - **Old files:** today's Sharpness and Noise Reduction must look the same afterwards. They become Amount and
     Luminance, and the new settings start at today's fixed values (radius 1.2 px and so on). Proven by the
     fixture.
   - **Performance:** blurs that depend on the settings, every frame, under an adjustment layer.
   - **Filters:** sharpening and noise reduction stay out of filters (Q0.4).
   - Questions: Q13.1 to Q13.3.
4. **Size:** M. **Opus, high.**
5. **Hand test** (`Noisy.png`, `Old Adjust Photo.colorproj`)
   1. Open the old project: its Sharpness and Noise Reduction look as before.
   2. On `Noisy.png` at 200%, Noise Reduction ▸ Color 60: the colored speckles go, and the grain of light stays.
      Luminance 50: smoother.
   3. Sharpness 60, then Masking 80: flat areas (the sky) stay smooth, and edges sharpen.
   4. Export, and compare with the screen.
6. **Done when:** exact-value tests, the fixture unchanged, screen versus export and time limits all pass. Help is
   updated.

### Stage 14. Vignette and Grain

1. **What gets built:** Vignette gets Midpoint, Roundness and Feather. **Grain** has Amount,
   Size and Roughness, fixed to the image so the preview matches the export. Vignette and Grain are now saved in
   filters and scaled by Intensity (Q0.4); Save as Filter absorbs them like the color and tone sliders. Covers FR-9.7
   item 5.
2. **Depends on:** stage 1. **Touches:** the core (`PhotoAdjustments.swift`, `Effects+Photo.swift`, `Vignette`,
   the noise code in `Effects+Texture.swift`), `Shaders.metal`.
3. **Risks**
   - **Old files:** the new settings start at today's vignette shape.
   - **Zoomed out,** the screen shows grain smaller than the file has it (each grain is image pixels), so it can
     look finer below 100%.
   - Whether Effects ▸ Vignette… also gets the new settings (Q14.3).
   - Questions: Q14.1 to Q14.4.
4. **Size:** M. **Opus, medium** (it follows stage 13's pattern).
5. **Hand test** (`Stage 9 Practice Photo.png`)
   1. Vignette −50, then Roundness +100: the darkening becomes a circle. Feather 0: a hard edge. Midpoint: the
      darkening moves in or out.
   2. Grain 50, at 100%: film-like grain. Size up: coarser. Export, and zoom both to 100%: the same grain.
   3. Save as Filter… named "Film". Open another picture and choose Film at 50%: half the vignette and grain.
      An older filter of yours shows no vignette or grain.
6. **Done when:** exact-value tests and the fixture unchanged. Help is updated.

### Stage 15. Tone curve and clipping warnings

1. **What gets built**
   - A **parametric tone curve** in Adjust Photo: four region sliders and three split points, drawn as a curve.
   - A **live histogram** at the top of Adjust Photo, with **clipping warnings:** when they're on, blown highlights
     show red and crushed shadows blue on the picture. This is display only and never exported.
   - Covers FR-9.7 item 6.
2. **Depends on:** stage 1. **Touches:**
   - Core: a new `ToneCurve.swift`, plus `Histogram.swift` (reused).
   - App: `ToneViews.swift` (the curve graph, reused), `AdjustPhotoPanel.swift`, and `Renderer.swift` with
     `Shaders.metal` (the clipping overlay).
3. **Risks**
   - **The histogram** of the edited result is worked out in the background as sliders move, from a smaller copy on
     big images.
   - **Naming** clashes with the existing Highlights and Shadows sliders (Q15.3).
   - Questions: Q15.1 to Q15.4.
4. **Size:** M. **Opus, high.**
5. **Hand test** (`Color Chart.png`, `Stage 9 Practice Photo.png`)
   1. Adjust Photo on the photo. The histogram shows; Exposure +80 moves it right.
   2. Turn on the highlight warning: the moon and bright sky turn red where they've blown out. Lower Exposure: the
      red shrinks.
   3. Curve, Darks −40: the gray ramp's lower middle darkens and the curve shows it. Move a split point: the
      change moves.
   4. Apply: no red in the result.
6. **Done when:** exact-value curve tests, and the overlay never shows in exports or copies. Help is updated.

### Stage 16. Drag on the picture to adjust

1. **What gets built:** a hand button. While it's on, dragging up or down on the picture changes the tone-curve
   region under the pointer, or, in the Color Mixer, the color under it. Covers FR-9.7 item 6.
2. **Depends on:** stages 1, 4 and 15. **Touches:** `Editor.swift` (pick mode with drags), `CanvasView.swift`,
   `AdjustPhotoPanel.swift`.
3. **Risks**
   - **Panning:** today any drag pans while the bar is open. While the hand is on, drags adjust and Space-drag pans.
   - **What it reads:** the pixel as it was before Adjust Photo, so the target doesn't move as you drag.
   - Questions: Q16.1, Q16.2.
4. **Size:** M. **Opus, high.**
5. **Hand test** (`Stage 9 Practice Photo.png`)
   1. Turn on the hand in the Curve section, then drag up on a dark part of the hills: the Shadows or Darks slider
      rises.
   2. In Color Mixer ▸ Saturation, turn on the hand and drag down on the sky: Blue (and maybe Aqua) saturation
      drops.
   3. Space-drag pans. Apply, then ⌘Z: one step.
6. **Done when:** app tests of which slider a drag moves pass. Help is updated.

### Stage 17. Photo geometry

1. **What gets built**
   - **Perspective Correction** places its four corners on the rectangle Apple Vision finds (on this Mac), for you
     to nudge. If it finds none, you get today's corners.
   - **Crop…** gets more overlays (golden ratio and others) and a key to switch between them.
   - Dimming: see the conflict above (Q17.3).
   - Covers FR-9.7 item 7.
2. **Depends on:** nothing. **Touches:** a new `RectangleFinder.swift` (core, Vision, like `Subjects.swift`),
   `Editor.swift` (Straighten, Perspective and Crop section), `CropOptions.swift`, `Renderer.swift` (overlay lines).
3. **Risks**
   - **Vision** finds documents well, but whiteboards photographed at a steep angle may be missed, so there's a
     fallback.
   - "Finding corners…" shows while it looks.
   - Questions: Q17.1 to Q17.3.
4. **Size:** M. **Opus, medium** (it follows Select Subject's pattern).
5. **Hand test** (`TestImages/Stage 9 Practice Perspective.png`)
   1. Image ▸ Perspective Correction…: after "Finding corners…", the corners sit on the shape's corners. Nudge one,
      then Return. The result is square.
   2. On a picture with no rectangle (the practice photo), the corners are where they are today.
   3. Crop…, then press the overlay key: thirds, grid, golden ratio and so on, in turn.
6. **Done when:** a test on a made-up rectangle (corners within 2 px) passes. Help is updated, and `make help` has
   run if a key was added.

### Stage 18. Trim (small extra)

1. **What gets built:** crop away borders that are transparent or all one color. It fits here, next to Crop and
   Straighten, and uses the same crop step.
2. **Depends on:** nothing. **Touches:** the core (a new `Trim.swift` that finds the edges, tested exactly, and
   `ImageActions.swift`), `Editor.swift`, `MainMenu.swift` (Image menu).
3. **Risks**
   - **JPEG edges** are never exactly one color (Q18.2).
   - **History:** all layers are cropped together, as Crop does: one undo step. On a page document, it trims the
     page being viewed.
   - **Nothing to trim:** a beep.
   - Questions: Q18.1 to Q18.3.
4. **Size:** S. **Opus, medium.** First I'll draft its FRD lines (Q0.1).
5. **Hand test** (`Trim Practice.png`, `Trim Practice Solid.png`, `TestImages/Stage 9 Practice Cutout.png`)
   1. Open `Trim Practice.png` and choose Image ▸ Trim. The see-through border is gone; the status bar shows the new
      size.
   2. `Trim Practice Solid.png`: the white border is gone.
   3. On the cutout, run Remove Background, then Trim: tight around the subject. ⌘Z.
6. **Done when:** exact-value tests (including soft edges and one-pixel lines) pass. Help is updated, and `make
   help` has run.

### Stage 19. Export: color space and Limit file size  *(could run in its own session, see section 7)*

1. **What gets built:** Export… gets **Color:** keep the document's (the default), sRGB or Display P3. **Limit file
   size** for JPEG and HEIC: enter a size, and Colorbee finds the best quality that fits. It's greyed out for PNG
   and other formats, which can't. Covers FR-9.7 item 8.
2. **Depends on:** nothing. **Touches:** `ImageDocument.swift` (`ExportOptions` and the panel), `SaveSnapshot.swift`,
   the core's `ImageCodec.swift` (conversion and embedding the new profile).
3. **Risks**
   - **Converting** Display P3 to sRGB pulls in colors sRGB can't show; vivid reds and greens get a little duller.
     That's expected, and the help says so.
   - **Size limit:** encodes several times in the background. An 8000 × 8000 HEIC may take a few seconds, so it
     shows progress.
   - **Camera details** count toward the size.
   - Questions: Q19.1 to Q19.5.
4. **Size:** M. **Opus, high.**
5. **Hand test** (`Stage 9 Practice Photo.png`)
   1. Export…, JPEG, Color sRGB. Open the file in Preview, then Tools ▸ Show Inspector: the profile is sRGB.
   2. Export again with "Keep document's": Display P3, as today.
   3. Limit file size 200 KB: Finder shows 200 KB or less.
   4. Choose PNG: Limit file size is greyed out.
   5. Limit 5 KB on a big image: the message you chose (Q19.3).
6. **Done when:** tests check the profile and the size stays under the limit. Help is updated.

### Stage 20. Color readout and Eyedropper sample size  *(could run in its own session)*

1. **What gets built:** the status bar shows the color under the pointer, as RGB and hex. The Eyedropper gets a
   Sample Size that averages a small area. Covers FR-9.7 item 9.
2. **Depends on:** nothing. **Touches:** `StatusBar.swift`, `Editor.swift` (the pointer and colors), the
   Eyedropper in `CanvasView.swift`, `PaletteBar.swift` (tool options), and the core's `Canvas.pixelAsShown` (an
   averaging helper).
3. **Risks**
   - **Which pixel** (Q20.1).
   - **Which numbers:** the document's own values or sRGB (Q20.2). This decides whether a brand color from a style
     guide matches.
   - **Narrow windows:** the status bar needs room.
   - Questions: Q20.1 to Q20.4.
4. **Size:** S. **Opus, medium.**
5. **Hand test** (`Color Chart.png`, `TestImages/Help/Sample Screenshot.png`)
   1. Move over a chart patch: the status bar shows its RGB and hex, matching the chart's list.
   2. Eyedropper, Sample Size 5 × 5, then click an anti-aliased letter edge in the screenshot: an in-between color.
      At 1 px: one exact pixel.
   3. Point at the gray surround: the readout clears.
6. **Done when:** an exact averaging test passes. Help is updated.

### Stage 21. Auto-redact faces  *(could run in its own session)*

1. **What gets built:** Auto-Redact also finds faces (Apple Vision, on this Mac) on every page. They're listed in
   the review sheet with the text matches and boxed on the canvas, with the same Blur, Pixelate and Solid Fill and
   one undo step. Covers FR-9.7 item 10.
2. **Depends on:** nothing. **Touches:** the core's `AutoRedact.swift` (a face scan), `AutoRedact+Apply.swift`,
   `Editor.swift` (Auto-Redact section), `AutoRedactSheet.swift`. Help: `redact-a-screenshot.html`,
   `privacy.html`.
3. **Risks**
   - **A missed face is a privacy miss.** Small, turned or half-hidden faces, and drawn or game characters, may not
     be found, so the sheet says to check.
   - **Box size:** Vision's face box is tight (Q21.3).
   - **A test picture with real faces** can't go in the public repo (Q21.1).
   - Questions: Q21.1 to Q21.5.
4. **Size:** M. **Opus, high.**
5. **Hand test** (the faces picture from Q21.1, and `TestImages/Stage 10/Three Page Test.pdf`)
   1. Open the faces picture and choose Redact ▸ Auto-Redact…. Each face is listed ("Face 1"…) and boxed, covering
      hair and chin.
   2. Untick one face, choose Pixelate, and Apply: the others are pixelated. ⌘Z: all back in one step.
   3. Open the PDF and choose Auto-Redact: no faces listed, and text matches as before.
6. **Done when:** core tests of box padding and of combining with text matches pass; face finding itself is checked
   by hand, like Select Subject. Help is updated.

---

## 4. Part B: layer follow-ups (§23, 2026-10-27)

Each stage starts with its FRD section drafted for your approval (Q0.1).

### Stage 22. Select All Layers, isolate a layer, Stamp Visible

1. **What gets built**
   - **Select All Layers** chooses every layer.
   - **Option-click an eye** shows only that layer; Option-click again brings back what was showing.
   - **Stamp Visible** adds a new layer with a merged copy of everything visible, keeping the originals.
2. **Depends on:** FR-8.6 (built). **Touches:** the core (`LayerActions.swift`, `LayerActions+Several.swift`),
   `Editor.swift` (layers), `LayersPanel.swift`, `LayerMenu.swift`, `MainMenu.swift`.
3. **Risks**
   - **Isolating** must remember what was showing (Q22.4).
   - **Memory:** Stamp Visible adds a full layer.
   - **Keys:** Q22.1, Q22.5.
   - Questions: Q22.1 to Q22.5.
4. **Size:** S–M. **Opus, medium.**
5. **Hand test** (`TestImages/Several Layers/Opacity Test.colorproj`)
   1. Layer ▸ Select All Layers: all five are chosen.
   2. Option-click Green's eye: only Green shows. Option-click it again: all are back.
   3. Stamp Visible: a new layer holds the whole picture. Hide every other layer: the picture still looks the
      same. ⌘Z.
6. **Done when:** core and app tests pass. Help (`work-with-layers.html`) is updated, and `make help` has run.

### Stage 23. Lock transparent pixels

1. **What gets built:** a second kind of lock. You can recolor a layer's pixels but not paint where it's empty, so
   a cutout or a shape keeps its outline.
2. **Depends on:** nothing. **Touches:**
   - Core: `Layer.swift` (a flag), `ProjectFile.swift` (an optional field), `Canvas.swift` (layer-stack state),
     `History.swift`.
   - App: `LayersPanel.swift`, `Editor.swift`.
3. **Risks**
   - **It reaches every tool that writes pixels.** Rather than changing each tool, every edit on such a layer gets
     its old transparency put back from history's before-images when the edit finishes. That's one place to get
     right, and history already has those images.
   - **The Eraser** can't make holes (Q23.2).
   - **Older betas** open such a layer unlocked.
   - Questions: Q23.1 to Q23.3.
4. **Size:** M. **Opus, high.**
5. **Hand test** (`TestImages/Stage 9 Practice Cutout.png` after Remove Background, or `Opacity Test.colorproj`)
   1. Lock transparent pixels on the cutout. Paint across it with a big red Brush: the subject turns red and the
      empty area stays empty.
   2. Fill Bucket and Gradient inside: the same.
   3. Eraser: it paints Color 2 inside the shape (or the behavior you chose).
   4. Save, close and reopen: still locked.
6. **Done when:** a test checks that every tool keeps transparency on such a layer. Help is updated.

### Stage 24. Align and Distribute

1. **What gets built:** with several layers chosen, Layer ▸ Align ▸ Left, Centers, Right, Top, Middle, Bottom, and
   Distribute horizontally or vertically. These go by each layer's visible pixels.
2. **Depends on:** FR-8.6. **Touches:** the core (a new `LayerAlign.swift`, `LayerActions.swift`), `Editor.swift`,
   `LayerMenu.swift`, `MainMenu.swift`.
3. **Risks**
   - **Layers have no position:** each is a canvas-sized picture, so aligning moves pixels inside it. Lining layers
     up with each other or with the canvas never pushes anything off the edge, but aligning a big layer to a small
     selection could, and pixels past the edge would be lost (Q24.1).
   - A layer that fills the canvas (a photo) can't move.
   - **History:** one undo step.
   - Questions: Q24.1 to Q24.4.
4. **Size:** M. **Opus, high.**
5. **Hand test** (`Align Practice.colorproj`)
   1. Choose the three badge layers, then Align ▸ Left: their left edges line up.
   2. Distribute Vertically: equal gaps.
   3. Choose one layer, then Align ▸ Centers: it centers on the canvas. ⌘Z.
6. **Done when:** exact tests of bounds and moves pass. Help is updated, and `make help` has run.

### Stage 25. Layer groups, part 1: groups in the document

1. **What gets built:** Group chosen layers and Ungroup. A group row in the Layers panel folds open and shut, can be
   hidden, and has its own opacity and blend mode. It's saved in .colorproj, and the screen, exports and Copy
   Merged all match.
2. **Depends on:** stage 22. **Touches:**
   - Core: `Layer.swift`, `Canvas.swift` (compositing, "Only the layer below"), the layer-stack state in
     `History.swift`, `ProjectFile.swift`, `LayerActions*.swift`.
   - App: `Renderer.swift` with `Shaders.metal` (an extra pass per group), `LayersPanel.swift`, `LayerMenu.swift`.
   - Also everything that walks the layers: Auto-Redact, Subjects, the Eyedropper, Merge.
3. **Risks**
   - **The biggest change to the document since pages.** Layers stay one flat list, each naming its group, so most
     code doesn't change. This also prepares the project format for masks and text layers.
   - **A group that isn't Pass Through** needs its own off-screen picture, which costs memory and GPU time.
   - **Older betas** would show each group as an empty layer, with its layers no longer grouped (Q25.5).
   - **The soak test** must include groups.
   - Questions: Q25.1 to Q25.7.
4. **Size:** L. **Opus, high.**
5. **Hand test** (`Opacity Test.colorproj`)
   1. Choose Red and Green, then Group: a "Group 1" row holds them. Fold it shut and open again.
   2. Hide the group: both go. Group opacity 50%: both fade together.
   3. Save, close and reopen: the same. Export a PNG: it matches the screen.
   4. Ungroup: back as before. ⌘Z twice.
6. **Done when:** compositing tests (screen versus export, with blend modes) pass, plus format tests and a soak with
   groups. Help is updated, and `make help` has run.

### Stage 26. Layer groups, part 2: working with groups

1. **What gets built:** drag layers into and out of groups, groups inside groups (Q25.1), Merge Group, duplicating,
   deleting and locking groups, "Group chosen layers" in the right-click menu (approved), and adjustment layers
   inside groups. Choosing a group works with Align and Stamp Visible.
2. **Depends on:** stage 25. **Touches:** `LayersPanel.swift` (dragging), `LayerActions+Several.swift`,
   `LayerMenu.swift`, `MainMenu.swift`.
3. **Risks**
   - **Dragging** onto a row versus between rows is fiddly to get right.
   - **Edge cases:** locked layers, and "Only the layer below" at a group's edge.
   - Questions: Q25.2, Q25.6.
4. **Size:** M–L. **Opus, high.**
5. **Hand test** (`Opacity Test.colorproj`)
   1. Drag Blue into the group, then out again.
   2. Add a Hue/Saturation layer inside the group. With Pass Through it changes everything below; with Normal, only
      the group.
   3. Right-click two chosen layers, then Group chosen layers. Merge Group: one layer, same look.
6. **Done when:** tests and help.

---

## 5. Part C: layer masks

### Stage 27. Layer masks, part 1: pixel layers

1. **What gets built:**
   - **Add Mask:** reveal all, hide all, or from the selection.
   - A mask thumbnail next to the layer's. Click it, then paint: black hides, white reveals, grays partly.
   - Delete Mask, and Apply Mask (bake it in).
   - Saved in .colorproj, and the screen matches the export.
2. **Depends on:** stage 25 (the layer model settles first). **Touches:**
   - Core: `Layer.swift`, a one-channel picture type for the mask, `History.swift` (before-images keyed by layer
     and by mask), `Canvas.swift` with `Compositing.swift`, `ProjectFile.swift`.
   - App: every tool's "where do I draw", `Renderer.swift` with `Shaders.metal`, `LayersPanel.swift`, and Merge,
     Flatten, Copy Merged and Remove Background.
3. **Risks**
   - **Memory:** a one-channel mask is a quarter of a layer's size (64 MB at 8000 × 8000), but it's a new kind of
     buffer for history's disk spill.
   - **Redaction safety:** a mask hides pixels without removing them. Redaction must change hidden pixels too, and
     the help says masks don't hide secrets (Q28.5).
   - **Older betas** show the hidden parts (Q28.5).
   - **Painting** on a mask must stay under 16 ms.
4. **Size:** L. **Opus, high.**
5. **Hand test** (`Stage 9 Practice Photo.png` with `Stage 9 Practice Cutout.png` pasted on a layer above)
   1. Add Mask on the cutout layer, click the mask thumbnail, and paint black on part of it: that part hides, and
      the photo shows through. Paint white: it's back.
   2. Save, close and reopen: the same. Export: it matches.
   3. Apply Mask: the hidden part is now gone for real. ⌘Z.
6. **Done when:** compositing, history (undo of mask strokes), format and memory tests pass. Help is updated, and
   `make help` has run.

### Stage 28. Layer masks, part 2: adjustment layers and mask tools

1. **What gets built:**
   - Masks on adjustment layers: local Adjust Photo that never changes pixels, the most Lightroom-like result in
     this plan (Q28.1).
   - Masks on groups (Q28.2).
   - Shift-click turns a mask off; Option-click shows it alone; Invert Mask.
   - Masks from Color Range, Luminance Range and graduated selections, through "from the selection".
   - Masks with "Only the layer below", with Merge Layers, and with several chosen layers.
   - Clipping for pixel layers too, if you choose it (Q28.4).
2. **Depends on:** stage 27, and stages 9 and 10 (useful). **Touches:** every adjustment shader in
   `Shaders.metal`, `Renderer.swift`, `Canvas.swift`, `AdjustmentsPanel.swift`, `LayersPanel.swift`.
3. **Risks:**
   - Every adjustment display path gets a mask input.
   - Merge Adjustment with a mask.
   - Questions: Q28.1 to Q28.7.
4. **Size:** L. **Opus, high.**
5. **Hand test** (`Stage 9 Practice Photo.png`)
   1. Color Range on the sky, then add an Adjust Photo layer with Saturation +50. Its mask is the sky.
   2. Paint on the mask to take the hills back out. Shift-click the mask: the adjustment applies everywhere.
      Shift-click again.
   3. Option-click the mask: you see the mask in gray. Option-click again.
   4. Save, close and reopen: the same.
6. **Done when:** tests and help.

---

## 6. Parts D and E: re-editable text and stroke smoothing

### Stage 29. Re-editable text, part 1: text layers

1. **What gets built:**
   - Placed text becomes a **text layer** (or only when you ask, Q29.1).
   - Double-click it with the Text tool to change the words, font, size, colors or box.
   - It's saved in .colorproj and flattened into pixels on export. Text placed before stays pixels.
2. **Depends on:** stages 25 and 27 (layer kinds settled). **Touches:**
   - Core: `Layer.swift` (holds the text and its drawn pixels), `TextRenderer.swift` (the text settings saved),
     `ProjectFile.swift`, `History.swift`.
   - App: the Text section of `Editor.swift`, `CanvasTextView.swift`, `LayersPanel.swift`.
3. **Risks**
   - **The drawn pixels are stored as an ordinary layer,** so compositing doesn't change, and older betas show the
     text as plain pixels.
   - **Redaction safety:** a text layer keeps its words in the file, so any redaction over it must turn it into
     pixels first (Q29.2).
   - **Missing fonts** on another Mac (Q29.4).
   - This reverses FR-6.3 (Q29.1).
   - Questions: Q29.1 to Q29.6.
4. **Size:** L. **Opus, high.**
5. **Hand test** (`TestImages/Help/Sample Screenshot.png`)
   1. Type a label with the Text tool and place it: a text layer appears.
   2. Paint elsewhere, then double-click the label with the Text tool: it opens for editing. Change a word and the
      font. Place it.
   3. ⌘Z undoes just the edit.
   4. Save as .colorproj, close and reopen, then double-click: still editable. Export a PNG: the text is there.
6. **Done when:** format tests (including old projects), redaction tests and help are done.

### Stage 30. Re-editable text, part 2: when text becomes pixels

1. **What gets built:**
   - The rules for painting, effects, Merge, Flatten, rotating and resizing on a text layer.
   - Layer ▸ Rasterize Text.
   - Text styles applied to a text layer.
2. **Depends on:** stage 29. **Touches:** `Editor.swift` (the tools' refusal checks), `LayerActions*.swift`,
   `ImageActions.swift`.
3. **Risks:** many entry points. Questions: Q29.2, Q29.3, Q29.6.
4. **Size:** M. **Opus, high.**
5. **Hand test** (the stage 29 file)
   1. Paint on a text layer: the behavior you chose (a message, or it turns into pixels first).
   2. Resize the image to 200%: the text stays crisp (if you chose re-rendering).
   3. Redact Brush over the text: it becomes pixels and is redacted. ⌘Z.
6. **Done when:** tests and help.

### Stage 31. Stroke smoothing  *(could run in its own session beside stages 22–24)*

1. **What gets built:** a Smoothing slider in the palette bar, 0% (off) by default, as you chose. The line trails
   the pointer a little to take out the wobble, and catches up when you let go.
2. **Depends on:** nothing. **Touches:** the core (a new `StrokeSmoother.swift`, like `AxisLock`), the painting,
   Redact Brush and Retouch sections of `Editor.swift`, and `PaletteBar.swift`.
3. **Risks**
   - **The feel** needs tuning with you.
   - **Shift** (a straight line) wins over smoothing, and Symmetry copies the smoothed line.
   - **Lag:** the trailing is on purpose, so it isn't counted against NFR-2's 16 ms.
   - Questions: Q31.1 to Q31.4.
4. **Size:** M. **Opus, high** (tuning by feel).
5. **Hand test** (a new image, ⌘N, on the trackpad)
   1. Brush at Smoothing 0%: as today.
   2. At 50%, write your name slowly: steadier lines that finish where you let go.
   3. At 100%: very smooth, with noticeable trailing.
   4. Hold Shift: still a straight line.
6. **Done when:** exact-path tests pass, and `make bench` shows unchanged latency at 0% (I'll ask before running
   it). Help (`tools.html`) is updated.

---

## 7. What can be built together, and what must not

**Safe to run side by side** (each in its own local worktree, while the Adjust Photo stages go on):
- **Stage 19 (Export):** touches only the export panel, `SaveSnapshot` and `ImageCodec`.
- **Stage 20 (readout):** the status bar and the Eyedropper. It also touches `Editor.swift`, but a different
  section.
- **Stage 21 (faces):** the Auto-Redact files.
- **Stage 31 (smoothing)** beside stages 22–24: the painting section, not the layer code.

**Must not run together:**
- **Any two Adjust Photo stages** (1–6, 11, 13–16): they all change `PhotoAdjustments`, `adjust_photo_fragment` and
  `PhotoControls`.
- **Any two of stages 23, 25, 26, 27, 28, 29 and 30:** each changes the layer model, the project format and
  compositing.
- **Stages 7, 8, 9 and 10:** the selection code and the Edit menu.
- **Stage 12 (snapshots) with stage 27 (masks):** both change history.

**Things to know before running side by side:**
- STATUS.md, the FRD log and generated help pages get small merge conflicts.
- Each worktree builds its own Colorbee copy, which can take over Help and Open With until it's unregistered.
- Two `make test` runs at once share Colorbee's settings.
- You test one thing at a time anyway.

**My recommendation:** build one stage at a time. The pace is set by your hand tests, not by build time. If you'd
like more speed, stages 19–21 are the safe ones to run beside the Adjust Photo work.

---

## 8. Overview

| # | Stage | Covers | Size | Effort | Depends on | Side by side? |
|---|---|---|---|---|---|---|
| 1 | Adjust Photo groundwork, Whites, white-balance eyedropper | FR-9.7 rule, item 1 | M | High | — | No |
| 2 | Same as Last, copy and paste settings | Item 4 | S–M | Medium | 1 | No |
| 3 | Texture and Dehaze | Item 1 | M–L | High | 1 | No |
| 4 | Color Mixer and Black & White | Items 1, 6 | M | High | 1 | No |
| 5 | Color Grading | Item 2 | M | High | 1 | No |
| 6 | Point Color | Item 2 | M | High | 1, 4 | No |
| 7 | Expand, Contract, Smooth | Item 3 | S | Medium | — | No |
| 8 | **Paste in Place** (extra) | Gap analysis | S | Medium | — | No |
| 9 | Color Range and Luminance Range | Item 3 | M | High | 1, 7 | No |
| 10 | Graduated selection | Item 3 | S–M | High | 9 | No |
| 11 | .cube looks | Item 4 | M | High | 1 | No |
| 12 | History Snapshots | Item 4 | M | High | — | No |
| 13 | Sharpening and Noise Reduction detail | Item 5 | M | High | 1 | No |
| 14 | Vignette and Grain | Item 5 | M | Medium | 1 | No |
| 15 | Tone curve and clipping warnings | Item 6 | M | High | 1 | No |
| 16 | Drag on the picture to adjust | Item 6 | M | High | 1, 4, 15 | No |
| 17 | Photo geometry | Item 7 | M | Medium | — | No |
| 18 | **Trim** (extra) | Gap analysis | S | Medium | — | No |
| 19 | Export color space and file size | Item 8 | M | High | — | Yes |
| 20 | Color readout and sample size | Item 9 | S | Medium | — | Yes |
| 21 | Auto-redact faces | Item 10 | M | High | — | Yes |
| 22 | Select All Layers, isolate, Stamp Visible | §23 layers | S–M | Medium | FR-8.6 | No |
| 23 | Lock transparent pixels | §23 layers | M | High | — | No |
| 24 | Align and Distribute | §23 layers | M | High | FR-8.6 | No |
| 25 | Layer groups 1 | §23 layers | L | High | 22 | No |
| 26 | Layer groups 2 | §23 layers | M–L | High | 25 | No |
| 27 | Layer masks 1 | §23 masks | L | High | 25 | No |
| 28 | Layer masks 2 | §23 masks | L | High | 27 (9, 10 help) | No |
| 29 | Re-editable text 1 | §23 text | L | High | 25, 27 | No |
| 30 | Re-editable text 2 | §23 text | M | High | 29 | No |
| 31 | Stroke smoothing | §23 smoothing | M | High | — | Beside 22–24 |

All Opus. FR-8.6 is already built, so it has no stage.

---

## Questions for you

Each has my recommendation and why. "Before stage N" means I need the answer before that stage starts, not now.

### Before any stage

- **Q0.1 FRD first.** For the items not yet in the FRD (stages 8, 18 and 22–31), I'll draft each FRD section at the
  start of its stage, you approve it, and then I build. *Recommend yes:* it keeps the FRD the single source of
  truth, as CLAUDE.md asks.
  **Answer: yes.**
- **Q0.2 FR-8.6.** It's built and passed. Is anything else wanted there? *Recommend nothing;* the follow-ups are part
  B. **Answer: nothing more.**
- **Q0.3 Saved filters and older betas.** Stage 1 moves filters to a new file and makes reading tolerant, but beta 7
  in your Applications folder stays old. *Recommend* cutting a beta right after stage 1 and using it as your
  everyday copy (and sending it to your friend). Until then, don't save or delete filters in beta 7.
  Another beta after stages 6, 16, 21, 26, 28 and 31. **Answer: yes.**
- **Q0.4 What filters hold.** Should these be saved in filters? *Recommend:*
  - **Dehaze: in.** It's a tone change.
  - **Texture, sharpening and noise reduction: out.** They depend on each photo's own detail.
  - **Vignette and Grain: in,** as Lightroom presets do, since they're part of a "look". This changes today's rule
    that leaves Vignette out, so it's your call.
  - **Answer: yes to all three.**
- **Q0.5 Side-by-side sessions.** *Recommend no* (section 7). If you want them, only stages 19–21. **Answer: one at a
  time.**

### Before stage 1

- **Q1.1** Remember which Adjust Photo sections are folded between launches? *Recommend yes,* for the whole app
  rather than per document: you'll settle into a layout. **Answer: yes, app-wide.**
- **Q1.2** Whites: −100 to 100, in Light just above Black Point? *Recommend yes;* that's Lightroom's order. **Answer: yes.**
- **Q1.3** Should Auto also set Whites? AC-35 says Auto moves only the sliders it lists. *Recommend no for now:* it
  keeps AC-35 true. We can revisit after Dehaze. **Answer: yes, Auto sets Whites;** AC-35's list grows to
  include it. Auto raises Whites only when the brightest parts fall short of white (my choice, in §23; veto it
  if you like).
- **Q1.4** The white-balance dropper: average a 5 × 5 area, and turn off after one click (Esc cancels)?
  *Recommend yes to both:* one pixel of a photo is noisy, and one click is the usual use. **Answer: yes to both.**
- **Q1.5** A click on something that isn't gray at all, or a cast stronger than Warmth and Tint can fix: set as
  far as it can, with no message? *Recommend yes;* you can see the result and undo it. **Answer: yes.**
- **Q1.6** Add a Blacks slider too? FR-9.7 names only Whites. *Recommend no:* Black Point already does this. **Answer: no.**

### Before stage 2

- **Q2.1** Where: Adjustments ▸ "Adjust Photo: Same as Last" plus "Copy Photo Settings" and "Paste Photo Settings",
  with no default keys (they can be set in Settings), and Copy and Paste buttons in the panel. *Recommend this:*
  Lightroom's keys (⇧⌘C, ⇧⌘V) are taken here.
- **Q2.2** "Last" is the last settings applied anywhere (Apply or As Adjustment Layer), kept across a relaunch?
  *Recommend yes:* the use is coming back to a look later.
- **Q2.3** Paste Settings opens Adjust Photo with the settings in place, so you see them before Return? *Recommend
  yes:* there are no surprises, and it's still one undo step. The other way, it applies straight away.
- **Q2.4** Copy everything, or choose which settings (Lightroom shows a checklist)? *Recommend everything for now;* a
  checklist can come later if you miss it.
- **Q2.5** Copy from an Adjust Photo layer too, and offer "Paste as Adjustment Layer"? *Recommend yes.*

### Before stage 3

- **Q3.1** Texture in Detail next to Definition, Dehaze in Light after Brilliance? *Recommend yes.*
- **Q3.2** Both −100 to 100, where a negative Texture softens and a negative Dehaze adds haze? *Recommend yes,* as in
  Lightroom.

### Before stage 4

- **Q4.1** The eight ranges: Red, Orange, Yellow, Green, Aqua, Blue, Purple, Magenta? *Recommend yes* (Lightroom's).
- **Q4.2** Layout: Hue, Saturation and Luminance tabs with eight sliders each? *Recommend tabs:* you can see all the
  colors at once, as in Lightroom.
- **Q4.3** How far Hue can move a color: ±100 is about ±30°? *Recommend yes:* red can lean orange or magenta but
  can't become green, which keeps it natural.
- **Q4.4** Black & White as a switch at the top of the Color Mixer, where Color Grading still tints (for split-toned
  black and white)? *Recommend yes.*
- **Q4.5** The Black & White mix starts at neutral, looking like the Mono filter? *Recommend yes:* it's predictable.

### Before stage 5

- **Q5.1** Shadows, Midtones and Highlights, plus a Global wheel? *Recommend all four:* Global is a small extra.
- **Q5.2** One large wheel with tabs, since the sidebar is narrow, and small dots showing the others? *Recommend
  yes.*
- **Q5.3** A filter at 50% halves each wheel's strength and keeps its hue? *Recommend yes.*
- **Q5.4** Blending starts at 50 and Balance at 0? *Recommend yes,* as in Lightroom.

### Before stage 6

- **Q6.1** Up to 8 picked colors? *Recommend yes,* as in Lightroom.
- **Q6.2** Per color: Hue, Saturation, Luminance and Range? *Recommend those four.* Lightroom also has Variance; I'd
  add it only if you want it.
- **Q6.3** While you hold the Range slider, gray out everything it doesn't touch? *Recommend yes:* it shows what
  "this color" means.

### Before stage 7

- **Q7.1** Colorbee has no Select menu. *Recommend* Edit ▸ Modify Selection ▸ Expand…, Contract…, Smooth…, next to
  Feather…, so the menus stay as they are. The other way is a new Select menu holding every selection command,
  like Photoshop's, which is a bigger change.
- **Q7.2** Not an undo step, like Feather? *Recommend yes,* for consistency.
- **Q7.3** 1 to 100 px, starting at 2 px? *Recommend yes.*
- **Q7.4** Expand and Contract keep soft edges soft? *Recommend yes,* per FR-3.4.

### Before stage 8

- **Q8.1** Key: ⇧⌘V is Paste into New Image here. *Recommend ⌥⇧⌘V,* which is free in Colorbee today.
- **Q8.2** A picture copied in another app has no place: paste it as ⌘V would, with no beep? *Recommend yes.*
- **Q8.3** Into a different-sized document: the same position if it lands on the canvas, otherwise as ⌘V?
  *Recommend yes.*
- **Q8.4** Should Clipboard History items remember their place too? *Recommend no;* keep it simple.

### Before stage 9

- **Q9.1** Edit ▸ Color Range… and Luminance Range…, next to Select Subject? *Recommend yes.*
- **Q9.2** It reads the active layer, with the Magic Wand's Sample All Layers switch to read everything shown?
  *Recommend yes:* that matches the Magic Wand and Select Subject.
- **Q9.3** Combining: Replace, Add, Subtract and Intersect in the bar, with Replace first? *Recommend yes.*
- **Q9.4** Fuzziness 0–100%, starting at 25%? *Recommend yes.*
- **Q9.5** Luminance Range: a two-handle range with Smoothness, plus Shadows, Midtones and Highlights buttons?
  *Recommend yes.*

### Before stage 10

- **Q10.1** Edit ▸ Graduated Selection, which opens a canvas tool like Straighten's line, rather than a toolbar
  tool? *Recommend the menu:* the toolbar is full, and it's an occasional tool.
- **Q10.2** Fully selected where the drag starts, fading to nothing where it ends? *Recommend yes,* as in Lightroom.
- **Q10.3** The same combining choices as Q9.3? *Recommend yes.*
- **Q10.4** Shift keeps the line at 0°, 45° or 90°? *Recommend yes.*

### Before stage 11

- **Q11.1** Import only from the filter strip's menu, with no opening of .cube files from Finder? *Recommend yes:*
  it's simpler.
- **Q11.2** Apply looks to the document's own color values, as Photoshop's Color Lookup does? *Recommend yes:* it's
  simple and predictable. The other way converts through sRGB first, closer to what the look's maker saw on sRGB
  pictures.
- **Q11.3** Name it from the file's TITLE line, or the file name if there's none? *Recommend yes.*
- **Q11.4** A look filter exported as .colorbeefilter carries its table (1–3 MB)? *Recommend yes.*

### Before stage 12

- **Q12.1** A snapshot keeps its own copy, so it survives new edits, rather than a marker that can vanish?
  *Recommend a copy:* a snapshot that disappears would be a nasty surprise.
- **Q12.2** Not saved in the project, like undo history? *Recommend not saved:* it keeps files small and redaction
  safe.
- **Q12.3** "Remove Earlier Versions and Undo History" after a redaction deletes snapshots too? *Recommend yes:*
  otherwise a snapshot could bring a secret back.
- **Q12.4** Where: a New Snapshot… button in the History panel, plus Edit ▸ New Snapshot… with no key? *Recommend
  yes.*
- **Q12.5** Going to a snapshot is an undo step of its own ("Go to Snapshot"), so ⌘Z comes back? *Recommend yes:*
  nothing is lost.
- **Q12.6** Each page has its own snapshots? *Recommend yes,* like its undo history.

### Before stage 13

- **Q13.1** Radius 0.5–3 px, Detail 0–100, Masking 0–100, with Luminance and Color noise reduction each with Detail;
  defaults that match today's look? *Recommend yes,* so old edits don't change.
- **Q13.2** Option-drag on Masking shows the edge mask on the picture (display only)? *Recommend yes,* as in
  Lightroom.
- **Q13.3** The extra settings under a disclosure arrow next to Sharpness and Noise Reduction? *Recommend yes:* it
  keeps the panel short.

### Before stage 14

- **Q14.1** Vignette Midpoint, Roundness and Feather start at today's shape? *Recommend yes.*
- **Q14.2** Grain: Amount 0–100, Size 0–100 (starting at 25), Roughness 0–100 (starting at 50)? *Recommend yes,*
  as in Lightroom.
- **Q14.3** Effects ▸ Vignette… stays as it is? *Recommend yes* (§23, 2026-10-03 kept both).
- **Q14.4** A new Effects section holding Vignette and Grain, with Vignette moved out of Detail? *Recommend yes,* as
  in Lightroom.

### Before stage 15

- **Q15.1** Adjust Photo has no histogram: add a live one at the top of the panel? *Recommend yes.*
- **Q15.2** Clipping warnings as two buttons on the histogram, off by default, with no key? *Recommend yes.*
- **Q15.3** Naming: Adjust Photo already has Highlights and Shadows. *Recommend* putting the curve's four regions
  under a "Tone Curve" heading, named Highlights, Lights, Darks, Shadows, so the heading tells them apart.
- **Q15.4** A parametric curve only, since Adjustments ▸ Curves… already does point curves? *Recommend yes,* per
  FR-9.7.

### Before stage 16

- **Q16.1** The hand drives the tone curve, or the Color Mixer tab showing, depending on which section's hand you
  click? *Recommend yes.*
- **Q16.2** Dragging up is more? *Recommend yes,* as in Lightroom.

### Before stage 17

- **Q17.1** Find corners automatically every time Perspective Correction opens, falling back to today's corners,
  with a Reset button? *Recommend yes.*
- **Q17.2** Overlays: Thirds, Grid, Diagonal, Triangle, Golden Ratio, Golden Spiral; O switches between them while
  cropping (O is free). Shown while dragging, as thirds are now? *Recommend yes.*
- **Q17.3** Crop… already shades what it cuts out. What should change? *Recommend* looking at today's Crop… first;
  if it's enough, this part is done. Otherwise tell me what you'd like: darker, or fully hidden.

### Before stage 18

- **Q18.1** One click, Image ▸ Trim: transparent borders if there are any, otherwise the top-left pixel's color.
  No dialog? *Recommend yes:* it's immediate, like Paint. Photoshop's dialog with choices is the other way.
- **Q18.2** A small fixed tolerance (about 2%) so JPEG edges still trim? *Recommend yes.*
- **Q18.3** Decided by everything shown, with all layers cropped together? *Recommend yes,* the same as Crop.

### Before stage 19

- **Q19.1** The color choice goes in Export… and in each Export As preset (Settings), while Copy, Share and PDF keep
  the document's profile? *Recommend yes:* those are the "sending it somewhere" paths.
- **Q19.2** "Limit file size to [ ] KB/MB" as a checkbox in Export…? *Recommend yes.*
- **Q19.3** If it can't fit even at the lowest quality: a message with the smallest size possible, and nothing
  written? *Recommend yes;* shrinking the picture is Export As's job.
- **Q19.4** Remember both settings between launches? *Recommend yes,* like format and quality.
- **Q19.5** Just sRGB, Display P3 and Keep, with no Adobe RGB? *Recommend yes,* per FR-9.7.

### Before stage 20

- **Q20.1** Read what you see (all layers), like the Eyedropper's Option-click? *Recommend yes.*
- **Q20.2** Show the document's own values (they match what the Eyedropper picks), or sRGB (it matches a style
  guide's hex)? *Recommend sRGB, labeled "sRGB":* checking brand colors is the stated use, and style guides are in
  sRGB. Your call, since it won't match the color panel's Display P3 numbers.
- **Q20.3** Sample sizes 1 px (the default), 3 × 3 and 5 × 5? *Recommend yes.*
- **Q20.4** The readout follows the sample size while the Eyedropper is chosen, and a click on the hex copies it?
  *Recommend yes to both.*

### Before stage 21

- **Q21.1** Test picture: real faces can't go in the public repo. *Recommend* a photo of your own, kept outside the
  repo like the small-subjects screenshot. Or I can try made-up pictures first and see whether Vision finds faces
  in them.
- **Q21.2** A "Faces" row in the pattern list, on by default? *Recommend on:* a missed face is the risk.
- **Q21.3** Boxes 30% bigger than Vision's, to cover hair and chin? *Recommend yes.*
- **Q21.4** The same treatment as the text matches (one choice in the sheet)? *Recommend yes:* it's simplest.
- **Q21.5** List even tiny faces, for you to untick? *Recommend yes.*

### Before stage 22

- **Q22.1** Select All Layers on ⌥⌘A (Photoshop's; free in Colorbee)? *Recommend yes.*
- **Q22.2** Includes hidden and adjustment layers? *Recommend yes,* all layers.
- **Q22.3** Isolating, and undoing it, are each one undo step, since showing and hiding are steps today?
  *Recommend yes.*
- **Q22.4** If you change visibility while isolated, the second Option-click shows everything? *Recommend yes;* it's
  predictable.
- **Q22.5** Stamp Visible goes just above the active layer, named "Stamp", with no default key (⌥⇧⌘E is Merge
  Visible here)? *Recommend yes.*

### Before stage 23

- **Q23.1** The padlock becomes a small menu (Lock All, Lock Transparent Pixels), and the row shows which?
  *Recommend yes.*
- **Q23.2** The Eraser on such a layer paints Color 2 inside the shape, with no holes? *Recommend yes,* close to
  Photoshop.
- **Q23.3** Every tool, effect, adjustment and Delete respects it? *Recommend yes.*

### Before stage 24

- **Q24.1** Aligning a big layer to a small selection could push pixels off the canvas. *Recommend* refusing with a
  message when that would happen, since pixels past the edge are lost.
- **Q24.2** Go by each layer's visible pixels? *Recommend yes.*
- **Q24.3** One chosen layer aligns to the canvas, or to the selection if there is one? *Recommend yes.*
- **Q24.4** Greyed out if a chosen layer is locked, like Merge Layers? *Recommend yes.*

### Before stage 25

- **Q25.1** Groups inside groups? *Recommend yes;* it costs little with the flat-list design.
- **Q25.2** Pass Through by default (adjustments inside affect everything below), with Normal as an option
  (adjustments affect only the group)? *Recommend yes,* as in Photoshop.
- **Q25.3** ⌘G Group and ⇧⌘G Ungroup (free in Colorbee)? *Recommend yes.*
- **Q25.4** Hiding or locking a group hides or locks everything in it? *Recommend yes.*
- **Q25.5** Older betas show a group as an empty layer and lose the grouping: acceptable? *Recommend yes,* with the beta after stage 26.
- **Q25.6** Merge Down on a group merges the group into one layer? *Recommend yes.*
- **Q25.7** Named "Group 1", "Group 2"…? *Recommend yes.*

### Before stage 27 and 28

- **Q28.1** Masks on adjustment layers? *Recommend yes,* in part 2: it's local, non-destructive Adjust Photo.
- **Q28.2** Masks on groups? *Recommend yes,* in part 2.
- **Q28.3** While a mask is chosen, the color wells and swatches turn to grays, and D gives white and black?
  *Recommend yes,* as in Photoshop.
- **Q28.4** "Only the layer below" for pixel layers too (from the gap analysis answer)? *Recommend yes,* in part 2;
  it's the same switch adjustments have.
- **Q28.5** Redaction changes hidden pixels too, and the help says masks don't hide secrets. Older betas show
  masked parts. *Recommend* accepting this, with the help's warning.
- **Q28.6** Add Mask uses the selection when there is one? *Recommend yes.*
- **Q28.7** No default keys for mask commands? *Recommend yes.*

### Before stage 29

- **Q29.1** Does every text become its own layer (as in Photoshop), or only with an "Editable" switch in the Text
  options, off by default? Every-text-a-layer means an annotated screenshot saves as a .colorproj instead of a PNG
  (§23, 2026-10-03). *Recommend the switch, off by default:* the quick screenshot flow stays as it is, and you turn
  it on when you want to edit text later. Either way FR-6.3 changes.
- **Q29.2** Painting or effects on a text layer: refused, with "Rasterize Text first"? And redaction turns it into
  pixels automatically, since redaction must win? *Recommend yes to both.*
- **Q29.3** Resizing, rotating or cropping the image redraws text layers so they stay crisp, and skew turns them into
  pixels? *Recommend yes.*
- **Q29.4** A missing font: keep the drawn pixels and say "Font missing" when you edit? *Recommend yes.*
- **Q29.5** Re-edit by double-clicking with the Text tool, or double-clicking the layer's thumbnail? *Recommend
  both.*
- **Q29.6** Merge and Flatten turn text into pixels? *Recommend yes.*

### Before stage 31

- **Q31.1** Which tools: the Brushes, Eraser, Redact Brush and Retouch brushes, but not the Pencil (pixel art wants
  exact pixels)? *Recommend yes.*
- **Q31.2** One shared Smoothing value, remembered? *Recommend yes.*
- **Q31.3** The line catches up to the pointer on release? *Recommend yes.*
- **Q31.4** A "pulled string" feel (the line moves only once the pointer pulls away), as Photoshop does?
  *Recommend yes.* I'll give you a test build to try before finishing.
