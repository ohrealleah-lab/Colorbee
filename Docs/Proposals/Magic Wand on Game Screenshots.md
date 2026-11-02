# Proposal: Selecting things in game screenshots, and other Vision updates

Status: **steps 1–3 built, waiting for Leah's hand test** (2026-11-01); steps 4–6 waiting to be scheduled. All questions answered.
This is separate from the Lightroom-style development plan.

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

### Step 4's before-and-after (2026-11-02)

Claude tried Refine Edge (a color guided filter: it moves a soft mask's edge onto the picture's own edges) and
Apple's people mask outside the app, on the lamp and on a portrait Leah supplied (kept out of the repo: a personal
photo). The comparison pictures were shown to Leah in chat.

- **Refine Edge helps a little, everywhere.** The lamp's stem and base come out crisper; on the portrait, the arm's
  edge is cleaner and the hair's ends come back where the subject mask had cut them off square. The strength
  matters: about 8 px is the middle ground; 16 px brings back more hair but leaves smears of the wall beside it;
  4 px barely changes anything. About 0.5–0.75 s on these pictures, in a plain scratch script.
- **The people mask did worse on this portrait.** Its edge is softer, with a blurry band of wall around the hair,
  and it took in part of the radiator behind. On the lamp it even reported a "person" under the click (a ghost of
  the lamp), so it could only ever be used when it closely matches the subject clicked.

## Vision updates batched with this (Leah, 2026-11-01)

Leah added these because they share the same code (`SubjectScan`, `Editor.findSubject` and `pickSubject`) and the
same test pictures. Items 1–4 change the "click the subject you want" step that Select Subject, Lift Subject,
Remove Background and Object mode all use.

1. **Untangle merged subjects.** Vision's first look sometimes joins neighbors into one subject: in Leah's catgirl
   screenshot (`Downloads/test.jpeg`) the catgirl comes with the doll and the chair, and in her cats photo
   (`Downloads/toughcat.png`) a click on the white cat takes the black cat too. When a click lands on a subject,
   Colorbee also looks closer around the click; if that finds a smaller subject under the click that sits mostly
   inside the big one, it takes the smaller one. A closer look at the catgirl in a square as tall as the picture
   separated her (tested 2026-10-28).
2. **Bigger closer looks.** The closer look's first square is half the picture's shorter side, which cut off the
   catgirl's hat and boots (a 1117 px square). It starts at the full shorter side instead (2234 px worked), then
   shrinks as today. This costs one more Vision look, a fraction of a second.
3. **Show what Vision found.** While the bar waits for a click, the subjects found are outlined, and the one under
   the pointer is tinted, so you can see what a click will take before you click.
4. **Pick more than one.** Shift-click adds a subject, so you can take two cats and leave the third. (Multi-subject
   Shift-click was dropped with the feature freeze on 2026-10-19; Leah brought it back here.)
5. **Auto Straighten.** Straighten… asks Vision for the horizon's angle (`VNDetectHorizonRequest`, on this Mac) and
   starts the slider there, for you to nudge, as Perspective Correction already starts on the corners Vision finds.
   With no horizon found it starts at 0° as today.
6. **Better people outlines.** Apple has a people-only mask (`VNGeneratePersonInstanceMaskRequest`, up to four
   people, each separately) that follows hair and fingers better than the general subject finder. When the subject
   you pick is a person, Colorbee uses the people mask for them. Like Refine Edge, it's judged by eye, so it starts
   with a before-and-after on a photo of a person, side by side with Refine Edge, since both make edges better.

Perspective Correction already finds its corners with Vision (built in stage 17, 2026-10-28), so it isn't in this
list. Auto-redacting faces is built too (FR-9.7 item 10).

## Decided (Leah, 2026-10-27; FRD §23)

- **Object mode:** a Color / Object choice on the Magic Wand (idea A).
- **Fill changes with the wand**, so tolerance means one thing in both.
- **New wand settings:** Sample Size as a small menu; Fill Pinholes and Soft Edge as toggles, on by default.
  Perceptual matching may change what a given tolerance selects, and that's accepted.

- **Refine Edge:** try it first as a before-and-after on the lamp, outside the app, then decide whether to build it.

## Decided for the Vision updates (Leah, 2026-11-01: "use your recs"; FRD §23)

- **Untangling merged subjects is automatic.** You clicked the white cat, so you meant the white cat. To avoid
  taking just a piece of someone (a hat), the smaller subject must be at least a fifth of the big one's size.
- **Showing what Vision found:** outlines on every subject found, plus a tint on the one under the pointer, so you
  can see at a glance whether Vision merged things.
- **Picking more than one:** a plain click still takes a subject at once. Shift-click marks subjects (tinted), and
  Return takes the marked ones; with none marked, Return takes all of them, as today.
- **Auto Straighten runs every time Straighten opens**, with "Finding the horizon…" for a moment and a Reset button,
  matching Perspective Correction.
- **Better people outlines are used whenever the picked subject is a person**, with no new command, if the
  before-and-after shows they're better.

## Open questions for Leah (2026-11-02)

- **Q6. Build Refine Edge?** Recommended: yes, always on, for Select Subject, Lift Subject, Remove Background and the
  wand's Object mode, at about 8 px (scaled to the picture's size), with no new setting.
- **Q7. Build the better people outlines?** Recommended: no. On the portrait it was worse than the general subject
  finder, and it can mistake things for people.

## Plan

- **Done:** lamp, sky and steps tests (above). Untangling, tried on the catgirl screenshot before building: the
  first look's subject (catgirl and right doll, 1.38 million pixels) gave way to the catgirl alone (0.76 million, 95%
  inside), in about 0.15 s; the lamp is still found by the bigger closer looks, in the second square (1501 px).
- **Built 2026-11-01:** steps 1 to 3 below (hand test in `Docs/STATUS.md`).
- **When Leah says go, in this order:**
  1. Bigger closer looks and untangling merged subjects (Vision updates 1 and 2): they make every pick better,
     Object mode included, so they come first. Tested on the catgirl and cats pictures.
  2. Object mode on the wand (small: it reuses Select Subject's search).
  3. Showing what Vision found, and Shift-click for more than one (updates 3 and 4).
  4. Refine Edge and better people outlines (update 6): before-and-afters outside the app, on the lamp and on a
     photo of a person (Leah's choice of photo, kept out of the repo), then build into `SubjectScan` what Leah likes.
  5. Wand ideas 1–4 for Fill and the wand, in `SelectionMask.magicWand` and `FloodFill`, with exact-value tests
     on small images and a speed check on a large screenshot (the wand must stay instant).
  6. Auto Straighten (update 5): separate from the rest, small. Tested on a tilted photo.
  Each with tests, the help page update and hand-test steps. Steps 1–3 can be hand-tested together.
- Recommended model and effort: **Opus, high** (careful image work).
