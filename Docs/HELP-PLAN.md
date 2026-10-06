# Plan: Colorbee Help

Colorbee's Help menu is empty today: it has only macOS's own search field. The FRD says "Standard" for it
(FR-14.5), and the only usage guide is the beta's `Docs/Beta/Start Here.txt`. This plan adds a real help book.

## Decisions so far (Leah, 2026-10-06)

- **Format:** a standard Mac **Help Book**.
  - Help ▸ Colorbee Help (⌘?) opens it in Apple's help viewer.
  - The Help menu's search field finds help topics as well as menu items.
  - It ships inside the app and works offline, which matters because Colorbee has no network access.
- **Scope:** task guides first (how to do the main jobs), then a full reference (every tool, menu, panel and setting).
- **Pictures:** a few key screenshots, where they help most. Everything else is text.

These go into the FRD (new FR-14.6, below) and the §23 decision log in phase 0.

## Principles

- **Describe what the app actually does.** The FRD and §23 say what's intended, but the help must match the
  shipped behavior. Every page is checked against the code and by hand (phase 6).
- **Plain, friendly, short.** Second person ("Choose Effects ▸ Auto-Redact…"), short sentences, numbered steps.
  The same voice as `Start Here.txt`.
- **Menus and keys exactly as they appear.** Use the menu path with ▸, and the macOS key symbols (⌘ ⇧ ⌥ ⌃).
  Every shortcut is shown as a default, with a note that Settings ▸ Shortcuts can change it (FR-15.3).
- **Leave out what's hidden.** Palettes are hidden for now (FR-15.1, 2026-10-05), so they're not in the help.
  Planned features (FR-11.7, iPhone import) are added when they ship.
- **Accessible.**
  - Real headings and lists.
  - Alt text on every screenshot.
  - Readable in dark mode (CSS `prefers-color-scheme`).
  - Text sizes that follow the help viewer's.
- **English first, ready for more.** Pages live in `en.lproj`, so another language can be added later without
  restructuring.

## What's in the book

### Task guides (the main way in)

| Page | Covers |
|---|---|
| **Getting started** | A tour of the window: toolbar, palette bar, canvas, sidebar, status bar. Color 1 and Color 2 (left- and right-click). One-key tools. Undo with no limit. Where to find Settings. Replaces most of `Start Here.txt`. |
| **Redact a screenshot** | Clipboard screenshot → Paste into New Image → Auto-Redact (Solid Fill is safest; why Blur and Pixelate can sometimes be read back) → Batch Redact for anything it missed → check with Before/After → export. What else keeps a copy: Versions, Clipboard History, and how to clear them (written after the round-3 fixes, see "Order"). |
| **Annotate an image** | Arrows, shapes and callouts, text and text styles, the marker as a highlighter, Crop and the size presets, Copy for Slack. |
| **Work with layers** | When to use layers. New, duplicate, merge and flatten. Blend modes, opacity, lock. Adjustment layers. Undo on Active Layer and Revert Layer. Why a layered image saves as a project. |
| **Fix up a photo** | Adjust Photo and Auto, filters, Levels and Curves, Straighten, Perspective, Remove Background and Lift Subject, RAW photos and the Develop window. |
| **Pages and PDFs** | Documents with pages, the page sidebar, opening PDFs, Export as PDF, Auto-Redact on every page. |
| **Pixel art** | Pencil, pixel grid, zoom to 3200%, symmetry, the Color Eraser. |
| **Save, export and share** | Formats and what each keeps (a table); the image-or-project rule; Export and Export As presets; Share, Print, Set as Desktop Picture; autosave, Revert To and Versions. |

### Reference

