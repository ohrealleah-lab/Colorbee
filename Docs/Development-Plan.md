# Colorbee Development Plan: after feature-complete

_Written 2026-10-27 by Claude for Leah. Planning only: no code or FRD changes. Functional decisions are Leah's; the questions are at the end._
_Updated 2026-10-27 after an independent review checked the plan against the code: stage 1 and stage 28 are now in two
parts each, filters gain a way to hold more than colors, and test builds get their own settings folder. Then
updated again with Leah's answers on snapshots (a cap) and the color readout (status bar only), thumbnails in the
layer stages, and a stage 12 hand-test fix._

**Scope:** FR-9.7 (all ten items), multi-select layers (FR-8.6), the approved layer follow-ups, layer masks,
re-editable text, stroke smoothing, Paste in Place and Trim.

**How to read this**
- 31 numbered stages in five parts (stages 1, 18 and 28 have an a and a b): **A** photo editing (FR-9.7), **B**
  layer follow-ups, **C** layer masks, **D** re-editable text, **E** stroke smoothing. The three small extras (Paste
  in Place, Trim and the Canvas Size anchor) sit inside part A, next to related work.
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
   back as an empty layer with the same name, and the adjustment is gone. Stage 1a fixes this going forward (Q0.3).
   - **Why:** the sliders are saved as a list of name and value pairs. Beta 7 can't read a slider name it doesn't
     know (`PhotoAdjustments.init(from:)`), and that loses the whole adjustment. It ignores anything saved *next to*
     the list. So new controls are saved as new entries beside the list, never as new slider names; beta 7 then
     opens them with only the new controls missing. (Beta 7's reading code is the same as today's; checked against
     tag `v0.9.0-beta.7`.)
   - **Reading tolerantly isn't enough on its own.** An older copy that skips what it doesn't know writes the file
     back without it the next time it saves. Your everyday copy and the test builds share one Application Support
     folder (same bundle ID, no sandbox), so a filter saved by a later test build would lose its new settings the
     next time you saved or deleted a filter in your everyday copy. So test builds get their own settings folder
     (Q0.6), and `make test` never writes to yours.
5. **How Adjust Photo works today**, since most of part A builds on it:
   - The 15 sliders are one list of named values. Filters scale those values by their Intensity.
   - **Color and tone** settings use exact math in exports. On screen, an Adjust Photo layer uses a 33-point color
     table, which can differ from the export by about one level (accepted in §23, 2026-10-03).
   - **Sharpness, Definition, Noise Reduction and Vignette** are worked out in the display shader from blurred
     copies of the image.
   - **Saved filters hold color and tone only.** Save as Filter leaves out the detail sliders and Vignette.
   - **A filter only ever changes colors.** Its steps are applied through their color part alone
     (`PhotoEdit.colorTransform`), and Vignette is read only from the panel's own slider, in the core
     (`Effects.photoAdjusted`) and on screen (`adjust_photo_fragment`). A filter holding Dehaze, Vignette or Grain
     (Q0.4) would do nothing, so stage 1a gives filters a way to carry settings that aren't colors.
   - **An Adjust Photo step with any detail slider is dropped whole from a filter** (`Effect.isColorOrTone` is
     all-or-nothing). Today, Save Filter from Layers skips an Adjust Photo layer entirely if its Sharpness is above
     0. Stage 1a changes this to keep the parts a filter may hold and leave out only the rest, as FR-9.7's rule says.
   - **While Adjust Photo is open, the picture is view-only:** any drag pans (§23, 2026-10-02). The white-balance
     eyedropper, Point Color, Color Range and drag-to-adjust all need clicks on the picture, so stage 1b adds a
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
| 7 | §23 vs gap analysis answer 2b | §23 says "then layer masks". The gap analysis answer also says "clip-to-layer-below" for pixel layers. Is that included? | Q28.4 (answered: yes) |
| 8 | Paste in Place shortcut | Photoshop's ⇧⌘V is Colorbee's Paste into New Image. | Q8.1 |
| 9 | Stamp Visible shortcut | Photoshop's ⌥⇧⌘E is Colorbee's Merge Visible. | Q22.5 |
| 10 | Adjust Photo slider names | Adjust Photo already has Highlights and Shadows sliders. A Lightroom tone curve's regions use the same names. | Q15.3 |
| 11 | History Snapshots vs §23 2026-10-03 (6b) | Undo history isn't saved in the project. Are snapshots? And must "Remove Earlier Versions and Undo History" after a redaction delete them too? | Q12.2, Q12.3 |

---

## 2. Shared checklists

### Every new Adjust Photo control goes through these

1. **Panel:** the control appears in Adjust Photo and in the Adjustments panel for an Adjust Photo layer. Both use
   the same `PhotoControls` view. Reset, Control-click to reset, sliding on the name and "Set by Auto" all work.
2. **Saved:** it's stored in `PhotoEdit` as a new entry beside the slider list, never as a new slider name (so
   beta 7 still opens the file, section 1). It's read back safely, and a missing value means neutral. Projects and
   filters from before open unchanged (the FR-9.7 rule).
3. **Exports:** exact math in the core (`PhotoAdjustments`, `Effects.photoAdjusted`).
4. **Screen:** the live preview and an Adjust Photo layer match the export. Color-only controls go through the
   color table. Controls that look at neighboring pixels or at the pixel's position go in `adjust_photo_fragment`
   with `Renderer`, and in `Canvas.pixelAsShown` (stage 20).
5. **Filters:** in or out by category (Q0.4). Intensity scales only amounts, never shape settings (Q0.7). A
   setting that isn't a color goes through the filter path stage 1a builds, in the core and on screen. Save as
   Filter and Save Filter from Layers keep it or leave just it out; they never drop the whole step.
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
| `Old Adjust Photo.colorproj`, `Old Filter.colorbeefilter` | Saved from **today's** build, before stage 1a changes anything. The project holds the practice photo with three Adjust Photo layers: one with every slider set to a non-zero value; one with a built-in filter at 60% Intensity plus a few sliders; and one set to "Only the layer below". The filter is a Save Filter from Layers of the first two. | Proving old files open unchanged (stages 1a, 13, 14) |
| `Color Cast.png` | The Stage 9 practice photo with a blue cast and a gray card | White-balance eyedropper |
| `Texture Practice.png` | The practice photo with fine grass and bark detail drawn into the hills | Texture |
| `No Rectangle.png` | Soft hills and round clouds, with nothing rectangular | Perspective Correction with nothing to find |
| `Dull Photo.png`, `Bright Photo.png` | The Stage 9 practice photo with its brightest parts dimmed to light gray, and with a patch of pure white | Auto's Whites |
| `Hazy.png` | The practice photo with haze added | Dehaze |
| `Color Chart.png` | Patches of the eight color ranges, skin tones and a gray ramp, saved in sRGB, with a list of each patch's sRGB values and hex | Color Mixer, Grading, Point Color, Color Range, curve, readout |
| `Noisy.png` | The practice photo with noise added | Noise reduction, sharpening |
| `Looks/Warm.cube`, `Looks/Identity.cube`, `Looks/Curve 1D.cube` | Written by a script (the last is a one-dimensional look) | .cube looks |
| `Trim Practice.png`, `Trim Practice Solid.png` | A picture with a transparent border; one with a white border | Trim |
| `Align Practice.colorproj` (in `TestImages/Several Layers/`) | Three badges on their own layers, out of line | Align and Distribute |
| Faces picture | Your choice (Q21.1) | Auto-redact faces |

---

## 3. Part A: Lightroom-style photo editing (FR-9.7)

The order follows FR-9.7's numbering, with two moves. "Same as Last" and copy/paste settings (item 4) come second:
they work on all of Adjust Photo's settings, so every later control is included automatically, and they deliver
your main aim of re-applying a look early. Black and White mix (item 6) is built with the Color Mixer (item 1),
since both use the same eight color ranges.

### Stage 1a. Adjust Photo groundwork: files, filters and sections

1. **What gets built**
   - **Fixtures first:** `Old Adjust Photo.colorproj` and `Old Filter.colorbeefilter` are saved from today's build
     before anything changes (recipe in section 2).
   - Room in Adjust Photo's saved settings for new controls, including ones that aren't a single slider (tables,
     colors, curves). Each is saved as a new entry beside the slider list, never as a new slider name, so beta 7
     still opens the file with only the new controls missing. Each starts at neutral, so filters and projects from
     before open unchanged.
   - Reading that skips a setting it doesn't know, instead of dropping the whole adjustment.
   - Saved filters move to a new file, copied once from the old one, so an older Colorbee can't wipe them (Q0.3).
   - **Test builds get their own settings folder** (Q0.6): every build except a signed beta keeps its Application
     Support files (saved filters, and later the last-used settings) in a folder of its own, and `make test` never
     writes to your real one. So test builds can't change your everyday copy's filters. The first time a test build
     runs, it copies your filters in, so you can try them there.
   - **Filters that hold more than colors:** a filter can carry settings that aren't a color change, and they're
     applied in exports (`Effects.photoAdjusted`) and on screen (`adjust_photo_fragment`). Intensity scales only
     their amounts (Q0.7). Vignette is the first one, since it exists today and you chose to keep it in filters
     (Q0.4): Save as Filter now keeps it.
   - **Keep, don't drop:** Save as Filter, Save Filter from Layers and importing keep the parts a filter may hold
     and leave out only the rest. An Adjust Photo layer with Sharpness set is no longer skipped whole.
   - Panel sections you can fold: Light, Color and Detail now, with more sections in later stages.
   - Covers the FR-9.7 rule.
