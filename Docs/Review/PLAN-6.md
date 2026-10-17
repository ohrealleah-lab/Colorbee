# Help accuracy review (help phase 6): sessions M and Q

Colorbee Help (`Help/Colorbee.help/Contents/Resources/en.lproj/`) was written in help phases 1–5
([../HELP-PLAN.md](../HELP-PLAN.md)) from the FRD and the code. This review checks that **every claim in it is what
the app really does**: each step works as written, and every menu name, button label, key, default, limit and
behavior matches the code. Testers will follow these pages word for word, so a wrong step is a real bug.

Two sessions, **M** (the task guides) and **Q** (the reference pages). They're independent and can run at the same
time.

## Rules

These sessions run **locally, in Leah's Colorbee folder**. Follow "Rules for every review session" and "Findings
file format" in [PLAN.md](PLAN.md) only where they don't clash with these:

- **Review only. Don't touch git** (no branches, commits, stashes or pushes): other sessions may be working in the
  same folder. Don't change any page, source file or doc. Your only output is one new file,
  `Docs/Review/findings-M.md` or `findings-Q.md`, using the format below. The engineer commits it and fixes what it
  finds.
- **Don't build, run the app or run tests.** Reason from the code. Never open Leah's personal files (her Downloads,
  Desktop, Documents or Pictures); use only `TestImages`.
- **The code is the truth for what the app does; the FRD (with its §23 decision log) is the truth for what it
  should do.** If the page matches the FRD but the code doesn't, report it as a code bug (say so). If the page
  differs from both, it's a help bug. Help phase decisions are in FRD §23 (entries from 2026-10-06 on) and
  [../HELP-PLAN.md](../HELP-PLAN.md): for example, palettes are a hidden feature and are left out on purpose, and
  iPhone import into an open document is a known pinned problem.
- **Check against the code, not memory.** Menu titles and key equivalents are in `Sources/Colorbee/MainMenu.swift`
  (and `ShortcutStore.swift` for defaults); tool keys and names in `Editor.swift` and the toolbar/palette bar views
  (`DocumentToolbar.swift`, `PaletteBar.swift`, `DocumentView.swift`, `Galleries.swift`); sheets and windows in
  their own files (`AutoRedactSheet.swift`, `ResizeSkewSheet.swift`, `CanvasPropertiesSheet.swift`,
  `DevelopWindow.swift`, `Settings.swift`, `ShortcutSettings.swift` and so on); limits and defaults in the core
  (`Packages/ColorbeeCore/Sources/ColorbeeCore/`). Quote the line that proves each finding.
- **Check every step in order**, as a tester would: is the command where the page says, is it enabled in that
  situation (see `DocumentWindow.validateMenuItem` and the views' `.disabled`), and does the result look like the
  page says?
- **Also check:** every link and `#anchor` between pages resolves (anchors are `<a name="…">`; the ? buttons'
  anchors in `Sources/Colorbee/HelpBook.swift` must each appear once in the whole book); every picture's `alt`
  text matches what the picture in `images/` shows; nothing promises a feature that isn't built.
- **Not bugs:** style, tone and wording preferences, unless the wording would make a tester do the wrong thing.
  Pages are written plainly on purpose.

## Findings file format

```markdown
# Review <letter>: help accuracy, <the pages>
Reviewed at commit: <full hash>
Checked: <one line per page, saying what you checked>

## <n>. <one-line summary>
- **Severity:** High (a step that doesn't work, or a wrong claim about privacy or redaction) · Medium (a wrong name,
  key, default or limit) · Low (missing or unclear, but not wrong)
- **Confidence:** High · Medium · Low
- **Page:** `page.html` line <n>, section "<heading>"
- **The help says:** the claim, quoted briefly.
- **The app does:** what the code does, with `path/File.swift:123` and the line quoted briefly.
- **Which is right:** help bug or code bug, and why (FRD section or §23 entry).
- **Suggested fix:** new wording for the page (plain, short, in its style), or the code change.
```

Order findings most severe first. If a page is fully correct, say so in "Checked".

---

## Session M: the task guides

Pages: `index.html`, `getting-started.html`, `redact-a-screenshot.html`, `annotate-an-image.html`,
`work-with-layers.html`, `fix-up-a-photo.html`, `pages-and-pdfs.html`, `pixel-art.html`,
`save-export-and-share.html`.

Look especially for:
- **Redaction (highest risk):** every claim in Redact a screenshot and the redaction parts of other pages: what
  Auto-Redact finds and where (layers, pages, hidden layers), what each treatment does, Batch Redact on soft
  selections, the Redact Brush (every layer, applied on release), the earlier-versions and Clipboard History offers,
  and what "check your work" tells people to look for. A wrong safety claim here is the worst kind of finding.
- **Steps that can't be done as written:** a command that's greyed out in that situation, a key that does
  something else, a button or label that's named differently, a sheet that opens somewhere else.
- **Numbers:** sizes, ranges and defaults (brush and Retouch sizes, Resize and Skew ranges, canvas limits, export
  preset sizes, zoom range, Feather, Straighten steps, crop presets).
- **New this week:** the Redact menu (redaction moved out of Effects), Lift Subject to New Layer in the Layer menu,
  the toolbar showing Size and Outline/Fill only for tools that use them, 4 custom colors, the new sections
  "Resize and Skew", "Canvas Properties" and "Using the Clone Stamp" (FRD §23, 2026-10-15 to 2026-10-16).
- Pictures: `window.png`, `toolbar.png`, `palette-bar.png`, `auto-redact.png`, `before-after.png`, `layers.png`,
  `develop.png`: does each page's text and `alt` describe what's in it?

## Session Q: the reference pages

Pages: `tools.html`, `panels.html`, `settings.html`, `privacy.html`, `troubleshooting.html`, and a spot check of the
generated `menus.html` and `keyboard-shortcuts.html`. Also `Docs/Beta/Start Here.txt`, the note testers read first.

Look especially for:
- **Tools:** each tool's key, options, ranges and right-click behavior against `Editor.swift` and the palette bar.
  Every tool in the toolbar should be on the page, and nothing that isn't.
- **Panels and Settings:** every control named as it appears, with its real default; what each setting changes.
- **Privacy:** every promise (on-device only, no networking, what's saved where, what exports include or strip,
  camera details, clipboard handling, earlier versions). Check each against the code: a broken promise here is
  High.
- **Troubleshooting:** each problem's cause and fix is real, and the messages quoted are the app's exact text
  (search for them in the code).
- **Generated pages:** they're made by `make help` from the app's own menus (`HelpDump.swift`,
  `Scripts/help-pages.py`). Check they're current with `MainMenu.swift` (menu order, the Redact menu, Lift Subject
  in Layer) and that the tool keys table matches; report it if they look stale.
- **Start Here.txt:** what it tells testers to do still works in Beta 4 and points them to Help correctly.

---

## Prompts for Leah

Run each in a fresh local session in the Colorbee folder, on **Opus, high effort**.

**Session M:**

> You're a reviewer for Colorbee. Read `Docs/Review/PLAN-6.md` and do **session M** (the task guides), following
> its rules exactly: review only, don't touch git, don't build or run anything. Write your findings to
> `Docs/Review/findings-M.md`, then tell me how many findings you have at each severity.

**Session Q:**

> You're a reviewer for Colorbee. Read `Docs/Review/PLAN-6.md` and do **session Q** (the reference pages),
> following its rules exactly: review only, don't touch git, don't build or run anything. Write your findings to
> `Docs/Review/findings-Q.md`, then tell me how many findings you have at each severity.
