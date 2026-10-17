# Review Q: help accuracy, the reference pages
Reviewed at commit: 58b4e28a0ca31cd685ac771c36a9f94957fc7047
Checked:
- `tools.html`: every tool in the toolbar is here, in toolbar order, and nothing extra (`DocumentToolbar.swift`). Keys against `ShortcutStore.canvasCommands`; names against `ToolAppearance.swift`; brush, retouch, shape, gradient and paint-style lists against the core enums; size ranges against `Editor.toolSizeRange`; palette bar options against `DocumentView.ToolOptions`; modifiers and right-click against `CanvasView` and `Editor`. Links resolve. Findings 1, 9, 10 and 11.
- `panels.html`: four panels, switcher, closing on the last one, Layers rows and buttons, Adjustments (Reset, Merge, Auto), History, Clipboard History (10 items, kept between launches, hover, Remove, Clear, clipboard untouched), page sidebar, Before/After, and every shortcut against `MainMenu.swift`. Fully correct.
- `settings.html`: General (Appearance, PDF resolution and its letter-page example), Shortcuts (recording, Esc, Delete, ⌘/⌃ rule, conflicts, blue dot, padlocks, Import/Export, search), Export Presets (Width / Fits square, Scaling, buttons, defaults), both pictures. Findings 3 and 12.
- `privacy.html`: no networking code anywhere (no URLSession or Network use); Vision used only for text, subjects and eyes; Export as PDF writes no metadata (`PDFWriter.swift`); camera details are only the eight fields in `CameraDetails.swift`; the Application Support files and Share cleanup. Findings 4 to 7.
- `troubleshooting.html`: project rule (`Editor.isLayered`), greyed-out causes (`DocumentWindow.validateMenuItem`), the "not allowed" pointer, the quoted messages (searched in the code), RAW message, report steps. The iPhone entry matches the known pinned problem, so not reported. Findings 1, 2 and 8.
- `menus.html` and `keyboard-shortcuts.html` (spot check): current with `MainMenu.swift`: menu order, the Redact menu after Effects with Batch Redact as a heading, Lift Subject to New Layer in Layer, every key equivalent, and the tool keys table. Not stale. One tooltip text issue, finding 13.
- `Docs/Beta/Start Here.txt`: system needs, notarized install (`Scripts/make-beta.sh` signs with hardened runtime, notarizes and staples), Help ▸ Colorbee Help (⌘?) and the two guide titles, privacy line, crash report steps. Fully correct.
- Links and anchors: every link from these pages resolves; the eight ? button anchors in `HelpBook.swift` each appear exactly once in the book.

## 1. Option-dragging to take part of a selection away moves a copy of the pixels instead
- **Severity:** High
- **Confidence:** High
- **Page:** `troubleshooting.html` line 37, section "⌘Z didn't undo my selection" (also `tools.html` line 25, section "Selection tools")
- **The help says:** "To take part of a selection away, hold Option and drag around it with a selection tool". Tools: "Hold a key as you start dragging: Shift adds to the selection, Option takes away from it".
- **The app does:** with the Rectangle, Ellipse or Free-Form tool, a drag that *starts inside* the selection always moves it, and Option makes that a copy. Only a drag that starts outside subtracts. `Sources/Colorbee/Editor.swift:2141-2146`: `let wandCombining = tool == .magicWand && (modifiers.shift || modifiers.option)` / `if !wandCombining, selectionContains(point), … { … selectionDrag = .move(…, smear: modifiers.shift, duplicate: modifiers.option)`. The part someone wants to take away is inside the selection, so the natural drag starts there. They get a moved copy of the pixels (an image change, not a selection change). Shift does the same thing (a trail of copies instead of adding).
- **Which is right:** help bug. FRD FR-3.2 has both "Option: Subtract" and "Option-drag moves a copy"; the code resolves the clash by where the drag starts, and the pages don't say so.
- **Suggested fix:** troubleshooting: "To take part of a selection away, hold Option and start dragging *outside* the selection, across the part to remove, or Option-click with the Magic Wand. (Option-dragging from inside the selection moves a copy.)" Tools line 25: "Hold a key as you start dragging outside the selection: …". Line 36 already explains dragging inside.

