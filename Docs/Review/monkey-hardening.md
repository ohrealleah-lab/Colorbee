# Monkey hardening before the App Store (2026-11-21)

A fresh audit of the overnight monkey (`Tests/ColorbeeTests/Monkey`) against the menus, tools and panels, because
[monkey-gaps.md](monkey-gaps.md) (audited 2026-11-09) no longer says what's open. Leah's answers, 2026-11-21: all four
store checks this round; damaged files made in a temp folder; raw input through the canvas view now; a Release run too.

**Priorities.** High: lost work, crashes, secrets left after a redaction, or exports that don't match the screen.
Medium: a real bug class, rarer or less harmful. Low: worth having.

## Closed since monkey-gaps.md's audit

| Gap | Where it's proven |
|---|---|
| C1 Retouch, all ten kinds, waiting for background landings | `.retouch` step |
| C2 Effect dialogs, applied, cancelled and raced | `.effectDialog`, `everyEffectDialogMeetsTheRules` |
| C3 Shapes and text left open meet the next step | `leavesOpen`, `checkLanded`, `objectsLeftOpenMeetTheNextStep` |
| C12, R1b Forget History | `.forgetHistory`, `checkForgotten` |
| R1, R1c Redactions cover everything, Auto-Redact finds something | `checkCovered`, `checkNothingLeft`, report counts finds |
| R2 Every page, not just the one shown | per-page undo lines, `aWrongPictureIsCaughtAfterShowingAnotherPage` |
| R3 The floating piece in undo | `selectionState`, floating checks in `UndoTracker.note` |
| R4 PNG and PDF exports match | `.export`, `checkPNG`, `checkPDF` |
| R5 Saving in the background while editing | `.saveInBackground` |
| R6 History spills to disk | `tinyHistory` on every other episode |
| Esc on floating pixels (stage 34b) | `.escape`, `floatStarts` |
| Adjust Photo settings, dialog, screen against export | `.photoLayer`, `.photoSetting`, `.adjustPhoto` |

## Still open

### Store-specific (new; not in the old list)

| # | Gap | Priority | What it takes |
|---|---|---|---|
| S1 | Opening damaged files: truncated, zero bytes, wrong extension, broken headers, a size bomb, a PDF cut short | High | Damaged copies of `TestImages` in a temp folder, opened through `ImageDocument.read` (the real path). A clean error or a sound document; never a crash or a hang |
| S2 | Opening unusual but valid files: 16-bit, gray, gray with alpha, indexed, CMYK JPEG, EXIF rotation, multi-page TIFF and PDF, animated GIF, profiles other than Display P3 | High | Made in code with ImageIO; opened, saved as a project, reopened: same look and profile (also R13) |
| S3 | Preferences and disk: nothing the monkey does writes `UserDefaults`, the settings folder, or leaves temp files | High | Snapshot before the run; compare after each episode |
| S4 | No networking at all (CLAUDE.md) | High | Count the process's internet sockets after each episode |
| S5 | Saving through the document: save over a file, reopen through `ImageDocument`; a save that fails partway leaves the old file whole | High | `writeSafely` on a temp file; a test-only failure inside `data(ofType:)` |
| S6 | Leaks: each episode's editors and pages go away | Medium | Weak references after each episode |
| S7 | Limits: 200 layers, groups nested deep, a huge canvas | Medium | One stress pass per run, bigger in Release |
| S8 | A Release build (what ships) | Medium | `make monkey-release` |

### Raw input (new)

| # | Gap | Priority | What it takes |
|---|---|---|---|
| I1 | Mouse, tablet and key events through `CanvasView`, in odd orders: a lost mouse-up, a drag with no mouse-down, the right button during a left drag, keys and tool changes mid-drag, Undo mid-drag, Esc mid-drag, pressure at 0 and 1, double-clicks | High | A `CanvasView` with no window, fed `NSEvent`s; the rules after each script. Never Ctrl-click (its menu would block) |

### From monkey-gaps.md, still open