2. **Depends on:** nothing. **Touches:**
   - Core: `PhotoAdjustments.swift` (reading and writing), `PhotoFilter.swift` (`isColorOrTone`, `fromLayers`,
     `scaled(by:)`), `Effect+Codable.swift`, `Effects+Photo.swift`.
   - App: `AdjustPhotoPanel.swift`, `AdjustmentsPanel.swift`, `FilterStore.swift` (the new file and folder),
     `Renderer.swift` and `Shaders.metal` (a filter's vignette), `TestHost.swift`.
3. **Risks**
   - **Old projects and filters:** proven by the fixture files.
   - **Your filters:** the copy to the new file happens once, the first time a build with this stage runs. Until the
     beta after this stage, don't save or delete filters in beta 7, since they won't carry over (Q0.3).
   - **Built-in filters** hold no vignette, so they look exactly as before.
   - **Performance:** none new; Vignette is already worked out in the shader.
   - Questions: Q1.1.
4. **Size:** M. **Opus, high:** every later stage builds on this format and these filters.
5. **Hand test** (`TestImages/Photo Editing/`: `Old Adjust Photo.colorproj`, `Old Adjust Photo (as shown before stage
   1a).png`, `Old Filter.colorbeefilter`; `TestImages/Stage 9 Practice Photo.png`, `TestImages/Help/Sample Screenshot.png`)
   1. Open `TestImages/Stage 9 Practice Photo.png` and choose Adjustments ▸ Adjust Photo…. The filter strip has
      **all of your own saved filters** (such as My Filter 2), each looking as it does in beta 7. Cancel.
   2. Open `Old Adjust Photo.colorproj`, and open `Old Adjust Photo (as shown before stage 1a).png` in Preview beside
      it: they look the same. Click each Adjust Photo layer and check its numbers in the Adjustments panel:
      - **Every Slider:** Exposure +10, Brilliance +15, Highlights −20, Shadows +25, Contrast +12, Brightness +8, Black
        Point +6, Saturation +18, Vibrance +22, Warmth +14, Tint −6, Sharpness 30, Definition 20, Noise Reduction 15,
        Vignette −25.
      - **Vivid Warm 60%:** Vivid Warm chosen, Intensity 60%, with Exposure −5, Contrast +10, Warmth −8.
      - **Layer Below Only:** Saturation −40, Brightness +10, Sharpness 25.
   3. In the filter menu (the ⋯ beside Filters), choose Import… and pick `Old Filter.colorbeefilter`: an "Old Filter"
      chip appears. On the practice photo, Adjust Photo ▸ Old Filter: warmer and more colorful, as in beta 7. Cancel.
   4. On the practice photo, Adjust Photo: Vignette +60 (the edges darken) and Saturation +30. Choose ⋯ ▸ Save as
      Filter… and name it "Dark Edges". Vignette and Saturation go back to 0, Dark Edges is chosen, and the picture
      doesn't change. Cancel.
   5. Open `TestImages/Help/Sample Screenshot.png`, Adjust Photo, choose Dark Edges: the corners darken. Intensity
      50%: half as dark. Back to 100%, then As Adjustment Layer: the corners still darken. File ▸ Export… as a PNG and
      open it in Preview: its corners match the screen.
   6. In Adjust Photo, click the **Light**, **Color** and **Detail** headings: each folds away and opens again. Leave
      Detail folded, quit Colorbee, reopen it and open Adjust Photo: Detail is still folded. It's folded in the
      Adjustments panel for an Adjust Photo layer too.
   7. In the old project, hide **Vivid Warm 60%** and **Layer Below Only** (their eyes). Choose ⋯ ▸ Save Filter from
      Layers… and name it "Every Slider Filter": it's saved (beta 7 would say there are no color or tone layers). On the
      practice photo it changes the colors and lightens the corners a little, with no sharpening.
   8. Quit, then open your everyday beta 7: your filters are just as they were, and Dark Edges, Old Filter and Every
      Slider Filter aren't there (test builds keep their own).
6. **Done when:** tests cover saving and reopening, the fixtures, beta 7's reading of a file with a new entry (its
   decoder, kept in a test), filters keeping and leaving out the right parts, and a filter's vignette in exports.
   On screen, the vignette is checked by hand (step 5): the app tests can't draw the Metal canvas. Help and STATUS are
   updated, and the beta is cut (Q0.3).

### Stage 1b. Whites and the white-balance eyedropper

1. **What gets built**
   - **Pick from the picture:** while Adjust Photo is open, or an Adjust Photo layer is being edited, a dropper
     button lets one click sample the picture. Space-drag and scrolling still pan.
   - A **Whites** slider, and the **white-balance eyedropper**: click something that should be gray, and it sets
     Warmth and Tint. It reads the picture before Adjust Photo's other settings; on an Adjust Photo layer, the
     layers below it (Q1.7). So a click on gray comes out neutral whatever Exposure or filter is set.
   - **Auto sets Whites** too (Q1.3): it raises Whites on a photo whose brightest parts fall short of white, and
     leaves it at 0 otherwise.
   - Covers item 1's eyedropper and Whites.
2. **Depends on:** stage 1a. **Touches:**
   - Core: `PhotoAdjustments.swift` (Whites), `PhotoAuto.swift`.
   - App: `AdjustPhotoPanel.swift`, `AdjustmentsPanel.swift`, `Editor.swift` (the Adjust Photo session, pick mode),
     `CanvasView.swift` (clicks while a bar is open).
3. **Risks**
   - **Strong color casts:** Warmth and Tint are gentle channel multipliers, so a very strong cast may need more
     than ±100 can give. The eyedropper then stops at the limit (Q1.5).
   - **Pick mode:** while the dropper is on, it suspends "the canvas is view-only while a bar is open".
   - **Performance:** none. Whites is color-only, so it goes in the color table.
   - Questions: Q1.2 to Q1.7.
4. **Size:** S–M. **Opus, high** (a new kind of canvas click).
5. **Hand test** (in `TestImages/Photo Editing/`: `Color Cast.png`, `Dull Photo.png`, `Bright Photo.png`; and
   `TestImages/Stage 9 Practice Cutout.png`)
   1. Open `Color Cast.png` and choose Adjustments ▸ Adjust Photo…. A **Whites** slider sits just above Black
      Point, and a small **eyedropper** button sits beside Warmth's number.
   2. Click the eyedropper (it turns blue), then click the gray card at the top left. The card turns gray and the
      blue cast goes; Warmth is about +74 and Tint about −12, and the eyedropper is off again. Apply, then ⌘Z: it's all
      undone in one step.
   3. Open Adjust Photo again, choose Vivid Warm, then use the eyedropper on the gray card: the card still comes out
      gray (Warmth about +96). Cancel.
   4. Open Adjust Photo again and click the eyedropper, then press **Esc**: the eyedropper turns off and Adjust Photo
      stays open. Press Esc again: Adjust Photo closes.
   5. Open Adjust Photo again and drag Whites to +60: the moon and the bright sky get brighter, and the dark hills
      barely change. Drag it to −60: the brights dim. Cancel.
   6. Open `Dull Photo.png`, Adjust Photo ▸ Auto: Whites moves up and shows "Set by Auto". Cancel. Open
      `Bright Photo.png` (it has a pure white cloud), Adjust Photo ▸ Auto: Whites stays at 0. Cancel.
   7. Open `TestImages/Stage 9 Practice Cutout.png` and choose Image ▸ Remove Background. Open Adjust Photo, click the
      eyedropper, then click an empty (checkered) area: a beep, and the eyedropper stays on. Press Esc, then Cancel.
   8. On `Color Cast.png`, choose Layer ▸ New Adjustment Layer ▸ Adjust Photo. In the Adjustments panel, click the
      eyedropper, then the gray card: the card turns gray. ⌘Z undoes it in one step; ⇧⌘Z brings it back. Save as a
      project, close and reopen: still gray, and Warmth and Tint show the same numbers.
6. **Done when:** tests cover an eyedropper click on a made-up gray patch coming out neutral within one level (also
   under a filter), Auto's Whites on a dull and a bright image, and Whites in filters at 50%. Help and STATUS are
   updated.

### Stage 2. Same as Last, and copy and paste settings

1. **What gets built:** re-apply the last Adjust Photo settings to the selection or active layer. Copy Settings
   and Paste Settings put one picture's look on another, in the same or another document. Covers FR-9.7 item 4
   (first two parts).
2. **Depends on:** stage 1a. **Touches:** `Editor.swift` (the Adjust Photo session), `AdjustPhotoPanel.swift`,
   `MainMenu.swift` (Adjustments menu), and a small new store for the last-used and copied settings (app side).
3. **Risks**
   - What counts as "last", and whether it survives a relaunch (Q2.2).
   - Copied settings stay out of the Mac clipboard, so the image you copied isn't replaced.
   - **History:** one undo step, the same as Apply today.
   - Questions: Q2.1 to Q2.5.
4. **Size:** S–M. **Opus, medium.**
5. **Hand test** (`TestImages/Stage 9 Practice Photo.png`, `TestImages/Photo Editing/Color Cast.png`)
   1. Open `TestImages/Stage 9 Practice Photo.png` and choose Adjustments ▸ Adjust Photo…. Choose **Vivid**, set
      Exposure +20, and Apply.
   2. Open `Color Cast.png` and choose **Adjustments ▸ Adjust Photo: Same as Last**: it gets Vivid and Exposure +20 at
      once, as one step ("Adjust Photo" in the History panel). ⌘Z.
   3. Back on the practice photo, open Adjust Photo, choose **Noir**, and click **Copy Settings** (the two-page icon beside Auto). Cancel.
   4. On `Color Cast.png`, choose **Adjustments ▸ Paste Photo Settings**: Adjust Photo opens with Noir chosen, and the
      picture shows it in black and white before you apply. Press Return, then ⌘Z.
   5. Choose **Adjustments ▸ Paste Photo Settings as Adjustment Layer**: a "Noir" layer appears. Hide it: the picture
      underneath is unchanged. Show it again.
   6. With that layer chosen, set Exposure −30 in the Adjustments panel, then choose **Adjustments ▸ Copy Photo
      Settings**. Open the practice photo, choose Layer ▸ New Adjustment Layer ▸ Adjust Photo, and click **Paste** in the
      Adjustments panel: the new layer gets Noir and Exposure −30. ⌘Z undoes just that.
   7. Quit Colorbee and open it again. Open any picture and choose Adjust Photo: Same as Last: Noir is applied (the last
      settings used were the pasted layer's, in step 5).
   8. In Preview, copy a picture (⌘C). In Colorbee, open Adjust Photo on any picture, click Copy Settings, Cancel, then press ⌘V:
      the picture from Preview pastes, so copying settings didn't replace it.
6. **Done when:** app tests check that last and pasted settings equal the source. Help is updated, and `make help`
   has run for the new menu items.

### Stage 3. Texture and Dehaze

1. **What gets built:** **Texture** brings out or softens fine detail without Definition's wider halos (a negative
   value smooths skin). **Dehaze** removes haze (a negative value adds it). Covers FR-9.7 item 1.