## 2. Batch Redact Blur… and Pixelate… don't need a selection
- **Severity:** Medium
- **Confidence:** High
- **Page:** `troubleshooting.html` line 27, section "A menu command is greyed out"
- **The help says:** "It needs a selection, such as Crop to Selection, Spotlight… or Batch Redact. Select an area first."
- **The app does:** only Solid Fill with Color 1 is greyed out without a selection (`Sources/Colorbee/DocumentWindow.swift:394-396`: `#selector(applySolidFill(_:)): return editor.hasSelection`). Blur… and Pixelate… aren't in the switch, so they fall to `default: return super.validateMenuItem(menuItem)` (line 473-474) and stay enabled. With nothing selected they open the bar and redact the whole page on every layer: `Sources/Colorbee/DocumentView.swift:396`: `editor.hasSelection ? "Redacts every layer in the selection" : "Redacts every layer"`.
- **Which is right:** help bug. FR-9.4 doesn't ask for them to be greyed out. (If Leah wants all three to need a selection, it's a code change instead: add the two selectors beside `applySolidFill` at `DocumentWindow.swift:395`.)
- **Suggested fix:** "It needs a selection, such as Crop to Selection, Spotlight… or Redact ▸ Solid Fill with Color 1. Select an area first."

## 3. A shortcut macOS already uses is refused, not given a warning
- **Severity:** Medium
- **Confidence:** High
- **Page:** `settings.html` line 34, section "Shortcuts"
- **The help says:** "If your Mac uses them for something else, an orange warning shows beside the command."
- **The app does:** pressing keys macOS uses doesn't set them. The keys are refused, and an orange message appears under the list. `Packages/ColorbeeCore/Sources/ColorbeeCore/Shortcuts.swift:175`: `if let owner = Self.reservedByMac[shortcut] ?? system[shortcut] { return .reserved(owner: owner) }`, then `Sources/Colorbee/ShortcutSettings.swift:168-169`: `case .reserved(let owner): message = "\(shortcut.display) is used by \(owner)."` (not assigned). The orange triangle beside a command (`ShortcutSettings.swift:84-87`) only shows when a command's *current* shortcut (usually its default) clashes with this Mac, as on Save As in `shortcuts.png`.
- **Which is right:** help bug (behavior is §23, 2026-10-03: "A command whose shortcut macOS takes first on this Mac shows an orange warning"; "Importing skips … shortcuts reserved on this Mac").
- **Suggested fix:** "If your Mac uses those keys for something else, Colorbee says so and keeps the old shortcut. An orange warning beside a command means macOS takes its shortcut first on this Mac: give it another one."

## 4. The earlier-versions offer only appears when the file has earlier versions
- **Severity:** Low
- **Confidence:** High
- **Page:** `privacy.html` line 31, section "Copies a redaction can leave behind"
- **The help says:** "after you redact and save with ⌘S, Colorbee offers Remove Earlier Versions and Undo History, so the original can't be brought back."
- **The app does:** the alert is skipped when macOS has no other versions of the file, for example the first save of a pasted screenshot. `Sources/Colorbee/ImageDocument.swift:204`: `guard let versions = NSFileVersion.otherVersionsOfItem(at: url), !versions.isEmpty, let window = windowForSheet else { return done() }`. In that case the undo history stays, and ⌘Z can still bring the original back in that window until it's closed.
- **Which is right:** help bug (the code matches §23, 2026-10-04: it warns that earlier versions still show the redaction). A tester who redacts a pasted screenshot and saves will wait for a dialog that never comes.
- **Suggested fix:** "after you redact and save with ⌘S, if the file has earlier versions, Colorbee offers Remove Earlier Versions and Undo History, so the original can't be brought back."

