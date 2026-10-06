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
- **Screenshots are light mode only.** The page text still adapts to dark mode.
- **Screenshots are taken by a script**, so they can be retaken quickly when the look changes (see phase 1).
- **No "What's new" page.** Beta notes stay in `Start Here.txt`.

These go into the FRD (new FR-14.6, below) and the §23 decision log in phase 0.

**Updated 2026-10-06** for what was built after the plan was written: pages and PDFs (stage 10), RAW photos and
the Develop window (stage 12), review rounds 3 and 4, the General settings tab, drag-to-change number fields, the
toolbar's single drawing-tools group, and the palette bar without palettes or Edit Colors.

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
| **Getting started** | A tour of the window: toolbar (selection tools, then one drawing-tools group with Brushes and Shapes after the Pencil, then Size), palette bar, canvas, sidebar, status bar. Color 1 and Color 2 (left- and right-click; double-click a well to choose any color). One-key tools. Drag up or down on a number field to change it (down for bigger, Shift for faster). New documents start with Rectangle Select. Undo with no limit. Where to find Settings. Replaces most of `Start Here.txt`. |
| **Redact a screenshot** | Clipboard screenshot → Paste into New Image → Auto-Redact (it always reads the whole image, every page, and ignores a selection; Solid Fill is safest; why Blur and Pixelate can sometimes be read back; one ⌘Z undoes it on every page) → Batch Redact for chosen areas and anything it missed (every layer under the selection) → check with Before/After → export. What else keeps a copy and how Colorbee offers to clear it: earlier versions and the undo history (after ⌘S), and Clipboard History, including copies made from the document. |
| **Annotate an image** | Arrows, shapes and callouts, text and text styles, the marker as a highlighter, Crop and the size presets, Copy for Slack. |
| **Work with layers** | When to use layers. New, duplicate, merge and flatten. Blend modes, opacity, lock. Adjustment layers. Undo on Active Layer and Revert Layer. Why a layered image saves as a project. |
| **Fix up a photo** | Adjust Photo and Auto, filters, Levels and Curves, Straighten, Perspective, Remove Background and Lift Subject. RAW photos and the Develop window: each control, Highlights only going down, greyed-out controls a camera doesn't support, Reset to Camera, why to develop before opening (RAW precision). Including camera details on export. |
| **Pages and PDFs** | Documents with pages, the page sidebar (click, right-click, drag to reorder, which scrolls in long documents), the Page menu, each page's own undo, opening PDFs (and the resolution in Settings ▸ General), multi-page TIFFs and GIFs, Export as PDF (no metadata, pixels only), Auto-Redact on every page, making a PDF from screenshots. |
| **Pixel art** | Pencil, pixel grid, zoom to 3200%, symmetry, the Color Eraser. |
| **Save, export and share** | Formats and what each keeps (a table); the image-or-project rule; Save and Export each remember the last format; Export and its "Include camera details"; Export As presets; Export as PDF; Share, Print, Set as Desktop Picture; autosave (untitled documents keep everything after a relaunch), Revert To and Versions. |

### Reference

| Page | Covers |
|---|---|
| **Tools** | One section per tool: Pencil, the 9 brushes, Eraser and Color Eraser (and its switch), Fill, Eyedropper, Magnifier, Rectangle/Ellipse and Free-Form select, Magic Wand (Shift adds, Option removes, Shift-Option keeps the overlap), Shapes (all 23, plus the Arrow), Gradient, Text, Measure. Each covers what it does, its options in the palette bar, left versus right click, its key, and modifiers (Shift, Option). |
| **Menus** | Every command in File, Edit, View, Image, Layer, Adjustments and Effects, with its default shortcut and one line on what it does (the existing tooltips in `MainMenu.swift` are the starting point). |
| **Panels** | Layers, Adjustments, History (it steps only the page shown), Clipboard History, the page sidebar, Before/After. |
| **Settings** | General (Appearance: System, Light or Dark; Open PDFs at 150, 200 or 300 DPI), Shortcuts (recording, conflicts, reset, import and export), Export Presets. |
| **Keyboard shortcuts** | One table of every default: menu commands and the single-key tool and canvas keys (FR-14.5). |
| **Privacy** | No network at all; Auto-Redact reads text on the Mac with Apple's Vision; Remove Earlier Versions and Undo History; the Clipboard History offer; what Export as PDF writes (no metadata, no text); camera details only when asked, never location, serial numbers or owner; which files Colorbee keeps and where (Clipboard History, desktop pictures). |
| **Troubleshooting** | Common surprises (why an image became a project, why a menu item is greyed out, locked layers, why ⌘Z doesn't undo a selection, a RAW camera macOS doesn't know yet) and how to report a problem with a crash report. |