2. **Depends on:** stage 1a. **Touches:**
   - Core: `PhotoAdjustments.swift` (math), `Effects+Photo.swift`.
   - App: `Shaders.metal` (`adjust_photo_fragment`), `Renderer.swift` (one more blurred copy for Texture; for
     Dehaze, a "darkest nearby" pass and a haze estimate passed in).
   - Tests: `PerformanceTests.swift`.
3. **Risks**
   - **Dehaze looks at the whole picture** to estimate the haze color (the standard "dark channel" method). On an
     adjustment layer, painting below changes that estimate. It's refreshed in the background at a reduced size,
     and exports use the same numbers, so the screen and the file agree.
   - **Dehaze also looks at neighbors:** how hazy each pixel is comes from the darkest color in a small patch
     around it. That's an extra pass on the GPU every frame, and in the core for exports, like Definition's blur.
     So Dehaze isn't a pure tone change; in a filter it goes through stage 1a's path for settings that aren't
     colors.
   - **Performance:** one more blur and one "darkest nearby" pass per frame under an Adjust Photo layer; strokes
     beneath it must stay under 16 ms.
   - **Filters:** Dehaze is saved in filters, and Intensity scales its amount; Texture isn't saved (Q0.4).
   - **Look:** Definition is already close to Lightroom's Clarity, so the hand test puts Texture next to Definition
     to make sure they feel different.
   - Questions: Q3.1, Q3.2.
4. **Size:** M–L. **Opus, high.**
5. **Hand test** (`TestImages/Photo Editing/Hazy.png`, `TestImages/Photo Editing/Texture Practice.png`)
   1. Open `Hazy.png` and choose Adjust Photo. Drag **Dehaze** (in Light, after Brilliance) to +50: the haze lifts, the
      hills turn green again and the sky deepens. Apply, then ⌘Z.
   2. Open Adjust Photo again and drag Dehaze to −50: the picture gets hazier. Cancel.
   3. Open Adjust Photo again, Dehaze +50, then ⋯ ▸ Save as Filter… named "Clear". Open `Texture Practice.png` and
      choose Clear: it gets clearer and more contrasty too (filters keep Dehaze). Cancel.
   4. On `Texture Practice.png`, zoom to 200% on the hills. Adjust Photo, **Texture** (in Detail, after Definition)
      +60: the grass grain gets crisper, with no glow along the hills' edges. Try −60: it smooths.
   5. Set Texture back to 0 and Definition to +60: now a wider glow runs along the hills' edges. That's the difference
      between them. Cancel.
   6. Open Adjust Photo, Texture +60, then **As Adjustment Layer**. Choose the Background layer and paint a few Brush
      strokes across the hills: drawing stays smooth, and the strokes get the crisper look too.
   7. File ▸ Export… as a PNG and open it in Preview. Zoom both to 100%: the grass looks the same.
6. **Done when:** exact-value tests, a screen-versus-export test, and a time limit at 8000 × 8000 all pass. Help is
   updated.

### Stage 4. Color Mixer and Black & White

1. **What gets built**
   - **Color Mixer:** hue, saturation and luminance for each of eight color ranges, blended so there are no hard
     edges between colors.
   - **Black & White:** a switch that makes the picture black and white. The same eight sliders then set how light
     each color becomes.
   - Covers FR-9.7 item 1 (Color Mixer) and item 6 (Black and White mix).
2. **Depends on:** stage 1a. **Touches:** the core (a new `ColorMixer.swift`, plus `PhotoAdjustments`,
   `ColorLookup.swift`), `AdjustPhotoPanel.swift` (a new section).
3. **Risks**
   - **Screen versus export:** narrow color changes through a 33-point table can differ from the export by more than
     today's one level. Adjust Photo layers may need a 65-point table (about 4 MB each); I'll measure first and tell
     you.
   - **Space:** 24 sliders need a compact layout (Q4.2).
   - **Filters:** hue shifts scale toward zero with Intensity.
   - Questions: Q4.1 to Q4.5.
4. **Size:** M. **Opus, high.**
5. **Hand test** (`TestImages/Photo Editing/Color Chart.png` (its colors are listed in `Color Chart.txt`), `TestImages/Stage 9 Practice Photo.png`)
   1. Open `Color Chart.png` and choose Adjust Photo. Under Color there's a **Color Mixer** section. Choose its
      **Saturation** tab and drag **Blue** to −100: only the Blue patch turns gray; Aqua, Purple, the skin patches and
      the grays stay as they are.
   2. Click Reset. Choose the **Hue** tab and drag **Green** to +100: the Green patch leans toward aqua, and nothing
      else moves.
   3. Click Reset. Turn on **Black & White**: the chart turns gray, like the Mono filter, and the tabs give way to eight
      sliders. Drag **Red** to +60: the Red patch becomes a lighter gray (Orange and Magenta a little); Blue, Green and
      the gray patches don't change. Cancel.
   4. Open `TestImages/Stage 9 Practice Photo.png`, Adjust Photo, Color Mixer ▸ **Luminance**, Blue −40: the sky
      darkens; the hills and the moon don't. Apply, then ⌘Z.
   5. Open Adjust Photo again, set Luminance Blue −40 again, then ⋯ ▸ Save as Filter… named "Blue Sky". Set its
      Intensity to 50%: the sky darkens half as much. Cancel.
   6. On `Color Chart.png`, Adjust Photo, Hue tab, Green +100, then **As Adjustment Layer**. File ▸ Export… as a PNG and
      open it in Preview: the patches look the same as in Colorbee.
6. **Done when:** an exact-value test on each patch passes, and the screen-versus-export test is within the agreed
   limit. Help is updated.

### Stage 5. Color Grading

1. **What gets built:** color wheels for shadows, midtones and highlights. Each sets a hue and a strength, with a
   luminance slider, plus Blending and Balance. Covers FR-9.7 item 2 (color grading).
2. **Depends on:** stage 1a. **Touches:** the core (a new `ColorGrading.swift`, the color table), a new
   `ColorWheel.swift` control (app), `AdjustPhotoPanel.swift`.
3. **Risks**
   - **A new kind of control:** a wheel you drag a point around. Fine moves, double-click to reset, VoiceOver.
   - **Intensity** must scale the strength, never the hue (Q5.3).
   - Color-only, so it goes in the color table.
   - Questions: Q5.1 to Q5.4.
4. **Size:** M. **Opus, high** (design-heavy control).
5. **Hand test** (`TestImages/Photo Editing/Color Chart.png`, `TestImages/Stage 9 Practice Photo.png`)
   1. Open `Color Chart.png` and choose Adjust Photo. Under the Color Mixer there's **Color Grading**. On the **Shadows**
      tab, drag the point on the wheel about halfway out toward aqua (the left). On the **Highlights** tab, drag it
      halfway out toward orange (the right, a little up). The gray ramp's dark end turns teal and its light end orange.
      The small dot on the wheel shows where the other wheel is.
   2. Drag **Balance** to the right: more of the ramp turns orange.
   3. Double-click the wheel: its point goes back to the middle. Click Reset.
   4. Drag a point while holding **Option**: it moves slowly, for fine changes. Cancel.
   5. Open `TestImages/Stage 9 Practice Photo.png`, Adjust Photo, set teal shadows and orange highlights as in step 1,
      then ⋯ ▸ Save as Filter… named "Teal and Orange". Set its Intensity to 50%: the same colors, half as strong. Cancel.
   6. Open Adjust Photo again, turn on **Black & White** (in the Color Mixer), then set the Shadows wheel toward blue and
      the Highlights wheel toward yellow: a split-toned black and white. Apply, then ⌘Z.
6. **Done when:** exact-value tests on the ramp pass. Help is updated.

### Stage 6. Point Color

1. **What gets built:** pick a color in the picture, then shift just that color's hue, saturation and luminance,
   with a Range setting for how wide "that color" is. You can pick several colors. Covers FR-9.7 item 2 (Point
   Color).
2. **Depends on:** stage 1b (pick mode) and stage 4 (shared color-range math). **Touches:** the core
   (`ColorMixer.swift` or a new `PointColor.swift`), `AdjustPhotoPanel.swift` (a swatch list), `Editor.swift` (pick
   mode).
3. **Risks**
   - **Saved in a filter,** a picked color still applies to whatever matches it in another picture; Intensity
     scales the shifts, not the picked color.
   - Narrow ranges have the same color-table precision issue as stage 4.
   - Questions: Q6.1 to Q6.3.
4. **Size:** M. **Opus, high.**
5. **Hand test** (`TestImages/Photo Editing/Color Chart.png`)
   1. Open `Color Chart.png` and choose Adjust Photo. In **Point Color** (under the Color Mixer), click its eyedropper,
      then click the **Orange** patch: a swatch appears, with Hue, Saturation, Luminance and Range sliders.
   2. Drag **Hue** to +50: the Orange patch leans toward yellow; Red, Yellow and the skin patches don't change.
   3. Press and hold the **Range** slider's knob: everything Orange doesn't touch turns gray. Still holding, drag it to
      100: the Yellow patch now shows in color too. Let go: the colors come back, and Yellow has shifted a little. Set
      Range back to 50 (Control-click it).
   4. Click the eyedropper again, then the **Skin medium** patch, and drag its Saturation to −80: that patch dulls, and
      Orange keeps its change. Click the first swatch: its sliders show again.
   5. With the skin swatch chosen, click the minus button: it's removed. Apply, then ⌘Z.
   6. Choose Layer ▸ New Adjustment Layer ▸ Adjust Photo. In the Adjustments panel's Point Color, click the eyedropper,
      then the **Blue** patch, and drag Hue to +60: only the Blue patch shifts. ⌘Z undoes the shift, and ⌘Z again the
      picked color.
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
   another one, instead of at the top-left of the view. It sits here only because it's a small Edit menu command
   like stage 7's; the two share no code.
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
2. **Depends on:** stage 1b (pick mode), stage 7 (its menu). **Touches:** the core (a new `ColorRange.swift`,
   `SelectionActions.swift`), `Editor.swift`, `CanvasView.swift`, `MainMenu.swift`, and Feather's red-tint preview
   (reused).