## 5. Untitled documents' autosaves aren't listed among the files kept
- **Severity:** Low
- **Confidence:** Medium
- **Page:** `privacy.html` lines 44-52, section "Files Colorbee keeps"
- **The help says:** lists only Clipboard History, Desktop Pictures and Filters.json in Application Support, plus temporary Share copies.
- **The app does:** documents autosave in place (`Sources/Colorbee/ImageDocument.swift:55`, `autosavesInPlace`), and an untitled one autosaves as a project (`ImageDocument.swift:254-256`: `fileURL == nil ? UTType.colorbeeProject.identifier : …`) in macOS's own autosave folder. A pasted, not-yet-redacted screenshot sits there until it's saved or closed. The confidence is Medium only because the exact folder is macOS's choice.
- **Which is right:** help bug (missing, not wrong). Standard autosave is FR-15 / guiding principle 7.
- **Suggested fix:** add: "An untitled image is autosaved by macOS until you save or close it, so it comes back after a crash."

## 6. A Colorbee project keeps the camera details
- **Severity:** Low
- **Confidence:** High
- **Page:** `privacy.html` line 41, section "What goes into the files you share"
- **The help says:** "Camera details … go into an exported photo only if you turn on Include camera details in File ▸ Export…."
- **The app does:** that's true of exported images. But a `.colorproj` always stores them: `Packages/ColorbeeCore/Sources/ColorbeeCore/ProjectFile.swift:98`: `… layers: entries, cameraDetails: canvas.cameraDetails, …`. Someone who shares a project file shares the camera, lens, settings and date taken. (Location, serial numbers and the owner's name are never kept, as the page says: `CameraDetails.swift` reads only eight fields.)
- **Which is right:** help bug (missing). Keeping them in projects is intended ("camera details survive a relaunch", `ImageDocument.swift:252`).
- **Suggested fix:** add: "A Colorbee project keeps them, so share an export rather than the project."

## 7. The Copy Text clipboard offer isn't mentioned
- **Severity:** Low
- **Confidence:** High
- **Page:** `privacy.html` line 32, section "Copies a redaction can leave behind"
- **The help says:** only the unredacted image in Clipboard History and on the clipboard.
- **The app does:** text read with Edit ▸ Copy Text before a redaction is offered for removal too. `Sources/Colorbee/DocumentView.swift:136`: `"The clipboard still has the text Copy Text read from this image before the redaction."`
- **Which is right:** help bug (missing). Decided in §23, 2026-10-11 (review N, finding 3).
- **Suggested fix:** "**Clipboard History and Copy Text:** if the unredacted image is in Clipboard History, or text you copied with Copy Text is still on the clipboard, Colorbee offers to remove it."

## 8. Two "not found" messages aren't the ones the page quotes
- **Severity:** Low
- **Confidence:** High
- **Page:** `troubleshooting.html` lines 44-48, section "'No text found', 'No subject found' or 'No red-eye found'"
- **The help says:** the three messages, with "No red-eye found: select the red pupils, then choose Remove Red-Eye again."
- **The app does:** when Vision finds no eyes at all, the message is different: `Sources/Colorbee/Editor.swift:2784`: `"No eyes found. Select the red pupils and try again."` "No text found" is only Copy Text's (`Editor.swift:2743`). Auto-Redact says `"No sensitive text found."` (`Sources/Colorbee/AutoRedactSheet.swift:65`), which means it read the text but nothing matched. A tester may look this up and read "too small or blurry" as the reason.
- **Which is right:** help bug.
- **Suggested fix:** heading "'No text found', 'No subject found' or 'No eyes found'". Bullets: "**No text found** (Copy Text): …"; "**No sensitive text found** (Auto-Redact): Colorbee read the text but found nothing it looks for. Add your own pattern, or redact by hand."; "**No eyes found** or **No red-eye found:** select the red pupils, then choose Remove Red-Eye again."

