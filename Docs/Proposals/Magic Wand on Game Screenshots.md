# Proposal: A Magic Wand that works on game screenshots

Status: **idea, waiting for Leah's example screenshots** (2026-10-27). Planning only; nothing is built. This is
separate from the Lightroom-style development plan.

## The problem

Leah finds the Magic Wand (FR-3.1) doesn't work well on screenshots of video games and other rich computer
graphics. Flat app screenshots are fine; game images aren't.

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

## Ideas, from most to least useful (recommended: the first three)

1. **Sample Size:** match against the average color of a small square around the click (Point, 3×3, 5×5),
   not one pixel, like Photoshop's Sample Size. Makes noisy textures behave and makes the result much less
   sensitive to the exact click.
2. **Perceptual color matching:** compare colors by how different they look (a perceptual color difference,
   such as one based on Oklab) instead of channel by channel. Tolerance then means roughly the same thing for
   dark and light colors.
3. **Fill Pinholes:** after finding the area, fill in small unselected specks surrounded by selected pixels,
   up to a few pixels in size. Removes the speckled look on textures.
4. **Soft Edge:** pixels just outside the tolerance get partly selected, fading to none, so anti-aliased edges
   leave no halo. Colorbee already supports soft selections (FR-3.4).
5. **Follow Gradients** (a separate mode): compare each pixel to its neighbor instead of to the click, so a
   shaded sky or a lit wall is selected as one area. Powerful, but it leaks through soft boundaries easily.
   Only if Leah needs it after 1–4.

Also worth checking first: for a character or object, **Select Subject** may already do better than the wand.

## Open questions for Leah

1. **What goes wrong most?** Holes and speckles (stops too early), leaking into things you didn't click, or
   rough edges? Example screenshots, with where you clicked, will answer this.
2. **Fill too?** Fill uses the same matching, so it has the same problems. Change both together (recommended:
   they'd behave alike, and you'd learn tolerance once), or the wand only?
3. **New toolbar settings.** Sample Size, Fill Pinholes and Soft Edge would each add a control to the wand's
   toolbar. Show them all, or turn the recommended ones on by default and keep the toolbar as it is?
   Recommended: Sample Size as a small menu; Fill Pinholes and Soft Edge as toggles, on by default.
4. **Will existing tolerances change meaning?** Perceptual matching means 10% won't select exactly what it does
   today. Fine to change (recommended: it's a personal tool and the new meaning is better), or keep the old
   matching available?
5. **Follow Gradients:** wanted at all, or wait and see?

## Plan

- **First:** Leah sends a few game screenshots that go wrong, with where she clicked and what she expected.
  They become test images (`TestImages/Magic Wand/`) and the yardstick for every change.
- **Try before deciding:** a quick comparison on those images, the current wand next to each idea, so Leah can
  see the difference before choosing.
- **Then build** the chosen ideas in the core (`SelectionMask.magicWand`, `FloodFill`), with exact-value tests on
  small images, a speed check on a large screenshot (the wand must stay instant), the help page update and
  hand-test steps.
- Recommended model and effort: **Opus, high** (careful algorithm work).