3. **Risks**
   - **What it reads:** the active layer or everything shown (Q9.2). "Everything shown" uses
     `Canvas.pixelAsShown`'s fix from stage 20 if that's built first; until then, adjustments that look at
     neighbors (Vignette, Sharpness, blur layers) aren't included in what it reads.
   - **Combining** with an existing selection (Q9.3).
   - **Redaction** hardens soft selections, as today.
   - Questions: Q9.1 to Q9.5.
4. **Size:** M. **Opus, high.**
5. **Hand test** (`Stage 9 Practice Photo.png`, `Color Chart.png`)
   1. Color Range…, then click the sky. It tints everything but the sky; raise Fuzziness to take in more blue.
      Return.
   2. Adjust Photo, Saturation +40: only the sky changes, with a soft edge at the hills. Apply.
   3. ⌘Z returns the photo as it was.
   4. Open `Color Chart.png`, then Luminance Range… and choose Shadows. On the gray ramp, only the dark end is
      selected, fading in.
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
2. **Depends on:** stage 1a. **Touches:**
   - Core: a new kind of adjustment that holds a color table (`Effects.swift`, `Effect+Codable.swift`,
     `PhotoFilter.swift`), a new `CubeFile.swift` reader, `ColorLookup.swift`.
   - App: `FilterStore.swift` (import).
3. **Risks**
   - **Size:** a big look holds about 800,000 numbers, so it's stored compactly in projects and filter files, not as
     text.
   - **Color:** looks are usually made for sRGB pictures (Q11.2).
   - **Damaged files:** a damaged `.cube` gives a plain message; added to the damaged-file tests.
   - **One-dimensional looks** (a curve per channel, not a color table) get a plain "not supported" message (Q11.5).
   - **Older betas:** older Colorbee versions show such a layer with no settings, as before.
   - Questions: Q11.1 to Q11.5.
4. **Size:** M. **Opus, high.**
5. **Hand test** (`Looks/Warm.cube`, `Looks/Identity.cube`, `Looks/Curve 1D.cube`, `Stage 9 Practice Photo.png`)
   1. Adjust Photo ▸ filter menu ▸ Import…, then choose `Warm.cube`. A "Warm" filter appears; the photo warms.
   2. Intensity 50%: half as warm.
   3. Import `Identity.cube`: no visible change.
   4. As Adjustment Layer, then save, close and reopen: still warm.
   5. Rename a text file to `.cube` and import it: a plain message, and nothing is added.
   6. Import `Curve 1D.cube`: a "not supported" message, and nothing is added.
6. **Done when:** reader tests, including damaged files, pass, and the exact result matches a reference. Help is
   updated.

### Stage 12. History Snapshots

1. **What gets built:** name the current state (for example "Before dramatic"). It shows in the History panel, and
   a click goes back to it. A snapshot keeps its own copy and can be renamed or deleted. There's a cap of about 10
   snapshots, and at the cap a clear message says to delete one first (Q12.1). Covers FR-9.7 item 4.
2. **Depends on:** nothing. **Touches:** the core (`History.swift`, `Canvas.swift` layer-stack state, the disk
   spill), `HistoryPanels.swift`, `Editor.swift`, `MainMenu.swift`.
3. **Risks**
   - **The main one:** Colorbee's history is one straight line, so going back and making a change throws away
     what came after. A snapshot that only marks a step would vanish then. A snapshot that keeps its own copy
     survives anything, but costs memory, which counts against history's budget and spills to disk (Q12.1).
   - **How much space:** a snapshot is a copy of every layer. A one-layer 4000 × 3000 photo is about 48 MB; an
     8000 × 8000 picture with five layers is about 1.3 GB. It won't fill your RAM, since older copies are
     compressed to disk like older history, but it uses disk space, which is why the cap exists. The soak test runs
     at 8000 × 8000 with snapshots.
   - **Redaction safety:** a snapshot from before a redaction would bring the secret back, so clearing history
     after a redaction must clear snapshots too (Q12.3).
   - **Pages:** each page has its own.
   - **Naming:** the app already has a `Snapshot` type (the help-picture runs) and `SaveSnapshot`, so this one gets
     a name of its own, such as `HistorySnapshot`.
   - **Later layer stages** (groups, masks, text layers) add to what a snapshot keeps; each of those stages checks
     snapshots too.
   - Questions: Q12.1 to Q12.6.
4. **Size:** M. **Opus, high** (history).
5. **Hand test** (`Stage 9 Practice Photo.png`, `TestImages/Auto-Redact Practice.png`)
   1. History panel ▸ New Snapshot…, and name it "Start".
   2. Paint a stroke, choose Adjust Photo ▸ Noir ▸ Apply, then Image ▸ Crop… and Return. Click "Start": the
      photo is back as it began.
   3. ⌘Z: you're back at the cropped Noir version.
   4. Click "Start", paint a stroke, then click "Start" again: it still works.
   5. Make a snapshot, then delete it from the panel: it's gone. Make 11 snapshots: at the cap, a message asks you
      to delete one first.
   6. In Finder, duplicate `Auto-Redact Practice.png` and open the copy. Take a snapshot, then Auto-Redact, Solid
      Fill, Apply, ⌘S, and choose Remove Earlier Versions and Undo History. The snapshot is gone.
6. **Done when:** history tests cover going back, undoing a jump, the cap, the memory budget and spilling, and
   clearing on redaction. The soak test includes snapshots. Help is updated.

### Stage 13. Sharpening and Noise Reduction in detail

1. **What gets built:** Sharpness gets Radius, Detail and Masking (sharpen only edges). Noise Reduction splits into
   Luminance and Color, each with Detail. Covers FR-9.7 item 5.
2. **Depends on:** stage 1a. **Touches:** the core (`PhotoAdjustments.detail`, `Effects+Photo.swift`),
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
   Size and Roughness, fixed to the image so the preview matches the export. Vignette and Grain are saved in filters
   through stage 1a's path for settings that aren't colors (Q0.4). Intensity scales only Vignette's and Grain's
   amounts; Midpoint, Roundness, Feather, Size and Roughness stay as saved (Q0.7). Covers FR-9.7 item 5.
2. **Depends on:** stage 1a. **Touches:** the core (`PhotoAdjustments.swift`, `Effects+Photo.swift`, `Vignette`,
   the noise code in `Effects+Texture.swift`, `PhotoFilter.swift` for scaling), `Shaders.metal`, `Renderer.swift`.
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
   3. Save as Filter… named "Film". Open another picture and choose Film at 50%: half the vignette and grain, and
      the grain is the same size as at 100%. An older filter of yours shows no vignette or grain.
6. **Done when:** exact-value tests and the fixture unchanged. Help is updated.

### Stage 15. Tone curve and clipping warnings

1. **What gets built**
   - A **parametric tone curve** in Adjust Photo: four region sliders and three split points, drawn as a curve.
   - A **live histogram** at the top of Adjust Photo, with **clipping warnings:** when they're on, blown highlights
     show red and crushed shadows blue on the picture. This is display only and never exported.
   - Covers FR-9.7 item 6.
2. **Depends on:** stage 1a. **Touches:**
   - Core: a new `ToneCurve.swift`, plus `Histogram.swift` (reused).
   - App: `ToneViews.swift` (the curve graph, reused), `AdjustPhotoPanel.swift`, and `Renderer.swift` with
     `Shaders.metal` (the clipping overlay).
3. **Risks**
   - **The histogram** of the edited result is worked out in the background as sliders move, from a smaller copy on
     big images.
   - **Naming** clashes with the existing Highlights and Shadows sliders (Q15.3).
   - **Filters:** Intensity scales the four region amounts; the split points stay where they were saved (Q0.7).
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
2. **Depends on:** stages 1b, 4 and 15. **Touches:** `Editor.swift` (pick mode with drags), `CanvasView.swift`,
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
5. **Hand test** (`TestImages/Stage 9 Practice Perspective.png`, `No Rectangle.png`)
   1. Image ▸ Perspective Correction…: after "Finding corners…", the corners sit on the whiteboard's corners. Nudge
      one, then Return. The whiteboard is now a straight-sided rectangle, and its grid lines are straight.
   2. Open `No Rectangle.png` and choose Perspective Correction…: the corners are where they are today. (Not the
      practice photo: its black box and striped box are rectangles Vision may find.)
   3. Crop…, then press the overlay key: thirds, grid, golden ratio and so on, in turn.
6. **Done when:** a test on a made-up rectangle (corners within 2 px) passes. Help is updated, and `make help` has
   run if a key was added.

### Stage 18a. Trim (small extra)

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
   3. On the cutout, run Remove Background, then Trim: the edges are tight around the circle and the star together.
      ⌘Z.
6. **Done when:** exact-value tests (including soft edges and one-pixel lines) pass. Help is updated, and `make
   help` has run.

### Stage 18b. Canvas Size anchor (small extra)

1. **What gets built:** Canvas Properties gets an **anchor**: a 3 × 3 grid of squares that chooses where the picture
   stays when the canvas changes size. Today it always stays at the top-left, so new space goes on the right and
   bottom. With Center, new space is split evenly on every side, for an even margin around a screenshot; with
   top-center, it all goes below, for a caption. Shrinking cuts the edges away from the anchor (Q18.5).
2. **Depends on:** nothing. **Touches:** the core (`ImageActions.resizeCanvas` takes where the picture goes, tested
   exactly, including the selection and every layer), `CanvasPropertiesSheet.swift` (the grid, and its preview),
   `Editor.swift`. Help: the Canvas Properties section of `annotate-an-image.html`.
3. **Risks**
   - **Odd sizes:** adding an odd number of pixels with Center can't split evenly; the extra pixel goes on the right
     or bottom.
   - **History:** one undo step, as today (all layers change size together). On a page document, it changes the page
     being viewed.
   - **VoiceOver:** each square says where it puts the picture ("Top left", "Center"…).
   - Questions: Q18.4, Q18.5.