## 9. "Every tool works on the active layer" isn't true of the Redact Brush
- **Severity:** Low
- **Confidence:** High
- **Page:** `tools.html` line 18, the introduction
- **The help says:** "Every tool works on the active layer."
- **The app does:** the Redact Brush changes every layer with pixels under the stroke (`Sources/Colorbee/Editor.swift:1629`: "Redacts the area on every layer with pixels under it"). The page says so itself at line 111, but the opening line contradicts it, and redaction is where a wrong impression matters most.
- **Which is right:** help bug (FR-9.6).
- **Suggested fix:** "Tools work on the active layer, except the Redact Brush, which changes every layer."

## 10. Size and Outline/Fill are in the toolbar, not the palette bar
- **Severity:** Low
- **Confidence:** High
- **Page:** `tools.html` lines 16-17 (introduction) and line 119, section "Size"
- **The help says:** "A tool's settings appear at the right end of the palette bar when you choose it." The Size section doesn't say where Size is.
- **The app does:** Size, and Outline and Fill, are toolbar groups, shown only for the tools that use them: `Sources/Colorbee/DocumentToolbar.swift:63-75` (`SizeControl … .hiddenKeepingSpace(editor.toolSize == nil)`, `OutlineFillControl … .hiddenKeepingSpace(editor.tool != .shape)`). Line 74 already says "in the toolbar" for Outline and Fill.
- **Which is right:** help bug (§23, 2026-10-15: toolbar shows Size and Outline/Fill only for tools that use them).
- **Suggested fix:** line 119: "In the toolbar, for the tools that have a size: five preset sizes and a box for any size. [ and ] make it smaller or larger."

## 11. Pen pressure can be turned off, and it applies to the Retouch brushes too
- **Severity:** Low
- **Confidence:** High
- **Page:** `tools.html` line 53, section "Brushes (B)"
- **The help says:** "On a Force Touch trackpad or a pen tablet, pressing harder makes the stroke bigger."
- **The app does:** the Brushes gallery has a switch for it: `Sources/Colorbee/Galleries.swift:70`: `Toggle("Pressure changes the size", isOn: $editor.usesPressure)`. The palette bar shows whether it's on: `DocumentView.swift:160`: `pressure \(editor.usesPressure ? "on" : "off")`. The same setting sizes the Retouch brushes (`CanvasView.swift:594` passes `pressure(event)` to `beginRetouchBrush`).
- **Which is right:** help bug (missing).
- **Suggested fix:** "On a Force Touch trackpad or a pen tablet, pressing harder makes the stroke bigger. Turn this off with Pressure changes the size, at the bottom of the gallery."

## 12. The Export Presets picture is missing the new ? button
- **Severity:** Low
- **Confidence:** High
- **Page:** `settings.html` line 44, section "Export Presets"
- **The help says:** the picture and its alt text show "Add Preset and Reset to Defaults buttons" (alt matches the picture).
- **The app does:** the tab now ends with a ? button after Reset to Defaults: `Sources/Colorbee/Settings.swift:192`: `HelpButton(anchor: .exportPresets)`. The Shortcuts picture beside it does show its ?.
- **Which is right:** help bug (stale picture; §23, 2026-10-16 added the ? buttons).
- **Suggested fix:** retake `export-presets.png` (`make help-shots`) and add "and ?" to the alt text.

## 13. The Settings… menu description leaves out General
- **Severity:** Low
- **Confidence:** High
- **Page:** `menus.html` line 26, section "Colorbee" (generated)
- **The help says:** "Keyboard shortcuts and export presets."
- **The app does:** Settings also has the General tab (Appearance, Open PDFs at), and it's the first tab (`Sources/Colorbee/Settings.swift:99-101`). The text comes from the menu's tooltip: `Sources/Colorbee/MainMenu.swift:34`: `"showSettings:": "Keyboard shortcuts and export presets."`
- **Which is right:** code bug (the tooltip text; the page is generated from it).
- **Suggested fix:** in `MainMenu.swift:34`: `"Appearance, PDF resolution, keyboard shortcuts and export presets."`, then `make help`.
