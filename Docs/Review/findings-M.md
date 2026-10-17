# Review M: help accuracy, the task guides
Reviewed at commit: 58b4e28a0ca31cd685ac771c36a9f94957fc7047
Checked:
- `index.html`: every guide and reference link resolves. Correct.
- `getting-started.html`: toolbar order and tool names (`DocumentToolbar.swift`), Size and Outline/Fill shown only for tools that use them, palette bar (28 swatches, 4 custom slots, Control-click Remove, swap arrow), number-box dragging (`ScrubArea.swift`), the one-key table against `ShortcutStore.canvasCommands`, undo and selection modifiers, sidebar and status bar, Settings tabs. Findings 1, 2, 3 and 6.
- `redact-a-screenshot.html`: Auto-Redact patterns (`AutoRedact.swift` built-ins), visible-only reading, every-layer apply including hidden layers, one grouped undo across pages, treatments and default, Batch Redact menu names and hardened soft selections (`AutoRedact+Apply.swift:30`, `Editor.swift:2532`), Redact Brush (K, Solid Fill default, Shift axis lock, every layer, on release), Before/After key and default Split layout, the Clipboard History and earlier-versions offers (exact titles and button names), Export as PDF. Every safety claim matches the code. Findings 1, 5 and 9.
- `annotate-an-image.html`: 24 shapes, outline/fill styles, curve and polygon hints, Return/Esc on shapes and badges, Delete on a pending badge, badge styles and Next, text options and Styles menu, Esc places text, Marker, Crop to Selection key, crop presets, Export As, Resize and Skew (1–500%, −89° to 89°, Smooth/Sharp names, Result line), Canvas Properties (top-left, Color 2 or transparent), Copy Text message. Correct.
- `work-with-layers.html`: layer keys and menu items, panel controls (double-click rename, Only the layer below, "Layer below only: none"), Merge Adjustment, Undo on Active Layer, Revert Layer, project saving rule (`Editor.isLayered`). Findings 4, 7 and 9.
- `fix-up-a-photo.html`: Adjust Photo slider and filter names, Levels/Curves/Auto Contrast, Straighten/Perspective/Crop, subject commands and "No subject found", Retouch gallery and options, Clone Stamp (Aligned on, Match Tone, offset from first stroke, Sample All Layers reads active and below), red-eye, Develop window (Highlights −100…0, Reset to Camera, Return opens), camera details fields and Export toggle. Finding 10.
- `pages-and-pdfs.html`: PDF resolutions 150/200/300 (`Settings.swift`), multi-frame open, page sidebar (shows with 2+ pages, ⌥⌘2, context menu, edge scrolling), Page menu and keys, per-page undo, Auto-Redact grouping, the paste-bigger-than-page offer, iPhone import with no document open, PDF page size (144 ppi default). Finding 1.
- `pixel-art.html`: Canvas Properties route, zoom to 3200% (`Viewport.maxZoom = 32`), Pixel Grid at 400% (`Renderer.pixelGridMinimumZoom = 4`), Pencil and Shift axis lock, Eyedropper Option, Fill and Color Eraser tolerances (both start at 0%), Symmetry, Sharp names in Resize and Skew and the palette bar. Finding 8.
- `save-export-and-share.html`: format table against `ImageFileFormat`, project rule, Save panel memory, Export… options and memory, Export As defaults (Slack 760, 1280, 1920, Mobile 750, Square 1024), Print, Duplicate, Revert To (macOS turns Revert To Saved into Revert To because `autosavesInPlace`). Correct.
- Links and anchors: every `page.html#anchor` link resolves. Each of the 8 ? button anchors in `HelpBook.swift` (auto-redact, settings-shortcuts, export-presets, resize-and-skew, canvas-properties, raw-develop, retouch-tools, clone-stamp) appears exactly once in the book.
- Pictures: `auto-redact.png`, `window.png`, `toolbar.png`, `palette-bar.png`, `develop.png` and `export-presets.png` match their alt text and the current UI. `before-after.png` and `layers.png`: finding 9.