### Screenshots (about 9)

1. The whole window, with callouts naming the toolbar, palette bar, canvas, sidebar and status bar
2. The toolbar
3. The palette bar
4. The Auto-Redact sheet with matches found
5. Before/After
6. The Layers panel with a few layers and an adjustment layer
7. Export As presets
8. Settings ▸ Shortcuts
9. The Develop window, with a made-up RAW photo (`TestImages/Stage 12/Test Camera.dng`)

Rules for the screenshots:
- **Made-up content only.** The repo is public, so use a sample screenshot with fake details, for example
  `bee@example.com`, `555-0100`, and a fake key `sk_test_…`.
- **Window shots at 2×**, without the window shadow.
- **Light mode only.**
- **The setup for each shot is written down** (document, zoom, which panel is open), and a script
  takes them all, so they can be retaken exactly whenever the look changes.

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
- **Screenshot script:** `make help-shots`.
  - It launches Colorbee with a developer-only flag (like `-ColorbeeBenchmark`), for example
    `-ColorbeeHelpShots YES`.
  - The app opens each written setup in turn (sample document, zoom, panel or sheet open) and captures the window
    with `screencapture -l <window id> -o` (no shadow), into the book's images folder.
  - It forces light appearance while it runs (`-Appearance light`) and ignores saved window state
    (`-ApplePersistenceIgnoreState YES`), so old windows don't reopen and pile up.
  - Like `make bench`, it brings windows to the front, so it runs only when Leah says so.
  - The made-up sample images it uses are committed with it.
- **Keeping the tables true:** the Menus and Keyboard shortcuts pages are generated, not typed.
  - A developer-only launch flag (like `-ColorbeeBenchmark`), for example `-ColorbeeDumpMenus YES`, writes every
    menu command, its default shortcut and its tooltip, plus the canvas keys from `ShortcutStore`, as JSON, then
    quits.
  - A small script turns that into the two HTML pages.
  - `make help` runs both. That way a renamed command or a changed default can't leave the help wrong.

## Order of work

Each phase ends with Leah hand-testing it. Recommended model: Opus throughout. Effort is medium for phases 1–5
(routine) and high for phase 6 (accuracy review).

**Timing:** ready to start. The round-3 and round-4 review fixes have landed, so the behavior the help describes
is settled. (The frame bar from round 3 was later replaced by pages, so the help covers pages, not frames.)

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
- The `make help-shots` script, with the first setup (the whole window) as a test.
- **Leah tests:**
  1. `make run`, then Help ▸ Colorbee Help. The help viewer opens on the placeholder page.
  2. Press ⌘? from anywhere in Colorbee: the same.
  3. Click Help, type "colorbee" in the search field: the placeholder topic is listed under Help Topics.
  4. Turn on dark mode (System Settings ▸ Appearance): the page is readable.
  5. When the engineer asks, let `make help-shots` run (it takes over the screen for a minute). Open the new
     window screenshot: Colorbee in light mode, with no window shadow and no personal content.

### Phase 2: the two pages that matter most
- **Getting started** and **Redact a screenshot**, with screenshots 1–5.
- Update `Start Here.txt` to point at Help ▸ Colorbee Help, keeping only installing, privacy and reporting
  problems.
- **Leah tests:** follow each guide step by step on a clean launch, exactly as written, using the made-up sample
  screenshot. Every step should work and every menu name should match. Note any step that's unclear.

### Phase 3: the other task guides
- Annotate, Work with layers, Fix up a photo, Pages and PDFs, Pixel art, Save, export and share.
- Screenshots 6, 7 and 9.
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
- A review session ("M: help accuracy"; K and L were review round 4) checks every page against the code and the
  FRD. In particular, it
  checks that each step, menu name, default and limit is what the app really does. It reports mismatches like
  the other reviews.
- Fix what it finds. Leah reads the whole book once.
- Update `STATUS.md` (a new row in the build table) and the README (a line about Help).

## Keeping it current

- **New rule for `CLAUDE.md` (Workflow):** any change to user-visible behavior updates the matching help page in
  the same commit. Run `make help` after adding, renaming or re-keying a menu command.
- **Screenshots** are retaken with `make help-shots` (with Leah's OK) when the part of the window they show changes.
- **Each later stage's "please try" list for Leah** includes "read the help page for this".