| Page | Covers |
|---|---|
| **Tools** | One section per tool: Pencil, the 7 brushes, Eraser and Color Eraser, Fill, Eyedropper, Magnifier, Rectangle/Ellipse and Free-Form select, Magic Wand, Shapes (all 23), Gradient, Text, Measure. Each covers what it does, its options in the palette bar, left versus right click, its key, and modifiers (Shift, Option). |
| **Menus** | Every command in File, Edit, View, Image, Layer, Adjustments and Effects, with its default shortcut and one line on what it does (the existing tooltips in `MainMenu.swift` are the starting point). |
| **Panels** | Layers, Adjustments, History, Clipboard History, the page sidebar, Before/After. |
| **Settings** | Shortcuts (recording, conflicts, reset, import and export), Export presets, Appearance. |
| **Keyboard shortcuts** | One table of every default: menu commands and the single-key tool and canvas keys (FR-14.5). |
| **Privacy** | No network at all; Auto-Redact reads text on the Mac with Apple's Vision; which files Colorbee keeps and where (Clipboard History, desktop pictures). |
| **Troubleshooting** | Common surprises (why an image became a project, why a menu item is greyed out, locked layers) and how to report a problem with a crash report. |

### Screenshots (about 8)

1. The whole window, with callouts naming the toolbar, palette bar, canvas, sidebar and status bar
2. The toolbar
3. The palette bar
4. The Auto-Redact sheet with matches found
5. Before/After
6. The Layers panel with a few layers and an adjustment layer
7. Export As presets
8. Settings ▸ Shortcuts

Rules for the screenshots:
- **Made-up content only.** The repo is public, so use a sample screenshot with fake details, for example
  `bee@example.com`, `555-0100`, and a fake key `sk_test_…`.
- **Window shots at 2×**, without the window shadow.
- **The setup for each shot is written down** (document, zoom, which panel is open), so it can be retaken
  exactly when the look changes.
- A question for Leah below: light only, or light and dark.

## How it's built (technical)

- **The book:** `Sources/Colorbee/Colorbee.help/`, a standard help bundle:
  - `Contents/Info.plist` with `CFBundleIdentifier` (`com.leah.Colorbee.help`), `CFBundlePackageType`
    `BNDL`, `HPDBookTitle` "Colorbee Help", `HPDBookType` 3, `HPDBookAccessPath` (the start page),
    `HPDBookIndexPath` and `HPDBookIconPath`.
  - `Contents/Resources/en.lproj/`: the HTML pages, images and the search index. Shared CSS goes in
    `Contents/Resources/shared/`.
  - Each page has `<meta name="AppleTitle">`, a description and keywords (these feed the search), and
    `<a name="…">` anchors for the contextual help buttons.
- **The app's Info.plist** (in `project.yml`): `CFBundleHelpBookFolder` = `Colorbee.help`,
  `CFBundleHelpBookName` = `com.leah.Colorbee.help`.
- **XcodeGen:** add the bundle as a folder resource (`type: folder`, `buildPhase: resources`), so it's copied as
  is rather than its files being flattened into the app.
- **Search index:** generated with `hiutil -I corespotlight` into the bundle. The plan's preference is a build
  step with declared inputs and outputs, since script sandboxing is on. If that fights the sandbox, use a
  `make help` target and commit the index. Check the exact `hiutil` flags with `man hiutil` on the build Mac.
- **Help menu:** a "Colorbee Help" item with `showHelp:` and ⌘? (⇧⌘/), which the FRD already reserves
  (FR-15.3), so it can't be reassigned.
- **Contextual help:** small ? buttons (SwiftUI `HelpLink`) in the places people get stuck. Each opens its
  page at an anchor with `NSHelpManager.shared.openHelpAnchor(_:inBook:)`. The places:
  - the Auto-Redact sheet
  - Settings ▸ Shortcuts and Export presets
  - Resize and Skew
  - Canvas Properties
  - the Develop window
- **Keeping the tables true:** the Menus and Keyboard shortcuts pages are generated, not typed.
  - A developer-only launch flag (like `-ColorbeeBenchmark`), for example `-ColorbeeDumpMenus YES`, writes every
    menu command, its default shortcut and its tooltip, plus the canvas keys from `ShortcutStore`, as JSON, then
    quits.
  - A small script turns that into the two HTML pages.
  - `make help` runs both. That way a renamed command or a changed default can't leave the help wrong.

## Order of work

Each phase ends with Leah hand-testing it. Recommended model: Opus throughout. Effort is medium for phases 1–5
(routine) and high for phase 6 (accuracy review).