4. **Size:** S. **Opus, medium.** First I'll draft its FRD lines (Q0.1).
5. **Hand test** (`TestImages/Help/Sample Screenshot.png`, 1200 × 760)
   1. Image ▸ Canvas Properties…: the anchor shows Center. Make it 1400 × 960 and press OK: an even 100 px border
      on every side, filled with Color 2. ⌘Z.
   2. Again, choose the top-middle square, make it 1200 × 960: all 200 px of new space is below the picture. ⌘Z.
   3. Again, Center, make it 1000 × 560: 100 px is cut from every side. ⌘Z: the whole picture is back.
   4. Open Canvas Properties once more: the anchor is back on Center.
6. **Done when:** exact tests of each anchor, growing and shrinking, odd sizes, and several layers pass. Help is
   updated.

### Stage 19. Export: color space and Limit file size

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
   - **What a KB is:** Finder counts 1 KB as 1,000 bytes. If Colorbee counted 1,024, a file it calls 200 KB could
     show as 205 KB in Finder (Q19.6).
   - Questions: Q19.1 to Q19.6.
4. **Size:** M. **Opus, high.**
5. **Hand test** (`Stage 9 Practice Photo.png`)
   1. Export…, JPEG, Color sRGB. Open the file in Preview, then Tools ▸ Show Inspector: the profile is sRGB.
   2. Export again with "Keep document's": Display P3, as today.
   3. Limit file size 200 KB: Finder shows 200 KB or less.
   4. Choose PNG: Limit file size is greyed out.
   5. Limit 5 KB on a big image: the message you chose (Q19.3).
6. **Done when:** tests check the profile and the size stays under the limit. Help is updated.

### Stage 20. Color readout and Eyedropper sample size

1. **What gets built:** the status bar shows the color under the pointer, as RGB and hex. The Eyedropper gets a
   Sample Size that averages a small area. Covers FR-9.7 item 9.
2. **Depends on:** nothing. **Touches:** `StatusBar.swift`, `Editor.swift` (the pointer and colors), the
   Eyedropper in `CanvasView.swift`, `PaletteBar.swift` (tool options), and the core's `Canvas.pixelAsShown` (an
   averaging helper, and a fix).
3. **Risks**
   - **`pixelAsShown` misses some adjustments today.** It works out one pixel on its own, so anything that looks
     at neighbors or at where the pixel is gets left out: Vignette, Sharpness, Definition, Noise Reduction, Blur
     and Sharpen layers (and later Texture, Dehaze and Grain). Under such a layer the readout wouldn't match the
     screen. The fix works out a small patch around the pointer, with the vignette placed by the whole canvas.
     This also fixes the Eyedropper's Option-click, which has the same gap today.
   - **Which pixel** (Q20.1).
   - **Which numbers:** the document's own values or sRGB (Q20.2). This decides whether a brand color from a style
     guide matches.
   - **Narrow windows:** the status bar needs room.
   - **Only the status bar:** the Info panel (⌥⌘I) describes the document and doesn't change as the pointer moves,
     so the readout isn't shown there (Q20.5).
   - Questions: Q20.1 to Q20.5.
4. **Size:** S. **Opus, medium.**
5. **Hand test** (`Color Chart.png`, `TestImages/Help/Sample Screenshot.png`)
   1. Move over a chart patch: the status bar shows its RGB and hex, matching the chart's list.
   2. Eyedropper, Sample Size 5 × 5, then click an anti-aliased letter edge in the screenshot: an in-between color.
      At 1 px: one exact pixel.
   3. Point at the gray surround: the readout clears.
   4. Open `Old Adjust Photo.colorproj` and point at a corner of the picture, where the vignette darkens it. Then
      hide the Adjust Photo layers: the readout changes, so it was reading what you see.
6. **Done when:** exact averaging tests, and a test that the readout under a vignette and a blur layer matches the
   export. Help is updated.

### Stage 21. Auto-redact faces

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
   - **It reaches every tool that writes pixels.** Rather than changing each tool, the old transparency is put back
     from history's before-images in one place. That's one place to get right, and history already has those images.
   - **While drawing, not just at the end.** It's put back on each part of a stroke as it's drawn, before it's
     shown, so paint never appears in the empty area and then vanishes when you let go. Strokes must stay under
     16 ms.
   - **Whole pixels:** where a pixel was fully clear, the whole pixel is put back, not just its transparency, so no
     stray colors hide in clear pixels (the Magic Wand and Color Eraser read those exactly).
   - **Edits with no before-images:** flip and rotate, and crop, resize and Straighten, keep no before-images. They
     move the outline itself, so they work as usual on such a layer (Q23.4).
   - **Saving:** a picture with one layer saves as a PNG, so the lock, like today's padlock, isn't kept there
     (Q23.5).
   - **The Eraser** can't make holes (Q23.2).
   - **Older betas** open such a layer unlocked.
   - Questions: Q23.1 to Q23.5.