| Gap | Priority | Notes |
|---|---|---|
| R9 The document is marked edited exactly when history changes | High | Count `onDocumentChange` |
| R7 History Snapshots go back exactly; rename | High | Keep each snapshot's picture by id |
| C11 Solid Fill with Color 1 (a redaction), Auto Contrast, Remove Red-Eye | Medium | One call each; Solid Fill gets the redaction rules |
| C10 Select Subject, Remove Background, Lift Subject | Medium | Vision may find nothing on flat pictures; count finds |
| C5 Feather, Expand, Contract, Smooth; Color Range, Luminance Range, Graduated; Shift and Option drags; Ellipse Select; handles on floating pieces | Medium | |
| C4 Copy, Copy Merged, Cut, Paste in Place without the clipboard | Medium | `selectedPixels`, `copiedPlace`, `paste(_:inPlaceAt:)` |
| R10 Locked layers don't change | Medium | Compare locked layers' pixels after each step |
| R12 Internal references stay valid | Medium | Selection mask the canvas's size, floating piece on a layer that exists, chosen layers exist |
| C6 Tool options off their defaults (fill tolerance, all layers, gradient mode, line width, all 23 shapes, wrapped and curved text) | Medium | |
| C9 Delete every word of a text layer | Medium | `""` in the words |
| C7 Select All Layers, Align, Distribute, menu toggles on several layers | Medium | |
| Edge values: slider ends, 1 px, selections on the canvas edge, emoji and right-to-left words | Medium | Bias the generator |
| C3 handles on open shapes and text boxes | Low | |
| C8 Rename, Pass Through, isolation | Low | |
| C13 Before/After, zoom, canvas anchors | Low | |
| R11 Text after crops and turns; R8 merges keep the look (needs Leah); R14 thumbnails; Revert Layer, Step Badges, Magic Wand, lasso, Trim, the History panel's jumps | Low | |

### Can't be covered safely (unchanged)

The real clipboard and Clipboard History, export option objects, Adjust Photo's "last used", saved filters, palettes,
text styles, shortcut editing, Settings, `NSDocument` windows, autosave and window restoration.

## Built 2026-11-21

Every item above is now driven or checked except those under "Low" (C3's handles on open objects, R11, R8, R14 and the
smaller ones), which wait for another round. How each works is in [STATUS.md](../STATUS.md), stage 32's notes. Each new
rule has a test that plants the bug it looks for and proves the rule fails.

The monkey's own mistakes the first runs found, fixed: a CMYK-style drawing it couldn't make; an Adobe RGB profile that
ImageIO reads back unnamed (known now by the name inside it); a preview step checked before its autosave; keys sent with
no key code (the canvas reads keys through the layout, so none landed); an open step badge not counted as placed first;
Auto-Redact starved of words it can find; a merge exemption matched by name.

### Second round, 2026-11-22

Leah asked for the smaller gaps too. The monkey now also drives Image ▸ Trim, Layer ▸ Revert Layer, a picture dropped
onto the canvas (an sRGB PNG converted and pasted floating), clicks in the History panel (`jump(toStep:)`, which the
undo checker follows like several undos or redos), the Magic Wand (Color and Object modes, Shift and Option), Free-Form
Select, step badges (clicked, dragged into arrows, left open), Measure and the Eyedropper (which must change nothing),
handles on open shapes and text boxes (C3), Copy Text (given a clipboard count no real clipboard has, so a later
redaction never clears Leah's clipboard), and Shift-clicking several subjects before Return. Refine Edge and untangling
run inside the subject steps. `everySecondRoundStepMeetsTheRules` checks each step lands, not just that it breaks no rule.
A 5-minute run (135 pictures, 8,100 steps) broke no rule.

Still open: R8 (Merge Down and Flatten keep the look) needs Leah to say how close is close enough, since some blend modes
inside groups can't merge exactly; R11 (text after crops and turns) and R14 (thumbnails beyond the end check) are low.
Auto-Redact finds words to cover about once in a hundred tries, as it has since 2026-11-09: a few hundred times a night.

### Leaks

In Debug, about one episode in ten leaves its editor held after it ends. `leaks --trace` led first to a canvas view with
no window (fixed: the monkey's canvas now has a hidden window, as a real one does), then only to the test run's own
suspended work. A canvas in a real window frees its editor when closed, and a 2-minute Release run left none held in
423 pictures. So the rule fails only when most episodes leave one, and the report gives the count each night.

### Leah's answers (2026-11-22)

All five as recommended, recorded in [FRD §23](../FRD.md#23-decision-log):

1. **Before/After ends a drag under way.** Fixed in `CanvasView` (`dropDragForComparison`): what was drawn before stays, the
   rest of the drag does nothing; panning and the divider carry on. `beforeAfterEndsADragUnderWay` proves it, and fails
   without the fix. The monkey's Before/After rule stays.
2. **Keys and menu commands may still edit while Before/After shows.** The monkey keeps checking only mouse events.
3. **A floating piece may be placed on a layer locked while it floated**, (4) **Merge Down may paint into locked clear
   pixels**, and (5) **a text layer's words may change with transparent pixels locked**. The monkey's lock rule leaves
   these out for good.
