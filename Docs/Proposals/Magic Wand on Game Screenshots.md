# Proposal: Selecting things in game screenshots

Status: **idea, first example tested** (2026-10-27). Planning only; nothing is built. This is separate from the
Lightroom-style development plan.

## The problem

Leah finds the Magic Wand (FR-3.1) doesn't work well on screenshots of video games and other rich computer
graphics. Flat app screenshots are fine; game images aren't.

First example: `~/Pictures/Final Fantasy/nin.png` (3266 × 2144, Display P3), trying to select the genie lamp
at the bottom right.

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

## What the lamp test showed

Claude simulated the wand outside the app, clicking the middle of the lamp's body (pixel 2830, 1760).
[Magic Wand lamp test.png](Magic%20Wand%20lamp%20test.png) shows, left to right: today's wand at 10%, 20% and 30%,
then Select Subject.

| Method | Result |
|---|---|
| Today's wand, 10% | Body only. Misses the knob, the lid and its rim, the base's highlights. |
| Today's wand, 20% | Most of the lamp, but already leaks onto the ground under the base; still misses the lid rim. |
| Today's wand, 30% and up | The whole picture (about 4 million pixels). |
| Ideas 1–3 below (average, perceptual matching, pinholes) | Almost the same as today at every setting. |
| Matching color more than brightness | Leaks from 5–6%, before it reaches the knob. |
| **Select Subject, clicking the lamp** | **The whole lamp, knob, spout and base, with no leaks.** Its outline is rounded and blobby, though: it softens the spout's tip and the narrow stem. |

**The lesson:** the lamp is a shaded 3D object. Its own colors range from deep shadow to bright highlight, a
bigger difference than the one between its shadow side and the blue-grey ground. No color rule can separate
them, so no tolerance works: low misses parts, high leaks. That's typical of objects in games, and it's the
wrong job for any color-matching wand. Select Subject's first look at the whole picture sees only the character,
but its closer look around the click (added 2026-10-27) finds the lamp.

So the problem splits in two:

- **Objects** (characters, items, props): Select Subject is the right tool, and the improvement it needs is a
  **crisper outline**.
- **Flat or gently shaded areas** (sky, walls, UI panels, text boxes): the wand is the right tool, and ideas 1–5
  below still apply. We need an example of this kind before deciding.

## Ideas

### For objects: a crisper Select Subject (recommended first)

A. **Refine Edge:** after Vision finds the subject, snap its soft, blobby outline to the real edges in the image
   (an edge-aware filter that uses the picture itself as a guide, such as a guided filter). Keeps Vision's "this
   is one object" understanding and adds the image's own detail: spout tips, the stem, gaps between parts. This
   would also improve Remove Background, which uses the same masks.

B. **Point it out from the wand:** when the wand is used on something Vision would call an object, nothing tells
   you that Select Subject would do better. Possibly a gentle hint, or a "Smart" option on the wand that runs
   Select Subject on the clicked object. (Open question 4.)

C. **Quick Selection brush** (later, larger): paint roughly over the thing you want, and the selection grows to
   the nearest strong edges, like Photoshop's Quick Selection. For things Vision doesn't see as objects.

### For flat areas: a better wand

1. **Sample Size:** match against the average color of a small square around the click (Point, 3×3, 5×5),
   not one pixel. Makes noisy textures behave and the result less sensitive to the exact click.
2. **Perceptual color matching:** compare colors by how different they look (for example, based on Oklab).
   Tolerance then means roughly the same thing for dark and light colors.
3. **Fill Pinholes:** fill in small unselected specks surrounded by selected pixels, up to a few pixels in size.
4. **Soft Edge:** pixels just outside the tolerance get partly selected, fading to none, so anti-aliased edges
   leave no halo. Colorbee already supports soft selections (FR-3.4).
5. **Follow Gradients** (a separate mode): compare each pixel to its neighbor instead of to the click, so a
   shaded sky is selected as one area. Leaks through soft boundaries easily; on the lamp picture it selected
   everything. Only if needed after 1–4.

## Open questions for Leah

1. **Had you tried Select Subject on the lamp?** (Edit ▸ Select Subject, then click the lamp.) If it worked
   but the edge looked rough, Refine Edge is the fix. If it didn't work, Claude needs to look at why.
2. **Another example, please:** a game screenshot where you wanted a flat or gently shaded *area* (sky, a wall,
   a menu panel), not an object. That decides whether ideas 1–5 are worth doing.
3. **Fill too?** Fill uses the same matching as the wand. If the wand changes, change both (recommended: they'd
   behave alike, and tolerance means one thing), or the wand only?
4. **Steering to Select Subject:** do nothing, show a hint, or add a "Smart" option to the wand? Recommended:
   wait until Refine Edge is in, then decide; a hint pointing to a blobby result wouldn't help.
5. **New wand settings** (only if ideas 1–5 go ahead): Sample Size as a small menu; Fill Pinholes and Soft Edge
   as toggles, on by default. Perceptual matching means 10% won't select exactly what it does today; recommended
   to accept that.

## Plan

- **Done:** the lamp test (above).
- **Next:** Leah answers questions 1 and 2.
- **Refine Edge spike (recommended first):** try an edge-aware refinement on the lamp's Vision mask, outside the
  app, and show Leah the before and after. If it looks right, build it into `SubjectScan` with tests, the help
  page update and hand-test steps.
- **Wand ideas:** only after a flat-area example shows they help. Same approach: compare outside the app first,
  then build in `SelectionMask.magicWand` and `FloodFill`, with exact-value tests on small images and a speed
  check on a large screenshot (the wand must stay instant).
- Recommended model and effort: **Opus, high** (careful image work).