4. **Size:** M. **Opus, high.**
5. **Hand test** (`TestImages/Stage 9 Practice Cutout.png`)
   1. Open the cutout and choose Remove Background with "put the subject on a new layer" on, so there are two
      layers. Choose the subject layer and lock its transparent pixels.
   2. Paint across it slowly with a big red Brush: the circle and star turn red, and the empty area stays empty the
      whole time, not only when you let go.
   3. Fill Bucket and Gradient inside: the same.
   4. Eraser: it paints Color 2 inside the shape (or the behavior you chose).
   5. Image ▸ Flip ▸ Horizontal: the layer flips as usual, and it's still locked. ⌘Z.
   6. Save (it's a project, since it has two layers), close and reopen: still locked.
6. **Done when:** a test checks that every tool keeps transparency on such a layer, mid-stroke too, with clear
   pixels left exactly as they were. Help is updated.

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
   - Core: `Layer.swift`, `Canvas.swift` (compositing, "Only the layer below", and the layer-stack state history
     keeps), `History.swift`, `ProjectFile.swift`, `LayerActions*.swift`.
   - App: `Renderer.swift` with `Shaders.metal` (an extra pass per group), `LayersPanel.swift`, `LayerMenu.swift`.
   - Also everything that walks the layers: Auto-Redact, the Redact Brush, Subjects, the Eyedropper, Merge,
     Flatten, Save Filter from Layers, Undo on Active Layer, and History Snapshots.
   - **Thumbnails:** `Canvas.thumbnail` draws the page, History-panel and saved-project thumbnails on the CPU,
     separately from the display and export, and only knows simple adjustments. It must handle groups too.
3. **Risks**
   - **The biggest change to the document since pages.** Layers stay one flat list, each naming its group. A group
     itself is a row in that list holding no pixels, and about 77 places in the code go through the list; each must
     skip group rows or treat them right. This also prepares the project format for masks and text layers.
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
2. **Depends on:** stage 25, stage 24 (Align with a chosen group), stage 22 (Stamp Visible) and stage 23 (the
   padlock menu, for locking a group). **Touches:** `LayersPanel.swift` (dragging), `LayerActions+Several.swift`,
   `LayerAlign.swift`, `LayerMenu.swift`, `MainMenu.swift`.
3. **Risks**
   - **Dragging** onto a row versus between rows is fiddly to get right.
   - **Edge cases:** locked layers, and "Only the layer below" at a group's edge.
   - **Locking a group** offers the same two locks as a layer (Q25.4).
   - Questions: Q25.2, Q25.4, Q25.6.
4. **Size:** M–L. **Opus, high.**
5. **Hand test** (`Opacity Test.colorproj`)
   1. Drag Blue into the group, then out again.
   2. Add a Hue/Saturation layer inside the group. With Pass Through it changes everything below; with Normal, only
      the group.
   3. Right-click two chosen layers, then Group chosen layers. Merge Group: one layer, same look.
   4. Choose the group and Align ▸ Left: everything in it moves together. ⌘Z.
   5. Lock the group: none of its layers can be painted. Unlock it.
6. **Done when:** core tests of moving into and out of groups (also nested ones), Merge Group's look, and adjustment
   layers inside Pass Through and Normal groups, screen versus export. Help is updated, and `make help` has run.

---

## 5. Part C: layer masks

### Stage 27. Layer masks, part 1: pixel layers

1. **What gets built:**
   - **Add Mask:** reveal all, hide all, or from the selection.
   - A mask thumbnail next to the layer's. Click it, then paint: black hides, white reveals, grays partly.
   - Delete Mask, and Apply Mask (bake it in).
   - Saved in .colorproj, and the screen matches the export.
2. **Depends on:** stage 25 (the layer model settles first). **Touches:**
   - Core: `Layer.swift`, a one-channel picture type for the mask, `History.swift` (`TileKey` today is layer,
     column and row, so it gains which picture: the layer's or its mask's), `Canvas.swift` with
     `Compositing.swift`, `ProjectFile.swift`, `PageBaseline.swift` (Revert Layer).
   - App: every tool's "where do I draw", `Renderer.swift` with `Shaders.metal`, `LayersPanel.swift`, and Merge,
     Flatten, Copy Merged and Remove Background. `Editor.isLayered` and `ImageDocument.swift` (see Saving).
3. **Risks**
   - **Saving:** today a picture counts as layered (and saves as a project) only with several pages, several layers
     or an adjustment layer (`Editor.isLayered`). A one-layer photo with a mask would save as a PNG and silently
     lose the mask, so a mask makes it a project too.
   - **Per-layer undo:** Undo on Active Layer and Revert Layer include the layer's mask (Q28.8).
   - **Memory:** a one-channel mask is a quarter of a layer's size (64 MB at 8000 × 8000), but it's a new kind of
     buffer for history's disk spill.
   - **History Snapshots** keep masks too.
   - **Thumbnails:** `Canvas.thumbnail` (page, History-panel and saved-project thumbnails) must honor masks, since
     it draws separately from the display and export.
   - **Redaction safety:** a mask hides pixels without removing them. Redaction must change hidden pixels too, and
     the help says masks don't hide secrets (Q28.5).
   - **Older betas** show the hidden parts (Q28.5).
   - **Painting** on a mask must stay under 16 ms.
   - Questions: Q28.3, Q28.5 to Q28.8.
4. **Size:** L. **Opus, high.**
5. **Hand test** (`Stage 9 Practice Photo.png` with `Stage 9 Practice Cutout.png` pasted on a layer above)
   1. Add Mask on the cutout layer, click the mask thumbnail, and paint black on part of it: that part hides, and
      the photo shows through. Paint white: it's back.
   2. Save, close and reopen: the same. Export: it matches.
   3. Paint on the layer itself, then a mask stroke. Edit ▸ Undo on Active Layer: the mask stroke goes. Again: the
      paint goes.
   4. Apply Mask: the hidden part is now gone for real. ⌘Z.
   5. Open the practice photo alone (one layer), Add Mask, paint black on the sky, then ⌘S: it saves as a new
      project (.colorproj) in the photo's folder, as a picture that gains layers does, not over the PNG. Reopen the
      project: the mask is there.
6. **Done when:** compositing, history (undo of mask strokes, Undo on Active Layer, Revert Layer), format, saving and
   memory tests pass. Help is updated, and `make help` has run.

### Stage 28a. Layer masks, part 2: adjustment layers and mask tools

1. **What gets built:**
   - Masks on adjustment layers: local Adjust Photo that never changes pixels, the most Lightroom-like result in
     this plan (Q28.1).
   - Shift-click turns a mask off; Option-click shows it alone; Invert Mask.
   - Masks from Color Range, Luminance Range and graduated selections, through "from the selection".
   - Masks with "Only the layer below", with Merge Layers, Merge Adjustment, and with several chosen layers.
2. **Depends on:** stage 27, and stages 9 and 10 (for masks from those selections). **Touches:** every adjustment
   shader in `Shaders.metal`, `Renderer.swift`, `Canvas.swift`, `AdjustmentsPanel.swift`, `LayersPanel.swift`.
3. **Risks:**
   - Every adjustment display path gets a mask input.
   - Merge Adjustment with a mask.
   - Questions: Q28.1, Q28.5.
4. **Size:** L. **Opus, high.**
5. **Hand test** (`Stage 9 Practice Photo.png`)
   1. Color Range on the sky, then add an Adjust Photo layer with Saturation +50. Its mask is the sky.
   2. Paint on the mask to take the hills back out. Shift-click the mask: the adjustment applies everywhere.
      Shift-click again.
   3. Option-click the mask: you see the mask in gray. Option-click again.
   4. Invert Mask: now only the hills are more colorful. ⌘Z.
   5. Merge Adjustment: the picture looks the same, and the sky's saturation is now in the pixels. ⌘Z.
   6. Save, close and reopen: the same. Export: it matches the screen.
6. **Done when:** screen-versus-export tests for a masked layer of each adjustment kind, Merge Adjustment with a
   mask, and format tests pass. Help is updated, and `make help` has run.

### Stage 28b. Masks on groups, and clipping for pixel layers

1. **What gets built:**
   - Masks on groups (Q28.2).
   - **Only the layer below for pixel layers** (Q28.4, answered yes): a pixel layer shows only where the layer
     under it has pixels, the same switch adjustment layers have today, like a clipping mask.
2. **Depends on:** stages 26 and 28a. **Touches:** `Canvas.swift` (compositing), `Renderer.swift` with
   `Shaders.metal` (a group's off-screen picture with its mask, clipped pixel layers), `LayersPanel.swift`,
   `ProjectFile.swift`, and Merge Down, Merge Layers and Duplicate for clipped pixel layers.
3. **Risks:**
   - **Clipped pixel layers** follow today's rules for clipped adjustments: they stay with their layer when it moves,
     Merge Down bakes them in, and Delete takes them along (FR-8.4).
   - **Older betas** show clipped pixel layers unclipped, and group masks not at all.
   - Questions: Q28.2, Q28.4.
4. **Size:** M. **Opus, high.**
5. **Hand test** (`Opacity Test.colorproj`)
   1. Group Red and Green, Add Mask on the group, and paint black across both: both hide there.
   2. Add a new layer above Blue, paint stripes across the whole canvas, and turn on Only the layer below: the
      stripes show only on Blue.
   3. Move Blue up one place: the striped layer goes with it.
   4. Save, close and reopen: the same. Export: it matches the screen.
6. **Done when:** compositing tests (screen versus export) for group masks and clipped pixel layers, and format
   tests, pass. Help is updated, and `make help` has run.

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
   - App: the Text section of `Editor.swift`, `Editor.isLayered`, `CanvasTextView.swift`, `LayersPanel.swift`.
3. **Risks**
   - **The drawn pixels are stored as an ordinary layer,** so compositing doesn't change, and older betas show the
     text as plain pixels.
   - **Redaction safety:** a text layer keeps its words in the file, so any redaction over it must turn it into
     pixels first (Q29.2).
   - **Thumbnails** need no change, since the drawn pixels are an ordinary layer; a test confirms it.
   - **Missing fonts** on another Mac (Q29.4).
   - **Saving:** a text layer makes the picture a project (`Editor.isLayered`), as a mask does in stage 27;
     otherwise a PNG save would quietly turn the text into pixels. This is why Q29.1 matters.
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
   4. Layer ▸ Rasterize Text: the layer's text can no longer be edited, and it looks the same.
   5. Merge it down: one pixel layer, same look.
6. **Done when:** tests check each entry point (painting, effects, adjustments, Merge, Flatten, rotate, resize,
   crop, every redaction) does what you chose on a text layer, and that no redaction leaves the words in the saved
   file. Help is updated, and `make help` has run.

### Stage 31. Stroke smoothing

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

**You chose one stage at a time (Q0.5),** so this section is for reference only. Building means one session, one stage after another; since stage 2, related stages are built in a row and hand tested together (Leah, 2026-10-28: "batching changes for testing instead of every round, where it's sensible").

**Least overlap** (no stage is completely free of shared files):
- **Stage 19 (Export):** the export panel, `SaveSnapshot` and `ImageCodec`. No other stage touches those.
- **Stage 21 (faces):** the Auto-Redact files, plus the Auto-Redact section of `Editor.swift`.
- **Stage 20 (readout)** shares `Editor.swift` and `CanvasView.swift` with stages 1b, 9, 10 and 16, and
  `PaletteBar.swift` with stage 31. Different sections, but real merge conflicts are likely.

**Must not run together:**
- **Any two Adjust Photo stages** (1a–6, 11, 13–16): they all change `PhotoAdjustments`, `adjust_photo_fragment`
  and `PhotoControls`.
- **Any two of stages 12, 23, 25, 26, 27, 28a, 28b, 29 and 30:** each changes the layer model, the project format,
  history or compositing.
- **Stages 7, 8, 9 and 10:** the selection code and the Edit menu.
- **Stage 31 (smoothing) with stage 23 (lock transparent pixels):** both change what happens as a stroke is drawn.

**Things to know before running side by side:**
- STATUS.md, the FRD log and generated help pages get small merge conflicts.
- Each worktree builds its own Colorbee copy, which can take over Help and Open With until it's unregistered.
- Two `make test` runs at once share Colorbee's settings.
- You test one thing at a time anyway.

**My recommendation:** build one stage at a time (your answer to Q0.5). The pace is set by your hand tests, not by
build time.

---

## 8. Overview

| # | Stage | Covers | Size | Effort | Depends on |
|---|---|---|---|---|---|
| 1a | Adjust Photo groundwork: files, filters, sections | FR-9.7 rule | M | High | — |
| 1b | Whites and the white-balance eyedropper | Item 1 | S–M | High | 1a |
| 2 | Same as Last, copy and paste settings | Item 4 | S–M | Medium | 1a |
| 3 | Texture and Dehaze | Item 1 | M–L | High | 1a |
| 4 | Color Mixer and Black & White | Items 1, 6 | M | High | 1a |
| 5 | Color Grading | Item 2 | M | High | 1a |
| 6 | Point Color | Item 2 | M | High | 1b, 4 |
| 7 | Expand, Contract, Smooth | Item 3 | S | Medium | — |
| 8 | **Paste in Place** (extra) | Gap analysis | S | Medium | — |
| 9 | Color Range and Luminance Range | Item 3 | M | High | 1b, 7 |
| 10 | Graduated selection | Item 3 | S–M | High | 9 |
| 11 | .cube looks | Item 4 | M | High | 1a |
| 12 | History Snapshots | Item 4 | M | High | — |
| 13 | Sharpening and Noise Reduction detail | Item 5 | M | High | 1a |
| 14 | Vignette and Grain | Item 5 | M | Medium | 1a |
| 15 | Tone curve and clipping warnings | Item 6 | M | High | 1a |
| 16 | Drag on the picture to adjust | Item 6 | M | High | 1b, 4, 15 |
| 17 | Photo geometry | Item 7 | M | Medium | — |
| 18a | **Trim** (extra) | Gap analysis | S | Medium | — |
| 18b | **Canvas Size anchor** (extra) | Gap analysis, Q0.9 | S | Medium | — |
| 19 | Export color space and file size | Item 8 | M | High | — |
| 20 | Color readout and sample size | Item 9 | S | Medium | — |
| 21 | Auto-redact faces | Item 10 | M | High | — |
| 22 | Select All Layers, isolate, Stamp Visible | §23 layers | S–M | Medium | FR-8.6 |
| 23 | Lock transparent pixels | §23 layers | M | High | — |
| 24 | Align and Distribute | §23 layers | M | High | FR-8.6 |
| 25 | Layer groups 1 | §23 layers | L | High | 22 |
| 26 | Layer groups 2 | §23 layers | M–L | High | 22, 23, 24, 25 |
| 27 | Layer masks 1 | §23 masks | L | High | 25 |
| 28a | Layer masks 2: adjustment layers, mask tools | §23 masks | L | High | 27, 9, 10 |
| 28b | Masks on groups, clipping for pixel layers | §23 masks, gap analysis 2b | M | High | 26, 28a |
| 29 | Re-editable text 1 | §23 text | L | High | 25, 27 |
| 30 | Re-editable text 2 | §23 text | M | High | 29 |
| 31 | Stroke smoothing | §23 smoothing | M | High | — |

All Opus. FR-8.6 is already built, so it has no stage.

---

## Questions for you

Each has my recommendation and why. "Before stage N" means I need the answer before that stage starts, not now.

### Before any stage

- **Q0.1 FRD first.** For the items not yet in the FRD (stages 8, 18a, 18b and 22–31), I'll draft each FRD section at the
  start of its stage, you approve it, and then I build. *Recommend yes:* it keeps the FRD the single source of
  truth, as CLAUDE.md asks.
  **Answer: yes.**
- **Q0.2 FR-8.6.** It's built and passed. Is anything else wanted there? *Recommend nothing;* the follow-ups are part
  B. **Answer: nothing more.**
- **Q0.3 Saved filters and older betas.** Stage 1a moves filters to a new file and makes reading tolerant, but beta 7
  in your Applications folder stays old. *Recommend* cutting a beta right after stage 1a and using it as your
  everyday copy. Until then, don't save or delete filters in beta 7.
  Another beta after stages 6, 16, 21, 26, 28b and 31. **Answer: yes.** (The beta moved from after stage 1 to after
  stage 1a when stage 1 was split, Q0.10.)
- **Q0.4 What filters hold.** Should these be saved in filters? *Recommend:*
  - **Dehaze: in.** It changes the tone. (The review found it also looks at neighboring pixels, so in a filter it
    goes through stage 1a's path for settings that aren't colors. That doesn't change the answer.)
  - **Texture, sharpening and noise reduction: out.** They depend on each photo's own detail.
  - **Vignette and Grain: in,** as Lightroom presets do, since they're part of a "look". This changes today's rule
    that leaves Vignette out, so it's your call.
  - **Answer: yes to all three.**
- **Q0.5 Side-by-side sessions.** *Recommend no* (section 7). If you want them, only stages 19–21. **Answer: one at a
  time.**

_Added after the review (2026-10-27):_

- **Q0.6 Test builds' settings.** Should test builds keep their own settings folder, apart from your everyday copy?
  *Recommend yes:* otherwise a filter saved in a test build can lose its new settings the next time your everyday
  copy saves its filters. A test build copies your filters in once, so you can try them there. **Answer: yes.**
- **Q0.7 Intensity and shape settings.** At 50%, do only the amounts halve, while Grain Size and Roughness, Vignette
  Midpoint, Roundness and Feather, and the curve's split points stay put? *Recommend yes:* otherwise "Film" at 50%
  has smaller grain, not less grain. **Answer: yes.**
- **Q0.8 Warning in an older Colorbee.** Should an older Colorbee warn when it opens a file made by a newer one, since
  saving there drops the newer settings? *Recommend a one-line note.* **Answer: no;** you're the only user for now.
- **Q0.9 Canvas Size anchor.** Today, making the canvas bigger keeps the picture at the top-left, so all the new
  space goes on the right and bottom. An anchor (a 3 × 3 grid of squares in Canvas Properties) chooses where the
  picture stays: Center splits the new space evenly on every side, for an even margin. It was in the gap analysis's
  "quick wins" with Paste in Place and Trim. Add it as a small stage next to Trim? *Recommend yes,* with Center chosen
  at first. **Answer: yes** (stage 18b).
- **Q0.10 Splitting stage 1.** Split it into 1a (files, filters, sections) and 1b (Whites, eyedropper, Auto)?
  *Recommend yes:* one stage was too much to hand test in one sitting, and 1a gets your filters protected sooner.
  **Answer: yes.**
- **Q0.11 A beta after the text stages?** Q0.3's list skips stages 29 and 30, which change the project format, and
  stage 31 comes right after them. *Recommend one more beta after stage 30,* so a text layer made in a test build
  can be tried in a copy outside your test folder before smoothing starts. **Answer: no** (Leah, 2026-10-27); Q0.3's
  list stands.

### Before stages 1a and 1b

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
- **Q1.7** The white-balance dropper reads the picture before Adjust Photo's other settings, and on an Adjust Photo
  layer, the layers below it? *Recommend yes,* so a click on gray comes out neutral whatever Exposure or filter is
  set. **Answer: yes.**

### Before stage 2

- **Q2.1** Where: Adjustments ▸ "Adjust Photo: Same as Last" plus "Copy Photo Settings" and "Paste Photo Settings",
  with no default keys (they can be set in Settings), and Copy and Paste buttons in the panel. *Recommend this:*
  Lightroom's keys (⇧⌘C, ⇧⌘V) are taken here. **Answer: yes, as recommended.**
- **Q2.2** "Last" is the last settings applied anywhere (Apply or As Adjustment Layer), kept across a relaunch?
  *Recommend yes:* the use is coming back to a look later. **Answer: yes, as recommended.**
- **Q2.3** Paste Settings opens Adjust Photo with the settings in place, so you see them before Return? *Recommend
  yes:* there are no surprises, and it's still one undo step. The other way, it applies straight away. **Answer: yes, as recommended.**
- **Q2.4** Copy everything, or choose which settings (Lightroom shows a checklist)? *Recommend everything for now;* a
  checklist can come later if you miss it. **Answer: yes, as recommended.**
- **Q2.5** Copy from an Adjust Photo layer too, and offer "Paste as Adjustment Layer"? *Recommend yes.* **Answer: yes, as recommended.**

### Before stage 3

- **Q3.1** Texture in Detail next to Definition, Dehaze in Light after Brilliance? *Recommend yes.* **Answer: yes, as recommended.**
- **Q3.2** Both −100 to 100, where a negative Texture softens and a negative Dehaze adds haze? *Recommend yes,* as in
  Lightroom. **Answer: yes, as recommended.**

### Before stage 4

- **Q4.1** The eight ranges: Red, Orange, Yellow, Green, Aqua, Blue, Purple, Magenta? *Recommend yes* (Lightroom's). **Answer: yes, as recommended.**
- **Q4.2** Layout: Hue, Saturation and Luminance tabs with eight sliders each? *Recommend tabs:* you can see all the
  colors at once, as in Lightroom. **Answer: yes, as recommended.**
- **Q4.3** How far Hue can move a color: ±100 is about ±30°? *Recommend yes:* red can lean orange or magenta but
  can't become green, which keeps it natural. **Answer: yes, as recommended.**
- **Q4.4** Black & White as a switch at the top of the Color Mixer, where Color Grading still tints (for split-toned
  black and white)? *Recommend yes.* **Answer: yes, as recommended.**
- **Q4.5** The Black & White mix starts at neutral, looking like the Mono filter? *Recommend yes:* it's predictable. **Answer: yes, as recommended.**

### Before stage 5

- **Q5.1** Shadows, Midtones and Highlights, plus a Global wheel? *Recommend all four:* Global is a small extra. **Answer: yes, as recommended.**
- **Q5.2** One large wheel with tabs, since the sidebar is narrow, and small dots showing the others? *Recommend
  yes.* **Answer: yes, as recommended.**
- **Q5.3** A filter at 50% halves each wheel's strength and keeps its hue? *Recommend yes.* **Answer: yes, as recommended.**
- **Q5.4** Blending starts at 50 and Balance at 0? *Recommend yes,* as in Lightroom. **Answer: yes, as recommended.**

### Before stage 6

- **Q6.1** Up to 8 picked colors? *Recommend yes,* as in Lightroom. **Answer: yes, as recommended.**
- **Q6.2** Per color: Hue, Saturation, Luminance and Range? *Recommend those four.* Lightroom also has Variance; I'd
  add it only if you want it. **Answer: yes, as recommended.**
- **Q6.3** While you hold the Range slider, gray out everything it doesn't touch? *Recommend yes:* it shows what
  "this color" means. **Answer: yes, as recommended.**

### Before stage 7

- **Q7.1** Colorbee has no Select menu. *Recommend* Edit ▸ Modify Selection ▸ Expand…, Contract…, Smooth…, next to
  Feather…, so the menus stay as they are. The other way is a new Select menu holding every selection command,
  like Photoshop's, which is a bigger change. **Answer: the Modify Selection submenu, as recommended.**
- **Q7.2** Not an undo step, like Feather? *Recommend yes,* for consistency. **Answer: yes, as recommended.**
- **Q7.3** 1 to 100 px, starting at 2 px? *Recommend yes.* **Answer: yes, as recommended.**
- **Q7.4** Expand and Contract keep soft edges soft? *Recommend yes,* per FR-3.4. **Answer: yes, as recommended.**

### Before stage 8

- **Q8.1** Key: ⇧⌘V is Paste into New Image here. *Recommend ⌥⇧⌘V,* which is free in Colorbee today. **Answer: yes, as recommended.**
- **Q8.2** A picture copied in another app has no place: paste it as ⌘V would, with no beep? *Recommend yes.* **Answer: yes, as recommended.**
- **Q8.3** Into a different-sized document: the same position if it lands on the canvas, otherwise as ⌘V?
  *Recommend yes.* **Answer: yes, as recommended.**
- **Q8.4** Should Clipboard History items remember their place too? *Recommend no;* keep it simple. **Answer: no, as recommended.**

### Before stage 9

- **Q9.1** Edit ▸ Color Range… and Luminance Range…, next to Select Subject? *Recommend yes.* **Answer: yes, as recommended.**
- **Q9.2** It reads the active layer, with the Magic Wand's Sample All Layers switch to read everything shown?
  *Recommend yes:* that matches the Magic Wand and Select Subject. **Answer: yes, as recommended.**
- **Q9.3** Combining: Replace, Add, Subtract and Intersect in the bar, with Replace first? *Recommend yes.* **Answer: yes, as recommended.**
- **Q9.4** Fuzziness 0–100%, starting at 25%? *Recommend yes.* **Answer: yes, as recommended.**
- **Q9.5** Luminance Range: a two-handle range with Smoothness, plus Shadows, Midtones and Highlights buttons?
  *Recommend yes.* **Answer: yes, as recommended.**

### Before stage 10

- **Q10.1** Edit ▸ Graduated Selection, which opens a canvas tool like Straighten's line, rather than a toolbar
  tool? *Recommend the menu:* the toolbar is full, and it's an occasional tool. **Answer: the menu, as recommended.**
- **Q10.2** Fully selected where the drag starts, fading to nothing where it ends? *Recommend yes,* as in Lightroom. **Answer: yes, as recommended.**
- **Q10.3** The same combining choices as Q9.3? *Recommend yes.* **Answer: yes, as recommended.**
- **Q10.4** Shift keeps the line at 0°, 45° or 90°? *Recommend yes.* **Answer: yes, as recommended.**

### Before stage 11

- **Q11.1** Import only from the filter strip's menu, with no opening of .cube files from Finder? *Recommend yes:*
  it's simpler. **Answer: yes, as recommended.**
- **Q11.2** Apply looks to the document's own color values, as Photoshop's Color Lookup does? *Recommend yes:* it's
  simple and predictable. The other way converts through sRGB first, closer to what the look's maker saw on sRGB
  pictures. **Answer: yes, as recommended.**
- **Q11.3** Name it from the file's TITLE line, or the file name if there's none? *Recommend yes.* **Answer: yes, as recommended.**
- **Q11.4** A look filter exported as .colorbeefilter carries its table (1–3 MB)? *Recommend yes.* **Answer: yes, as recommended.**
- **Q11.5** One-dimensional .cube files (a curve per channel): accept them, or a plain "not supported" message?
  *Recommend the message:* most looks are 3D. **Answer: the message.**

### Before stage 12

- **Q12.1** A snapshot keeps its own copy, so it survives new edits, rather than a marker that can vanish?
  *Recommend a copy:* a snapshot that disappears would be a nasty surprise. A copy takes space (about 48 MB for a
  4000 × 3000 photo, about 1.3 GB at 8000 × 8000 with five layers), so *also recommend a cap of about 10 snapshots,*
  with a message at the cap. **Answer: yes to both** (Leah, 2026-10-27). The cap counts per page, like the undo
  history (my choice; veto any).
- **Q12.2** Not saved in the project, like undo history? *Recommend not saved:* it keeps files small and redaction
  safe. **Answer: yes, as recommended.**
- **Q12.3** "Remove Earlier Versions and Undo History" after a redaction deletes snapshots too? *Recommend yes:*
  otherwise a snapshot could bring a secret back. **Answer: yes, as recommended.**
- **Q12.4** Where: a New Snapshot… button in the History panel, plus Edit ▸ New Snapshot… with no key? *Recommend
  yes.* **Answer: yes, as recommended.**
- **Q12.5** Going to a snapshot is an undo step of its own ("Go to Snapshot"), so ⌘Z comes back? *Recommend yes:*
  nothing is lost. **Answer: yes, as recommended.**
- **Q12.6** Each page has its own snapshots? *Recommend yes,* like its undo history. **Answer: yes, as recommended.**

### Before stage 13

- **Q13.1** Radius 0.5–3 px, Detail 0–100, Masking 0–100, with Luminance and Color noise reduction each with Detail;
  defaults that match today's look? *Recommend yes,* so old edits don't change. **Answer: yes, as recommended.**
- **Q13.2** Option-drag on Masking shows the edge mask on the picture (display only)? *Recommend yes,* as in
  Lightroom. **Answer: yes, as recommended.**
- **Q13.3** The extra settings under a disclosure arrow next to Sharpness and Noise Reduction? *Recommend yes:* it
  keeps the panel short. **Answer: yes, as recommended.**

### Before stage 14

- **Q14.1** Vignette Midpoint, Roundness and Feather start at today's shape? *Recommend yes.* **Answer: yes, as recommended.**
- **Q14.2** Grain: Amount 0–100, Size 0–100 (starting at 25), Roughness 0–100 (starting at 50)? *Recommend yes,*
  as in Lightroom. **Answer: yes, as recommended.**
- **Q14.3** Effects ▸ Vignette… stays as it is? *Recommend yes* (§23, 2026-10-03 kept both). **Answer: yes, as recommended.**
- **Q14.4** A new Effects section holding Vignette and Grain, with Vignette moved out of Detail? *Recommend yes,* as
  in Lightroom. **Answer: yes, as recommended.**

### Before stage 15

- **Q15.1** Adjust Photo has no histogram: add a live one at the top of the panel? *Recommend yes.* **Answer: yes, as recommended.**
- **Q15.2** Clipping warnings as two buttons on the histogram, off by default, with no key? *Recommend yes.* **Answer: yes, as recommended.**
- **Q15.3** Naming: Adjust Photo already has Highlights and Shadows. *Recommend* putting the curve's four regions
  under a "Tone Curve" heading, named Highlights, Lights, Darks, Shadows, so the heading tells them apart. **Answer: yes, as recommended.**
- **Q15.4** A parametric curve only, since Adjustments ▸ Curves… already does point curves? *Recommend yes,* per
  FR-9.7. **Answer: yes, as recommended.**

### Before stage 16

- **Q16.1** The hand drives the tone curve, or the Color Mixer tab showing, depending on which section's hand you
  click? *Recommend yes.* **Answer: yes, as recommended.**
- **Q16.2** Dragging up is more? *Recommend yes,* as in Lightroom. **Answer: yes, as recommended.**

### Before stage 17

- **Q17.1** Find corners automatically every time Perspective Correction opens, falling back to today's corners,
  with a Reset button? *Recommend yes.* **Answer: yes, as recommended.**
- **Q17.2** Overlays: Thirds, Grid, Diagonal, Triangle, Golden Ratio, Golden Spiral; O switches between them while
  cropping (O is free). Shown while dragging, as thirds are now? *Recommend yes.* **Answer: yes, as recommended.**
- **Q17.3** Crop… already shades what it cuts out. What should change? *Recommend* looking at today's Crop… first;
  if it's enough, this part is done. Otherwise tell me what you'd like: darker, or fully hidden. **Answer: keep today's shading.**

### Before stage 18a

- **Q18.1** One click, Image ▸ Trim: transparent borders if there are any, otherwise the top-left pixel's color.
  No dialog? *Recommend yes:* it's immediate, like Paint. Photoshop's dialog with choices is the other way. **Answer: yes, as recommended.**
- **Q18.2** A small fixed tolerance (about 2%) so JPEG edges still trim? *Recommend yes.* **Answer: yes, as recommended.**
- **Q18.3** Decided by everything shown, with all layers cropped together? *Recommend yes,* the same as Crop. **Answer: yes, as recommended.**

### Before stage 18b

- **Q18.4** The anchor is a 3 × 3 grid of squares in Canvas Properties, set to Center each time the sheet opens
  (not remembered)? *Recommend yes:* Center is the common case, and it's never a surprise. **Answer: yes, as recommended.**
- **Q18.5** The anchor also decides which edges are cut when the canvas gets smaller? *Recommend yes,* as in
  Photoshop. **Answer: yes, as recommended.**

### Before stage 19

- **Q19.1** The color choice goes in Export… and in each Export As preset (Settings), while Copy, Share and PDF keep
  the document's profile? *Recommend yes:* those are the "sending it somewhere" paths.
- **Q19.2** "Limit file size to [ ] KB/MB" as a checkbox in Export…? *Recommend yes.*
- **Q19.3** If it can't fit even at the lowest quality: a message with the smallest size possible, and nothing
  written? *Recommend yes;* shrinking the picture is Export As's job.
- **Q19.4** Remember both settings between launches? *Recommend yes,* like format and quality.
- **Q19.5** Just sRGB, Display P3 and Keep, with no Adobe RGB? *Recommend yes,* per FR-9.7.
- **Q19.6** Count 1 KB as 1,000 bytes, as Finder does? *Recommend yes,* so a 200 KB limit never shows as more in
  Finder. **Answer: yes.**

### Before stage 20

- **Q20.1** Read what you see (all layers), like the Eyedropper's Option-click? *Recommend yes.*
- **Q20.2** Show the document's own values (they match what the Eyedropper picks), or sRGB (it matches a style
  guide's hex)? *Recommend sRGB, labeled "sRGB":* checking brand colors is the stated use, and style guides are in
  sRGB. Your call, since it won't match the color panel's Display P3 numbers.
- **Q20.3** Sample sizes 1 px (the default), 3 × 3 and 5 × 5? *Recommend yes.*
- **Q20.4** The readout follows the sample size while the Eyedropper is chosen, and a click on the hex copies it?
  *Recommend yes to both.*
- **Q20.5** Should the color readout also show in the Info panel? *Recommend no, the status bar only:* the Info
  panel describes the document and doesn't change as the pointer moves. **Answer: status bar only** (Leah,
  2026-10-27).

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
- **Q23.4** Flip, Rotate, Crop, Resize and Straighten work as usual on such a layer, moving its outline with the
  picture? *Recommend yes,* as in Photoshop: they move the whole layer rather than paint on it. **Answer: yes.**
- **Q23.5** A one-layer picture saved as a PNG doesn't keep the lock, like today's padlock? *Recommend yes:* a lock
  alone shouldn't turn a PNG into a project. **Answer: yes.**

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

### Before stages 27, 28a and 28b

- **Q28.1** Masks on adjustment layers? *Recommend yes,* in stage 28a: it's local, non-destructive Adjust Photo.
- **Q28.2** Masks on groups? *Recommend yes,* in stage 28b.
- **Q28.3** While a mask is chosen, the color wells and swatches turn to grays, and D gives white and black?
  *Recommend yes,* as in Photoshop.
- **Q28.4** "Only the layer below" for pixel layers too (from the gap analysis answer)? *Recommend yes,* in stage
  28b; it's the same switch adjustments have. **Answer: yes** (gap analysis answer 2b, confirmed after the review).
- **Q28.5** Redaction changes hidden pixels too, and the help says masks don't hide secrets. Older betas show
  masked parts. *Recommend* accepting this, with the help's warning.
- **Q28.6** Add Mask uses the selection when there is one? *Recommend yes.*
- **Q28.7** No default keys for mask commands? *Recommend yes.*
- **Q28.8** Undo on Active Layer and Revert Layer include the layer's mask? *Recommend yes:* the mask belongs to the
  layer. **Answer: yes.**

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