**Best timing:** after the round-3 review fixes (H, I, J) land. Several of them change what the help would say:
Batch Redact on every layer, "Only visible layers were checked", the Versions warning, Clipboard History
removal, the frame bar, and tools greyed out during effects. The plumbing (phase 1) can start any time.

### Phase 0: FRD and decisions
- Add **FR-14.6 Help**:
  - Help ▸ Colorbee Help (⌘?) opens a Help Book.
  - The Help menu's search finds help topics.
  - Contextual ? buttons in the places listed above.
  - The book has task guides and a reference, with a few screenshots.
  - Change the FR-14.5 menu table's "Window / Help: Standard" to point at FR-14.6.
- Add to §23 today's decisions, plus any choices the engineer makes on their own, phrased "veto any".
- Add acceptance criteria:
  - **AC-a:** ⌘? opens Colorbee Help.
  - **AC-b:** typing "redact" in the Help menu's search lists the Redact a screenshot guide.
  - **AC-c:** every menu command appears in the Menus reference with its default shortcut.
  - **AC-d:** each contextual ? button opens the matching section.

### Phase 1: plumbing
- The help bundle, the Info.plist keys, the folder resource, the index step, the Help menu item, and one placeholder
  page.
- **Leah tests:**
  1. `make run`, then Help ▸ Colorbee Help. The help viewer opens on the placeholder page.
  2. Press ⌘? from anywhere in Colorbee: the same.
  3. Click Help, type "colorbee" in the search field: the placeholder topic is listed under Help Topics.
  4. Turn on dark mode (System Settings ▸ Appearance): the page is readable.

### Phase 2: the two pages that matter most
- **Getting started** and **Redact a screenshot**, with screenshots 1–5.
- Update `Start Here.txt` to point at Help ▸ Colorbee Help, keeping only installing, privacy and reporting
  problems.
- **Leah tests:** follow each guide step by step on a clean launch, exactly as written, using the made-up sample
  screenshot. Every step should work and every menu name should match. Note any step that's unclear.

### Phase 3: the other task guides
- Annotate, Work with layers, Fix up a photo, Pages and PDFs, Pixel art, Save, export and share.
- Screenshots 6–7.
- **Leah tests:** the same as phase 2, one guide at a time.

### Phase 4: the reference
- Tools, Panels, Settings, Privacy and Troubleshooting, written by hand.
- Menus and Keyboard shortcuts, generated with `make help`.
- Screenshot 8.
- **Leah tests:**
  1. Open any menu, pick three commands at random, and check each is on the Menus page with the same name and
     shortcut.
  2. In Settings ▸ Shortcuts, compare five shortcuts with the Keyboard shortcuts page.
  3. Search the Help menu for "magic wand", "layer" and "export": each finds a sensible page.

### Phase 5: contextual help buttons
- The ? buttons and their anchors.
- **Leah tests:** open each sheet or panel in the list, click its ?, and check the right section opens.

### Phase 6: accuracy review and wrap-up
- A cloud review session ("K: help accuracy") checks every page against the code and the FRD. In particular, it
  checks that each step, menu name, default and limit is what the app really does. It reports mismatches like
  the other reviews.
- Fix what it finds. Leah reads the whole book once.
- Update `STATUS.md` (a new row in the build table) and the README (a line about Help).

## Keeping it current

- **New rule for `CLAUDE.md` (Workflow):** any change to user-visible behavior updates the matching help page in
  the same commit. Run `make help` after adding, renaming or re-keying a menu command.
- **Screenshots** are retaken from their written setups when the part of the window they show changes.
- **Each later stage's "please try" list for Leah** includes "read the help page for this".

## Questions for Leah

1. **Screenshots in dark mode too?**
   - Light only is half the work.
   - Light and dark means each shot follows the viewer's appearance.
   - Recommendation: light only, since the page text adapts to dark mode either way.
2. **Who takes the screenshots?**
   - Leah by hand from the written setups (⇧⌘5, window capture), or
   - Claude with a script that opens each setup and captures the window. Like `make bench`, it brings windows to
     the front, so it would only run when Leah says so.
   - Recommendation: the script, so retakes are quick.
3. **A "What's new" page** for each beta, so testers know what to try? (Optional; it could also stay in
   `Start Here.txt`.)