## 1. File ▸ Paste into New Image is greyed out when no Colorbee window is open
- **Severity:** High
- **Confidence:** High
- **Page:** `redact-a-screenshot.html` line 23, section "Step by step" (also `pages-and-pdfs.html` line 63, "Make a PDF from screenshots")
- **The help says:** "In Colorbee, choose File ▸ Paste into New Image (⇧⌘V)."
- **The app does:** the action exists only on the document window: `Sources/Colorbee/DocumentWindow.swift:311` `@objc func pasteIntoNewImage(_ sender: Any?)`. Nothing else in the responder chain has it: `AppDelegate.swift` and `DocumentController.swift` don't implement it (`grep pasteIntoNewImage` finds only `MainMenu.swift` and `DocumentWindow.swift`). After the last window is closed (Colorbee keeps running), the menu item has no target, so it's greyed out and ⇧⌘V does nothing. It works only while a document window is open.
- **Which is right:** code bug. FRD §16 (line 647) gives "Paste into New Image (Cmd+Shift+V) for a new document" as the quick route for a screenshot, and AC-25 expects it to open the screenshot. A new document shouldn't need another one open. A tester who closes the last image and takes the next screenshot hits this on step 2.
- **Suggested fix:** handle `pasteIntoNewImage:` at the app level too (for example in `AppDelegate`, or move it there and keep the window's version calling it), with the same `PasteboardImages.hasImage()` check in `validateMenuItem`. Test: close every window, copy a screenshot with ⌃⇧⌘4, press ⇧⌘V; a new window opens.

## 2. Option-dragging inside a selection with Rectangle Select copies the pixels instead of taking part of the selection away
- **Severity:** High
- **Confidence:** High
- **Page:** `getting-started.html` line 70, section "Undo"
- **The help says:** "to take part of one away, Option-click it with the Magic Wand, or hold Option and drag around it with Rectangle Select."
- **The app does:** an Option-drag that starts inside the selection moves a copy of the selected pixels. `Sources/Colorbee/Editor.swift:2141-2146`: `let wandCombining = tool == .magicWand && (modifiers.shift || modifiers.option)` / `if !wandCombining, selectionContains(point), ... { ... selectionDrag = .move(edit: nil, grab: point, origin: origin, smear: modifiers.shift, duplicate: modifiers.option)`. Only the Magic Wand always combines; with Rectangle Select, subtract happens only when the drag starts outside the selection. The part someone wants to take away is inside the selection, so the natural drag starts inside it, and duplicates pixels (a change to the image) instead.
- **Which is right:** help bug. FRD FR-3.3 makes Option-drag inside a selection a duplicate-drag, and §23 (2026-10-01) makes only the wand always select with a modifier.
- **Suggested fix:** "to take part of one away, Option-click it with the Magic Wand, or hold Option and drag with Rectangle Select, starting the drag outside the selection. (Option-dragging from inside a selection moves a copy of it.)"

## 3. The Alpha percentage can't be clicked to type a number
- **Severity:** Medium
- **Confidence:** High
- **Page:** `getting-started.html` line 48, section "The palette bar" (note)
- **The help says:** "You can drag up or down on a number box, such as the size or the Alpha percentage, to change it ... Click it to type a number instead."
- **The app does:** the Alpha percentage is a plain label with dragging, not a text field, and no focus is passed: `Sources/Colorbee/PaletteBar.swift:24-30` `Text("\(Int(alpha.wrappedValue))%") ... .scrubs(alpha, in: 0...100)`. `ScrubArea.swift:7-8`: a click focuses the field to type "On a text field, pass `focus`". Clicking Alpha does nothing. The toolbar Size box is a real field and does take typing (`DocumentToolbar.swift:179`, `passingClicksThrough: true`).
- **Which is right:** help bug (FRD doesn't require typing into Alpha).
- **Suggested fix:** "You can drag up or down on a number box, such as the size or the Alpha percentage, to change it: down makes it bigger. Hold Shift to go faster. You can also click the size box and type a number."

## 4. "Every tool, effect and adjustment works on the active layer only" isn't true for redaction or whole-image commands
- **Severity:** Medium
- **Confidence:** High
- **Page:** `work-with-layers.html` line 36, section "The Layers panel"
- **The help says:** "Click a layer to make it active. Every tool, effect and adjustment works on the active layer only."
- **The app does:** the Redact Brush, Batch Redact and Auto-Redact change every layer with pixels under them (`Sources/Colorbee/Editor.swift:1632` `endRedactStroke` → `redactEveryLayer`, and `AutoRedact+Apply.swift:35` `for layer in layers { Effects.apply(...) }`). Crop, Straighten and Perspective apply to every layer (`Editor.swift:122` `appliesToWholeImage`), as do Rotate, Flip and Resize and Skew with nothing selected (`DocumentWindow.swift:356-361`). The redaction guide says this correctly ("it changes every layer with pixels under the stroke"), so the two pages contradict each other.
- **Which is right:** help bug. FR-9.4, FR-9.6 and §23 (review H, finding 3: redaction on every layer; "whole-image tools apply to every layer, locked or not").
- **Suggested fix:** "Click a layer to make it active. Painting, effects and adjustments work on the active layer. Redaction works on every layer, and Crop, Straighten, Rotate and resizing the whole image change every layer."

## 5. Batch Redact ▸ Blur… and Pixelate… need Apply, which the steps leave out
- **Severity:** Low
- **Confidence:** High
- **Page:** `redact-a-screenshot.html` line 53, section "Anything it missed: Batch Redact"
- **The help says:** "Choose one of the Batch Redact commands in the Redact menu: Blur…, Pixelate… or Solid Fill with Color 1."
- **The app does:** Blur… and Pixelate… open the effect bar with a preview and need Apply (or Return): `Editor.swift:2485-2486` `beginBatchRedact` → `beginEffect(kind, coveringAllLayers: true)`; `DocumentView.swift:403` `Button("Apply") { editor.applyEffect() }`. Only Solid Fill with Color 1 applies at once. Until Apply, the preview looks done, but nothing is committed, and Before/After, Save, Copy and Export are greyed out.
- **Which is right:** help bug (missing step).
- **Suggested fix:** add a step 3: "For Blur… or Pixelate…, set the strength in the bar above the image, then click Apply (or press Return). Solid Fill applies straight away."

## 6. Only Layers has its own toolbar button; the other panels are chosen at the top of the sidebar
- **Severity:** Low
- **Confidence:** High
- **Page:** `getting-started.html` line 75, section "The sidebar and status bar"
- **The help says:** "The sidebar on the right holds the Layers (⌘L), Adjustments, History (⌘Y) and Clipboard History (⌥⌘V) panels. Choose them from the View menu or the buttons at the right of the toolbar."
- **The app does:** the right of the toolbar has a Layers button and a Sidebar button (`DocumentToolbar.swift:79-85`). Adjustments, History and Clipboard History are picked with the switcher at the top of the sidebar (`LayersPanel.swift:13-16`).
- **Which is right:** help bug.
- **Suggested fix:** "Choose them from the View menu or the buttons at the top of the sidebar. The Layers and Sidebar buttons at the right of the toolbar show or hide it."

## 7. A locked layer can still be changed by whole-image commands
- **Severity:** Low
- **Confidence:** High
- **Page:** `work-with-layers.html` line 38, section "The Layers panel"
- **The help says:** "The padlock locks it, so it can't be painted on, moved, changed, merged into or deleted."
- **The app does:** whole-image commands still change a locked layer: `Editor.swift:2490` "Whole-image tools apply to every layer, locked or not (§23)"; `DocumentWindow.swift:356-361` greys out only pixel commands, and Rotate/Flip and Resize and Skew only when there's a selection. So Crop, Straighten, Perspective, Rotate, Flip, Resize and Skew and Canvas Properties change it.
- **Which is right:** help bug (§23 makes this intended).
- **Suggested fix:** "The padlock locks it, so it can't be painted on, moved, merged into or deleted. Commands that change the whole image, such as Crop, Rotate and Resize, still change it. A locked layer can still be hidden and reordered."

## 8. Export As never enlarges, so its automatic sharp scaling doesn't help pixel art
- **Severity:** Low
- **Confidence:** High
- **Page:** `pixel-art.html` line 54, section "Resize without blurring"
- **The help says:** "File ▸ Export As picks sharp scaling for small, pixel-art-sized images on its own."
- **The app does:** sharp scaling is picked for images up to 256 × 256 (`ExportPreset.swift:40-41` `size.width <= 256 && size.height <= 256 ? .nearestNeighbor : .smooth`). But presets never enlarge (`ExportPreset.swift:26` "Images are never enlarged"), and every default preset is 750 px or wider (`ExportPreset.swift:18-24`). A 32 × 32 drawing exported with any default preset comes out 32 × 32, unscaled. Under a heading about resizing, this reads as a way to get a bigger copy, which it isn't.
- **Which is right:** help bug (the code matches §23 on never enlarging).
- **Suggested fix:** replace the bullet with: "File ▸ Export As never makes an image bigger, so to share pixel art larger, use Resize and Skew with Sharp (pixel art) first, then export."

## 9. Two pictures show the old palette bar, and Before/After's divider hides the "before" side
- **Severity:** Low
- **Confidence:** High
- **Page:** `redact-a-screenshot.html` line 71, section "Check it with Before/After" (`before-after.png`); `work-with-layers.html` line 31, section "The Layers panel" (`layers.png`)
- **The help says:** before-after alt: "the original screenshot on the left of the divider, and the email, phone number and API key covered with black boxes on the right." Caption: "As Opened on the left, your redacted image on the right."
- **The app does:** both pictures predate 2026-10-15. They show 12 custom-color slots (now 4, `CustomColors.swift:10` `static let slotCount = 4`). `before-after.png` also has the older toolbar without Retouch, Redact Brush and Step Badge. In `before-after.png` the divider sits at the far left of the image, so the "As Opened" side shows none of the email, phone or key. A tester comparing with the picture can't see what the original side should look like.
- **Which is right:** help bug (pictures out of date).
- **Suggested fix:** retake both with the current UI (`HelpShots.swift`). Put the Before/After divider through the middle of the email, phone and key, so the unredacted text shows on the left.

## 10. Remove and Spot Heal have no Strength or Hardness; the Clone Stamp has no Strength
- **Severity:** Low
- **Confidence:** High
- **Page:** `fix-up-a-photo.html` line 71, section "Retouch: remove things and touch up spots"
- **The help says:** "Strength and Hardness are in the palette bar."
- **The app does:** `RetouchKind.swift:58,61` `fillsArea` is Remove and Spot Heal; `hasStrength: Bool { !fillsArea && self != .cloneStamp }`. `DocumentView.swift:246,253` shows Strength only `if kind.hasStrength` and Hardness only `if !kind.fillsArea`.
- **Which is right:** help bug.
- **Suggested fix:** "**Strength** (the brushes and Smudge) and **Hardness** (all but Remove and Spot Heal) are in the palette bar."
