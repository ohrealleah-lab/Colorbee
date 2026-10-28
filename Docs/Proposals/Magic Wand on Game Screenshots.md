# Proposal: Selecting things in game screenshots

Status: **planned, waiting to be scheduled** (2026-10-27). All questions answered. Planning only; nothing is built. This is separate from
the Lightroom-style development plan.

## The problem

Leah finds the Magic Wand (FR-3.1) doesn't work well on screenshots of video games and other rich computer
graphics. Flat app screenshots are fine; game images aren't.

Test picture: `~/Pictures/Final Fantasy/nin.png` (3266 × 2144, Display P3). Leah was trying to select the genie
lamp at the bottom right.

## Why it happens today

The wand (and Fill, which shares the same code in `FloodFill.swift`) works like this:

1. **Everything is compared to the one pixel you clicked.** Games have lighting, shading, textures, grain and
   compression noise, so the clicked pixel is often a little lighter or darker than the area around it. The
   selection then stops early or leaves speckles, and it changes a lot depending on exactly where you click.
2. **The color test doesn't match how people see color.** Red, green and blue (and alpha) must each be within
   the tolerance (default 10%). Shades that look the same can fail, and shades that look different can pass.
3. **Hard edges.** A pixel is fully selected or not at all. Games anti-alias their edges, so the result has a
   jagged outline or a thin halo of the old color.
4. **Only side-by-side neighbors count** (4-connected), so thin diagonal lines and textures with many small gaps
   break the area into pieces.

## What the tests showed

Claude simulated each method outside the app, on the test picture.

### The lamp (an object)

A comparison picture (kept out of the repo: it's a personal screenshot) showed, left to right: today's wand at 10%,
20% and 30%, then Vision's closer look around the click.

| Method | Result |
|---|---|
| Today's wand, 10% | Body only. Misses the knob, the lid and its rim, the base's highlights. |
| Today's wand, 20% | Most of the lamp, but already leaks onto the ground under the base; still misses the lid rim. |
| Today's wand, 30% and up | The whole picture (about 4 million pixels). |
| Ideas 1–3 below (average, perceptual matching, pinholes) | Almost the same as today at every setting. |
| Matching color more than brightness | Leaks from 5–6%, before it reaches the knob. |
| **Vision's closer look around the click** | **The whole lamp, knob, spout and base, with no leaks.** The outline is rounded and blobby, softening the spout's tip and the narrow stem. |

The lamp is a shaded 3D object. Its own colors range from deep shadow to bright highlight, a bigger difference
than the one between its shadow side and the blue-grey ground. No color rule can separate them, so no tolerance
works: low misses parts, high leaks.

**But Select Subject can't reach the lamp today.** Leah tried it, and it took the lalafell. When Vision's first
look finds exactly one subject, Select Subject (and Lift Subject, and Remove Background) takes it at once without
waiting for a click (`Editor.findSubject`). The closer look around a click only happens when the first look finds
no subject or several. Claude's first test skipped straight to the closer look, so it got this wrong at first.

### The sky and the stone steps (areas)

A second comparison picture (also kept out of the repo), clicking the sky: top row today's wand at 10% and 20%,
bottom row ideas 1–3 at a low and a medium setting.

- **Sky:** today at 10% leaves the pink sunset near the horizon unselected, and 20% leaks into the mountains and
  trees. Ideas 1–3 at the medium setting take the whole sky, sunset included, and stop cleanly at the mountains.
  **A clear win for ideas 1–3.**
- **Stone steps:** every method leaks into the blurred grey trees, and even onto the lalafell's leg, since
  they're the same grey. Like the lamp, this needs something that understands shapes, not colors.

## Ideas

### A way to point at the object you want (recommended first)

A. **Object mode for the Magic Wand** (decided). The wand gets a Color / Object choice in its toolbar. In Object
   mode, a click selects the object under the click: the subject Vision's first look found there, or, if none,
   the closer look around the click. The lamp would be one click. The wand is where Leah reached naturally, so
   it's where this belongs. Claude's choices (veto any):
   - Shift and Option add and subtract, as in Color mode.
   - Tolerance and Contiguous are greyed out in Object mode; Sample All Layers still applies.
   - While Vision looks, the status bar says "Looking closer…" and Esc stops it, as in Select Subject.
   - A click where nothing is found beeps and leaves the selection as it was.
   - The wand remembers the last mode, like its other settings. Color stays the default.
   - The first look's results are kept until the image changes, so further clicks on the same picture are quick.

B. **Refine Edge:** Vision's outline has the right shape but soft, rounded edges, like tracing with a thick
   marker. Refine Edge would look at the actual picture along that outline and move it to where the object
   really ends: the spout's tip comes back to a point, the stem gets its waist, and no strip of grey ground
   stays stuck to the edge. It would sharpen Select Subject, Lift Subject and Remove Background too. Best judged
   by eye, so it starts with a before-and-after for Leah.

C. **Quick Selection brush** (later, larger): paint roughly over the thing you want, and the selection grows to
   the nearest strong edges, like Photoshop's Quick Selection. For things Vision doesn't see as objects, like
   the steps.

### For areas: a better color wand

1. **Sample Size:** match against the average color of a small square around the click (Point, 3×3, 5×5),
   not one pixel. Makes noisy textures behave and the result less sensitive to the exact click.
2. **Perceptual color matching:** compare colors by how different they look (for example, based on Oklab).
   Tolerance then means roughly the same thing for dark and light colors.
3. **Fill Pinholes:** fill in small unselected specks surrounded by selected pixels, up to a few pixels in size.
4. **Soft Edge:** pixels just outside the tolerance get partly selected, fading to none, so anti-aliased edges
   leave no halo. Colorbee already supports soft selections (FR-3.4).
5. **Follow Gradients** (a separate mode): compare each pixel to its neighbor instead of to the click, so a
   shaded area is selected as one. On the lamp picture it selected everything. Not recommended.

## Decided (Leah, 2026-10-27; FRD §23)

- **Object mode:** a Color / Object choice on the Magic Wand (idea A).
- **Fill changes with the wand**, so tolerance means one thing in both.
- **New wand settings:** Sample Size as a small menu; Fill Pinholes and Soft Edge as toggles, on by default.
  Perceptual matching may change what a given tolerance selects, and that's accepted.

- **Refine Edge:** try it first as a before-and-after on the lamp, outside the app, then decide whether to build it.

## Open questions for Leah

None for now.

## Plan

- **Done:** lamp, sky and steps tests (above).
- **When Leah says go, in this order:**
  1. Object mode on the wand (small: it reuses Select Subject's search).
  2. Refine Edge: a before-and-after on the lamp outside the app, then build into `SubjectScan` if Leah likes it.
  3. Wand ideas 1–4 for Fill and the wand, in `SelectionMask.magicWand` and `FloodFill`, with exact-value tests
     on small images and a speed check on a large screenshot (the wand must stay instant).
  Each with tests, the help page update and hand-test steps.
- Recommended model and effort: **Opus, high** (careful image work).
